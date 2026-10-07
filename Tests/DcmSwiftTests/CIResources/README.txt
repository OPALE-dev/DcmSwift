This tracked directory is reserved for small synthetic fixtures required by the
unit-test suite. Synthetic RT fixtures are currently assembled deterministically
by the test fixture builders so that their intent remains reviewable in source.

jpeg-*.jpg are synthetic JPEG streams encoded by libjpeg-turbo (imagecodecs
2026.8.16 and Pillow 12.3.0). Each jpeg-*.ref holds the raw samples that
libjpeg-turbo 3.2.0 decodes from it with default settings (8-bit bytes, or
16-bit little endian words for 12-bit streams, RGB interleaved for color), and
jpeg-baseline-cases.json lists their dimensions. DcmSwift must decode them
identically.

Large DICOM, DICOMDIR, SR, and RT corpora are not SwiftPM resources. They are an
optional interoperability qualification input selected with the
DCMSWIFT_INTEROP_CORPUS environment variable.
