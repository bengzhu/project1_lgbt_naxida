#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-false}" != "true" ]]; then
  echo "v3.293 shared corpus readiness is cloud-only" >&2
  exit 2
fi

manifest_path="${JAPANESE_CORPUS_READINESS_MANIFEST:-benchmarks/japanese_ocr/examples/corpus_readiness/manifest.json}"
output_path="${JAPANESE_CORPUS_READINESS_OUTPUT:-${RUNNER_TEMP:-/tmp}/japanese-corpus-readiness-report.json}"

python3 scripts/evaluate-japanese-corpus-readiness.py \
  --manifest "$manifest_path" \
  --output "$output_path"

echo "v3.293 shared corpus readiness report: ${output_path}"
