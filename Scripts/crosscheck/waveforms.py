"""Cross-check DcmSwift's waveforms with pydicom.

  waveforms.py BUILD_DIR [FILE_OR_DIR...]

BUILD_DIR holds DcmWaveform. For each file with a Waveform Sequence, and for
files made here with every Waveform Sample Interpretation of PS3.3 C.10.9.1.5
(including a Big Endian one), the stored samples and the values (sample ×
sensitivity × correction + baseline) of DcmWaveform --json must equal those of
pydicom's multiplex_array, as_raw True and False. pydicom keeps mu-law and
A-law samples encoded: they are decoded here with ITU-T G.711. pydicom 3.0
reads Waveform Data as Little Endian whatever the Transfer Syntax: for Big
Endian files, as DCMTK's dcmdump shows the words, its samples are swapped
here. Exits 1 on any difference.
"""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
import pydicom
from pydicom.dataset import Dataset, FileMetaDataset
from pydicom.sequence import Sequence
from pydicom.uid import ExplicitVRBigEndian, ExplicitVRLittleEndian, generate_uid
from pydicom.waveforms.numpy_handler import multiplex_array

DTYPES = {"SB": "i1", "UB": "u1", "MB": "u1", "AB": "u1", "SS": "i2", "US": "u2", "SL": "i4", "UL": "u4",
          "SV": "i8", "UV": "u8"}


def mu_law(code):
    value = ~int(code) & 0xFF
    exponent = (value >> 4) & 7
    magnitude = (((value & 0x0F) << 3) + 0x84) << exponent
    return 0x84 - magnitude if value & 0x80 else magnitude - 0x84


def a_law(code):
    value = int(code) ^ 0x55
    exponent = (value >> 4) & 7
    mantissa = value & 0x0F
    magnitude = (mantissa << 4) + 8 if exponent == 0 else ((mantissa << 4) + 0x108) << (exponent - 1)
    return magnitude if value & 0x80 else -magnitude


def synthetic(folder, interpretation, big_endian=False):
    """A General ECG instance with two channels of that interpretation."""
    bits = {"SB": 8, "UB": 8, "MB": 8, "AB": 8, "SS": 16, "US": 16, "SL": 32, "UL": 32, "SV": 64, "UV": 64}[interpretation]
    rng = np.random.default_rng(len(interpretation) * 7 + bits)
    dtype = np.dtype(DTYPES[interpretation])
    info = np.iinfo(dtype)
    samples = rng.integers(info.min, info.max, size=(500, 2), dtype=dtype, endpoint=True)
    ds = Dataset()
    ds.SOPClassUID = "1.2.840.10008.5.1.4.1.1.9.1.2"
    ds.SOPInstanceUID = generate_uid()
    group = Dataset()
    group.MultiplexGroupLabel = "TEST"
    group.NumberOfWaveformChannels = 2
    group.NumberOfWaveformSamples = 500
    group.SamplingFrequency = "500"
    group.WaveformBitsAllocated = bits
    group.WaveformSampleInterpretation = interpretation
    channels = []
    for index, (sensitivity, correction, baseline) in enumerate(((2.5, 1, 0), (0.5, 1.02, -3.5))):
        channel = Dataset()
        channel.ChannelSensitivity = str(sensitivity)
        channel.ChannelSensitivityCorrectionFactor = str(correction)
        channel.ChannelBaseline = str(baseline)
        channel.WaveformBitsStored = bits
        channels.append(channel)
    group.ChannelDefinitionSequence = Sequence(channels)
    raw = samples.astype(dtype.newbyteorder(">" if big_endian else "<")).tobytes()
    group.WaveformData = raw
    group["WaveformData"].VR = "OB" if bits == 8 else "OW"
    ds.WaveformSequence = Sequence([group])
    ds.file_meta = FileMetaDataset()
    ds.file_meta.TransferSyntaxUID = ExplicitVRBigEndian if big_endian else ExplicitVRLittleEndian
    ds.file_meta.MediaStorageSOPClassUID = ds.SOPClassUID
    ds.file_meta.MediaStorageSOPInstanceUID = ds.SOPInstanceUID
    path = os.path.join(folder, f"{interpretation}{'-be' if big_endian else ''}.dcm")
    ds.save_as(path, enforce_file_format=True, little_endian=not big_endian, implicit_vr=False)
    return path


def compare(executable, path, failures):
    dataset = pydicom.dcmread(path)
    result = subprocess.run([executable, path, "--json"], capture_output=True, timeout=120)
    if result.returncode != 0:
        failures.append(f"{os.path.basename(path)}: DcmWaveform failed: {result.stderr[-200:]!r}")
        return 0
    ours = json.loads(result.stdout)
    for index, group in enumerate(dataset.WaveformSequence):
        interpretation = group.WaveformSampleInterpretation
        raw = multiplex_array(dataset, index, as_raw=True)
        values = multiplex_array(dataset, index, as_raw=False)
        if not dataset.is_little_endian and raw.dtype.itemsize > 1:
            raw = raw.byteswap()
            values = raw.astype(float).copy()
            for channel, definition in enumerate(group.ChannelDefinitionSequence):
                values[:, channel] = (raw[:, channel] * float(definition.get("ChannelSensitivity", 1.0))
                                      * float(definition.get("ChannelSensitivityCorrectionFactor", 1.0))
                                      + float(definition.get("ChannelBaseline", 0.0)))
        if interpretation in ("MB", "AB"):
            decode = np.vectorize(mu_law if interpretation == "MB" else a_law)
            raw = decode(raw)
            values = raw.astype(float).copy()
            for channel, definition in enumerate(group.ChannelDefinitionSequence):
                values[:, channel] = (raw[:, channel] * float(definition.get("ChannelSensitivity", 1.0))
                                      * float(definition.get("ChannelSensitivityCorrectionFactor", 1.0))
                                      + float(definition.get("ChannelBaseline", 0.0)))
        mine_raw = np.array(ours[index]["samples"], dtype=np.int64).T
        mine_values = np.array(ours[index]["values"], dtype=float).T
        if interpretation == "UV":
            raw = np.minimum(raw.astype(np.uint64), np.iinfo(np.int64).max).astype(np.int64)
        if not np.array_equal(mine_raw, raw.astype(np.int64)):
            failures.append(f"{os.path.basename(path)} group {index + 1} {interpretation}: stored samples differ")
        if not np.allclose(mine_values, values, rtol=1e-12, atol=1e-9):
            failures.append(f"{os.path.basename(path)} group {index + 1} {interpretation}: values differ")
    return len(dataset.WaveformSequence)


def main(build, paths):
    executable = os.path.join(build, "DcmWaveform")
    failures, groups = [], 0
    with tempfile.TemporaryDirectory() as folder:
        files = [synthetic(folder, interpretation) for interpretation in DTYPES]
        files.append(synthetic(folder, "SS", big_endian=True))
        files.append(synthetic(folder, "SL", big_endian=True))
        for path in paths:
            for root, _, names in os.walk(path) if os.path.isdir(path) else [("", [], [path])]:
                for name in names:
                    candidate = os.path.join(root, name)
                    try:
                        if "WaveformSequence" in pydicom.dcmread(candidate, stop_before_pixels=True):
                            files.append(candidate)
                    except Exception:
                        pass
        for path in files:
            groups += compare(executable, path, failures)
    for failure in failures:
        print("FAIL", failure)
    print(f"{len(files)} files, {groups} multiplex groups, {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2:]))
