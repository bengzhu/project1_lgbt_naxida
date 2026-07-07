# Koharu External Artifact Contract

本目录定义 AITRANS 漫画探针可接受的外部 Koharu artifact 契约。它只解决格式、坐标和离线校验问题，不代表真实 detector 已接入。

## 目录约定

- Active 输入目录：`test/koharu_artifacts/`
- 非活动示例目录：`md/koharu研究/artifact_contract/examples/`

`test/koharu_artifacts/` 只能放真实 detector / segmenter 输出。不要把本目录的 examples、Vision OCR blocks、pre-crop plan、line plan、BubbleMask proxy 或人工真值派生内容复制进去冒充真实输出。

`examples/` 只用于 schema / parser smoke。示例 manifest 必须写 `contractExampleOnly=true`，即使误放到 active 目录，Swift readiness 和 validator 也必须阻塞，不允许进入 `readyForShadowOCR`。

## 文件布局

推荐 active 目录使用：

```text
test/koharu_artifacts/
  1.manifest.json
  1.textboxes.json
  1.bubbles.json
  1.segment_mask.json
```

manifest 可指定等价相对路径：

```json
{
  "schemaVersion": "aitrans.koharu_artifact_contract.v1",
  "sourceImage": "test/1.png",
  "coordinateSpace": "originalImageTopLeftPixels",
  "contractExampleOnly": false,
  "generatedBy": "external-detector-name",
  "textBoxesPath": "1.textboxes.json",
  "bubbleMaskPath": "1.bubbles.json",
  "segmentMaskPath": "1.segment_mask.json",
  "notes": []
}
```

## 坐标和字段

- 坐标系固定为 `originalImageTopLeftPixels`。
- 当前探针图固定映射为 `sourceImage = test/1.png`。
- bbox 格式统一为 `[x, y, width, height]`，左上角原点，像素坐标。
- bbox 宽高必须为正，且不能越过原图边界。
- `confidence` 若存在，必须在 `[0, 1]`。
- TextBoxes 支持 `bbox` 或 `x/y/width/height` 两种输入；报告统一输出 `bbox`。
- BubbleMask 当前契约先接收 instance summary：`id`、`bbox`、`maskValue`、`pixelCount`，不要求提交真实 mask PNG。
- SegmentMask 当前契约先接收 summary：`width`、`height`、`glyphPixelCount`、`connectedComponentCount`，不要求提交真实 mask PNG。
- `linePolygons`、`sourceDirection`、`rotationDegrees` / `rotationDeg`、`detectedFontSizePx` 是可选字段，不作为 readiness 必填；但一旦提供，validator 和 Swift readiness 会校验方向枚举、旋转范围和 line polygon 点位。
- `sourceDirection` 支持 `horizontal`、`horizontal-lr`、`vertical`、`vertical-rl`、`vertical-lr`、`unknown`，大小写、空格和下划线会规范化后比较。
- `rotationDegrees` / `rotationDeg` 必须是有限数值，范围为 `[-360, 360]`。
- `linePolygons` 必须是非空 polygon 数组；每个 polygon 至少 4 个 `[x, y]` 点，点位必须在 `test/1.png` 原图范围内。
- manifest 中 `textBoxesPath`、`bubbleMaskPath`、`segmentMaskPath` 必须是 active artifact 目录内的相对路径；绝对路径和包含 `..` 的路径会被 validator 和 Swift readiness 阻塞。
- active manifest 的 `generatedBy` 必须声明真实 detector / segmenter 来源；缺失或包含 `manual`、`fixture`、`Vision OCR`、`pre-crop`、`line plan`、`BubbleMask proxy`、`SegmentMask proxy`、`ground truth`、`handwritten` 等禁用来源词时，validator 和 Swift readiness 都会阻塞，不允许进入 `readyForShadowOCR`。

## 离线校验

```sh
python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --print-required-files
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid_orientation_partial_unsupported
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid --expect-fail
python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing
```

