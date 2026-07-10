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
mkdir -p "$output_dir"
metadata_tsv="$output_dir/evidence.tsv"
: > "$metadata_tsv"

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
devices = [item for item in runtime.get("supportedDeviceTypes", []) if item.get("identifier")]
phones = [item for item in devices if item.get("productFamily") == "iPhone"]
if not phones:
    raise SystemExit("At least one iPhone simulator device type is required")

def choose(items, preferred):
    for needle in preferred:
        for item in items:
            if needle in item.get("name", ""):
                return item
    return items[-1]

small = choose(phones, ["iPhone SE (3rd generation)", "iPhone 16e", "iPhone 15"])
print(runtime["identifier"])
print(small["identifier"])
PY
)"

runtime="$(echo "$device_selection" | sed -n '1p')"
small_type="$(echo "$device_selection" | sed -n '2p')"

small_id="$(xcrun simctl create "AITRANS UI Small" "$small_type" "$runtime")"

cleanup() {
  if [ "${CI:-false}" = "true" ]; then
    echo "Skipping simulator cleanup on ephemeral CI runner"
    return
  fi
  xcrun simctl shutdown "$small_id" >/dev/null 2>&1 || true
  xcrun simctl delete "$small_id" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Booting compact iPhone simulator and waiting for full readiness"
xcrun simctl bootstatus "$small_id" -b

xcrun simctl install "$small_id" "$app_path"
xcrun simctl ui "$small_id" appearance dark
xcrun simctl spawn "$small_id" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true

capture() {
  local device_id="$1"
  local device_label="$2"
  local scenario="$3"
  local content_size="$4"
  local orientation="$5"
  local filename="$6"
  local reduce_motion="$7"
  local appearance="$8"

  echo "Capturing $filename ($device_label, $orientation, $content_size, $appearance)"
  xcrun simctl ui "$device_id" content_size "$content_size"
  xcrun simctl terminate "$device_id" "$bundle_id" >/dev/null 2>&1 || true
  SIMCTL_CHILD_AITRANS_UI_EVIDENCE_SCENARIO="$scenario" \
    SIMCTL_CHILD_AITRANS_UI_EVIDENCE_APPEARANCE="$appearance" \
    xcrun simctl launch --terminate-running-process "$device_id" "$bundle_id"
  sleep 3
  xcrun simctl io "$device_id" screenshot "$output_dir/$filename"

  local image_width
  local image_height
  local image_bytes
  image_width="$(sips -g pixelWidth "$output_dir/$filename" | awk '/pixelWidth/ {print $2}')"
  image_height="$(sips -g pixelHeight "$output_dir/$filename" | awk '/pixelHeight/ {print $2}')"
  image_bytes="$(stat -f '%z' "$output_dir/$filename")"
  if [ "$orientation" = "portrait" ] && [ "$image_height" -le "$image_width" ]; then
    echo "Expected portrait screenshot but received ${image_width}x${image_height}: $filename" >&2
    exit 1
  fi
  if [ "$image_bytes" -lt 50000 ]; then
    echo "Screenshot appears blank (${image_bytes} bytes): $filename" >&2
    exit 1
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$filename" "$device_label" "$orientation" "$content_size" "$scenario" "$reduce_motion" "$appearance" "$commit_sha" >> "$metadata_tsv"
}

capture "$small_id" "compact-iPhone" empty large portrait text-empty-compact-day.png false 日间
capture "$small_id" "compact-iPhone" imageEmpty large portrait image-empty-compact-night.png false 夜间
capture "$small_id" "compact-iPhone" history large portrait history-data-compact-day.png false 日间
capture "$small_id" "compact-iPhone" proLocked large portrait settings-pro-locked-compact-night.png false 夜间

capture "$small_id" "compact-iPhone" textSuccess extra-extra-large portrait text-success-compact-xxl-day.png false 日间
capture "$small_id" "compact-iPhone" textKeyboard large portrait text-keyboard-compact-night.png false 夜间
capture "$small_id" "compact-iPhone" textFailure accessibility-extra-large portrait text-failure-compact-accessibility-night.png false 夜间
capture "$small_id" "compact-iPhone" audioRecognizing large portrait audio-running-compact-reduce-motion-night.png true 夜间

python3 - "$metadata_tsv" "$output_dir/ui-evidence-manifest.json" <<'PY'
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
items = []
for line in source.read_text(encoding="utf-8").splitlines():
    filename, device, orientation, dynamic_type, scenario, reduce_motion, appearance, commit_sha = line.split("\t")
    items.append({
        "file": filename,
        "device": device,
        "orientation": orientation,
        "dynamicType": dynamic_type,
        "scenario": scenario,
        "reduceMotion": reduce_motion == "true",
        "appearance": appearance,
        "commitSha": commit_sha,
    })
if len(items) != 8:
    raise SystemExit(f"Expected 8 iPhone screenshots, received {len(items)}")
if any(item["device"] != "compact-iPhone" for item in items):
    raise SystemExit("UI evidence must use the compact iPhone device")
if any(item["orientation"] != "portrait" for item in items):
    raise SystemExit("iPhone-only UI evidence must remain portrait")
if {item["appearance"] for item in items} != {"日间", "夜间"}:
    raise SystemExit("Both day and night evidence are required")
if not any(item["dynamicType"].startswith("accessibility-") for item in items):
    raise SystemExit("Accessibility Dynamic Type evidence is required")
if not any(item["reduceMotion"] for item in items):
    raise SystemExit("Reduce Motion evidence is required")
destination.write_text(json.dumps({"screenshots": items}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

rm "$metadata_tsv"
echo "Captured UI evidence for commit $commit_sha in $output_dir"
