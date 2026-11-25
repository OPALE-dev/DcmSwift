#!/usr/bin/env bash
# Builds the vendored OpenJPEG with AddressSanitizer and runs every case of
# openjpeg_asan.c in its own process. SwiftPM test bundles cannot load the
# sanitizer runtime on macOS (the test runner is a platform binary), so the
# library sources are compiled here directly with clang.
#
#   openjpeg_asan.sh
#
# Prints one line per case and exits 1 if AddressSanitizer reported an error.

set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

sources=()
for file in "$root"/Sources/COpenJPEG/*.c; do
    sources+=("$file")
done
clang -std=c99 -g -O1 -fsanitize=address -fno-omit-frame-pointer -DMUTEX_pthread \
    -I "$root/Sources/COpenJPEG/include" -I "$root/Sources/COpenJPEG" \
    "${sources[@]}" "$root/Scripts/crosscheck/openjpeg_asan.c" -lm -lpthread -o "$work/openjpeg_asan"

failures=0
for name in $("$work/openjpeg_asan" list); do
    if output=$(ASAN_OPTIONS=detect_leaks=0 "$work/openjpeg_asan" "$name" "$work" 2>&1); then
        echo "ok    $name ${output##*: }"
    elif grep -q "AddressSanitizer" <<<"$output"; then
        echo "ASAN  $name: $(grep -m1 -o 'AddressSanitizer: [a-z-]*' <<<"$output") $(grep -m1 -o 'in opj_[a-z0-9_]*' <<<"$output")"
        failures=$((failures + 1))
    else
        echo "FAIL  $name: $output"
        failures=$((failures + 1))
    fi
done
exit $((failures > 0))
