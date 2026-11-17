"""Cross-check DcmSwift's Digital Signatures with DCMTK's dcmsign.

  dcmsign.py BUILD_DIR FILE_OR_DIR...

BUILD_DIR holds DcmSign. Needs DCMTK (dcmsign, dcmodify) and openssl.

For each DICOM file:
1. DcmSign signs it with SHA-256, SHA-384, and SHA-512, and dcmsign
   verifies the signatures, trusting the test certificate;
2. dcmsign signs it with RIPEMD-160 (its default), SHA-1, and SHA-256, and
   DcmSign verifies the signatures;
3. dcmsign signs the first Item of its first Sequence, if any, and DcmSign
   verifies that signature;
4. a signed Data Element of the dcmsign-signed file is changed with
   dcmodify, and both tools must find the signature invalid.
When dcmsign and DcmSwift disagree, a third reading of PS3.3 C.12.1.1.3 in
this script, built on pydicom, computes the MAC of the signed file, and the
digest inside the signature is recovered with openssl: a signature whose
digest the reference finds is right. DcmSwift is wrong when the reference
sides with dcmsign; otherwise the difference is dcmsign's, and is counted.
Files dcmsign or DcmSwift cannot read are counted and skipped. Exits 1 when
DcmSwift is wrong.
"""
import os
import subprocess
import sys
import tempfile

import hashlib

import pydicom
import pydicom.datadict
import pydicom.encaps
from pydicom.filebase import DicomBytesIO
from pydicom.filewriter import write_data_element
from pydicom.tag import Tag

HASHES = {"RIPEMD160": "ripemd160", "SHA1": "sha1", "SHA256": "sha256", "SHA384": "sha384", "SHA512": "sha512"}


def signable(element):
    tag = element.tag
    return not (tag.element == 0 or tag.group < 8 or tag.group == 0xFFFA or tag == Tag(0x4FFE0001)
                or tag == Tag(0xFFFCFFFC) or element.VR == "UN")


def encode(container, tag, out):
    """C.12.1.1.3.1.2: Explicit VR Little Endian, from the raw bytes of the
    Value; Sequences and encapsulated Pixel Data without lengths, with Item
    tags and a Sequence Delimitation tag."""
    raw = container.get_item(tag)
    head = tag.group.to_bytes(2, "little") + tag.element.to_bytes(2, "little")
    vr = raw.VR or pydicom.datadict.dictionary_VR(tag)
    vr = vr.split(" or ")[0]
    if vr == "SQ":
        out += head + b"SQ\x00\x00"
        for item in container[tag].value:
            out += bytes([0xFE, 0xFF, 0x00, 0xE0])
            for child in list(item.keys()):
                if signable(item[child]):
                    encode(item, child, out)
        out += bytes([0xFE, 0xFF, 0xDD, 0xE0])
        return
    value = raw.value if isinstance(raw.value, bytes) else None
    if value is None:
        # Created or decoded by pydicom: encode it as pydicom does.
        buffer = DicomBytesIO()
        buffer.is_little_endian, buffer.is_implicit_VR = True, False
        write_data_element(buffer, container[tag])
        out += buffer.getvalue()
        return
    if tag == Tag(0x7FE00010) and raw.length == 0xFFFFFFFF:
        out += head + b"OB\x00\x00"
        for fragment in pydicom.encaps.generate_fragments(value):
            out += bytes([0xFE, 0xFF, 0x00, 0xE0]) + fragment
        out += bytes([0xFE, 0xFF, 0xDD, 0xE0])
        return
    if vr in ("OB", "OD", "OF", "OL", "OV", "OW", "SV", "UC", "UN", "UR", "UT", "UV"):
        out += head + vr.encode() + b"\x00\x00" + len(value).to_bytes(4, "little") + value
    else:
        out += head + vr.encode() + len(value).to_bytes(2, "little") + value


def as_list(value):
    """A value of VM 1 or more as a list: AT values of VM 1 are one tag."""
    return [value] if isinstance(value, int) else list(value)


def reference_says_valid(path, certificate):
    """Whether the digest in the (first) signature is the reference MAC."""
    dataset = pydicom.dcmread(path)
    parameters, signature = dataset[0x4FFE0001][0], dataset[0xFFFAFFFA][0]
    tags = as_list(parameters[0x04000020].value)
    out = bytearray()
    for tag in tags:
        encode(dataset, Tag(tag), out)
    for tag in list(signature.keys()):
        if tag not in (Tag(0x04000115), Tag(0x04000120), Tag(0x04000305), Tag(0x04000310)):
            encode(signature, tag, out)
    digest = hashlib.new(HASHES[parameters[0x04000015].value], bytes(out)).digest()
    with tempfile.NamedTemporaryFile(delete=False) as file:
        file.write(signature[0x04000120].value)
    recovered = subprocess.run(["openssl", "pkeyutl", "-verifyrecover", "-certin", "-inkey", certificate, "-in", file.name,
                                "-pkeyopt", "rsa_padding_mode:pkcs1"], capture_output=True).stdout
    os.unlink(file.name)
    return recovered.endswith(digest)


