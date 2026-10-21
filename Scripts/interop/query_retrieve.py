"""Independent Q/R extension checks with pynetdicom/pydicom.

Usage: python query_retrieve.py /path/to/DcmServer
Starts an isolated archive and a C-MOVE receiver, then removes both.
"""
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from pydicom.dataset import Dataset, FileDataset, FileMetaDataset
from pydicom.uid import ExplicitVRLittleEndian, UID, generate_uid
from pynetdicom import AE, evt, build_role
from pynetdicom.pdu_primitives import SOPClassExtendedNegotiation

FIND = "1.2.840.10008.5.1.4.1.2.2.1"
GET = "1.2.840.10008.5.1.4.1.2.2.3"
ROOT_MOVE = "1.2.840.10008.5.1.4.1.2.4.2"
ROOT_GET = "1.2.840.10008.5.1.4.1.2.4.3"
BULK_GET = "1.2.840.10008.5.1.4.1.2.5.3"
PATIENT = "1.2.840.10008.5.1.4.37.1"
SC = "1.2.840.10008.5.1.4.1.1.7.2"


def check(condition, description):
    if not condition:
        raise AssertionError(description)
    print("OK", description, flush=True)


def query(level, **keys):
    result = Dataset()
    result.QueryRetrieveLevel = level
    for key, value in keys.items():
        setattr(result, key, value)
    return result


def extended(sop, values):
    result = SOPClassExtendedNegotiation()
    result.sop_class_uid = sop
    result.service_class_application_information = bytes(values)
    return result


def fixture(path, uid, modality, series):
    meta = FileMetaDataset()
    meta.MediaStorageSOPClassUID = SC
    meta.MediaStorageSOPInstanceUID = uid
    meta.TransferSyntaxUID = ExplicitVRLittleEndian
    data = FileDataset(str(path), {}, file_meta=meta, preamble=b"\0" * 128)
    data.SOPClassUID, data.SOPInstanceUID = SC, uid
    data.SpecificCharacterSet = "ISO_IR 192"
    data.PatientName, data.PatientID = "Müller^Anne", "P1"
    data.StudyInstanceUID, data.SeriesInstanceUID = "1.2.826.0.1.3680043.10.999.1", series
    data.StudyDate, data.StudyTime = "20261020", "223000"
    data.TimezoneOffsetFromUTC = "+0000"
    data.ContentDate, data.ContentTime = "20261020", "235959"
    data.Modality = modality
    data.PatientBirthDate = data.PatientSex = ""
    data.ReferringPhysicianName = data.AccessionNumber = ""
    data.StudyID, data.SeriesNumber, data.InstanceNumber = "1", 1, 1
    data.Manufacturer, data.ConversionType = "Test", "WSD"
    data.ImageType, data.PatientOrientation = ["DERIVED", "SECONDARY"], ""
    data.BurnedInAnnotation, data.PresentationLUTShape = "NO", "IDENTITY"
    data.RescaleIntercept, data.RescaleSlope, data.RescaleType = "0", "1", "US"
    data.WindowCenter, data.WindowWidth = "127", "256"
    data.Rows, data.Columns, data.SamplesPerPixel = 1, 2, 1
    data.PhotometricInterpretation = "MONOCHROME2"
    data.BitsAllocated = data.BitsStored = 8
    data.HighBit, data.PixelRepresentation = 7, 0
    data.NumberOfFrames, data.FrameTime = 4, "1000"
    data.FrameIncrementPointer = 0x00181063
    data.PixelData = bytes([10, 11, 20, 21, 30, 31, 40, 41])
    icon = Dataset()
    icon.Rows, icon.Columns, icon.SamplesPerPixel = 1, 2, 1
    icon.PhotometricInterpretation = "MONOCHROME2"
    icon.BitsAllocated = icon.BitsStored = 8
    icon.HighBit, icon.PixelRepresentation = 7, 0
    icon.PixelData = b"\x01\x02"
    data.IconImageSequence = [icon]
    waveform = Dataset()
    waveform.WaveformBitsAllocated = 16
    waveform.WaveformData = b"\x01\x02"
    waveform.NumberOfWaveformChannels = 1
    data.WaveformSequence = [waveform]
    # Keep the frame extraction source free of unrelated waveform structures.
    if modality == "CT":
        del data.WaveformSequence
    data.save_as(path, enforce_file_format=True)
    return data


