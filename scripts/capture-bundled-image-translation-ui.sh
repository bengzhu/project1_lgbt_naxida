#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "usage: $0 APP_PATH BUNDLE_ID OUTPUT_DIR COMMIT_SHA" >&2
  exit 64
fi

app_path="$1"
bundle_id="$2"
output_dir="$3"
commit_sha="$4"
model_cache_dir="${MODEL_CACHE_DIR:?MODEL_CACHE_DIR is required}"
model_asset="${MODEL_ASSET:?MODEL_ASSET is required}"
model_sha256="${MODEL_SHA256:?MODEL_SHA256 is required}"
fixture_name="${IMAGE_TRANSLATION_FIXTURE:-2.png}"
timeout_seconds="${IMAGE_TRANSLATION_TIMEOUT_SECONDS:-900}"

mkdir -p "$output_dir"
test -f "$app_path/test/$fixture_name"
test -f "$model_cache_dir/$model_asset"

runtimes_json="$output_dir/sim-runtimes.json"
xcrun simctl list runtimes -j > "$runtimes_json"
device_selection="$(python3 - "$runtimes_json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
runtimes = [item for item in data.get("runtimes", []) if item.get("isAvailable") and item.get("platform") == "iOS"]
if not runtimes:
    raise SystemExit("No available iOS simulator runtime")
runtime = runtimes[-1]
phones = [
    item for item in runtime.get("supportedDeviceTypes", [])
    if item.get("productFamily") == "iPhone" and item.get("identifier")
]
if not phones:
    raise SystemExit(f"No iPhone device type for runtime {runtime.get('identifier')}")

def choose(items, preferred):
    for needle in preferred:
        for item in items:
            if needle in item.get("name", ""):
                return item
    return items[-1]

device = choose(phones, ["iPhone SE (3rd generation)", "iPhone 16e", "iPhone 15"])
print(runtime["identifier"])
print(device["identifier"])
PY
)"
runtime="$(echo "$device_selection" | sed -n '1p')"
device_type="$(echo "$device_selection" | sed -n '2p')"
device_id="$(xcrun simctl create "AITRANS test2 image translation" "$device_type" "$runtime")"
log_pid=""

cleanup() {
  if [ -n "${log_pid:-}" ]; then
    kill "$log_pid" >/dev/null 2>&1 || true
  fi
  xcrun simctl shutdown "$device_id" >/dev/null 2>&1 || true
  xcrun simctl delete "$device_id" >/dev/null 2>&1 || true
}
trap cleanup EXIT

xcrun simctl boot "$device_id"
xcrun simctl bootstatus "$device_id" -b
xcrun simctl install "$device_id" "$app_path"
xcrun simctl ui "$device_id" appearance light
xcrun simctl spawn "$device_id" launchctl setenv AITRANS_RUN_BUNDLED_IMAGE_TRANSLATION_TEST 1
xcrun simctl spawn "$device_id" launchctl setenv AITRANS_IMAGE_TRANSLATION_UI_FOCUS results
xcrun simctl spawn "$device_id" launchctl setenv AITRANS_RUN_LLM_SMOKE 1

container="$(xcrun simctl get_app_container "$device_id" "$bundle_id" data)"
model_dir="$container/Library/Application Support/Models/Gemma-1.5B"
mkdir -p "$model_dir"
cp -c "$model_cache_dir/$model_asset" "$model_dir/model.gguf" 2>/dev/null || cp "$model_cache_dir/$model_asset" "$model_dir/model.gguf"
echo "$model_sha256  $model_dir/model.gguf" | shasum -a 256 -c -

state_path="$container/Library/Application Support/AITRANS/state.json"
app_log="$output_dir/app-console.log"
xcrun simctl spawn "$device_id" log stream \
  --style compact \
  --predicate 'process == "AITRANS" OR eventMessage CONTAINS[c] "AITRANS" OR eventMessage CONTAINS[c] "llama"' \
  > "$app_log" 2>&1 &
log_pid="$!"

echo "Launching ordinary image OCR→translation for $fixture_name"
SIMCTL_CHILD_AITRANS_RUN_BUNDLED_IMAGE_TRANSLATION_TEST=1 \
SIMCTL_CHILD_AITRANS_IMAGE_TRANSLATION_UI_FOCUS=results \
SIMCTL_CHILD_AITRANS_RUN_LLM_SMOKE=1 \
  xcrun simctl launch --terminate-running-process "$device_id" "$bundle_id" \
  -AITRANS_RUN_BUNDLED_IMAGE_TRANSLATION_TEST 1 \
  -AITRANS_IMAGE_TRANSLATION_UI_FOCUS results \
  -AITRANS_RUN_LLM_SMOKE 1

