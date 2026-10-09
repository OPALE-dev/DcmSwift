#!/usr/bin/env python3
"""Cross-checks the Modality Worklist (PS3.4 K.6) against DCMTK.

    worklist_dcmtk.py BUILD_DIR [-v]

BUILD_DIR holds the DcmServer and DcmFind executables (.build/debug).
DCMTK's wlmscpfs, findscu, dump2dcm, and dcmdump must be on the PATH.

The same worklist items, written with dump2dcm, are served by wlmscpfs and
by DcmServer --worklist-directory. Each query is sent with findscu -W to
both servers, and with DcmFind -m worklist to wlmscpfs; the responses must
be identical (as dumped by dcmdump), and DcmFind must find the same items.
Work files go to a new temporary directory. Exits 1 on a difference.
"""

import os
import re
import socket
import subprocess
import sys
import tempfile
import time

ITEMS = [
    # patient, id, station, modality, date, time, physician, accession
    ("DOE^JANE", "P1", "CT1", "CT", "20240706", "080000", "SMITH^ANN", "A1"),
    ("DOE^JOHN", "P2", "CT1", "CT", "20240705", "113000", "SMITH^ANN", "A2"),
    ("ROE^RICHARD", "P3", "MR1", "MR", "20240707", "190000", "JONES^BOB", "A3"),
    ("POE^EDGAR", "P4", "MR1", "MR", "20240707", "170000", "JONES^BOB", "A4"),
    ("MOE^ANNA", "P5", "US1", "US", "20240708", "093000", "", "A5"),
    ("NOE^PAT", "P6", "CT2", "CT", "20240704", "235959", "SMITH^ANN", ""),
]

QUERIES = {
    "all": [],
    "modality": ["ScheduledProcedureStepSequence[0].Modality=CT"],
    "station": ["ScheduledProcedureStepSequence[0].ScheduledStationAETitle=MR1"],
    "name wildcard": ["PatientName=DOE*"],
    "name single char": ["PatientName=?OE^JANE"],
    "patient id": ["PatientID=P3"],
    "date single": ["ScheduledProcedureStepSequence[0].ScheduledProcedureStepStartDate=20240707"],
    "date range": ["ScheduledProcedureStepSequence[0].ScheduledProcedureStepStartDate=20240705-20240707"],
    "date open low": ["ScheduledProcedureStepSequence[0].ScheduledProcedureStepStartDate=-20240705"],
    "date open high": ["ScheduledProcedureStepSequence[0].ScheduledProcedureStepStartDate=20240707-"],
    "time range": ["ScheduledProcedureStepSequence[0].ScheduledProcedureStepStartTime=0800-1200"],
    "date and time ranges": [
        "ScheduledProcedureStepSequence[0].ScheduledProcedureStepStartDate=20240705-20240707",
        "ScheduledProcedureStepSequence[0].ScheduledProcedureStepStartTime=1000-1800",
    ],
    "physician": ["ScheduledProcedureStepSequence[0].ScheduledPerformingPhysicianName=SMITH*"],
    "accession": ["AccessionNumber=A4"],
    "modality and station": [
        "ScheduledProcedureStepSequence[0].Modality=CT",
        "ScheduledProcedureStepSequence[0].ScheduledStationAETitle=CT2",
    ],
}

# Return keys added to every query.
RETURN_KEYS = [
    "PatientName", "PatientID", "AccessionNumber", "StudyInstanceUID", "RequestedProcedureID",
    "ScheduledProcedureStepSequence[0].ScheduledStationAETitle",
    "ScheduledProcedureStepSequence[0].Modality",
    "ScheduledProcedureStepSequence[0].ScheduledProcedureStepStartDate",
    "ScheduledProcedureStepSequence[0].ScheduledProcedureStepStartTime",
    "ScheduledProcedureStepSequence[0].ScheduledPerformingPhysicianName",
    "ScheduledProcedureStepSequence[0].ScheduledProcedureStepID",
]


def item_dump(patient, pid, station, modality, date, tm, physician, accession):
    return f"""(0008,0005) CS [ISO_IR 100]
(0008,0050) SH [{accession}]
(0010,0010) PN [{patient}]
(0010,0020) LO [{pid}]
(0020,000d) UI [1.2.826.0.1.3680043.2.1125.{pid[1:]}]
(0032,1060) LO [Procedure of {pid}]
(0040,0100) SQ (Sequence with explicit length #=1)
  (fffe,e000) na (Item with explicit length #=7)
    (0008,0060) CS [{modality}]
    (0040,0001) AE [{station}]
    (0040,0002) DA [{date}]
    (0040,0003) TM [{tm}]
    (0040,0006) PN [{physician}]
    (0040,0007) LO [Step of {pid}]
    (0040,0009) SH [SPS{pid}]
  (fffe,e00d) na (ItemDelimitationItem for re-encoding)
(fffe,e0dd) na (SequenceDelimitationItem for re-encoding)
(0040,1001) SH [RP{pid}]
"""


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_for(port):
    for _ in range(100):
        with socket.socket() as s:
            if s.connect_ex(("127.0.0.1", port)) == 0:
                return
        time.sleep(0.1)
    raise SystemExit(f"nothing listens on {port}")


