#!/usr/bin/env bash
# A short, deterministic fuzzing campaign of the vendored OpenJPEG decoder
# under AddressSanitizer, for the JPEG 2000 Part 1 (t1, t2, tcd) and HTJ2K
# (ht_dec) code-block paths.
#
#   openjpeg_fuzz.sh [CASES] [KEY]
#
# CASES is the number of cases per seed (default 5000), KEY the mutation key
# (default 20261125): the same pair always gives the same cases.
#
# Seeds, written by openjpeg_fuzz_seeds.c with the vendored encoders:
#   - HTJ2K by OpenJPH: 8-bit and 16-bit reversible, 12-bit irreversible, and
#     RGB with the colour transform;
#   - Part 1 by OpenJPEG: 8-bit, 16-bit with every code-block style, 12-bit
#     irreversible, RGB with BYPASS and RESTART; three layers, four resolutions;
#   - one-code-block HTJ2K headers (heights 16, 9, 10, 11) for forged packets.
# OpenJPH writes only the HT cleanup pass, so the SigProp and MagRef passes of
# ht_dec.c are reached only by the forged packets (openjpeg_fuzz.c, "forge").
#
# Each seed runs twice, with the library's assertions enabled and with NDEBUG,
# as in release builds. A case is limited to 20 s and a batch to 300 s;
# openjpeg_fuzz.py restarts after each crash and keeps the input that caused
# it in a new temporary directory, which the script prints. At 5000 cases the
# campaign takes about two minutes. Exits 1 if any case failed an assertion,
# raised an AddressSanitizer report, ran out of time or crashed.
#
# What it shows: these inputs neither fail an assertion nor read or write out
# of bounds on this machine. What it does not show: the absence of defects.
# It is a blind, short campaign, not coverage-guided; it runs one tile per
# seed, no PPM or PPT, no decoding of a region or of a reduced resolution, and
# the forged HT packets have one code-block and one layer. Only the code paths
# of the build machine are compiled (no SSE2 on ARM).

set -euo pipefail

cases=${1:-5000}
key=${2:-20261125}
root=$(cd "$(dirname "$0")/../.." && pwd)
here="$root/Scripts/crosscheck"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/objects" "$work/seeds" "$work/run"

openjpeg=("$root"/Sources/COpenJPEG/*.c)
ojph="$root/Sources/COpenJPH/openjph/src/core"
ojph_sources=("$root/Sources/COpenJPH/copenjph.cpp" "$ojph"/others/*.cpp "$ojph"/codestream/*.cpp
    "$ojph"/coding/*.cpp "$ojph"/transform/*.cpp)

(cd "$work/objects" && clang++ -std=c++14 -O1 -DOJPH_DISABLE_SIMD -I "$root/Sources/COpenJPH/include" \
    -I "$ojph/openjph" -I "$ojph/codestream" -I "$ojph/coding" -I "$ojph/transform" -I "$ojph/others" \
    -c "${ojph_sources[@]}" && clang -O1 -I "$ojph/openjph" -c "$ojph/others/ojph_mem_c.c")
clang++ -O1 -DMUTEX_pthread -I "$root/Sources/COpenJPEG/include" -I "$root/Sources/COpenJPH/include" \
    -x c "$here/openjpeg_fuzz_seeds.c" -x c "${openjpeg[@]}" -x none "$work"/objects/*.o -o "$work/seeds-writer"
"$work/seeds-writer" "$work/seeds" > /dev/null
for variant in assert ndebug; do
    defines=-DMUTEX_pthread
    [ "$variant" = ndebug ] && defines="-DMUTEX_pthread -DNDEBUG"
    # shellcheck disable=SC2086
    clang -std=c99 -g -O1 -fsanitize=address -fno-omit-frame-pointer $defines \
        -I "$root/Sources/COpenJPEG/include" "${openjpeg[@]}" "$here/openjpeg_fuzz.c" -lm -o "$work/fuzz-$variant"
done

keep=$(mktemp -d)
failures=0
for variant in assert ndebug; do
    echo "== $variant"
    for seed in ht-rev-8 ht-rev-16 ht-irr-12 ht-rgb-8 j2k-rev-8 j2k-rev-16-modes j2k-irr-12 j2k-rgb-bypass; do
        python3 -I "$here/openjpeg_fuzz.py" "$work/fuzz-$variant" "$work/seeds/$seed.j2c" "$cases" "$key" \
            "$work/run" "$keep" || failures=$((failures + 1))
    done
    for seed in one-8 one-16 one-8-h10 one-12-h11; do
        python3 -I "$here/openjpeg_fuzz.py" "$work/fuzz-$variant" "$work/seeds/$seed.j2c" "$cases" "$key" \
            "$work/run" "$keep" forge || failures=$((failures + 1))
    done
done
if [ "$failures" -gt 0 ]; then
    echo "inputs kept in $keep"
    exit 1
fi
rmdir "$keep"
