# 项目核心流程文档
本文只记录 AITRANS 当前真实架构和运行流程，不写历史流水账。历史看 `update_log.md`。

## 0. 一句话总览
当前项目主链路是：用户输入文本、音频或图片，`TranslationSessionStore` 统一调度本地状态、Apple OCR/Speech、Mock/Local 模型和持久化；漫画探针独立读取 `test/1.png`，生成 OCR、翻译、覆盖合成和诊断报告。

```text
用户操作 / test 固定素材
  -> SwiftUI 页面
  -> TranslationSessionStore
  -> OCR / Speech / Model Adapter
  -> 质量判定 / 诊断汇总
  -> UI 展示 / state.json / output 调试产物
```

## 1. 核心模块
### 1.1 SwiftUI App 入口
职责：创建全局 `TranslationSessionStore` 并注入 UI。

输入：

- App 启动。

输出：

- `ContentView().environmentObject(store)`。

关键文件：

- `AITRANS/App/AITRANSApp.swift`

禁止：

- 不要在 UI 层创建第二套 store。

### 1.2 UI 层
职责：提供文本、图片、音频、历史、设置、模型、Pro 和开发调试入口。

输入：

- 用户输入文本。
- 图片或音频文件选择。
- 模型和提示词配置。
- 开发页 raw 探针和漫画探针按钮。

输出：

- 调用 `TranslationSessionStore` 方法。
- 展示翻译、历史、模型状态、OCR 块、探针报告和错误。

关键文件：

- `AITRANS/Views/ContentView.swift`
- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS/Views/ProFeatureViews.swift`
- `AITRANS/Views/AppTheme.swift`

禁止：

- 不要绕过 store 直接读写持久化 JSON 或调用模型。
- 不要把开发页 raw 输出清洗成普通译文。

### 1.3 TranslationSessionStore
职责：统一管理状态、持久化、模型选择、文本/图片/音频翻译、开发探针和漫画探针。

输入：

- UI 事件。
- OCR/Speech 结果。
- Mock 或 Local 模型输出。
- `test/` 固定素材和输出报告。

输出：

- Published UI 状态。
- `Application Support/AITRANS/state.json`。
- `output/probe_report.json` 相关报告模型。
- 诊断汇总和质量判定结果。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`

禁止：

- 不要在其他模块重复实现模型选择、质量判定或持久化入口。
- 不要把 ground truth 引入生产候选选择。

### 1.4 模型适配层
职责：统一 Mock 和 Local 生成接口。

输入：

- `ModelGenerationRequest`
- 当前语言、提示词、采样参数和任务类型。

输出：

- `ModelGenerationResult`
- `RawModelProbeResult`

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MockGemmaService.swift`
- `AITRANS/Services/GemmaLocalService.swift`
- `AITRANS/Services/LlamaRuntime.swift`
- `AITRANS/Services/LocalModelDownloadService.swift`

规则：

- 普通用户翻译和 summary 走 sampled 解码。
- 漫画探针、raw 诊断、clean text、batch 对照和纠错翻译对照走 deterministic 解码。
- 当前内置 Gemma 270M 不作为质量基准。

禁止：

- 不要提交 GGUF 模型文件。
- 不要把 raw 探针结果伪装成普通 UI 成功。

### 1.5 普通图片 OCR 翻译
职责：对用户选图做 Vision OCR，并按 bbox 展示译文。

输入：

- 用户选择的图片数据。

输出：

- `ImageTranslationBlock`
- 旁贴或覆盖展示。

关键文件：

- `AITRANS/Services/VisionOCRService.swift`
- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS/Services/TranslationSessionStore.swift`

禁止：

- 不要把漫画探针专用真值、纠错或质量统计混入普通图片生产路径。

### 1.6 漫画覆盖翻译探针
职责：固定读取 bundle 内 `test/1.png`，跑 OCR、翻译、覆盖绘制和诊断报告。

输入：

- `test/1.png`
- `test/1.ground_truth.json`
- 当前模型引擎和英译中提示词。

输出：

- `Application Support/AITRANS/Output/`
- 项目根 `output/` 导出副本。
- `probe_report.json`
- `clean_text_diagnostic.json`
- `1_ocr_probe_text.txt`
- 多张 PNG，包括 `1_probe_contact_sheet.png`。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `scripts/export-probe-output.sh`

当前主流程：

```text
test/1.png
  -> 裁掉浏览器 UI / 广告 / 底部导航
  -> 内容区 2x 放大
  -> 0/90/180/270 Vision OCR
  -> OCR candidates
  -> 气泡候选检测和 bubbleID 归属
  -> 同 bubble 合并，跨 bubble 拒绝
  -> final OCR blocks
  -> 自适应 crop 二次 OCR 诊断
  -> 确定性 OCR 纠错对照
  -> 逐块 Local/Mock 翻译
  -> clean text / batch / bubble-first / slice OCR 对照
  -> glyph mask / 背景估计 / 安全布局 / 离屏碰撞检查
  -> JSON / TXT / PNG 输出
```

禁止：

