#!/usr/bin/env bash

set -euo pipefail

exec swift package --disable-sandbox preview-documentation --target DcmSwift
