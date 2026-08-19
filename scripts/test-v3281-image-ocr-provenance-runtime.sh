#!/bin/sh
set -eu

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root=$(mktemp -d "${TMPDIR:-/tmp}/aitrans-v3281-provenance.XXXXXX")
cleanup() {
  if command -v trash >/dev/null 2>&1 && [ -d "$runtime_root" ]; then
    trash "$runtime_root"
  fi
}
trap cleanup EXIT HUP INT TERM

executable="$runtime_root/ImageOCRProvenanceEvaluator"
xcrun swiftc -parse-as-library \
  "$repo_root/AITRANS/Models/ImageOCRProvenance.swift" \
  "$repo_root/AITRANS/Models/TranslationContextQuality.swift" \
  "$repo_root/AITRANS/Models/TranscriptModels.swift" \
  "$repo_root/AITRANS/Services/ImageOCRLayoutEngine.swift" \
  "$repo_root/scripts/fixtures/v3281-image-ocr-provenance-evaluator.swift" \
  -o "$executable"

output="$runtime_root/output.txt"
"$executable" | tee "$output"
grep -Fx 'v3.281 image OCR provenance evaluator passed' "$output" >/dev/null
