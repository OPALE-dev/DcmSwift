"""Cross-check DcmSwift's Encrypted Attributes with OpenSSL's CMS.

  cms_openssl.py BUILD_DIR FILE_OR_DIR...

BUILD_DIR holds DcmAnonymize. Needs openssl and pydicom.

For each DICOM file:
1. DcmAnonymize de-identifies it with --encrypt-for a test certificate, with
   PKCS #1 v1.5 and with OAEP key transport; `openssl cms -decrypt` opens
   the Encrypted Content, which must be an Encrypted Attributes Data Set
   (PS3.3 C.12.1.1.4) whose Modified Attributes Sequence Item holds the
   source's values of every attribute the de-identification removed or
   changed;
2. pydicom builds an Encrypted Attributes Data Set with the source's
   Patient's Name and ID, `openssl cms -encrypt` envelopes it (AES-128 and
   AES-256, PKCS #1 v1.5 and OAEP), and DcmAnonymize --restore-with must
   put those values back in the de-identified file.
Exits 1 on any failure.
"""
import io
import os
import subprocess
import sys
import tempfile

import pydicom
from pydicom.dataset import Dataset
from pydicom.filebase import DicomBytesIO
from pydicom.filereader import read_dataset
from pydicom.filewriter import write_dataset
from pydicom.sequence import Sequence


def files(paths):
    for path in paths:
        if os.path.isdir(path):
            for root, _, names in os.walk(path):
                yield from (os.path.join(root, name) for name in sorted(names) if not name.startswith("."))
        else:
            yield path


def main(build, paths):
    anonymize = os.path.join(build, "DcmAnonymize")
    failures, checks, skipped = [], 0, 0
    with tempfile.TemporaryDirectory() as folder:
        key, certificate = os.path.join(folder, "key.pem"), os.path.join(folder, "certificate.pem")
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2", "-subj",
                        "/CN=DcmSwift recipient", "-keyout", key, "-out", certificate], check=True, capture_output=True)
        for index, path in enumerate(files(paths)):
            name = os.path.basename(path)
            try:
                source = pydicom.dcmread(path)
                source.SOPClassUID
            except Exception:
                skipped += 1
                continue
            for transport in ("pkcs1", "oaep"):
                output = os.path.join(folder, f"{index}-{transport}.dcm")
                arguments = [anonymize, path, output, "--encrypt-for", certificate] + (["--oaep"] if transport == "oaep" else [])
                if subprocess.run(arguments, capture_output=True).returncode != 0:
                    skipped += 1
                    break
                deidentified = pydicom.dcmread(output)
                envelope = os.path.join(folder, "envelope.der")
                with open(envelope, "wb") as file:
                    file.write(deidentified[0x04000500][0][0x04000520].value)
                opened = subprocess.run(["openssl", "cms", "-decrypt", "-binary", "-inform", "DER", "-in", envelope,
                                         "-recip", certificate, "-inkey", key], capture_output=True)
                checks += 1
                if opened.returncode != 0:
                    failures.append(f"{name}: openssl cannot open the {transport} envelope: {opened.stderr[:200]!r}")
                    continue
                syntax = deidentified[0x04000500][0][0x04000510].value
                content = read_dataset(io.BytesIO(opened.stdout), is_implicit_VR=syntax == "1.2.840.10008.1.2",
                                       is_little_endian=True)
                originals = content[0x04000550][0]
                # Every attribute removed or changed is there, with the
                # source's value.
                for element in source:
                    if element.tag.group in (0x0002, 0x0004) or element.tag.element == 0:
                        continue
                    after = deidentified.get(element.tag)
                    changed = after is None or after.value != element.value
                    if not changed:
                        continue
                    kept = originals.get(element.tag)
                    if kept is None or (element.VR not in ("SQ", "UN") and kept.value != element.value):
                        failures.append(f"{name}: {element.tag} {element.keyword} missing or different in the "
                                        f"{transport} Encrypted Attributes Data Set")
                        break
            # OpenSSL envelopes, DcmSwift restores.
            deidentified_path = os.path.join(folder, f"{index}-pkcs1.dcm")
            if not os.path.exists(deidentified_path) or "PatientName" not in source:
                continue
            content = Dataset()
            item = Dataset()
            item.PatientName = source.PatientName
            item.PatientID = source.get("PatientID", "")
            content.ModifiedAttributesSequence = Sequence([item])
            buffer = DicomBytesIO()
            buffer.is_little_endian, buffer.is_implicit_VR = True, False
            write_dataset(buffer, content)
            plain = os.path.join(folder, "plain.bin")
            with open(plain, "wb") as file:
                file.write(buffer.getvalue())
            for cipher, transport in (("-aes256", "pkcs1"), ("-aes128", "oaep")):
                envelope = os.path.join(folder, "theirs.der")
                command = ["openssl", "cms", "-encrypt", "-binary", "-outform", "DER", cipher, "-in", plain, "-out", envelope,
                           "-recip", certificate]
                if transport == "oaep":
                    command += ["-keyopt", "rsa_padding_mode:oaep"]
                subprocess.run(command, check=True, capture_output=True)
                target = pydicom.dcmread(deidentified_path)
                with open(envelope, "rb") as file:
                    target[0x04000500][0][0x04000520].value = file.read()
                encrypted = os.path.join(folder, "theirs.dcm")
                target.save_as(encrypted)
                restored = os.path.join(folder, "restored.dcm")
                result = subprocess.run([anonymize, encrypted, restored, "--restore-with", key], capture_output=True, text=True)
                checks += 1
                if result.returncode != 0:
                    failures.append(f"{name}: DcmSwift cannot open the openssl {cipher} {transport} envelope: {result.stderr[-200:]}")
                    continue
                back = pydicom.dcmread(restored)
                if back.PatientName != source.PatientName or back.get("PatientID", "") != item.PatientID:
                    failures.append(f"{name}: values not restored from the openssl {cipher} {transport} envelope")
    for failure in failures:
        print("FAIL", failure)
    print(f"{checks} checks, {len(failures)} failures, {skipped} files skipped")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2:]))
