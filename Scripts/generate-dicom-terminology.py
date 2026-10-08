#!/usr/bin/env python3
"""Generate DcmSwift's terminology resource from DICOM PS3.16 DocBook XML.

  generate-dicom-terminology.py part16.xml dicom-terminology-2026d.json

The resource holds the Coding Schemes of Table 8-1, the DICOM Controlled
Terminology of Table D-1 (scheme DCM), and every Context Group (Annex B):
its keyword, extensibility, version, UID, codes (scheme, value, meaning, and
the Coding Scheme Version when the table gives one), and included groups.
Tables are read as laid out, with cells spanning rows and columns.
"""

from __future__ import annotations

import argparse
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

DB = "{http://docbook.org/ns/docbook}"
XML_ID = "{http://www.w3.org/XML/1998/namespace}id"
INVISIBLE = dict.fromkeys(map(ord, "​‌‍⁠﻿"), None)
CID_SECTION = re.compile(r"^sect_CID_(\d+)$")


def text(element: ET.Element) -> str:
    return re.sub(r"\s+", " ", "".join(element.itertext()).translate(INVISIBLE)).strip()


def rows(table: ET.Element) -> tuple[list[str], list[tuple[ET.Element, list[str]]]]:
    """The header cells, and each body row with its cells laid out on the
    table's columns: a cell spanning several rows or columns fills each of
    them, as in an HTML table."""
    header: list[str] = []
    head = table.find(f".//{DB}thead")
    if head is not None:
        first = head.find(f"{DB}tr")
        if first is not None:
            header = [text(cell) for cell in first if cell.tag in (f"{DB}th", f"{DB}td")]
    body = table.find(f".//{DB}tbody")
    laid_out: list[tuple[ET.Element, list[str]]] = []
    pending: dict[int, tuple[str, int]] = {}  # column -> (text, rows still covered)
    for row in ([] if body is None else body.iter(f"{DB}tr")):
        cells: list[str] = []
        column_index = 0

        def fill_pending():
            nonlocal column_index
            while column_index in pending:
                value, remaining = pending[column_index]
                cells.append(value)
                if remaining <= 1:
                    del pending[column_index]
                else:
                    pending[column_index] = (value, remaining - 1)
                column_index += 1

        for cell in row:
            if cell.tag not in (f"{DB}td", f"{DB}th"):
                continue
            fill_pending()
            value = text(cell)
            span = int(cell.get("colspan", "1") or 1)
            down = int(cell.get("rowspan", "1") or 1)
            for _ in range(span):
                cells.append(value)
                if down > 1:
                    pending[column_index] = (value, down - 1)
                column_index += 1
        fill_pending()
        laid_out.append((row, cells))
    return header, laid_out


def column(header: list[str], name: str) -> int | None:
    for index, title in enumerate(header):
        if title.startswith(name):
            return index
    return None


def coding_schemes(root: ET.Element) -> list[dict[str, str]]:
    table = next(t for t in root.iter(f"{DB}table") if t.get(XML_ID) == "table_8-1")
    header, body = rows(table)
    designator, uid, name, organization = (column(header, key) for key in (
        "Coding Scheme Designator", "Coding Scheme UID", "Coding Scheme Name", "Coding Scheme Responsible Organization"))
    schemes = []
    for _, cells in body:
        if designator is None or len(cells) <= designator or not cells[designator]:
            continue
        entry = {"designator": cells[designator]}
        for key, index in (("uid", uid), ("name", name), ("organization", organization)):
            if index is not None and index < len(cells) and cells[index]:
                entry[key] = re.sub(r"\s", "", cells[index]) if key == "uid" else cells[index]
        schemes.append(entry)
    return schemes


def dicom_codes(root: ET.Element) -> list[list[object]]:
    table = next(t for t in root.iter(f"{DB}table") if t.get(XML_ID) == "table_D-1")
    header, body = rows(table)
    value, meaning, notes = column(header, "Code Value"), column(header, "Code Meaning"), column(header, "Notes")
    codes = []
    for _, cells in body:
        if value is None or len(cells) <= max(value, meaning or 0) or not cells[value]:
            continue
        retired = notes is not None and notes < len(cells) and cells[notes].startswith("Retired")
        codes.append([cells[value], cells[meaning]] + ([1] if retired else []))
    return codes


def context_groups(root: ET.Element) -> list[dict[str, object]]:
    groups = []
    for section in root.iter(f"{DB}section"):
        match = CID_SECTION.match(section.get(XML_ID) or "")
        if not match:
            continue
        title = section.find(f"{DB}title")
        group: dict[str, object] = {"cid": int(match.group(1)), "name": text(title) if title is not None else ""}
        # The metadata list: Keyword, Type, Version, UID.
        metadata = section.find(f"{DB}variablelist")
        if metadata is not None:
            for entry in metadata.iter(f"{DB}varlistentry"):
                term, item = entry.find(f"{DB}term"), entry.find(f"{DB}listitem")
                if term is None or item is None:
                    continue
                key = {"Keyword:": "keyword", "Type:": "type", "Version:": "version", "UID:": "uid"}.get(text(term))
                if key == "type":
                    group["extensible"] = text(item).lower() == "extensible"
                elif key:
                    group[key] = re.sub(r"\s", "", text(item)) if key == "uid" else text(item)
        codes: list[list[str]] = []
        includes: list[int] = []
        for table in section.iter(f"{DB}table"):
            header, body = rows(table)
            scheme, value, meaning = (column(header, key) for key in ("Coding Scheme Designator", "Code Value", "Code Meaning"))
            scheme_version = column(header, "Coding Scheme Version")
            for row, cells in body:
                links = [CID_SECTION.match(x.get("linkend") or "") for x in row.iter(f"{DB}xref")]
                own = [cell for cell in row if cell.tag in (f"{DB}td", f"{DB}th")]
                # "Include CID n" spans the code columns; other cells, such as
                # notes, stay empty.
                if own and text(own[0]).startswith("Include") and not any(text(cell) for cell in own[1:]):
                    includes += [int(link.group(1)) for link in links if link]
                    continue
                if None in (scheme, value, meaning) or len(cells) <= max(scheme, value, meaning):
                    continue
                if cells[value]:
                    code = [cells[scheme], cells[value], cells[meaning]]
                    # Coding Scheme Version (0008,0103), required by some schemes.
                    if scheme_version is not None and scheme_version < len(cells) and cells[scheme_version]:
                        code.append(cells[scheme_version])
                    codes.append(code)
        group["codes"] = codes
        if includes:
            group["includes"] = includes
        if not codes and not includes:
            # Groups defined by a rule, such as all LOINC document names.
            definition = section.find(f"{DB}para")
            if definition is not None:
                group["definition"] = text(definition)
        groups.append(group)
    return sorted(groups, key=lambda group: group["cid"])


def generate(source: Path) -> dict[str, object]:
    root = ET.parse(source).getroot()
    return {
        "edition": "2026d",
        "codingSchemes": coding_schemes(root),
        "dicomCodes": dicom_codes(root),
        "contextGroups": context_groups(root),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Path to part16.xml")
    parser.add_argument("output", type=Path, help="Destination JSON file")
    parser.add_argument("--check", action="store_true", help="Fail if the output differs instead of writing it")
    arguments = parser.parse_args()
    encoded = json.dumps(generate(arguments.source), ensure_ascii=False, separators=(",", ":")) + "\n"
    if arguments.check:
        if arguments.output.read_text(encoding="utf-8") != encoded:
            raise SystemExit(f"{arguments.output} is not up to date")
        return
    arguments.output.write_text(encoded, encoding="utf-8")


if __name__ == "__main__":
    main()
