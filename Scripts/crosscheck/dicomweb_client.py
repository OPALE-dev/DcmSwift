"""Check DcmSwift's DICOMweb origin server with an independent user agent.

  dicomweb_client.py BASE_URL [--pydicom-testdata] [PATH...]

BASE_URL is the service root of a running `DcmServer --http-port`, such as
http://127.0.0.1:8042/dicomweb, over an empty storage directory. Every file
is stored with dicomweb-client (STOW-RS), then found (QIDO-RS) and retrieved
(WADO-RS: instance, metadata, frames, rendered); results are compared with
pydicom's reading of the source file. Prints one line per difference and a
summary; exits 1 on any difference.

Normalization: Group Length elements are ignored (pydicom 3 removes them
before sending). Files that pydicom cannot encode, Implicit VR or Big Endian
files (not used by Web Services), and instances without valid UIDs are
skipped. Multi-frame images are rendered frame by frame, since a single-part
image cannot stand for several frames (PS3.18 10.4.4).

Needs: pip install dicomweb-client pydicom numpy
"""
import io, os, sys
import pydicom
from pydicom.uid import ExplicitVRLittleEndian
from dicomweb_client.api import DICOMwebClient

EXCLUDED = {0x7FE00010, 0x7FE00008, 0x7FE00009}


def files(arguments):
    paths = []
    for argument in arguments:
        if argument == "--pydicom-testdata":
            from pydicom.data import get_testdata_files
            paths += get_testdata_files("*.dcm")
        elif os.path.isdir(argument):
            for root, _, names in os.walk(argument):
                paths += [os.path.join(root, name) for name in names]
        else:
            paths.append(argument)
    return sorted(paths)


def readable(path):
    try:
        ds = pydicom.dcmread(path)
    except Exception:
        return None
    required = ("SOPClassUID", "SOPInstanceUID", "StudyInstanceUID", "SeriesInstanceUID")
    if not all(getattr(ds, keyword, None) for keyword in required) or "TransferSyntaxUID" not in ds.file_meta:
        return None
    if not all(pydicom.uid.UID(str(getattr(ds, keyword))).is_valid for keyword in required):
        return None
    # Web Services do not use Implicit VR or Big Endian (PS3.18 8.7.3).
    if ds.file_meta.TransferSyntaxUID in ("1.2.840.10008.1.2", "1.2.840.10008.1.2.2"):
        return None
    return ds


def decodable(ds):
    """Whether pydicom decodes the Pixel Data, so it can serve as reference."""
    if "PixelData" not in ds:
        return False
    try:
        ds.pixel_array
        return True
    except Exception:
        return False


def values(ds):
    """Top-level attributes other than Pixel Data, as comparable text."""
    result = {}
    for element in ds:
        if element.tag in EXCLUDED or element.tag.group == 0x0002 or element.tag.is_private or element.tag.element == 0:
            continue
        if element.VR == "SQ":
            result[int(element.tag)] = len(element.value)
        elif element.VR in ("OB", "OW", "OF", "OD", "OL", "OV", "UN"):
            result[int(element.tag)] = bytes(element.value or b"").rstrip(b"\0 ")
        else:
            result[int(element.tag)] = str(element.value).rstrip("\0 ")
    return result


def main(arguments):
    base, rest = arguments[0], arguments[1:]
    client = DICOMwebClient(base)
    differences, checked, skipped = [], 0, 0

    def differ(path, message):
        differences.append(f"{os.path.basename(path)}: {message}")
        print(f"{os.path.basename(path)}: {message}")

    for path in files(rest):
        ds = readable(path)
        if ds is None:
            skipped += 1
            continue
        study, series, instance = ds.StudyInstanceUID, ds.SeriesInstanceUID, ds.SOPInstanceUID
        try:
            pydicom.dcmwrite(io.BytesIO(), ds)
        except Exception:
            skipped += 1  # pydicom cannot encode the data set it read
            continue
        try:
            response = client.store_instances([ds])
        except Exception as error:
            differ(path, f"STOW-RS failed: {error}")
            continue
        stored = [item.ReferencedSOPInstanceUID for item in getattr(response, "ReferencedSOPSequence", [])]
        if instance not in stored:
            differ(path, f"not in the Referenced SOP Sequence: {response}")
            continue
        checked += 1

        found = client.search_for_instances(study_instance_uid=study, series_instance_uid=series,
                                            search_filters={"SOPInstanceUID": instance})
        if len(found) != 1:
            differ(path, f"QIDO-RS found {len(found)} instances")

        try:
            retrieved = client.retrieve_instance(study, series, instance)
            original, received = values(ds), values(retrieved)
            for tag in sorted(set(original) | set(received)):
                if original.get(tag) != received.get(tag):
                    differ(path, f"WADO-RS ({tag >> 16:04X},{tag & 0xFFFF:04X}): "
                                 f"{str(original.get(tag))[:60]!r} != {str(received.get(tag))[:60]!r}")
            if decodable(ds) and retrieved.file_meta.TransferSyntaxUID == ExplicitVRLittleEndian:
                import numpy
                if not numpy.array_equal(ds.pixel_array, retrieved.pixel_array):
                    differ(path, "decompressed pixels differ from pydicom's")
        except Exception as error:
            differ(path, f"WADO-RS failed: {error}")

        try:
            metadata = client.retrieve_instance_metadata(study, series, instance)
            if metadata.get("00080018", {}).get("Value") != [instance]:
                differ(path, "metadata has another SOP Instance UID")
            if "PixelData" in ds and "BulkDataURI" not in metadata.get("7FE00010", {}):
                differ(path, "metadata Pixel Data has no Bulk Data URI")
        except Exception as error:
            differ(path, f"metadata failed: {error}")

        if decodable(ds) and ds.file_meta.TransferSyntaxUID == ExplicitVRLittleEndian and ds.get("BitsAllocated", 8) >= 8:
            try:
                frame = client.retrieve_instance_frames(study, series, instance, frame_numbers=[1])[0]
                size = ds.Rows * ds.Columns * ds.get("SamplesPerPixel", 1) * ds.BitsAllocated // 8
                expected = bytes(ds.PixelData)[:size]
                if frame != expected:
                    differ(path, f"frame 1: {len(frame)} bytes differ from the {len(expected)} stored")
            except Exception as error:
                differ(path, f"frames failed: {error}")
            try:
                if int(ds.get("NumberOfFrames", 1) or 1) > 1:
                    rendered = client.retrieve_instance_frames_rendered(
                        study, series, instance, frame_numbers=[1], media_types=("image/jpeg",))
                else:
                    rendered = client.retrieve_instance_rendered(study, series, instance, media_types=("image/jpeg",))
                if not rendered.startswith(b"\xff\xd8"):
                    differ(path, "rendered is not a JPEG image")
            except Exception as error:
                differ(path, f"rendered failed: {error}")

    print(f"{checked} instances checked, {skipped} files skipped, {len(differences)} differences")
    return 1 if differences else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
