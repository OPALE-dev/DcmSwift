# DcmFind

Query a remote Query/Retrieve SCP with C-FIND.

```sh
DcmFind PACS pacs.example.org 11112 --level STUDY \
  --key 'PatientName=DOE*' --key 'StudyDate=20240101-20241231'
DcmFind PACS pacs.example.org 11112 -l SERIES -k StudyInstanceUID=1.2.3 -k Modality
```

Query a Modality Worklist SCP with `--model worklist`; keys inside a sequence
are written `Sequence[0].Keyword`:

```sh
DcmFind RIS ris.example.org 11112 -m worklist \
  -k 'ScheduledProcedureStepSequence[0].ScheduledStationAETitle=CT1' \
  -k 'ScheduledProcedureStepSequence[0].ScheduledProcedureStepStartDate=20240705-20240707' \
  -k PatientName -k PatientID
```

Without keys, a worklist query requests the patient, the Requested Procedure,
and the main attributes of the Scheduled Procedure Step. Responses print the
attributes of sequence Items indented with `>`.

Keys may be DICOM keywords or `gggg,eeee` tags. A key without `=value` requests
that attribute in the response. The command supports patient-, study-, series-,
and image-level queries, TLS, cancellation through `--limit`, and verbose DIMSE
logging.
