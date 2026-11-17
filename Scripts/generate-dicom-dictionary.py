#!/usr/bin/env python3
"""Generate DcmSwift's runtime dictionary from DICOM PS3.6 DocBook XML."""

from __future__ import annotations

import argparse
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path


TAG_RE = re.compile(r"^\(([0-9A-Fa-fxX]{4}),([0-9A-Fa-fxX]{4})\)$")
UID_RE = re.compile(r"^[0-9]+(?:\.[0-9]+)+$")
INVISIBLE = dict.fromkeys(map(ord, "\u200b\u200c\u200d\u2060\ufeff"), None)


def text(element: ET.Element) -> str:
    return "".join(element.itertext()).translate(INVISIBLE).strip()


def is_retired(row: ET.Element, cells: list[str]) -> bool:
    if cells and cells[-1].upper() == "RET":
        return True
    return any(
        node.attrib.get("role") == "italic"
        for node in row.iter()
        if node.tag.rsplit("}", 1)[-1] == "emphasis"
    )


def generate(source: Path) -> dict[str, object]:
    root = ET.parse(source).getroot()
    tags: list[dict[str, object]] = []
    uids: list[dict[str, object]] = []
    seen_tags: set[str] = set()
    seen_uids: set[str] = set()

    for row in root.iter():
        if row.tag.rsplit("}", 1)[-1] != "tr":
            continue
        cells = [text(cell) for cell in row if cell.tag.rsplit("}", 1)[-1] in {"td", "th"}]
        if not cells:
            continue

        tag_match = TAG_RE.fullmatch(cells[0])
        if tag_match and len(cells) >= 5:
            group, element = (part.lower() for part in tag_match.groups())
            code = group + element
            if code not in seen_tags and cells[2] and cells[3]:
                tags.append(
                    {
                        "group": group,
                        "element": element,
                        "name": cells[1],
                        "keyword": cells[2],
                        "vr": cells[3],
                        "vm": cells[4],
                        "retired": is_retired(row, cells),
                    }
                )
                seen_tags.add(code)
            continue

        uid = cells[0].replace(" ", "")
        if UID_RE.fullmatch(uid) and len(cells) >= 4 and uid not in seen_uids:
            uids.append(
                {
                    "uid": uid,
                    "name": cells[1],
                    "keyword": cells[2],
                    "type": cells[3],
                    "retired": is_retired(row, cells),
                }
            )
            seen_uids.add(uid)

    if len(tags) < 4_000 or len(uids) < 300:
        raise RuntimeError(f"Unexpected PS3.6 extraction result: {len(tags)} tags, {len(uids)} UIDs")

    return {
        "edition": "2026d",
        "source": "DICOM PS3.6 DocBook",
        "tags": tags,
        "uids": uids,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Path to part06.xml")
    parser.add_argument("output", type=Path, help="Destination JSON file")
    args = parser.parse_args()

    result = generate(args.source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(f"Generated {len(result['tags'])} tags and {len(result['uids'])} UIDs in {args.output}")


if __name__ == "__main__":
    main()
