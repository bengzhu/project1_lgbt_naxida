# Cloud-only OCR oracle boundary (v3.282)

This directory describes the handoff boundary for same-crop comparison. It
does not contain GPL weights, Koharu runtime binaries, PaddleOCR-VL weights,
or a general Japanese corpus.

Cloud jobs may produce an input envelope for
`scripts/evaluate-japanese-ocr-multi-engine.py` from a shared crop manifest.
The envelope must carry the dataset SHA, stable `pageID`/`regionID`, crop
level, a `cropSha256` content identity, engine source/runtime/model revisions,
model SHA when available, license, and one result row per engine/crop key. MIT48 and PaddleOCR-VL remain
`referenceOnly` and cloud-only. Missing model artifacts are represented by
explicit engine failure metadata and explicit failure rows; they are never
silently dropped.

The committed multi-engine example is synthetic and only tests schema,
alignment, failure-row, and table-separation behavior. It does not prove
Vision, Manga OCR, MIT48, PaddleOCR-VL, detector recall, or translation
quality.
