# 几何融合、owner 与阅读顺序

> 状态：current。主题是 observation 到最终 block 的几何、身份和顺序边界。

## 快速定位

| 任务/符号 | 文件路径 | 关键入口 |
| --- | --- | --- |
| normalized rect/quad | [`AITRANS/Services/ImageOCRLayoutEngine.swift`](../../../AITRANS/Services/ImageOCRLayoutEngine.swift) | `ImageOCRLayoutRect`、`ImageOCRLayoutQuad` |
| observation → block | 同上 | `ImageOCRLayoutEngine.layout(...)` |
| known owner 完整覆盖 | 同上 | `lineCoverageOwnersProveBlock(...)`、`blockFallbackCanReplacePartialLines(...)` |
| 候选身份与 engine/crop provenance | [`AITRANS/Models/ImageOCRProvenance.swift`](../../../AITRANS/Models/ImageOCRProvenance.swift) | `ImageOCRCandidateProvenance`、`ImageOCRBlockProvenance` |
| 复查摘要 | [`AITRANS/Models/ImageOCRResultSummary.swift`](../../../AITRANS/Models/ImageOCRResultSummary.swift) | `requiresReview`、`hasLowConfidence`、`hasUnknownDirection` |
| 产品 block | [`AITRANS/Models/TranscriptModels.swift`](../../../AITRANS/Models/TranscriptModels.swift) | `ImageTranslationBlock` |

## 融合规则

```text
observation
  -> normalize geometry / confidence
  -> candidate provenance + owner compatibility
  -> dedupe / coverage / boundary checks
  -> horizontal or vertical/manga reading-order cluster
  -> ImageOCRLayoutBlock
  -> Store projects to ImageTranslationBlock
```

在日语漫画阅读模式下，known `verticalTextRegionOwner` 先成为临时归组键；不同 owner 不能通过普通列距、duplicate、coverage 或中间 geometry 被桥接。ownerless observation 仍走兼容的 geometry clustering，但同时命中多个 known owner 时不能替任一 owner 证明完整覆盖。

## 权威边界与禁止路径

- normalized rect/quad 先做有限值、正面积和 unit-space clipping；无效 geometry 在进入排序、crop、focus 或 overlay 前拒绝。
- confidence 只在已通过合法域 gate 后参与排序/替换；不要把原始 `Float` 当作无界全序。
- owner 是 request/session-local 的识别上下文，不是用户可见 block ID；只有同 owner、同 source-line proof 才能完成 Koharu-style fallback replacement。
- `blockFallback` 只有显式 `.crop`、可靠日语质量、geometry、exact-owner、一对一 source-line complete coverage 都成立时，才可移除 partial `.verticalLine`；否则保留已有 partial lines。
- reading order 与 translation order 是不同概念：layout 产出稳定 block 顺序，翻译/Store 决定批量和持久化。

## 相关测试与验证路由

- owner/coverage：[`test-v3276-koharu-line-owner-boundary-contract.py`](../../../scripts/test-v3276-koharu-line-owner-boundary-contract.py)、[`test-v3277-koharu-owned-line-grouping-contract.py`](../../../scripts/test-v3277-koharu-owned-line-grouping-contract.py)、[`test-v3278-koharu-line-coverage-owner-contract.py`](../../../scripts/test-v3278-koharu-line-coverage-owner-contract.py)、[`test-v3279-koharu-block-fallback-replacement-contract.py`](../../../scripts/test-v3279-koharu-block-fallback-replacement-contract.py)。
- candidate/provenance：[`test-v3281-image-ocr-provenance-no-selection-change-contract.py`](../../../scripts/test-v3281-image-ocr-provenance-no-selection-change-contract.py)、[`test-v3309-image-ocr-scoped-provenance-contract.py`](../../../scripts/test-v3309-image-ocr-scoped-provenance-contract.py)。
- 质量域/排序：`scripts/test-v331*` 到 `scripts/test-v339*` 及 `scripts/test-v340*` 到 `scripts/test-v361*` 中的 Japanese OCR/layout contracts。
- 完整流程：[`md/flow/flow.md`](../../flow/flow.md) 的普通图片 OCR 段落；日常定位不需默认通读全文。

## 何时更新本索引

改变 cluster/merge predicate、owner 传递、coverage proof、reading-order cut、confidence 排序或最终 block 投影时更新；如果改变产品 snapshot/复查操作，还要更新应用状态索引。
