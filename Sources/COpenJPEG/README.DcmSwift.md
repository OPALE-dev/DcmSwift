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

## Assertions

`Package.swift` defines `NDEBUG` for this target in release builds only, so
that a malformed codestream is refused with an error instead of failing an
`assert` and aborting the whole process. The assertions of the decoder are
redundant with header checks where they guard a buffer size (for example,
`opj_t1_allocate_buffers` relies on `opj_j2k_read_SPCod_SPCoc` refusing
code-block exponents above 10 or summing above 12), and
`Scripts/crosscheck/openjpeg_fuzz.sh` decodes mutated codestreams under
AddressSanitizer with and without `NDEBUG`. Debug builds keep the
assertions, so tests and the crosscheck scripts still report a violated
invariant.

## Local patches

Each patch below is applied on top of 2.5.4, as published upstream, and is
removed when a release contains it. `Scripts/crosscheck/openjpeg_asan.sh`
runs the cases that the `dwt.c` and `j2k.c` patches fix under
AddressSanitizer; the `pi.c` case needs many layers and tiny precincts, and
gigabytes of memory, so it is not run.

| File | Reason | Upstream reference |
| --- | --- | --- |
| `dwt.c`, `opj_dwt_encode_and_deinterleave_v` | Reversible encoding of a resolution level with no rows at an odd start coordinate (a short edge tile with many decomposition levels) read and wrote past the end of the scratch buffer (CVE-2026-107080). Return early when the height is 0. | Pull request uclouvain/openjpeg#1674, commit `843b78e2712edab13bbda30662465d443a062716`, not merged yet; only its `dwt.c` hunk is applied |
| `j2k.c`, `opj_j2k_read_sod` | When a TLM segment announced fewer tile-parts for a tile than its SOT segments then used (TNsot = 0 leaves the count unknown), the tile-part index sized from TLM was written past its end. Skip the index update when the tile-part number is beyond it. Affects 2.5.3 and 2.5.4. | Pull request uclouvain/openjpeg#1621, merged on master as `d33cbecc148d3affcdf403211fddc2cc5d442379` (patch commit `91d08b11a72764f6d199f32fa0c1b1abd4edc2ad`), in no release yet |
| `pi.c`, `opj_pi_initialise_encode` | Encoder only: the size of the packet inclusion table (layers × resolutions × components × precincts) was computed in 32 bits and could wrap, so a smaller table was allocated and then written past its end (CVE-2026-6192). Allocate it only when the product fits. Affects 2.5.0 to 2.5.4. `DICOMJPEG2000Codec` does not reach it: it writes one layer, at most 6 resolutions, at most 16384 components (Part 2 component collections), and the default 2^15 × 2^15 precincts, at most 4 per resolution for a 65535 × 65535 image, so the product stays below 400,000. | Pull request uclouvain/openjpeg#1628, commit `839936aa33eb8899bbbd80fda02796bb65068951` (merged as `70f16e0e331eee7da02cdfc448a1394da2665036`), in no release yet |
