"""Cross-check DcmSwift's RT objects with dicompyler-core.

  rt_dicompyler.py BUILD_DIR FILE_OR_DIR...

Run with a Python that has dicompyler-core and pydicom 2 (dicompyler-core
does not run with pydicom 3). BUILD_DIR holds DcmRT. For each RT Structure
Set, RT Dose, and RT Plan, DcmRT --json is compared with dicompyler-core's
DicomParser:
- Structure Sets: each ROI's name, color, and interpreted type, and every
  contour point (GetStructures, GetStructureCoordinates);
- Doses: grid, units, type, summation, scaling (GetDoseData), every dose
  value (pydicom's pixel_array times Dose Grid Scaling), and the DVHs
  (GetDVHs: volumes and bin edges);
- Plans: label, date, prescription in cGy (GetPlan), and the beams of the
  first Fraction Group with their meterset (GetReferencedBeamsInFraction).
Exits 1 on any difference.
"""
import json
import os
import subprocess
import sys

import numpy as np
import pydicom
from dicompylercore import dicomparser

STRUCTURES, DOSE, PLAN = "1.2.840.10008.5.1.4.1.1.481.3", "1.2.840.10008.5.1.4.1.1.481.2", "1.2.840.10008.5.1.4.1.1.481.5"


def close(a, b, tolerance=1e-6):
    return abs(float(a) - float(b)) <= tolerance * max(1.0, abs(float(a)), abs(float(b)))


def check_structures(path, ours, failures):
    parser = dicomparser.DicomParser(path)
    theirs = parser.GetStructures()
    mine = {roi["number"]: roi for roi in ours["structureSet"]["rois"]}
    if set(mine) != set(theirs):
        failures.append(f"ROI numbers {sorted(mine)} != {sorted(theirs)}")
        return
    for number, structure in theirs.items():
        roi = mine[number]
        if roi["name"] != structure["name"]:
            failures.append(f"ROI {number} name {roi['name']!r} != {structure['name']!r}")
        color = structure.get("color")
        if color is not None and roi["color"] is not None and [int(c) for c in color] != roi["color"]:
            failures.append(f"ROI {number} color {roi['color']} != {list(color)}")
        if (structure.get("type") or None) != roi["type"]:
            failures.append(f"ROI {number} type {roi['type']} != {structure.get('type')}")
        coordinates = parser.GetStructureCoordinates(number)
        expected = sorted(tuple(round(float(v), 4) for v in point)
                          for planes in coordinates.values() for plane in planes for point in plane["data"])
        found = sorted(tuple(round(v, 4) for v in point) for contour in roi["contours"] for point in contour["points"])
        if expected != found:
            failures.append(f"ROI {number}: {len(found)} contour points, dicompyler-core {len(expected)}, or different")


def check_dose(path, ours, failures):
    parser = dicomparser.DicomParser(path)
    data = parser.GetDoseData()
    dose = ours["dose"]
    for key, theirs in (("rows", data["rows"]), ("columns", data["columns"]), ("frames", data["frames"]),
                        ("units", data["doseunits"]), ("type", data["dosetype"]),
                        ("summationType", data["dosesummationtype"])):
        if str(dose[key]) != str(theirs):
            failures.append(f"dose {key} {dose[key]} != {theirs}")
    if not close(dose["gridScaling"], data["dosegridscaling"]):
        failures.append(f"Dose Grid Scaling {dose['gridScaling']} != {data['dosegridscaling']}")
    if [round(v, 4) for v in dose["position"]] != [round(float(v), 4) for v in data["position"]]:
        failures.append("Image Position (Patient) differs")
    dataset = pydicom.dcmread(path)
    pixels = dataset.pixel_array.reshape(int(data["frames"]), int(data["rows"]), int(data["columns"]))
    expected = pixels.astype(float) * float(dataset.DoseGridScaling)
    found = np.array(dose["values"], dtype=float).reshape(expected.shape)
    if not np.allclose(found, expected, rtol=1e-9, atol=0):
        failures.append(f"dose values differ, at most by {np.abs(found - expected).max()}")
    dvhs = parser.GetDVHs() or {}
    mine = {roi: dvh for dvh in dose["dvhs"] for roi in dvh["rois"]}
    if set(mine) != set(dvhs):
        failures.append(f"DVH ROIs {sorted(mine)} != {sorted(dvhs)}")
    for roi, dvh in dvhs.items():
        volumes = [bin_[1] for bin_ in mine[roi]["bins"]]
        if not np.allclose(volumes, dvh.counts, rtol=1e-9):
            failures.append(f"DVH of ROI {roi}: volumes differ")
        edges = np.concatenate([[0], np.cumsum([bin_[0] for bin_ in mine[roi]["bins"]])])
        if not np.allclose(edges[: len(dvh.bins)], dvh.bins, rtol=1e-6, atol=1e-9):
            failures.append(f"DVH of ROI {roi}: bin edges differ")


