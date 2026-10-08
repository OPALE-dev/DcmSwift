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

GitLab CI runs the package on Linux (official Swift 6.1 image), and on a macOS
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
