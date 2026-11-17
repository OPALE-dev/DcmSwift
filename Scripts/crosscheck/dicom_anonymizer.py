"""Compare DcmSwift's de-identification with Kitware's dicom-anonymizer.

  dicom_anonymizer.py dicom-deidentification-2026d.json DCMANONYMIZE FILE_OR_DIR...

dicom-anonymizer (pip install dicom-anonymizer) implements the Basic
Application Level Confidentiality Profile of PS3.15 Table E.1-1 from its own
reading of the 2026c edition.

1. Table: the Basic Profile action of every attribute in DcmSwift's 2026d
   resource is compared with dicom-anonymizer's 2026c lists. Differences are
   printed for review; the edition changed some rows.
2. Behaviour: each file is de-identified by DCMANONYMIZE (DcmAnonymize) and
   by dicom-anonymizer, both removing private attributes. For every attribute
   of the source, at any depth, the outcome is classified as removed,
   emptied, replaced, or unchanged. For the attributes whose action is
   simple (D, Z, X, U, K), both outcomes must be equal. dicom-anonymizer
   resolves compound actions (X/Z, X/D, Z/D, X/Z/D, X/Z/U*) without the IOD,
   always to their last choice, whereas DcmSwift follows the Type of the
   attribute in the IOD; for those, DcmSwift's outcome must be one the
   action allows, a Sequence kept for D having its contents de-identified.
   An attribute already empty that stays empty counts as emptied. Exits 1
   on any behaviour difference.
"""
import json
import os
import subprocess
import sys
import tempfile

import pydicom
from dicomanonymizer import anonymize_dicom_file
from dicomanonymizer.dicomfields_selector import dicom_anonymization_database_selector

CATEGORIES = {"D_TAGS": "D", "Z_TAGS": "Z", "X_TAGS": "X", "U_TAGS": "U", "Z_D_TAGS": "Z/D", "X_Z_TAGS": "X/Z",
              "X_D_TAGS": "X/D", "X_Z_D_TAGS": "X/Z/D", "X_Z_U_STAR_TAGS": "X/Z/U*"}
# The outcomes each compound action allows.
ALLOWED = {"Z/D": {"emptied", "replaced"}, "X/Z": {"removed", "emptied"}, "X/D": {"removed", "replaced"},
           "X/Z/D": {"removed", "emptied", "replaced"}, "X/Z/U*": {"removed", "emptied", "replaced", "unchanged"}}
SIMPLE = {"D": "replaced", "Z": "emptied", "X": "removed", "U": "replaced", "K": "unchanged"}


def theirs_table():
    table = {}
    for category, action in CATEGORIES.items():
        for entry in dicom_anonymization_database_selector("dicomfields_2026c")[category]:
            if isinstance(entry, tuple) and len(entry) == 2 and all(isinstance(part, int) for part in entry):
                table[f"{entry[0]:04X}{entry[1]:04X}"] = action
    return table


def compare_tables(resource):
    ours = {entry["tag"]: entry["basic"] for entry in resource["attributes"] if "X" not in entry["tag"]
            and entry["tag"] != "private"}
    theirs = theirs_table()
    only_ours = sorted(set(ours) - set(theirs))
    only_theirs = sorted(set(theirs) - set(ours))
    changed = sorted(tag for tag in set(ours) & set(theirs) if ours[tag] != theirs[tag])
    print(f"Table: {len(ours)} attributes in 2026d, {len(theirs)} in dicom-anonymizer 2026c, "
          f"{len(set(ours) & set(theirs)) - len(changed)} with the same action")
    for tag in only_ours:
        print(f"  2026d only: {tag} {ours[tag]}")
    for tag in only_theirs:
        print(f"  2026c only: {tag} {theirs[tag]}")
    for tag in changed:
        print(f"  changed: {tag} 2026d {ours[tag]}, 2026c {theirs[tag]}")
    return ours


