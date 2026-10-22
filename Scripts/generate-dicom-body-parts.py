#!/usr/bin/env python3
"""Generate PS3.16 Table L-1 Body Part Examined mappings from local DocBook."""
import argparse
import json
import xml.etree.ElementTree as ET
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("part16", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
root = ET.parse(args.part16).getroot()
table = next(element for element in root.iter() if element.get("label") == "L-1")
entries = {}
for row in table.iter("{http://docbook.org/ns/docbook}tr"):
    cells = [" ".join(" ".join(cell.itertext()).split()) for cell in row]
    if len(cells) >= 4 and cells[0] in ("SCT", "DCM") and cells[3]:
        entries[cells[3]] = {"scheme": cells[0], "value": cells[1], "meaning": cells[2]}
args.output.write_text(json.dumps({"edition": "2026d", "table": "PS3.16 L-1", "entries": entries}, sort_keys=True, indent=2) + "\n")
