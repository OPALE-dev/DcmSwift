"""Application Event Logging with pynetdicom (PS3.4 P).

  event_logging.py PORT
      pynetdicom SCU against `DcmServer -a LOG -p PORT --event-log-directory
      DIR`: procedural events (P.2) and substance administrations (P.3),
      valid and invalid, with their statuses and Action Reply.
"""
import sys
from pydicom.dataset import Dataset
from pynetdicom import AE
from pynetdicom.sop_class import ProceduralEventLogging, SubstanceAdministrationLogging

PROCEDURAL_INSTANCE = '1.2.840.10008.1.40.1'
SUBSTANCE_INSTANCE = '1.2.840.10008.1.42.1'


def check(cond, message):
    if not cond:
        print('FAIL', message, flush=True)
        sys.exit(1)
    print('OK  ', message, flush=True)


def code(value, scheme, meaning):
    item = Dataset()
    item.CodeValue, item.CodingSchemeDesignator, item.CodeMeaning = value, scheme, meaning
    return item


def procedural(study='1.2.826.0.1.3680043.2.1125.77'):
    ds = Dataset()
    ds.PatientID = 'P1'
    ds.StudyInstanceUID = study
    ds.StudyID = ''
    ds.SynchronizationFrameOfReferenceUID = ''
    ds.PerformedLocation = 'CATH LAB 1'
    ds.ValueType = 'CONTAINER'
    ds.ConceptNameCodeSequence = [code('121145', 'DCM', 'Description of Procedure')]
    ds.ContinuityOfContent = 'SEPARATE'
    comment = Dataset()
    comment.RelationshipType = 'CONTAINS'
    comment.ValueType = 'TEXT'
    comment.ConceptNameCodeSequence = [code('121106', 'DCM', 'Comment')]
    comment.TextValue = 'Catheter inserted'
    ds.ContentSequence = [comment]
    return ds


def substance(patient='P1'):
    ds = Dataset()
    ds.PatientName = 'DOE^JANE'
    ds.PatientID = patient
    ds.ProductName = 'Heparin'
    ds.SubstanceAdministrationDateTime = '20240706101500'
    ds.AdministrationRouteCodeSequence = []
    operator = Dataset()
    operator.PersonIdentificationCodeSequence = [code('123', 'L', 'Nurse Ann')]
    ds.OperatorIdentificationSequence = [operator]
    return ds


def main():
    ae = AE(ae_title='CATH')
    ae.add_requested_context(ProceduralEventLogging)
    ae.add_requested_context(SubstanceAdministrationLogging)
    assoc = ae.associate('127.0.0.1', int(sys.argv[1]), ae_title='LOG')
    check(assoc.is_established, 'association')

    status, reply = assoc.send_n_action(procedural(), 1, ProceduralEventLogging, PROCEDURAL_INSTANCE)
    check(status.Status == 0x0000 and reply.StudyInstanceUID == '1.2.826.0.1.3680043.2.1125.77'
          and reply.PatientID == 'P1', 'procedural event logged, Action Reply')
    status, _ = assoc.send_n_action(procedural(study=''), 1, ProceduralEventLogging, PROCEDURAL_INSTANCE)
    check(status.Status == 0xC103, 'procedural event without study: C103H')
    flat = procedural()
    del flat.ContentSequence
    status, _ = assoc.send_n_action(flat, 1, ProceduralEventLogging, PROCEDURAL_INSTANCE)
    check(status.Status == 0xC102, 'procedural event without content: C102H')
    status, _ = assoc.send_n_action(procedural(), 2, ProceduralEventLogging, PROCEDURAL_INSTANCE)
    check(status.Status == 0x0123, 'unknown Action Type: 0123H')

    status, _ = assoc.send_n_action(substance(), 1, SubstanceAdministrationLogging, SUBSTANCE_INSTANCE)
    check(status.Status == 0x0000, 'substance administration logged')
    status, _ = assoc.send_n_action(substance(patient=''), 1, SubstanceAdministrationLogging, SUBSTANCE_INSTANCE)
    check(status.Status == 0xC110, 'substance administration without patient: C110H')
    assoc.release()


if __name__ == '__main__':
    main()
