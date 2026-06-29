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
  -> whole-page OCR blocks
  -> bubble-first OCR candidates
  -> ground-truth-free 融合选择和去重
  -> fused OCR blocks
  -> post-fusion 重复/碎片清理
  -> bubble 分割审计诊断
  -> BubbleMask 轻量子区域诊断
  -> BubbleMask 实例 ID 近似、mask-safe layout 和渲染 mask collision 诊断
  -> BubbleMask 归属修正诊断和保守 split candidate
  -> pre-crop TextBox plan artifact（TextRegion crop 前生成，shadow-only）
  -> TextRegion crop OCR 候选诊断和 split / corrected bubble / subregion / bubble / content / mask coverage 审计
  -> ground-truth-free crop 护栏选择
  -> TextBox / SegmentMask crop 后派生诊断和 failure attribution
  -> 自适应 crop 二次 OCR 诊断
  -> 确定性 OCR 纠错对照
  -> 逐块 Local/Mock 翻译
  -> clean text / batch / whole-page / bubble-first / slice OCR 对照
  -> glyph mask / 背景估计 / 安全布局 / 离屏碰撞检查
  -> TextRegion crop shadow 实验矩阵（control + pre-crop plan 候选，不替换主输入）
  -> TextBox plan 失败归因与晋级门槛审计（解释 blockers，不替换主输入）
  -> line-level TextBox / deskew shadow 验证（仅目标块，不替换主输入）
  -> external artifact readiness gate（真实 TextBoxes / BubbleMask / SegmentMask 输入解析、校验和阻塞报告）
  -> JSON / TXT / PNG 输出
```

禁止：

- 不要失败就跳过绘制。
- 不要让浏览器 UI、广告、底部导航进入 OCR。
- 不要把 ground truth 用于融合候选选择。
- 不要把确定性纠错直接切主流程。
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
  -> MangaOverlayProbeService.runBubbleFirstProbe
  -> fuse whole-page + bubble-first candidates
  -> post-fusion cleanup / bubbleAudits
  -> BubbleMask 归属修正 / split candidate 诊断
  -> TextRegion crop OCR 候选诊断和护栏选择
  -> TranslationSessionStore.translateMangaProbeBlock
  -> TextBox / SegmentMask 派生诊断和 crop experiment shadow 矩阵
  -> external artifact readiness gate
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
- 测试层：`md/test/test.md` 定义本地轻量检查、GitHub Actions 重验证、结果包和失败回传规则。
- 版本层：`update_log.md` 记录历史，`metrics/version_history.csv` 记录可量化指标。

## 4. 云端协作和验证流
当前日常开发不再把本机 Xcode build / 模拟器探针作为默认硬要求。默认流程是：

```text
人工目标
  -> Agent A 本地分析并写版本化提示词
  -> Agent B 从 smalldata_test 开 codeb/vX.Y-短标题 分支
  -> Agent B 本地只跑轻量检查
  -> Agent B push codeb/... 到 GitHub
  -> GitHub Actions 运行 build / JSON / 静态检查 / 可用探针
  -> GitHub Actions 上传未加密 CI 结果包
  -> Agent C 拉取 codeb/...，核对 diff、日志、manifest 和 artifact
      -> 失败：C 输出退回清单，B 按结果包日志继续修
      -> 通过：C 更新核心文档，合并回 smalldata_test 并 push
