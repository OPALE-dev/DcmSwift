# Vendored OpenJPEG

- Upstream: https://github.com/uclouvain/openjpeg
- Version: 2.5.4, commit 6c4a29b00211eb0430fa0e5e890f1ce5c80f409f (2025-09-20)
- License: BSD 2-Clause (`LICENSE`)

Files from `src/lib/openjp2` are copied unchanged, except for the layout:
`openjpeg.h` and a hand-written `opj_config.h` form the public `include`
directory, and `opj_config_private.h` replaces the CMake-generated header.
The library sources listed in upstream `OPENJPEG_SRCS` are included; the
JPIP index managers, benchmarks, and table generators are not.

To update, copy the same files from a new release, then adjust the version
numbers in `include/opj_config.h`, `opj_config_private.h`, and this file.

## Local patches

Each patch below is applied on top of 2.5.4, as published upstream, and is
removed when a release contains it. `Scripts/crosscheck/openjpeg_asan.sh`
runs the cases they fix under AddressSanitizer.

| File | Reason | Upstream reference |
| --- | --- | --- |
| `dwt.c`, `opj_dwt_encode_and_deinterleave_v` | Reversible encoding of a resolution level with no rows at an odd start coordinate (a short edge tile with many decomposition levels) read and wrote past the end of the scratch buffer (CVE-2026-107080). Return early when the height is 0. | Pull request uclouvain/openjpeg#1674, commit `843b78e2712edab13bbda30662465d443a062716`, not merged yet; only its `dwt.c` hunk is applied |
| `j2k.c`, `opj_j2k_read_sod` | When a TLM segment announced fewer tile-parts for a tile than its SOT segments then used (TNsot = 0 leaves the count unknown), the tile-part index sized from TLM was written past its end. Skip the index update when the tile-part number is beyond it. Affects 2.5.3 and 2.5.4. | Pull request uclouvain/openjpeg#1621, merged on master as `d33cbecc148d3affcdf403211fddc2cc5d442379` (patch commit `91d08b11a72764f6d199f32fa0c1b1abd4edc2ad`), in no release yet |
