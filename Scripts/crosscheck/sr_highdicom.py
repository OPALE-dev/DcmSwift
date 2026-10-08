"""Cross-check DcmSwift's Structured Reports with highdicom, pydicom, and DCMTK.

  sr_highdicom.py BUILD_DIR STANDARD_DIR CT_SERIES_DIR [SR_FILE_OR_DIR...]

BUILD_DIR holds DcmSR; STANDARD_DIR is the -src folder of dicom-validator's
validate_iods (on the PATH); CT_SERIES_DIR holds images to measure. Needs
highdicom and DCMTK's dsrdump.

1. DcmSR measure makes a TID 1500 Measurement Report; highdicom must read
   its Measurement Groups and measurements back, dicom-validator must find no
   error, and dsrdump must read it without error or warning.
2. highdicom makes a TID 1500 report with an image Measurement Group and a
   planar ROI Measurement Group (SCOORD); for it and for every SR file given,
   the content tree of DcmSR json (relationship, value type, concept name,
   value, children) must equal the one pydicom reads.
Exits 1 on any failure.
"""
import json
import os
import subprocess
import sys
import tempfile

import highdicom as hd
import numpy as np
import pydicom
from pydicom.sr.codedict import codes


def code(sequence):
    if not sequence:
        return None
    item = sequence[0]
    return [item.get("CodeValue") or item.get("LongCodeValue") or item.get("URNCodeValue"), item.CodingSchemeDesignator,
            item.CodeMeaning]


def value(item):
    kind = item.get("ValueType", "")
    if "ReferencedContentItemIdentifier" in item:
        return [int(v) for v in pydicom.multival.MultiValue(int, item.ReferencedContentItemIdentifier)] \
            if not isinstance(item.ReferencedContentItemIdentifier, int) else [int(item.ReferencedContentItemIdentifier)]
    if kind == "TEXT":
        return item.TextValue
    if kind == "CODE":
        return code(item.ConceptCodeSequence)
    if kind == "NUM":
        measured = item.get("MeasuredValueSequence")
        if not measured:
            return [None, None]
        return [float(measured[0].NumericValue), code(measured[0].MeasurementUnitsCodeSequence)]
    if kind in ("DATETIME", "DATE", "TIME", "UIDREF", "PNAME"):
        return str(item.get({"DATETIME": "DateTime", "DATE": "Date", "TIME": "Time", "UIDREF": "UID",
                             "PNAME": "PersonName"}[kind]))
    if kind in ("IMAGE", "COMPOSITE", "WAVEFORM"):
        reference = item.ReferencedSOPSequence[0]
        return [reference.ReferencedSOPClassUID, reference.ReferencedSOPInstanceUID]
    if kind in ("SCOORD", "SCOORD3D"):
        return [item.GraphicType, [round(float(v), 4) for v in item.GraphicData]]
    return None


def tree(item, root=False):
    return {"relationship": None if root else item.get("RelationshipType"), "valueType": item.get("ValueType", ""),
            "concept": code(item.get("ConceptNameCodeSequence")), "value": value(item),
            "children": [tree(child) for child in item.get("ContentSequence", [])]}


def normalized(node):
    """DcmSR's JSON node with rounded coordinates and float numbers."""
    result = dict(node)
    if node["valueType"] in ("SCOORD", "SCOORD3D") and node.get("value"):
        result["value"] = [node["value"][0], [round(v, 4) for v in node["value"][1]]]
    if node["valueType"] == "NUM" and node.get("value"):
        result["value"] = [None if node["value"][0] is None else float(node["value"][0]), node["value"][1]]
    if node["valueType"] == "" and isinstance(node.get("value"), list):
        result["valueType"] = ""
    result.setdefault("value", None)
    result["children"] = [normalized(child) for child in node["children"]]
    return result


def run(*arguments):
    return subprocess.run(list(arguments), capture_output=True, text=True, timeout=120)