def main(executable):
    check("MOVE" in UID(ROOT_MOVE).name and "GET" in UID(ROOT_GET).name, "UID direction agrees with independent dictionary")
    received, moved = [], []

    def store(event):
        received.append(event.dataset)
        if "FrameExtractionSequence" in event.dataset:
            result = event.dataset
            result.file_meta = event.file_meta
            result.save_as(root / "derived.dcm", enforce_file_format=True)
        return 0

    def move_store(event):
        moved.append(event.dataset)
        return 0

    receiver = AE(ae_title="MOVEDEST")
    receiver.add_supported_context(SC)
    listener = receiver.start_server(("127.0.0.1", 0), block=False, evt_handlers=[(evt.EVT_C_STORE, move_store)])
    process = None
    try:
        with tempfile.TemporaryDirectory(prefix="dcmswift-qr-") as root:
            root = Path(root)
            archive = root / "archive"
            archive.mkdir()
            patients = root / "patients"
            patients.mkdir()
            patient = Dataset()
            patient.SpecificCharacterSet = "ISO_IR 192"
            patient.PatientID, patient.IssuerOfPatientID, patient.PatientName = "P1", "DOMAIN", "Müller^Anne"
            patient.PatientBirthDate, patient.PatientSex = "", ""
            patient.ObservationDateTime, patient.ValueType = "20261021120000", "CONTAINER"
            concept = Dataset()
            concept.CodeValue, concept.CodingSchemeDesignator, concept.CodeMeaning = "1", "99TEST", "Summary"
            patient.ConceptNameCodeSequence, patient.ContentSequence = [concept], []
            template = Dataset()
            template.MappingResource, template.TemplateIdentifier = "DCMR", "9007"
            patient.ContentTemplateSequence = [template]
            (patients / "patient.json").write_text(patient.to_json(), encoding="utf-8")
            uid = generate_uid()
            source = fixture(archive / "ct.dcm", uid, "CT", "1.2.826.0.1.3680043.10.999.2")
            mr = fixture(archive / "mr.dcm", generate_uid(), "MR", "1.2.826.0.1.3680043.10.999.3")
            with socket.socket() as probe:
                probe.bind(("127.0.0.1", 0))
                port = probe.getsockname()[1]
            with tempfile.TemporaryFile() as log:
                process = subprocess.Popen([executable, "--aet", "QRSCP", "--host", "127.0.0.1", "--port", str(port),
                    "--storage-directory", str(archive), "--patient-information-directory", str(patients), "--destination", f"MOVEDEST=127.0.0.1:{listener.server_address[1]}"], stdout=log, stderr=log)
                for _ in range(100):
                    if process.poll() is not None:
                        log.seek(0)
                        raise RuntimeError(log.read().decode())
                    try:
                        with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                            break
                    except OSError:
                        time.sleep(0.1)
                ae = AE(ae_title="QRSCU")
                for sop in [FIND, GET, ROOT_GET, ROOT_MOVE, BULK_GET, PATIENT, SC]:
                    ae.add_requested_context(sop)
                association = ae.associate("127.0.0.1", port, ae_title="QRSCP",
                    ext_neg=[extended(FIND, [1] * 7), extended(GET, [1, 1]), extended(ROOT_GET, [0, 1]),
                             extended(ROOT_MOVE, [0, 1]), extended(BULK_GET, [0, 1]), build_role(SC, scu_role=False, scp_role=True)],
                    evt_handlers=[(evt.EVT_C_STORE, store)])
                check(association.is_established, "association")
                try:
                    check(association.acceptor.sop_class_extended[FIND] == bytes([1, 1, 1, 1, 0, 0, 0]), "only implemented FIND options accepted")
                    check(association.acceptor.sop_class_extended[GET] == bytes([1, 0]), "relational retrieve accepted, conversion refused")
                    check(all(association.acceptor.sop_class_extended[sop] == bytes([0, 0]) for sop in [ROOT_GET, ROOT_MOVE, BULK_GET]),
                          "Annex Y/Z reserved byte and conversion refusal")
                    matches = list(association.send_c_find(query("STUDY", Modality="CT", PatientName="Anne Muller", StudyInstanceUID="", NumberOfStudyRelatedInstances=""), FIND))
                    pending = [data for status, data in matches if status.Status == 0xFF00]
                    check(len(pending) == 1 and int(pending[0].NumberOfStudyRelatedInstances) == 2, "relational/fuzzy FIND returns complete study counts")
                    matches = list(association.send_c_find(query("STUDY", StudyDate="20261020-20261021", StudyTime="2300-0100", TimezoneOffsetFromUTC="+0200"), FIND))
                    check(any(status.Status == 0xFF00 for status, _ in matches), "combined midnight range with timezone adjustment")
                    result = list(association.send_c_get(query("SERIES", SeriesInstanceUID=source.SeriesInstanceUID), GET))[-1][0]
                    check(result.Status == 0 and result.NumberOfCompletedSuboperations == 1, "relational GET without Study UID")
                    result = list(association.send_c_get(query("IMAGE", SOPInstanceUID=uid), ROOT_GET))[-1][0]
                    check(result.Status == 0 and received[-1].PixelData == source.PixelData, "Composite Instance Root GET by instance UID")
                    result = list(association.send_c_get(query("IMAGE", SOPInstanceUID=uid), BULK_GET))[-1][0]
                    check(result.Status == 0 and "PixelData" not in received[-1] and received[-1].SOPInstanceUID == uid, "bulk-free GET preserves identity")
                    check(received[-1].IconImageSequence[0].PixelData == b"\x01\x02", "bulk-free GET preserves icon pixels")
                    result = list(association.send_c_get(query("IMAGE", SOPInstanceUID=mr.SOPInstanceUID), BULK_GET))[-1][0]
                    check(result.Status == 0 and "WaveformData" not in received[-1].WaveformSequence[0]
                          and received[-1].WaveformSequence[0].NumberOfWaveformChannels == 1, "bulk-free GET strips waveform samples only")
                    patient_query = Dataset()
                    patient_query.PatientID, patient_query.IssuerOfPatientID = "P1", "DOMAIN"
                    patient_query.ContentTemplateSequence = [template]
                    patient_query.ConceptNameCodeSequence, patient_query.ContentSequence = [], []
                    patient_matches = list(association.send_c_find(patient_query, PATIENT))
                    patient_pending = [data for status, data in patient_matches if status.Status == 0xFF00]
                    check(len(patient_pending) == 1 and str(patient_pending[0].PatientName) == "Müller^Anne"
                          and patient_pending[0].ContentTemplateSequence[0].TemplateIdentifier == "9007", "Relevant Patient Information returns template content and UTF-8 PN")
                    patient_query.ContentTemplateSequence[0].TemplateIdentifier = "99999"
                    check(list(association.send_c_find(patient_query, PATIENT))[-1][0].Status == 0xC200, "unsupported patient template returns C200")
                    frame_query = query("FRAME", SOPInstanceUID=uid, SimpleFrameList=[2, 4])
                    result = list(association.send_c_get(frame_query, ROOT_GET))[-1][0]
                    check(result.Status == 0 and received[-1].PixelData == bytes([20, 21, 40, 41]), "FRAME GET selects native pixels")
                    check(received[-1].SOPInstanceUID != uid and received[-1].FrameExtractionSequence[0].MultiFrameSourceSOPInstanceUID == uid,
                          "FRAME GET generates a new UID and source provenance")
                    check(received[-1].ContentDate == "20261021", "FRAME GET adjusts timing across midnight")
                    calculated = query("FRAME", SOPInstanceUID=uid, CalculatedFrameList=[2, 4, 2])
                    result = list(association.send_c_get(calculated, ROOT_GET))[-1][0]
                    check(result.Status == 0 and received[-1].PixelData == bytes([20, 21, 40, 41]), "calculated frame list over DIMSE")
                    temporal = query("FRAME", SOPInstanceUID=uid, TimeRange=[1.0, 2.0])
                    result = list(association.send_c_get(temporal, ROOT_GET))[-1][0]
                    check(result.Status == 0 and received[-1].PixelData == bytes([20, 21, 30, 31]), "inclusive Time Range over DIMSE")
                    result = list(association.send_c_move(frame_query, "MOVEDEST", ROOT_MOVE))[-1][0]
                    check(result.Status == 0 and moved[-1].PixelData == bytes([20, 21, 40, 41]) and moved[-1].SOPInstanceUID != uid,
                          "FRAME MOVE sends the derived instance to the destination")
                    result = list(association.send_c_move(query("IMAGE", SOPInstanceUID=uid), "MOVEDEST", ROOT_MOVE))[-1][0]
                    check(result.Status == 0 and moved[-1].SOPInstanceUID == uid, "Composite Instance Root MOVE uses independent storage association")
                    result = list(association.send_c_get(query("FRAME", SOPInstanceUID=uid), ROOT_GET))[-1][0]
                    check(result.Status == 0xAA04, "invalid frame selector returns AA04 over DIMSE")
                    matches = list(association.send_c_find(query("STUDY", QueryRetrieveView="CLASSIC"), FIND))
                    check(matches[-1][0].Status == 0xA900, "unaccepted Query/Retrieve View rejected")
                finally:
                    association.release()
                validator = Path(executable).with_name("DcmValidate")
                if validator.is_file():
                    validated = subprocess.run([str(validator), str(archive / "ct.dcm"), str(root / "derived.dcm")], capture_output=True, text=True)
                    check(validated.returncode == 0, "source and derived Secondary Capture pass the local PS3.3 IOD validator: " + validated.stdout.strip())
                # A separate association proves that absent negotiation retains baseline rules.
                baseline = ae.associate("127.0.0.1", port, ae_title="QRSCP")
                try:
                    result = list(baseline.send_c_get(query("SERIES", SeriesInstanceUID=source.SeriesInstanceUID), GET))[-1][0]
                    check(result.Status == 0xA900, "baseline GET requires ancestor unique key")
                    matches = list(baseline.send_c_find(query("STUDY", PatientName="Muller^Anne"), FIND))
                    check(matches[-1][0].Status == 0 and not any(status.Status == 0xFF00 for status, _ in matches),
                          "baseline PN retains accents without fuzzy negotiation")
                finally:
                    baseline.release()
    finally:
        if process is not None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        listener.shutdown()
        receiver.shutdown()


if __name__ == "__main__":
    main(str(Path(sys.argv[1]).resolve()))
