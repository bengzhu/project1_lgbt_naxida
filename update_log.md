# 项目版本更新记录
本文记录 AITRANS 的正式版本、重要维护事项、关键决策和遗留问题。它不是流水账，细节证据优先看 `README.md`、`metrics/version_history.csv`、最新 `output/` 和 git 提交。

## 维护规则
- 每完成一个正式版本或重要任务后追加记录。
- 记录必须包含：版本或任务名、日期、核心变更、关键文件、验证结果、遗留事项。
- 文档整理、目录迁移、回滚、打捞等不伪装成新版本，写入“历史维护记录”。
- 若核心逻辑、测试规范或项目行为变化，必须同步更新本日志、`md/flow/flow.md`、`md/flow/flowchart.md` 或 `md/test/test.md`。
- 涉及漫画探针或翻译链路时，README 近期记录和 `metrics/version_history.csv` 必须 append-only 更新。

## 当前状态
日期：2026-06-29

当前项目是 SwiftUI iOS 本地翻译原型，主线已从普通翻译 UI 转到漫画截图 OCR、本地翻译、覆盖合成和探针诊断。最新可用基线来自当前 `output/probe_report.json`、`output/clean_text_diagnostic.json` 和 `metrics/version_history.csv` 的 v21 行：

- `sourceImage = test/1.png`
- `engineUsed = Local GGUF`
- `decodingMode = deterministic`
- `decodingSeed = 42`
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
- `frameworkComparison.consistencyPassed = true`
- `fusionComparison.consistencyPassed = true`
- `fusion.fused.accuracyVsGroundTruth = 0.7384`
- `cleanTextDiagnostic.passRate = 0.4545`
- `textRegionCropReport.totalRegions = 13`
- `textRegionCropReport.cropSucceededCount = 10`
- `textRegionCropReport.adoptedCount = 0`
- `textRegionCropReport.rejectedCount = 13`
- `bubbleSubRegionReport.totalSubRegions = 11`
- `bubbleSubRegionReport.clampEligibleCount = 2`
- `bubbleSubRegionReport.oversizedBubbleIDs = [4, 6, 7]`
- `textRegionCropReport.clampSources = { bubbleBBox: 9, contentRect: 2, subRegion: 2 }`
- `bubbleMaskReport.instanceCount = 8`
- `bubbleMaskReport.maskSafeLayoutBlocks = 13`
- `bubbleMaskReport.bboxFallbackBlocks = 0`
- `bubbleMaskReport.inconsistentBubbleAssignmentBlocks = [4, 5, 11, 12]`
- `bubbleMaskReport.renderMaskOverflowBlocks = []`
- `bubbleAssignmentCorrectionReport.recommendedCorrectionBlocks = [5, 11]`
- `bubbleAssignmentCorrectionReport.appliedToCropClampBlocks = [5]`
- `bubbleAssignmentCorrectionReport.rejectedCorrectionBlocks = [4, 11, 12]`
- `bubbleSplitCandidateReport.parentBubbleIDs = [4, 6, 7]`
- `bubbleSplitCandidateReport.candidateCount = 6`
- `bubbleSplitCandidateReport.clampEligibleCount = 3`
- `bubbleSplitCandidateReport.appliedToCropClampBlocks = [5, 9, 10]`
- `textBoxCandidateReport.candidateCount = 13`
- `textBoxCandidateReport.cropEligibleCount = 6`
- `textBoxCandidateReport.usedForCropBlocks = []`
- `textBoxCandidateReport.rejectedBlocks = [2, 4, 5, 7, 9, 11, 12]`
- `segmentMaskReport.glyphMaskBlocks = 11`
- `segmentMaskReport.usableForCropEvidenceBlocks = [0, 1, 2, 3, 6, 7, 8, 9, 10, 11]`
- `segmentMaskReport.weakSegmentBlocks = [4, 5, 12]`
- `preCropTextBoxPlanReport.planCount = 37`
- `preCropTextBoxPlanReport.shadowOCREligiblePlanCount = 29`
- `preCropTextBoxPlanReport.selectedForShadowOCRBlocks = [0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11]`
- `preCropTextBoxPlanReport.stoppedBlocks = [4, 12]`
- `cropExperimentReport.candidateCount = 48`
- `cropExperimentReport.controlCandidateCount = 13`
- `cropExperimentReport.ocrSucceededCount = 36`
- `cropExperimentReport.betterThanControlCount = 13`
- `cropExperimentReport.promotedShadowBlocks = []`
- `cropExperimentReport.stoppedBlocks = [2, 3, 4, 5, 7, 9, 11, 12]`
- `textBoxPlanFailureReport.evaluatedBlockCount = 13`
- `textBoxPlanFailureReport.evaluatedPlanCount = 37`
- `textBoxPlanFailureReport.evaluatedCandidateCount = 35`
- `textBoxPlanFailureReport.betterThanControlCandidateCount = 13`
- `textBoxPlanFailureReport.promotedShadowBlockCount = 0`
- `textBoxPlanFailureReport.stopRecommendedBlocks = [2, 3, 4, 5, 7, 9, 11, 12]`
- `textBoxPlanFailureReport.continueGeometryResearchBlocks = [1, 6, 10]`
- `textBoxPlanFailureReport.candidatePromotionBlockedBlocks = [1, 2, 4, 5, 6, 9, 10]`
- `lineTextBoxPlanReport.targetBlocks = [1, 6, 10]`
- `lineTextBoxPlanReport.planCount = 12`
- `lineTextBoxPlanReport.shadowOCREligiblePlanCount = 12`
- `lineCropExperimentReport.candidateCount = 12`
- `lineCropExperimentReport.ocrSucceededCount = 12`
- `lineCropExperimentReport.betterThanControlCount = 5`
- `lineCropExperimentReport.promotedLineShadowBlocks = []`
- `lineCropExperimentReport.stoppedAfterLineResearchBlocks = [1, 6, 10]`
- `externalArtifactReadinessReport.manifestFound = false`
- `externalArtifactReadinessReport.textBoxesFound = false`
- `externalArtifactReadinessReport.bubbleMaskFound = false`
- `externalArtifactReadinessReport.segmentMaskFound = false`
- `externalArtifactReadinessReport.readinessVerdict = manifestMissing`
- `externalArtifactReadinessReport.nextAction = stopUntilArtifactsProvided`
- `externalArtifactReadinessReport.missingArtifacts = [manifest, TextBoxes, BubbleMask, SegmentMask]`
- `externalArtifactReadinessReport.blockAlignment.count = 13`
- `textRegionCropReport.failureAttributionBreakdown = { localVisionRegression: 6, rawWordsLost: 5, bubbleMaskConflict: 3, emptyLocalOCR: 3, segmentMaskWeak: 3, textBoxTooWide: 2, introducedLikelyOCRError: 2, wordCountRegression: 2, sameAsFusedText: 2, insufficientQualityGain: 2 }`
- `passedBlocks = 1`
- `failedBlocks = 12`
- `translationFailureBreakdown = { modelOutputFailure: 2, ocrInputSuspect: 7, translationLanguageQualityFailure: 3 }`
- `likelyRuleFalseFailureBlocks = []`