def main(build, standard, series, paths):
    failures = []
    dcmsr = os.path.join(build, "DcmSR")
    images = sorted((os.path.join(series, name) for name in os.listdir(series)),
                    key=lambda path: float(pydicom.dcmread(path).ImagePositionPatient[2]))
    with tempfile.TemporaryDirectory() as folder:
        # 1. DcmSR makes, highdicom, dicom-validator, and dsrdump read.
        ours = os.path.join(folder, "ours.dcm")
        result = run(dcmsr, "measure", "--image", images[0], "--image", images[1], "--observer", "Doe^John",
                     "--measurement", "lesion1=118565006,SCT,Volume:12.5:cm3",
                     "--measurement", "lesion1=103339001,SCT,Long Axis:31:mm",
                     "--measurement", "lesion2=118565006,SCT,Volume:3.25:cm3", "--output", ours)
        if result.returncode != 0:
            failures.append(f"DcmSR measure failed: {result.stderr[-300:]}")
        else:
            report = hd.sr.MeasurementReport.from_sequence([hd.sr.srread(ours)], copy=False)
            found = {group.tracking_identifier: [(m.name.value, m.value, m.unit.value) for m in group.get_measurements()]
                     for group in report.get_image_measurement_groups()}
            expected = {"lesion1": [("118565006", 12.5, "cm3"), ("103339001", 31.0, "mm")],
                        "lesion2": [("118565006", 3.25, "cm3")]}
            if found != expected:
                failures.append(f"highdicom reads {found}, not {expected}")
            oracle = run("validate_iods", "-src", standard, "-r", "2026d", ours)
            errors = [line for line in oracle.stdout.splitlines()
                      if "missing" in line or "unexpected" in line or "invalid value" in line or "not allowed" in line]
            if errors:
                failures.append(f"dicom-validator: {errors}")
            dump = run("dsrdump", ours)
            if dump.returncode != 0 or "E:" in dump.stderr or "W:" in dump.stderr:
                failures.append(f"dsrdump: {dump.stderr.strip()[-300:]}")

        # 2. highdicom makes; DcmSR reads like pydicom.
        sources = [pydicom.dcmread(path) for path in images[:2]]
        tracking = hd.sr.TrackingIdentifier(identifier="nodule", uid=hd.UID())
        polyline = hd.sr.ImageRegion(graphic_type=hd.sr.GraphicTypeValues.POLYLINE,
                                     graphic_data=np.array([[1.0, 1.0], [5.5, 1.0], [5.5, 4.25], [1.0, 1.0]]),
                                     source_image=hd.sr.SourceImageForRegion.from_source_image(sources[0]))
        groups = [
            hd.sr.MeasurementsAndQualitativeEvaluations(
                tracking_identifier=hd.sr.TrackingIdentifier(identifier="overall", uid=hd.UID()),
                measurements=[hd.sr.Measurement(name=codes.SCT.Volume, value=42.0,
                                                unit=hd.sr.CodedConcept("cm3", "UCUM", "cm3"))]),
            hd.sr.PlanarROIMeasurementsAndQualitativeEvaluations(
                tracking_identifier=tracking, referenced_region=polyline,
                finding_type=codes.SCT.Nodule,
                measurements=[hd.sr.Measurement(name=codes.SCT.Area, value=11.75,
                                                unit=hd.sr.CodedConcept("mm2", "UCUM", "mm2"))]),
        ]
        measurement_report = hd.sr.MeasurementReport(
            observation_context=hd.sr.ObservationContext(
                observer_person_context=hd.sr.ObserverContext(
                    observer_type=codes.DCM.Person,
                    observer_identifying_attributes=hd.sr.PersonObserverIdentifyingAttributes(name="Doe^Jane"))),
            procedure_reported=codes.LN.CTUnspecifiedBodyRegion, imaging_measurements=groups)
        theirs = os.path.join(folder, "theirs.dcm")
        hd.sr.Comprehensive3DSR(evidence=sources, content=measurement_report[0], series_number=2,
                                series_instance_uid=hd.UID(), sop_instance_uid=hd.UID(), instance_number=1,
                                manufacturer="test").save_as(theirs)
        files = [theirs]
        for path in paths:
            if os.path.isdir(path):
                for root, _, names in os.walk(path):
                    files += [os.path.join(root, name) for name in sorted(names) if not name.startswith(".")]
            else:
                files.append(path)
        compared = 0
        for path in files:
            try:
                dataset = pydicom.dcmread(path)
            except Exception:
                continue
            if not str(dataset.get("SOPClassUID", "")).startswith("1.2.840.10008.5.1.4.1.1.88.") \
                    or dataset.get("ValueType") != "CONTAINER":
                continue
            result = run(dcmsr, "json", path)
            if result.returncode != 0:
                failures.append(f"{os.path.basename(path)}: DcmSR json failed: {result.stderr[-200:]}")
                continue
            mine = normalized(json.loads(result.stdout)["root"])
            expected = tree(dataset, root=True)
            compared += 1
            if mine != expected:
                failures.append(f"{os.path.basename(path)}: content trees differ")
    for failure in failures:
        print("FAIL", failure)
    print(f"1 DcmSR report checked, {compared} SR trees compared with pydicom, {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]))
