"""Instance Availability Notification with pynetdicom (PS3.4 R).

  ian.py PORT LISTEN_PORT
      Against `DcmServer -a PACS -p PORT -s DIR --ian-directory DIR2
      --ian-destination PYIAN=127.0.0.1:LISTEN_PORT --ian-delay 0.5`:
      pynetdicom sends notifications to DcmServer (one valid, one without
      Retrieve AE Title), then stores instances of two studies and must
      receive one notification per study from DcmServer.
"""
import sys, time
from pydicom.dataset import Dataset
from pydicom.uid import generate_uid, ExplicitVRLittleEndian
from pynetdicom import AE, evt
from pynetdicom.sop_class import InstanceAvailabilityNotification, SecondaryCaptureImageStorage


def check(cond, message):
    if not cond:
        print('FAIL', message, flush=True)
        sys.exit(1)
    print('OK  ', message, flush=True)


def notification(retrieve='PACS'):
    ds = Dataset()
    ds.ReferencedPerformedProcedureStepSequence = []
    ds.StudyInstanceUID = generate_uid()
    series = Dataset()
    series.SeriesInstanceUID = generate_uid()
    reference = Dataset()
    reference.ReferencedSOPClassUID = SecondaryCaptureImageStorage
    reference.ReferencedSOPInstanceUID = generate_uid()
    reference.InstanceAvailability = 'ONLINE'
    reference.RetrieveAETitle = retrieve
    series.ReferencedSOPSequence = [reference]
    ds.ReferencedSeriesSequence = [series]
    return ds


def instance(study, series):
    ds = Dataset()
    ds.SOPClassUID = SecondaryCaptureImageStorage
    ds.SOPInstanceUID = generate_uid()
    ds.StudyInstanceUID = study
    ds.SeriesInstanceUID = series
    ds.PatientID = 'P1'
    ds.file_meta = Dataset()
    ds.file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
    return ds


def main():
    port, listen_port = int(sys.argv[1]), int(sys.argv[2])
    received = []

    def on_create(event):
        received.append(event.attribute_list)
        return 0x0000, None

    listener = AE(ae_title='PYIAN')
    listener.add_supported_context(InstanceAvailabilityNotification)
    server = listener.start_server(('127.0.0.1', listen_port), block=False,
                                   evt_handlers=[(evt.EVT_N_CREATE, on_create)])

    ae = AE(ae_title='PYSCU')
    ae.add_requested_context(InstanceAvailabilityNotification)
    ae.add_requested_context(SecondaryCaptureImageStorage, ExplicitVRLittleEndian)
    assoc = ae.associate('127.0.0.1', port, ae_title='PACS')
    check(assoc.is_established, 'association')
    status, _ = assoc.send_n_create(notification(), InstanceAvailabilityNotification, generate_uid())
    check(status.Status == 0x0000, 'N-CREATE accepted by DcmServer')
    status, _ = assoc.send_n_create(notification(retrieve=''), InstanceAvailabilityNotification, generate_uid())
    check(status.Status == 0x0121, 'N-CREATE without Retrieve AE Title: 0121H')

    studies = [generate_uid(), generate_uid()]
    stored = {}
    for study, count in zip(studies, [2, 1]):
        series = generate_uid()
        for _ in range(count):
            ds = instance(study, series)
            status = assoc.send_c_store(ds)
            check(status.Status == 0x0000, 'C-STORE')
            stored.setdefault(study, set()).add(ds.SOPInstanceUID)
    assoc.release()

    for _ in range(50):
        if len(received) >= 2:
            break
        time.sleep(0.1)
    server.shutdown()
    check(len(received) == 2, f'one notification per study, {len(received)} received')
    for ds in received:
        instances = {item.ReferencedSOPInstanceUID for series in ds.ReferencedSeriesSequence
                     for item in series.ReferencedSOPSequence}
        check(instances == stored.get(ds.StudyInstanceUID), f'instances of study {ds.StudyInstanceUID}')
        item = ds.ReferencedSeriesSequence[0].ReferencedSOPSequence[0]
        check(item.InstanceAvailability == 'ONLINE' and item.RetrieveAETitle == 'PACS'
              and 'ReferencedPerformedProcedureStepSequence' in ds, 'Table R.3.2-1 attributes')


if __name__ == '__main__':
    main()
