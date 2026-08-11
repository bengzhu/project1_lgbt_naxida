#!/bin/sh
set -eu

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root=$(mktemp -d "${TMPDIR:-/tmp}/aitrans-v3254-region-diagnostic.XXXXXX")
bundle="$runtime_root/AITRANSJapaneseRegionDiagnostic.app"
resources="$bundle/Contents/Resources"
executable="$bundle/Contents/MacOS/AITRANSJapaneseRegionDiagnostic"

cleanup() {
  if command -v trash >/dev/null 2>&1 && [ -d "$runtime_root" ]; then
    trash "$runtime_root"
  fi
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$resources" "$(dirname "$executable")"
plutil -create xml1 "$bundle/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.local.aitrans.japanese-region-diagnostic "$bundle/Contents/Info.plist"
plutil -insert CFBundleExecutable -string AITRANSJapaneseRegionDiagnostic "$bundle/Contents/Info.plist"
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
  "$repo_root/AITRANS/Services/ImageOCRLayoutEngine.swift" \
  "$repo_root/AITRANS/Services/MangaOCRService.swift" \
  "$repo_root/AITRANS/Services/ComicTextBubbleDetectorService.swift" \
  "$repo_root/AITRANS/Services/VisionOCRService.swift" \
  "$repo_root/scripts/fixtures/v3254-japanese-region-diagnostic-harness.swift" \
  -o "$executable"

output="$runtime_root/output.txt"
"$executable" "$repo_root/test/jap.jpg" | tee "$output"
python3 - "$output" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
if "batchInference=true" not in text:
    raise SystemExit(f"expected bundled Manga OCR runtime: {text}")
detector = re.search(r"^detectorRegions=(\d+)$", text, re.MULTILINE)
if detector is None or int(detector.group(1)) != 6:
    raise SystemExit(f"expected six detector regions on test/jap.jpg: {text}")
diagnostic = re.search(r"^diagnosticRegions=(\d+)$", text, re.MULTILINE)
if diagnostic is None or int(diagnostic.group(1)) != 6:
    raise SystemExit(f"expected six bounded diagnostic regions: {text}")
region_lines = re.findall(
    r"^region=(\d+) x=.* detectorConfidence=.* rotate270Applied=(true|false)$",
    text,
    re.MULTILINE,
)
if len(region_lines) != 6:
    raise SystemExit(f"expected six detector geometry rows: {text}")
for index in range(6):
    for orientation in ("natural", "rotate90", "rotate270"):
        marker = rf"^region={index} {orientation}Text=.* {orientation}Confidence=.* {orientation}JapaneseDensity=.*$"
        if re.search(marker, text, re.MULTILINE) is None:
            raise SystemExit(f"missing {orientation} matrix row for region {index}: {text}")

# Record whether the compact owner is present in RT-DETR at all. This is a
# diagnostic oracle only: the production Vision fusion still owns the final
# choice when the detector does not produce an owner.
compact = [
    line for line in text.splitlines()
    if "Text=こっ、" in line or "Text=ニコッ" in line
]
print(f"compactOwnerObserved={'true' if compact else 'false'}")
if "naturalText=今度こそこの爆乳を持ち帰る！" not in text:
    raise SystemExit(f"missing reliable detector Manga OCR baseline: {text}")

long = re.search(r"^longBlocks=(\d+)$", text, re.MULTILINE)
if long is None or int(long.group(1)) != 20:
    raise SystemExit(f"expected twenty bounded long-page blocks after compact recovery: {text}")
long_vertical = re.findall(
    r"^longBlock=\d+ x=.* direction=vertical text=(.+)$",
    text,
    re.MULTILINE,
)
if len(long_vertical) != 20:
    raise SystemExit(f"expected every long-page block to retain vertical provenance: {text}")
if re.search(r"^longBlock=\d+ x=.* direction=horizontal text=ニコッ$", text, re.MULTILINE):
    raise SystemExit(f"retained horizontal compact echo after vertical recovery: {text}")
long_rows = re.findall(
    r"^longBlock=\d+ x=([^ ]+) y=([^ ]+) w=([^ ]+) h=([^ ]+) "
    r"direction=vertical text=(.+)$",
    text,
    re.MULTILINE,
)
compact_rows = [
    row for row in long_rows
    if float(row[2]) <= 0.05 and float(row[3]) <= 0.03
]
if len(compact_rows) != 4:
    raise SystemExit(f"expected four bounded compact vertical blocks: {text}")
compact_texts = [row[4] for row in compact_rows]
if not all(2 <= len(value) <= 4 for value in compact_texts):
    raise SystemExit(f"expected short compact OCR reads: {compact_texts}")
if sum(value == "ニコッ" for value in compact_texts) == 4:
    print("compactTextSummary=ニコッ|ニコッ|ニコッ|ニコッ")
else:
    # Vision/Core ML text can vary by host when the same fixture is rendered
    # into a tall PNG. Keep this harness focused on compact ownership,
    # geometry, and vertical provenance; the single-page exact `ニコッ`
    # oracle remains covered by the v3.214 runtime contract.
    print(f"compactTextSummary=host-variant:{'|'.join(compact_texts)}")
if not re.search(
    r"^longBlock=\d+ x=.* y=0\.940558\d* .* direction=vertical text=．．．では最後",
    text,
    re.MULTILINE,
):
    raise SystemExit(f"long-page bottom boundary regressed: {text}")
PY
