# Command-Line Tools

DcmSwift ships focused executables for file inspection, transformation,
structured reports, and DIMSE networking.

Build every product in release mode:

```sh
swift build -c release
.build/release/DcmPrint /my/dicom/file.dcm
```

The resulting binaries are under `.build/release`; `swift build` puts debug
builds under `.build/debug`. Every command supports
`--help`; that output is the authoritative option reference for the checked-out
revision.

## Files and images

- <doc:DcmPrint> prints data sets as text, Native DICOM Model XML, or DICOM JSON.
- <doc:DcmConvert> renders DICOM frames as PNG, JPEG, TIFF, PGM, or PPM.
- <doc:DcmValidate> validates files against the IODs of PS3.3.
- <doc:DcmSign> signs files and verifies their Digital Signatures.
- <doc:DcmDocument> wraps PDF, CDA, STL, OBJ, and MTL documents in DICOM, or extracts them.
- <doc:DcmWaveform> prints the channels of a waveform instance or exports their samples.
- <doc:DcmAnonymize> de-identifies files with the PS3.15 Basic Profile and its options.
- <doc:DcmIzer> demonstrates wrapping an ordinary image in a DICOM file.
- <doc:DcmSR> prints structured-report trees or renders them as HTML.

## Networking

- <doc:DcmEcho> verifies a remote Application Entity.
- <doc:DcmStore> sends instances and can request Storage Commitment.
- <doc:DcmFind> performs Query/Retrieve C-FIND requests.
- <doc:DcmServer> provides verification, storage, query/retrieve, and Storage
  Commitment services over a directory, and serves it over DICOMweb.

The networking programs exit with status 1 when the association or any
operation fails, making them suitable for scripts and demonstrations.

## Network options

These options are shared by the networking programs:

| Option | Tools | Meaning |
| --- | --- | --- |
| `-c`, `--calling-aet` | SCU tools | Local AE title (default `DCMCLIENT`) |
| `-v`, `--verbose` | All | Log association and DIMSE details |
| `--timeout` | All | Seconds to connect, and for ARTIM (default 30) |
| `--idle-timeout` | All | Seconds without data before aborting; 0 disables it (default 120) |
| `--max-pdu` | All | Maximum Length Received, in bytes (default 65536) |

TLS options for the SCU tools:

| Option | Meaning |
| --- | --- |
| `--tls` | Connect with TLS 1.2 or later |
| `--tls-ca` | PEM CA certificates trusted for the server (default: the system's) |
| `--tls-certificate`, `--tls-key` | Client certificate chain and private key |
| `--tls-no-hostname-check` | Verify the server certificate but not its host name |

TLS options for <doc:DcmServer>:

| Option | Meaning |
| --- | --- |
| `--tls-certificate`, `--tls-key` | Accept TLS connections only |
| `--tls-client-ca` | Require client certificates signed by these CAs |
| `--destination-tls` | Reach C-MOVE destinations with TLS |
| `--destination-tls-ca`, `--destination-tls-certificate`, `--destination-tls-key` | Trust and credentials for C-MOVE destinations |
