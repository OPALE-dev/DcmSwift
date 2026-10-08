# Testing and Qualification

Build and test the package, run the interoperability corpus, and check
DcmSwift against other DICOM toolkits.

## Build and test

Run the package checks on macOS or Linux, as CI does:

```sh
swift build -c release
swift test --parallel
```

On macOS, build and test for iOS with Xcode:

```sh
xcodebuild build -scheme DcmSwift -destination 'generic/platform=iOS'
xcodebuild test -scheme DcmSwift-Package \
  -destination 'platform=iOS Simulator,name=<iPhone simulator>'
```

The mandatory unit suite uses only small, deterministic synthetic fixtures
versioned with the source. It runs identically in a clean checkout on every
platform, never depends on a private or downloaded corpus, and writes its
generated files to temporary directories that it removes. Tests are listed per
requirement in <doc:Traceability>.

## Interoperability corpus

Large DICOM, DICOMDIR, SR, and RT collections form a separate, optional
qualification suite. It recursively discovers `.dcm` and `.dicomdir` files:

```sh
DCMSWIFT_INTEROP_CORPUS=/absolute/path/to/corpus \
  swift test --filter DcmSwiftTests/testExternalDICOMCorpus
```

Without a corpus the suite is skipped; mandatory unit coverage is unchanged.
Set `DCMSWIFT_REQUIRE_INTEROP_CORPUS=1` to make a missing corpus fail the run.
A successful unit run does not claim interoperability with files that were not
qualified.

## Continuous integration

GitLab CI runs the package on Linux (official Swift 6.2 image), and on a macOS
runner with Xcode for macOS and the newest installed iOS Simulator runtime.

| Step | Behavior |
| --- | --- |
| Corpus | Each job downloads the confidential corpus from the project's private Generic Package Registry (`dcmswift-dicom-corpus`, version `DCM_CORPUS_VERSION`), verifies it against `DCM_CORPUS_SHA256`, and caches it per version |
| iOS | The job forwards the variables to the simulator with the `TEST_RUNNER_` prefix |
| Reports | SwiftPM writes JUnit reports with `swift test --parallel --xunit-output`; `Scripts/xcresult-junit.py` converts the iOS result bundle; every job publishes them to the pipeline Tests tab |
| Documentation | The DocC site is built with warnings as errors; see <doc:DocumentationWorkflow> |

GitHub Actions runs the same Linux, macOS, and iOS jobs in
`.github/workflows/ci.yml`, on `macos-26` runners for Apple platforms, and
uploads the JUnit reports as artifacts. It fetches the corpus only when the
`DCM_CORPUS_URL` and `DCM_CORPUS_TOKEN` secrets are set, through
`Scripts/ci/fetch-interop-corpus.sh`, with the version and checksum declared
in `.gitlab-ci.yml`; without them, the corpus suite is skipped.

To publish a new corpus version, upload the archive with a token that has the
`api` scope, then update both variables in `.gitlab-ci.yml`:

```sh
COPYFILE_DISABLE=1 tar --no-xattrs --exclude .DS_Store \
  -czf dcmswift-dicom-corpus.tar.gz \
  -s ',^Tests/DcmSwiftTests/Resources,dcmswift-dicom-corpus,' \
  Tests/DcmSwiftTests/Resources
shasum -a 256 dcmswift-dicom-corpus.tar.gz
curl --fail --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --upload-file dcmswift-dicom-corpus.tar.gz \
  "$GITLAB_URL/api/v4/projects/rw%2Fdcmswift/packages/generic/dcmswift-dicom-corpus/<version>/dcmswift-dicom-corpus.tar.gz"
```

## File cross-checks

`Scripts/crosscheck` compares the output of <doc:DcmPrint> with pydicom:

| Script | Check |
| --- | --- |
| `pydicom_json.py DCMPRINT [--pydicom-testdata] [PATH...]` | `DcmPrint -f JSON` against pydicom's `to_json_dict`, after normalization |
| `native_xml.py DCMPRINT [--pydicom-testdata] [PATH...]` | `DcmPrint -f XML` against the normative PS3.19 schema, and against pydicom through the PS3.18 F.3 mapping; needs `rnc2rng` and `lxml` |
| `dicomweb_client.py BASE_URL [--pydicom-testdata] [PATH...]` | The DICOMweb origin server of `DcmServer --http-port` against dicomweb-client: STOW-RS, QIDO-RS, then instances, metadata, frames, and rendered images compared with pydicom |

## JPIP

`DcmSwiftJPIPTests.testRetrievalFromAnIndependentJPIPServer` retrieves every
file of a directory served by a JPIP server, such as Kakadu's kdu_server, and
compares it with the file decoded directly. `Scripts/crosscheck/jpip_kakadu.sh`
then decodes the served files and the rebuilt codestreams with kdu_expand:

```sh
kdu_server -wd /path/to/images -restrict -port 8080 -address 127.0.0.1
DCMSWIFT_JPIP_ORACLE=http://127.0.0.1:8080 DCMSWIFT_JPIP_FILES=/path/to/images \
DCMSWIFT_JPIP_OUTPUT=/path/to/rebuilt swift test --filter DcmSwiftJPIPTests
Scripts/crosscheck/jpip_kakadu.sh /path/to/kakadu/bin /path/to/images /path/to/rebuilt
```

## DICOMweb user agent

`DcmSwiftWebInteropTests` stores files with `DICOMwebClient` in an
independent origin server and checks search, retrieval, metadata, frames, and
rendering against DcmSwift's reading of the files. It runs when both
variables are set:

```sh
DCMSWIFT_DICOMWEB_ORACLE=http://127.0.0.1:8042/dicom-web \
DCMSWIFT_DICOMWEB_FILES=/path/to/files \
  swift test --filter DcmSwiftWebInteropTests
```

Orthanc with its DICOMweb plugin is the reference, run over an empty
storage directory. The test leaves out empty attributes, which Orthanc drops,
and files that reuse another file's SOP Instance UID.

## Terminology

`Scripts/generate-dicom-terminology.py` rebuilds the terminology resource
from the PS3.16 DocBook; `--check` verifies that the bundled resource is up
to date. `Scripts/crosscheck/nema_valuesets.py` compares it with the FHIR
value sets NEMA publishes for the same edition, downloaded from
`https://dicom.nema.org/medical/dicom/resources/valuesets/fhir/json/`:

```sh
python3 Scripts/generate-dicom-terminology.py part16.xml Sources/DcmSwift/Resources/dicom-terminology-2026d.json --check
python3 Scripts/crosscheck/nema_valuesets.py Sources/DcmSwift/Resources/dicom-terminology-2026d.json /path/to/valuesets
```

## IOD validation

`Scripts/generate-dicom-iods.py` rebuilds the IOD resource from the PS3.3
and PS3.4 DocBook; `--check` verifies that the bundled resource is up to date.
`Scripts/crosscheck/dicom_validator.py` compares the findings of DcmValidate
with those of dicom-validator 0.9.0 (`pip install dicom-validator`), which
reads the same DocBook from its `-src` folder:

```sh
python3 Scripts/generate-dicom-iods.py part03.xml part04.xml Sources/DcmSwift/Resources/dicom-iods-2026d.json --check
python3 Scripts/crosscheck/dicom_validator.py .build/debug/DcmValidate /path/to/standard /path/to/files
```

## De-identification

`Scripts/generate-dicom-deidentification.py` rebuilds the de-identification
resource from the PS3.15 DocBook; `--check` verifies that the bundled
resource is up to date. `Scripts/crosscheck/dicom_anonymizer.py` compares it
with Kitware's dicom-anonymizer (`pip install dicom-anonymizer`): the actions
of its 2026c table, then the outcome of every attribute of each file
de-identified by both tools:

```sh
python3 Scripts/generate-dicom-deidentification.py part15.xml Sources/DcmSwift/Resources/dicom-deidentification-2026d.json --check
python3 Scripts/crosscheck/dicom_anonymizer.py Sources/DcmSwift/Resources/dicom-deidentification-2026d.json .build/debug/DcmAnonymize /path/to/files
```

## Audit trail

`Scripts/crosscheck/audit_syslog.py` starts DcmServer with a syslog
collector over TLS and UDP, stores, queries, and retrieves an instance, has
an association rejected, stops the server, and checks every message
received (`pip install rnc2rng lxml syslog-rfc5424-parser pynetdicom`):

```sh
python3 Scripts/crosscheck/audit_syslog.py part15.xml .build/debug image.dcm
```

## Digital Signatures

`Scripts/crosscheck/dcmsign.py` checks DcmSwift's signatures with DCMTK's
dcmsign, and dcmsign's with DcmSwift, for each file: SHA-1 to SHA-512 and
RIPEMD-160, a signed Sequence Item, and a changed file both must reject:

```sh
python3 Scripts/crosscheck/dcmsign.py .build/debug /path/to/files
```

## Encrypted attributes

`Scripts/crosscheck/cms_openssl.py` checks that `openssl cms` opens the
Encrypted Attributes DcmAnonymize writes, with both key transports, and that
DcmAnonymize restores the values of envelopes `openssl cms` makes:

```sh
python3 Scripts/crosscheck/cms_openssl.py .build/debug /path/to/files
```

## Encapsulated documents

`Scripts/crosscheck/encapsulated_documents.py` wraps a PDF, a CDA, a binary
STL, an OBJ, and an MTL document with DcmDocument, validates the instances,
and extracts them with dcmdecap; then DCMTK wraps them and DcmDocument
extracts them:

```sh
python3 Scripts/crosscheck/encapsulated_documents.py .build/debug /path/to/standard
```

## Waveforms

`Scripts/crosscheck/waveforms.py` compares DcmWaveform with pydicom's
`multiplex_array` on the files given and on files of every sample
interpretation it makes:

```sh
python3 Scripts/crosscheck/waveforms.py .build/debug /path/to/files
```

## Radiotherapy

`Scripts/crosscheck/rt_dicompyler.py` compares DcmRT with dicompyler-core,
which needs pydicom 2 (`pip install "pydicom<3" dicompyler-core`):

```sh
python3 Scripts/crosscheck/rt_dicompyler.py .build/debug /path/to/files
```

## Network interoperability

`Scripts/interop` drives pynetdicom 3 against DcmSwift:

| Script | Role |
| --- | --- |
| `scu.py` | Echo, store, find, get, and move against <doc:DcmServer> |
| `scp.py` | An SCP for <doc:DcmEcho>, <doc:DcmStore>, and <doc:DcmFind> |
| `commitment.py` | Storage Commitment in both roles |
| `tls.py` | DICOM over TLS with mutual authentication, using the fixtures of `Scripts/generate-tls-test-certificates.sh` |

DCMTK and dcm4che tools are good references for manual testing:

```sh
storescp 11112 --log-level trace                                  # DCMTK, detailed logs
storescp -b STORESCP@127.0.0.1:11112                              # dcm4che 5.x
dcmqrscp 11112 --log-level trace -c /path/to/config/dcmqrscp.cfg  # DCMTK, for C-FIND
```
