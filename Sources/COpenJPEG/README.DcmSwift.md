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
