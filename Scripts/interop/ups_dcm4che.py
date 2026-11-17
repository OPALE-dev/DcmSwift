"""Independent UPS DIMSE checks using dcm4che upsscu (no Python DICOM library).

Usage: python3 ups_dcm4che.py /path/to/dcm4che/bin/upsscu PORT [NOTIFY_PORT]
DcmServer must use --aet UPSSCP --ups-directory DIR and, to check events,
--ups-notify WATCHER=127.0.0.1:NOTIFY_PORT. Start with a fresh DIR.
The supplied dcm4che create.xml contains historical tags and missing Type 2
attributes; this script builds an explicit 2026d Native DICOM Model fixture.
"""
import pathlib
import re
import socket
import subprocess
import sys
import tempfile
import time
import uuid
import xml.etree.ElementTree as ET


def main(tool, port, notify_port):
    uid = "2.25." + str(uuid.uuid4().int)
    token = "2.25." + str(uuid.uuid4().int)
    base = [tool, "-c", f"UPSSCP@127.0.0.1:{port}"]

    def run(operation, expected=0, *options):
        result = subprocess.run(base + ["-O", operation] + list(options), capture_output=True,
                                text=True, timeout=30)
        output = result.stdout + result.stderr
        statuses = [int(x, 16) for x in re.findall(r"status=([0-9a-fA-F]+)H", output)]
        if result.returncode != 0 or not statuses or statuses[-1] != expected:
            raise AssertionError(f"{operation}: expected {expected:04X}\n{output}")
        print(f"OK {operation}: {expected:04X}", flush=True)
        return output

    with tempfile.TemporaryDirectory(prefix="dcmswift-ups-dcm4che-") as folder:
        root = ET.Element("NativeDicomModel")
        attributes = {
            "00741200": ("CS", "MEDIUM"), "00741204": ("LO", "Read"),
            "00404005": ("DT", "20261021190000+0200"), "00404041": ("CS", "READY"),
            "00741000": ("CS", "SCHEDULED"), "00081195": ("UI", None), "00741202": ("LO", None),
            "00400400": ("LT", None), "00100010": ("PN", None), "00100020": ("LO", None),
            "00100021": ("LO", None), "00100030": ("DA", None), "00100040": ("CS", None),
            "00380010": ("LO", None), "00081080": ("LO", None),
        }
        for tag in ["00741210", "00404025", "00404026", "00404027", "00404018", "00404021",
                    "00100024", "00101002", "00380014", "00081084", "0040A370", "00741002", "00741216"]:
            attributes[tag] = ("SQ", None)
        for tag, (vr, text) in sorted(attributes.items()):
            attribute = ET.SubElement(root, "DicomAttribute", tag=tag, vr=vr)
            if text is not None:
                ET.SubElement(attribute, "Value", number="1").text = text
        fixture = pathlib.Path(folder) / "scheduled.xml"
        ET.ElementTree(root).write(fixture, encoding="utf-8", xml_declaration=True)
        receiver = None
        event_log = open(pathlib.Path(folder) / "events.log", "w+")
        try:
            if notify_port:
                receiver = subprocess.Popen(base + ["-b", f"WATCHER:{notify_port}", "-O", "receive"],
                                            stdout=event_log, stderr=subprocess.STDOUT)
                for _ in range(100):
                    try:
                        with socket.create_connection(("127.0.0.1", notify_port), timeout=0.1):
                            break
                    except OSError:
                        time.sleep(0.1)
                else:
                    raise RuntimeError("upsscu receiver did not start")
            run("create", 0, "-u", uid, "--", str(fixture))
            run("create", 0x0111, "-u", uid, "--", str(fixture))
            if notify_port:
                run("subscribe", 0, "-u", uid, "--receiving-ae", "WATCHER", "-l")
            run("get", 0, "-u", uid, "-p", "-r", "ProcedureStepState")
            run("changeState", 0, "-u", uid, "-P", token)
            run("changeState", 0xC301, "-u", uid, "-D", "2.25.999")
            run("changeState", 0xC304, "-u", uid, "-C", token)
            run("requestCancel", 0, "-u", uid, "--reason", "Please stop")
            # N-ACTION requestCancel only notifies; the owner sets its final data.
            run("update", 0, "-u", uid, "-s", f"TransactionUID={token}",
                "-s", "ProcedureStepProgressInformationSequence.ProcedureStepDiscontinuationReasonCodeSequence.CodeValue=110513",
                "-s", "ProcedureStepProgressInformationSequence.ProcedureStepDiscontinuationReasonCodeSequence.CodingSchemeDesignator=DCM",
                "-s", "ProcedureStepProgressInformationSequence.ProcedureStepDiscontinuationReasonCodeSequence.CodeMeaning=Discontinued")
            run("changeState", 0, "-u", uid, "-D", token)
            run("get", 0, "-u", uid, "-w", "-r", "ProcedureStepProgressInformationSequence")
            run("changeState", 0xB304, "-u", uid, "-D", token)
            if notify_port:
                run("unsubscribe", 0, "-u", uid, "--receiving-ae", "WATCHER")
                event_log.flush()
                event_log.seek(0)
                events = event_log.read()
                for event_type in [1, 2, 3]:
                    if not re.search(rf"eventID={event_type}", events):
                        raise AssertionError(f"missing dcm4che event {event_type}\n{events}")
                print("OK dcm4che receives UPS Push commands on UPS Event context (types 1, 2, 3)", flush=True)
        finally:
            if receiver:
                receiver.terminate()
                try:
                    receiver.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    receiver.kill()
                    receiver.wait()
            event_log.close()


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]), int(sys.argv[3]) if len(sys.argv) > 3 else None)
