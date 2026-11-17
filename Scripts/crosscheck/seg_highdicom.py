"""Cross-check DcmSwift's Segmentations and Parametric Maps with highdicom.

  seg_highdicom.py BUILD_DIR STANDARD_DIR CT_SERIES_DIR

BUILD_DIR holds DcmSeg; STANDARD_DIR is the -src folder of dicom-validator's
validate_iods (on the PATH); CT_SERIES_DIR holds single-frame images of one
series. Needs highdicom.

1. highdicom makes Segmentations of the series (BINARY with two segments,
   FRACTIONAL, also RLE compressed) and a float Parametric Map; DcmSeg reads
   each frame's segment and mask, or values, which must equal pydicom's.
2. DcmSeg makes a BINARY Segmentation of two boxes; dicom-validator must find
   no error but those it also finds in highdicom's Segmentation (it reports
   the Functional Group Sequences as unexpected), and highdicom must read it
   back with the boxes on the right source images.
Exits 1 on any failure.
"""
import json
import os
import subprocess
import sys
import tempfile

import highdicom as hd
import numpy as np
import pydicom
from pydicom.sr.codedict import codes
from pydicom.uid import RLELossless


def show(build, path):
    result = subprocess.run([os.path.join(build, "DcmSeg"), "show", path, "--json"], capture_output=True, timeout=120)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode()[-300:])
    return json.loads(result.stdout)


def frame_segments(dataset):
    numbers = []
    for item in dataset.PerFrameFunctionalGroupsSequence:
        identification = item.get("SegmentIdentificationSequence") or \
            dataset.SharedFunctionalGroupsSequence[0].get("SegmentIdentificationSequence")
        numbers.append(int(identification[0].ReferencedSegmentNumber))
    return numbers


