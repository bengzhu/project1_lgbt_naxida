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
- `linePolygons`、`sourceDirection`、`rotationDegrees` / `rotationDeg`、`detectedFontSizePx` 是可选字段；有则校验 JSON 结构，不作为 readiness 必填。

## 离线校验

```sh
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail
python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing
```

validator 只读指定目录，不复制、不生成 active artifact。输出 JSON 摘要包含 `verdict`、缺失文件、解析错误、坐标错误、TextBox 数量、Bubble instance 数量和 SegmentMask 尺寸匹配结果。

## Readiness 语义

只有同时满足以下条件，App 报告才允许进入 external TextBoxes shadow OCR：

```text
readinessVerdict == "readyForShadowOCR"
activeArtifactsDirectory == true
contractExampleOnly == false
externalTextBoxesShadowOCRAllowed == true
```

没有真实 active artifact 时，正确结果仍是 `manifestMissing` 或 `artifactFilesMissing`，`nextAction = stopUntilArtifactsProvided`。本契约工作不改变 `configuration.currentBlockSource`、`finalTextUsedForTranslation`、主覆盖图、`blockPassed` 或 `textRegionCropReport.adoptedCount`。