def run(*arguments):
    return subprocess.run(list(arguments), capture_output=True, text=True, timeout=300)


def files(paths):
    for path in paths:
        if os.path.isdir(path):
            for root, _, names in os.walk(path):
                yield from (os.path.join(root, name) for name in sorted(names) if not name.startswith("."))
        else:
            yield path


def main(build, paths):
    dcmsign = os.path.join(build, "DcmSign")
    failures, checks, skipped, dcmtk_differs = [], 0, 0, []
    with tempfile.TemporaryDirectory() as folder:
        key, certificate = os.path.join(folder, "key.pem"), os.path.join(folder, "certificate.pem")
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2", "-subj",
                        "/CN=DcmSwift crosscheck", "-keyout", key, "-out", certificate], check=True, capture_output=True)
        for index, path in enumerate(files(paths)):
            name = os.path.basename(path)
            try:
                dataset = pydicom.dcmread(path)
            except Exception:
                skipped += 1
                continue
            if "SOPClassUID" not in dataset:
                skipped += 1
                continue
            stem = os.path.join(folder, str(index))
            # 1. DcmSwift signs, dcmsign verifies.
            for algorithm in ("SHA256", "SHA384", "SHA512"):
                signed = f"{stem}-ours-{algorithm}.dcm"
                result = run(dcmsign, path, "--key", key, "--certificate", certificate, "--algorithm", algorithm,
                             "--output", signed)
                if result.returncode != 0:
                    skipped += 1
                    break
                verified = run("dcmsign", "--verify", "+rg", "+cf", certificate, signed)
                checks += 1
                if verified.returncode != 0 or "Signature Verification : OK" not in verified.stdout + verified.stderr:
                    if reference_says_valid(signed, certificate):
                        dcmtk_differs.append(f"{name}: dcmsign rejects a DcmSwift {algorithm} signature the reference accepts")
                    else:
                        failures.append(f"{name}: dcmsign and the reference reject the DcmSwift {algorithm} signature")
            # 2. dcmsign signs, DcmSwift verifies.
            theirs = None
            for option, algorithm in (("+mr", "RIPEMD160"), ("+ms", "SHA1"), ("+m2", "SHA256")):
                signed = f"{stem}-theirs-{algorithm}.dcm"
                if run("dcmsign", "-pw", option, "--sign", key, certificate, path, signed).returncode != 0:
                    continue
                theirs = theirs or signed
                verified = run(dcmsign, signed)
                checks += 1
                if verified.returncode != 0 or f"{algorithm} valid" not in verified.stdout:
                    if reference_says_valid(signed, certificate):
                        failures.append(f"{name}: DcmSwift rejects a dcmsign {algorithm} signature the reference accepts")
                    else:
                        dcmtk_differs.append(f"{name}: dcmsign signs a {algorithm} MAC the reference does not find")
            # 3. A Sequence Item signed by dcmsign.
            sequence = next((element for element in dataset if element.VR == "SQ" and element.value
                             and not element.tag.is_private and element.tag.group not in (0x4FFE, 0xFFFA)), None)
            if sequence is not None:
                signed = f"{stem}-item.dcm"
                location = f"{sequence.keyword or f'({sequence.tag.group:04x},{sequence.tag.element:04x})'}[0]"
                if run("dcmsign", "-pw", "+m2", "--sign-item", key, certificate, location, path, signed).returncode == 0:
                    verified = run(dcmsign, signed)
                    checks += 1
                    item_tag = f"{sequence.tag.group:04X}{sequence.tag.element:04X}"
                    if verified.returncode != 0 or f"{item_tag} SHA256 valid" not in verified.stdout:
                        failures.append(f"{name}: Item signature at {location}: {verified.stdout.strip()}")
            # 4. Tampering is detected by both.
            if theirs:
                changed = f"{stem}-changed.dcm"
                with open(theirs, "rb") as source, open(changed, "wb") as target:
                    target.write(source.read())
                # Change a signed attribute with a text value.
                signed_dataset = pydicom.dcmread(theirs)
                tags = signed_dataset[0x4FFE0001][0][0x04000020].value
                target = next((Tag(t) for t in as_list(tags)
                               if signed_dataset[t].VR in ("CS", "LO", "SH", "UI", "DA", "TM", "PN", "IS", "DS")
                               and signed_dataset[t].value not in (None, "")), None)
                if target is None:
                    continue
                run("dcmodify", "-nb", "-m", f"({target.group:04x},{target.element:04x})=1", changed)
                ours, dcmtk = run(dcmsign, changed), run("dcmsign", "--verify", "+cf", certificate, changed)
                checks += 1
                if "invalid" not in ours.stdout or ours.returncode == 0:
                    failures.append(f"{name}: DcmSwift accepts a changed file: {ours.stdout.strip()}")
                if dcmtk.returncode == 0:
                    failures.append(f"{name}: dcmsign accepts a changed file")
    for difference in dcmtk_differs:
        print("DCMTK", difference)
    for failure in failures:
        print("FAIL", failure)
    print(f"{checks} checks, {len(failures)} failures, {len(dcmtk_differs)} where dcmsign differs from the reference, "
          f"{skipped} files skipped")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2:]))