deadline=$((SECONDS + timeout_seconds))
last_status=""
terminal_state=""
while [ "$SECONDS" -lt "$deadline" ]; do
  if [ -f "$state_path" ]; then
    summary="$(python3 - "$state_path" <<'PY'
import json
import sys

try:
    data = json.loads(open(sys.argv[1], encoding="utf-8").read())
except (OSError, json.JSONDecodeError):
    print("\t\t0")
    raise SystemExit(0)
session = data.get("imageTranslationSession") or {}
print(
    str(session.get("state") or ""),
    str(session.get("filename") or ""),
    str(len(session.get("blocks") or [])),
    sep="\t",
)
PY
)"
    IFS=$'\t' read -r state_value filename_value block_count <<< "$summary"
    current_status="$state_value/$filename_value/$block_count"
    if [ "$current_status" != "$last_status" ]; then
      echo "imageTranslationSession=$current_status"
      last_status="$current_status"
    fi
    if [ "$filename_value" = "$fixture_name" ] && { [ "$state_value" = "translated" ] || [ "$state_value" = "failed" ]; }; then
      terminal_state="$state_value"
      break
    fi
  fi
  sleep 5
done

test -n "$terminal_state" || {
  echo "Timed out waiting for terminal imageTranslationSession for $fixture_name" >&2
  if [ -f "$state_path" ]; then
    cp "$state_path" "$output_dir/test2-image-translation-state-timeout.json"
  fi
  exit 1
}

cp "$state_path" "$output_dir/test2-image-translation-state.json"
translation_probe_path="$container/Library/Application Support/AITRANS/llm-smoke-result.log"
if [ -f "$translation_probe_path" ]; then
  cp "$translation_probe_path" "$output_dir/test2-llm-probe.log"
fi
sleep 2
xcrun simctl io "$device_id" screenshot "$output_dir/test2-image-translation-results.png"

python3 - "$output_dir/test2-image-translation-state.json" "$output_dir/test2-image-translation-results.png" "$output_dir/test2-image-translation-manifest.json" "$commit_sha" "$fixture_name" "$terminal_state" <<'PY'
import json
import os
import sys
from pathlib import Path

state_path, screenshot_path, manifest_path, commit_sha, fixture_name, terminal_state = sys.argv[1:]
data = json.loads(Path(state_path).read_text(encoding="utf-8"))
session = data.get("imageTranslationSession") or {}
blocks = session.get("blocks") or []
if session.get("filename") != fixture_name:
    raise SystemExit(f"unexpected fixture in persisted session: {session.get('filename')!r}")
if session.get("sourceLanguage") != "日语" or session.get("targetLanguage") != "简体中文":
    raise SystemExit(
        "unexpected image translation languages: "
        f"{session.get('sourceLanguage')!r}->{session.get('targetLanguage')!r}"
    )
if terminal_state == "translated" and not blocks:
    raise SystemExit("translated image session has no OCR blocks")
if any(not (block.get("original") or "").strip() for block in blocks):
    raise SystemExit("image OCR block has empty original text")

manifest = {
    "commitSha": commit_sha,
    "fixture": fixture_name,
    "state": session.get("state"),
    "sourceLanguage": session.get("sourceLanguage"),
    "targetLanguage": session.get("targetLanguage"),
    "blockCount": len(blocks),
    "translatedBlockCount": sum(bool((block.get("translation") or "").strip()) for block in blocks),
    "screenshot": Path(screenshot_path).name,
    "screenshotBytes": os.path.getsize(screenshot_path),
    "blocks": [
        {
            "index": index + 1,
            "original": block.get("original", ""),
            "translation": block.get("translation", ""),
            "confidence": block.get("confidence"),
            "sourceDirection": block.get("sourceDirection"),
        }
        for index, block in enumerate(blocks)
    ],
}
Path(manifest_path).write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(manifest, ensure_ascii=False, indent=2))
if terminal_state != "translated":
    raise SystemExit(f"ordinary image translation ended in {terminal_state}")
if manifest["translatedBlockCount"] != manifest["blockCount"]:
    raise SystemExit(
        "ordinary image translation has incomplete translations: "
        f"{manifest['translatedBlockCount']}/{manifest['blockCount']}"
    )
if manifest["screenshotBytes"] < 50_000:
    raise SystemExit("captured image translation screenshot appears blank")
PY

echo "Captured actual image translation UI for $fixture_name at commit $commit_sha"
