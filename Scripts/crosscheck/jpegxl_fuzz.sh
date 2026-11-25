#!/usr/bin/env bash
# Checks that the release build of the vendored libjxl cannot abort, and runs
# a short, deterministic fuzzing campaign of its decoder in debug and release.
#
#   jpegxl_fuzz.sh [CASES] [KEY]
#
# CASES is the number of cases per seed (default 5000), KEY the mutation key
# (default 20261125). The script builds the CJPEGXL target with `swift build`
# in debug and in release, unless DEBUG_BIN and RELEASE_BIN name the bin
# directories of existing builds, and links jpegxl_fuzz.cc against the
# objects of each.
#
# Without NDEBUG, libjxl is a debug build: JXL_ENSURE, JXL_DASSERT,
# JXL_UNREACHABLE and JXL_DEBUG_ABORT call jxl::Abort(), which ends the
# process. Package.swift defines NDEBUG in release only, where JXL_ENSURE
# returns an error instead and the others compile to nothing. The first check
# counts the release objects that refer to jxl::Abort: it must be 0 (the debug
# objects refer to it, which the script prints for comparison).
#
# Seeds, written by jpegxl_fuzz.cc with the vendored encoder: lossless 8-bit
# and 16-bit, lossy 8-bit and 12-bit, grayscale. Mutations change 1 to 16
# bytes after the signature. A case is limited to 20 s and a batch to 300 s;
# openjpeg_fuzz.py restarts after each crash, keeps the input in a new
# temporary directory, which the script prints, and counts libjxl aborts
# ("jxl-abort") apart from other crashes. Exits 1 on any abort, crash or time
# limit, or if a release object refers to jxl::Abort.
#
# What it shows: the release objects hold no abort path of libjxl's checks,
# and these inputs do not abort either build. It does not show the absence of
# defects: the campaign is blind and short, with small grayscale images only.

set -euo pipefail

cases=${1:-5000}
key=${2:-20261125}
root=$(cd "$(dirname "$0")/../.." && pwd)
here="$root/Scripts/crosscheck"
cd "$root"
if [ -z "${DEBUG_BIN:-}" ]; then
    swift build --target CJPEGXL > /dev/null
    DEBUG_BIN=$(swift build --show-bin-path)
fi
if [ -z "${RELEASE_BIN:-}" ]; then
    swift build -c release --target CJPEGXL > /dev/null
    RELEASE_BIN=$(swift build -c release --show-bin-path)
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/seeds" "$work/run"

aborts() {
    local count=0 object
    while IFS= read -r object; do
        if nm -C "$object" 2>/dev/null | grep -q " jxl::Abort()"; then count=$((count + 1)); fi
    done < <(find "$1/CJPEGXL.build" -name "*.o")
    echo "$count"
}
debug_aborts=$(aborts "$DEBUG_BIN")
release_aborts=$(aborts "$RELEASE_BIN")
echo "objects referring to jxl::Abort: debug $debug_aborts, release $release_aborts"

failures=0
[ "$release_aborts" -eq 0 ] || failures=$((failures + 1))
for variant in debug release; do
    bin=$DEBUG_BIN
    [ "$variant" = release ] && bin=$RELEASE_BIN
    objects=()
    while IFS= read -r object; do objects+=("$object"); done < <(find "$bin/CJPEGXL.build" -name "*.o")
    clang++ -std=c++17 -g -O1 -I "$root/Sources/CJPEGXL/include" "$here/jpegxl_fuzz.cc" "${objects[@]}" \
        -o "$work/jpegxl_fuzz-$variant"
done
"$work/jpegxl_fuzz-release" seeds "$work/seeds"
keep=$(mktemp -d)
for variant in debug release; do
    echo "== $variant"
    for seed in jxl-lossless-8 jxl-lossless-16 jxl-lossy-8 jxl-lossy-12; do
        python3 -I "$here/openjpeg_fuzz.py" "$work/jpegxl_fuzz-$variant" "$work/seeds/$seed.jxl" "$cases" "$key" \
            "$work/run" "$keep" || failures=$((failures + 1))
    done
done
if [ "$failures" -gt 0 ]; then
    echo "inputs kept in $keep"
    exit 1
fi
rmdir "$keep"
