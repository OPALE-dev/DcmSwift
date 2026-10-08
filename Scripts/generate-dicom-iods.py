#!/usr/bin/env python3
"""Generate DcmSwift's IOD and module resource from DICOM PS3.3 and PS3.4 DocBook XML.

  generate-dicom-iods.py part03.xml part04.xml dicom-iods-2026d.json [--check]

The resource holds:
- every attribute table of PS3.3 (modules and macros), keyed by table id:
  attributes with their tag, nesting depth, Type, Enumerated Values, and the
  condition sentence of Types 1C and 2C, and the tables they include;
- every IOD module table: the modules of the IOD with their usage (M, C, U)
  and the condition of conditional modules, and the Functional Group Macros of
  enhanced multi-frame IODs;
- the IOD of each SOP Class, from the "IOD Specification" columns of PS3.4.
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
TAG = re.compile(r"^\(([0-9A-Fa-fx]{4}),([0-9A-Fa-fx]{4})\)$")


def text(element: ET.Element | None) -> str:
    if element is None:
        return ""
    return re.sub(r"\s+", " ", "".join(element.itertext()).translate(INVISIBLE)).strip()


def cells_of(row: ET.Element) -> list[ET.Element]:
    return [cell for cell in row if cell.tag in (f"{DB}td", f"{DB}th")]


def header_of(table: ET.Element) -> list[str]:
    head = table.find(f".//{DB}thead")
    first = head.find(f"{DB}tr") if head is not None else None
    return [text(cell) for cell in cells_of(first)] if first is not None else []


def laid_out(table: ET.Element) -> list[tuple[ET.Element, list[ET.Element | None]]]:
    """Body rows with one cell per column; a cell spanning rows or columns
    fills each of them, as in an HTML table."""
    body = table.find(f".//{DB}tbody")
    result: list[tuple[ET.Element, list[ET.Element | None]]] = []
    pending: dict[int, tuple[ET.Element, int]] = {}
    for row in ([] if body is None else body.iter(f"{DB}tr")):
        cells: list[ET.Element | None] = []
        index = 0

        def fill() -> None:
            nonlocal index
            while index in pending:
                cell, remaining = pending[index]
                cells.append(cell)
                if remaining <= 1:
                    del pending[index]
                else:
                    pending[index] = (cell, remaining - 1)
                index += 1

        for cell in cells_of(row):
            fill()
            span, down = int(cell.get("colspan", "1") or 1), int(cell.get("rowspan", "1") or 1)
            for _ in range(span):
                cells.append(cell)
                if down > 1:
                    pending[index] = (cell, down - 1)
                index += 1
        fill()
        result.append((row, cells))
    return result


def column(header: list[str], name: str) -> int | None:
    return next((index for index, title in enumerate(header) if title.startswith(name)), None)


def links(element: ET.Element | None) -> list[str]:
    if element is None:
        return []
    return [node.get("linkend") or node.get("targetptr") or ""
            for node in element.iter() if node.tag in (f"{DB}xref", f"{DB}olink")]


def enumerated_values(cell: ET.Element) -> list[str] | None:
    """The terms of an "Enumerated Values:" list in a description."""
    for variablelist in cell.iter(f"{DB}variablelist"):
        if text(variablelist.find(f"{DB}title")).startswith("Enumerated Values"):
            return [text(entry.find(f"{DB}term")) for entry in variablelist.iter(f"{DB}varlistentry")]
    return None


def condition(description: str) -> str | None:
    """The sentence of a conditional Type: from "Required if" or "Shall be
    present if" to the end of that sentence."""
    match = re.search(r"((?:Required|Shall be present|Required only) (?:if|when)[^.]*(?:\.\d[^.]*)*\.)", description)
    return match.group(1) if match else None


