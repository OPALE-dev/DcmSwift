# Vendored libjxl

This target contains the decoder sources from libjxl 0.12.0, commit
`a7a9c787341cf703dede03c2009fa460cae5e5df`, and Highway at the commit pinned
by that release. The upstream files are unchanged except that only the source
files required by `JPEGXL_INTERNAL_DEC_SOURCES` and the Highway runtime are
included.

The generated `jxl/version.h` and `jxl/jxl_export.h` headers are provided by
hand for the static SwiftPM target. JPEG transcoding output and arbitrary box
content decoding are disabled; ordinary codestream and container decoding,
including JPEG-recompression streams decoded to pixels, remains enabled.

Upstream license: BSD-3-Clause (`LICENSE`). Highway is Apache-2.0; its license
is retained as `third_party/highway/LICENSE`.
