# DcmFind

Query a remote Query/Retrieve SCP with C-FIND.

```sh
DcmFind PACS pacs.example.org 11112 --level STUDY \
  --key 'PatientName=DOE*' --key 'StudyDate=20240101-20241231'
```

Keys may be DICOM keywords or `gggg,eeee` tags. A key without `=value` requests
that attribute in the response. The command supports patient-, study-, series-,
and image-level queries, TLS, cancellation through `--limit`, and verbose DIMSE
logging.
