# Japanese render mask artifact readiness

This envelope is the v3.291+ preflight for distributable `BubbleMask` and
`SegmentMask` artifacts. It is intentionally contract-only and fail-closed.

The manifest must identify the exact model/runtime revisions, artifact SHA-256,
size, quantization, license review and distribution boundary for both mask
roles. It must also identify an authorized render-quality corpus and complete
measurements on a real target device. Missing artifacts, missing authorization,
unreviewed licenses or synthetic/non-target measurements keep the report
`blocked`.

`referenceOnly`, `productPathEnabled` and `productSelectionChanged` are kept
explicit so a cloud/reference or `MangaOverlayProbeService` proxy cannot be
mistaken for an App mask model. This preflight does not load a model, change
the rectangle renderer, add a mask to `ImageTranslationBlock`, run inpainting,
or claim OCR/translation improvement. Those changes require a later, separately
benchmarked implementation after the readiness gate is satisfied.

The checked-in example is deliberately unavailable and contract-only. It is a
fixture for the negative gate, not a model or a quality result.
