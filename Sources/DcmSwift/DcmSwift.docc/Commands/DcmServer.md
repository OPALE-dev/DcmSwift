# DcmServer

Serve verification, storage, Query/Retrieve, and Storage Commitment over a
directory.

```sh
DcmServer --aet DCMSERVER --port 11112
DcmServer --aet ARCHIVE --storage-directory ./archive --port 11112
DcmServer -a DCMSERVER -p 11112 -s /data/archive --destination VIEWER=10.0.0.5:104
```

Without `--storage-directory`, only C-ECHO is served. With a storage directory,
received instances are persisted and indexed for C-FIND, C-MOVE, and C-GET.
Move destinations and Storage Commitment callback destinations use repeated
`--destination AET=host:port` options. TLS and mutual TLS are available through
the certificate, key, and client-CA options.

With `--http-port`, the storage directory is also served over DICOMweb
(QIDO-RS, WADO-RS, STOW-RS) under `--http-base-path` (default `/dicomweb`), over
HTTPS when the TLS certificate options are given. `--http-public-origin` sets
the scheme and authority used in Retrieve URLs behind a reverse proxy:

```sh
DcmServer -s ./archive --http-port 8080
curl -H 'Accept: application/dicom+json' 'http://localhost:8080/dicomweb/studies?PatientID=12345'
```

See <doc:DICOMweb>.

`--validate` checks received instances, by C-STORE or STOW-RS, against their
IOD in PS3.3:

| Policy | Instance that does not conform |
| --- | --- |
| `off` (default) | Stored, not validated |
| `warn` | Stored; C-STORE answers Status B007H, STOW-RS the Warning Reason B007H; the findings are logged |
| `reject` | Not stored; C-STORE answers Status A900H, STOW-RS the Failure Reason A900H |

Instances of a SOP Class without an IOD in PS3.3, such as a retired one, are
stored either way.

`--audit` sends audit messages (PS3.15 A.5) to syslog collectors, over TLS or
UDP: start and stop, instances received and sent, queries, retrievals,
rejected associations, and user logins.

```sh
DcmServer -s ./archive --audit tls://audit.example.org --audit-tls-ca ca.pem
DcmServer -s ./archive --audit udp://127.0.0.1:514
```

This is a demonstrator and interoperability tool. Production deployment still
requires access control, durable indexing, audit logging, monitoring, backup,
and an operational security review.

## Modality Worklist

With `--worklist-directory`, `DcmServer` is a Modality Worklist SCP. The
directory is read at each query, recursively: Part 10 files, data sets
without File Meta Information (such as the `.wl` files of DCMTK `wlmscpfs`),
and DICOM JSON files (`.json`) are worklist items. It needs no storage
directory.

```sh
DcmServer -a RIS --worklist-directory ./worklist
```

## Modality Performed Procedure Step

With `--mpps-directory`, `DcmServer` is an SCP of the Modality Performed
Procedure Step SOP Class and of its Retrieve SOP Class. Each step is kept
there as `<SOP Instance UID>.json` (DICOM JSON) and read again at start-up.
Requests are checked against PS3.4 Table F.7.2-1. Each `--mpps-notify
AET=host:port` receives the In Progress, Updated, Completed, and
Discontinued events (N-EVENT-REPORT of the Notification SOP Class).

```sh
DcmServer -a RIS --worklist-directory ./worklist \
  --mpps-directory ./mpps --mpps-notify PACS=pacs.example.org:11112
```
