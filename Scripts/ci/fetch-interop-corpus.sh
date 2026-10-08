#!/usr/bin/env bash
# Downloads the confidential interoperability corpus for GitHub Actions and
# exports DCMSWIFT_INTEROP_CORPUS and DCMSWIFT_REQUIRE_INTEROP_CORPUS to the
# following steps. GitLab CI does the same in its .interop-corpus template.
#
# Needs DCM_CORPUS_URL (the generic package URL, without version) and
# DCM_CORPUS_TOKEN. The version and checksum come from .gitlab-ci.yml.

set -euo pipefail

gitlab_variable() {
  sed -n "s/^  $1: \"\(.*\)\"$/\1/p" .gitlab-ci.yml
}

version=$(gitlab_variable DCM_CORPUS_VERSION)
checksum=$(gitlab_variable DCM_CORPUS_SHA256)
test -n "$version" || { echo "DCM_CORPUS_VERSION not found in .gitlab-ci.yml" >&2; exit 1; }
test -n "$checksum" || { echo "DCM_CORPUS_SHA256 not found in .gitlab-ci.yml" >&2; exit 1; }

# Everything goes to the runner's temporary directory, which GitHub empties
# after each job, so nothing is written to or deleted from the checkout.
corpus_dir="$RUNNER_TEMP/dcmswift-corpus"
archive="$corpus_dir/dcmswift-dicom-corpus.tar.gz"
mkdir -p "$corpus_dir"

curl --fail --silent --show-error --location \
  --header "PRIVATE-TOKEN: $DCM_CORPUS_TOKEN" \
  --output "$archive" \
  "$DCM_CORPUS_URL/$version/dcmswift-dicom-corpus.tar.gz"

if command -v sha256sum >/dev/null; then
  echo "$checksum  $archive" | sha256sum -c -
else
  echo "$checksum  $archive" | shasum -a 256 -c -
fi

tar -xzf "$archive" -C "$corpus_dir"

echo "DCMSWIFT_INTEROP_CORPUS=$corpus_dir/dcmswift-dicom-corpus" >> "$GITHUB_ENV"
echo "DCMSWIFT_REQUIRE_INTEROP_CORPUS=1" >> "$GITHUB_ENV"