当前结论：

- 当前瓶颈是 OCR 文本质量和 Gemma 270M 翻译能力，不是覆盖绘制，也不是规则过严。
- 主流程已切到 whole-page + bubble-first 融合；`Let's Battle!` 保留，bubble-first 独有两条真实内容也进入融合结果。
- post-fusion cleanup 已把 16 个融合块压到 13 个，拒绝重复/碎片块但保留关键真实内容。
- TextRegion crop OCR 候选层已接入报告和 `1_ocr_probe_text.txt`，本轮 13 个块全部被护栏回退，没有替换主翻译输入。
- `bubbleAudits` 标出 `bubbleID 4/6/7` 的分割风险；v13 新增轻量 `bubbleSubRegionReport`，v14 新增 `bubbleMaskReport`，v15 新增归属修正报告和保守 split candidate 报告，v16 新增轻量 `textBoxCandidateReport`、`segmentMaskReport` 和 crop failure attribution，v17 新增 shadow-only `cropExperimentReport`，v18 新增 TextRegion crop 前生成的 `preCropTextBoxPlanReport`，v19 新增 `textBoxPlanFailureReport`，v20 新增 `lineTextBoxPlanReport` / `lineCropExperimentReport`。当前只有 block 5 的归属修正用于 crop clamp，split candidate 用于块 `[5, 9, 10]` 的 crop clamp；TextBox 候选是 TextRegion crop 之后派生的诊断层，`usedForCropBlocks = []`；pre-crop plan、crop experiment、line crop experiment 的 best shadow candidate 和 failure attribution 都不替换 `finalTextUsedForTranslation`；crop 采用护栏未放宽。
- v20 证明 block `[1, 6, 10]` 的 line-level / deskew shadow 候选仍不能通过既有 promotion gate，应停止继续在这条 crop/line/deskew 试参线上消耗。
- v21 新增真实 TextBoxes / BubbleMask / SegmentMask artifact 适配前证据闸门；当前 `test/koharu_artifacts/` 不存在，报告明确阻塞在 `manifestMissing`，不得伪造 detector 接入。
- Vision `customWords` 对当前图最终合并文本无变化，`changedBlockIndexes = []`。
- 确定性 OCR 纠错能提升部分相似度，但翻译收益不稳定，仍只做探针对照。
- tagged batch 翻译分支格式崩坏，不替换逐块翻译。

## 历史记录
### 协作流程维护：云端验证和结果包制度
日期：2026-06-29
依据：流程制度变更，不是漫画探针质量版本；未刷新 `output/`，未追加 `metrics/version_history.csv` 漫画指标行。

核心变更：

- 将日常重验证默认迁移到 GitHub Actions；本机默认只做 `git diff --check`、JSON/YAML smoke 等轻量检查。
- 明确当前真实工作主分支为 `smalldata_test`，Agent B 候选分支为 `codeb/vX.Y-短标题`，Agent C 通过后合并回 `smalldata_test`，禁止合并到 `main`。
- 增加 `agenta` / `a:`、`agentb` / `b:`、`agentc` / `c:` 召唤规则和最终回复身份标识。
- 保留现有带密码的软件包打包流程，不为 Agent C 验收改动或解密；Agent C 只使用独立未加密 CI 结果包。
- 要求云端失败时保留 `.xcresult`、`junit.xml`、`xcodebuild.log`、`ci-artifact-manifest.json` 和 `ci-failure-summary.md`，由 Agent C 指明失败阶段和日志位置后退回 Agent B 修复。
- 记录 GGUF 云端模型依赖为已知后续事项：未来通过 GitHub Release + workflow 下载 + 缓存解决，本轮不提交模型、不处理 Release asset。

关键文件：

- `AGENTS.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/prompt/README.md`
- `.github/workflows/ci-results.yml`

验证结果：

- 本轮应运行文档/JSON/YAML 静态检查。
- 未运行本机 Xcode build / 漫画探针；按新规则交给云端验证。

遗留事项：

- 云端完整漫画探针仍受 GGUF、模拟器容器、App 沙盒输出导出和外部 artifact 依赖影响；能稳定运行后必须由 workflow 生成新报告。
- 旧文档 `md/云端协作流程/云端改造.md` 是原始提示词归档，其中 `samlldata_test` 拼写与当前远端真实分支不一致；执行时以 `smalldata_test` 为准。

### 项目初始与多页 SwiftUI 原型
日期：2026-06 中旬
依据提交：`c988066` 到 `b7376d8`、`2b1a4f7`、`9a1a456`、`43f6890`、`ae7fe12`

核心变更：

- 建立 SwiftUI iOS App 骨架和 Xcode 工程。
- 形成文本翻译、历史、提示词、模型、Pro、开发调试等多页结构。
- `TranslationSessionStore` 成为状态和持久化中心。
- 本地状态落到 `Application Support/AITRANS/state.json`。
- 引入 Apple Vision OCR、Speech、StoreKit 2 占位和本地模型目录概念。

关键文件：

- `AITRANS/App/AITRANSApp.swift`
- `AITRANS/Views/ContentView.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/VisionOCRService.swift`
- `README.md`

验证结果：

- 历史记录显示 `plutil`、asset JSON 检查、iOS Simulator build 和 generic iOS build 曾通过。
- 当时 CoreSimulator service 不稳定，未完成完整点击交互测试。

遗留事项：

- UI 已可用，但主线质量依赖后续 OCR、模型和探针。

### LLM 接口、自测和 Local 模型路径
日期：2026-06 中旬
依据提交：`92f2a8c`、`84d00bb`、`c529c6b`

核心变更：

