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
tablets = [item for item in devices if item.get("productFamily") == "iPad"]
if not phones or not tablets:
    raise SystemExit("Both iPhone and iPad simulator device types are required")

def choose(items, preferred):
    for needle in preferred:
        for item in items:
            if needle in item.get("name", ""):
                return item
    return items[-1]

small = choose(phones, ["iPhone SE (3rd generation)", "iPhone 16e", "iPhone 15"])
large = choose(phones, ["Pro Max", "Plus"])
tablet = choose(tablets, ["13-inch", "12.9-inch", "iPad Pro"])
print(runtime["identifier"])
print(small["identifier"])
print(large["identifier"])
print(tablet["identifier"])
PY
)"

runtime="$(echo "$device_selection" | sed -n '1p')"
small_type="$(echo "$device_selection" | sed -n '2p')"
large_type="$(echo "$device_selection" | sed -n '3p')"
tablet_type="$(echo "$device_selection" | sed -n '4p')"

small_id="$(xcrun simctl create "AITRANS UI Small" "$small_type" "$runtime")"
large_id="$(xcrun simctl create "AITRANS UI Large" "$large_type" "$runtime")"
tablet_id="$(xcrun simctl create "AITRANS UI iPad" "$tablet_type" "$runtime")"

cleanup() {
  for device_id in "$small_id" "$large_id" "$tablet_id"; do
    xcrun simctl shutdown "$device_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$device_id" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

for device_id in "$small_id" "$large_id" "$tablet_id"; do
  xcrun simctl boot "$device_id"
done

for device_id in "$small_id" "$large_id" "$tablet_id"; do
  xcrun simctl bootstatus "$device_id" -b
  xcrun simctl install "$device_id" "$app_path"
  xcrun simctl ui "$device_id" appearance dark
done

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
    SIMCTL_CHILD_AITRANS_UI_EVIDENCE_ORIENTATION="$orientation" \
    xcrun simctl launch --terminate-running-process "$device_id" "$bundle_id"
  sleep 3
  xcrun simctl io "$device_id" screenshot "$output_dir/$filename"

  local image_width
  local image_height
  image_width="$(sips -g pixelWidth "$output_dir/$filename" | awk '/pixelWidth/ {print $2}')"
  image_height="$(sips -g pixelHeight "$output_dir/$filename" | awk '/pixelHeight/ {print $2}')"
  if [ "$orientation" = "portrait" ] && [ "$image_height" -le "$image_width" ]; then
    echo "Expected portrait screenshot but received ${image_width}x${image_height}: $filename" >&2
    exit 1
  fi
  if [ "$orientation" != "portrait" ] && [ "$image_width" -le "$image_height" ]; then
    echo "Expected landscape screenshot but received ${image_width}x${image_height}: $filename" >&2
    exit 1
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$filename" "$device_label" "$orientation" "$content_size" "$scenario" "$reduce_motion" "$appearance" "$commit_sha" >> "$metadata_tsv"
}

capture "$small_id" "compact-iPhone" empty large portrait text-empty-compact-day.png false 日间
capture "$small_id" "compact-iPhone" imageEmpty large portrait image-empty-compact-night.png false 夜间
capture "$small_id" "compact-iPhone" history large portrait history-data-compact-day.png false 日间
capture "$small_id" "compact-iPhone" proLocked large portrait settings-pro-locked-compact-night.png false 夜间

capture "$large_id" "large-iPhone" textSuccess extra-extra-large portrait text-success-large-xxl-day.png false 日间
capture "$large_id" "large-iPhone" textKeyboard large portrait text-keyboard-large-night.png false 夜间
capture "$large_id" "large-iPhone" textFailure accessibility-extra-large portrait text-failure-large-accessibility-night.png false 夜间
capture "$large_id" "large-iPhone" audioRecognizing large portrait audio-running-reduce-motion-night.png true 夜间

capture "$tablet_id" "iPad" proUnlocked large portrait settings-pro-unlocked-ipad-portrait-day.png false 日间
capture "$tablet_id" "iPad" imageSuccess large landscapeLeft image-success-ipad-landscape-night.png false 夜间
capture "$tablet_id" "iPad" localMissing large portrait model-missing-ipad-portrait-day.png false 日间
capture "$tablet_id" "iPad" localReady extra-extra-large landscapeLeft model-ready-ipad-landscape-xxl-night.png false 夜间

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
destination.write_text(json.dumps({"screenshots": items}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

rm "$metadata_tsv"
echo "Captured UI evidence for commit $commit_sha in $output_dir"
