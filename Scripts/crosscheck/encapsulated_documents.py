"""Cross-check DcmSwift's Encapsulated Documents with DCMTK and dicom-validator.

  encapsulated_documents.py BUILD_DIR STANDARD_DIR

BUILD_DIR holds DcmDocument and DcmValidate; STANDARD_DIR is the -src folder
of dicom-validator's validate_iods (on the PATH). Needs DCMTK (pdf2dcm,
cda2dcm, stl2dcm, dcmencap, dcmdecap).

For a PDF, a CDA, a binary STL, an OBJ, and an MTL document made here:
1. DcmDocument wraps it; DcmValidate and dicom-validator find no error, and
   dcmdecap extracts the same bytes;
2. DCMTK wraps it; DcmDocument extracts the same bytes.
Exits 1 on any failure.
"""
import os
import struct
import subprocess
import sys
import tempfile

PDF = (b"%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n"
       b"3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n")
CDA = (b'<?xml version="1.0"?>\n<ClinicalDocument xmlns="urn:hl7-org:v3"><id root="2.16.840.1.113883.19" '
       b'extension="c266"/><title>Report</title></ClinicalDocument>\n')
OBJ = b"v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n"
MTL = b"newmtl m\nKd 1 0 0\n"


def stl():
    triangles = [((0, 0, 1), (0, 0, 0), (1, 0, 0), (0, 1, 0)), ((0, 0, -1), (0, 0, 0), (0, 1, 0), (1, 0, 0))]
    data = b"binary stl".ljust(80, b" ") + struct.pack("<I", len(triangles))
    for normal, a, b, c in triangles:
        data += struct.pack("<12fH", *normal, *a, *b, *c, 0)
    return data


DOCUMENTS = {"report.pdf": (PDF, ["pdf2dcm"]), "report.xml": (CDA, ["cda2dcm"]), "model.stl": (stl(), ["stl2dcm"]),
             "model.obj": (OBJ, ["dcmencap", "+fo"]), "model.mtl": (MTL, ["dcmencap", "+fm"])}


def run(*arguments):
    return subprocess.run(list(arguments), capture_output=True, text=True, timeout=120)


def main(build, standard):
    failures = []
    with tempfile.TemporaryDirectory() as folder:
        for name, (content, dcmtk) in DOCUMENTS.items():
            source = os.path.join(folder, name)
            with open(source, "wb") as file:
                file.write(content)
            wrapped = source + ".dcm"
            if run(os.path.join(build, "DcmDocument"), "wrap", source, wrapped).returncode != 0:
                failures.append(f"{name}: DcmDocument cannot wrap it")
                continue
            validation = run(os.path.join(build, "DcmValidate"), wrapped)
            if validation.returncode != 0:
                failures.append(f"{name}: DcmValidate: {validation.stdout.strip()}")
            oracle = run("validate_iods", "-src", standard, "-r", "2026d", wrapped)
            errors = [line for line in oracle.stdout.splitlines() if "missing" in line or "unexpected" in line
                      or "invalid value" in line or "not allowed" in line]
            if errors or oracle.returncode != 0:
                failures.append(f"{name}: dicom-validator: {errors or oracle.stdout.strip()[-300:]}")
            extracted = source + ".dcmdecap"
            run("dcmdecap", wrapped, extracted)
            if not os.path.exists(extracted) or open(extracted, "rb").read() != content:
                failures.append(f"{name}: dcmdecap does not extract the document DcmDocument wrapped")
            made = source + ".dcmtk.dcm"
            run(*dcmtk, source, made)
            back = source + ".back"
            if run(os.path.join(build, "DcmDocument"), "extract", made, back).returncode != 0 \
                    or open(back, "rb").read() != content:
                failures.append(f"{name}: DcmDocument does not extract the document {dcmtk[0]} wrapped")
    for failure in failures:
        print("FAIL", failure)
    print(f"{len(DOCUMENTS)} documents, {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
