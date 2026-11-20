#!/usr/bin/env bash

# Builds the static DocC site.
# Usage: build.sh [output] [hosting-base-path]

set -euo pipefail

output="${1:-.build/documentation}"
base_path="${2:-}"

case "$output" in
  ""|"/"|"."|"..")
    echo "Refusing unsafe documentation output path: '$output'" >&2
    exit 2
    ;;
esac

if [[ -e "$output" ]]; then
  echo "Documentation output already exists: $output" >&2
  echo "Choose a new path or remove that generated directory first." >&2
  exit 2
fi

mkdir -p "$(dirname "$output")"

arguments=(
  swift package
  --allow-writing-to-directory "$output"
  generate-documentation
  --target DcmSwift
  --output-path "$output"
  --transform-for-static-hosting
  --warnings-as-errors
)
if [[ -n "$base_path" ]]; then
  arguments+=(--hosting-base-path "$base_path")
fi
"${arguments[@]}"
touch "$output/.nojekyll"
# DocC has no page at the site root: send visitors of the root address to the documentation.
cat > "$output/index.html" <<'HTML'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Documentation</title>
<meta http-equiv="refresh" content="0; url=documentation/dcmswift/"><link rel="canonical" href="documentation/dcmswift/"></head>
<body><p><a href="documentation/dcmswift/">Documentation</a></p></body></html>
HTML

echo "Generated DocC documentation at $output"
