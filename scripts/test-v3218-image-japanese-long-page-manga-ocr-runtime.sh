#!/bin/sh
set -eu

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root=$(mktemp -d "${TMPDIR:-/tmp}/aitrans-v3218-long-page.XXXXXX")
cleanup() {
  if command -v trash >/dev/null 2>&1 && [ -d "$runtime_root" ]; then
    trash "$runtime_root"
  fi
}
trap cleanup EXIT HUP INT TERM

bundle="$runtime_root/AITRANSLongPageMangaHarness.app"
resources="$bundle/Contents/Resources"
executable="$bundle/Contents/MacOS/AITRANSLongPageMangaHarness"

mkdir -p "$resources" "$(dirname "$executable")"
plutil -create xml1 "$bundle/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.local.aitrans.long-page-manga-harness "$bundle/Contents/Info.plist"
plutil -insert CFBundleExecutable -string AITRANSLongPageMangaHarness "$bundle/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$bundle/Contents/Info.plist"

cp "$repo_root/AITRANS/Resources/MangaOCR/MangaOCRVocab.txt" "$resources/"
xcrun coremlcompiler compile \
  "$repo_root/AITRANS/Resources/MangaOCR/MangaOCREncoderINT8.mlpackage" \
  "$resources"
xcrun coremlcompiler compile \
  "$repo_root/AITRANS/Resources/MangaOCR/MangaOCRDecoderINT8.mlpackage" \
  "$resources"
xcrun coremlcompiler compile \
  "$repo_root/AITRANS/Resources/ComicTextDetector/ComicTextBubbleDetectorINT8.mlpackage" \
  "$resources"
xcrun swiftc -parse-as-library \
  "$repo_root/AITRANS/Services/ImageOCRLayoutEngine.swift" \
  "$repo_root/AITRANS/Services/MangaOCRService.swift" \
  "$repo_root/AITRANS/Services/ComicTextBubbleDetectorService.swift" \
  "$repo_root/AITRANS/Services/VisionOCRService.swift" \
  "$repo_root/scripts/fixtures/v3218-long-page-manga-ocr-runtime-harness.swift" \
  -o "$executable"

output="$runtime_root/output.txt"
"$executable" "$repo_root/test/jap.jpg" | tee "$output"
python3 - "$output" <<'PY'
from pathlib import Path
import re
import sys


text = Path(sys.argv[1]).read_text(encoding="utf-8")
if "copies=4" not in text or "image=1136x6400" not in text:
    raise SystemExit(f"unexpected tall fixture geometry: {text}")
match = re.search(r"^blocks=(\d+)$", text, re.MULTILINE)
if match is None or int(match.group(1)) < 14:
    raise SystemExit(f"expected stable long-page OCR coverage: {text}")
if "direction=unknown" in text:
    raise SystemExit(f"retained unknown-direction long-page OCR blocks: {text}")

vertical_rects = [
    tuple(float(value) for value in values)
    for values in re.findall(
        r"^block=([0-9.]+),([0-9.]+),([0-9.]+),([0-9.]+) direction=vertical text=.+$",
        text,
        re.MULTILINE,
    )
]
if len(vertical_rects) < 12:
    raise SystemExit(f"expected at least 12 vertical long-page OCR blocks: {text}")
for quarter in range(4):
    lower = quarter * 0.25
    upper = lower + 0.25
    if sum(lower <= y < upper for _, y, _, _ in vertical_rects) < 3:
        raise SystemExit(f"insufficient vertical OCR coverage in quarter {quarter}: {text}")
if not any(y > 0.75 for _, y, _, _ in vertical_rects):
    raise SystemExit(f"missing final OCR output near the long-page tail: {text}")

vertical_texts = re.findall(r"direction=vertical text=(.+)$", text, re.MULTILINE)
if sum("今度こそ" in value for value in vertical_texts) < 4:
    raise SystemExit(f"not every repeated page received vertical Manga OCR: {text}")
if sum("前は生意気に俺の誘い断りやがって..." in value for value in vertical_texts) < 3:
    raise SystemExit(f"long-page Manga OCR did not replace weak fallback text: {text}")
PY
