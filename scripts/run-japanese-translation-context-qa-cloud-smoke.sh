#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-false}" != "true" ]]; then
  echo "v3.288 translation context QA is cloud-only" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_PATH="${JAPANESE_TRANSLATION_CONTEXT_QA_INPUT:-${REPO_ROOT}/benchmarks/japanese_translation/examples/translation_context_qa/input.json}"
OUTPUT_PATH="${JAPANESE_TRANSLATION_CONTEXT_QA_OUTPUT:-${RUNNER_TEMP:-${REPO_ROOT}}/japanese-translation-context-qa-report.json}"

python3 "${REPO_ROOT}/scripts/evaluate-japanese-translation-context-qa.py" \
  --input "${INPUT_PATH}" \
  --output "${OUTPUT_PATH}"

echo "v3.288 translation context QA report: ${OUTPUT_PATH}"
