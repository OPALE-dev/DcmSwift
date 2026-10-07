#!/usr/bin/env python3
"""Generate DcmSwift's Specific Character Set mapping tables.

DcmSwift decodes every DICOM character set (PS3.3 C.12.1.1.2, PS3.5 6.1)
with its own tables so that macOS, iOS, and Linux behave identically,
independently of the platform's Foundation and iconv/ICU builds.

Sources:
- Single-byte G1 sets and the ISO 2022 multi-byte sets (JIS X 0208,
  JIS X 0212, KS X 1001, GB 2312) come from the CPython codecs, which follow
  the national standards' Unicode mappings and leave unassigned code points
  unmapped. Vendor extensions (NEC row 13, private-use fillers) are excluded.
- GB18030 (and GBK, its one- and two-byte subset) comes from the system ICU
  library (macOS libicucore, ICU >= 73), which implements GB18030-2022.

The script must run on macOS for the GB18030 tables. It refuses to write
tables that map a multi-byte code to a DICOM delimiter or Control Character.

Usage: Scripts/generate-character-set-tables.py [--check]
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Sources/DcmSwift/Resources/CharacterSets"
SWIFT_TABLES = ROOT / "Sources/DcmSwift/Foundation/CharacterSets/DICOMSingleByteTables.swift"

# DICOM delimiters (value, PN component, PN group) and Control Characters
# must never be produced by a multi-byte code.
FORBIDDEN = {0x5C, 0x5E, 0x3D} | set(range(0x00, 0x20)) | {0x7F}

# Defined Term -> (Swift identifier, codec) for 96/94-character G1 sets
# invoked in GR (bytes A0H-FFH).
SINGLE_BYTE = [
    ("ISO_IR 100", "isoIR100", "iso8859_1"),
    ("ISO_IR 101", "isoIR101", "iso8859_2"),
    ("ISO_IR 109", "isoIR109", "iso8859_3"),
    ("ISO_IR 110", "isoIR110", "iso8859_4"),
    ("ISO_IR 144", "isoIR144", "iso8859_5"),
    ("ISO_IR 127", "isoIR127", "iso8859_6"),
    ("ISO_IR 126", "isoIR126", "iso8859_7"),
    ("ISO_IR 138", "isoIR138", "iso8859_8"),
    ("ISO_IR 148", "isoIR148", "iso8859_9"),
    ("ISO_IR 203", "isoIR203", "iso8859_15"),
    ("ISO_IR 166", "isoIR166", "tis_620"),
]


def single_byte_table(codec: str) -> list[int]:
    table = []
    for byte in range(0xA0, 0x100):
        try:
            text = bytes([byte]).decode(codec)
        except UnicodeDecodeError:
            table.append(0)
            continue
        assert len(text) == 1 and ord(text) >= 0xA0, (codec, hex(byte), text)
        table.append(ord(text))
    return table


def katakana_table() -> list[int]:
    """JIS X 0201 katakana (ISO-IR 13) in GR."""
    table = []
    for byte in range(0xA0, 0x100):
        if 0xA1 <= byte <= 0xDF:
            scalar = 0xFF61 + byte - 0xA1
            assert bytes([byte]).decode("shift_jis") == chr(scalar)
            table.append(scalar)
        else:
            table.append(0)
    return table


def ninety_four_squared(make, codec: str) -> list[int]:
    """Row-major 94x94 table for GL codes 2121H-7E7EH; 0 means unmapped."""
    table = []
    for row in range(0x21, 0x7F):
        for cell in range(0x21, 0x7F):
            try:
                text = make(row, cell).decode(codec)
            except UnicodeDecodeError:
                table.append(0)
                continue
            if len(text) != 1:
                table.append(0)
                continue
            scalar = ord(text)
            assert scalar not in FORBIDDEN and scalar <= 0xFFFF, (codec, hex(row), hex(cell))
            table.append(scalar)
    return table


class ICU:
    def __init__(self) -> None:
        self.lib = ctypes.CDLL("/usr/lib/libicucore.A.dylib")
        self.lib.ucnv_open.restype = ctypes.c_void_p
        self.lib.ucnv_open.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
        self.lib.ucnv_reset.argtypes = [ctypes.c_void_p]
        self.lib.ucnv_toUChars.restype = ctypes.c_int32
        self.lib.ucnv_toUChars.argtypes = [
            ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int32,
            ctypes.c_char_p, ctypes.c_int32, ctypes.POINTER(ctypes.c_int),
        ]
        version = ctypes.create_string_buffer(4)
        self.lib.u_getVersion(version)
        self.version = ".".join(str(part) for part in version.raw[:2])
        if int(version.raw[0]) < 73:
            sys.exit(f"ICU {self.version} predates GB18030-2022 (ICU >= 73 required)")
        error = ctypes.c_int(0)
        self.converter = self.lib.ucnv_open(b"gb18030", ctypes.byref(error))
        assert error.value <= 0, error.value

    def decode(self, data: bytes) -> str | None:
        self.lib.ucnv_reset(self.converter)
        output = (ctypes.c_uint16 * 8)()
        error = ctypes.c_int(0)
        count = self.lib.ucnv_toUChars(
            self.converter, output, 8, data, len(data), ctypes.byref(error)
        )
        if error.value > 0:
            return None
        text = b"".join(unit.to_bytes(2, "little") for unit in output[:count]).decode("utf-16-le")
        # ICU substitutes U+FFFD, or SUB (1AH) for some illegal sequences.
        # 8431A437H is the genuine GB18030 encoding of U+FFFD.
        substituted = ("�" in text and data != b"\x84\x31\xa4\x37") or (
            "\x1a" in text and b"\x1a" not in data
        )
        return None if substituted else text


def gb18030_tables(icu: ICU) -> tuple[list[int], list[int]]:
    for byte in range(0x80):
        assert icu.decode(bytes([byte])) == chr(byte)
    # ICU decodes the single byte 80H as EURO SIGN for Windows code page 936
    # compatibility. GB18030 does not assign it (EURO SIGN is A2E3H), so the
    # DcmSwift runtime rejects 80H and FFH itself instead of using ICU here.
    assert icu.decode(b"\xff") is None

    # Two-byte area: lead 81H-FEH, trail 40H-7EH and 80H-FEH (7FH invalid).
    two_byte = []
    for lead in range(0x81, 0xFF):
        for trail in range(0x40, 0xFF):
            text = None if trail == 0x7F else icu.decode(bytes([lead, trail]))
            if text is None or len(text) != 1:
                two_byte.append(0)
                continue
            scalar = ord(text)
            assert scalar not in FORBIDDEN and not 0xD800 <= scalar <= 0xDFFF
            if (lead, trail) == (0xA3, 0xA0):
                # ICU (like WHATWG) decodes A3A0H as IDEOGRAPHIC SPACE for
                # compatibility; GB18030-2022 keeps it at U+E5E5 and encodes
                # IDEOGRAPHIC SPACE as A1A1H.
                assert scalar == 0x3000
                scalar = 0xE5E5
            two_byte.append(scalar)

    # Four-byte BMP area 81308130H-8431A439H, linear index of 39,420 codes.
    four_byte = []
    for index in range(39420):
        b1, rest = divmod(index, 12600)
        b2, rest = divmod(rest, 1260)
        b3, b4 = divmod(rest, 10)
        text = icu.decode(bytes([0x81 + b1, 0x30 + b2, 0x81 + b3, 0x30 + b4]))
        if text is None or len(text) != 1:
            four_byte.append(0)
            continue
        scalar = ord(text)
        assert scalar not in FORBIDDEN and not 0xD800 <= scalar <= 0xDFFF
        four_byte.append(scalar)

    # Supplementary planes are linear from 90308130H (U+10000) and are
    # computed at runtime; verify that ICU agrees at both ends.
    assert icu.decode(b"\x90\x30\x81\x30") == "\U00010000"
    assert icu.decode(b"\xe3\x32\x9a\x35") == "\U0010ffff"
    # GB18030-2022 maps these former private-use codes to standard ones.
    assert two_byte[(0xA6 - 0x81) * 191 + (0xD9 - 0x40)] == 0xFE10
    assert two_byte[(0xFE - 0x81) * 191 + (0x59 - 0x40)] == 0x9FB4
    return two_byte, four_byte


def pack(table: list[int]) -> bytes:
    return struct.pack(f"<{len(table)}H", *table)


def swift_source(tables: list[tuple[str, str, list[int]]]) -> str:
    lines = [
        "// Generated by Scripts/generate-character-set-tables.py. Do not edit.",
        "//",
        "// GR (A0H-FFH) mappings of the DICOM single-byte G1 code elements from",
        "// PS3.3 2026d Table C.12-2. Each table has 96 entries; 0 means the",
        "// byte is not assigned in the character set.",
        "",
        "enum DICOMSingleByteTables {",
    ]
    for term, name, table in tables:
        lines.append(f"    /// {term}")
        lines.append(f"    static let {name}: [UInt16] = [")
        for start in range(0, 96, 8):
            row = ", ".join(f"0x{value:04X}" for value in table[start:start + 8])
            lines.append(f"        {row},")
        lines.append("    ]")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail if outputs are stale")
    args = parser.parse_args()

    single = [(term, name, single_byte_table(codec)) for term, name, codec in SINGLE_BYTE]
    single.append(("ISO_IR 13 (JIS X 0201 katakana)", "isoIR13", katakana_table()))

    icu = ICU()
    gb_two, gb_four = gb18030_tables(icu)
    binaries = {
        "jisx0208.bin": ninety_four_squared(
            lambda r, c: b"\x1b$B" + bytes([r, c]) + b"\x1b(B", "iso2022_jp"),
        "jisx0212.bin": ninety_four_squared(
            lambda r, c: bytes([0x8F, r | 0x80, c | 0x80]), "euc_jp"),
        "ksx1001.bin": ninety_four_squared(
            lambda r, c: bytes([r | 0x80, c | 0x80]), "euc_kr"),
        "gb2312.bin": ninety_four_squared(
            lambda r, c: bytes([r | 0x80, c | 0x80]), "gb2312"),
        "gb18030-2byte.bin": gb_two,
        "gb18030-4byte-bmp.bin": gb_four,
    }

    outputs = {SWIFT_TABLES: swift_source(single).encode()}
    for name, table in binaries.items():
        outputs[RESOURCES / name] = pack(table)

    stale = []
    for path, content in outputs.items():
        if args.check:
            if not path.exists() or path.read_bytes() != content:
                stale.append(path)
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    for path, content in outputs.items():
        mapped = ""
        if path.suffix == ".bin":
            values = struct.unpack(f"<{len(content) // 2}H", content)
            mapped = f", {sum(1 for value in values if value)} mapped"
        print(f"{path.relative_to(ROOT)}: sha256 {hashlib.sha256(content).hexdigest()[:16]}{mapped}")
    print(f"GB18030 tables from ICU {icu.version}")
    if stale:
        sys.exit("Stale tables: " + ", ".join(str(path.relative_to(ROOT)) for path in stale))


if __name__ == "__main__":
    main()
