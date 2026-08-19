# Japanese OCR benchmark (v3.286)

This directory defines the first reproducible comparison boundary between
AITRANS and Koharu. It is an offline benchmark contract; it does not change
the app OCR candidate selector, model bundle, request budgets, translation
prompt, UI, or renderer.

The committed `fixtures/manifest.json` contains only the historical
`test/jap.jpg` regression page. Its seven MIT48 crops are explicitly marked
`legacyRegression` and `referenceOnly`; they are not human full-page ground
truth and are excluded from accuracy metrics. The small fixture under
`examples/minimal/` exists only to exercise the scorer and is marked
`contractExampleOnly`.

## Manifest integrity

`manifestSha256` is the SHA-256 of the canonical JSON document after setting
the top-level `manifestSha256` value to `null`. Canonical JSON uses UTF-8,
`ensure_ascii=false`, sorted keys, and compact separators. This avoids a
recursive self-hash while still making every manifest change visible.

Image paths are relative to the manifest and must resolve inside the
repository. Their declared SHA-256, pixel dimensions, source, license, and
permitted uses are part of the fixture identity. Coordinates use normalized
top-left origin (`x`, `y`, `width`, `height` in `[0, 1]`). The scorer performs
the geometry checks that JSON Schema cannot express, including finite values,
non-degenerate polygons, and self-intersection rejection.

## Evaluation levels

Predictions must declare exactly one of:

- `oracleCrop`: evaluate recognition on a known crop;
- `detectedCrop`: evaluate detector/crop plus recognition;
- `fullPage`: evaluate detector, grouping, reading order, and recognition.

The levels are never mixed in one report. A failed or empty prediction is a
real row with an explicit status; it cannot be omitted to make a score look
better. `oracleCrop` rows identify the annotated `regionID`; `detectedCrop`
and `fullPage` rows must leave `regionID` null so the scorer can perform
deterministic IoU matching without leaking ground-truth ownership. If a
detector emits no result for an annotated page, it must still emit one
page-level `empty`/`failure` row. A prediction run records the app SHA,
dataset SHA, engine/model identity, license, device, and parameters. A
cloud-only oracle must set `referenceOnly: true`.

## Scoring

Run the pure-Python scorer from the repository root:

```text
python3 scripts/evaluate-japanese-ocr-benchmark.py \
  --manifest benchmarks/japanese_ocr/examples/minimal/manifest.json \
  --predictions benchmarks/japanese_ocr/examples/minimal/predictions.json \
  --output /tmp/japanese-ocr-report.json
```

The report includes original and NFC exact match, CER with
substitution/insertion/deletion decomposition, deterministic IoU-0.5
one-to-one detector matching, duplicate/omission and block-composition
signals, direction accuracy, page-order exactness, Kendall tau, and
vertical/horizontal/SFX/small-text/long-page strata when those tags exist.
The report is deterministic: it has no wall-clock timestamp or random ID.

No committed fixture currently supports a general OCR quality claim. A real
corpus must be added under this top-level directory only after its source
license, page/region SHA, annotation status, and train/dev/holdout split are
known. It must not be added under `test/`, because the Xcode project bundles
that directory as app resources.

## Native line/TextRegion shadow signal (v3.283)

The `line_signal/` protocol evaluates an independent native TextRegion/line
geometry signal against the same manifest boundary. Its contract-only example
is structural only and must report `insufficientCorpus`; it does not enter the
AITRANS target or product OCR selection. See `line_signal/README.md` and
`examples/line_signal/README.md` for the cloud-only handoff and fail-closed
candidate rules.

## Distributable OCR candidate shadow matrix (v3.284)

The `engine_candidate/` protocol reuses the v3.282 same-crop keys and adds
artifact/model SHA, size, quantization, license, distribution policy,
cold/warm latency, peak memory, energy, target-device, and default-selection
metadata. Missing candidate artifacts or incomplete measurements produce a
blocked report with explicit reasons. The committed example is synthetic and
does not enable an OCR engine or make a quality claim.

## GT-isolated OCR selector and rollback shadow policy (v3.285)

The `engine_selector/` protocol freezes a runtime-only candidate gate. It may
use artifact/license availability, crop-role capability, valid geometry,
duplicate risk, calibrated engine-local quality, latency, memory, cancellation,
generation and remaining budgets. It cannot receive ground truth, benchmark
fixture identity, expected region counts or raw cross-engine confidence.

Every block records the selected engine, rejection reasons and rollback state;
request and pixel budget deltas are fixed at zero, and review state is retained
on fallback. The feature flag is off in the committed contract fixture because
the v3.284 candidate artifact and authorized holdout evidence are still absent.
Only a train/dev-frozen policy followed by one untouched holdout evaluation and
complete output, duplicate/omission/order, cancellation, memory and rollback
evidence can move the report from `blocked` to `readyForReview`.
