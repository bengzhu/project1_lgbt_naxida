# OCR 候选与日语竖排恢复

> 状态：current。主题是识别候选如何产生和筛选，不包含 Store 的翻译生命周期。

## 快速定位

| 任务/符号 | 文件路径 | 说明 |
| --- | --- | --- |
| Vision 请求与候选读取 | [`AITRANS/Services/VisionOCRService.swift`](../../../AITRANS/Services/VisionOCRService.swift) | `VNRecognizeTextRequest`、top candidates、language profile |
| 日语方向侦察/坐标回映 | 同上 | `rotatedImage`、`mapRotatedObservation`、`preferredJapaneseRotation` |
| block/line/crop recovery | 同上 | `recognizeJapaneseVerticalCrops`、`recognizeJapaneseVerticalLineCrops`、`recognizeJapaneseCropPass` |
| detector-owned Manga OCR | 同上、[`MangaOCRService.swift`](../../../AITRANS/Services/MangaOCRService.swift) | `recognizeJapaneseMangaOCR`、`japaneseMangaOCRRegions` |
| detector 输入与 slice | [`ComicTextBubbleDetectorService.swift`](../../../AITRANS/Services/ComicTextBubbleDetectorService.swift) | 640×640、tall-image slices、merge |
| OCR 清洗与 quality gate | [`VisionOCRService.swift`](../../../AITRANS/Services/VisionOCRService.swift)、[`JapaneseOCRTextNormalizer.swift`](../../../AITRANS/Models/JapaneseOCRTextNormalizer.swift) | `postProcessJapaneseOCRText`、`validOCRConfidence`、`japaneseScriptDensity` |

## 处理策略

1. `ImagePreviewService`/`VisionOCRService` 从 Data 解码为 bounded OCR image；长图保持足够宽度，同时受像素预算约束。
2. 先执行 Apple Vision `.accurate` page OCR；日语再做受控 90°/270° reconnaissance，并把旋转后的 rect/quad 映回原图。
3. 需要漫画区域时，detector 输出 text-region bbox；bundled Manga OCR 使用 bbox，弱 bbox 时才消费严格 quad/line crop。
4. 对已有竖排 layout block，按风险/几何选择 line、block、tile 或 pixel-first recovery；候选进入相同的清洗、confidence、日语密度和 owner gate。
5. 最终由 [`ImageOCRLayoutEngine`](../../../AITRANS/Services/ImageOCRLayoutEngine.swift) 负责融合，不在 OCR service 内直接决定产品 block 顺序之外的 Store 状态。

## 竖排日语精度边界

- **方向**：明确的 90°/270°读取、映射 geometry 和 source direction hint；未知方向保留 review 信号，不伪造方向。
- **像素**：detector bbox、tight line crop、quad warp、rotate270；Manga OCR 的 canonical preprocessing 与 bounded target canvas 有独立合同。
- **候选**：Vision 读取多个 `VNRecognizedText` 候选，优先日语脚本证据；有限 confidence window 内再比较内容/geometry，而不是盲取第一候选。
- **保护**：detector owner、line owner、覆盖关系和 one-to-one source-line proof 阻止相邻文字块互相污染。
- **恢复**：weak/short/uncertain block 使用有上限的风险优先补读；补读只在有可测证据时替换 incumbent，不能制造空 block。
- **清洗**：Unicode/全角、标点、噪声和日语文本后处理集中在既有 helper；翻译前后不重复改写 OCR 原文。

## 相关测试与验证路由

- 基础方向/裁剪/后处理：`scripts/test-v3156-*` 到 `scripts/test-v3179-*`。
- line/quad/owner/bbox：`scripts/test-v3180-*` 到 `scripts/test-v3268-*`、`scripts/test-v3276-*` 到 `scripts/test-v3281-*`。
- 当前 confidence/风险恢复：`scripts/test-v3295-image-japanese-weak-block-recovery-contract.py`、`scripts/test-v331*`、`scripts/test-v332*`、`scripts/test-v335*` 到 `scripts/test-v353*`。
- 固定图片输入：[`test/jap.jpg`](../../../test/jap.jpg)、[`test/1.png`](../../../test/1.png)、[`test/2.png`](../../../test/2.png)；它们是验证样本，不是通用质量证明。
- Core ML/Xcode/runtime 默认不在本机运行；按 [`index-validation-ci.md`](../index-validation/index-validation-ci.md) 选择云端 profile。

## 何时更新本索引

新增 OCR pass、候选角色、方向/裁剪 variant、模型输入预处理、质量 gate 或请求上限时更新；只改融合/阅读顺序时更新 [`几何融合、owner 与阅读顺序`](index-image-layout.md)。