def check_plan(path, ours, failures):
    parser = dicomparser.DicomParser(path)
    theirs = parser.GetPlan()
    plan = ours["plan"]
    if plan["label"] != theirs["label"] or (plan["date"] or "") != theirs["date"]:
        failures.append(f"plan label or date {plan['label']} {plan['date']} != {theirs['label']} {theirs['date']}")
    if plan["prescriptionDose"] is not None and theirs.get("rxdose") and round(plan["prescriptionDose"] * 100) != theirs["rxdose"]:
        failures.append(f"prescription {plan['prescriptionDose']} Gy != {theirs['rxdose']} cGy")
    beams = parser.GetReferencedBeamsInFraction() if plan["fractionGroups"] else {}
    mine = {beam["number"]: beam for beam in plan["beams"]}
    for number, beam in beams.items():
        if number not in mine:
            failures.append(f"beam {number} missing")
            continue
        if "name" in beam and (mine[number]["name"] or "") != beam["name"]:
            failures.append(f"beam {number} name {mine[number]['name']} != {beam['name']}")
        if beam.get("meterset") is not None and not close(mine[number]["meterset"] or 0, beam["meterset"]):
            failures.append(f"beam {number} meterset {mine[number]['meterset']} != {beam['meterset']}")


def main(build, paths):
    executable = os.path.join(build, "DcmRT")
    failures, checked, unreadable = [], 0, 0
    files = []
    for path in paths:
        if os.path.isdir(path):
            for root, _, names in os.walk(path):
                files += [os.path.join(root, name) for name in sorted(names) if not name.startswith(".")]
        else:
            files.append(path)
    for path in files:
        try:
            sop = str(pydicom.dcmread(path, stop_before_pixels=True).SOPClassUID)
        except Exception:
            continue
        if sop not in (STRUCTURES, DOSE, PLAN):
            continue
        try:
            pydicom.dcmread(path).pixel_array if sop == DOSE else None
        except Exception:
            continue  # pydicom 2 cannot decode it
        result = subprocess.run([executable, path, "--json"], capture_output=True, timeout=300)
        name = os.path.basename(path)
        if result.returncode != 0:
            if b"cannot read" in result.stderr:
                unreadable += 1  # truncated files, which DcmSwift rejects
            else:
                failures.append(f"{name}: DcmRT failed: {result.stderr[-200:]!r}")
            continue
        ours = json.loads(result.stdout)
        found = []
        try:
            {STRUCTURES: check_structures, DOSE: check_dose, PLAN: check_plan}[sop](path, ours, found)
        except Exception as error:
            found.append(f"dicompyler-core failed: {error}")
        failures += [f"{name}: {failure}" for failure in found]
        checked += 1
    for failure in failures:
        print("FAIL", failure)
    print(f"{checked} RT objects, {len(failures)} failures, {unreadable} files DcmSwift cannot read")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2:]))
