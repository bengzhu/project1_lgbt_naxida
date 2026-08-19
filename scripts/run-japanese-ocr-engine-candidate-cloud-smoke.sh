#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-false}" != "true" ]]; then
  echo "v3.284 OCR engine candidate evaluation is cloud-only" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_PATH="${JAPANESE_OCR_ENGINE_CANDIDATE_INPUT:-${REPO_ROOT}/benchmarks/japanese_ocr/examples/engine_candidate/input.json}"
OUTPUT_PATH="${JAPANESE_OCR_ENGINE_CANDIDATE_OUTPUT:-${RUNNER_TEMP:-${REPO_ROOT}}/japanese-ocr-engine-candidate-report.json}"

python3 "${REPO_ROOT}/scripts/evaluate-japanese-ocr-engine-candidate.py" \
  --input "${INPUT_PATH}" \
  --output "${OUTPUT_PATH}" \
  --allow-missing-artifacts

echo "v3.284 OCR engine candidate report: ${OUTPUT_PATH}"
