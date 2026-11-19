"""Generate the synthetic DICOM corpus of the interoperability round-trip test.

  uv run --with pydicom==3.0.1 --with numpy Scripts/generate-synthetic-corpus.py [OUTPUT_DIR]

OUTPUT_DIR defaults to Tests/DcmSwiftTests/Corpus. Every file is made from
scratch: synthetic patients (SYNTH-*), deterministic UIDs under 2.25, and
geometric pixel patterns. pydicom writes the uncompressed files; DCMTK
(dcmconv, dcmcjpeg, dcmcrle) re-encodes them, so the encoded
streams come from a toolkit independent of DcmSwift. The set covers the
modalities, transfer syntaxes, photometric interpretations, bit depths, and
frame counts of the corpus it replaces, plus RT, SR, and a DICOMDIR.
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from pydicom.dataset import Dataset, FileMetaDataset
from pydicom.fileset import FileSet
from pydicom.sequence import Sequence
from pydicom.uid import (
    ExplicitVRLittleEndian,
    ImplicitVRLittleEndian,
    PYDICOM_IMPLEMENTATION_UID,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, "Tests", "DcmSwiftTests", "Corpus")
DATE = "20260101"
TIME = "120000"

SOP = {
    "CR": "1.2.840.10008.5.1.4.1.1.1",
    "CT": "1.2.840.10008.5.1.4.1.1.2",
    "MR": "1.2.840.10008.5.1.4.1.1.4",
    "NM": "1.2.840.10008.5.1.4.1.1.20",
    "OT": "1.2.840.10008.5.1.4.1.1.7",
    "US": "1.2.840.10008.5.1.4.1.1.6.1",
    "US-MF": "1.2.840.10008.5.1.4.1.1.3.1",
    "XA": "1.2.840.10008.5.1.4.1.1.12.1",
    "RTDOSE": "1.2.840.10008.5.1.4.1.1.481.2",
    "RTSTRUCT": "1.2.840.10008.5.1.4.1.1.481.3",
    "RTPLAN": "1.2.840.10008.5.1.4.1.1.481.5",
    "SR": "1.2.840.10008.5.1.4.1.1.88.11",
}


def uid(*parts):
    """A deterministic UID: 2.25 followed by 120 bits of a hash of the parts."""
    digest = hashlib.sha256("/".join(map(str, parts)).encode()).digest()[:15]
    return "2.25." + str(int.from_bytes(digest, "big"))


def base(name, modality, sop_class, patient):
    ds = Dataset()
    ds.SpecificCharacterSet = "ISO_IR 100"
    ds.SOPClassUID = sop_class
    ds.SOPInstanceUID = uid(name, "instance")
    ds.StudyDate = ds.SeriesDate = ds.ContentDate = DATE
    ds.StudyTime = ds.SeriesTime = ds.ContentTime = TIME
    ds.AccessionNumber = "SYNTH-ACC-" + patient[-3:]
    ds.Modality = modality
    ds.Manufacturer = "DcmSwift synthetic corpus"
    ds.InstitutionName = "Synthetic Institution"
    ds.ReferringPhysicianName = ""
    ds.StudyDescription = "Synthetic " + modality + " study"
    ds.SeriesDescription = name
    ds.PatientName = "SYNTHETIC^" + modality + "^" + patient[-3:]
    ds.PatientID = patient
    ds.IssuerOfPatientID = "SYNTH"
    ds.PatientBirthDate = "19700101"
    ds.PatientSex = "O"
    ds.StudyInstanceUID = uid(name, "study")
    ds.SeriesInstanceUID = uid(name, "series")
    ds.StudyID = "1"
    ds.SeriesNumber = 1
    ds.InstanceNumber = 1
    return ds


def pattern(rows, columns, frames, bits, signed=False):
    """Diagonal ramps that differ per frame, with a bright square marker."""
    y, x = np.mgrid[0:rows, 0:columns]
    maximum = (1 << bits) - 1
    out = []
    for frame in range(frames):
        values = ((x * 3 + y * 5 + frame * 17) % 256) * maximum // 255
        values[rows // 4: rows // 2, columns // 4: columns // 2] = maximum
        if signed:
            values = values - (1 << (bits - 1))
        out.append(values)
    array = np.stack(out) if frames > 1 else out[0]
    if bits <= 8:
        return array.astype(np.int8 if signed else np.uint8)
    return array.astype(np.int16 if signed else np.uint16)


def image(ds, rows, columns, frames=1, bits=16, photometric="MONOCHROME2", signed=False):
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = photometric
    ds.Rows, ds.Columns = rows, columns
    ds.BitsAllocated = 8 if bits <= 8 else 16
    ds.BitsStored = bits
    ds.HighBit = bits - 1
    ds.PixelRepresentation = 1 if signed else 0
    if frames > 1:
        ds.NumberOfFrames = frames
    ds.PixelData = pattern(rows, columns, frames, bits, signed).tobytes()
    return ds


def rgb(ds, rows, columns, frames=1):
    ds.SamplesPerPixel = 3
    ds.PhotometricInterpretation = "RGB"
    ds.PlanarConfiguration = 0
    ds.Rows, ds.Columns = rows, columns
    ds.BitsAllocated = ds.BitsStored = 8
    ds.HighBit = 7
    ds.PixelRepresentation = 0
    if frames > 1:
        ds.NumberOfFrames = frames
    y, x = np.mgrid[0:rows, 0:columns]
    planes = []
    for frame in range(frames):
        planes.append(np.stack([(x * 4 + frame * 9) % 256, (y * 4) % 256, ((x + y) * 2 + frame * 31) % 256], axis=-1))
    array = np.stack(planes) if frames > 1 else planes[0]
    ds.PixelData = array.astype(np.uint8).tobytes()
    return ds


def palette(ds, rows, columns, frames=1):
    image(ds, rows, columns, frames, bits=8, photometric="PALETTE COLOR")
    ramp = np.arange(256, dtype=np.uint16) * 257
    descriptor = [256, 0, 16]
    ds.RedPaletteColorLookupTableDescriptor = descriptor
    ds.GreenPaletteColorLookupTableDescriptor = descriptor
    ds.BluePaletteColorLookupTableDescriptor = descriptor
    ds.RedPaletteColorLookupTableData = ramp.tobytes()
    ds.GreenPaletteColorLookupTableData = ramp[::-1].copy().tobytes()
    ds.BluePaletteColorLookupTableData = ((ramp // 2) + 16384).astype(np.uint16).tobytes()
    return ds


def ct_attributes(ds):
    ds.ImageType = ["ORIGINAL", "PRIMARY", "AXIAL"]
    ds.RescaleIntercept = -1024
    ds.RescaleSlope = 1
    ds.WindowCenter = 40
    ds.WindowWidth = 400
    ds.KVP = 120
    ds.PixelSpacing = [0.5, 0.5]
    ds.SliceThickness = 1.0
    ds.ImagePositionPatient = [0.0, 0.0, 0.0]
    ds.ImageOrientationPatient = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
    return ds


def save(ds, path, syntax):
    ds.file_meta = FileMetaDataset()
    ds.file_meta.MediaStorageSOPClassUID = ds.SOPClassUID
    ds.file_meta.MediaStorageSOPInstanceUID = ds.SOPInstanceUID
    ds.file_meta.TransferSyntaxUID = syntax
    ds.file_meta.ImplementationClassUID = PYDICOM_IMPLEMENTATION_UID
    ds.save_as(path, implicit_vr=syntax == ImplicitVRLittleEndian, little_endian=True, enforce_file_format=True)


def run(*command):
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL)


def rt_dose(name, patient):
    ds = base(name, "RTDOSE", SOP["RTDOSE"], patient)
    frames, rows, columns = 4, 24, 32
    image(ds, rows, columns, frames, bits=16)
    ds.NumberOfFrames = frames
    ds.FrameIncrementPointer = 0x3004000C
    ds.GridFrameOffsetVector = [float(i * 2.5) for i in range(frames)]
    ds.ImagePositionPatient = [-40.0, -30.0, 0.0]
    ds.ImageOrientationPatient = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
    ds.PixelSpacing = [2.5, 2.5]
    ds.SliceThickness = 2.5
    ds.DoseUnits = "GY"
    ds.DoseType = "PHYSICAL"
    ds.DoseSummationType = "PLAN"
    ds.DoseGridScaling = 0.0001
    plan = Dataset()
    plan.ReferencedSOPClassUID = SOP["RTPLAN"]
    plan.ReferencedSOPInstanceUID = uid("rt_plan", "instance")
    ds.ReferencedRTPlanSequence = Sequence([plan])
    return ds


def rt_struct(name, patient):
    ds = base(name, "RTSTRUCT", SOP["RTSTRUCT"], patient)
    ds.StructureSetLabel = "SYNTHETIC"
    ds.StructureSetDate, ds.StructureSetTime = DATE, TIME
    frame = uid("rt_frame_of_reference")
    reference = Dataset()
    reference.FrameOfReferenceUID = frame
    ds.ReferencedFrameOfReferenceSequence = Sequence([reference])
    rois, contours, observations = [], [], []
    for number, (label, kind, color, radius) in enumerate(
        [("EXTERNAL", "EXTERNAL", [0, 255, 0], 60.0), ("PTV", "PTV", [255, 0, 0], 20.0)], start=1
    ):
        roi = Dataset()
        roi.ROINumber = number
        roi.ReferencedFrameOfReferenceUID = frame
        roi.ROIName = label
        roi.ROIGenerationAlgorithm = "MANUAL"
        rois.append(roi)
        slices = []
        for z in (0.0, 2.5, 5.0):
            contour = Dataset()
            contour.ContourGeometricType = "CLOSED_PLANAR"
            points = []
            for step in range(12):
                angle = step * np.pi / 6
                points += [round(radius * np.cos(angle), 3), round(radius * np.sin(angle), 3), z]
            contour.NumberOfContourPoints = 12
            contour.ContourData = points
            slices.append(contour)
        item = Dataset()
        item.ROIDisplayColor = color
        item.ReferencedROINumber = number
        item.ContourSequence = Sequence(slices)
        contours.append(item)
        observation = Dataset()
        observation.ObservationNumber = number
        observation.ReferencedROINumber = number
        observation.RTROIInterpretedType = kind
        observation.ROIInterpreter = ""
        observations.append(observation)
    ds.StructureSetROISequence = Sequence(rois)
    ds.ROIContourSequence = Sequence(contours)
    ds.RTROIObservationsSequence = Sequence(observations)
    return ds


def rt_plan(name, patient):
    ds = base(name, "RTPLAN", SOP["RTPLAN"], patient)
    ds.SOPInstanceUID = uid("rt_plan", "instance")
    ds.RTPlanLabel = "SYNTHETIC"
    ds.RTPlanDate, ds.RTPlanTime = DATE, TIME
    ds.RTPlanGeometry = "PATIENT"
    fraction = Dataset()
    fraction.FractionGroupNumber = 1
    fraction.NumberOfFractionsPlanned = 25
    fraction.NumberOfBeams = 2
    fraction.NumberOfBrachyApplicationSetups = 0
    beams, references = [], []
    for number, angle in ((1, 90.0), (2, 270.0)):
        reference = Dataset()
        reference.ReferencedBeamNumber = number
        reference.BeamMeterset = 100.0
        references.append(reference)
        beam = Dataset()
        beam.BeamNumber = number
        beam.BeamName = "BEAM" + str(number)
        beam.BeamType = "STATIC"
        beam.RadiationType = "PHOTON"
        beam.TreatmentDeliveryType = "TREATMENT"
        beam.NumberOfWedges = beam.NumberOfCompensators = beam.NumberOfBoli = beam.NumberOfBlocks = 0
        beam.FinalCumulativeMetersetWeight = 1.0
        beam.NumberOfControlPoints = 2
        points = []
        for index, weight in ((0, 0.0), (1, 1.0)):
            point = Dataset()
            point.ControlPointIndex = index
            point.CumulativeMetersetWeight = weight
            if index == 0:
                point.NominalBeamEnergy = 6.0
                point.GantryAngle = angle
                point.IsocenterPosition = [0.0, 0.0, 2.5]
            points.append(point)
        beam.ControlPointSequence = Sequence(points)
        beams.append(beam)
    fraction.ReferencedBeamSequence = Sequence(references)
    ds.FractionGroupSequence = Sequence([fraction])
    ds.BeamSequence = Sequence(beams)
    return ds


def code(value, scheme, meaning):
    item = Dataset()
    item.CodeValue, item.CodingSchemeDesignator, item.CodeMeaning = value, scheme, meaning
    return item


def sr(name, patient):
    ds = base(name, "SR", SOP["SR"], patient)
    ds.ValueType = "CONTAINER"
    ds.ConceptNameCodeSequence = Sequence([code("18748-4", "LN", "Diagnostic Imaging Report")])
    ds.ContinuityOfContent = "SEPARATE"
    ds.CompletionFlag = "COMPLETE"
    ds.VerificationFlag = "UNVERIFIED"
    items = []
    for concept, text in (
        (code("121060", "DCM", "History"), "Synthetic history, no clinical meaning."),
        (code("121071", "DCM", "Finding"), "Synthetic finding: square marker in the upper left quadrant."),
        (code("121076", "DCM", "Conclusion"), "Synthetic conclusion."),
    ):
        item = Dataset()
        item.RelationshipType = "CONTAINS"
        item.ValueType = "TEXT"
        item.ConceptNameCodeSequence = Sequence([concept])
        item.TextValue = text
        items.append(item)
    ds.ContentSequence = Sequence(items)
    ds.PerformedProcedureCodeSequence = Sequence()
    return ds


# name, builder, transfer syntax step. Steps: "implicit", "explicit", "big"
# (DCMTK explicit big endian), "jpeg-baseline", "jpeg-sv1" (process 14 SV1),
# "jpeg-lossless" (process 14, selection value 6), "rle".
def cases():
    def ct(name, bits=16, signed=False):
        return ct_attributes(image(base(name, "CT", SOP["CT"], "SYNTH-0000101"), 64, 64, bits=bits, signed=signed))

    def mr(name, frames=1, bits=16):
        ds = image(base(name, "MR", SOP["MR"], "SYNTH-0000102"), 64, 48, frames, bits=bits)
        ds.ScanningSequence, ds.SequenceVariant, ds.ScanOptions, ds.MRAcquisitionType = "SE", "NONE", "", "2D"
        ds.EchoTime, ds.RepetitionTime, ds.MagneticFieldStrength = 15.0, 500.0, 1.5
        return ds

    def us(name, builder, frames=1, sop="US-MF"):
        ds = builder(base(name, "US", SOP[sop if frames > 1 else "US"], "SYNTH-0000104"), 48, 64, frames)
        if frames > 1:
            ds.FrameTime = 33.3
            ds.FrameIncrementPointer = 0x00181063
        return ds

    yield "CR_ImplicitVRLittleEndian_SINGLE_MONOCHROME1_16", lambda n: image(
        base(n, "CR", SOP["CR"], "SYNTH-0000100"), 64, 64, bits=12, photometric="MONOCHROME1"), "implicit"
    yield "CT_ExplicitVRLittleEndian_SINGLE_MONOCHROME2_16", lambda n: ct(n, signed=True), "explicit"
    yield "CT_ImplicitVRLittleEndian_SINGLE_MONOCHROME2_16", lambda n: ct(n, bits=12), "implicit"
    yield "CT_ImplicitVRLittleEndian_SINGLE_MONOCHROME2_8", lambda n: ct(n, bits=8), "implicit"
    yield "CT_JPEGLosslessSV1_SINGLE_MONOCHROME2_16", lambda n: ct(n, bits=12), "jpeg-sv1"
    yield "MR_ExplicitVRLittleEndian_MULTI_MONOCHROME2_8", lambda n: mr(n, frames=4, bits=8), "explicit"
    yield "MR_ImplicitVRLittleEndian_MULTI_MONOCHROME2_16", lambda n: mr(n, frames=3), "implicit"
    yield "MR_ImplicitVRLittleEndian_SINGLE_MONOCHROME2_16", lambda n: mr(n), "implicit"
    yield "MR_JPEGLossless_SINGLE_MONOCHROME2_16", lambda n: mr(n), "jpeg-lossless"
    yield "NM_ExplicitVRLittleEndian_MULTI_MONOCHROME2_16", lambda n: image(
        base(n, "NM", SOP["NM"], "SYNTH-0000103"), 32, 32, 4), "explicit"
    yield "OT_ImplicitVRLittleEndian_SINGLE_MONOCHROME2_8", lambda n: image(
        base(n, "OT", SOP["OT"], "SYNTH-0000105"), 40, 40, bits=8), "implicit"
    yield "OT_ImplicitVRLittleEndian_SINGLE_PALETTE_COLOR_8", lambda n: palette(
        base(n, "OT", SOP["OT"], "SYNTH-0000105"), 40, 40), "implicit"
    yield "US_ExplicitVRBigEndian_SINGLE_RGB_8", lambda n: us(n, rgb), "big"
    yield "US_ExplicitVRLittleEndian_MULTI_MONOCHROME2_8", lambda n: us(
        n, lambda ds, r, c, f: image(ds, r, c, f, bits=8), frames=5), "explicit"
    yield "US_ExplicitVRLittleEndian_SINGLE_RGB_8", lambda n: us(n, rgb), "explicit"
    yield "US_JPEGBaseline_MULTI_YBR_FULL_422_8", lambda n: us(n, rgb, frames=5), "jpeg-baseline"
    yield "US_JPEGBaseline_SINGLE_YBR_FULL_422_8", lambda n: us(n, rgb), "jpeg-baseline"
    yield "US_RLELossless_MULTI_PALETTE_COLOR_8", lambda n: us(n, palette, frames=3), "rle"
    yield "XA_JPEGLossless_MULTI_MONOCHROME2_8", lambda n: image(
        base(n, "XA", SOP["XA"], "SYNTH-0000106"), 48, 48, 4, bits=8), "jpeg-sv1"
    yield "RT_Dose", lambda n: rt_dose(n, "SYNTH-0000107"), "implicit"
    yield "RT_StructureSet", lambda n: rt_struct(n, "SYNTH-0000107"), "implicit"
    yield "RT_Plan", lambda n: rt_plan(n, "SYNTH-0000107"), "implicit"
    yield "SR_BasicText", lambda n: sr(n, "SYNTH-0000108"), "explicit"


def main():
    if os.path.isdir(OUTPUT):
        for entry in os.listdir(OUTPUT):
            if entry.endswith((".dcm", ".dicomdir")):
                os.remove(os.path.join(OUTPUT, entry))
    os.makedirs(OUTPUT, exist_ok=True)
    work = tempfile.mkdtemp(prefix="dcmswift-corpus-")
    try:
        names = []
        for name, build, step in cases():
            ds = build(name)
            target = os.path.join(OUTPUT, name + ".dcm")
            if step == "implicit":
                save(ds, target, ImplicitVRLittleEndian)
            elif step == "explicit":
                save(ds, target, ExplicitVRLittleEndian)
            else:
                source = os.path.join(work, name + ".dcm")
                save(ds, source, ExplicitVRLittleEndian)
                if step == "big":
                    run("dcmconv", "+tb", source, target)
                elif step == "jpeg-baseline":
                    run("dcmcjpeg", "+eb", "+q", "90", "+cy", "+s2", "+un", source, target)
                elif step == "jpeg-sv1":
                    run("dcmcjpeg", "+e1", source, target)
                elif step == "jpeg-lossless":
                    run("dcmcjpeg", "+el", "+sv", "6", source, target)
                elif step == "rle":
                    run("dcmcrle", source, target)
            names.append(name)
        # A DICOMDIR (General Purpose CD profile: Explicit VR Little Endian files), written by
        # pydicom's FileSet with a pinned file-set UID.
        files = FileSet()
        files.ID = "SYNTHETIC"
        files.UID = uid("dicomdir", "file-set")
        for name, _, step in cases():
            if step == "explicit":
                files.add(os.path.join(OUTPUT, name + ".dcm"))
        media = os.path.join(work, "media")
        files.write(media)
        shutil.copy(os.path.join(media, "DICOMDIR"), os.path.join(OUTPUT, "SYNTHETIC.dicomdir"))
        print("wrote %d files to %s" % (len(names) + 1, OUTPUT))
    finally:
        shutil.rmtree(work)


if __name__ == "__main__":
    main()
