"""Independent C.3.5 view conversion/restart/FRAME check.

Usage: python enhanced_views.py /path/to/DcmServer
Requires pydicom and pynetdicom; starts only isolated temporary servers.
"""
import hashlib
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from pydicom.dataset import Dataset, FileDataset, FileMetaDataset
from pydicom.uid import ExplicitVRLittleEndian, generate_uid
from pynetdicom import AE, evt, build_role
from pynetdicom.pdu_primitives import SOPClassExtendedNegotiation

CT = "1.2.840.10008.5.1.4.1.1.2"
ENH = "1.2.840.10008.5.1.4.1.1.2.2"
SR = "1.2.840.10008.5.1.4.1.1.88.34"
FIND = "1.2.840.10008.5.1.4.1.2.2.1"
GET = "1.2.840.10008.5.1.4.1.2.4.3"
MOVE = "1.2.840.10008.5.1.4.1.2.4.2"


def check(value, description):
    if not value:
        raise AssertionError(description)
    print("OK", description, flush=True)


def code(value, meaning):
    result = Dataset()
    result.CodeValue, result.CodingSchemeDesignator, result.CodeMeaning = value, "99TEST", meaning
    return result


def dataset(path, sop_class, study, series):
    meta = FileMetaDataset()
    meta.MediaStorageSOPClassUID, meta.MediaStorageSOPInstanceUID = sop_class, generate_uid()
    meta.TransferSyntaxUID = ExplicitVRLittleEndian
    result = FileDataset(str(path), {}, file_meta=meta, preamble=b"\0" * 128)
    result.SOPClassUID, result.SOPInstanceUID = sop_class, meta.MediaStorageSOPInstanceUID
    result.StudyInstanceUID, result.SeriesInstanceUID = study, series
    result.PatientID, result.PatientName, result.PatientBirthDate, result.PatientSex = "P1", "Doe^Jane", "", "F"
    result.StudyDate = result.ContentDate = result.SeriesDate = result.AcquisitionDate = "20261021"
    result.StudyTime = result.ContentTime = result.SeriesTime = result.AcquisitionTime = "120000"
    result.StudyID, result.AccessionNumber, result.ReferringPhysicianName = "1", "", ""
    result.SeriesNumber, result.InstanceNumber, result.Manufacturer = 1, 1, "Test"
    return result


def fixture(root):
    study, series = generate_uid(), generate_uid()
    images = []
    for i in (1, 2):
        path = root / f"ct-{i}.dcm"
        image = dataset(path, CT, study, series)
        image.Modality, image.ImageType = "CT", ["ORIGINAL", "PRIMARY", "AXIAL"]
        image.InstanceNumber, image.AcquisitionNumber = i, 1
        image.FrameOfReferenceUID, image.PositionReferenceIndicator = "1.2.826.0.1.3680043.10.999.99", ""
        image.Rows = image.Columns = 2
        image.SamplesPerPixel, image.PhotometricInterpretation = 1, "MONOCHROME2"
        image.BitsAllocated = image.BitsStored = 16
        image.HighBit, image.PixelRepresentation = 15, 0
        image.ImagePositionPatient, image.ImageOrientationPatient = [0, 0, i], [1, 0, 0, 0, 1, 0]
        image.PixelSpacing, image.SliceThickness, image.BodyPartExamined = [1, 1], 1, "CHEST"
        image.RescaleIntercept, image.RescaleSlope, image.RescaleType, image.KVP = "0", "1", "HU", "120"
        image.WindowCenter, image.WindowWidth = "40", "400"
        image.PixelData = b"".join(bytes([i * 10 + n, 0]) for n in range(4))
        image.save_as(path, enforce_file_format=True)
        images.append(image)
    sr = dataset(root / "sr.dcm", SR, study, generate_uid())
    sr.Modality, sr.CompletionFlag, sr.VerificationFlag = "SR", "COMPLETE", "UNVERIFIED"
    sr.ValueType, sr.ContinuityOfContent = "CONTAINER", "SEPARATE"
    sr.ConceptNameCodeSequence = [code("1", "Summary")]
    sr.ReferencedPerformedProcedureStepSequence = sr.PerformedProcedureCodeSequence = []
    ref = Dataset()
    ref.ReferencedSOPClassUID, ref.ReferencedSOPInstanceUID = CT, images[1].SOPInstanceUID
    child = Dataset()
    child.RelationshipType, child.ValueType = "CONTAINS", "IMAGE"
    child.ConceptNameCodeSequence, child.ReferencedSOPSequence = [code("2", "Image")], [ref]
    sr.ContentSequence = [child]
    evidence_study, evidence_series = Dataset(), Dataset()
    evidence_study.StudyInstanceUID, evidence_series.SeriesInstanceUID = study, series
    evidence_series.ReferencedSOPSequence = [ref]
    evidence_study.ReferencedSeriesSequence = [evidence_series]
    sr.CurrentRequestedProcedureEvidenceSequence = [evidence_study]
    sr.save_as(root / "sr.dcm", enforce_file_format=True)
    return images, sr


