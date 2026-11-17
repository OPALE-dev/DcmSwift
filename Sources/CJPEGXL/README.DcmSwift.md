# Vendored libjxl

This target contains the decoder and encoder sources from libjxl 0.12.0,
commit `a7a9c787341cf703dede03c2009fa460cae5e5df`, with the third-party code
pinned by that release:

- Highway (runtime only), Apache-2.0, `third_party/highway/LICENSE`;
- Brotli 1.2.0 (`c/common`, `c/dec`, `c/enc`, and the public headers),
  commit `028fb5a23661f123017c060daa546b55cf4bde29`, MIT,
  `third_party/brotli/LICENSE`;
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

Upstream license: BSD-3-Clause (`LICENSE`).
