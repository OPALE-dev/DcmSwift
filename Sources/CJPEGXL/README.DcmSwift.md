# Vendored libjxl

This target contains the decoder and encoder sources from libjxl 0.12.0,
commit `a7a9c787341cf703dede03c2009fa460cae5e5df`, with the third-party code
pinned by that release:

- Highway (runtime only), Apache-2.0, `third_party/highway/LICENSE`;
- Brotli 1.2.1 (`c/common`, `c/dec`, `c/enc`, and the public headers),
  tag `v1.2.1`, commit `db24a98aed38a16de78cc05ca15cdd8dc2a0d92d`, MIT,
  `third_party/brotli/LICENSE`. It is newer than the 1.2.0 that libjxl
  0.12.0 pins: 1.2.1 fixes an out-of-bounds write of the decoder on
  block-type switches (`c/dec/decode.c`) and changes nothing else in the
  vendored files but the version and a new decoder error code;
- skcms (`skcms.cc` and the baseline transform), commit
  `96d9171c94b937a1b5f0293de7309ac16311b722`, BSD-3-Clause,
  `third_party/skcms/LICENSE`.

The upstream files are unchanged. Only the source files of
`JPEGXL_INTERNAL_DEC_SOURCES`, `JPEGXL_INTERNAL_DEC_JPEG_SOURCES`,
`JPEGXL_INTERNAL_DEC_BOX_SOURCES`, `JPEGXL_INTERNAL_ENC_SOURCES`,
`jxl/cms/jxl_cms.cc`, and the thread parallel runner are included.

The generated `jxl/version.h`, `jxl/jxl_export.h`, `jxl/jxl_cms_export.h`, and
`jxl/jxl_threads_export.h` headers are provided by hand for the static SwiftPM
target. JPEG transcoding is enabled (JPEG recompression in both directions);
arbitrary box content decoding is disabled. skcms is built without its AVX2
and AVX-512 paths (`SKCMS_DISABLE_HSW`, `SKCMS_DISABLE_SKX`), which need
per-file compiler flags.

## Assertions

`Package.swift` defines `NDEBUG` for this target in release builds only, so
that a malformed codestream is refused with an error instead of failing an
`assert` and aborting the whole process. This matters most for libjxl: without `NDEBUG` it is a
debug build (`lib/jxl/base/compiler_specific.h`), where `JXL_ENSURE`,
`JXL_DASSERT`, `JXL_UNREACHABLE`, and `JXL_DEBUG_ABORT` call `jxl::Abort()`;
with it, `JXL_ENSURE` returns an error and the others compile to nothing. The
define reaches the C sources (Brotli, skcms) and the C++ sources (libjxl,
Highway). `Scripts/crosscheck/jpegxl_fuzz.sh` checks that no release object
refers to `jxl::Abort` and decodes mutated codestreams in both builds. Debug builds keep the
assertions, so tests and the crosscheck scripts still report a violated
invariant.

Upstream license: BSD-3-Clause (`LICENSE`).
