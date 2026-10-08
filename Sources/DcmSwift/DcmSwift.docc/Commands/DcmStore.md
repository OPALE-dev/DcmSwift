# DcmStore

Send DICOM files to a Storage SCP. Directories are traversed recursively.

```sh
DcmStore PACS pacs.example.org 11112 image.dcm
DcmStore PACS pacs.example.org 2762 study/ --tls --commit
```

Each instance is proposed in its current transfer syntax and may be converted
between uncompressed syntaxes when required by negotiation. `--commit` requests
Storage Commitment after successful storage. The command exits with status 1
if any requested file is not stored or committed.