- 新增 LLM 接口自测和更严格的翻译探针。
- 确认本地模型路线优先走 `llama.cpp + GGUF`。
- 英译中自测开始拒绝返回原文、包含完整原文和不像目标语言的输出。
- 模型导入后统一复制为 `Application Support/Models/Gemma-1.5B/model.gguf`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Views/ContentView.swift`
- `README.md`

验证结果：

- `git diff --check` 通过。
- `plutil -lint` 通过。
- iOS Simulator build 和 generic iOS build 通过。

遗留事项：

- 当时 Local 仍偏接口接入和冒烟，真实翻译质量还需 raw 探针和模型对比。

### Developer Console、Pro 页和测试入口
日期：2026-06 中旬
依据提交：`6b7df35`、`7e552ed`、`9adb9a0`

核心变更：

- 新增开发者调试界面，展示真实 prompt、raw output 和错误。
- Pro 从首页迁移到独立底部 Tab。
- Pro 页新增 StoreKit 2 订阅骨架、长按麦克风同声传译、音频和 OCR 测试入口。
- 修复缺少 `test/` 空文件夹导致的编译失败。

关键文件：

- `AITRANS/Views/ContentView.swift`
- `AITRANS/Views/ProFeatureViews.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `test/.gitkeep`
- `README.md`

验证结果：

- README 记录了相关功能和入口。
- 编译失败由 `test/.gitkeep` 修复。

遗留事项：

- StoreKit 商品仍未上线，购买链路只能作为骨架。
- 语音和权限行为需要真机验证。

### 普通图片 OCR 翻译与漫画探针起步
日期：2026-06 中旬
依据提交：`f6f22e7`、`b95b97f`、`1daddcd`、`b5811b7`、`4a9eab4`、`4288e32`、`103d773`、`51fa18d`

核心变更：

- 普通图片翻译接入 Apple Vision OCR，支持按 bbox 旁贴或覆盖译文。
- 漫画截图 `test/1.png` 进入固定探针链路。
- 探针开始记录 OCR 坐标、逐块 prompt/raw output、debug boxes、translated overlay 和 JSON 报告。
- 引入内容裁切、2x 放大、多角度 OCR、空间聚类、预处理对照、OCR 纠错护栏、iOS 18+ RecognizeTextRequest 对比、customWords 和 bubble-first 初版对照。

关键文件：

- `AITRANS/Services/VisionOCRService.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `scripts/export-probe-output.sh`
- `test/1.png`
- `README.md`

验证结果：

- 多轮在 iPhone 17 Pro 模拟器运行 `test/1.png` 探针并导出 `output/`。
- 初期旧指标 `0.8378 / 0.8755` 后来被确认因真值不完整、强行匹配和旧相似度过宽而不可信。

遗留事项：

- OCR 已能定位文字区域，但文本误识别严重。
- Gemma 270M raw 输出常复读英文、空输出、占位或解释。

### v13-v20：失败诊断、质量门槛、纠错对照和总览输出
日期：2026-06 下旬
依据提交：`382d8ee` 到 `b5be534`

核心变更：

- 报告新增输出清理证明、`translationDecisionTrace`、`translationFailureDetail`、`translationFailureBreakdown`、`ocrProbeNotes`。
- `blockPassed` 质量门槛收紧，不再只凭含中文判定成功。
- 引入确定性 OCR 纠错候选、纠错覆盖图、纠错后翻译对照和 `1_ocr_probe_text.txt`。
- 新增 `1_bubble_text_overlay.png` 和 `1_probe_contact_sheet.png`，便于优先看总览图。
- `outputCleanupRemovedItemCount`、`outputFileCountAfterCleanup` 等字段证明输出目录每轮重建。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`
- `README.md`

验证结果：

- 多轮 `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` 通过。
- 多轮模拟器探针导出。
- `git diff --check` 通过。
- v20 时 `totalBlocksDetected = 12`、`passedBlocks = 0`、`failedBlocks = 12`，输出目录保留 14 个本轮文件。

遗留事项：

- 当前未完成的是翻译质量可用。
- Local Gemma 270M raw 输出不稳和 OCR 原句错误仍是主因。

### v21：结构化真值、可信匹配和新基线
日期：2026-06 下旬
依据：`README.md` 近期记录

核心变更：

- `test/1.ground_truth.json` 改为 12 条结构化真值：11 条 `dialogue`、1 条 `decorative`。
- 真值匹配改为可拒绝匹配，低于阈值标记 `unmatched`。
- 相似度改用词级 Levenshtein，保留旧 `ocrLegacySimilarity` 作对照。
- 核心对话和装饰标题分开统计。
- 新增 clean text diagnostic，直接把 dialogue 真值送入翻译链路。

关键文件：

- `test/1.ground_truth.json`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- 当轮可信基线为 `totalBlocksDetected = 12`、`10 matched / 2 unmatched`、核心对话 `0.6196`、装饰标题 `0.8000`、bubble-first `0.7397`、clean text `4/11`。

遗留事项：

- README 中旧 `0.8378 / 0.8755` 只能作为历史对照，不再用于验收。

### Agent 1-2：气泡几何约束和长图 slice OCR 诊断
日期：2026-06 下旬
依据提交：`ad56eae`、README Agent 1-2 记录

核心变更：

- 引入气泡候选几何约束，把 OCR candidate 分配到 `bubbleID`。
- 同一 bubble 内合并，跨 bubble 合并被拒绝。
- 新增长图竖向 slice OCR 诊断，长宽比超过阈值时分片 OCR、坐标还原和重叠去重。
- 合成长图机制测试验证 3 个竖向切片和 20% 重叠去重。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `md/koharu研究/v5work.md`
- `README.md`

验证结果：

- `test/1.png` 默认不触发 slice，主图结果保持 `14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`、装饰 `0.8000`。
- 合成长图触发 3 个竖向切片，重叠去重链路跑通。

遗留事项：

- 块数从 12 增至 14，是气泡边界拒绝旧跨气泡合并导致，不是 OCR 阈值变激进。
- 底部相邻气泡仍有分割问题。

### v10：whole-page + bubble-first 融合主流程
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.0（bubble融合主流程）.md`、当前 `output/probe_report.json`

核心变更：

- 新增融合候选模型、`fusionResults` 和 `fusionComparison`。
- 融合选择只用 bbox、bubbleID、文本相似度、OCR 置信度、文本长度和疑似 OCR 损坏等无真值信号。
- 主翻译输入切到 `fusedWholePageBubble`；whole-page 和 bubble-first 原始对比仍保留用于回退审计。
- 保留 whole-page 独有 `Let's Battle!`，并纳入 bubble-first 独有的两条真实内容。
- `renderOutputs` 不再二次清空沙盒 Output，避免提前生成的 bubble 调试图被本轮主渲染删除；目录清理由探针开始和导出脚本负责。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `output/probe_report.json`
- `metrics/version_history.csv`