def extension(sop, fields):
    item = SOPClassExtendedNegotiation()
    item.sop_class_uid, item.service_class_application_information = sop, bytes(fields)
    return item


class Server:
    def __init__(self, executable, root, move_port):
        self.executable, self.root, self.process = executable, root, None
        self.port = None
        self.move_port = move_port
        self.log = tempfile.TemporaryFile()

    def start(self):
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            self.port = probe.getsockname()[1]
        self.process = subprocess.Popen([self.executable, "--aet", "VIEWS", "--host", "127.0.0.1", "--port", str(self.port), "--storage-directory", str(self.root), "--destination", f"VIEWDEST=127.0.0.1:{self.move_port}"], stdout=self.log, stderr=self.log)
        for _ in range(100):
            if self.process.poll() is not None:
                self.log.seek(0)
                raise RuntimeError(self.log.read().decode())
            try:
                with socket.create_connection(("127.0.0.1", self.port), timeout=0.1):
                    return
            except OSError:
                time.sleep(0.1)
        raise RuntimeError("server did not bind")

    def stop(self):
        if self.process:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
            self.process = None

    def close(self):
        self.stop()
        self.log.close()


def connect(server, received):
    def store(event):
        data = event.dataset
        data.file_meta = event.file_meta
        received.append(data)
        return 0
    ae = AE(ae_title="VIEWSCU")
    for sop in [FIND, GET, MOVE, CT, ENH, SR]:
        ae.add_requested_context(sop, [ExplicitVRLittleEndian])
    assoc = ae.associate("127.0.0.1", server.port, ae_title="VIEWS", ext_neg=[extension(FIND, [1, 1, 1, 1, 1]), extension(GET, [0, 1]), extension(MOVE, [0, 1])]
        + [build_role(sop, scu_role=False, scp_role=True) for sop in [CT, ENH, SR]], evt_handlers=[(evt.EVT_C_STORE, store)])
    check(assoc.is_established, "association")
    check(assoc.acceptor.sop_class_extended[FIND] == bytes([1, 1, 1, 1, 1]), "conversion accepted for FIND")
    check(assoc.acceptor.sop_class_extended[GET] == bytes([0, 1]), "conversion accepted for Composite Instance Root GET")
    return assoc


def find(assoc, view):
    query = Dataset()
    query.QueryRetrieveLevel, query.QueryRetrieveView = "IMAGE", view
    query.SOPInstanceUID = query.SOPClassUID = query.SeriesInstanceUID = ""
    responses = list(assoc.send_c_find(query, FIND))
    check(responses[-1][0].Status == 0, "FIND " + view)
    return {str(data.SOPInstanceUID): str(data.SOPClassUID) for status, data in responses if status.Status == 0xFF00}


def get(assoc, uid, view, received, frames=None):
    query = Dataset()
    query.QueryRetrieveLevel, query.QueryRetrieveView, query.SOPInstanceUID = "IMAGE", view, uid
    if frames is not None:
        query.QueryRetrieveLevel, query.SimpleFrameList = "FRAME", frames
    count = len(received)
    responses = list(assoc.send_c_get(query, GET))
    check(responses[-1][0].Status == 0 and len(received) == count + 1, "GET " + view + (" FRAME" if frames else " IMAGE"))
    return received[-1]


