#!/usr/bin/env python3
"""Generate DcmSwift's command-field dictionary from PS3.7 Table E.1-1."""

from __future__ import annotations

import argparse
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path


TAG_RE = re.compile(r"^\(([0-9A-Fa-f]{4}),([0-9A-Fa-f]{4})\)$")


def text(element: ET.Element) -> str:
    return "".join(element.itertext()).strip()


def generate(source: Path, edition: str) -> dict[str, object]:
    root = ET.parse(source).getroot()
    table = next(
        (
            node
            for node in root.iter()
            if node.tag.rsplit("}", 1)[-1] == "table"
            and node.attrib.get("{http://www.w3.org/XML/1998/namespace}id") == "table_E.1-1"
        ),
        None,
    )
    if table is None:
        raise RuntimeError("PS3.7 Table E.1-1 was not found")

    tags: list[dict[str, object]] = []
    for row in table.iter():
        if row.tag.rsplit("}", 1)[-1] != "tr":
            continue
        cells = [text(cell) for cell in row if cell.tag.rsplit("}", 1)[-1] in {"td", "th"}]
        match = TAG_RE.fullmatch(cells[0]) if len(cells) >= 5 else None
        if not match:
            continue
        group, element = (part.lower() for part in match.groups())
        tags.append(
            {
                "group": group,
                "element": element,
                "name": cells[1],
                "keyword": cells[2],
                "vr": cells[3],
                "vm": cells[4],
                "retired": False,
            }
        )

    if len(tags) != 24 or any(tag["group"] != "0000" for tag in tags):
        raise RuntimeError(f"Unexpected PS3.7 extraction result: {len(tags)} command fields")
    return {"edition": edition, "source": "DICOM PS3.7 DocBook Table E.1-1", "tags": tags}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Path to part07.xml")
    parser.add_argument("output", type=Path, help="Destination JSON file")
    parser.add_argument("--edition", default="2026d")
    args = parser.parse_args()
    result = generate(args.source, args.edition)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Generated {len(result['tags'])} command fields in {args.output}")


if __name__ == "__main__":
    main()
