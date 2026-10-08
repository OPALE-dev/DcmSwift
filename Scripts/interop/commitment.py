"""Storage Commitment with pynetdicom (PS3.4 Annex J).

  commitment.py scu PORT CLASS:INSTANCE...
                          pynetdicom SCU against a DcmSwift SCP (AE "SCP")
                          holding those instances,
                          result on the same association, then on a new
                          one to a pynetdicom listener (AE "PYSCU", PORT+1).
  commitment.py scp PORT  pynetdicom storage and Storage Commitment SCP
                          (AE "PYSCP"): commits the instances it stored,
                          and answers on the same association.
"""
import sys, threading, time
from pydicom.dataset import Dataset
from pydicom.uid import generate_uid
from pynetdicom import AE, evt, build_role, AllStoragePresentationContexts, ALL_TRANSFER_SYNTAXES
from pynetdicom.sop_class import StorageCommitmentPushModel, Verification

INSTANCE = '1.2.840.10008.1.20.1.1'
SC = '1.2.840.10008.5.1.4.1.1.7'

def check(cond, message):
    if not cond:
        print('FAIL', message, flush=True); sys.exit(1)

def request(references):
    ds = Dataset()
    ds.TransactionUID = generate_uid()
    ds.ReferencedSOPSequence = []
    for sop_class, uid in references:
        item = Dataset(); item.ReferencedSOPClassUID = sop_class; item.ReferencedSOPInstanceUID = uid
        ds.ReferencedSOPSequence.append(item)
    return ds

mode, port = sys.argv[1], int(sys.argv[2])

if mode == 'scu':
    references = [tuple(argument.split(':')) for argument in sys.argv[3:]]
    uids = [uid for _, uid in references]
    reports = []
    def on_report(event):
        reports.append((event.event_type, event.event_information))
        return 0x0000, None
    # Results on a new association.
    listener = AE(ae_title='PYSCU')
    listener.add_supported_context(StorageCommitmentPushModel, scu_role=True, scp_role=True)
    server = listener.start_server(('127.0.0.1', port + 1), block=False,
                                   evt_handlers=[(evt.EVT_N_EVENT_REPORT, on_report)])
    ae = AE(ae_title='PYSCU')
    ae.add_requested_context(StorageCommitmentPushModel)
    assoc = ae.associate('127.0.0.1', port, ae_title='SCP', evt_handlers=[(evt.EVT_N_EVENT_REPORT, on_report)])
    check(assoc.is_established, 'association')
    ds = request(references + [(SC, '1.2.826.0.1.97.99')])
    status, _ = assoc.send_n_action(ds, 1, StorageCommitmentPushModel, INSTANCE)
    check(status and status.Status == 0, 'N-ACTION %s' % status)
    for _ in range(50):
        if reports: break
        time.sleep(0.1)
    assoc.release()
    check(len(reports) == 1, 'same-association report: %d' % len(reports))
    event_type, info = reports[0]
    check(event_type == 2, 'event type %s' % event_type)
    check(info.TransactionUID == ds.TransactionUID, 'transaction')
    check(sorted(i.ReferencedSOPInstanceUID for i in info.ReferencedSOPSequence) == sorted(uids), 'committed')
    check([(i.ReferencedSOPInstanceUID, i.FailureReason) for i in info.FailedSOPSequence] == [('1.2.826.0.1.97.99', 0x0112)], 'failed')
    # Release at once: the result comes on a new association.
    reports.clear()
    assoc = ae.associate('127.0.0.1', port, ae_title='SCP')
    ds = request(references)
    status, _ = assoc.send_n_action(ds, 1, StorageCommitmentPushModel, INSTANCE)
    assoc.release()
    check(status and status.Status == 0, 'second N-ACTION')
    for _ in range(100):
        if reports: break
        time.sleep(0.1)
    server.shutdown()
    check(len(reports) == 1 and reports[0][0] == 1, 'new-association report %s' % reports)
    check(reports[0][1].TransactionUID == ds.TransactionUID, 'second transaction')
    print('OK')
else:
    stored = set()
    def on_store(event):
        stored.add(event.request.AffectedSOPInstanceUID)
        return 0x0000
    def on_action(event):
        info = event.action_information
        def report():
            result = Dataset()
            result.TransactionUID = info.TransactionUID
            ok = [i for i in info.ReferencedSOPSequence if i.ReferencedSOPInstanceUID in stored]
            bad = [i for i in info.ReferencedSOPSequence if i.ReferencedSOPInstanceUID not in stored]
            if ok: result.ReferencedSOPSequence = ok
            if bad:
                for i in bad: i.FailureReason = 0x0112
                result.FailedSOPSequence = bad
            time.sleep(0.2)
            event.assoc.send_n_event_report(result, 2 if bad else 1, StorageCommitmentPushModel, INSTANCE)
        threading.Thread(target=report).start()
        return 0x0000, None
    ae = AE(ae_title='PYSCP')
    for context in AllStoragePresentationContexts:
        ae.add_supported_context(context.abstract_syntax, ALL_TRANSFER_SYNTAXES)
    ae.add_supported_context(StorageCommitmentPushModel)
    ae.add_supported_context(Verification)
    ae.start_server(('127.0.0.1', port), block=False,
                    evt_handlers=[(evt.EVT_N_ACTION, on_action), (evt.EVT_C_STORE, on_store)])
    print('READY', flush=True)
    sys.stdin.read()
