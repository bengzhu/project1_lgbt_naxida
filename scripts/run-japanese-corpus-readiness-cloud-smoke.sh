#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-false}" != "true" ]]; then
  echo "v3.294 shared corpus readiness is cloud-only" >&2
  exit 2
fi

manifest_path="${JAPANESE_CORPUS_READINESS_MANIFEST:-benchmarks/japanese_ocr/examples/corpus_readiness/manifest.json}"
output_path="${JAPANESE_CORPUS_READINESS_OUTPUT:-${RUNNER_TEMP:-/tmp}/japanese-corpus-readiness-report.json}"

evaluator_args=(
  --manifest "$manifest_path"
  --output "$output_path"
)
if [[ -n "${JAPANESE_CORPUS_READINESS_ARTIFACT_ROOT:-}" ]]; then
  evaluator_args+=(--artifact-root "$JAPANESE_CORPUS_READINESS_ARTIFACT_ROOT")
fi

python3 scripts/evaluate-japanese-corpus-readiness.py "${evaluator_args[@]}"

echo "v3.294 shared corpus readiness report: ${output_path}"
