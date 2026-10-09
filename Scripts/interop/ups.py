"""UPS DIMSE loopback check against DcmServer (PS3.4 Annex CC).

Run with `ups.py PORT` while DcmServer serves `--ups-directory` on PORT.
Checks the real DIMSE command SOP Class UID / negotiated abstract syntax split,
state lock, N-GET, and UPS Query C-FIND using pynetdicom as an independent peer.
"""
import sys
import time

from pydicom.dataset import Dataset
from pydicom.uid import generate_uid
from pynetdicom import AE, evt
from pynetdicom.sop_class import (
    UnifiedProcedureStepPush, UnifiedProcedureStepPull, UnifiedProcedureStepWatch,
    UnifiedProcedureStepQuery, UnifiedProcedureStepEvent,
)


def check(condition, description):
    if not condition:
        raise AssertionError(description)
    print("OK", description, flush=True)


def main(port, notify_port):
    reports = []

    def received(event):
        reports.append((event.event_type, event.event_information.ProcedureStepState))
        return 0x0000, None

    receiver = AE(ae_title="WATCHER")
    receiver.add_supported_context(UnifiedProcedureStepEvent, scp_role=True, scu_role=True)
    listener = receiver.start_server(("127.0.0.1", notify_port), block=False,
                                     evt_handlers=[(evt.EVT_N_EVENT_REPORT, received)])
    ae = AE(ae_title="UPSSCU")
    for sop in (UnifiedProcedureStepPush, UnifiedProcedureStepPull,
                UnifiedProcedureStepWatch, UnifiedProcedureStepQuery):
        ae.add_requested_context(sop)
    assoc = ae.associate("127.0.0.1", port, ae_title="UPSSCP")
    check(assoc.is_established, "association")
    uid = generate_uid()
    token = generate_uid()
    try:
        create = Dataset()
        create.ProcedureStepState = "SCHEDULED"
        create.ScheduledProcedureStepPriority = "MEDIUM"
        create.ProcedureStepLabel = "READ"
        create.ScheduledProcedureStepStartDateTime = "20261009140000+0200"
        create.InputReadinessState = "READY"
        create.TransactionUID = ""
        create.WorklistLabel = ""
        create.ScheduledProcessingParametersSequence = []
        create.ScheduledStationNameCodeSequence = []
        create.ScheduledStationClassCodeSequence = []
        create.ScheduledStationGeographicLocationCodeSequence = []
        create.ScheduledWorkitemCodeSequence = []
        create.CommentsOnTheScheduledProcedureStep = ""
        create.InputInformationSequence = []
        create.PatientName = ""
        create.IssuerOfPatientID = ""
        create.IssuerOfPatientIDQualifiersSequence = []
        create.OtherPatientIDsSequence = []
        create.PatientBirthDate = ""
        create.PatientSex = ""
        create.AdmissionID = ""
        create.IssuerOfAdmissionIDSequence = []
        create.AdmittingDiagnosesDescription = ""
        create.AdmittingDiagnosesCodeSequence = []
        create.ReferencedRequestSequence = []
        create.ProcedureStepProgressInformationSequence = []
        create.UnifiedProcedureStepPerformedProcedureSequence = []
        status, _ = assoc.send_n_create(create, UnifiedProcedureStepPush, uid)
        check(status.Status == 0, "N-CREATE scheduled")

        subscription = Dataset()
        subscription.ReceivingAE = "WATCHER"
        subscription.DeletionLock = "TRUE"
        status, _ = assoc.send_n_action(subscription, 3, UnifiedProcedureStepPush, uid,
                                        meta_uid=UnifiedProcedureStepWatch)
        check(status.Status == 0, "Watch subscription")

        get_status, attributes = assoc.send_n_get([0x00741000, 0x00081195],
                                                  UnifiedProcedureStepPush, uid)
        check(get_status.Status == 0 and attributes.ProcedureStepState == "SCHEDULED"
              and "TransactionUID" not in attributes, "N-GET hides Transaction UID")

        action = Dataset()
        action.ProcedureStepState = "IN PROGRESS"
        action.TransactionUID = token
        status, _ = assoc.send_n_action(action, 1, UnifiedProcedureStepPush, uid,
                                        meta_uid=UnifiedProcedureStepPull)
        check(status.Status == 0, "Pull Change State with Push command SOP Class")

        wrong = Dataset()
        wrong.TransactionUID = generate_uid()
        wrong.ProcedureStepState = "COMPLETED"
        status, _ = assoc.send_n_action(wrong, 1, UnifiedProcedureStepPush, uid,
                                        meta_uid=UnifiedProcedureStepPull)
        check(status.Status == 0xC301, "incorrect Transaction UID refused")

        query = Dataset()
        query.ProcedureStepState = "IN PROGRESS"
        query.SOPInstanceUID = ""
        found = [identifier for status, identifier in assoc.send_c_find(query, UnifiedProcedureStepQuery)
                 if status.Status == 0xFF00]
        check(len(found) == 1 and found[0].SOPInstanceUID == uid, "UPS Query C-FIND")
        for _ in range(30):
            if len(reports) >= 2:
                break
            time.sleep(0.1)
        check(reports == [(1, "SCHEDULED"), (1, "IN PROGRESS")],
              f"initial and state-change Event reports: {reports}")
    finally:
        assoc.release()
        listener.shutdown()


if __name__ == "__main__":
    main(int(sys.argv[1]), int(sys.argv[2]))
