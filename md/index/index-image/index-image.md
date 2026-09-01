# 图片 OCR 与版面

> 状态：current。按“识别候选 → 几何融合 → 产品 block”划分；漫画覆盖探针本身属于独立诊断链路。

## 边界

本模块负责普通图片的 Apple Vision OCR、日语竖排方向/裁剪补读、Core ML 漫画文字区域检测、bundled Manga OCR、候选 provenance、几何去重和阅读顺序。图片翻译请求、review/persistence 和 UI 由相邻模块拥有。

## 快速定位

| 任务/符号 | 文件 | 关键入口 |
| --- | --- | --- |
| 普通图片 OCR | [`AITRANS/Services/VisionOCRService.swift`](../../../AITRANS/Services/VisionOCRService.swift) | `recognizeTextBlocks(in:)`、`recognizeTextBlocksWithShadowLedger(...)` |
| 单 block crop 复读 | 同上 | `recognizeTextBlock(...)` |
| 日语竖排/line/pixel recovery | 同上 | `recognizeJapaneseVerticalCrops(...)`、`recognizeJapaneseVerticalLineCrops(...)`、`recognizeJapaneseCropPass(...)` |
| OCR candidate/provenance | [`AITRANS/Models/ImageOCRProvenance.swift`](../../../AITRANS/Models/ImageOCRProvenance.swift) | `ImageOCRCandidate`、`ImageOCREngineSelector` |
| 日语清洗 | [`AITRANS/Models/JapaneseOCRTextNormalizer.swift`](../../../AITRANS/Models/JapaneseOCRTextNormalizer.swift) | `JapaneseOCRTextNormalizer` |
| 漫画文字区域检测 | [`AITRANS/Services/ComicTextBubbleDetectorService.swift`](../../../AITRANS/Services/ComicTextBubbleDetectorService.swift) | `detectTextRegions(in:)` |
| bundled Manga OCR | [`AITRANS/Services/MangaOCRService.swift`](../../../AITRANS/Services/MangaOCRService.swift) | `recognize(...)`、`recognizeBatch(...)` |
| block 几何/阅读顺序 | [`AITRANS/Services/ImageOCRLayoutEngine.swift`](../../../AITRANS/Services/ImageOCRLayoutEngine.swift) | `layout(...)` |
| 图片解码/预览 | [`AITRANS/Services/ImagePreviewService.swift`](../../../AITRANS/Services/ImagePreviewService.swift) | `makePreview(...)` |

## 主数据流

```text
image Data
  -> VisionOCRService.makeOCRImage
  -> Vision page OCR + Japanese 90/270 reconnaissance
  -> detector regions / MangaOCR bbox, quad, line candidates（仅日语相关路径）
  -> provenance、confidence、日语密度、geometry/owner gate
  -> ImageOCRLayoutEngine.layout
  -> [ImageTranslationBlock] -> TranslationSessionStore
```

独立 OCR 检测页仍消费同一最终 `[ImageTranslationBlock]`，但使用 `ImageOCRDetectionLanguage` 的 automatic/日语/中文/英语选择和独立的版式偏好；automatic 传给 Vision 自动语言集合，显式日语才启用 bundled Manga OCR，日语竖排才启用 90°/270° 方向复读。页面只做框选、质量复查和导出，不生成翻译。

Apple Vision 是普通文字识别的基础；Core ML detector 负责漫画文字区域几何，bundled Manga OCR 负责受控 crop/line recognition。外部 Koharu/MIT48 只在云端 reference parity/诊断中使用，不进入产品主路径。

## 高风险边界

- Vision page pass 是 baseline；日语补读是有上限的 recognition supplement，不能无条件覆盖可靠候选。
- detector bbox 是文字区域 ownership；quad/line/pixel crop 是弱结果或几何证据下的 fallback，不能跨 owner 合并。
- 候选必须通过有限 confidence、日语脚本密度、有效 normalized geometry 和去重门控；NaN/∞/空文本不得进入 layout 或 UI。
- 识别 provenance、owner、candidate ledger 是内部/诊断上下文；产品 block 只接收经过 layout 的最终文字、置信度、方向和 geometry。
- 修改图片识别请求预算、方向映射、crop/warp 或模型资源时，必须同时看布局、翻译和云端 App 证据路由。

## 相关索引

- [`OCR 候选与竖排恢复`](index-image-ocr.md)
- [`几何融合、owner 与阅读顺序`](index-image-layout.md)
- [`图片复查与 UI 操作`](../index-app/index-app-ui.md)
- [`资源与 Core ML bundle`](../index-assets/index-assets.md)
- [`合同与 runtime harness`](../index-validation/index-validation-contracts.md)

## 何时更新本索引

新增 OCR engine、detector/model、crop family、provenance 字段、候选 gate、请求预算、布局输入/输出或识别→翻译边界时更新；单纯 OCR 文案/复查 UI 改动转到相应三级索引。
