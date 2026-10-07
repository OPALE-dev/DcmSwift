"""pynetdicom as SCU against a DcmSwift server: echo, store, find, get, move."""
import os, sys
import pydicom
from pydicom.data import get_testdata_file
from pydicom.dataset import Dataset
from pynetdicom import AE, build_role, evt
from pynetdicom.sop_class import (Verification, StudyRootQueryRetrieveInformationModelFind,
    StudyRootQueryRetrieveInformationModelGet, StudyRootQueryRetrieveInformationModelMove)
from pydicom.uid import ExplicitVRLittleEndian, ImplicitVRLittleEndian

port = int(sys.argv[1])
names = ['CT_small.dcm', 'MR_small.dcm', 'rtplan.dcm', 'JPEG2000.dcm', 'SC_rgb_jpeg_gdcm.dcm', 'MR_small_RLE.dcm']
files = [pydicom.dcmread(get_testdata_file(n)) for n in names]

def check(cond, message):
    if not cond:
        print('FAIL', message); sys.exit(1)

ae = AE(ae_title='PYSCU')
ae.add_requested_context(Verification)
for ds in files:
    ae.add_requested_context(ds.SOPClassUID, [ds.file_meta.TransferSyntaxUID])
assoc = ae.associate('127.0.0.1', port, ae_title='SCP')
check(assoc.is_established, 'association')
check(assoc.send_c_echo().Status == 0, 'echo')
for ds in files:
    status = assoc.send_c_store(ds)
    check(status and status.Status == 0, 'store %s' % ds.SOPInstanceUID)
assoc.release()

ae = AE(ae_title='PYSCU')
ae.add_requested_context(StudyRootQueryRetrieveInformationModelFind)
assoc = ae.associate('127.0.0.1', port, ae_title='SCP')
query = Dataset(); query.QueryRetrieveLevel = 'STUDY'; query.StudyInstanceUID = ''
matches = [identifier for status, identifier in assoc.send_c_find(query, StudyRootQueryRetrieveInformationModelFind)
           if status and status.Status in (0xFF00, 0xFF01)]
check(len(matches) == len({ds.StudyInstanceUID for ds in files}), 'find returned %d' % len(matches))
assoc.release()

received = []
def on_store(event):
    received.append((event.dataset.SOPInstanceUID, event.context.transfer_syntax))
    return 0x0000
ae = AE(ae_title='PYSCU')
ae.add_requested_context(StudyRootQueryRetrieveInformationModelGet)
roles = []
for ds in files:
    ae.add_requested_context(ds.SOPClassUID, [ds.file_meta.TransferSyntaxUID, ExplicitVRLittleEndian, ImplicitVRLittleEndian])
    roles.append(build_role(ds.SOPClassUID, scp_role=True))
assoc = ae.associate('127.0.0.1', port, ae_title='SCP', ext_neg=roles, evt_handlers=[(evt.EVT_C_STORE, on_store)])
check(assoc.is_established, 'get association')
final = None
for status, identifier in assoc.send_c_get(query, StudyRootQueryRetrieveInformationModelGet):
    final = status
check(final is not None and final.Status == 0, 'get status %s' % final)
check(sorted(received) == sorted((ds.SOPInstanceUID, ds.file_meta.TransferSyntaxUID) for ds in files), 'get received %s' % received)

ae = AE(ae_title='PYSCU')
ae.add_requested_context(StudyRootQueryRetrieveInformationModelMove)
assoc = ae.associate('127.0.0.1', port, ae_title='SCP')
final = None
for status, identifier in assoc.send_c_move(query, 'SCP', StudyRootQueryRetrieveInformationModelMove):
    final = status
check(final is not None and final.Status == 0 and final.NumberOfCompletedSuboperations == len(files), 'move %s' % final)
assoc.release()
print('OK')