def include_condition(cell: ET.Element) -> str | None:
    """The text after the included table's reference, when it states a
    condition."""
    parts: list[str] = []
    seen = False
    for node in cell.iter():
        if node.tag == f"{DB}xref" and (node.get("linkend") or "").startswith("table_") and not seen:
            seen = True
            parts.append(node.tail or "")
            continue
        if seen and node.tag != f"{DB}xref":
            parts.append((node.text or "") + (node.tail or ""))
        elif seen:
            parts.append(node.get("linkend", "") + (node.tail or ""))
    rest = re.sub(r"\s+", " ", "".join(parts).translate(INVISIBLE)).strip(" .")
    return rest if re.match(r"(?i)^(if|when|only if|unless)\b", rest) else None


def attribute_tables(root: ET.Element) -> dict[str, dict[str, object]]:
    tables: dict[str, dict[str, object]] = {}
    for table in root.iter(f"{DB}table"):
        header = header_of(table)
        name, tag, kind = column(header, "Attribute Name"), column(header, "Tag"), column(header, "Type")
        if None in (name, tag, kind):
            continue
        description = column(header, "Attribute Description")
        entries: list[dict[str, object]] = []
        for row, cells in laid_out(table):
            own = cells_of(row)
            first = text(own[0]) if own else ""
            depth = len(first) - len(first.lstrip(">"))
            # The nesting marks may fill a cell of their own before "Include".
            if first and not first.strip(">").strip() and len(own) > 1 and text(own[1]).startswith("Include"):
                own = own[1:]
                first = ">" * depth + text(own[0])
            if first.lstrip(">").lstrip().startswith("Include"):
                targets = [link for link in links(own[0]) if link.startswith("table_")]
                if targets:
                    entry: dict[str, object] = {"include": targets[0][len("table_"):], "depth": depth}
                    # An inclusion may be conditional, as "Include Table
                    # C.18.1-1 if and only if Value Type (0040,A040) is NUM".
                    rest = include_condition(own[0])
                    if rest:
                        entry["condition"] = rest
                    cids = [int(link[len("sect_CID_"):]) for cell in own[1:] for link in links(cell)
                            if link.startswith("sect_CID_")]
                    if cids:
                        entry["cid"] = cids[0]
                    entries.append(entry)
                continue
            if len(cells) <= max(name, tag, kind) or cells[tag] is None:
                continue
            match = TAG.match(text(cells[tag]).replace(" ", ""))
            if not match:
                continue
            attribute: dict[str, object] = {
                "tag": (match.group(1) + match.group(2)).upper(),
                "depth": depth,
                "type": text(cells[kind]),
            }
            if description is not None and description < len(cells) and cells[description] is not None:
                values = enumerated_values(cells[description])
                if values:
                    attribute["enumerated"] = values
                if str(attribute["type"]).endswith("C"):
                    sentence = condition(text(cells[description]))
                    if sentence:
                        attribute["condition"] = sentence
            entries.append(attribute)
        caption = table.find(f"{DB}caption")
        tables[(table.get(XML_ID) or "")[len("table_"):]] = {"name": text(caption), "entries": entries}
    return tables


def section_tables(root: ET.Element) -> dict[str, str]:
    """The first attribute table of each section, so that an IOD's module
    reference, a section, leads to the module's table."""
    result: dict[str, str] = {}
    for section in root.iter(f"{DB}section"):
        identifier = section.get(XML_ID) or ""
        for table in section.iter(f"{DB}table"):
            header = header_of(table)
            if column(header, "Attribute Name") is not None and column(header, "Tag") is not None:
                result[identifier[len("sect_"):]] = (table.get(XML_ID) or "")[len("table_"):]
                break
    return result