def main(executable):
    with tempfile.TemporaryDirectory(prefix="dcmswift-c35-") as directory:
        root = Path(directory)
        first, second = root / "classic", root / "enhanced"
        first.mkdir(); second.mkdir()
        images, source_sr = fixture(first)
        digests = {file.name: hashlib.sha256(file.read_bytes()).digest() for file in first.iterdir()}
        received, moved = [], []
        def store_moved(event):
            moved.append(event.dataset)
            return 0
        receiver = AE(ae_title="VIEWDEST")
        for sop in [CT, ENH, SR]:
            receiver.add_supported_context(sop, [ExplicitVRLittleEndian])
        listener = receiver.start_server(("127.0.0.1", 0), block=False, evt_handlers=[(evt.EVT_C_STORE, store_moved)])
        move_port = listener.server_address[1]
        server, inverse = Server(executable, first, move_port), Server(executable, second, move_port)
        try:
            server.start()
            assoc = connect(server, received)
            try:
                catalogue = find(assoc, "ENHANCED")
                check(sorted(catalogue.values()) == sorted([ENH, SR]), "complete enhanced image + dependent SR view")
                enhanced_uid = next(uid for uid, sop in catalogue.items() if sop == ENH)
                sr_uid = next(uid for uid, sop in catalogue.items() if sop == SR)
                enhanced = get(assoc, enhanced_uid, "ENHANCED", received)
                sr = get(assoc, sr_uid, "ENHANCED", received)
                query = Dataset()
                query.QueryRetrieveLevel, query.QueryRetrieveView, query.SOPInstanceUID = "IMAGE", "ENHANCED", enhanced_uid
                responses = list(assoc.send_c_move(query, "VIEWDEST", MOVE))
                check(responses[-1][0].Status == 0 and len(moved) == 1 and moved[-1].SOPInstanceUID == enhanced_uid
                      and moved[-1].PixelData == enhanced.PixelData, "MOVE delivers the same converted view identity and pixels")
                query.QueryRetrieveLevel, query.SimpleFrameList = "FRAME", [2]
                responses = list(assoc.send_c_move(query, "VIEWDEST", MOVE))
                check(responses[-1][0].Status == 0 and len(moved) == 2 and moved[-1].SOPInstanceUID != enhanced_uid
                      and moved[-1].PixelData == images[1].PixelData, "MOVE extracts an enhanced frame over an independent storage association")
                check(enhanced.PixelData == images[0].PixelData + images[1].PixelData and int(enhanced.NumberOfFrames) == 2, "combined pixels preserved")
                check(str(enhanced.StudyInstanceUID) == str(images[0].StudyInstanceUID) and enhanced.SeriesInstanceUID != images[0].SeriesInstanceUID, "study preserved and new series")
                ref = sr.ContentSequence[0].ReferencedSOPSequence[0]
                check(ref.ReferencedSOPInstanceUID == enhanced_uid and int(ref.ReferencedFrameNumber) == 2 and ref.ReferencedSOPClassUID == ENH,
                      "SR UID, SOP class and frame reference rewritten")
                hierarchical = sr.CurrentRequestedProcedureEvidenceSequence[0].ReferencedSeriesSequence[0]
                check(hierarchical.SeriesInstanceUID == enhanced.SeriesInstanceUID, "hierarchical series reference rewritten")
                frame = get(assoc, enhanced_uid, "ENHANCED", received, [2])
                check(frame.PixelData == images[1].PixelData and frame.SOPInstanceUID != enhanced_uid and frame.SeriesInstanceUID == enhanced.SeriesInstanceUID, "enhanced FRAME extracts pixels with Annex Y identity")
                for obj in [enhanced, sr]:
                    obj.save_as(second / (str(obj.SOPInstanceUID) + ".dcm"), enforce_file_format=True)
                check(set(find(assoc, "CLASSIC")) == {str(images[0].SOPInstanceUID), str(images[1].SOPInstanceUID), str(source_sr.SOPInstanceUID)}, "classic view of classic originals unchanged")
            finally:
                assoc.release()
            server.stop(); server.start()
            assoc = connect(server, received)
            try:
                check(find(assoc, "ENHANCED") == catalogue, "view identities stable after restart")
            finally:
                assoc.release()
            server.stop()
            inverse.start()
            assoc = connect(inverse, received)
            try:
                catalogue = find(assoc, "CLASSIC")
                check(sorted(catalogue.values()) == sorted([CT, CT, SR]), "inverse view contains two classic frames and SR")
                recovered = [get(assoc, uid, "CLASSIC", received) for uid, sop in catalogue.items() if sop == CT]
                check(sorted(obj.PixelData for obj in recovered) == sorted(obj.PixelData for obj in images), "inverse pixels preserved")
                report = get(assoc, next(uid for uid, sop in catalogue.items() if sop == SR), "CLASSIC", received)
                ref = report.ContentSequence[0].ReferencedSOPSequence[0]
                check(ref.ReferencedSOPInstanceUID in {obj.SOPInstanceUID for obj in recovered} and "ReferencedFrameNumber" not in ref, "inverse SR reference points to a classic instance")
                for obj in recovered + [report, frame]:
                    obj.save_as(root / (str(obj.SOPInstanceUID) + ".dcm"), enforce_file_format=True)
                validator = Path(executable).with_name("DcmValidate")
                if validator.is_file():
                    paths = [str(file) for file in list(first.glob("*.dcm")) + list(second.glob("*.dcm")) + list(root.glob("*.dcm"))]
                    result = subprocess.run([str(validator), *paths], text=True, capture_output=True)
                    check(result.returncode == 0, "source, both converted views, dependent SR and FRAME pass PS3.3 IOD validation: " + result.stdout.strip())
            finally:
                assoc.release()
            check({file.name: hashlib.sha256(file.read_bytes()).digest() for file in first.iterdir()} == digests, "stored originals unchanged")
        finally:
            server.close(); inverse.close()
            listener.shutdown()


if __name__ == "__main__":
    main(str(Path(sys.argv[1]).resolve()))
