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
- v1.26 起云端 `ci-fast` 也必须产出 `bubbleMaskAssignmentSplitScoreboardReport`；`enabled = true`、`source = AITRANSProbe`、`referenceWorkItemID = WI-bubblemask-assignment-split-scorecard`、`referenceKoharuArtifact = BubbleMask`、`evaluatedBlockCount == totalBlocksDetected`、`evaluatedBubbleCount == bubbleMaskReport.instanceCount`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`。`blockScorecards.count == totalBlocksDetected`，`bubbleScorecards.count == bubbleMaskReport.instanceCount`，`splitCandidateLedgers.count == bubbleSplitCandidateReport.candidateCount`，`gateLedger.count >= 10`，`assignmentStatusBreakdown`、`splitRiskBreakdown`、`siblingLayoutStatusBreakdown`、`renderMaskStatusBreakdown`、`nextActionBreakdown` 必须非空；`conflictBlocks` 应覆盖 `bubbleMaskReport.inconsistentBubbleAssignmentBlocks`，除非上游为空；每个 block scorecard 必须保持 `groundTruthUsedForDecision = false`、`diagnosticOnly = true`、`wouldChangeMainFlow = false`；`1_ocr_probe_text.txt` 必须包含报告级 `bubbleMaskAssignmentSplitScoreboardReport` summary 和逐块 `bubbleMaskScoreboard` 摘要。该报告只聚合现有 BubbleMask proxy / assignment / split / sibling layout / render / Native TextBox ledger 证据，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect` 或 `configuration.currentBlockSource`。
- v1.27 起云端 `ci-fast` 也必须产出 `segmentMaskProxyCoverageScoreboardReport`；`enabled = true`、`source = AITRANSProbe`、`referenceWorkItemID = WI-segmentmask-proxy-coverage-scorecard`、`referenceKoharuArtifact = SegmentMask`、`evaluatedBlockCount == totalBlocksDetected`、`glyphMaskBlockCount == segmentMaskReport.glyphMaskBlocks`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealSegmentMask = true`。`blockScorecards.count == totalBlocksDetected`，`cleanupLedgerCount >= glyphMaskBlockCount`，`gateLedger.count >= 12`，`coverageStatusBreakdown`、`cleanupStatusBreakdown`、`renderMaskStatusBreakdown`、`backgroundFillStatusBreakdown`、`nextActionBreakdown` 必须非空；`usableForCleanupBlocks` / `usableForCropEvidenceBlocks` / `weakSegmentBlocks` 应覆盖 `segmentMaskReport` 对应列表，除非上游为空。每个 block scorecard 必须保持 `groundTruthUsedForDecision = false`、`diagnosticOnly = true`、`wouldChangeMainFlow = false`；`1_ocr_probe_text.txt` 必须包含报告级 `segmentMaskProxyCoverageScoreboardReport` summary 和逐块 `segmentMaskProxyScoreboard` 摘要。该报告只聚合现有 glyph mask / SegmentMask proxy / TextBox / BubbleMask / background fill / render 证据，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为或 `configuration.currentBlockSource`。
- v1.28 起云端 `ci-fast` 也必须产出 `koharuArtifactConvergenceReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 9`、`blockPathCount == totalBlocksDetected`、`workItemLedgerCount >= 6`、`gateCount >= 10`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`externalArtifactsRequiredForThisReport = false`。`convergenceStatusBreakdown`、`firstBlockingArtifactBreakdown`、`primaryNextActionBreakdown`、`workItemStatusBreakdown` 必须非空；`closedWorkItems` 至少包含 `WI-native-textbox-artifact-scorecard`、`WI-bubblemask-assignment-split-scorecard`、`WI-segmentmask-proxy-coverage-scorecard`；v1.29 起 `referenceReports` 必须包含 `translationModelFloorComparisonReport`，且 `WI-translation-model-floor-comparison` 不再只是 v1.28 的未执行 open 状态。每个 `stages[]`、`blockPaths[]`、`workItemLedger[]`、`gateLedger[]` 必须保持 `groundTruthUsedForDecision = false`；`1_ocr_probe_text.txt` 必须包含报告级 `koharuArtifactConvergenceReport` summary 和逐块 `koharuArtifactPath` 摘要。该报告只聚合既有 DAG / stage gap / native scoreboard / TextBox / BubbleMask / SegmentMask / external gate / clean text / diagnostics / blocks，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、渲染逻辑或 `configuration.currentBlockSource`。
- v1.29 起云端 `ci-fast` 也必须产出 `translationModelFloorComparisonReport`；`enabled = true`、`source = AITRANSProbe`、`referenceWorkItemID = WI-translation-model-floor-comparison`、`evaluatedCleanCaseCount == cleanTextDiagnostic.totalCases`、`evaluatedNoisyBlockCount == totalBlocksDetected`、`baselinePassRate == cleanTextDiagnostic.passRate`、`variantPassRate` 和 `passRateDelta` 可解析、`floorVerdict` 非空、`floorVerdictBreakdown`、`promptVariantOutcomeBreakdown`、`failureReasonBreakdown` 非空、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`cleanTextGroundTruthUsedForModelFloorOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`。`cleanCases.count == cleanTextDiagnostic.totalCases`、`noisyBlockSummaries.count == totalBlocksDetected`、每个 clean case / noisy summary 的 `groundTruthUsedForDecision = false`、`gateLedger.count >= 9`；`1_ocr_probe_text.txt` 必须包含报告级 `translationModelFloorComparisonReport` summary、`translationFloorCleanCase` 和逐块 `translationFloorNoisyBlock` 摘要。该报告允许新增 deterministic strict clean text LLM 诊断调用，但不得替换主 prompt、主译文、覆盖图、`blockPassed`、失败分类、质量规则或模型。
- v1.30 起云端 `ci-fast` 也必须产出 `koharuRenderRegressionLockReport`；`enabled = true`、`source = AITRANSProbe`、`referenceWorkItemID = WI-render-regression-lock`、`referencePipeline = Koharu`、`evaluatedBlockCount == totalBlocksDetected`、`renderLockVerdict` 非空、`renderLockVerdictBreakdown`、`renderStatusBreakdown`、`safeLayoutSourceBreakdown`、`outputFileStatusBreakdown` 非空、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuRenderer = true`。`blockLocks.count == totalBlocksDetected`、`artifactStages.count >= 5`、`gateLedger.count >= 13`、`outputFileChecks` 覆盖 `probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、`1_debug_boxes.png`、`1_translated_overlay.png`；`failureOverlayRequiredBlocks` 必须覆盖所有 `blockPassed = false` 的块。v1.30 起 `koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuRenderRegressionLockReport`，且 `WI-render-regression-lock` 不再只是 v1.28 的未执行 open 状态；`1_ocr_probe_text.txt` 必须包含报告级 `koharuRenderRegressionLockReport` summary、逐块 `renderLock` 摘要和 convergence render work item 摘要。该报告只聚合现有渲染和输出证据，不新增 OCR / LLM，不改 renderer、safe layout、glyph mask、背景填充、主 OCR、主翻译、`blockPassed` 或失败分类。Agent C 还必须直接核对未加密结果包里的 `output/1_debug_boxes.png` 和 `output/1_translated_overlay.png` 非空。
- v1.31 起云端 `ci-fast` 也必须产出 `koharuPipelineResolverReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = EngineInfo.needsProduces.DAGResolver.OpPreview`、`evaluatedBlockCount == totalBlocksDetected`、`nodeCount >= 12`、`edgeCount >= 12`、`blockTraceCount == totalBlocksDetected`、`executionQueueCount >= 6`、`opPreviewCount >= 4`、`gateCount >= 8`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`。`nodes[]` 必须包含 `sourceImage`、`contentCrop`、`visionOCRCandidates`、`bubbleCandidates`、`bubbleMaskProxy`、`textBoxProxy`、`segmentMaskProxy`、`ocrText`、`fusionCleanup`、`translations`、`renderedSpritesProxy`、`finalRender`、`externalArtifacts`；`nodeStatusBreakdown`、`artifactAvailabilityBreakdown`、`firstBlockedNodeBreakdown`、`executionItemStatusBreakdown`、`nextActionBreakdown` 必须非空。缺 active `test/koharu_artifacts/` 时，`externalArtifacts` 节点必须保持 missing / blocked，不能把 proxy 冒充真实 artifact；`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuPipelineResolverReport`，并且 `workItemLedger` 或 `gateLedger` 必须包含 `WI-koharu-pipeline-resolver-shadow-dag` / `G-koharu-pipeline-resolver-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuPipelineResolverReport` summary、`resolverExecutionQueue` 摘要和逐块 `koharuPipelineResolverTrace`。该报告只聚合现有报告，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择或渲染行为。
- v1.32 起云端 `ci-fast` 也必须产出 `koharuWorkOrderRouterReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = ResolverExecutionQueue.WorkOrderRouter.BudgetGate`、`evaluatedBlockCount == totalBlocksDetected`、`workOrderCount >= 7`、`blockRouteCount == totalBlocksDetected`、`gateCount >= 10`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`externalArtifactsRequiredForThisReport = false`。`workOrderStatusBreakdown`、`workOrderPriorityBreakdown`、`targetStageBreakdown`、`nextActionBreakdown`、`budgetClassBreakdown` 必须非空；`budgetLedger.ciFastRunnableWorkOrderIDs.count >= 1`；缺 active `test/koharu_artifacts/` 时，external artifact work orders 必须保持 `blockedMissingExternalArtifact` 或等价阻塞状态，不能把 proxy 变成真实 artifact ready。`WO-v132-stop-local-crop-line-deskew`、`WO-v132-request-real-textboxes`、`WO-v132-external-artifact-package-handoff` 必须存在；`WO-v132-stop-local-crop-line-deskew` 不得建议继续 crop / line / deskew 调参。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuWorkOrderRouterReport`，并且 `workItemLedger` 或 `gateLedger` 必须包含 `WI-koharu-workorder-router` / `G-koharu-workorder-router-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuWorkOrderRouterReport` summary、`workOrderQueue` 和逐块 `koharuWorkOrderRoute`。该报告只聚合现有报告，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择或渲染行为。
- v1.33 起云端 `ci-fast` 也必须产出 `koharuExternalArtifactRequestPacketReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = ExternalArtifacts.ContractReadiness.RequestPacket`、`evaluatedBlockCount == totalBlocksDetected`、`requiredFileCount >= 4`、`artifactRequirementCount >= 3`、`blockRequestCount == totalBlocksDetected`、`gateCount >= 13`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`externalArtifactsRequiredForThisReport = false`。`requiredFiles[]` 必须覆盖 `test/koharu_artifacts/1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`；`artifactRequirements[]` 必须覆盖 `TextBoxes`、`BubbleMask`、`SegmentMask`；缺 active artifact 时 `requestPacketVerdict` 必须是 missing / waiting / blocked 类状态，不能 ready；`forbiddenActiveSources` 必须包含 contract examples、Vision OCR blocks、pre-crop plan、line plan、BubbleMask proxy、SegmentMask proxy、ground truth 和 handwritten ideal boxes 或等价项。`blockRequests.count == totalBlocksDetected`，每块要有 primary work order、needs artifact flags、stoplist / model floor / render lock 信号。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuExternalArtifactRequestPacketReport`，并且 `workItemLedger` 或 `gateLedger` 必须包含 `WI-koharu-external-artifact-request-packet` / `G-koharu-external-artifact-request-packet-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuExternalArtifactRequestPacketReport` summary、`requiredFiles`、`artifactRequirements` 和逐块 `koharuExternalArtifactRequest`。该报告只聚合现有报告，不新增 OCR / LLM，不创建、复制、修改或提交 active `test/koharu_artifacts/`，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充或渲染行为。
- v1.34 起云端 `ci-fast` 也必须产出 `koharuNativeAlgorithmReplayMatrixReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = NativeAlgorithmReplayMatrix.ProbeEvidenceBudgetGate`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 10`、`candidateCount >= 9`、`blockRouteCount == totalBlocksDetected`、`gateCount >= 14`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`externalArtifactsRequiredForThisReport = false`。固定 candidates 必须包含 `C-v134-preserve-fused-mainflow-audit`、`C-v134-stop-local-crop-line-deskew`、`C-v134-textbox-proxy-replay-ledger`、`C-v134-bubblemask-assignment-split-replay`、`C-v134-segmentmask-coverage-replay`、`C-v134-ocr-quality-bottleneck-replay`、`C-v134-translation-floor-replay`、`C-v134-render-lock-replay`、`C-v134-external-artifact-handoff-replay`。缺 active artifact 时 external candidate 必须保持 blocked；crop / line / deskew stoplist 必须继续阻止本地调参；model floor、OCR 输入问题和 render lock 必须分开路由。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeAlgorithmReplayMatrixReport`，并且 `workItemLedger` 或 `gateLedger` 必须包含 `WI-koharu-native-algorithm-replay-matrix` / `G-koharu-native-algorithm-replay-matrix-executed`。`1_ocr_probe_text.txt` 必须包含 report summary、`candidateQueue`、`stageMatrix` 和逐块 `koharuNativeReplayRoute`。该报告只聚合现有报告，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充、active artifacts 或 `configuration.currentBlockSource`。
- v1.35 起云端 `ci-fast` 也必须产出 `koharuBubbleIndexShadowLedgerReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = BubbleIndex.MajorityMaskSafeAreaSiblingPartition`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`evaluatedBubbleCount == bubbleMaskReport.instanceCount`、`bubbleLedgerCount == bubbleMaskReport.instanceCount`、`gateCount >= 12`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealBubbleMask = true`、`externalArtifactsRequiredForThisReport = false`。`assignmentVerdictBreakdown`、`safeAreaVerdictBreakdown`、`siblingPartitionVerdictBreakdown`、`renderLockVerdictBreakdown`、`bubbleLayoutVerdictBreakdown`、`nextActionBreakdown` 必须非空；每个 block ledger 必须保持 `groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`，并写出当前 `bubbleID`、shadow bubble、assignment、safe-area、sibling partition、render lock 和 next action。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuBubbleIndexShadowLedgerReport`，并且 `workItemLedger` 或 `gateLedger` 必须包含 `WI-koharu-bubble-index-shadow-ledger` / `G-koharu-bubble-index-shadow-ledger-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuBubbleIndexShadowLedgerReport` summary、`bubbleIndexBubbleLedger`、`bubbleIndexSiblingLedger` 和逐块 `koharuBubbleIndexBlockLedger`。该报告只聚合现有报告，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`blockPassed`、失败分类、post-fusion cleanup、候选选择、glyph mask、背景填充、active artifacts 或 `configuration.currentBlockSource`。
- v1.36 起云端 `ci-fast` 也必须产出 `koharuDistanceFieldSafeAreaReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = BubbleIndex.DistanceFieldSafePixels.MaximumSafeRect`、`evaluatedBlockCount == totalBlocksDetected`、`bubbleLedgerCount == bubbleMaskReport.instanceCount`、`blockLedgerCount == totalBlocksDetected`、`gateCount >= 10`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`、`externalArtifactsRequiredForThisReport = false`。`safePixelVerdictBreakdown`、`safeRectComparisonBreakdown`、`spriteContainmentBreakdown`、`nextActionBreakdown` 必须非空；每个 block ledger 必须包含当前 `safeLayoutRect`、v1.35 `bubbleIndexShadowSafeRect`、distance-field safe rect 或明确 fallback source、sprite containment、render lock 和 report-only next action。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuDistanceFieldSafeAreaReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-distance-field-safe-area` / `G-koharu-distance-field-safe-area-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuDistanceFieldSafeAreaReport` summary、`distanceFieldBubbleLedger`、逐块 `distanceFieldBlockLedger` 和 `distanceFieldSiblingLedger`。该报告只在 rounded-rect proxy ID mask 的 bubble bbox 内计算 distance field / safe pixels / maximum safe rect，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`。
- v1.37 起云端 `ci-fast` 也必须产出 `koharuBubbleAdjacencySeamReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = BubbleMask.InstanceAdjacency.SeamPartition`、`evaluatedBlockCount == totalBlocksDetected`、`evaluatedBubbleCount == bubbleMaskReport.instanceCount`、`blockLedgerCount == totalBlocksDetected`、`pairLedgerCount >= 1`、`seamCandidateCount >= bubbleSplitCandidateReport.candidateCount`（若上游为空，必须有明确 warning / fallback note）、`gateCount >= 10`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`、`externalArtifactsRequiredForThisReport = false`。`pairVerdictBreakdown`、`seamCandidateVerdictBreakdown`、`blockSeamRiskBreakdown`、`nextActionBreakdown` 必须非空；block ledgers 必须覆盖 assignment conflict、same-bubble sibling、split candidate、needs real BubbleMask 和 render lock 信号。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuBubbleAdjacencySeamReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-bubble-adjacency-seam` / `G-koharu-bubble-adjacency-seam-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuBubbleAdjacencySeamReport` summary、`bubbleAdjacencyPair`、`bubbleSeamCandidate` 和逐块 `bubbleSeamBlockLedger`。该报告只聚合现有 proxy / BubbleIndex / DistanceField / split / sibling / OCR damage / render lock 证据，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`。
- v1.38 起云端 `ci-fast` 也必须产出 `koharuRenderSpriteFitPlannerReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = RenderedSprites.FontSizeSearch.SpriteFitBudget`、`referenceWorkItemID = WI-koharu-render-sprite-fit-planner`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`layoutCandidateCount >= totalBlocksDetected`、`gateCount >= 10`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuRenderer = true`、`proxyNotRealBubbleMask = true`、`externalArtifactsRequiredForThisReport = false`。`fitVerdictBreakdown`、`fontBudgetBreakdown`、`spriteContainmentBreakdown`、`failureOverlayFitBreakdown`、`nextActionBreakdown` 必须非空；block ledgers 必须覆盖当前 safe rect、DistanceField safe rect、BubbleIndex shadow safe rect、render font / sprite bounds、failure overlay fit、seam / sibling / render lock 信号。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuRenderSpriteFitPlannerReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-render-sprite-fit-planner` / `G-koharu-render-sprite-fit-planner-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuRenderSpriteFitPlannerReport` summary、逐块 `renderSpriteFit`、`renderSpriteLayoutCandidate` 和 `renderSpriteSiblingFit`。该报告只聚合现有 render / BubbleIndex / DistanceField / seam 证据，不新增 OCR / LLM，不重新渲染 PNG，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`renderFontSize`、`renderNonTransparentBounds`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`。
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
