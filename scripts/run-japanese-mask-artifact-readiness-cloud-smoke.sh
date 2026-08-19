#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-false}" != "true" ]]; then
  echo "v3.291 mask artifact readiness is cloud-only" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest_path="${JAPANESE_RENDER_MASK_MANIFEST:-${repo_root}/benchmarks/japanese_render/examples/mask_artifacts/manifest.json}"
output_path="${JAPANESE_RENDER_MASK_OUTPUT:-${RUNNER_TEMP:-${repo_root}}/japanese-render-mask-artifact-report.json}"

python3 "${repo_root}/scripts/evaluate-japanese-mask-artifact-readiness.py" \
  --manifest "${manifest_path}" \
  --output "${output_path}"

echo "v3.291 mask artifact readiness report: ${output_path}"
