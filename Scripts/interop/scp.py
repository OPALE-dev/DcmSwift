"""pynetdicom as SCP for a DcmSwift client: echo, storage, find, get."""
import sys
from pynetdicom import AE, evt, AllStoragePresentationContexts, ALL_TRANSFER_SYNTAXES
from pynetdicom.sop_class import (Verification, StudyRootQueryRetrieveInformationModelFind,
    StudyRootQueryRetrieveInformationModelGet)

port = int(sys.argv[1])
stored = {}

def on_store(event):
    ds = event.dataset
    ds.file_meta = event.file_meta
    stored[ds.SOPInstanceUID] = ds
    print('STORED', ds.SOPInstanceUID, event.context.transfer_syntax, flush=True)
    return 0x0000

def on_find(event):
    studies = {}
    for ds in stored.values():
        studies.setdefault(ds.StudyInstanceUID, ds)
    for uid in studies:
        if event.is_cancelled:
            yield (0xFE00, None); return
        match = event.identifier.__class__()
        match.QueryRetrieveLevel = 'STUDY'
        match.StudyInstanceUID = uid
        yield (0xFF00, match)

def on_get(event):
    yield len(stored)
    for ds in stored.values():
        yield (0xFF00, ds)

ae = AE(ae_title='PYSCP')
for context in AllStoragePresentationContexts:
    ae.add_supported_context(context.abstract_syntax, ALL_TRANSFER_SYNTAXES, scu_role=True, scp_role=True)
ae.add_supported_context(Verification)
ae.add_supported_context(StudyRootQueryRetrieveInformationModelFind)
ae.add_supported_context(StudyRootQueryRetrieveInformationModelGet)
server = ae.start_server(('127.0.0.1', port), block=False, evt_handlers=[
    (evt.EVT_C_STORE, on_store), (evt.EVT_C_FIND, on_find), (evt.EVT_C_GET, on_get)])
print('READY', flush=True)
sys.stdin.read()
server.shutdown()
