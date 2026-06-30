# 测试规范
本文指导 Agent B 和 Agent C 选择 AITRANS 的验证层级。默认云端重验证，本机只做轻量检查；只有人工明确要求“本机测试 / 本地 build / 本地跑探针 / 本地 xcodebuild”时，才把本机 Xcode build 或漫画探针作为默认验证路径。

## 0. 默认验证策略
- Agent B 默认本地只跑 `git diff --check`、JSON 解析、YAML smoke 等轻量检查。
- Swift / Xcode / 漫画探针相关任务完成后，默认 push 到 `codeb/vX.Y-短标题`，由 GitHub Actions 执行重验证。
- Agent C 只验收与 `codeb/...` HEAD commit 完全一致的云端结果包，不只看 Agent B 的文字说明。
- 加密打包 workflow 只用于软件包交付，不作为 Agent C 验收依据；Agent C 使用独立未加密 CI 结果包。
- 如果云端验证失败，Agent C 按 `ci-failure-summary.md`、`xcodebuild.log`、`junit.xml`、`.xcresult` 和 manifest 输出退回清单，Agent B 修复后继续 push。
- 如果云端环境缺少模拟器、GGUF、App 容器权限或外部 artifact，必须说明哪个测试未运行、缺什么依赖、是否影响验收、需要人工提供什么。
- GGUF 云端模型通过 GitHub Release `model-gemma-3-270m-it-qat-q4_0-v1` 下载，并用 SHA256 `3626e245220ca4a1c5911eb4010b3ecb7bdbf5bc53c79403c21355354d1e2dc6` 校验后缓存到 `.ci-models/`；本规范不要求提交 GGUF。
- 云端漫画探针复用同一次 Debug simulator build 产物安装 App，把 `.ci-models/gemma-3-270m-it-qat-Q4_0.gguf` 复制为 App sandbox `Application Support/Models/Gemma-1.5B/model.gguf`，再用 `AITRANS_RUN_MANGA_PROBE=1` 和 `AITRANS_MANGA_PROBE_MODE` 启动 App 并导出 `output/`。`Gemma-1.5B` 是历史目录名；验收实际模型时看 asset 名、字节数和 SHA256。
- `AITRANS CI Results` 默认 `probe_mode = ci-fast`，手动 `workflow_dispatch` 可选 `full` 或 `skip`。`ci-fast` 仍跑真实模拟器、Local GGUF、真实 `test/1.png`、deterministic 解码、主 OCR / bubble-first 融合 / 逐块翻译 / 失败块覆盖 / clean text / external artifact gate；跳过 shadow-only 对照和诊断 PNG。`ci-fast` 必须保留 `probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、`1_debug_boxes.png`、`1_translated_overlay.png`、`manga_probe_progress.json`。`full` 额外要求 contact sheet 等完整关键 PNG。`skip` 只能用于文档-only 或人工明确跳过，manifest 必须写 `probeSkippedReason`。
- 等待期间 `ci-fast` 每 30 秒打印 `output/manga_probe_progress.json` 和输出目录快照，1800 秒总超时、进度 300 秒不更新提前失败；`full` 为 3600 秒总超时、600 秒停滞阈值。失败时仍复制已有 `output/`，并在结果包保留 `manga-probe.log`、`app-console.log`、manifest 和失败摘要。

## 1. 固定前缀 / 环境要求
人工明确要求本机命令行构建时，固定使用完整 Xcode：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

常用构建命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

漫画探针运行依赖：

- `test/1.png` 已打入 App bundle。
- `test/1.ground_truth.json` 可解析。
- Local 模式需要沙盒内存在 GGUF 模型，默认内置下载模型只适合接口冒烟。
- 导出模拟器 App 容器通常需要读取 CoreSimulator 容器，受限环境下要请求批准。

当前仓库没有独立 XCTest 目标作为主要验收入口。日常核心验证由 GitHub Actions 产出 build 结果包、日志、JSON/PNG artifact 和失败摘要；本地命令保留为人工要求或紧急排查路径。

## 2. 测试分层
### 2.1 Local Light / Fast
最快发现主链路断点。

触发条件：

- 文档-only 修改。
- JSON、脚本、指标读取或报告字段整理。
- 不影响 Swift 编译路径的小改动。

命令：

```sh
git diff --check
python3 -m json.tool test/1.ground_truth.json
python3 -m json.tool output/probe_report.json
python3 -m json.tool output/clean_text_diagnostic.json
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail
python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --print-required-files
python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing
```

当前基线：

- `output/probe_report.json` 可解析。
- `output/clean_text_diagnostic.json` 可解析。
- `test/1.ground_truth.json` 可解析。
- 最新 `configuration.currentBlockSource = fusedWholePageBubble`。
- 最新 `totalBlocksDetected = 13`，`frameworkComparison.consistencyPassed = true`，`fusionComparison.consistencyPassed = true`。

### 2.2 Cloud Smoke
验证主要集成路径，默认在 GitHub Actions 运行。

触发条件：

- Swift 代码或 Xcode 工程文件改变。
- `TranslationSessionStore`、模型接口、OCR 服务、SwiftUI 入口或 Info.plist 改变。
- 需要确认 target 能编译。

默认动作：

```text
Agent B push codeb/vX.Y-短标题 并创建 PR 到 smalldata_test
  -> GitHub Actions 运行 xcodebuild
  -> 上传未加密 CI 结果包
  -> Agent C 按 manifest 核对分支、commitSha、runId、runAttempt
  -> Agent C 通过 PR merge 后删除远端 codeb/... 候选分支
