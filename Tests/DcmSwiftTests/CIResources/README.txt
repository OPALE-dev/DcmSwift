This tracked directory is reserved for small synthetic fixtures required by the
unit-test suite. Synthetic RT fixtures are currently assembled deterministically
by the test fixture builders so that their intent remains reviewable in source.

jpeg-*.jpg are synthetic JPEG streams encoded by libjpeg-turbo (imagecodecs
2026.8.16 and Pillow 12.3.0). Each jpeg-*.ref holds the raw samples that
libjpeg-turbo 3.2.0 decodes from it with default settings (8-bit bytes, or
16-bit little endian words for 12-bit streams, RGB interleaved for color), and
jpeg-baseline-cases.json lists their dimensions. DcmSwift must decode them
identically.

jpeg-hier-*.jpg are 45x37 hierarchical streams encoded by the ISO reference
implementation (Thomas Richter's libjpeg, jpeg -y); each jpeg-hier-*.ref holds
that implementation's decoding, and jpeg-hierarchical-cases.json lists the
Transfer Syntax and the tolerance of each case. jpeg-sof11-rgb.jpg is a SOF11
RGB stream from the same encoder (-p -a -c, with a local fix for its missing
quantization table in predictive mode); jpeg-sof11-rgb.ref holds the original,
losslessly coded samples.

jpegls-*.jls are JPEG-LS streams listed in jpegls-cases.json. The "charls"
cases were encoded by CharLS 2.4 (with encoding options none) from the
matching .raw samples; "charls-hp" cases add its HP color transforms; the
"dcmswift" cases, which use restart intervals, were encoded by DcmSwift and
their .raw files hold CharLS's decoding. jpegls-conformance-* come from the
ITU-T T.87 Annex E conformance suite (t8nde0/t8nde3 and their source image).

jpeg2000-*.j2k are listed in jpeg2000-cases.json. The ht_* codestreams were
encoded by OpenJPH 0.31 (through imagecodecs 2026.8.16), independently of the
OpenJPEG decoder under test; jp2_rgb8_padded is an OpenJPEG JP2 file followed
by one padding byte, as in an even-length DICOM fragment. Lossless .raw files
hold the source samples; the lossy one holds OpenJPH's own decoding.

jpegxl-*.jxl are listed in jpegxl-cases.json. They were encoded and decoded by
imagecodecs 2026.8.16 with libjxl 0.12.0; matching .raw files contain the
independently decoded native pixels. The set covers lossless raw codestreams,
a lossless container, lossy coding, and reversible JPEG recompression.

Large DICOM, DICOMDIR, SR, and RT corpora are not SwiftPM resources. They are an
optional interoperability qualification input selected with the
DCMSWIFT_INTEROP_CORPUS environment variable.