def outcomes(source, result, prefix=()):
    """The outcome of every attribute of `source` in `result`, by path."""
    found = {}
    for element in source:
        if element.tag.is_private or element.tag.group in (0x0002, 0x0004) or element.tag.element == 0:
            continue
        path = prefix + (f"{element.tag.group:04X}{element.tag.element:04X}",)
        after = result.get(element.tag) if result is not None else None
        if after is None:
            found[path] = "removed"
        elif element.VR == "SQ":
            if not after.value:
                found[path] = "emptied"
            else:
                found[path] = "unchanged"
                for index, item in enumerate(element.value):
                    other = after.value[index] if index < len(after.value) else None
                    found.update(outcomes(item, other, path))
        elif after.is_empty:
            # Emptied, or already empty.
            found[path] = "emptied"
        elif after.value != element.value:
            found[path] = "replaced"
        else:
            found[path] = "unchanged"
    return found


def main(resource_path, executable, paths):
    resource = json.load(open(resource_path, encoding="utf-8"))
    actions = compare_tables(resource)
    files = []
    for path in paths:
        if os.path.isdir(path):
            for root, _, names in os.walk(path):
                files += [os.path.join(root, name) for name in sorted(names) if not name.startswith(".")]
        else:
            files.append(path)
    differences, compared, checked, unreadable = 0, 0, 0, 0
    with tempfile.TemporaryDirectory() as folder:
        for index, path in enumerate(files):
            try:
                source = pydicom.dcmread(path)
            except Exception:
                continue
            if "SOPClassUID" not in source:
                continue
            ours_path, theirs_path = os.path.join(folder, f"{index}-ours.dcm"), os.path.join(folder, f"{index}-theirs.dcm")
            run = subprocess.run([executable, path, ours_path], capture_output=True, text=True)
            if run.returncode != 0:
                if "Cannot read" in run.stdout + run.stderr:
                    # Truncated files, which DcmSwift rejects.
                    unreadable += 1
                else:
                    print(f"{path}: DcmAnonymize failed")
                    differences += 1
                continue
            try:
                anonymize_dicom_file(path, theirs_path, base_rules_gen=lambda: _rules())
                theirs = pydicom.dcmread(theirs_path)
            except Exception as error:
                print(f"{path}: dicom-anonymizer failed ({error})")
                continue
            ours = pydicom.dcmread(ours_path)
            mine, other = outcomes(source, ours), outcomes(source, theirs)
            compared += 1
            for attribute, outcome in sorted(mine.items()):
                action = actions.get(attribute[-1])
                if action is None or attribute not in other:
                    continue
                checked += 1
                expected = SIMPLE.get(action)
                if expected is not None:
                    # Both must agree, when dicom-anonymizer did what the
                    # action says (it may skip attributes in Sequences).
                    if outcome != other[attribute] and other[attribute] == expected:
                        print(f"{os.path.basename(path)}: {'>'.join(attribute)} {action}: "
                              f"DcmSwift {outcome}, dicom-anonymizer {other[attribute]}")
                        differences += 1
                elif outcome not in ALLOWED[action] and not (outcome == "unchanged" and "D" in action
                                                             and source_is_sequence(source, attribute)):
                    # A Sequence kept for D has its contents de-identified,
                    # which are checked as attributes of their own.
                    print(f"{os.path.basename(path)}: {'>'.join(attribute)} {action}: DcmSwift {outcome}")
                    differences += 1
    print(f"Behaviour: {compared} files, {checked} attribute outcomes checked, {differences} differences, "
          f"{unreadable} files DcmSwift cannot read")
    return 1 if differences else 0


def source_is_sequence(dataset, path):
    for index, tag in enumerate(path):
        element = dataset.get(int(tag, 16)) if dataset is not None else None
        if element is None:
            return False
        if index == len(path) - 1:
            return element.VR == "SQ"
        dataset = element.value[0] if element.VR == "SQ" and element.value else None
    return False


def _rules():
    from dicomanonymizer.simpledicomanonymizer import initialize_actions
    return initialize_actions("dicomfields_2026c")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3:]))
