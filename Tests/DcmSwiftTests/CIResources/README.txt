This tracked directory is reserved for small synthetic fixtures required by the
unit-test suite. Synthetic RT fixtures are currently assembled deterministically
by the test fixture builders so that their intent remains reviewable in source.

Large DICOM, DICOMDIR, SR, and RT corpora are not SwiftPM resources. They are an
optional interoperability qualification input selected with the
DCMSWIFT_INTEROP_CORPUS environment variable.