```

云端最低命令等价于：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

当前基线：

- 近期多轮该 build 通过。
- 构建日志可能出现 CoreSimulator 沙盒警告，只要最终 `BUILD SUCCEEDED` 即可作为 build 通过。

### 2.3 Stage Regression
覆盖当前阶段核心模块。

触发条件：

- 修改漫画探针、OCR 合并、覆盖绘制、报告模型、clean text diagnostic、translation quality gate、Local/Mock 模型适配。
- 修改会影响 `probe_report.json` 结构或 `output/` 产物。

默认动作：优先由 GitHub Actions 运行能稳定执行的 build、JSON 检查、报告解析和探针产物收集。若完整漫画探针因 GitHub-hosted macOS runner、GGUF、模拟器容器或 App 沙盒访问不稳定而不能运行，workflow 必须生成失败摘要或跳过说明，不能伪造新 `output/`。

人工明确要求本机运行时命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

运行 App 内开发页 `运行漫画覆盖翻译探针`，或用 DEBUG 环境变量触发：

```sh
AITRANS_RUN_MANGA_PROBE=1
```

导出输出：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/export-probe-output.sh booted
```

检查报告：

```sh
python3 -m json.tool output/probe_report.json
python3 -m json.tool output/clean_text_diagnostic.json
python3 -m json.tool test/1.ground_truth.json
```