验证结果：

- iPhone 17 Pro 模拟器重新跑 `test/1.png` 并导出。
- `totalBlocksDetected = 16`、可信匹配 `13`、未匹配 `3`。
- `averageCoreDialogueOCRSimilarity = 0.7106`、`averageDecorativeOCRSimilarity = 0.8000`。
- `frameworkComparison.consistencyPassed = true`、`fusionComparison.consistencyPassed = true`。
- `fusion.fused.accuracyVsGroundTruth = 0.7384`。
- `cleanTextDiagnostic.passRate = 0.4545`。
- `translationFailureBreakdown = { modelOutputFailure: 2, ocrInputSuspect: 10, translationLanguageQualityFailure: 3 }`。
- `likelyRuleFalseFailureBlocks = []`。

遗留事项：

- 融合提高了 OCR 覆盖和可信匹配，但翻译通过仍只有 1 块，瓶颈仍在 OCR 噪声和 Gemma 270M 翻译能力。
- `totalBlocksDetected = 16` 是纳入真实 bubble-only 内容后的结果；后续仍需继续压重复/碎片块。

### v11：融合后重复碎片压缩与气泡分割审计
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.1（重复碎片压缩与气泡分割审计）.md`、当前 `output/probe_report.json`

核心变更：

- 在 `fusedWholePageBubble` 后新增 post-fusion cleanup，拒绝明显重复、被包含、低信息或与更完整候选重叠的碎片块。
- 清理逻辑只用 bbox、bubbleID、source、文本长度、词覆盖、候选间覆盖关系和 OCR 质量启发，不用 ground truth 做生产选择。
- `probe_report.json` 新增 `fusionComparison.postFusionCleanup`，记录清理前后块数、拒绝块、拒绝原因、关联块和保护内容。
- `bubbleGeometry` 新增 `bubbleAudits`，诊断每个 bubble 的文本区数量、selected block 数、重叠风险、过大 bubble 风险和 `bubbleSplitCandidate`；本轮不默认拆分主流程。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `metrics/version_history.csv`
- `md/flow/flow.md`
- `md/flow/flowchart.md`

验证结果：

- iPhone 17 Pro 模拟器重新跑 `test/1.png` 并导出最新 `output/`。
- `totalBlocksDetected = 13`，清理前 `16`，清理后 `13`，拒绝 `3` 块。
- 被拒绝块：`THE SUGSESTION WAS OVERPULED...`、`PLAY ONLING...`、`JUST`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。
- `groundTruthMatchedBlocks = 13`，`groundTruthUnmatchedBlocks = 0`。
- `averageCoreDialogueOCRSimilarity = 0.7106`，`averageDecorativeOCRSimilarity = 0.8000`。
- `frameworkComparison.consistencyPassed = true`，`fusionComparison.consistencyPassed = true`。
- `fusion.fused.accuracyVsGroundTruth = 0.7384`，`cleanTextDiagnostic.passRate = 0.4545`。
- `passedBlocks = 1`，`failedBlocks = 12`，`translationFailureBreakdown = { modelOutputFailure: 2, ocrInputSuspect: 7, translationLanguageQualityFailure: 3 }`。
- `likelyRuleFalseFailureBlocks = []`。

遗留事项：

- `-02 AT / LEAST... 2EN-` 残片被保守保留，避免跨 bubble 误删真实内容；后续应在气泡分割层处理。
- `bubbleAudits` 标出 `bubbleID 4/6/7` 有多块同 bubble 或过大 bubble 风险，下一轮可做诊断开关下的保守拆分实验。

### v12：TextRegion crop 候选与结构化中间层
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.2（TextRegion crop候选与Koharu结构化中间层）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 TextRegion crop OCR 候选层，为每个 post-fusion 主块记录 seed bbox、region bbox、crop bbox、bubble clamp、padding、方向、whole-page/fused/adaptive/crop 文本和选择决策。
- `probe_report.json` 新增 `textRegionCropReport`，`1_ocr_probe_text.txt` 同步写入每块 crop 文本、selected 文本、拒绝理由、词保留率和质量分。
- crop 采用逻辑只用 ground-truth-free 信号：词数、词保留率、文本相似度、拉丁/符号比例、疑似 OCR 错误、bubble clamp 和质量分；真值只在选择后用于报告评估。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `textRegionCropReport.totalRegions = 13`，`cropSucceededCount = 10`，`adoptedCount = 0`，`rejectedCount = 13`。
- 主要拒绝原因：`rawWordsLost = 5`、`emptyCropText = 3`、`wordCountRegression = 2`、`sameAsFusedText = 2`、`insufficientQualityGain = 2`、`introducedLikelyOCRError = 1`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。

遗留事项：

- 当前 crop 候选没有足够收益，不能为了指标强行替换主翻译输入。
- 后续应优先改进 TextRegion 检测/气泡分割质量，再重新评估 crop 采用收益。

### v13：BubbleMask 子区域诊断与 TextRegion clamp
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.3（BubbleMask子区域与TextRegion clamp优化）.md`、当前 `output/probe_report.json`

核心变更：

- 新增轻量 `bubbleSubRegionReport`，用 fused block seed bbox、parent bubble bbox、oversized bubble audit 和几何覆盖率生成 block-local subregion 诊断。
- TextRegion crop OCR 优先使用 `clampEligible` 的 subregion 作为 clamp 边界；无可信 subregion 时继续回退到 bubble bbox 或 content rect。
- `textRegionCropReport.diagnostics` 新增 `clampSource`、`subRegionID`、`subRegionBBox`、`subRegionCoverageRatio`、`subRegionRejectedReason`、subregion clamp 前后 crop bbox。
- `1_ocr_probe_text.txt` 同步写入每块 subregion/clamp 证据。
- crop 采用护栏保持 v12 口径，不放宽 adopted 条件，不用 ground truth 做 subregion 生成、crop clamp 或候选选择。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `bubbleSubRegionReport.totalSubRegions = 11`，`clampEligibleCount = 2`，`oversizedBubbleIDs = [4, 6, 7]`。
- `textRegionCropReport.clampSources = { bubbleBBox: 9, contentRect: 2, subRegion: 2 }`，subregion clamp 实际用于块 `[6, 8]`。
- `textRegionCropReport.totalRegions = 13`，`cropSucceededCount = 10`，`adoptedCount = 0`，`rejectedCount = 13`；主要拒绝原因未因 clamp 变化被放宽。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。

遗留事项：