- 不要失败就跳过绘制。
- 不要让浏览器 UI、广告、底部导航进入 OCR。
- 不要把 bubble-first 或确定性纠错直接切主流程。
- 不要把 `accuracyVsGroundTruth = 0.8378 / 0.8755` 当新基线。

### 1.7 持久化和输出
职责：保存用户状态、历史、提示词和探针产物。

路径：

- App 状态：`Application Support/AITRANS/state.json`
- 导出 JSON：`Application Support/AITRANS/aitrans-export.json`
- 本地模型：`Application Support/Models/Gemma-1.5B/model.gguf`
- 探针沙盒输出：`Application Support/AITRANS/Output/`
- 项目导出输出：`output/`
- 长期指标：`metrics/version_history.csv`

规则：

- 探针输出目录每轮必须清理，不能堆积旧图。
- `metrics/version_history.csv` 不随 `output/` 清理。
- 每次版本收尾追加指标，不覆盖历史行。

## 2. 核心执行流
### 2.1 文本翻译
```text
用户输入文本
  -> ContentView
  -> TranslationSessionStore.makeRequest
  -> selectedEngine
  -> MockGemmaService 或 GemmaLocalService
  -> cleanTranslationOutput / 质量检查
  -> transcript / history / UI
```

### 2.2 图片翻译
```text
用户选择图片
  -> TranslationSessionStore.translateImage
  -> VisionOCRService.recognizeTextBlocks
  -> 每块调用 translate
  -> ImageTranslationBlock
  -> 旁贴或覆盖 UI
```

### 2.3 音频翻译
```text
用户选择或长按录音
  -> Apple Speech on-device recognition
  -> recognized text
  -> TranslationSessionStore.translate
  -> UI 展示
```

### 2.4 漫画探针
```text
开发页运行漫画覆盖翻译探针
  -> TranslationSessionStore.runMangaOverlayProbe
  -> MangaOverlayProbeService.recognizeTextBlocks
  -> TranslationSessionStore.translateMangaProbeBlock
  -> makeMangaOverlayProbeDiagnostics
  -> render overlays / contact sheet
  -> write JSON / TXT / PNG
  -> scripts/export-probe-output.sh 导出
```

## 3. 数据层 / 模型层 / 测试层关系
- 数据层：`TranscriptModels.swift` 定义会话、提示词、模型请求、OCR 块、漫画报告和诊断结构。
- 状态层：`TranslationSessionStore.swift` 汇总 UI 状态、持久化、翻译调用和报告生成。
- 服务层：Vision OCR、Manga probe、Local model download、Gemma local、llama runtime。
- UI 层：SwiftUI 页面只展示状态并触发 store 方法。
- 测试层：`md/test/test.md` 定义 build、JSON、探针、导出和静态检查层级。
- 版本层：`update_log.md` 记录历史，`metrics/version_history.csv` 记录可量化指标。

## 4. 已确认铁律
- `TranslationSessionStore` 是单一状态和调度中心。
- ground truth 只能做探针统计，不能做生产候选选择。
- 失败块必须进入报告和覆盖图。
- 可信匹配必须可拒绝，`unmatched` 不进平均准确率。
- 核心对话和装饰标题分开统计。
- 词级 Levenshtein 是当前可信 OCR 相似度口径。
- clean text 失败时优先怀疑模型质量，不继续盲调 OCR。
- bubble-first 当前是对照路径，不是主流程替代。
- 确定性纠错当前是对照路径，不替换 `finalTextUsedForTranslation`。
- tagged batch 当前是负面诊断，不替换逐块翻译。

## 5. 当前关键基线
来自最新 `output/probe_report.json` 和 `output/clean_text_diagnostic.json`：

- `totalBlocksDetected = 14`
- `groundTruthMatchedBlocks = 10`
- `groundTruthUnmatchedBlocks = 4`
- `averageCoreDialogueOCRSimilarity = 0.6131`
- `averageDecorativeOCRSimilarity = 0.8000`
- `wholePageAccuracyVsGroundTruth = 0.6131`
- `bubbleFirstAccuracyVsGroundTruth = 0.7397`
- `frameworkComparison.consistencyPassed = true`
- `cleanTextDiagnostic.passRate = 0.4545`
- `passedBlocks = 1`
- `failedBlocks = 13`
- `translationFailureBreakdown = { ocrInputSuspect: 10, translationLanguageQualityFailure: 3 }`
- `likelyRuleFalseFailureBlocks = []`

## 6. 未来扩展点
- 更强小模型对比，优先 Qwen2.5-0.5B-Instruct-GGUF q4_k_m。
- bubble-first 主候选与 whole-page 真实内容兜底的融合架构。
- 更稳的气泡候选分割，尤其底部相邻气泡。
- 更强 OCR/纠错护栏，替换主流程前必须用探针证明收益。
- Share Extension 或 ReplayKit 路线，但当前不是优先级。

## 7. 不允许破坏的行为
- 不得静默隐藏翻译失败块。
- 不得让旧输出文件污染新验收。
- 不得把测试真值写入生产决策。
- 不得在报告中维护两套互相矛盾的统计。
- 不得删除 `metrics/version_history.csv` 历史行。
- 不得绕过 `LocalLanguageModeling` 协议直接耦合 UI 和 llama runtime。
