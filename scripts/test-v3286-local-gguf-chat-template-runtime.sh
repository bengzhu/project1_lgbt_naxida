#!/bin/sh
set -eu

if [ "${GITHUB_ACTIONS:-false}" != "true" ]; then
  echo "v3.286 local GGUF chat-template evaluator is cloud-only" >&2
  exit 2
fi

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root=$(mktemp -d "${TMPDIR:-/tmp}/aitrans-v3286-chat-template.XXXXXX")
cleanup() {
  if command -v trash >/dev/null 2>&1 && [ -d "$runtime_root" ]; then
    trash "$runtime_root"
  fi
}
trap cleanup EXIT HUP INT TERM

executable="$runtime_root/LocalGGUFChatTemplateEvaluator"
xcrun swiftc -parse-as-library \
  "$repo_root/AITRANS/Models/LocalModelPromptProfile.swift" \
  "$repo_root/scripts/fixtures/v3286-local-gguf-chat-template-evaluator.swift" \
  -o "$executable"

output="$runtime_root/output.txt"
"$executable" | tee "$output"
grep -Fx 'v3.286 local GGUF chat-template evaluator passed' "$output" >/dev/null