validator 只读指定目录，不复制、不生成 active artifact。输出 JSON 摘要包含 `verdict`、`readyForShadowOCR`、`externalTextBoxesShadowOCRAllowed`、`nextAction`、`readinessBlockers`、缺失文件、解析错误、坐标错误、TextBox 数量、Bubble instance 数量、SegmentMask 尺寸匹配结果、`artifactIdentitySummary` 和 `orientationMetadataSummary`。`artifactIdentitySummary` 会记录 source image 以及 manifest / TextBoxes / BubbleMask / SegmentMask 的路径、存在性、size、SHA256，并透传 manifest 的 `generatedBy`、`generatedAt`、`contractExampleOnly`、schema、source image 和 coordinate space；用于 Agent C 核对当前云端结果包里的四件套是否就是被审查的 archive 内容。`orientationMetadataSummary` 会汇总 sourceDirection、orientation category、rotation plan、line polygon TextBox、竖排 TextBox、近 90 度倍数 rotation、任意角度 rotation、orientation partial TextBox 和 unsupported reason breakdown。

`--print-required-files` 只打印 Koharu / 外部 detector 侧需要交付的 active 文件清单，不读取或写入 `test/koharu_artifacts/`。缺少真实 active 目录时，`--allow-missing` 的正确结果是 `verdict = manifestMissing`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided`，并列出 `manifest`、`TextBoxes`、`BubbleMask`、`SegmentMask` 的阻塞项；不应额外混入 schema / coordinate 缺失噪音。

云端手动 workflow 可选从 Release archive 注入真实四件套：填写 `koharu_artifact_release_tag`、`koharu_artifact_asset`、`koharu_artifact_sha256` 后，CI 会在 Xcode build 前下载、校验、解压，并且只接受唯一一个同时包含 `1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json` 的目录；找到 0 个或多个候选目录都会失败，避免从不同目录拼出错包。通过后 CI 只复制该目录下四个固定 JSON 到 `test/koharu_artifacts/`，并把 validator identity / orientation 摘要写入未加密结果包；`koharu_artifact_required=true` 时下载、SHA、解压、唯一目录检查或 validator 失败会直接失败。

## 从 Koharu 导出到 AITRANS contract

当前仓库没有真实 active artifact。Koharu 或人工导出时，先在外部生成 detector / segmenter 结果，再转换成上面的四个 JSON 文件；AITRANS 不接受由 Vision OCR、pre-crop plan、line plan、BubbleMask proxy、SegmentMask proxy、ground truth 或手写理想框派生的 active artifact。

最小转换要求：

- 将 Koharu `TextRegion` 的 `x/y/width/height` 转成 `1.textboxes.json` 的 `bbox`，保留 `confidence`、`detector`、`linePolygons`、`sourceDirection`、`rotationDegrees` / `rotationDeg`、`detectedFontSizePx` 等可选字段。
- 将 speech bubble instance 结果转成 `1.bubbles.json`，每个 instance 至少包含 `id`、`bbox`，建议包含 `maskValue` 和 `pixelCount`。
- 将文字像素 mask 统计转成 `1.segment_mask.json`，至少包含与 `test/1.png` 一致的 `width = 576`、`height = 1280`；建议包含 `glyphPixelCount` 和 `connectedComponentCount`。
- `1.manifest.json` 必须显式声明 `schemaVersion = aitrans.koharu_artifact_contract.v1`、`sourceImage = test/1.png`、`coordinateSpace = originalImageTopLeftPixels`、`contractExampleOnly = false`，并记录 `generatedBy`；缺 `sourceImage`、缺 `contractExampleOnly` 或 `contractExampleOnly` 不是布尔值都会被 validator 阻塞。
- manifest 路径字段不得使用绝对路径或 `..` 逃逸 active 目录。
- 转换后先运行 validator；只有 `readyForShadowOCR = true` 且 `externalTextBoxesShadowOCRAllowed = true`，App 探针才允许执行 external TextBoxes shadow OCR。

## v1.15 真实交付包清单

当前 active 目录仍不存在，validator 的正确阻塞结果是 `verdict = manifestMissing`、`nextAction = stopUntilArtifactsProvided`。v1.15 不再接受继续补 Vision crop、line deskew 或 fake fixture；下一步只等待真实 Koharu / 外部 detector 交付包。

Koharu / 人工必须交付以下四个文件：

```text
test/koharu_artifacts/
  1.manifest.json
  1.textboxes.json
  1.bubbles.json
  1.segment_mask.json
