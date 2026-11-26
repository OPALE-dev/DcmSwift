"""Compare the partial read of malformed DICOM files by DcmSwift and pydicom.

  pydicom_partial.py DCMPRINT PATH...

DCMPRINT is the DcmPrint executable. Each file is read by
`DcmPrint --tolerant -f JSON` and by `pydicom.dcmread(force=True)`, whose
iteration stops at the first unreadable element. The top-level data set
tags DcmSwift keeps must be a prefix of those pydicom reads: DcmSwift drops
the element it cannot read, where pydicom may keep it with a truncated or
undecoded value. A file pydicom cannot read at all is reported, not counted
as a difference. Exits 1 on any difference.
"""
import json, subprocess, sys, warnings
import pydicom

warnings.simplefilter("ignore")
dcmprint, paths = sys.argv[1], sys.argv[2:]
differences = 0
for path in paths:
    run = subprocess.run([dcmprint, "--tolerant", "-f", "JSON", path], capture_output=True, text=True)
    if run.returncode == 1:
        ours = None
    else:
        ours = sorted(json.loads(run.stdout or "{}").keys())
    failure = next((l for l in run.stderr.splitlines() if l.startswith(path + ": ")), "").removeprefix(path + ": ")

    theirs = []
    try:
        dataset = pydicom.dcmread(path, force=True)
        try:
            for element in dataset:
                theirs.append(f"{element.tag.group:04X}{element.tag.element:04X}")
        except Exception:
            pass
    except Exception as error:
        print(f"{path}: pydicom cannot read it ({type(error).__name__}); DcmSwift keeps {len(ours or [])} element(s)")
        continue

    if ours is None:
        print(f"DIFF {path}: DcmSwift reads nothing, pydicom {len(theirs)} element(s)")
        differences += 1
    elif theirs[:len(ours)] != ours:
        print(f"DIFF {path}: DcmSwift {ours} is not a prefix of pydicom {theirs}")
        differences += 1
    else:
        print(f"{path}: DcmSwift {len(ours)}, pydicom {len(theirs)} element(s); {failure or 'read completely'}")
print(f"{len(paths)} file(s), {differences} difference(s)")
sys.exit(1 if differences else 0)
