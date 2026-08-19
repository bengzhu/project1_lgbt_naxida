# Multi-engine OCR contract example

`input.json` is a synthetic, `contractExampleOnly`-style envelope for the
v3.282 joiner. It is not an OCR result and must not be used as a quality
claim. The four engine IDs mirror the intended comparison boundary:
Vision, bundled Manga OCR, Koharu MIT48, and Koharu PaddleOCR-VL.

The only permitted join key is:

```text
datasetSha256 + pageID + regionID + cropLevel
```

Each crop key also carries a `cropSha256`; it is a content identity check,
not an additional join dimension. A result row cannot silently substitute a
different image while retaining the same region ID.

Every engine must emit one row for every key. If an artifact is unavailable,
the engine metadata becomes `missing` or `failed` and every crop receives an
explicit failure row. `oracleCrop` and `detectedCrop` are always reported in
separate tables. The detected table intentionally carries no ground-truth
text; detector/crop quality belongs to the separate full benchmark.