```

`1.manifest.json` 必填字段：

```json
{
  "schemaVersion": "aitrans.koharu_artifact_contract.v1",
  "sourceImage": "test/1.png",
  "coordinateSpace": "originalImageTopLeftPixels",
  "contractExampleOnly": false,
  "generatedBy": "真实 detector / Koharu 输出来源",
  "textBoxesPath": "1.textboxes.json",
  "bubbleMaskPath": "1.bubbles.json",
  "segmentMaskPath": "1.segment_mask.json",
  "notes": []
}
```

`1.textboxes.json` 最低要求：

- 顶层是数组，或对象里包含 `textBoxes` / `textboxes` / `items` 数组。
- 每个 TextBox 必须有 `bbox = [x, y, width, height]`，或等价的 `x`、`y`、`width`、`height`。
- 坐标必须是 `test/1.png` 原图左上角像素坐标，原图尺寸固定为 `576 x 1280`。
- bbox 宽高必须为正，不能越界。
- `confidence` 如存在，必须在 `[0, 1]`。
- 可选保留 `linePolygons`、`sourceDirection`、`rotationDegrees` / `rotationDeg`、`detectedFontSizePx`、`detector`；提供时必须通过方向枚举、旋转范围和 line polygon 点位校验。

`1.bubbles.json` 最低要求：

- 顶层是数组，或对象里包含 `bubbleInstances` / `bubbles` / `instances` / `items` 数组。
- 每个气泡 instance 至少包含 `id` 和 `bbox`。
- 建议包含 `maskValue` 和 `pixelCount`，用于后续更严格的 mask-safe layout 归因。
- bbox 坐标同样必须在 `576 x 1280` 原图范围内。

`1.segment_mask.json` 最低要求：

- 顶层是对象。
- 必须包含 `width = 576` 和 `height = 1280`。
- 建议包含 `glyphPixelCount` 和 `connectedComponentCount`。
- 当前契约只要求 summary，不要求提交真实 mask PNG；后续若要启用 mask-safe rendering / inpainting，再扩展真实 mask 文件。

交付后先运行：

```sh
python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --print-required-files
python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts
```

必须达到：

```text
verdict = readyForShadowOCR
readyForShadowOCR = true
externalTextBoxesShadowOCRAllowed = true
missingArtifacts = []
parseErrors = []
coordinateErrors = []
textBoxCount > 0
bubbleInstanceCount > 0
segmentMaskSizeMatches = true
```

禁止作为 active artifact 来源：

- contract examples
- Vision OCR blocks
- pre-crop plan
- line plan
- BubbleMask proxy
- SegmentMask proxy
- ground truth
- handwritten ideal boxes

如果 detector 输出来自裁切图、缩放图或其他坐标空间，必须先在外部转换到 `originalImageTopLeftPixels`，并在 manifest `notes` 说明转换来源。AITRANS App 不会在读取时猜测坐标换算。

ready 后，AITRANS 云端探针应证明：

```text
koharuArtifactValidation.verdict = readyForShadowOCR
externalArtifactReadinessSummary.readinessVerdict = readyForShadowOCR
externalArtifactReadinessSummary.activeArtifactsDirectory = true
externalArtifactReadinessSummary.contractExampleOnly = false
externalArtifactReadinessSummary.externalTextBoxesShadowOCRAllowed = true
externalTextBoxShadowOCRSummary.executed = true
externalTextBoxShadowOCRSummary.candidateCount > 0
externalTextBoxShadowOCRSummary.ocrExecutedCount > 0
koharuArtifactValidationOrientationSummary 可用于审计 TextBox 方向风险
externalTextBoxShadowOCRSummary.orientationReadinessVerdict 已按 App 探针结果填充
```

该路径仍是 shadow-only：external OCR 结果只写入 `probe_report.json` 和 `1_ocr_probe_text.txt`，不得改变 `finalTextUsedForTranslation`、主覆盖图、`blockPassed`、`configuration.currentBlockSource` 或 `textRegionCropReport.adoptedCount`。

## Readiness 语义

只有同时满足以下条件，App 报告才允许进入 external TextBoxes shadow OCR：

```text
readinessVerdict == "readyForShadowOCR"
activeArtifactsDirectory == true
contractExampleOnly == false
externalTextBoxesShadowOCRAllowed == true
```

没有真实 active artifact 时，正确结果仍是 `manifestMissing` 或 `artifactFilesMissing`，`nextAction = stopUntilArtifactsProvided`。本契约工作不改变 `configuration.currentBlockSource`、`finalTextUsedForTranslation`、主覆盖图、`blockPassed` 或 `textRegionCropReport.adoptedCount`。
