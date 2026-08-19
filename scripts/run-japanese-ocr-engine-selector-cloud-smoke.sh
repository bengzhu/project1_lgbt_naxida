#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-false}" != "true" ]]; then
  echo "v3.285 OCR engine selector evaluation is cloud-only" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_PATH="${JAPANESE_OCR_ENGINE_SELECTOR_INPUT:-${REPO_ROOT}/benchmarks/japanese_ocr/examples/engine_selector/input.json}"
OUTPUT_PATH="${JAPANESE_OCR_ENGINE_SELECTOR_OUTPUT:-${RUNNER_TEMP:-${REPO_ROOT}}/japanese-ocr-engine-selector-report.json}"

python3 "${REPO_ROOT}/scripts/evaluate-japanese-ocr-engine-selector.py" \
  --input "${INPUT_PATH}" \
  --output "${OUTPUT_PATH}" \
  --allow-not-ready

echo "v3.285 OCR engine selector report: ${OUTPUT_PATH}"
