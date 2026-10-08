#!/usr/bin/env python3
"""Generate DcmSwift's de-identification resource from DICOM PS3.15 DocBook XML.

  generate-dicom-deidentification.py part15.xml dicom-deidentification-2026d.json [--check]

The resource holds:
- the attributes of Table E.1-1, Application Level Confidentiality Profile
  Attributes: tag (with "X" for repeating groups such as 50xx, and
  "private" for the row of all private attributes), name,
  whether retired, the action of the Basic Profile, and the action of each
  option that changes it;
- the safe private attributes of Table E.3.10-1: tag (with "XX" for the
  private block), Private Creator, and VR.
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
ACTIONS = {"D", "Z", "X", "K", "C", "U", "Z/D", "X/Z", "X/D", "X/Z/D", "X/Z/U*"}
# The option columns of Table E.1-1, by the keys of the resource.
OPTIONS = [
    ("Rtn. Safe Priv. Opt.", "retainSafePrivate"),
    ("Rtn. UIDs Opt.", "retainUIDs"),
    ("Rtn. Dev. Id. Opt.", "retainDeviceIdentity"),
    ("Rtn. Inst. Id. Opt.", "retainInstitutionIdentity"),
    ("Rtn. Pat. Chars. Opt.", "retainPatientCharacteristics"),
    ("Rtn. Long. Full Dates Opt.", "retainLongitudinalFullDates"),
    ("Rtn. Long. Modif. Dates Opt.", "retainLongitudinalModifiedDates"),
    ("Clean Desc. Opt.", "cleanDescriptors"),
    ("Clean Struct. Cont. Opt.", "cleanStructuredContent"),
    ("Clean Graph. Opt.", "cleanGraphics"),
]


def text(element: ET.Element | None) -> str:
    if element is None:
        return ""
    return re.sub(r"\s+", " ", "".join(element.itertext()).translate(INVISIBLE)).strip()


def cells_of(row: ET.Element) -> list[ET.Element]:
    return [cell for cell in row if cell.tag in (f"{DB}td", f"{DB}th")]


def laid_out(table: ET.Element, part: str) -> list[list[ET.Element | None]]:
    """The rows of the table head or body with one cell per column; a cell
    spanning rows or columns fills each of them."""
    section = table.find(f".//{DB}{part}")
    result: list[list[ET.Element | None]] = []
    pending: dict[int, tuple[ET.Element, int]] = {}
    for row in ([] if section is None else section.iter(f"{DB}tr")):
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
        result.append(cells)
    return result


def table(root: ET.Element, identifier: str) -> ET.Element:
    for candidate in root.iter(f"{DB}table"):
        if candidate.get(XML_ID) == identifier:
            return candidate
    raise SystemExit(f"{identifier} not found")


def tag_of(value: str) -> str | None:
    match = TAG.match(value.replace(" ", ""))
    return (match.group(1) + match.group(2)).upper() if match else None


def profile_attributes(root: ET.Element) -> list[dict[str, object]]:
    profile = table(root, "table_E.1-1")
    header = [text(cell) for cell in laid_out(profile, "thead")[0]]

    def column(title: str) -> int:
        return next(index for index, name in enumerate(header) if name.startswith(title))

    name, tag, retired, basic = column("Attribute Name"), column("Tag"), column("Retd."), column("Basic Prof.")
    options = [(column(title), key) for title, key in OPTIONS]
    attributes = []
    for cells in laid_out(profile, "tbody"):
        value = tag_of(text(cells[tag]))
        if value is None and "gggg is odd" in text(cells[tag]):
            # The row of every private attribute.
            value = "private"
        if value is None:
            raise SystemExit(f"unexpected tag {text(cells[tag])!r} in Table E.1-1")
        action = text(cells[basic])
        if action not in ACTIONS:
            raise SystemExit(f"unexpected Basic Profile action {action!r} for {value}")
        entry: dict[str, object] = {"tag": value, "name": text(cells[name]), "basic": action}
        if text(cells[retired]) == "Y":
            entry["retired"] = True
        changes = {}
        for index, key in options:
            option = text(cells[index]) if index < len(cells) else ""
            if option:
                if option not in ACTIONS:
                    raise SystemExit(f"unexpected {key} action {option!r} for {value}")
                changes[key] = option
        if changes:
            entry["options"] = changes
        attributes.append(entry)
    return attributes


def safe_private_attributes(root: ET.Element) -> list[dict[str, str]]:
    safe = table(root, "table_E.3.10-1")
    header = [text(cell) for cell in laid_out(safe, "thead")[0]]
    element, creator, vr = header.index("Data Element"), header.index("Private Creator"), header.index("VR")
    result = []
    for cells in laid_out(safe, "tbody"):
        value = tag_of(text(cells[element]))
        if value is None:
            raise SystemExit(f"unexpected private tag {text(cells[element])!r} in Table E.3.10-1")
        result.append({"tag": value, "creator": text(cells[creator]), "vr": text(cells[vr])})
    return result


def generate(part15: Path) -> dict[str, object]:
    root = ET.parse(part15).getroot()
    return {
        "edition": "2026d",
        "attributes": sorted(profile_attributes(root), key=lambda entry: entry["tag"]),
        "safePrivate": safe_private_attributes(root),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("part15", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check", action="store_true", help="Fail if the output differs instead of writing it")
    arguments = parser.parse_args()
    encoded = json.dumps(generate(arguments.part15), ensure_ascii=False, indent=0, separators=(",", ":")) + "\n"
    if arguments.check:
        if arguments.output.read_text(encoding="utf-8") != encoded:
            raise SystemExit(f"{arguments.output} is not up to date")
        return
    arguments.output.write_text(encoded, encoding="utf-8")


if __name__ == "__main__":
    main()