def iod_tables(root: ET.Element, sections: dict[str, str]) -> dict[str, dict[str, object]]:
    """IOD module tables and Functional Group Macro tables, keyed by the
    section that contains them directly."""
    parents = {child: parent for parent in root.iter() for child in parent}

    def owner(table: ET.Element) -> ET.Element | None:
        node = parents.get(table)
        while node is not None and node.tag != f"{DB}section":
            node = parents.get(node)
        return node

    iods: dict[str, dict[str, object]] = {}
    for table in root.iter(f"{DB}table"):
        section = owner(table)
        identifier = (section.get(XML_ID) or "")[len("sect_"):] if section is not None else ""
        if not identifier.startswith(("A.", "F.")):
            continue
        header = header_of(table)
        module, usage, reference = column(header, "Module"), column(header, "Usage"), column(header, "Reference")
        group_macro = column(header, "Functional Group Macro")
        entries = []
        for row, cells in laid_out(table):
            if usage is None or len(cells) <= usage:
                continue
            target_column = column(header, "Section") if group_macro is not None else reference
            if target_column is None or target_column >= len(cells):
                continue
            targets = [l for l in links(cells[target_column]) if l.startswith("sect_")]
            use = text(cells[usage])
            if not targets:
                continue
            entry = {"table": sections.get(targets[0][len("sect_"):]), "usage": use[:1]}
            if group_macro is None:
                entry = {"name": text(cells[module]) if module is not None else "", **entry}
            else:
                entry = {"name": text(cells[group_macro]), **entry}
            if use.startswith("C"):
                entry["condition"] = use.split("-", 1)[-1].strip()
            entries.append(entry)
        if not entries:
            continue
        iod = iods.setdefault(identifier, {"name": text(section.find(f"{DB}title")), "modules": []})
        if group_macro is not None and usage is not None:
            iod["functionalGroups"] = entries
        elif module is not None and reference is not None and header[0:1] == ["IE"]:
            iod["modules"] = entries
    return iods


def sop_classes(root: ET.Element) -> dict[str, str]:
    result: dict[str, str] = {}
    for table in root.iter(f"{DB}table"):
        header = header_of(table)
        uid, specification = column(header, "SOP Class UID"), column(header, "IOD Specification")
        if uid is None or specification is None:
            continue
        for row, cells in laid_out(table):
            if len(cells) <= max(uid, specification) or cells[uid] is None:
                continue
            value = re.sub(r"\s", "", text(cells[uid]))
            targets = [l for l in links(cells[specification]) if l.startswith("sect_")]
            if re.match(r"^[0-9.]+$", value) and targets:
                result[value] = targets[0][len("sect_"):]
    return result


def generate(part03: Path, part04: Path) -> dict[str, object]:
    root3 = ET.parse(part03).getroot()
    sections = section_tables(root3)
    iods = iod_tables(root3, sections)
    sops = sop_classes(ET.parse(part04).getroot())
    # Functional Group Macro tables sit near the module table, such as
    # A.38.1.4 beside A.38.1.3, or A.52.4.3 for A.52.3: they join the only
    # IOD module table under their closest common ancestor section.
    for key, iod in list(iods.items()):
        if iod["modules"] or "functionalGroups" not in iod:
            continue
        ancestor = key
        while "." in ancestor[2:]:
            ancestor = ancestor.rsplit(".", 1)[0]
            owners = [other for other in iods if other.startswith(ancestor + ".") and iods[other]["modules"]]
            if len(owners) == 1:
                iods[owners[0]]["functionalGroups"] = iod["functionalGroups"]
                break
            if owners:
                break
    # A SOP Class references the IOD section; its module table may be in a
    # subsection, such as A.3 and A.3.3.
    resolved: dict[str, str] = {}
    for uid, section in sops.items():
        candidates = sorted(key for key in iods if (key == section or key.startswith(section + ".")) and iods[key]["modules"])
        if candidates:
            resolved[uid] = candidates[0]
    return {
        "edition": "2026d",
        "sopClasses": dict(sorted(resolved.items())),
        "iods": dict(sorted((key, value) for key, value in iods.items() if value["modules"])),
        "tables": dict(sorted(attribute_tables(root3).items())),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("part03", type=Path)
    parser.add_argument("part04", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check", action="store_true", help="Fail if the output differs instead of writing it")
    arguments = parser.parse_args()
    encoded = json.dumps(generate(arguments.part03, arguments.part04), ensure_ascii=False, separators=(",", ":")) + "\n"
    if arguments.check:
        if arguments.output.read_text(encoding="utf-8") != encoded:
            raise SystemExit(f"{arguments.output} is not up to date")
        return
    arguments.output.write_text(encoded, encoding="utf-8")


if __name__ == "__main__":
    main()
