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
pads = [item for item in devices if item.get("productFamily") == "iPad"]
if not phones:
    raise SystemExit("At least one iPhone simulator device type is required")
if not pads:
    raise SystemExit("At least one iPad simulator device type is required for wide evidence")

def choose(items, preferred):
    for needle in preferred:
        for item in items:
            if needle in item.get("name", ""):
                return item
    return items[-1]

small = choose(phones, ["iPhone SE (3rd generation)", "iPhone 16e", "iPhone 15"])
wide = choose(pads, ["iPad (10th generation)", "iPad Air", "iPad Pro (11-inch)", "iPad"])
print(runtime["identifier"])
print(small["identifier"])
print(wide["identifier"])
PY
)"

runtime="$(echo "$device_selection" | sed -n '1p')"
small_type="$(echo "$device_selection" | sed -n '2p')"
wide_type="$(echo "$device_selection" | sed -n '3p')"

small_id="$(xcrun simctl create "AITRANS UI Small" "$small_type" "$runtime")"
wide_id=""

cleanup() {
  if [ "${CI:-false}" = "true" ]; then
    echo "Skipping simulator cleanup on ephemeral CI runner"
    return
  fi
  if [ -n "${small_id:-}" ]; then
    xcrun simctl shutdown "$small_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$small_id" >/dev/null 2>&1 || true
  fi
  if [ -n "${wide_id:-}" ]; then
    xcrun simctl shutdown "$wide_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$wide_id" >/dev/null 2>&1 || true
  fi
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
  if [ "$orientation" = "landscape" ] && [ "$image_width" -le "$image_height" ]; then
    echo "Expected landscape screenshot but received ${image_width}x${image_height}: $filename" >&2
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
capture "$small_id" "compact-iPhone" promptLibrary large portrait prompt-library-compact-day.png false 日间
capture "$small_id" "compact-iPhone" localMissing large portrait model-missing-compact-night.png false 夜间
capture "$small_id" "compact-iPhone" developerConsole large portrait developer-console-compact-day.png false 日间

echo "Shutting down compact iPhone before wide-iPad evidence to avoid dual-simulator migration contention"
xcrun simctl shutdown "$small_id" >/dev/null 2>&1 || true

echo "Creating and booting wide iPad simulator for home workspace evidence"
wide_id="$(xcrun simctl create "AITRANS UI Wide" "$wide_type" "$runtime")"
# Explicit boot then wait; dual create+bootstatus previously spent the whole 15m on Data Migration
xcrun simctl boot "$wide_id" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$wide_id" -b
xcrun simctl install "$wide_id" "$app_path"
xcrun simctl ui "$wide_id" appearance light
xcrun simctl spawn "$wide_id" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true
capture "$wide_id" "wide-iPad" empty large portrait text-empty-wide-ipad-day.png false 日间

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
if len(items) != 12:
    raise SystemExit(f"Expected 12 screenshots (11 compact iPhone + 1 wide iPad), received {len(items)}")
compact = [item for item in items if item["device"] == "compact-iPhone"]
wide = [item for item in items if item["device"] == "wide-iPad"]
if len(compact) != 11:
    raise SystemExit(f"Expected 11 compact-iPhone screenshots, received {len(compact)}")
if len(wide) != 1:
    raise SystemExit(f"Expected 1 wide-iPad screenshot, received {len(wide)}")
if any(item["orientation"] != "portrait" for item in compact):
    raise SystemExit("compact-iPhone UI evidence must remain portrait")
if wide[0]["scenario"] != "empty":
    raise SystemExit("wide-iPad evidence must capture the empty text workspace")
if wide[0]["orientation"] != "portrait":
    raise SystemExit("wide-iPad evidence orientation must be portrait for this matrix")
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
