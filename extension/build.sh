#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DIST_DIR="$SCRIPT_DIR/dist"
VERSION=$(sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)",?$/\1/p' "$SCRIPT_DIR/manifest.json")
ARTIFACT="$DIST_DIR/omafox-$VERSION.xpi"

if ! command -v zip >/dev/null 2>&1; then
  echo "Omafox: zip is required to build the XPI" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$ARTIFACT"

(
  cd "$SCRIPT_DIR"
  zip -q -r "$ARTIFACT" \
    manifest.json background.js theme.js icons popup THIRD_PARTY_NOTICES.md \
    -x '*.DS_Store'
)

echo "Built $ARTIFACT"
echo "Note: normal Firefox and Zen Browser installations require Mozilla to sign the XPI."