def main(build, standard, series):
    failures = []
    images = sorted((pydicom.dcmread(os.path.join(series, name)) for name in os.listdir(series)),
                    key=lambda image: float(image.ImagePositionPatient[2]))
    rows, columns = images[0].Rows, images[0].Columns
    mask = np.zeros((len(images), rows, columns), dtype=bool)
    mask[1:4, rows // 4: rows // 2, columns // 4: 3 * columns // 4] = True
    other = np.zeros_like(mask)
    other[2, rows // 2: rows - 1, columns // 2: columns - 1] = True

    def description(number, label, kind):
        return hd.seg.SegmentDescription(
            segment_number=number, segment_label=label, segmented_property_category=codes.SCT.Tissue,
            segmented_property_type=kind, algorithm_type=hd.seg.SegmentAlgorithmTypeValues.MANUAL)

    common = dict(series_instance_uid=hd.UID(), series_number=10, sop_instance_uid=hd.UID(), instance_number=1,
                  manufacturer="test", manufacturer_model_name="test", software_versions="1", device_serial_number="1")
    with tempfile.TemporaryDirectory() as folder:
        made = {
            "binary": hd.seg.Segmentation(
                source_images=images, pixel_array=np.stack([mask, other], axis=-1).astype(np.uint8),
                segmentation_type=hd.seg.SegmentationTypeValues.BINARY,
                segment_descriptions=[description(1, "first", codes.SCT.Liver), description(2, "second", codes.SCT.Kidney)],
                **common),
            "fractional": hd.seg.Segmentation(
                source_images=images, pixel_array=mask.astype(np.float32) * 0.75,
                segmentation_type=hd.seg.SegmentationTypeValues.FRACTIONAL,
                segment_descriptions=[description(1, "first", codes.SCT.Liver)], max_fractional_value=255, **common),
            "fractional-rle": hd.seg.Segmentation(
                source_images=images, pixel_array=mask.astype(np.float32) * 0.5,
                segmentation_type=hd.seg.SegmentationTypeValues.FRACTIONAL,
                segment_descriptions=[description(1, "first", codes.SCT.Liver)], max_fractional_value=255,
                transfer_syntax_uid=RLELossless, **common),
        }
        values = np.stack([np.full((rows, columns), index * 1.5, dtype=np.float32)
                           + np.arange(columns, dtype=np.float32)[None, :] * 0.01 for index in range(len(images))])
        mapping = hd.pm.RealWorldValueMapping(
            lut_label="ADC", lut_explanation="test", unit=hd.sr.CodedConcept("mm2/s", "UCUM", "mm2/s"),
            value_range=(float(values.min()), float(values.max())), intercept=0, slope=1)
        made["parametric-map"] = hd.pm.ParametricMap(
            source_images=images, pixel_array=values, contains_recognizable_visual_features=False,
            real_world_value_mappings=[mapping], window_center=1, window_width=2, **common)
        for name, instance in made.items():
            path = os.path.join(folder, f"{name}.dcm")
            instance.save_as(path)
            dataset = pydicom.dcmread(path)
            try:
                ours = show(build, path)
            except RuntimeError as error:
                failures.append(f"{name}: DcmSeg failed: {error}")
                continue
            if name == "parametric-map":
                expected = np.frombuffer(dataset.FloatPixelData, dtype="<f4").reshape(len(images), rows, columns)
                found = np.array([frame["values"] for frame in ours["frames"]]).reshape(expected.shape)
                if not np.allclose(found, expected.astype(float), rtol=1e-7):
                    failures.append(f"{name}: values differ")
                continue
            pixels = dataset.pixel_array.reshape(int(dataset.NumberOfFrames), rows, columns)
            found = np.array([frame["mask"] for frame in ours["frames"]]).reshape(pixels.shape)
            if not np.array_equal(found, pixels):
                failures.append(f"{name}: masks differ")
            if [frame["segment"] for frame in ours["frames"]] != frame_segments(dataset):
                failures.append(f"{name}: frame segments differ")
            if [segment["label"] for segment in ours["segments"]] != [s.SegmentLabel for s in dataset.SegmentSequence]:
                failures.append(f"{name}: segment labels differ")

        # DcmSeg makes, dicom-validator validates, highdicom reads.
        sources = [os.path.join(series, name) for name in os.listdir(series)]
        sources.sort(key=lambda path: float(pydicom.dcmread(path).ImagePositionPatient[2]))
        output = os.path.join(folder, "ours.dcm")
        box = f"{columns // 4},{rows // 4},{columns // 2},{rows // 2}"
        arguments = [os.path.join(build, "DcmSeg"), "make", "--output", output, "--box", f"first:{box}:1,3",
                     "--box", f"second:0,0,2,3:2,2"]
        for source in sources:
            arguments += ["--source", source]
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            failures.append(f"DcmSeg make failed: {result.stderr[-300:]}")
        else:
            def oracle_errors(path):
                result = subprocess.run(["validate_iods", "-src", standard, "-r", "2026d", path], capture_output=True, text=True)
                return {line.strip() for line in result.stdout.splitlines()
                        if "missing" in line or "unexpected" in line or "invalid value" in line or "not allowed" in line}
            # dicom-validator finds the Functional Group Sequences of a
            # Segmentation unexpected, in highdicom's too: those are not
            # held against DcmSeg.
            baseline = oracle_errors(os.path.join(folder, "binary.dcm"))
            errors = sorted(oracle_errors(output) - baseline)
            if errors:
                failures.append(f"dicom-validator on DcmSeg's Segmentation: {errors}")
            segmentation = hd.seg.segread(output)
            uids = [image.SOPInstanceUID for image in images]
            volume = segmentation.get_pixels_by_source_instance(source_sop_instance_uids=uids,
                                                                segment_numbers=[1, 2], assert_missing_frames_are_empty=True)
            expected = np.zeros((len(images), rows, columns, 2), dtype=bool)
            expected[1:4, rows // 4: rows // 2, columns // 4: columns // 2, 0] = True
            expected[2, 0:3, 0:2, 1] = True
            if not np.array_equal(volume.astype(bool), expected):
                failures.append("highdicom reads other masks from DcmSeg's Segmentation")
    for failure in failures:
        print("FAIL", failure)
    print(f"{len(made)} highdicom instances read, 1 DcmSeg Segmentation checked, {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3]))
