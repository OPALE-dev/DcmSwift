# DcmEcho

Send one or more C-ECHO requests to a remote DICOM Application Entity.

```sh
DcmEcho PACS pacs.example.org 11112
DcmEcho PACS pacs.example.org 2762 --tls --repeat 5
```

The command supports calling AE configuration, timeouts, maximum PDU length,
TLS trust, mutual TLS credentials, and verbose DIMSE logging. It exits with
status 1 when association or verification fails.