当前基线：

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
- `fusion.fused.accuracyVsGroundTruth = 0.7384`
- `frameworkComparison.consistencyPassed = true`
- `fusionComparison.consistencyPassed = true`
- `textRegionCropReport.totalRegions = 13`
- `textRegionCropReport.cropSucceededCount = 10`
- `textRegionCropReport.adoptedCount = 0`
- `textRegionCropReport.rejectedCount = 13`
- `bubbleSubRegionReport.totalSubRegions = 11`
- `bubbleSubRegionReport.clampEligibleCount = 2`
- `bubbleSubRegionReport.oversizedBubbleIDs = [4, 6, 7]`
- `textRegionCropReport.clampSources = { bubbleBBox: 9, contentRect: 2, subRegion: 2 }`
- `subRegion` clamp 实际用于块 `[6, 8]`
- `bubbleMaskReport.instanceCount = 8`
- `bubbleMaskReport.maskSafeLayoutBlocks = 13`
- `bubbleMaskReport.bboxFallbackBlocks = 0`
- `bubbleMaskReport.inconsistentBubbleAssignmentBlocks = [4, 5, 11, 12]`
- `bubbleMaskReport.renderMaskOverflowBlocks = []`
- `cropMaskCoverage` 低的块 `[4, 5, 9, 12]`
- `bubbleAssignmentCorrectionReport.recommendedCorrectionBlocks = [5, 11]`
- `bubbleAssignmentCorrectionReport.appliedToCropClampBlocks = [5]`
- `bubbleAssignmentCorrectionReport.rejectedCorrectionBlocks = [4, 11, 12]`
- `bubbleSplitCandidateReport.parentBubbleIDs = [4, 6, 7]`
- `bubbleSplitCandidateReport.candidateCount = 6`
- `bubbleSplitCandidateReport.clampEligibleCount = 3`
- `bubbleSplitCandidateReport.appliedToCropClampBlocks = [5, 9, 10]`
- `textBoxCandidateReport.usedForCropBlocks = []`
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
- `cropExperimentReport` 每块候选数最大为 4，即 control + 最多 3 个 shadow 候选；v18 shadow 候选优先来自 `preCropTextBoxPlan.*`
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
- 默认缺 active artifact 时，`externalTextBoxShadowOCRReport.executed = false`、`gateVerdict = manifestMissing`、`candidateCount = 0`、`ocrExecutedCount = 0`、`promotedExternalShadowBlocks = []`、`skippedBlocks = [0...12]`。
- 若真实 `test/koharu_artifacts/` readiness 通过，`externalTextBoxShadowOCRReport` 每块最多生成 1 个 `externalArtifact.textBoxCrop` candidate；选择和 report-only promotion 不能读取 `test/1.ground_truth.json`，且不得改变 `finalTextUsedForTranslation`、主覆盖图、`blockPassed`、`configuration.currentBlockSource` 或 `textRegionCropReport.adoptedCount`。
- v1.18 起云端 `ci-fast` 也必须产出 `internalStructureBottleneckReport`；`evaluatedBlockCount` 必须等于 `totalBlocksDetected`，`primaryBottleneckBreakdown` 和 `recommendedActionBreakdown` 必须非空，`1_ocr_probe_text.txt` 必须包含 `internalStructureBottleneck` 逐块摘要。
- v1.19 起云端 `ci-fast` 也必须产出 `routingDrivenTranslationComparisonReport` 和 `ocrCharacterDamageAuditReport`；前者 `enabled = true`、`evaluatedCaseCount <= 5`，target 只能来自 `modelTranslationQuality` 路由块，后者 `enabled = true`、`evaluatedBlockCount > 0`，并写出 damaged / missing / extra / substitution token 证据。`1_ocr_probe_text.txt` 必须包含两个新报告的逐块摘要。
- v1.20 起云端 `ci-fast` 也必须产出 `readingOrderStructureAuditReport`；`enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`cases.count == totalBlocksDetected`，`recommendedStructureActionBreakdown`、`bubbleAssignmentRiskBreakdown`、`textBoxEvidenceBreakdown`、`segmentMaskEvidenceBreakdown` 必须非空。`1_ocr_probe_text.txt` 必须包含报告级 `readingOrderStructureAuditReport` summary 和每块 `readingOrderStructureAudit` 摘要；该报告不得改变 `blocks` 顺序、`finalTextUsedForTranslation`、主覆盖图、`blockPassed` 或失败分类。
- v1.21 起云端 `ci-fast` 也必须产出 `structureActionCandidateReport`；`enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`candidateCount >= 1`，`candidateTypeBreakdown`、`promotionVerdictBreakdown`、`recommendedNextStepBreakdown` 必须非空。每个 candidate 必须保持 `diagnosticOnly = true`、`groundTruthUsedForPlanning = false`、`wouldChangeMainFlow = false`；`1_ocr_probe_text.txt` 必须包含报告级 `structureActionCandidateReport` summary 和每块 `structureActionCandidates` 摘要。该报告只复用已有 shadow / geometry / render 证据，不新增昂贵 OCR / LLM，不改变 `blocks` 顺序、`finalTextUsedForTranslation`、主覆盖图、`blockPassed`、失败分类或 post-fusion cleanup。
- v1.22 起云端 `ci-fast` 也必须产出 `koharuArtifactDAGReport`；`enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 8`、`edgeCount >= 8`，`stageStatusBreakdown`、`artifactKindBreakdown`、`firstBlockingStageBreakdown`、`downstreamImpactBreakdown` 必须非空。每个 `dependencyEdges[]` 必须保持 `diagnosticOnly = true`、`wouldChangeMainFlow = false`；每个 `blockTraces[]` 必须含关键阶段 trace，至少覆盖 `bubbleMask`、`textBoxes`、`segmentMask`、`ocrText`、`translation`、`renderLayout` 中 4 个。`1_ocr_probe_text.txt` 必须包含报告级 `koharuArtifactDAGReport` summary 和逐块 `koharuArtifactTrace` 摘要；该报告只复用既有证据，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- v1.23 起云端 `ci-fast` 也必须产出 `koharuStageGapReplicationReport`；`enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`canonicalStageCount >= 9`、`workPackageCount >= 1`，`stageCapabilityBreakdown`、`gapCategoryBreakdown`、`replicationReadinessBreakdown` 必须非空。每个 `stageGaps[]` 必须保持 `diagnosticOnly = true`、`wouldChangeMainFlow = false`、`groundTruthUsedForPlanning = false`；每个 promotion gate 的 `groundTruthUsedForDecision = false`；`workPackages[]` 至少包含一个 `requiresRealExternalArtifact = true` 的包；`blockPlans.count == totalBlocksDetected` 且含 `firstBlockingStageFromDAG`、`primaryGapCategory`、`recommendedWorkPackageID`、`nextAction`。`1_ocr_probe_text.txt` 必须包含报告级 `koharuStageGapReplicationReport` summary 和逐块 `koharuStageGapPlan` 摘要；该报告只把 v1.22 DAG 和既有诊断转成复刻计划，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- v1.24 起云端 `ci-fast` 也必须产出 `koharuNativeReplicationScoreboardReport`；`enabled = true`、`source = AITRANSProbe`、`evaluatedBlockCount == totalBlocksDetected`、`stageScorecardCount >= 9`、`gateCount >= 8`、`workItemCount >= 1`，`externalArtifactsRequiredForThisReport = false`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`。`stageStatusBreakdown`、`gateStatusBreakdown`、`blockPrimaryBottleneckBreakdown`、`recommendedPriorityBreakdown` 必须非空；每个 `stageScorecards[]` 必须保持 `diagnosticOnly = true`、`wouldChangeMainFlow = false`、`groundTruthUsedForDecision = false`；每个 `gateLedger[]` 的 `groundTruthUsedForDecision = false`；`blockScorecards.count == totalBlocksDetected` 且每块包含 `primaryNativeStage`、`primaryBottleneck`、`recommendedPriority`、`priorityUsedGroundTruth = false`、`recommendedWorkItemID`、`nextAction`；`recommendedNextWorkItems[]` 至少包含 `P0` 或 `stop` 的 stoplist / native scoreboard 工作项。`1_ocr_probe_text.txt` 必须包含报告级 `koharuNativeReplicationScoreboardReport` summary 和逐块 `koharuNativeBlockScorecard` 摘要。该报告只复用现有 probe 证据，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择；缺真实 artifact 只能记为 optional external path，不阻塞 native scoreboard。
- v1.25 起云端 `ci-fast` 也必须产出 `nativeTextBoxProxyLedgerReport`；`enabled = true`、`source = AITRANSProbe`、`referenceWorkItemID = WI-native-textbox-artifact-scorecard`、`evaluatedBlockCount == totalBlocksDetected`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`。`blockLedgers.count == totalBlocksDetected`，`gateLedger.count >= 10`，`qualityStatusBreakdown`、`candidateSourceBreakdown`、`freezeReasonBreakdown`、`nextActionBreakdown` 必须非空；`stoplist[]` 应覆盖 `textBoxPlanFailureReport.stopRecommendedBlocks` 和 `lineCropExperimentReport.stoppedAfterLineResearchBlocks` 的并集，除非上游报告为空。每个 block ledger 必须保持 `groundTruthUsedForDecision = false`、`diagnosticOnly = true`、`wouldChangeMainFlow = false`；`1_ocr_probe_text.txt` 必须包含报告级 `nativeTextBoxProxyLedgerReport` summary 和逐块 `nativeTextBoxProxyLedger` 摘要。该报告只聚合现有 TextBox / crop / line / BubbleMask / SegmentMask / OCR damage / scoreboard 证据，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- 若 post-fusion cleanup 新增拒绝块，`fusionComparison.postFusionCleanup.rejectedBlocks[]` 必须写出 ground-truth-free 的 `reason`、`relatedKeptBlockIndex`、`qualityScore`、`protectedTextMatched` 和 `evidence`；保护文本与 decorative 标题不能被清理掉。
- 外部 Koharu artifact validator 对 `md/koharu研究/artifact_contract/examples/valid` 应返回 `validationPassed = true`、`verdict = contractExampleOnly`、`externalTextBoxesShadowOCRAllowed = false`；对 invalid fixtures 应在 `--expect-fail` 下成功；`--print-required-files` 应输出 active 目录四件套和 forbidden active sources；对缺失的 `test/koharu_artifacts` 应在 `--allow-missing` 下返回 `manifestMissing`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided` 和缺失文件 blockers。
- `1_ocr_probe_text.txt` 每块包含 `textBoxPlanFailure` 和 `promotionChecks`；目标块 `[1, 6, 10]` 还包含 `lineTextBoxPlans`、`lineCropExperiment`、`linePromotionChecks` 和 `lineResearchDecision`；每块还包含 `externalArtifacts` 与 `externalTextBoxShadowOCR` 摘要。
- `cleanTextDiagnostic.passRate = 0.4545`
- `passedBlocks = 1`
- `failedBlocks = 12`
- `translationFailureBreakdown = { modelOutputFailure: 2, ocrInputSuspect: 7, translationLanguageQualityFailure: 3 }`
- `likelyRuleFalseFailureBlocks = []`