- 轻量 subregion 仍是传统几何近似，不是真正 Koharu 实例 mask。
- 当前 `adoptedCount = 0`，说明 subregion clamp 只提供了更清楚的 crop 串扰证据，尚未证明可替换主翻译输入。
- 下一步应继续观察 `bubbleID 4/6/7` 的 sibling overlap 和 subregion 失败原因，再决定是否引入更强的 bubble/text region 检测。

### v14：BubbleMask 实例 ID 与 mask 安全区诊断
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.4（BubbleMask实例ID与mask安全区诊断）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `bubbleMaskReport`，用现有 bubble bbox 生成轻量实例 ID mask 近似，背景为 0，内部栅格值为 `bubbleID + 1`。
- 逐块记录 `maskDominantBubbleID`、`maskDominantCoverageRatio`、`maskIDsUnderSeed`、mask-safe rect、渲染 mask collision 和 crop mask coverage。
- safe layout 优先使用可信 mask-safe rect；不可用时回退既有 bbox safe rect。
- TextRegion crop 只新增 mask 覆盖诊断，不放宽 adopted 护栏，不用 ground truth 做 mask、crop 或布局选择。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `bubbleMaskReport.instanceCount = 8`，`maskSafeLayoutBlocks = 13`，`bboxFallbackBlocks = 0`。
- `bubbleMaskReport.inconsistentBubbleAssignmentBlocks = [4, 5, 11, 12]`，`renderMaskOverflowBlocks = []`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`；mask coverage 低的 crop 块为 `[4, 5, 9, 12]`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。

遗留事项：

- 当前 BubbleMask 是 bbox/rounded-rect 近似，不是真正 Koharu 实例分割 mask。
- mask-safe layout 改善的是覆盖布局和诊断证据，不代表 OCR 分数提升。
- 下一步应继续围绕 `bubbleID 4/6/7` 的实例分割可信度、TextRegion 检测和 crop 低 mask 覆盖块做诊断。

### v15：BubbleMask 归属修正与保守气泡拆分候选
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.5（BubbleMask归属修正与保守气泡拆分候选）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `bubbleAssignmentCorrectionReport`，逐块记录 current bubble、mask dominant bubble、coverage、修正建议、采用状态、拒绝原因和风险标记。
- 新增 `bubbleSplitCandidateReport`，只对 oversized `bubbleID 4/6/7` 生成保守 split candidate，记录 parent bubble、seed block、bbox、coverage、sibling overlap、clamp eligibility 和采用块。
- TextRegion crop clamp 顺序扩展为 split candidate、corrected bubble mask、subregion、bubble bbox、content rect；原有 adopted 护栏不放宽。
- `1_ocr_probe_text.txt` 同步输出 bubble 修正决策、split candidate、assignment/split clamp 证据和拒绝原因。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `bubbleAssignmentCorrectionReport = { evaluatedBlockCount: 13, inconsistentBlockIndexes: [4, 5, 11, 12], recommendedCorrectionBlocks: [5, 11], appliedToCropClampBlocks: [5], rejectedCorrectionBlocks: [4, 11, 12] }`。
- `bubbleSplitCandidateReport = { parentBubbleIDs: [4, 6, 7], candidateCount: 6, clampEligibleCount: 3, appliedToCropClampBlocks: [5, 9, 10] }`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。

遗留事项：

- 当前 BubbleMask 和 split candidate 仍是 bbox/rounded-rect 近似，不是真正 Koharu 实例分割。
- block 11 只推荐修正到 `bubbleID 7`，因 coverage 未达 clamp 阈值未采用；block 4/12 因保护短文本或 decorative 标题保持诊断-only。
- TextRegion crop adopted 仍为 0，下一步应继续改进真实 TextRegion/BubbleMask 检测质量，而不是放宽采用护栏。

### v16：TextBoxes 与 SegmentMask 轻量证据层
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.6（TextBoxes与SegmentMask轻量证据层）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `textBoxCandidateReport`，逐块记录 TextBox 候选来源、bbox、clamp source、padding、glyph overlap、BubbleMask coverage、safe rect overlap、证据分、是否可用于 crop 和拒绝/风险原因。
- 新增 `segmentMaskReport`，把现有 glyph mask 与 BubbleMask/safe rect/TextBox overlap 聚合成轻量 SegmentMask 诊断，标注 cleanup/crop evidence 可用块和弱证据块。
- `textRegionCropReport.diagnostics` 新增 `textBoxCandidateID`、`segmentMaskUsableForCropEvidence` 和 `failureAttribution`；报告级新增 `failureAttributionBreakdown`。
- `1_ocr_probe_text.txt` 同步输出每块 TextBox candidate、SegmentMask 和 crop failure attribution 摘要。
- TextBoxes / SegmentMask 均是传统图像处理和现有 bbox/mask 字段的轻量证据层，不是真模型；本轮不改变主输入、不放宽 TextRegion crop adopted 护栏。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `textBoxCandidateReport = { candidateCount: 13, cropEligibleCount: 6, usedForCropBlocks: [], rejectedBlocks: [2, 4, 5, 7, 9, 11, 12] }`，TextBox 候选本轮只从既有 TextRegion crop 诊断派生，没有作为上游 crop clamp 输入。
- `segmentMaskReport = { glyphMaskBlocks: 11, usableForCleanupBlocks: [0, 1, 2, 3, 6, 7, 8, 9, 10, 11], usableForCropEvidenceBlocks: [0, 1, 2, 3, 6, 7, 8, 9, 10, 11], weakSegmentBlocks: [4, 5, 12] }`。
- `failureAttributionBreakdown = { localVisionRegression: 6, rawWordsLost: 5, bubbleMaskConflict: 3, emptyLocalOCR: 3, segmentMaskWeak: 3, textBoxTooWide: 2, introducedLikelyOCRError: 2, wordCountRegression: 2, sameAsFusedText: 2, insufficientQualityGain: 2 }`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。

遗留事项：

- 本轮只输出 JSON/TXT 证据，没有新增 PNG 边框可视化；原因是现有 `1_bubble_debug.png` 生成早于 v16 的 TextBox/SegmentMask 汇总，直接改图会扩大耦合。
- 当前主要归因仍是局部 Vision OCR 退化、raw words 丢失和近似 mask 冲突；下一步应提升真实 TextRegion/BubbleMask/SegmentMask 检测质量，而不是放宽 crop 采用护栏。

### v17：TextRegion crop shadow 实验矩阵
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.7（TextRegion crop实验矩阵与候选晋级门槛）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `cropExperimentReport`，以当前 TextRegion crop 为 control，对每个 fused block 运行受控 shadow candidate 矩阵。
- 候选来源限定在现有结构证据：TextBox、SegmentMask/glyph、BubbleMask mask-safe rect、split candidate、corrected bubble 和 subregion；每块最多 control + 3 个额外候选。
- 新增逐候选 `candidateID`、`variantName`、source stack、bbox、OCR 文本、词保留率、质量分、risk flags、rejection reasons。
- 新增逐块 `bestShadowCandidate`、`promotionVerdict` 和 `stopReasons`；这些字段只做诊断，不写回 `finalTextUsedForTranslation`。
- `1_ocr_probe_text.txt` 同步输出每块 `cropExperiment` 摘要，便于直接比较 control 与 best shadow。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `cropExperimentReport = { candidateCount: 52, controlCandidateCount: 13, ocrSucceededCount: 43, betterThanControlCount: 15, promotedShadowBlocks: [], stoppedBlocks: [2, 4, 5, 6, 7, 9, 11, 12] }`。
- 每块候选数最大为 4，未出现指数级矩阵。
- variant 尝试数：`currentTextRegionCrop=13`、`textBoxTight=13`、`maskSafeRectConstrained=13`、`glyphMaskExpanded=10`、`conservativeSeedBBox=2`、`splitCandidateClamp=1`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`；TextBox `usedForCropBlocks=[]`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 融合清理 `missingKeyTexts = []`，三条保护内容仍保留。

