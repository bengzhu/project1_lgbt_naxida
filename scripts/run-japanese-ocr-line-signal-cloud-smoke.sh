#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-false}" != "true" ]]; then
  echo "v3.283 native line/TextRegion shadow evaluation is cloud-only" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH="${JAPANESE_OCR_LINE_SIGNAL_MANIFEST:-${REPO_ROOT}/benchmarks/japanese_ocr/examples/line_signal/manifest.json}"
SIGNAL_PATH="${JAPANESE_OCR_LINE_SIGNAL_INPUT:-${REPO_ROOT}/benchmarks/japanese_ocr/examples/line_signal/input.json}"
OUTPUT_PATH="${JAPANESE_OCR_LINE_SIGNAL_OUTPUT:-${RUNNER_TEMP:-${REPO_ROOT}}/japanese-ocr-line-signal-report.json}"

python3 "${REPO_ROOT}/scripts/evaluate-japanese-ocr-line-signal.py" \
  --manifest "${MANIFEST_PATH}" \
  --signal "${SIGNAL_PATH}" \
  --output "${OUTPUT_PATH}"

echo "v3.283 native line/TextRegion shadow report: ${OUTPUT_PATH}"
