#!/usr/bin/env bash
set -euo pipefail

# This is an artifact aggregation boundary, not a model runner.  Real
# reference engines are allowed only in a cloud job that supplies their
# already-generated, pinned artifact envelope.  Keeping this guard here makes
# accidental local execution of a GPL/model workflow fail closed.
if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
  echo "Japanese OCR multi-engine oracle aggregation is cloud-only; set GITHUB_ACTIONS=true in GitHub Actions" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INPUT="${JAPANESE_OCR_MULTI_ENGINE_INPUT:?JAPANESE_OCR_MULTI_ENGINE_INPUT is required}"
OUTPUT="${JAPANESE_OCR_MULTI_ENGINE_OUTPUT:-${RUNNER_TEMP:?RUNNER_TEMP is required}/japanese-ocr-multi-engine-report.json}"

test -f "$INPUT"
python3 "$REPO_ROOT/scripts/evaluate-japanese-ocr-multi-engine.py" \
  --input "$INPUT" \
  --output "$OUTPUT" \
  --allow-missing-artifacts

echo "Japanese OCR multi-engine artifact report: $OUTPUT"