遗留事项：

- 本轮没有 shadow candidate 达到晋级门槛，说明当前轻量候选还不足以上游化。
- `betterThanControlCount = 15` 只表示局部质量分高于 control，不表示可采用；多数候选仍有 raw words lost、local Vision regression、bubble mask conflict 或 protected diagnostic only 风险。
- 下一步应停止在 `[2, 4, 5, 6, 7, 9, 11, 12]` 继续盲目局部 crop 调参，优先补真正 TextBoxes/BubbleMask/SegmentMask 检测质量或更强 OCR。

### v18：TextRegion crop 前 TextBox plan artifact
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.8（Koharu式上游TextBoxes候选规划与shadow验证）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `preCropTextBoxPlanReport`，在 TextRegion crop OCR 之前为每个 fused block 生成 Koharu 式 TextBox plan。
- plan 来源限定在生产可用结构信号：fused seed bbox、bubble geometry、BubbleMask majority / safe rect、subRegion、split candidate、assignment correction、glyph / SegmentMask proxy。
- 每块最多保留 3 个 plan；`evidenceScore`、`eligibleForShadowOCR`、`riskFlags`、`rejectionReasons` 均为 ground-truth-free。
- `cropExperimentReport` 优先使用 `preCropTextBoxPlan.*` 变体作为 shadow OCR 来源；control 仍是当前 TextRegion crop。
- `1_ocr_probe_text.txt` 新增逐块 `preCropTextBoxPlans` 摘要，并明确 `shadowOnly=true`、`groundTruthNotUsed=true`、`notWrittenToFinalTextUsedForTranslation=true`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `AGENTS.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `preCropTextBoxPlanReport = { planCount: 37, shadowOCREligiblePlanCount: 29, selectedForShadowOCRBlocks: [0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11], stoppedBlocks: [4, 12] }`。
- `cropExperimentReport = { candidateCount: 48, controlCandidateCount: 13, ocrSucceededCount: 36, betterThanControlCount: 13, promotedShadowBlocks: [], stoppedBlocks: [2, 3, 4, 5, 7, 9, 11, 12] }`。
- `cropExperimentReport.variantBreakdown` 新增 `preCropTextBoxPlan.seedTightTextBox`、`preCropTextBoxPlan.bubbleContainedTextBox`、`preCropTextBoxPlan.maskMajorityTextBox`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`；`finalTextUsedForTranslation` 未由 plan 或 shadow OCR 写回。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容仍可信匹配：`Let's Battle!`、`What are you even talking about?`、`We need to get results...`。

遗留事项：

- `promotedShadowBlocks` 仍为空；本轮证明上游 plan artifact 可审计，但没有证明可直接替换主输入。
- 局部 Vision OCR 仍会在多个 pre-crop plan 上出现空输出、raw words lost 或质量退化；下一步应继续改善真实 TextBoxes/BubbleMask/SegmentMask 生成质量，而不是放宽 adopted 护栏。

### v19：TextBox plan 失败归因与晋级门槛审计
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.9（TextBox计划失败归因与晋级门槛收敛）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `textBoxPlanFailureReport`，把 pre-crop plan、shadow OCR candidate 和 block 级结论串成三级失败归因。
- `MangaOverlayCropExperimentCandidate` 新增 `sourcePlanID`，稳定关联 `preCropTextBoxPlanReport.plans[].planID` 和 `cropExperimentReport.candidates[]`。
- 每个 best shadow candidate 输出 ground-truth-free promotion checks，包括 OCR 成功、`wordPreservationRatio >= 0.80`、`qualityDelta > 0.08`、raw words lost、OCR 错误、same-as-fused、BubbleMask / SegmentMask 风险和 protected block。
- `1_ocr_probe_text.txt` 每块新增 `textBoxPlanFailure` 和 `promotionChecks` 摘要，直接说明为什么停止、继续几何研究或需要审计晋级门槛。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `textBoxPlanFailureReport = { evaluatedBlockCount: 13, evaluatedPlanCount: 37, evaluatedCandidateCount: 35, betterThanControlCandidateCount: 13, promotedShadowBlockCount: 0 }`。
- `stopRecommendedBlocks = [2, 3, 4, 5, 7, 9, 11, 12]`，`continueGeometryResearchBlocks = [1, 6, 10]`，`candidatePromotionBlockedBlocks = [1, 2, 4, 5, 6, 9, 10]`。
- `promotionBlockerBreakdown` 主要为 `qualityDeltaBelowOrEqual0.08: 31`、`wordPreservationRatioBelow0.80: 29`、`notBetterThanControl: 22`、`rawWordsLost: 19`、`emptyLocalOCR: 9`、`noShadowCandidate: 8`。
- `cropExperimentReport` 仍为 `48 candidates / 13 controls / 36 OCR succeeded / 13 betterThanControl / 0 promoted`；TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容仍可信匹配：`Let's Battle!`、`What are you even talking about?`、`We need to get results...`。

遗留事项：

- `betterThanControl = 13` 仍全部未晋级；主要原因是质量增益不足、词保留不足、raw words lost、空 OCR 或保护块，不是 adopted 护栏过严。
- 下一步应优先改善真实 TextBoxes / BubbleMask / SegmentMask 的几何证据，停止在已标记 stop 的块上继续盲目枚举局部 crop 变体。