def normalized_dumps(directory):
    """The dcmdump text of each response file, without offsets and lengths."""
    dumps = []
    for name in sorted(os.listdir(directory)):
        text = subprocess.run(["dcmdump", "-q", os.path.join(directory, name)], capture_output=True, text=True,
                              check=True).stdout
        lines = []
        for line in text.splitlines():
            if line.startswith("#") or not line.strip():
                continue
            # The File Meta Information is written by findscu. Specific
            # Character Set: DcmServer returns the item's, wlmscpfs only when
            # requested; both are allowed (PS3.4 K.4.1.1.3.2).
            if line.startswith("(0002,") or line.startswith("(0008,0005)"):
                continue
            # Drop the length and VM columns, and explicit sequence lengths.
            line = re.sub(r"\s+#\s*\d+,\s*\d+\s+\S+$", "", line)
            line = re.sub(r"\(Sequence with (explicit|undefined) length #=(\d+)\)", r"(Sequence #=\2)", line)
            line = re.sub(r"\(Item with (explicit|undefined) length #=(\d+)\)", r"(Item #=\2)", line)
            lines.append(line.rstrip())
        dumps.append("\n".join(lines))
    return sorted(dumps)


def with_return_keys(keys):
    """The keys, then the return keys they do not set (a later -k replaces
    an earlier one)."""
    given = {key.split("=")[0] for key in keys}
    return keys + [key for key in RETURN_KEYS if key not in given]


def findscu(port, keys, out):
    os.makedirs(out)
    args = ["findscu", "-W", "-aec", "WORKLIST", "-X", "-od", out, "127.0.0.1", str(port)]
    for key in with_return_keys(keys):
        args += ["-k", key]
    subprocess.run(args, check=True, capture_output=True)
    return normalized_dumps(out)


def dcmfind(build, port, keys):
    args = [os.path.join(build, "DcmFind"), "WORKLIST", "127.0.0.1", str(port), "-m", "worklist"]
    for key in with_return_keys(keys):
        args += ["-k", key]
    output = subprocess.run(args, check=True, capture_output=True, text=True).stdout
    return sorted(re.findall(r"\(0010,0020\) PatientID: (\S*)", output))


def main():
    build = os.path.abspath(sys.argv[1])
    work = tempfile.mkdtemp(prefix="dcmswift-worklist-")
    items = os.path.join(work, "WORKLIST")
    os.makedirs(items)
    # wlmscpfs locks this file while it reads the directory.
    open(os.path.join(items, "lockfile"), "w").close()
    for index, item in enumerate(ITEMS):
        dump = os.path.join(work, f"item{index}.dump")
        with open(dump, "w") as f:
            f.write(item_dump(*item))
        subprocess.run(["dump2dcm", "-q", dump, os.path.join(items, f"item{index}.wl")], check=True)

    dcmtk_port, swift_port = free_port(), free_port()
    servers = [
        subprocess.Popen(["wlmscpfs", "-dfp", work, str(dcmtk_port)], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL),
        subprocess.Popen([os.path.join(build, "DcmServer"), "-a", "WORKLIST", "--host", "127.0.0.1",
                          "-p", str(swift_port), "--worklist-directory", items], stdout=subprocess.DEVNULL),
    ]
    differences = 0
    try:
        wait_for(dcmtk_port)
        wait_for(swift_port)
        for index, (name, keys) in enumerate(QUERIES.items()):
            reference = findscu(dcmtk_port, keys, os.path.join(work, f"q{index}-dcmtk"))
            served = findscu(swift_port, keys, os.path.join(work, f"q{index}-dcmswift"))
            ids = sorted(re.findall(r"\(0010,0020\) LO \[(\S*)\]", "\n".join(reference)))
            found = dcmfind(build, dcmtk_port, keys)
            status = "OK"
            if reference != served:
                status = "DIFFERENT RESPONSES"
                differences += 1
            elif ids != found:
                status = f"DcmFind found {found}"
                differences += 1
            print(f"{name:24} {len(reference)} match(es) {ids}: {status}")
            if reference != served and "-v" in sys.argv:
                print("--- wlmscpfs\n" + "\n\n".join(reference) + "\n--- DcmServer\n" + "\n\n".join(served))
    finally:
        for server in servers:
            server.terminate()
            server.wait()
    print(f"{len(QUERIES)} queries, {differences} difference(s); work files in {work}")
    sys.exit(1 if differences else 0)


if __name__ == "__main__":
    main()
