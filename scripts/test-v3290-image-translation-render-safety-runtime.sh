#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

xcrun swiftc -parse-as-library \
  "$ROOT_DIR/AITRANS/Models/ImageOCRProvenance.swift" \
  "$ROOT_DIR/AITRANS/Services/ImageOCRLayoutEngine.swift" \
  "$ROOT_DIR/AITRANS/Models/TranslationContextQuality.swift" \
  "$ROOT_DIR/AITRANS/Models/TranscriptModels.swift" \
  "$ROOT_DIR/AITRANS/Models/ImageTranslationRenderSafety.swift" \
  "$ROOT_DIR/scripts/fixtures/v3290-image-translation-render-safety-evaluator.swift" \
  -o "$TEMP_DIR/v3290-render-safety-evaluator"

"$TEMP_DIR/v3290-render-safety-evaluator"
