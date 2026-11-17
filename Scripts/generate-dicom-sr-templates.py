#!/usr/bin/env python3
"""Generate DcmSwift's SR template resource from DICOM PS3.16 DocBook XML.

  generate-dicom-sr-templates.py part16.xml dicom-sr-templates-2026d.json [--check]

For every template of Annex A (sections sect_TID_*), the resource holds its
number, name, Type (extensible or not), Order (significant or not), Root,
parameters, and the rows of its table: nesting level, relationship with the
parent, value type, concept name, value multiplicity, requirement type,
condition (as text) and value set constraint. Cells are parsed into
structured forms:

  concept   {"code": [value, scheme, meaning], "defined": bool}   EV / DT
            {"group": cid, "baseline": bool}                       BCID / DCID
            {"groups": [cid, ...], "baseline": bool}               alternatives
            {"include": tid}                                       DTID (INCLUDE rows)
            {"parameter": name}                                    $Name
  values    the same forms for a CODE value, plus "units" for NUM rows,
            and "arguments" {name: form} for INCLUDE rows.

Free text the standard writes in these cells (explanations, conditions that
cannot be expressed) is kept under "note" and not interpreted. Cross
references are read as "CID n" and "TID n", which DocBook leaves empty.
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
TEMPLATE = re.compile(r"^sect_TID_(\w+)$")
CODE = r'\(\s*([^,()]+?)\s*,\s*([^,()]+?)\s*,\s*"([^"]*)"\s*\)'


def text(element: ET.Element) -> str:
    """Text of an element; cross references to Context Groups and Templates
    become "CID n" and "TID n"."""
    parts: list[str] = []

    def walk(node: ET.Element) -> None:
        if node.text:
            parts.append(node.text)
        for child in node:
            if child.tag == f"{DB}xref":
                match = re.match(r"sect_(CID|TID)_(\w+)$", child.get("linkend", ""))
                parts.append(f" {match.group(1)} {match.group(2)} " if match else "")
            else:
                walk(child)
            if child.tail:
                parts.append(child.tail)

    walk(element)
    return re.sub(r"\s+", " ", "".join(parts).translate(INVISIBLE)).strip()


def laid_out(table: ET.Element) -> tuple[list[str], list[list[str]]]:
    """Header and body cells, with cells spanning rows or columns repeated."""
    head = table.find(f".//{DB}thead/{DB}tr")
    header = [] if head is None else [text(cell) for cell in head]
    body: list[list[str]] = []
    pending: dict[int, tuple[str, int]] = {}
    for row in table.iter(f"{DB}tr"):
        if head is not None and row is head:
            continue
        cells: list[str] = []
        column = 0

        def fill() -> None:
            nonlocal column
            while column in pending:
                value, remaining = pending[column]
                cells.append(value)
                if remaining <= 1:
                    del pending[column]
                else:
                    pending[column] = (value, remaining - 1)
                column += 1

        for cell in row:
            if cell.tag not in (f"{DB}td", f"{DB}th"):
                continue
            fill()
            value = text(cell)
            span = int(cell.get("colspan", "1") or 1)
            down = int(cell.get("rowspan", "1") or 1)
            for _ in range(span):
                cells.append(value)
                if down > 1:
                    pending[column] = (value, down - 1)
                column += 1
        fill()
        body.append(cells)
    return header, body


def normal(cell: str) -> str:
    """"B CID 7000" and "D TID 1204", as cross references read, become
    "BCID 7000" and "DTID 1204"."""
    return re.sub(r"\b([BD])\s+(CID|TID)\b", r"\1\2", cell).strip()


def form(cell: str) -> dict | None:
    """A concept or value constraint: code, group, template or parameter."""
    cell = normal(cell)
    if not cell:
        return None
    match = re.match(r"^(EV|DT)\s*" + CODE, cell)
    if match:
        return {"code": [match.group(2), match.group(3), match.group(4)], "defined": match.group(1) == "DT"}
    groups = re.findall(r"\b([BD])CID\s+(\d+)", cell)
    if len(groups) > 1 and re.fullmatch(r"(?:[BD]CID\s+\d+(?:\s+or)?\s*)+", cell):
        # Alternatives: a code of any of these groups.
        return {"groups": [int(number) for _, number in groups], "baseline": all(kind == "B" for kind, _ in groups)}
    match = re.match(r"^([BD])CID\s+(\d+)", cell)
    if match:
        return {"group": int(match.group(2)), "baseline": match.group(1) == "B"}
    match = re.match(r"^DTID\s+(\w+)", cell)
    if match:
        return {"include": match.group(1)}
    match = re.match(r"^\$(\w+)", cell)
    if match:
        return {"parameter": match.group(1)}
    return None


ASSIGNMENT = re.compile(r"\$(\w+)\s*=\s*")


def arguments(cell: str) -> dict[str, dict]:
    """Parameters an INCLUDE row passes: "$Name = constraint" pairs."""
    found: dict[str, dict] = {}
    marks = list(ASSIGNMENT.finditer(cell))
    for index, mark in enumerate(marks):
        end = marks[index + 1].start() if index + 1 < len(marks) else len(cell)
        value = form(normal(cell[mark.end():end]))
        if value is not None:
            found[mark.group(1)] = value
    return found


ROW = r"\d+[a-z]?\d*"


def condition(cell: str) -> dict | None:
    """Conditions on the presence of other rows of the template, the only
    ones evaluated: XOR, at least one of, required if absent, present iff."""
    cell = cell.strip().rstrip(".")
    rows = lambda part: re.findall(rf"\b({ROW})\b", part)
    match = re.match(rf"^XOR (?:with )?Rows? ((?:{ROW})(?:\s*(?:,|and|or)\s*{ROW})*)$", cell)
    if match:
        return {"xor": rows(match.group(1))}
    match = re.match(rf"^At least one of Rows ((?:{ROW})(?:\s*(?:,|and|or)\s*{ROW})*) (?:shall|must) be present$", cell)
    if match:
        return {"atLeastOne": rows(match.group(1))}
    match = re.match(rf"^IF Rows? ((?:{ROW})(?:\s*(?:,|and|or)\s*(?:Row\s+)?{ROW})*) (?:are|is) (?:absent|not present)$", cell) \
        or re.match(rf"^IF Row ({ROW}) not present$", cell)
    if match:
        return {"ifAbsent": rows(match.group(1))}
    match = re.match(rf"^IFF Row ({ROW}) is present$", cell)
    if match:
        return {"iffPresent": rows(match.group(1))}
    return None


def multiplicity(cell: str) -> list:
    match = re.match(r"^(\d+)\s*(?:-\s*(\d+|n))?$", cell.strip())
    if not match:
        return [1, None]
    low = int(match.group(1))
    high = match.group(2)
    return [low, None if high == "n" else int(high) if high else low]


def values(value_type: str, cell: str) -> dict:
    """The value set constraint of a row, by value type."""
    result: dict = {}
    if value_type == "INCLUDE":
        found = arguments(cell)
        if found:
            result["arguments"] = found
        return result
    cell = normal(cell)
    units = re.search(r"UNITS?\s*=\s*(.*)$", cell, re.IGNORECASE)
    if units:
        value = form(units.group(1))
        if value is not None:
            result["units"] = value
        return result
    value = form(cell)
    if value is not None and "include" not in value:
        result["value"] = value
    elif cell:
        result["note"] = cell
    return result


def properties(section: ET.Element) -> dict:
    """Type, Order and Root of the variable list before the table."""
    found: dict = {}
    for entry in section.iter(f"{DB}varlistentry"):
        if len(found) == 3:
            break
        term = entry.find(f"{DB}term")
        item = entry.find(f"{DB}listitem")
        if term is None or item is None:
            continue
        found.setdefault(text(term).rstrip(":").strip().lower(), text(item))
    return found


def template(section: ET.Element, number: str) -> dict | None:
    tables = [table for table in section.iter(f"{DB}table") if table.get(XML_ID) == f"table_TID_{number}"]
    if not tables:
        return None
    title = section.find(f"{DB}title")
    header, body = laid_out(tables[0])
    columns = {name: index for index, name in enumerate(header)}
    if "VT" not in columns or "Concept Name" not in columns:
        return None
    described = properties(section)
    parameters = []
    for table in section.iter(f"{DB}table"):
        if (table.get(XML_ID) or "").startswith(f"table_TID_{number}_Parameters"):
            parameters = [cells[0].lstrip("$") for cells in laid_out(table)[1] if cells and cells[0].startswith("$")]
    rows = []
    for cells in body:
        def cell(name: str) -> str:
            index = columns.get(name)
            return cells[index].strip() if index is not None and index < len(cells) else ""

        value_type = cell("VT").upper()
        if not value_type:
            continue
        row: dict = {
            "row": cells[0].strip() if cells else "",
            "depth": cell("NL").count(">"),
            "valueTypes": [{"NUMERIC": "NUM"}.get(part.strip(), part.strip())
                           for part in re.split(r"\s+OR\s+|/|,", value_type) if part.strip()],
            "multiplicity": multiplicity(cell("VM")),
            "requirement": cell("Req Type") or "U",
        }
        if cell("Rel with Parent"):
            row["relationship"] = cell("Rel with Parent").upper()
        concept = form(cell("Concept Name"))
        if concept is not None:
            row["concept"] = concept
        if cell("Condition"):
            row["condition"] = cell("Condition")
            parsed = condition(cell("Condition"))
            if parsed is not None:
                row["presence"] = parsed
        row.update(values(row["valueTypes"][0], cell("Value Set Constraint")))
        rows.append(row)
    kind = described.get("type", "")
    return {
        "identifier": number,
        "name": text(title) if title is not None else "",
        "extensible": not kind.lower().startswith("non"),
        "orderSignificant": described.get("order", "").lower().startswith("significant"),
        "root": described.get("root", "").lower().startswith("yes"),
        "parameters": parameters,
        "rows": rows,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Path to part16.xml")
    parser.add_argument("output", type=Path, help="Destination JSON file")
    parser.add_argument("--check", action="store_true", help="Fail if the output differs instead of writing it")
    arguments_ = parser.parse_args()
    root = ET.parse(arguments_.source).getroot()
    edition = re.search(r"DICOM PS3\.16 (\d{4}[a-e])", text(root))
    templates = []
    for section in root.iter(f"{DB}section"):
        match = TEMPLATE.match(section.get(XML_ID, ""))
        if match:
            found = template(section, match.group(1))
            if found is not None:
                templates.append(found)
    templates.sort(key=lambda t: (int(re.sub(r"\D", "", t["identifier"]) or 0), t["identifier"]))
    document = {"edition": edition.group(1) if edition else "", "templates": templates}
    output = json.dumps(document, ensure_ascii=False, separators=(",", ":"), sort_keys=False) + "\n"
    if arguments_.check:
        if arguments_.output.read_text(encoding="utf-8") != output:
            raise SystemExit(f"{arguments_.output} differs from {arguments_.source}")
        return
    arguments_.output.write_text(output, encoding="utf-8")
    print(f"{len(templates)} templates, {sum(len(t['rows']) for t in templates)} rows, edition {document['edition']}")


if __name__ == "__main__":
    main()
