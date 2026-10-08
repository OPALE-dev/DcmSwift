"""Compare DcmValidate's findings with those of dicom-validator.

  dicom_validator.py DCMVALIDATE STANDARD_DIR FILE_OR_DIR...

DCMVALIDATE is the DcmValidate executable; STANDARD_DIR is the folder that
dicom-validator's validate_iods reads (-src), with the 2026d DocBook parts in
STANDARD_DIR/2026d/docbook. validate_iods must be on the PATH (pip install
dicom-validator).

Files without the Part 10 preamble, which dicom-validator does not read, and
truncated files, which DcmSwift rejects, are counted and skipped. For each other file, compares the attributes reported missing, empty, or with an
unexpected Enumerated Value by both tools, by tag. dicom-validator evaluates
the conditions of Types 1C and 2C and of conditional modules, which
DcmValidate does not: attributes it alone reports are listed as conditions
not evaluated, not as differences. An attribute only DcmValidate reports is a
difference. Exits 1 on any difference.
"""
import os
import re
import subprocess
import sys

TAG = r"\(([0-9A-F]{4}),([0-9A-F]{4})\)"


def files(paths):
    for path in paths:
        if os.path.isdir(path):
            for root, _, names in os.walk(path):
                for name in sorted(names):
                    if not name.startswith("."):
                        yield os.path.join(root, name)
        else:
            yield path


def ours(executable, path):
    output = subprocess.run([executable, path], capture_output=True, text=True).stdout
    findings = set()
    for line in output.splitlines():
        match = re.search(TAG + r" (is missing|is empty|has the value)", line.split(">")[-1])
        if match:
            kind = {"is missing": "missing", "is empty": "empty", "has the value": "value"}[match.group(3)]
            findings.add((match.group(1) + match.group(2), kind))
    unknown = "unknown IOD" in output
    return findings, unknown, "cannot be read" in output


def theirs(standard, path):
    result = subprocess.run(["validate_iods", "-src", standard, "-r", "2026d", path], capture_output=True, text=True)
    findings = set()
    lines = (result.stdout + result.stderr).splitlines()
    for index, line in enumerate(lines):
        match = re.search(r"Tag " + TAG + r".*? (is missing|is empty| - enum value)", line)
        if match:
            kind = {"is missing": "missing", "is empty": "empty", " - enum value": "value"}[match.group(3)]
            findings.add((match.group(1) + match.group(2), kind))
    unknown = re.search(r"^(Unknown or retired SOP Class|Missing SOP Class UID)", result.stdout, re.M) is not None
    unreadable = "Not a DICOM File" in result.stdout
    return findings, unknown, unreadable


def main(executable, standard, paths):
    differences, files_compared, conditions, unreadable, agreed = 0, 0, 0, 0, 0
    for path in files(paths):
        mine, mine_unknown, mine_unreadable = ours(executable, path)
        other, other_unknown, other_unreadable = theirs(standard, path)
        if other_unreadable or mine_unreadable:
            # pydicom reads only files with the Part 10 preamble; DcmSwift
            # rejects truncated files.
            unreadable += 1
            continue
        if mine_unknown or other_unknown:
            if mine_unknown != other_unknown:
                print(f"{path}: IOD known to only one tool")
                differences += 1
            continue
        files_compared += 1
        only_mine = mine - other
        only_theirs = other - mine
        conditions += len(only_theirs)
        agreed += len(mine & other)
        if only_mine:
            differences += 1
            print(f"{path}: DcmValidate only {sorted(only_mine)}")
        if only_theirs:
            print(f"{path}: conditions not evaluated {sorted(only_theirs)}")
    print(f"{files_compared} files compared, {agreed} findings of both tools, {differences} files with differences, "
          f"{conditions} findings from conditions DcmValidate does not evaluate, "
          f"{unreadable} files one of the tools cannot read")
    return 1 if differences else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3:]))
