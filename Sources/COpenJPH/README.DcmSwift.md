# Vendored OpenJPH

- Upstream: https://github.com/aous72/OpenJPH
- Version: 0.32.0, commit 23c422895ce6c3a156935222e4715ee0b7be952c (2026-09-17)
- License: BSD 2-Clause (`LICENSE`)

`openjph/src/core` holds the upstream library sources, unchanged and in their
original layout. Only the generic code path is vendored: the SSE, AVX, AVX-512,
WebAssembly, and VSX variants need per-file compiler flags that SwiftPM does not
allow for dependencies, so they are left out and `OJPH_DISABLE_SIMD` is
defined. OpenJPH has no NEON variant, so Apple silicon loses nothing.

`include/copenjph.h` and `copenjph.cpp` are DcmSwift's C interface to the
encoder, so that Swift does not need C++ interoperability.

To update, copy `src/core` from a new release without the SIMD-suffixed files
(`*_sse*.cpp`, `*_avx*.cpp`, `*_wasm.cpp`, `*_vsx.cpp`, `ojph_simd_vsx.h`,
`ojph_block_encoder_avx2_apple.h`), then update this file.