### v20：行级 TextBox 与 deskew shadow 验证
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.10（Koharu式行级TextBox与deskew shadow验证）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `lineTextBoxPlanReport`，目标块动态来自 `textBoxPlanFailureReport.continueGeometryResearchBlocks`，当前为 `[1, 6, 10]`。
- 每个目标块最多生成 4 个 line-level plan，覆盖 `lineTightTextBox`、`lineBandTextBox` 和保守 `deskewProbeTextBox`；deskew 角度只作为诊断记录，不做昂贵全局搜索。
- 新增 `lineCropExperimentReport`，复用现有 TextRegion crop OCR 和 v19 promotion gate，候选变体以 `lineTextBoxPlan.*` 开头。
- `1_ocr_probe_text.txt` 为目标块输出 line-level 计划、best line candidate、promotion checks 和带原因的 `lineResearchDecision`。
- 所有 line-level 结果均为 shadow-only，不改变 `finalTextUsedForTranslation`、主覆盖图、`blockPassed`、post-fusion cleanup 或 `textRegionCropReport.adoptedCount`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `lineTextBoxPlanReport = { targetBlocks: [1, 6, 10], planCount: 12, shadowOCREligiblePlanCount: 12 }`。
- `lineCropExperimentReport = { candidateCount: 12, ocrSucceededCount: 12, betterThanControlCount: 5, promotedLineShadowBlocks: [], stoppedAfterLineResearchBlocks: [1, 6, 10] }`。
- block 1 best line candidate 为 `lineBandTextBox`，`qualityDelta = 0.095`，但 `wordPreservationRatio = 0.571`，未过 `wordPreservationRatio >= 0.80`。
- block 6 best line candidate 为 `lineTightTextBox`，`qualityDelta = -0.053`，且有 `introducedLikelyOCRError`、`notBetterThanControl` 和词保留不足。
- block 10 best line candidate 为 `lineTightTextBox`，`qualityDelta = 0.046`，低于 `qualityDelta > 0.08`，且 `wordPreservationRatio = 0.583`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`cleanTextDiagnostic.passRate = 0.4545`、`frameworkComparison.consistencyPassed = true`、`fusionComparison.consistencyPassed = true`。
- `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 仍在明细中可信匹配。

遗留事项：

- line-level / deskew shadow 对 block `[1, 6, 10]` 有 5 个 better-than-control 候选，但没有任何候选通过既有 promotion gate。
- 当前证据支持停止继续在这 3 块上堆 crop / line / deskew 变体；下一步应转向真实 TextBoxes detector、真实 BubbleMask / SegmentMask，或更强 OCR / 翻译模型质量基准。

### v21：真实 TextBoxes 与 Mask 适配前证据闸门
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.11（真实TextBoxes与Mask适配前证据闸门）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `externalArtifactReadinessReport`，覆盖真实或外部导出的 `TextBoxes`、`BubbleMask`、`SegmentMask` 三类 artifact。
- 支持读取 bundle 内 `test/koharu_artifacts/1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`，或 manifest 指定的等价路径。
- parser 校验 manifest、schema、坐标系、source image、bbox 越界、confidence 和 SegmentMask 尺寸，并把外部 TextBoxes / Bubble instances 与当前 fused blocks 做 IoU / center containment 对齐。
- `1_ocr_probe_text.txt` 顶部新增 `externalArtifactReadiness` 摘要，每块新增 `externalArtifacts` 行。
- 所有 external artifact 结果均为 shadow-only，不改变 `configuration.currentBlockSource`、`finalTextUsedForTranslation`、主覆盖图、`blockPassed`、post-fusion cleanup 或 `textRegionCropReport.adoptedCount`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- 当前仓库没有 `test/koharu_artifacts/`，因此 `externalArtifactReadinessReport = { manifestFound: false, textBoxesFound: false, bubbleMaskFound: false, segmentMaskFound: false, readinessVerdict: manifestMissing, nextAction: stopUntilArtifactsProvided, missingArtifacts: [manifest, TextBoxes, BubbleMask, SegmentMask], blockAlignmentCount: 13 }`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`frameworkComparison.consistencyPassed = true`、`fusionComparison.consistencyPassed = true`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`。
- line-level research 仍为 `targetBlocks = [1, 6, 10]`、`promotedLineShadowBlocks = []`、`stoppedAfterLineResearchBlocks = [1, 6, 10]`。

遗留事项：

- 当前正确结论是缺少真实 detector / mask artifact，下一步必须先提供或生成真实 TextBoxes / BubbleMask / SegmentMask 输出。
- 不得把 reference/koharu-main 源码存在、现有 Vision OCR blocks、pre-crop plan 或 line plan 写成“真实 detector 已接入”。
- 不应继续在 v20 已判停的 block / line / deskew crop 变体上试参。

### Agent 3：自适应 crop 与回退自测
日期：2026-06 下旬
依据提交：`da9d574`

核心变更：

- OCR 二次 crop 从固定比例扩张改为自适应 padding。
- 横排文本 y padding 大于 x padding，竖排相反。
- crop clamp 到所属气泡 bbox。
- 新增固定 crop 对照、自适应 crop 字段和人为超窄 crop 回退自测。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- build、模拟器探针、JSON 解析、`git diff --check` 通过。
- `totalBlocksDetected = 14`、`10 matched / 4 unmatched`、核心 OCR `0.6131`、装饰 `0.8000`、clean text `0.5455`。
- `cropFallbackSelfTest.triggered = true`。

遗留事项：

- 真实 `test/1.png` 未触发实际 fallback。
- 自适应 crop 有提升块也有变差块，不能按真值驱动生产选择。

### Agent 4-5：安全布局区和离屏碰撞检查
日期：2026-06 下旬
依据提交：`b65d904`

核心变更：

- 新增 `safeLayoutRect` 和 `safeLayoutSource`。
- 单块气泡使用气泡 bbox inset，多块同气泡使用分区安全区。
- 覆盖绘制前用离屏 alpha mask 检查文字越界，通过字号回退解决。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- build、完整探针、导出、JSON 解析、`git diff --check` 通过。
- `safeLayoutRectBlocks = 14`、`renderCollisionCheckedBlocks = 14`。
- `renderCollisionUnresolvedBlocks = []`、`renderTextTruncatedBlocks = []`。

遗留事项：

- 该轮改善渲染布局，不改变 OCR 准确率。

### Agent 6-7：glyph mask 和纯色背景填充
日期：2026-06 下旬
依据提交：`0ab70d0`、`08438e9`

