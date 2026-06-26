#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="${BUNDLE_ID:-com.local.aitrans}"
DEVICE="${1:-booted}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="$PROJECT_ROOT/output"

CONTAINER="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)"
SOURCE="$CONTAINER/Library/Application Support/AITRANS/Output"

if [[ ! -d "$SOURCE" ]]; then
  echo "Output not found: $SOURCE" >&2
  exit 1
fi

rm -rf "$DESTINATION"
mkdir -p "$DESTINATION"
cp -R "$SOURCE"/. "$DESTINATION"/
echo "Exported probe output to $DESTINATION"
