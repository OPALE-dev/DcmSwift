"""Cross-check the PS3.16 template documents DcmSwift makes with DCMTK.

  sr_templates.py

Runs DcmSwiftReportTemplateTests/testExportTemplateDocuments with
DCMSWIFT_SR_EXPORT set to a new temporary folder, then, for each document
(TID 2000, TID 2010, TID 10011):

1. DCMTK's dsrdump reads it with relationship content constraints checked
   (the default) and prints its template identification: no error or
   warning is allowed, and the template must be DCMR with the expected number.
   Two warnings state DCMTK limits and are accepted: its VR checker does not
   support UTF-8 (ISO_IR 192), and it does not check KO template constraints.
2. pydicom, when installed, reads the file and finds the SOP Class and the
   Content Template Sequence.
Exits 1 on any failure. Needs DCMTK on the PATH; pydicom is optional.
"""
import os
import shutil
import subprocess
import sys
import tempfile

ACCEPTED = {"W: The VR checker does not support this Specific Character Set: ISO_IR 192",
            "W: Check for template constraints not yet supported"}
EXPECTED = {"tid2000": ("1.2.840.10008.5.1.4.1.1.88.11", "2000"),
            "tid2010": ("1.2.840.10008.5.1.4.1.1.88.59", "2010"),
            "tid10011": ("1.2.840.10008.5.1.4.1.1.88.67", "10011")}


def main():
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    folder = tempfile.mkdtemp(prefix="dcmswift-sr-templates-")
    failures = []
    try:
        env = dict(os.environ, DCMSWIFT_SR_EXPORT=folder)
        test = subprocess.run(["swift", "test", "--skip-build", "--filter",
                               "DcmSwiftReportTemplateTests/testExportTemplateDocuments"],
                              cwd=root, env=env, capture_output=True, text=True)
        if test.returncode != 0:
            print(test.stdout[-3000:], test.stderr[-3000:])
            return 1
        try:
            import pydicom
        except ImportError:
            pydicom = None
        for name, (sop_class, template) in EXPECTED.items():
            path = os.path.join(folder, name + ".dcm")
            dump = subprocess.run(["dsrdump", "+Pt", path], capture_output=True, text=True)
            noise = [line for line in (dump.stdout + dump.stderr).splitlines()
                     if line.strip().startswith(("W:", "E:", "F:")) and line.strip() not in ACCEPTED]
            ok = dump.returncode == 0 and not noise and f"# TID {template} (DCMR)" in dump.stdout
            print(f"{name}: dsrdump {'ok' if ok else 'FAILED'}")
            if not ok:
                failures.append(name)
                print(dump.stdout[:3000], dump.stderr[:3000])
            if pydicom:
                data = pydicom.dcmread(path)
                found = (str(data.SOPClassUID), str(data.ContentTemplateSequence[0].TemplateIdentifier))
                print(f"{name}: pydicom {found}")
                if found != (sop_class, template):
                    failures.append(name + " pydicom")
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if failures:
        print("FAILED:", ", ".join(failures))
        return 1
    print("all template documents pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