核心变更：

- 对已归属气泡块生成轻量 glyph mask。
- mask 使用局部阈值、连通域过滤、OCR bbox 重叠约束和膨胀。
- 低纹理背景区域使用 RGB 中位数做纯色填充，高纹理或插画区域保留半透明覆盖。
- 未归属气泡块不生成 mask。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- build、完整探针、导出、JSON 解析、`git diff --check` 通过。
- `glyphMaskBlocks = 11`。
- 纯色填充触发块 `[2, 4, 6, 7]`。
- 未归属块 `5/11/13` 的 mask 为 0，符合气泡内约束。

遗留事项：

- glyph mask 和背景填充只影响覆盖可读性，不修 OCR 文本。

### Agent 8-9：tagged batch 诊断和 v5 汇总
日期：2026-06 下旬
依据提交：`6e1aa7f`、`613ca14`

核心变更：

- 新增 `batchTranslationComparison` tagged 批量翻译诊断。
- 批量分支只写报告，不替换逐块翻译、`blockPassed`、raw output 或 fallback。
- 完成 Agent 1-9 汇总，确认几何约束改善归属、裁切、渲染和跨气泡隔离。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `output/probe_report.json`

验证结果：

- batch 诊断负面：`parsedCases = 0`、`missingTags = [0...13]`、`unexpectedTags = [14...24]`。
- 逐块通过率 `0.0714`，批量通过率 `0`。
- 完整探针基线仍为 `14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`。

遗留事项：

- Gemma 270M 不适合 tagged batch 翻译主流程。
- 几何约束不能根治专有名词和 OCR 字符损坏。

### v6：确定性诊断解码和跨版本指标
日期：2026-06-27
依据提交：`d316ab2`、`metrics/version_history.csv`

核心变更：

- `LlamaRuntime` 支持按调用切换 sampled 和 deterministic 解码。
- 用户实际翻译和 summary 保持 sampled。
- raw 诊断、漫画探针、clean text、batch 和纠错翻译对照使用 deterministic，固定 `seed = 42`。
- 新增 `metrics/version_history.csv` 和 `scripts/append-version-metrics.py`。

关键文件：

- `AITRANS/Services/LlamaRuntime.swift`
- `AITRANS/Services/GemmaLocalService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `metrics/version_history.csv`
- `scripts/append-version-metrics.py`

验证结果：

- build、探针、导出、JSON 解析、`git diff --check` 通过。
- `deterministicDecodingCheck.outputsIdentical = true`。
- v6 指标：`14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`、clean text `0.4545`。

遗留事项：

- v4 缺完整逐块 OCR 快照，无法字符级回溯 `0.6196 -> 0.6131`。

### v7：底部气泡串扰诊断和保守 crop 修复
日期：2026-06-27
依据提交：`c5bd626`、`metrics/version_history.csv`

核心变更：

- 专项排查 `GET PESULTE...` 和 `What Whet...`。
- 当 OCR bbox 只覆盖合理气泡的一部分时，二次预处理 OCR 使用所属气泡 bbox 做 adaptive crop。
- 检测层 seed 分裂和小框优先实验因回归被回退。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `metrics/version_history.csv`

验证结果：

- build、完整探针、导出、JSON 解析、`git diff --check` 通过。
- 指标保持 `14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`、clean text `0.4545`。

遗留事项：

- 目标 OCR 没有实质改善。
- 后续应改气泡候选分割，而不是放宽跨气泡合并。

### v8：bubble-first 主流程切换评估
日期：2026-06-28
依据提交：`ce577b7`、`metrics/version_history.csv`

核心变更：

- 重新评估 bubble-first 能否替换整页主候选源。
- 结论是不推进架构改造，本轮只做证据收集和决策。

关键文件：

- `README.md`
- `metrics/version_history.csv`
- `output/probe_report.json`

验证结果：

- build、模拟器探针、导出、JSON 解析、`git diff --check` 通过。
- `blocksFoundByBoth = 8`。
- `blocksOnlyInWholePage = ["Let's Battle!"]`。
- `blocksOnlyInBubbleFirst = ["What are you even talking about?", "We need to get results at this tournament to save the gaming club from being disbanded."]`。
- `frameworkComparison.consistencyPassed = true`。

遗留事项：

- bubble-first 可作为未来融合候选，但不能直接独占主流程。
- 未来若推进，需要 whole-page 真实内容兜底和去重报告字段。

### v9：词表、确定性纠错和 OCR 错误结构复盘
日期：2026-06-28
依据提交：`d3080c4`、`metrics/version_history.csv`、`md/koharu研究/v6～9work.md`

核心变更：

- 复测 Vision `customWords`：开关词表最终文本无变化。
- 复盘确定性 OCR 纠错候选：只保留诊断对照，不进入主流程。
- 总结低相似和未匹配块结构，确认问题不是 `Senpai` 单点，而是专有名词和常见词混淆共同存在。

关键文件：

- `README.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `md/koharu研究/v6～9work.md`

验证结果：

- 最新指标：`totalBlocksDetected = 14`、`10 matched / 4 unmatched`、核心 OCR `0.6131`、装饰 `0.8000`、whole-page `0.6131`、bubble-first `0.7397`、clean text `0.4545`、`passedBlocks = 1`、`failedBlocks = 13`。
- `translationFailureBreakdown = { ocrInputSuspect: 10, translationLanguageQualityFailure: 3 }`。
- `likelyRuleFalseFailureBlocks = []`。

遗留事项：

- 文字区域检测和 OCR 文本质量仍是核心瓶颈。
- 下一轮优先做更强小模型对比，如 Qwen2.5-0.5B-Instruct-GGUF q4_k_m，或推进 bubble-first + whole-page 融合，而不是继续放宽质量规则。

## 历史维护记录
### 建立多 Agent 迭代文档体系
日期：2026-06-28

核心变更：

- 整合标准入口为 `AGENTS.md`，作为项目唯一核心入口文档。
- 新增 `md/prompt/README.md`、`md/test/test.md`、`md/flow/flow.md`、`md/flow/flowchart.md`。
- 根据 git 记录、README 和指标 CSV 整理本 `update_log.md`。

关键文件：

- `AGENTS.md`
- `update_log.md`
- `md/prompt/README.md`
- `md/test/test.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`

验证结果：

- 本轮为文档-only 任务，按 `md/test/test.md` 只需静态检查。

遗留事项：

- 后续每轮由 Agent A 按 `md/prompt/README.md` 的命名规则写入具体实现提示词。