### 2.4 Full
全量验证。

触发条件：

- 修改 llama.cpp 封装、模型下载/导入、Xcode framework、bundle resource、持久化迁移、Pro 权限或发布相关配置。
- 版本收尾或准备提交时需要高置信度。

默认动作：由 GitHub Actions 负责 build/test/report/artifact 重验证。人工明确要求本机全量时命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .derivedDataDevice \
  CODE_SIGNING_ALLOWED=NO build
```

然后运行 Stage Regression 的完整漫画探针、导出和 JSON 检查。

当前基线：

- generic iOS Simulator build 近期通过。
- generic iOS device build 在 README 当前验证中记录通过。
- Debug iOS Simulator app bundle 曾确认内嵌 `llama.framework`。

## 3. 云端结果包要求
Agent B 的云端结果必须可下载、可追溯、未加密，供 Agent C 验收。最低内容：

- `.xcresult`：Xcode 结果包，例如 `TestResults/AITRANS-${version}-${short_sha}.xcresult`。
- `junit.xml`：CI 可读摘要。当前没有 XCTest 时，至少生成 build smoke 的 JUnit 摘要。
- `xcodebuild.log`：完整构建日志。
- `ci-artifact-manifest.json`：结果包索引，包含 `version`、`branch`、`commitSha`、`runId`、`runAttempt`、`workflowName`、`createdAt`、`xcodeVersion`、`scheme`、`destination`、`resultBundlePath`、`junitPath`、`xcodebuildLogPath`、`failureSummaryPath`、`probeReportPath`。v1.14 起还包含 `koharuActiveArtifactValidationPath`、`koharuArtifactValidation`、`externalArtifactReadinessSummary` 和 `externalTextBoxShadowOCRSummary`，用于区分缺 artifact 阻塞路径和 ready/executed=true 路径。
- `ci-failure-summary.md`：无论成功或失败都生成；失败时写清失败阶段、关键日志位置、建议 Agent B 先看哪些文件。
- `model-download.log` / `model-verify.log`：Release 下载、cache 命中和 SHA256 校验记录。
- `simulator-build.log` / `manga-probe.log`：Debug simulator app 构建、安装、模型导入、探针启动、报告等待和导出日志。
- 若运行漫画探针：上传 `output/probe_report.json`、`output/clean_text_diagnostic.json`、`output/1_ocr_probe_text.txt` 和关键 PNG。

artifact 命名建议：

```text
aitrans-ci-${version}-${branch_slug}-${short_sha}-run${run_id}-attempt${run_attempt}
```

Agent C 取用规则：

- 只看当前 `codeb/...` HEAD 对应的 `commitSha`。
- 必须核对 manifest 的 `branch`、`commitSha`、`runId`、`runAttempt`。
- 涉及 external artifact 时，必须核对 manifest 内 `koharuArtifactValidation.verdict`、`externalArtifactReadinessSummary.readinessVerdict`、`externalTextBoxShadowOCRSummary.executed`，并确认这些值来自当前 `commitSha` 的结果包。
- B 再次 push 后，旧 run 结果废弃。
- Actions 重跑时，记录实际验收的 `runAttempt`。
- C 验收通过后默认通过 PR merge 收口，并删除远端 `codeb/...` 候选分支；无权限删除时必须说明。

## 4. 静态检查
常用命令：

```sh
git diff --check
plutil -lint AITRANS/Resources/Info.plist AITRANS.xcodeproj/project.pbxproj
python3 -m json.tool test/1.ground_truth.json
python3 -m json.tool output/probe_report.json
python3 -m json.tool output/clean_text_diagnostic.json
```

版本指标追加：

```sh
python3 scripts/append-version-metrics.py --version vN --notes "简短说明"
```

## 5. 规则
- 每次实现前先读本文件。
- 默认从本地轻量检查开始，重负载验证交给 GitHub Actions。
- 不得伪造测试结果。
- 未跑测试必须说明原因。
- 文档-only 修改可只跑 `git diff --check` 和必要 JSON/YAML smoke，但要说明未跑 build 和探针的原因。
- 未经人工明确要求，不因为 Swift 代码变化就在本机默认跑 Xcode build 或完整漫画探针。
- 漫画探针或翻译链路修改后，最终回复必须汇总关键数字。
- 如果 clean text 仍失败，优先讨论模型质量，不要继续盲目调 OCR 或放宽规则。
