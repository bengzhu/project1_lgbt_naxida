#!/bin/sh
set -eu

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root=$(mktemp -d "${TMPDIR:-/tmp}/aitrans-v3239-bbox-primary.XXXXXX")
cleanup() {
  if command -v trash >/dev/null 2>&1 && [ -d "$runtime_root" ]; then
    trash "$runtime_root"
  fi
}
trap cleanup EXIT HUP INT TERM

bundle="$runtime_root/AITRANSBBoxPrimaryHarness.app"
resources="$bundle/Contents/Resources"
executable="$bundle/Contents/MacOS/AITRANSBBoxPrimaryHarness"

mkdir -p "$resources" "$(dirname "$executable")"
plutil -create xml1 "$bundle/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.local.aitrans.bbox-primary-harness "$bundle/Contents/Info.plist"
plutil -insert CFBundleExecutable -string AITRANSBBoxPrimaryHarness "$bundle/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$bundle/Contents/Info.plist"

cp "$repo_root/AITRANS/Resources/MangaOCR/MangaOCRVocab.txt" "$resources/"
xcrun coremlcompiler compile \
  "$repo_root/AITRANS/Resources/MangaOCR/MangaOCREncoderINT8.mlpackage" \
  "$resources"
xcrun coremlcompiler compile \
  "$repo_root/AITRANS/Resources/MangaOCR/MangaOCRDecoderINT8.mlpackage" \
  "$resources"
if [ -d "$repo_root/AITRANS/Resources/MangaOCR/MangaOCREncoderINT8Batch.mlpackage" ] \
  && [ -d "$repo_root/AITRANS/Resources/MangaOCR/MangaOCRDecoderINT8Batch.mlpackage" ]; then
  xcrun coremlcompiler compile \
    "$repo_root/AITRANS/Resources/MangaOCR/MangaOCREncoderINT8Batch.mlpackage" \
    "$resources"
  xcrun coremlcompiler compile \
    "$repo_root/AITRANS/Resources/MangaOCR/MangaOCRDecoderINT8Batch.mlpackage" \
    "$resources"
fi
xcrun coremlcompiler compile \
  "$repo_root/AITRANS/Resources/ComicTextDetector/ComicTextBubbleDetectorINT8.mlpackage" \
  "$resources"
xcrun swiftc -parse-as-library \
  "$repo_root/AITRANS/Models/ImageOCRProvenance.swift" \
  "$repo_root/AITRANS/Models/TranslationContextQuality.swift" \
  "$repo_root/AITRANS/Services/ImageOCRLayoutEngine.swift" \
  "$repo_root/AITRANS/Services/MangaOCRService.swift" \
  "$repo_root/AITRANS/Services/ComicTextBubbleDetectorService.swift" \
  "$repo_root/AITRANS/Services/VisionOCRService.swift" \
  "$repo_root/scripts/fixtures/v3239-manga-ocr-bbox-primary-runtime-harness.swift" \
  -o "$executable"

output="$runtime_root/output.txt"
"$executable" "$repo_root/test/jap.jpg" | tee "$output"
python3 - "$output" <<'PY'
from pathlib import Path
import re
import sys


text = Path(sys.argv[1]).read_text(encoding="utf-8")
for marker in [
    "batchInference=true",
    "targetConfidence=",
    "targetText=",
    "distractorConfidence=",
    "distractorText=",
    "adversarialConfidence=",
    "adversarialText=",
]:
    if marker not in text:
        raise SystemExit(f"missing bbox-primary runtime evidence {marker}: {text}")
match = re.search(r"^detectorRegions=(\d+)$", text, re.MULTILINE)
if match is None or int(match.group(1)) < 4:
    raise SystemExit(f"expected real RT-DETR Japanese regions: {text}")

def value(name: str) -> str:
    match = re.search(rf"^{name}=(.+)$", text, re.MULTILINE)
    if match is None:
        raise SystemExit(f"missing {name}: {text}")
    return match.group(1)

target = value("targetText")
distractor = value("distractorText")
adversarial = value("adversarialText")
if "爆乳" not in target or "生意気" not in distractor:
    raise SystemExit(f"fixture regions no longer identify distinct Japanese columns: {text}")
if target == distractor:
    raise SystemExit(f"target and distractor must be distinct: {text}")
if adversarial != target:
    raise SystemExit(f"misplaced reliable quad replaced detector bbox owner: {text}")
if adversarial == distractor:
    raise SystemExit(f"neighboring quad text leaked into detector owner: {text}")
for name in ["targetConfidence", "distractorConfidence", "adversarialConfidence"]:
    if float(value(name)) < 0.55:
        raise SystemExit(f"expected reliable {name}: {text}")
PY
