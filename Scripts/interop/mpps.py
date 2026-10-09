"""Modality Performed Procedure Step with pynetdicom (PS3.4 F.7 to F.9).

  mpps.py PORT NOTIFY_PORT
      pynetdicom SCU against `DcmServer -a MPPS -p PORT --mpps-directory DIR
      --mpps-notify RIS=127.0.0.1:NOTIFY_PORT`: N-CREATE, N-SET, and N-GET
      with the statuses of Table F.7.2-1 and F.7.2-2; a pynetdicom listener
      (AE "RIS", NOTIFY_PORT) must receive the In Progress, Updated, and
      Completed events (F.9).
"""
import sys, time
from pydicom.dataset import Dataset
from pydicom.uid import generate_uid
from pynetdicom import AE, evt
from pynetdicom.sop_class import (ModalityPerformedProcedureStep, ModalityPerformedProcedureStepRetrieve,
                                  ModalityPerformedProcedureStepNotification)


def check(cond, message):
    if not cond:
        print('FAIL', message, flush=True)
        sys.exit(1)
    print('OK  ', message, flush=True)


def step(status='IN PROGRESS'):
    ds = Dataset()
    scheduled = Dataset()
    scheduled.StudyInstanceUID = generate_uid()
    scheduled.ReferencedStudySequence = []
    scheduled.AccessionNumber = 'A1'
    scheduled.RequestedProcedureID = 'RP1'
    scheduled.RequestedProcedureDescription = ''
    scheduled.ScheduledProcedureStepID = 'SPS1'
    scheduled.ScheduledProcedureStepDescription = ''
    scheduled.ScheduledProtocolCodeSequence = []
    ds.ScheduledStepAttributesSequence = [scheduled]
    ds.PatientName = 'DOE^JANE'
    ds.PatientID = 'P1'
    ds.PatientBirthDate = ''
    ds.PatientSex = 'F'
    ds.ReferencedPatientSequence = []
    ds.PerformedProcedureStepID = 'PPS1'
    ds.PerformedStationAETitle = 'CT1'
    ds.PerformedStationName = ''
    ds.PerformedLocation = ''
    ds.PerformedProcedureStepStartDate = '20240706'
    ds.PerformedProcedureStepStartTime = '080000'
    ds.PerformedProcedureStepStatus = status
    ds.PerformedProcedureStepDescription = ''
    ds.PerformedProcedureTypeDescription = ''
    ds.ProcedureCodeSequence = []
    ds.PerformedProcedureStepEndDate = ''
    ds.PerformedProcedureStepEndTime = ''
    ds.Modality = 'CT'
    ds.StudyID = ''
    ds.PerformedProtocolCodeSequence = []
    ds.PerformedSeriesSequence = []
    return ds


def series():
    item = Dataset()
    item.PerformingPhysicianName = ''
    item.ProtocolName = 'Head'
    item.OperatorsName = ''
    item.SeriesInstanceUID = generate_uid()
    item.SeriesDescription = ''
    item.RetrieveAETitle = 'PACS'
    image = Dataset()
    image.ReferencedSOPClassUID = '1.2.840.10008.5.1.4.1.1.2'
    image.ReferencedSOPInstanceUID = generate_uid()
    item.ReferencedImageSequence = [image]
    item.ReferencedNonImageCompositeSOPInstanceSequence = []
    return item


def main():
    port, notify_port = int(sys.argv[1]), int(sys.argv[2])
    events = []

    def on_event(event):
        events.append(event.event_type)
        return 0x0000, None

    listener = AE(ae_title='RIS')
    listener.add_supported_context(ModalityPerformedProcedureStepNotification, scp_role=True, scu_role=True)
    server = listener.start_server(('127.0.0.1', notify_port), block=False,
                                   evt_handlers=[(evt.EVT_N_EVENT_REPORT, on_event)])

    ae = AE(ae_title='CT1')
    ae.add_requested_context(ModalityPerformedProcedureStep)
    ae.add_requested_context(ModalityPerformedProcedureStepRetrieve)
    assoc = ae.associate('127.0.0.1', port, ae_title='MPPS')
    check(assoc.is_established, 'association')
    uid = generate_uid()
    mpps = ModalityPerformedProcedureStep

    status, _ = assoc.send_n_create(step('COMPLETED'), mpps, uid)
    check(status.Status == 0x0106, 'N-CREATE not IN PROGRESS: 0106H')
    incomplete = step()
    del incomplete.PerformedStationName
    status, _ = assoc.send_n_create(incomplete, mpps, uid)
    check(status.Status == 0x0120, 'N-CREATE without a Type 2 attribute: 0120H')
    status, _ = assoc.send_n_create(step(), mpps, uid)
    check(status.Status == 0x0000, 'N-CREATE IN PROGRESS')
    status, _ = assoc.send_n_create(step(), mpps, uid)
    check(status.Status == 0x0111, 'N-CREATE of an existing instance: 0111H')

    forbidden = Dataset()
    forbidden.Modality = 'MR'
    status, _ = assoc.send_n_set(forbidden, mpps, uid)
    check(status.Status == 0x0106, 'N-SET of an attribute that may not be set: 0106H')
    update = Dataset()
    update.PerformedProcedureStepEndDate = '20240706'
    update.PerformedProcedureStepEndTime = '083000'
    update.PerformedSeriesSequence = [series()]
    status, _ = assoc.send_n_set(update, mpps, uid)
    check(status.Status == 0x0000, 'N-SET of the end and the series')
    final = Dataset()
    final.PerformedProcedureStepStatus = 'COMPLETED'
    status, _ = assoc.send_n_set(final, mpps, uid)
    check(status.Status == 0x0000, 'N-SET COMPLETED')
    late = Dataset()
    late.PerformedProcedureStepDescription = 'late'
    status, _ = assoc.send_n_set(late, mpps, uid)
    check(status.Status == 0x0110 and status.get('ErrorID') == 0xA710,
          'N-SET after COMPLETED: 0110H, Error ID A710H')

    status, attributes = assoc.send_n_get([0x00400252, 0x00400340], ModalityPerformedProcedureStepRetrieve, uid)
    check(status.Status == 0x0000 and attributes.PerformedProcedureStepStatus == 'COMPLETED'
          and len(attributes.PerformedSeriesSequence) == 1 and 'PatientName' not in attributes,
          'N-GET under the Retrieve SOP Class')
    assoc.release()

    for _ in range(50):
        if len(events) >= 3:
            break
        time.sleep(0.1)
    server.shutdown()
    check(events == [1, 4, 2], f'notifications In Progress, Updated, Completed: {events}')


if __name__ == '__main__':
    main()
