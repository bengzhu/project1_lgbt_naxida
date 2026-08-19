#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-false}" != "true" ]]; then
  echo "v3.287 translation model comparison is cloud-only" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH="${JAPANESE_TRANSLATION_MODEL_COMPARISON_MANIFEST:-${REPO_ROOT}/benchmarks/japanese_translation/examples/model_comparison/manifest.json}"
INPUT_PATH="${JAPANESE_TRANSLATION_MODEL_COMPARISON_INPUT:-${REPO_ROOT}/benchmarks/japanese_translation/examples/model_comparison/input.json}"
OUTPUT_PATH="${JAPANESE_TRANSLATION_MODEL_COMPARISON_OUTPUT:-${RUNNER_TEMP:-${REPO_ROOT}}/japanese-translation-model-comparison-report.json}"

python3 "${REPO_ROOT}/scripts/evaluate-japanese-translation-model-comparison.py" \
  --manifest "${MANIFEST_PATH}" \
  --input "${INPUT_PATH}" \
  --output "${OUTPUT_PATH}"

echo "v3.287 translation model comparison report: ${OUTPUT_PATH}"
