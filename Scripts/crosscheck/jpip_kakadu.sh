#!/usr/bin/env bash
# Compares the codestreams DcmSwift rebuilt from a JPIP server with the
# files it served, both decoded by Kakadu's kdu_expand.
#
#   jpip_kakadu.sh KAKADU_BIN FILES REBUILT
#
# FILES is the directory kdu_server served; REBUILT holds the
# <file>-<codestream>.j2c files written by
#   DCMSWIFT_JPIP_ORACLE=http://127.0.0.1:8080 DCMSWIFT_JPIP_FILES=FILES \
#   DCMSWIFT_JPIP_OUTPUT=REBUILT swift test --filter DcmSwiftJPIPTests
# Decoded images go to a new temporary directory. Exits 1 on a difference.

set -euo pipefail

kakadu=$1
files=$2
rebuilt=$3
work=$(mktemp -d)
differences=0
checked=0

for codestream in "$rebuilt"/*.j2c; do
    base=$(basename "$codestream" .j2c)
    name=${base%-*}
    index=${base##*-}
    source="$files/$name"
    components=$("$kakadu/kdu_jp2info" -i "$source" | grep -m1 -o "<components> [0-9]*" | grep -o "[0-9]*$")
    original=""
    copy=""
    for ((c = 0; c < components; c++)); do
        original+="$work/$base-original-$c.pgm,"
        copy+="$work/$base-rebuilt-$c.pgm,"
    done
    layer=()
    case "$name" in
        *.jpx) layer=(-jpx_layer "$index") ;;
    esac
    "$kakadu/kdu_expand" -quiet -i "$source" ${layer[@]+"${layer[@]}"} -o "${original%,}"
    "$kakadu/kdu_expand" -quiet -i "$codestream" -o "${copy%,}"
    for ((c = 0; c < components; c++)); do
        if ! cmp -s "$work/$base-original-$c.pgm" "$work/$base-rebuilt-$c.pgm"; then
            echo "$base: component $c differs"
            differences=$((differences + 1))
        fi
    done
    checked=$((checked + 1))
done

echo "$checked codestreams compared with kdu_expand, $differences differences (images in $work)"
[ "$differences" -eq 0 ]