```

分支规则：

- `main` 只作为外观展示分支，禁止合并日常开发成果。
- `smalldata_test` 是当前远端真实工作主分支；若旧提示词写成 `samlldata_test`，以 `origin/smalldata_test` 为准。
- `codeb/vX.Y-短标题` 是 Agent B 候选实现分支。

结果包规则：

- 加密打包 workflow 只负责软件包交付，不作为 Agent C 验收依据，不为验收改动密码或解密流程。
- Agent C 使用独立未加密 CI 结果包验收，至少核对 `.xcresult`、`junit.xml`、`xcodebuild.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`。
- `ci-artifact-manifest.json` 必须能追溯 `version`、`branch`、`commitSha`、`runId`、`runAttempt`、`workflowName`、`scheme`、`destination`、结果路径和探针报告路径。
- 云端失败时，workflow 必须保留日志和失败摘要，Agent C 按结果包指出应交回 Agent B 修复的失败阶段和日志位置。
- 云端完整漫画探针目前受模拟器、GGUF、App 容器和外部 artifact 等依赖影响；能稳定运行时必须生成新报告，不能稳定运行时必须显式说明未运行范围和后续补齐条件。
- GGUF 模型云端依赖已知，后续由 GitHub Release + workflow 下载 + 缓存解决；本阶段不提交模型文件。

## 5. 已确认铁律
- `TranslationSessionStore` 是单一状态和调度中心。
- ground truth 只能做探针统计，不能做生产候选选择。
- 失败块必须进入报告和覆盖图。
- 可信匹配必须可拒绝，`unmatched` 不进平均准确率。
- 核心对话和装饰标题分开统计。
- 词级 Levenshtein 是当前可信 OCR 相似度口径。
- clean text 失败时优先怀疑模型质量，不继续盲调 OCR。
- bubble-first 当前参与融合主流程；whole-page 原始块和 bubble-first 原始候选仍保留为对照和回退审计。
- TextRegion crop 当前是结构化候选层；v15 会优先尝试可信 split candidate 或 corrected bubble mask，再回退到 block-local subregion、bubble bbox 或 content rect。只有通过 ground-truth-free 护栏才可替换主翻译输入，本轮 0 块采用。
- v18 `preCropTextBoxPlanReport` 是 TextRegion crop 前生成的 Koharu 式上游 TextBox plan artifact；每块最多保留 3 个 plan，只用 fused seed bbox、bubble geometry、BubbleMask majority/safe rect、subRegion、split candidate、assignment correction 和 glyph/SegmentMask proxy 等无真值信号排序。
- v18 `cropExperimentReport` 仍是 shadow-only 实验矩阵；control 使用当前 TextRegion crop，shadow 候选优先来自 `preCropTextBoxPlan.*`，`bestShadowCandidate` 和 `promotionVerdict` 不替换 `finalTextUsedForTranslation`，也不改变 `textRegionCropReport.adoptedCount`。
- v19 `textBoxPlanFailureReport` 用 `sourcePlanID` 串联 plan、candidate 和 block 级结论，只解释 promotion checks / blockers / recommended action，不改变主输入、主覆盖图或 `textRegionCropReport.adoptedCount`。
- v20 `lineTextBoxPlanReport` / `lineCropExperimentReport` 只对 `textBoxPlanFailureReport.continueGeometryResearchBlocks` 生成 line-level TextBox / deskew shadow 候选；当前目标块 `[1, 6, 10]` 共 12 个候选，全部只写报告和 TXT，不改变主输入、主覆盖图、`blockPassed` 或 `textRegionCropReport.adoptedCount`。
- v21 `externalArtifactReadinessReport` 是真实 TextBoxes / BubbleMask / SegmentMask 适配前证据闸门；它只读 `test/koharu_artifacts/` 或 manifest 指定文件，做解析、坐标校验和 block alignment。没有真实 artifact 时输出 `manifestMissing` / `stopUntilArtifactsProvided`，不能用现有 Vision OCR、pre-crop plan 或 line plan 伪装 detector 输出。
- BubbleMask 当前是 bbox/rounded-rect 近似实例 ID mask，用于 seed 归属、归属修正诊断、保守 split candidate、mask-safe layout、crop coverage 和渲染碰撞诊断；不是 Koharu 真实分割 mask，不能把布局收益冒充 OCR 提升。
- 确定性纠错当前是对照路径，不替换 `finalTextUsedForTranslation`。
- tagged batch 当前是负面诊断，不替换逐块翻译。

## 6. 当前关键基线
来自最新 `output/probe_report.json` 和 `output/clean_text_diagnostic.json`：

- `configuration.currentBlockSource = fusedWholePageBubble`
- `totalBlocksDetected = 13`
- `postFusionCleanup.blockCountBeforeCleanup = 16`
- `postFusionCleanup.blockCountAfterCleanup = 13`
- `postFusionCleanup.rejectedBlockCount = 3`
- `groundTruthMatchedBlocks = 13`
- `groundTruthUnmatchedBlocks = 0`
- `averageCoreDialogueOCRSimilarity = 0.7106`
- `averageDecorativeOCRSimilarity = 0.8000`
- `wholePageAccuracyVsGroundTruth = 0.5972`
- `bubbleFirstAccuracyVsGroundTruth = 0.7300`
- `fusionFusedAccuracyVsGroundTruth = 0.7384`
- `frameworkComparison.consistencyPassed = true`
- `fusionComparison.consistencyPassed = true`
- `cleanTextDiagnostic.passRate = 0.4545`
- `textRegionCropReport.totalRegions = 13`
- `textRegionCropReport.cropSucceededCount = 10`
- `textRegionCropReport.adoptedCount = 0`
- `textRegionCropReport.rejectedCount = 13`
- `preCropTextBoxPlanReport.planCount = 37`
- `preCropTextBoxPlanReport.shadowOCREligiblePlanCount = 29`
- `cropExperimentReport.candidateCount = 48`
- `cropExperimentReport.controlCandidateCount = 13`
- `cropExperimentReport.ocrSucceededCount = 36`
- `cropExperimentReport.betterThanControlCount = 13`
- `cropExperimentReport.promotedShadowBlocks = []`
- `textBoxPlanFailureReport.evaluatedPlanCount = 37`
- `textBoxPlanFailureReport.evaluatedCandidateCount = 35`
- `textBoxPlanFailureReport.betterThanControlCandidateCount = 13`
- `textBoxPlanFailureReport.promotedShadowBlockCount = 0`
- `textBoxPlanFailureReport.stopRecommendedBlocks = [2, 3, 4, 5, 7, 9, 11, 12]`
- `textBoxPlanFailureReport.continueGeometryResearchBlocks = [1, 6, 10]`
- `lineTextBoxPlanReport.targetBlocks = [1, 6, 10]`
- `lineTextBoxPlanReport.planCount = 12`
- `lineTextBoxPlanReport.shadowOCREligiblePlanCount = 12`
- `lineCropExperimentReport.candidateCount = 12`
- `lineCropExperimentReport.ocrSucceededCount = 12`
- `lineCropExperimentReport.betterThanControlCount = 5`
- `lineCropExperimentReport.promotedLineShadowBlocks = []`
- `lineCropExperimentReport.stoppedAfterLineResearchBlocks = [1, 6, 10]`
- `textBoxPlanFailureReport.candidatePromotionBlockedBlocks = [1, 2, 4, 5, 6, 9, 10]`
- `passedBlocks = 1`
- `failedBlocks = 12`
- `translationFailureBreakdown = { modelOutputFailure: 2, ocrInputSuspect: 7, translationLanguageQualityFailure: 3 }`
- `likelyRuleFalseFailureBlocks = []`

## 7. 未来扩展点
- 更强小模型对比，优先 Qwen2.5-0.5B-Instruct-GGUF q4_k_m。
- 基于 `bubbleAudits` 对 `bubbleID 4/6/7` 做诊断开关下的保守气泡拆分实验。
- 更稳的气泡候选分割。
- 更强 OCR/纠错护栏，替换主流程前必须用探针证明收益。
- Share Extension 或 ReplayKit 路线，但当前不是优先级。

## 8. 不允许破坏的行为
- 不得静默隐藏翻译失败块。
- 不得让旧输出文件污染新验收。
- 不得把测试真值写入生产决策。
- 不得在报告中维护两套互相矛盾的统计。
- 不得删除 `metrics/version_history.csv` 历史行。
- 不得绕过 `LocalLanguageModeling` 协议直接耦合 UI 和 llama runtime。
