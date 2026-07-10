# 测试规范
本文指导 Agent B 和 Agent C 选择 AITRANS 的验证层级。默认云端快验、本机只做轻量检查；只有人工明确要求“本机测试 / 本地 build / 本地跑探针 / 本地 xcodebuild”时，才把本机 Xcode build 或漫画探针作为默认验证路径。

## 0. 默认验证策略
- Agent B 默认本地只跑 `git diff --check`、JSON 解析、YAML smoke 等轻量检查。
- Swift / Xcode / 漫画探针相关任务完成后，默认 push 到 `codeb/vX.Y-短标题`，由 GitHub Actions 执行快验；需要探针重验证时手动 `workflow_dispatch` 选择 `ci-fast` 或 `full`。
- Agent C 只验收与 `codeb/...` HEAD commit 完全一致的云端结果包，不只看 Agent B 的文字说明。
- 加密打包 workflow 只用于软件包交付，不作为 Agent C 验收依据；Agent C 使用独立未加密 CI 结果包。
- 如果云端验证失败，Agent C 按 `ci-failure-summary.md`、`xcodebuild.log`、`junit.xml`、`.xcresult` 和 manifest 输出退回清单，Agent B 修复后继续 push。
- 如果云端环境缺少模拟器、GGUF、App 容器权限或外部 artifact，必须说明哪个测试未运行、缺什么依赖、是否影响验收、需要人工提供什么。
- GGUF 云端模型只在手动 `ci-fast` / `full` 探针中通过 GitHub Release `model-gemma-3-270m-it-qat-q4_0-v1` 下载，并用 SHA256 `3626e245220ca4a1c5911eb4010b3ecb7bdbf5bc53c79403c21355354d1e2dc6` 校验后缓存到 `.ci-models/`；本规范不要求提交 GGUF。
- 云端漫画探针复用同一次 Debug simulator build 产物安装 App，把 `.ci-models/gemma-3-270m-it-qat-Q4_0.gguf` 复制为 App sandbox `Application Support/Models/Gemma-1.5B/model.gguf`，再用 `AITRANS_RUN_MANGA_PROBE=1` 和 `AITRANS_MANGA_PROBE_MODE` 启动 App 并导出 `output/`。`Gemma-1.5B` 是历史目录名；验收实际模型时看 asset 名、字节数和 SHA256。
- `AITRANS CI Results` 对 push 默认 `probe_mode = skip`，只跑静态检查、Xcode build、manifest 和未加密结果包，不下载 GGUF、不创建模拟器、不安装 App、不跑漫画探针。manifest 必须写 `probeSkippedReason = default_push_fast_ci_or_manual_skip` 和 `modelSetupSkippedReason = probe_mode_skip_fast_ci_does_not_need_model`。例外：只要填写 Koharu artifact archive，`probe_mode` 必须为 `ci-fast` 或 `full`，不能用 skip 验收 artifact handoff。
- `probe_mode=skip` 或云端探针失败时，CI 结果包不得复制仓库里已有的旧 `output/probe_report.json` / `clean_text_diagnostic.json` / `1_ocr_probe_text.txt` 当成本次产物；只能保留 `output/probe-not-run.txt` 和 manifest skip / failure reason。只有 `probe_mode != skip` 且 `manga_probe` 成功时才复制本轮 `output/`。
- push CI 会先做变更范围检测：非 App 构建相关变更可跳过 Xcode build，manifest 写 `xcodeBuildRequired = false` 和 `xcodeBuildSkippedReason`，结果包保留 `xcodebuild.log` skip 说明；Swift、Xcode 工程、资源、`test/` 素材、手动 `ci-fast/full` 或 Koharu artifact 注入仍必须跑 Xcode build。
- `AITRANS CI Results` checkout 至少保留最近 2 个提交，确保普通单提交 push 能 diff 到 `github.event.before`；若一次 push 含多提交导致 before commit 不在浅克隆内，workflow 必须先定向 fetch `github.event.before` 再 diff。只有 checkout 和 targeted fetch 都拿不到 before commit 时，才允许把 `changed-files.txt` 回退成全仓列表；manifest / failure summary 必须记录 `scopeDiffMethod`、`scopeDiffBaseSha` 和 `scopeDiffFallbackUsed`。
- Koharu artifact validator 的完整 invalid fixture 矩阵只在 validator、artifact contract 或 workflow 相关文件变化时跑；普通 push 保留 valid example、active allow-missing 和 required-files 核心校验。
- 手动注入 Koharu artifact archive 且运行 `ci-fast/full` 时，云端 smoke 必须核对 archive 只有一个目录同时包含四件套，并在 `ci-artifact-manifest.json` / `koharu-active-artifacts-validation.json` 中核对 `koharuArtifactValidationIdentitySummary` / `artifactIdentitySummary` 的 source image 与四件套 SHA256、size、`generatedBy`、`contractExampleOnly=false`，且 `1.manifest.json` 声明的 `sourceImageSHA256` 必须等于当前仓库 `test/1.png` 的 SHA256，validator 侧 `sourceImageSHA256Matches=true`。还必须核对 `probe_report.json` 中 App 侧 `externalArtifactReadinessReport.artifactIdentityReceipt.identityVerdict = activeArtifactIdentityRecorded`、`artifactIdentityReceipt.sourceImageSHA256Declared` / `sourceImageSHA256Expected` / `sourceImageSHA256Matches=true`、`koharuArtifactIdentityReconciliationReport.readyForCIManifestComparison = true`、`koharuArtifactIdentityReconciliationReport.sourceImageSHA256Declared` / `sourceImageSHA256Expected` / `sourceImageSHA256Matches=true`、`ci-artifact-manifest.koharuArtifactIdentityReconciliationMatch.matchVerdict = matched`、required files size / SHA256 与 CI identity 逐项匹配、`externalArtifactReadinessReport` 为 `readyForShadowOCR`、`externalTextBoxesShadowOCRAllowed = true`、`koharuNativeArtifactContractDryRunReport.contractDryRunVerdict = activeArtifactsReadyForShadowOCR`、`appSideArtifactIdentityVerdict = activeArtifactIdentityRecorded`、`appSideArtifactIdentityHashesPresent = true`、`dryRunOnly = true`、`activeExportAllowed = false`、`externalTextBoxShadowOCRReport.executed = true`、`candidateCount > 0`、`ocrExecutedCount > 0`、`ocrSucceededCount > 0`，以及 convergence 的 `WI/G-external-textbox-shadow-ocr-coverage` 已消费这些证据；不能只用 Release 下载、SHA、validator 日志或 `readyForShadowOCR` 作为 App 已消费 artifact 的证据。
- 若注入的真实 TextBox 带 `sourceDirection`、`linePolygons` 或 `rotationDegrees`，还必须核对 validator / manifest 的 `koharuArtifactValidationOrientationSummary`，以及 `externalTextBoxShadowOCRReport.orientationReadinessVerdict`、`orientationShadowPathNeededBlocks`、`orientationShadowPathExecutedBlocks`、`orientationShadowPathPartialBlocks`、`orientationShadowPathNotExecutedBlocks`、`orientationUnsupportedBlocks`、`orientationUnsupportedReasonBreakdown`、候选 `orientationAttemptedRotations`、`orientationSelectedRotation`、`orientationRecognitionLanguages`、`orientationUnsupportedReason`、`riskFlags/blockers`、`koharuArtifactConvergenceReport` 的 `WI-external-textbox-shadow-ocr-coverage` / `G-external-textbox-shadow-ocr-coverage` 和 `WI-external-textbox-orientation-shadow-path` / `G-external-textbox-orientation-shadow-path`，以及 `1_ocr_probe_text.txt` 的 coverage / orientation / app-side identity 摘要。v1.64 只支持竖排或接近 90/180/270 度 TextBox 的有上限 rotation shadow OCR；v1.69 要求 ready artifact 后有 executed shadow OCR、`candidateCount > 0`、`ocrExecutedCount > 0`、`ocrSucceededCount > 0` 且未闭合时 coverage gate 为 blocked；v1.66 要求 coverage gate 同时拿到 contract dry-run ready 与 CI identity；v1.67 要求 App 侧 runtime identity receipt 完整；line polygon warp 和任意角度 deskew 仍必须作为 unsupported / convergence blockers，阻塞相关块进入 `wouldPromoteByExistingGateBlocks` 或误判 closed。
- 需要探针验收时，手动 `workflow_dispatch` 选择 `ci-fast` 或 `full`。`ci-fast` 仍跑真实模拟器、Local GGUF、真实 `test/1.png`、deterministic 解码、主 OCR / bubble-first 融合 / 逐块翻译 / 失败块覆盖 / clean text / external artifact gate，以及 v1.18+ 必需的 report-only / detector-lite 受限 shadow 报告；只跳过明确列出的高成本对照和诊断 PNG。`ci-fast` 必须保留 `probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、`1_debug_boxes.png`、`1_translated_overlay.png`、`manga_probe_progress.json`。`full` 额外要求 contact sheet 等完整关键 PNG。
- 探针模式等待期间 `ci-fast` 每 30 秒打印 `output/manga_probe_progress.json` 和输出目录快照，1800 秒总超时、启动后 180 秒未创建 progress 提前失败、进度 300 秒不更新提前失败；`full` 为 3600 秒总超时、300 秒 no-progress 阈值、600 秒停滞阈值。失败时仍复制已有 `output/`，并在结果包保留 `manga-probe.log`、`app-console.log`、manifest 和失败摘要。

### 0.1 v1.87 UI 视觉与交互矩阵

`codeb/v1.87-enterprise-ui` 的 push CI 在 Xcode build 通过后必须运行 `scripts/capture-ui-evidence.sh`。该步骤复用当前 Debug app，不下载 GGUF、不运行漫画探针；输出 `ci-results/ui-evidence/`、`ui-evidence-manifest.json` 和 `ui-evidence.log`，manifest 的每张截图必须记录设备、方向、Dynamic Type、场景、Reduce Motion 和当前 `commitSha`。

当前最低截图矩阵为 8 张 iPhone 竖屏证据：紧凑 iPhone 的文本空态、图片空态、历史有数据、Pro 锁定；大屏 iPhone 的文本成功 XXL、键盘显示、Accessibility 失败态、Reduce Motion 音频运行。矩阵必须同时包含日间和夜间外观，manifest 记录 `appearance`；截图步骤失败必须使候选分支 CI 失败。iPad / Mac 视觉证据本轮暂缓，不得把缺失证据描述为已验证。

Agent C 逐张检查：文字和控件不重叠、不越界、不被底栏或键盘遮挡；页面没有卡片套卡片；主操作层级唯一；颜色之外仍有图标和文字状态；44pt 触控、最长状态文案、Dynamic Type 和安全区可用。Preview matrix 只用于复现状态和开发检查，不得当作当前 HEAD 运行截图。

交互回归至少覆盖：文本翻译/交换语言/目标语言/提示词；新会话与历史恢复/搜索/删除/导入/导出/清空；提示词新建/编辑/复制/删除/选择；Mock/Local、GGUF 下载/导入/移除和失败；图片导入/OCR/旁贴/覆盖/取消/重试/导出；音频导入/识别/取消/翻译/摘要；Pro 锁定/解锁/订阅校验；开发 raw probe、批量探针和漫画报告入口。

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

当前仓库没有独立 XCTest 目标作为主要验收入口。日常核心验证由 GitHub Actions 快验产出 build 结果包、日志、manifest 和失败摘要；探针 JSON/PNG artifact 只在手动 `ci-fast` / `full` 运行中要求。本地命令保留为人工要求或紧急排查路径。

## 2. 测试分层
### 2.1 Local Light / Fast
最快发现主链路断点。

触发条件：

- 非 App 构建相关修改。
- JSON、脚本、指标读取或报告字段整理。
- 不影响 Swift 编译路径的小改动。

命令：

```sh
git diff --check
python3 -m json.tool test/1.ground_truth.json
python3 -m json.tool output/probe_report.json
python3 -m json.tool output/clean_text_diagnostic.json
python3 -B scripts/test-speech-recognition-contract.py
python3 scripts/make-koharu-native-draft-artifacts.py --out build/koharu_native_draft
python3 scripts/validate-koharu-artifacts.py --root build/koharu_native_draft
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid_orientation_partial_unsupported
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/source_image_missing --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/source_image_sha_missing --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/source_image_sha_mismatch --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/contract_example_only_missing --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/contract_example_only_invalid --expect-fail
python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files
python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing
python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --emit-handoff-packet
```

`build/koharu_native_draft/` 是 `scripts/make-koharu-native-draft-artifacts.py` 生成的非 active 四件套草稿，只用于 contract shape / validator smoke。它必须保持 `contractExampleOnly=true`，validator 应输出 `verdict = contractExampleOnly`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`；不得复制到 `test/koharu_artifacts/`，不得作为真实 detector / SegmentMask / BubbleMask 验收证据。

`scripts/test-speech-recognition-contract.py` 是无设备依赖的源代码契约测试，覆盖 v1.86 状态枚举、运行摘要字段、异步 run ID 隔离、UI 取消/翻译状态和 CI 动态 bundle ID。它不能代替真机 Speech 权限、麦克风采集或识别质量测试。

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
- Speech 状态机或 bundle ID / simulator launch 工作流改变。

默认动作：

```text
Agent B push codeb/vX.Y-短标题 并创建 PR 到 smalldata_test
  -> GitHub Actions 做变更范围检测
  -> Swift / Xcode / 资源 / test 素材变化时运行 xcodebuild
  -> 非 App 构建相关变化时跳过 xcodebuild 并写明 skip reason
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

默认动作：push 先由 GitHub Actions 跑静态检查、JSON 检查、Xcode build 和结果包生成；需要探针产物时再手动 `workflow_dispatch` 运行 `ci-fast` 或 `full`。若完整漫画探针因 GitHub-hosted macOS runner、GGUF、模拟器容器或 App 沙盒访问不稳定而不能运行，workflow 必须生成失败摘要或跳过说明，不能伪造新 `output/`。

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
- v1.28 起云端 `ci-fast` 也必须产出 `koharuArtifactConvergenceReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 9`、`blockPathCount == totalBlocksDetected`、`workItemLedgerCount >= 6`、`gateCount >= 10`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`externalArtifactsRequiredForThisReport = false`。`convergenceStatusBreakdown`、`firstBlockingArtifactBreakdown`、`primaryNextActionBreakdown`、`workItemStatusBreakdown` 必须非空；`closedWorkItems` 至少包含 `WI-native-textbox-artifact-scorecard`、`WI-bubblemask-assignment-split-scorecard`、`WI-segmentmask-proxy-coverage-scorecard`；v1.29 起 `referenceReports` 必须包含 `translationModelFloorComparisonReport`，且 `WI-translation-model-floor-comparison` 不再只是 v1.28 的未执行 open 状态；v1.58 起 `workItemLedger` 必须包含 `WI-koharu-native-artifact-bundle-lite-textbox-segment-linkage` 和 `WI-koharu-native-promotion-gate-lite-textbox-segment-linkage`，`gateLedger` 必须包含 `G-koharu-convergence-bundle-lite-textbox-segment-linkage` 和 `G-koharu-convergence-promotion-lite-textbox-segment-linkage`，`stages[]` / `blockPaths[]` 必须能把 weak / fallback / rejected / wrong-bubble linkage 传播为 TextBoxes / SegmentMask 阻塞；v1.64 起 `workItemLedger` 必须包含 `WI-external-textbox-orientation-shadow-path`，`gateLedger` 必须包含 `G-external-textbox-orientation-shadow-path`，并核对 `orientationShadowPathPartialBlocks`、`orientationUnsupportedBlocks`、`orientationUnsupportedReasonBreakdown` 已进入 decision signals；partial 或 unsupported 块不得被判为 `closedReportOnly` 或 passed；v1.69 起 `workItemLedger` 必须包含 `WI-external-textbox-shadow-ocr-coverage`，`gateLedger` 必须包含 `G-external-textbox-shadow-ocr-coverage`，ready artifact 后若 shadow OCR report 缺失、`executed=false`、`candidateCount=0`、`ocrExecutedCount=0` 或 `ocrSucceededCount=0`，ExternalArtifacts stage 不得为 `nativeReady`，coverage gate status 必须为 `blocked` 而不是 warning；v1.68 起 `referenceReports` 必须包含 `koharuArtifactIdentityReconciliationReport`，`workItemLedger` 必须包含 `WI-koharu-artifact-identity-reconciliation`，`gateLedger` 必须包含 `G-koharu-artifact-identity-reconciliation-ready`，同一 coverage work item / gate 必须消费 `identityReconciliationVerdict`、`readyForCIManifestComparison` 和 App 侧 identity receipt verdict / files / hashes。v1.69 起 `G-ci-fast-report-availability` 的 threshold / decision signals 必须覆盖当前 v1.24-v1.70 convergence dependency set，并写出 `missingReportCount`、`missingReports` 和 `requiredReportSpan`，不得继续只描述 v1.24-v1.27 旧依赖。每个 `stages[]`、`blockPaths[]`、`workItemLedger[]`、`gateLedger[]` 必须保持 `groundTruthUsedForDecision = false`；`1_ocr_probe_text.txt` 必须包含报告级 `koharuArtifactConvergenceReport` summary、逐块 `koharuArtifactPath` 摘要、`convergenceBundleTextBoxSegmentLinkage`、`convergencePromotionTextBoxSegmentLinkage`、`convergenceExternalShadowOCRCoverage`、`convergenceExternalTextBoxOrientation` 和 `convergenceArtifactIdentityReconciliation`。该报告只聚合既有 DAG / stage gap / native scoreboard / TextBox / BubbleMask / SegmentMask / external gate / clean text / diagnostics / blocks，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、渲染逻辑或 `configuration.currentBlockSource`。
- v1.70 起同一 convergence 验收还必须覆盖 App/CI handoff strict closure：artifact archive 不能配 `probe_mode=skip`，coverage work item / gate ID 与 status 必须出现在 smoke 证据里，orientation work item / gate 在 partial 或 unsupported blockers 存在时不得 passed，TXT 摘要必须能让 Agent C 快速看到 coverage / orientation / App-side identity 状态。
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
- v1.39 起云端 `ci-fast` 也必须产出 `koharuNativeTextBoxDetectorLiteReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = TextBoxes.NativeDetectorLite.PreOCRArtifact`、`referenceWorkItemID = WI-koharu-native-textbox-detector-lite`、`evaluatedBlockCount == totalBlocksDetected`、`evaluatedBubbleCount > 0`、`blockLedgerCount == totalBlocksDetected`、`bubbleLedgerCount == evaluatedBubbleCount`、`candidateCount >= 1`、`gateCount >= 8`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`、`externalArtifactsRequiredForThisReport = false`。`candidateSourceBreakdown`、`candidateVerdictBreakdown`、`blockRelationBreakdown`、`primaryBottleneckBreakdown`、`nextActionBreakdown` 必须非空；candidates 必须标记 `source = nativeDetectorLite`，并记录 bbox、direction、dark pixel density、component count、projection peak、bubble coverage、glyph overlap、`relatedBlockRelations[]` 的 block index / overlap / center-contained / same-bubble / relation reason、`componentCluster` / `singleUnion` / `unionFallback` generation signal 和有上限的 per-bubble candidate pool（最多 4 个 component-cluster + 1 个 diagnostic union fallback，fallback 必须 `shadowOCREligible = false`）。每个 block ledger 必须记录 best candidate 的 coverage ratio、center-contained、same-bubble、candidate verdict 和 shadow eligibility。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeTextBoxDetectorLiteReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-textbox-detector-lite` / `G-koharu-native-textbox-detector-lite-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuNativeTextBoxDetectorLiteReport` summary、带 relation 的 `nativeTextBoxDetectorLiteCandidateLedger`、逐块 `nativeTextBoxDetectorLiteBlockLedger` 和 bubble ledger。该报告默认不执行 shadow OCR，不使用 Vision OCR 文本、ground truth、pre-crop plan、line plan 或 TextRegion crop 结果生成 / 排序候选，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。
- v1.40 起云端 `ci-fast` 也必须产出 `koharuNativeTextBoxDetectorLiteShadowOCRReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = TextBoxes.NativeDetectorLite.ShadowOCR`、`referenceWorkItemID = WI-koharu-native-textbox-detector-lite-shadow-ocr`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`selectedCandidateCount <= totalBlocksDetected`、`ocrExecutedCount == selectedCandidateCount`、`gateCount >= 9`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`、`proxyNotRealKoharuOCR = true`、`externalArtifactsRequiredForThisReport = false`。`ocrOutcomeBreakdown`、`qualityDeltaBreakdown`、`candidateSourceBreakdown`、`primaryBottleneckBreakdown`、`nextActionBreakdown` 必须非空或在无候选时明确 blocked ledger；candidates 必须标记 `source = nativeDetectorLite.shadowOCR`，只来自 v1.39 `shadowOCREligible` detector-lite bbox，并按当前 block overlap / center containment 优先，避免同 bubble sibling 共享错误高分候选；full 模式 block ledger 必须记录本块 report-only 最佳 shadow OCR 候选。`verticalCandidate` candidates 必须只做有上限的 `[0,90]` rotation shadow OCR 对照，使用 `ja-JP/ja/en-US/en` 受限 language profile，记录 `rotationApplied`，并由无真值 OCR 质量和当前文本保词率选择 report-only 最佳结果；`G-native-textbox-detector-lite-shadow-ocr-vertical-rotation-budget` 必须存在。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeTextBoxDetectorLiteShadowOCRReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-textbox-detector-lite-shadow-ocr` / `G-koharu-native-textbox-detector-lite-shadow-ocr-executed`。`1_ocr_probe_text.txt` 必须包含 report summary、`nativeTextBoxDetectorLiteShadowOCRRotation`、`nativeTextBoxDetectorLiteShadowOCRCandidate` 和逐块 `nativeTextBoxDetectorLiteShadowOCRBlockLedger`。该报告允许新增受限 Vision crop OCR 调用，不新增 LLM，不用 ground truth 决定候选、排序、OCR 执行、nextAction 或 gate，不改变主 OCR、翻译输入、覆盖图、`finalTextUsedForTranslation`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。
- v1.41 起云端 `ci-fast` 也必须产出 `koharuNativeTextBoxDetectorLiteRefinementReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = TextBoxes.NativeDetectorLite.ClosedLoopRefinement`、`referenceWorkItemID = WI-koharu-native-textbox-detector-lite-refinement`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`ocrExecutedCount <= min(6,totalBlocksDetected)` 或报告明确当前 budget、`gateCount >= 8`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`、`proxyNotRealKoharuOCR = true`、`externalArtifactsRequiredForThisReport = false`。`targetReasonBreakdown`、`refinementStrategyBreakdown`、`ocrOutcomeBreakdown`、`primaryBottleneckBreakdown`、`nextActionBreakdown` 必须非空或在无 eligible target 时明确 `blockedByNoEligibleTargets`；candidates 必须标记 `source = nativeDetectorLite.refinementShadowOCR`，refined bbox 必须从 v1.39 detector-lite 父 bbox 派生。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeTextBoxDetectorLiteRefinementReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-textbox-detector-lite-refinement` / `G-koharu-native-textbox-detector-lite-refinement-executed`。`1_ocr_probe_text.txt` 必须包含 report summary、`nativeTextBoxDetectorLiteRefinementCandidate` 和逐块 `nativeTextBoxDetectorLiteRefinementBlockLedger`。该报告允许新增受限 Vision crop OCR 调用，不新增 LLM，不用 ground truth 决定 target、bbox、排序、OCR 执行、nextAction 或 gate，不改变主 OCR、翻译输入、覆盖图、`finalTextUsedForTranslation`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。
- v1.42 起云端 `ci-fast` 也必须产出 `koharuNativeTextBoxDetectorLiteClosedLoopReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = TextBoxes.NativeDetectorLite.ClosedLoopRouter`、`referenceWorkItemID = WI-koharu-native-textbox-detector-lite-closed-loop-router`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`candidateFamilyCount == totalBlocksDetected`、`gateCount >= 8`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`、`proxyNotRealKoharuOCR = true`、`externalArtifactsRequiredForThisReport = false`。`routeBreakdown`、`candidateFamilyVerdictBreakdown`、`ocrOutcomeRollup`、`primaryBottleneckBreakdown`、`nextActionBreakdown` 必须非空，或在上游 v1.39-v1.41 报告缺失时明确 `blockedByMissingUpstreamReports`。`stopBlockIndexes`、`fullProbeReviewBlockIndexes`、`realTextBoxesNeededBlocks`、`realBubbleMaskNeededBlocks`、`realSegmentMaskNeededBlocks`、`modelFloorRoutedBlocks`、`renderLockRoutedBlocks` 字段必须存在；每个 block ledger 必须保留 `finalTextUsedForTranslation` 原值、route、nextAction、failureCategory、BubbleMask / SegmentMask / translation / render 证据、decisionSignals 和 evaluationSignals。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeTextBoxDetectorLiteClosedLoopReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-textbox-detector-lite-closed-loop-router` / `G-koharu-native-textbox-detector-lite-closed-loop-router-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuNativeTextBoxDetectorLiteClosedLoopReport` summary、`nativeTextBoxDetectorLiteCandidateFamily` 和逐块 `nativeTextBoxDetectorLiteClosedLoopBlockLedger`。该报告不新增 OCR / LLM / PNG，不使用 ground truth 决定 route、nextAction、gate 或 candidate family verdict，不改变主 OCR、翻译输入、覆盖图、`finalTextUsedForTranslation`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。
- v1.43 起云端 `ci-fast` 也必须产出 `koharuNativeBubbleMaskInstanceLiteReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = BubbleMask.NativeInstanceLite.PixelIDMask`、`referenceWorkItemID = WI-koharu-native-bubblemask-instance-lite`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`gateCount >= 8`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`nativeInstanceLite = true`、`proxyNotRealKoharuBubbleMask = true`、`usesSourceImagePixels = true`、`externalArtifactsRequiredForThisReport = false`。`instanceCount >= 1`，若像素证据不足则必须写 `instanceLiteVerdict = blockedByInsufficientPixelEvidence`，不能静默空报告；`assignmentAgreementBreakdown`、`splitRiskBreakdown`、`siblingPartitionBreakdown`、`safeRectComparisonBreakdown`、`safeRectPolicyBreakdown`、`spriteBlockScopedContainmentBreakdown`、`spriteSiblingCollisionBreakdown`、`primaryBottleneckBreakdown`、`nextActionBreakdown` 必须非空或有明确 warning / blocked gate。每个 block ledger 必须包含 current bubble、instance-lite majority、由实例像素 erosion / projection 派生的 `instanceLiteSafeRect`、实际 report-only `instanceLiteBlockScopedSafeRect`、`instanceLiteSafeRectPolicy`、`spriteBlockScopedSafeRectContainmentRatio`、`spriteContainedByBlockScopedSafeRect`、`spriteContainmentPolicy`、`sameInstanceRenderSpriteOverlapCount`、`spriteSiblingCollisionPolicy`、render lock、translation failure route、detector-lite closed-loop route 和 nextAction；同 instance 多 block 时 policy 必须避免共享同一个最大 safe rect，并输出 sibling render sprite overlap / collision policy。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeBubbleMaskInstanceLiteReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-bubblemask-instance-lite` / `G-koharu-native-bubblemask-instance-lite-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuNativeBubbleMaskInstanceLiteReport` summary、`nativeBubbleMaskInstanceLiteSafeRectPolicy`、`nativeBubbleMaskInstanceLiteBlockScopedSpriteContainment`、`nativeBubbleMaskInstanceLiteSiblingSpriteCollision`、`nativeBubbleMaskInstanceLiteInstance`、逐块 `nativeBubbleMaskInstanceLiteBlockLedger`、`nativeBubbleMaskInstanceLiteSiblingLedger` 和 `nativeBubbleMaskInstanceLiteAdjacencyLedger`。该报告不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不把 instance-lite mask 冒充真实 Koharu `BubbleMask`，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。
- v1.44 起云端 `ci-fast` 也必须产出 `koharuNativeSegmentMaskRefinementLiteReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = SegmentMask.NativeRefinementLite.TextBoxConstrainedGlyphMask`、`referenceWorkItemID = WI-koharu-native-segmentmask-refinement-lite`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`candidateLedgerCount >= totalBlocksDetected`、`gateCount >= 8`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`nativeRefinementLite = true`、`proxyNotRealKoharuSegmentMask = true`、`usesSourceImagePixels = true`、`usesTextBoxConstraints = true`、`usesBubbleMaskConstraints = true`、`externalArtifactsRequiredForThisReport = false`。若像素证据不足必须写 `refinementLiteVerdict = blockedByInsufficientPixelEvidence`，不能静默空报告；`candidateSourceBreakdown`、`candidateVerdictBreakdown`、`pixelEvidenceBreakdown`、`textboxClampBreakdown`、`textBoxSegmentLinkBreakdown`、`bubbleClampBreakdown`、`componentFilteringBreakdown`、`maskContainmentBreakdown`、`maskMajorityAgreementBreakdown`、`primaryBottleneckBreakdown`、`nextActionBreakdown` 必须非空或有明确 warning / blocked gate。每个 candidate ledger 必须包含 source TextBox candidate verdict、shadow eligibility、block overlap ratio、same-bubble、accepted-for-SegmentMask 和 link verdict；每个 block ledger 必须包含 selected candidate、selected source TextBox candidate ID / link verdict、pixel counts、TextBox / BubbleMask clamp、`maskContainedByTextBoxRatio`、`maskContainedByBubbleRatio`、`maskMajorityAgreement`、glyph overlap、SegmentMask proxy agreement、clear-text / OCR crop / render containment 可用性、primary bottleneck 和 nextAction。报告必须输出 `segmentFromAcceptedTextBoxCount`、`segmentFromRejectedTextBoxCount`、`segmentFromFallbackBBoxCount`，并包含 `G-native-segmentmask-refinement-lite-textbox-linkage-audited` 和 `G-native-segmentmask-refinement-lite-no-rejected-textbox-silent-selection` gates。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeSegmentMaskRefinementLiteReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-segmentmask-refinement-lite` / `G-koharu-native-segmentmask-refinement-lite-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuNativeSegmentMaskRefinementLiteReport` summary、`nativeSegmentMaskRefinementLiteTextBoxLink`、`nativeSegmentMaskRefinementLiteMajorityAgreement`、`nativeSegmentMaskRefinementLiteCandidate`、逐块 `nativeSegmentMaskRefinementLiteBlockLedger` 和 `nativeSegmentMaskRefinementLiteSiblingLedger`。该报告不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不把 refinement-lite mask 冒充真实 Koharu `SegmentMask`，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。
- v1.45 起云端 `ci-fast` 也必须产出 `koharuNativeArtifactBundleLiteReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = ArtifactBundle.NativeLite.TextBoxesBubbleMaskSegmentMaskConsistency`、`referenceWorkItemID = WI-koharu-native-artifact-bundle-lite`、`evaluatedBlockCount == totalBlocksDetected`、`bundleLedgerCount == totalBlocksDetected`、`consistencyEdgeCount >= totalBlocksDetected`、`workItemCount >= 1`、`gateCount >= 8`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`nativeBundleLite = true`、`proxyNotRealKoharuTextBoxes = true`、`proxyNotRealKoharuBubbleMask = true`、`proxyNotRealKoharuSegmentMask = true`、`externalArtifactsRequiredForThisReport = false`。每个 final block 必须有 bundle ledger，至少包含 selected TextBox / Bubble / Segment component、OCR evidence、translation route、render evidence、artifact consistency verdict、primary blocking artifact 和 nextAction；v1.57 起每块 ledger 还必须包含 `selectedTextBoxSegmentLinkVerdict`、`textBoxSegmentLinkageStatus`、`textBoxSegmentLinkageRisk`，consistency edges 必须包含 `TextBoxSegmentMaskLinkage`，报告必须包含 `textBoxSegmentLinkBreakdown` 和 `textBoxSegmentLinkageReviewBlocks`。consistency edges 必须覆盖 TextBox/Bubble、Segment/TextBox、Segment/Bubble、final OCR bbox/TextBox、same-bubble sibling non-overlap、seam/split risk、render sprite containment、model-floor separation 和 TextBox -> SegmentMask linkage。`componentReadinessBreakdown`、`artifactConsistencyBreakdown`、`textBoxSegmentLinkBreakdown`、`primaryBlockingArtifactBreakdown`、`nextActionBreakdown` 必须非空或有明确 warning / blocked gate。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeArtifactBundleLiteReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-artifact-bundle-lite` / `G-koharu-native-artifact-bundle-lite-executed`；v1.57 起还必须包含 `WI-koharu-native-artifact-bundle-lite-textbox-segment-linkage` / `G-native-artifact-bundle-lite-textbox-segment-linkage`。`1_ocr_probe_text.txt` 必须包含 report summary、`nativeArtifactBundleLiteTextBoxSegmentLink`、逐块 `nativeArtifactBundleLiteBlockLedger` 的 `textBoxSegmentLink=`、`nativeArtifactBundleLiteConsistencyEdge` 和 `nativeArtifactBundleLiteWorkItem`。该报告不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不把 bundle-lite 冒充真实 Koharu artifacts，不改变主 OCR、翻译输入、覆盖图、renderer、`blockPassed`、失败分类、`safeLayoutRect`、`glyphMaskFillRects`、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。
- v1.46 起云端 `ci-fast` 也必须产出 `koharuNativePromotionGateLiteReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = NativePromotionGateLite.ProbeDrivenArtifactReadiness`、`referenceWorkItemID = WI-koharu-native-promotion-gate-lite`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`stageGateCount >= 8`、`candidateExportPreviewCount >= 1` 或明确 blocked / warning reason、`workItemCount >= 1`、`gateCount >= 8`、`promotionGateLite = true`、`nativePromotionPreviewOnly = true`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`externalArtifactsRequiredForThisReport = false`、`proxyNotRealKoharuTextBoxes = true`、`proxyNotRealKoharuBubbleMask = true`、`proxyNotRealKoharuSegmentMask = true`、`proxyNotRealKoharuOCR = true`、`proxyNotRealKoharuRenderer = true`。每个 final block 必须有 promotion ledger，至少包含 TextBoxes / BubbleMask / SegmentMask / OcrText / Translations / Render promotion status、primary blocking artifact、probe bottleneck、promotion eligibility、nextAction 和 `mustNotPromoteReasons`；v1.57 起每块 ledger 还必须包含 `textBoxSegmentLinkVerdict` 和 `textBoxSegmentLinkagePromotionStatus`，报告必须包含 `textBoxSegmentLinkBreakdown` 和 `textBoxSegmentLinkageBlockedBlocks`，weak / fallback / rejected / wrong-bubble linkage 必须进入 `mustNotPromoteReasons`。`stageGates[]` 必须覆盖 TextBoxes、BubbleMask、SegmentMask、OcrText、Translations、RenderedSprites、FinalRender、ExternalArtifacts；`candidateExportPreviews[]` 必须保持 `canBeExportedNow = false`、`wouldCreateActiveArtifact = false`。`stageReadinessBreakdown`、`promotionEligibilityBreakdown`、`primaryBlockingArtifactBreakdown`、`probeBottleneckBreakdown`、`textBoxSegmentLinkBreakdown`、`nextActionBreakdown` 必须非空或有明确 warning / blocked gate。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativePromotionGateLiteReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-promotion-gate-lite` / `G-koharu-native-promotion-gate-lite-executed`；v1.57 起还必须包含 `WI-koharu-native-promotion-gate-lite-textbox-segment-linkage` / `G-native-promotion-gate-lite-textbox-segment-linkage`。`1_ocr_probe_text.txt` 必须包含 report summary、`nativePromotionTextBoxSegmentLink`、`nativePromotionStageGate`、逐块 `nativePromotionBlockLedger` 的 `textBoxSegmentLink=`、`nativeCandidateExportPreview` 和 `nativePromotionWorkItem`。该报告不新增 OCR / LLM / PNG，不更换模型，不创建或修改 active `test/koharu_artifacts/`，不把 native-lite proxy 冒充真实 Koharu promotion / detector / artifact，不改变主 OCR、翻译输入、覆盖图、renderer、`blockPassed`、失败分类、`safeLayoutRect`、`glyphMaskFillRects`、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals。
- v1.47 起云端 `ci-fast` 也必须产出 `koharuNativeArtifactContractDryRunReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = NativeArtifactContractDryRun.FourFileReadiness`、`referenceWorkItemID = WI-koharu-native-artifact-contract-dry-run`、`sourceImage = test/1.png`、`coordinateSpace = originalImageTopLeftPixels`、`activeInputDirectory = test/koharu_artifacts`、`examplesDirectory = md/koharu研究/artifact_contract/examples`、`evaluatedBlockCount == totalBlocksDetected`、`requiredFileCount >= 4`、`contractGateCount >= 6`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`dryRunOnly = true`、`activeExportAllowed = false`、`externalArtifactsRequiredForThisReport = false`。`requiredFiles[]` 必须覆盖 `1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`，且 manifest required fields 必须包含 `sourceImageSHA256=<expected runtime test/1.png sha256>`；v1.67 起每个 required file 还必须写出 `identityStatus`，有 active 文件时写出 `fileSizeBytes` 和 `sha256`，顶层必须写 `appSideArtifactIdentityVerdict`、`appSideArtifactIdentityFilesPresent`、`appSideArtifactIdentityHashesPresent`；v1.80 起 App-side identity ready 还必须要求 `externalArtifactReadinessReport.artifactIdentityReceipt.sourceImageSHA256Matches = true`。真实 artifact ready 后 `contractDryRunVerdict = activeArtifactsReadyForShadowOCR` 必须要求 App 侧 identity ready。`validatorCommands[]` 必须包含 `scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --print-required-files` 和 `--allow-missing`；`forbiddenActiveSources[]` 必须包含 contract examples、Vision OCR blocks、pre-crop plan、line plan、BubbleMask proxy、SegmentMask proxy、ground truth、handwritten ideal boxes。`previews[]` 必须保持 `activeExportAllowed = false`、`wouldCreateActiveArtifact = false`，并写出 required / missing fields 与 forbidden source reasons。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeArtifactContractDryRunReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-artifact-contract-dry-run` / `G-koharu-native-artifact-contract-dry-run-executed`；缺 active 四件套时该 work item 应为 `blockedByMissingRealArtifact`，禁止把 proxy preview 当成真实 artifact readiness。`1_ocr_probe_text.txt` 必须包含 `koharuNativeArtifactContractDryRunReport` summary、App-side identity summary、`nativeArtifactContractDryRunRequiredFile` 的 size / SHA、`nativeArtifactContractDryRunPreview`、validator commands 和 forbidden active sources。该报告只做四件套 contract dry-run，不创建、复制、修改 active `test/koharu_artifacts/`，不新增 OCR / LLM / PNG，不改变主 OCR、翻译输入、覆盖图、renderer、`blockPassed`、失败分类、`safeLayoutRect`、`glyphMaskFillRects`、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。
- v1.68 起云端 `ci-fast` 也必须产出 `koharuArtifactIdentityReconciliationReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = ArtifactIdentityReconciliation.CIManifestAppReceipt`、`referenceWorkItemID = WI-koharu-artifact-identity-reconciliation`、`evaluatedBlockCount == totalBlocksDetected`、`fileRowCount >= 5`、`gateCount >= 3`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`dryRunOnly = true`、`activeExportAllowed = false`、`externalArtifactsRequiredForThisReport = false`。`fileRows[]` 必须覆盖 `SourceImage`、`manifest`、`TextBoxes`、`BubbleMask`、`SegmentMask`，每行必须包含 App size / SHA256、`ciManifestFieldPathForSize`、`ciManifestFieldPathForSHA256` 和 `comparisonStatus`；v1.80 起顶层还必须包含 `sourceImageSHA256Declared`、`sourceImageSHA256Expected`、`sourceImageSHA256Matches`，真实 artifact ready 后 `readyForCIManifestComparison = true` 必须要求每行 `comparisonStatus = appReceiptReady` 且 `sourceImageSHA256Matches = true`。`koharuArtifactConvergenceReport.referenceReports` 必须包含该报告，`workItemLedger` / `gateLedger` 必须包含 `WI-koharu-artifact-identity-reconciliation` / `G-koharu-artifact-identity-reconciliation-ready`；`1_ocr_probe_text.txt` 必须包含 `koharuArtifactIdentityReconciliationReport`、逐行 `artifactIdentityReconciliationFile`、source image SHA declared / expected / matches 和 `convergenceArtifactIdentityReconciliation`。Actions 注入真实 artifact 后还必须在 `ci-artifact-manifest.json` 写出 `koharuArtifactIdentityReconciliationMatch.matchVerdict = matched`，否则不得把 artifact handoff 当作通过。该报告不读取 CI manifest、不创建或修改 active artifact、不新增 OCR / LLM / PNG、不改变主 OCR、翻译输入、覆盖图或 renderer。
- 若 post-fusion cleanup 新增拒绝块，`fusionComparison.postFusionCleanup.rejectedBlocks[]` 必须写出 ground-truth-free 的 `reason`、`relatedKeptBlockIndex`、`qualityScore`、`protectedTextMatched` 和 `evidence`；保护文本与 decorative 标题不能被清理掉。
- 外部 Koharu artifact validator 对 `md/koharu研究/artifact_contract/examples/valid` 应返回 `validationPassed = true`、`verdict = contractExampleOnly`、`externalTextBoxesShadowOCRAllowed = false`，且 `artifactIdentitySummary.sourceImageSHA256Declared` 等于 `artifactIdentitySummary.sourceImage.sha256`、`sourceImageSHA256Matches = true`；对 `examples/valid_orientation_partial_unsupported` 还必须输出 `orientationMetadataSummary`，其中 `orientationPartialTextBoxIDs` 包含合法竖排 + line polygon fixture，`orientationUnsupportedReasonBreakdown` 包含 `linePolygonWarpUnsupported` 和 `arbitraryRotationUnsupported`；对 invalid fixtures 应在 `--expect-fail` 下成功，至少覆盖 coordinate mismatch、invalid bbox、missing textboxes、schema mismatch、manifest path escape、forbidden `generatedBy` source、TextBox 方向元数据非法、manifest 缺 `sourceImage`、manifest 缺 / 错 `sourceImageSHA256` 和 manifest 缺 `contractExampleOnly`。v1.79 起 active manifest 缺 `sourceImageSHA256` 必须输出 `sourceImageSHA256Missing`，SHA 格式非法输出 `sourceImageSHA256Invalid`，与当前仓库 `test/1.png` 不一致输出 `sourceImageSHA256Mismatch`，并阻止 `readyForShadowOCR`；v1.80 起 Swift readiness、App identity receipt 和 identity reconciliation 也必须输出同等 missing / invalid / mismatch 阻塞，不能只由 Python validator 拦截。v1.81 起 `--emit-handoff-packet` 必须输出 Release upload / `workflow_dispatch` 输入，`--package-release-archive` 生成的 zip 必须只有一个目录且包含四个标准 JSON，并输出 archive SHA256；默认不得把 `contractExampleOnly` examples 标记为 handoff ready，云端 static checks 也必须覆盖 fixture 默认拒绝打包、允许 fixture 打包后的 zip 布局和带空格 dispatch 参数 shell quote。v1.82 起 `--inspect-release-archive` 必须按 CI 同口径拒绝 0 个或多个四件套 candidate directory 的 archive，成功时输出 archive size/SHA、members、candidate directory 和 validation verdict；handoff packet 必须输出带 `--repo` 的 `ghReleaseUploadCommand`、`ghWorkflowDispatchCommand` 和 `ghRunListCommand`。v1.83 起 `--package-release-archive` 的 handoff packet 还必须包含 `releaseArchive.inspection`、`releaseArchiveInspectionPassed`、`releaseArchiveInspectionVerdict`、`inspectReleaseArchiveCommand` 和 `expectedCIManifestEcho`，static checks 必须断言 fixture package 的 inspection proof 存在且 candidate directory count 为 1；v1.84 起 handoff packet 还必须包含 `ghRunWatchCommand`、`ghRunDownloadCommand`、`ciResultReview`、`expectedCIManifestAssertions`、`expectedAppRuntimeAssertions`、`expectedReconciliationAssertions`、`expectedExternalShadowOCRAssertions`、`expectedConvergenceAssertions`、`expectedCloudIdentityRows`、`expectedProbeTextNeedles` 和 `staleRunRejectionAssertions`，static checks 只断言这些结构化 review 字段的 shape 和关键路径存在，不增加真实 GitHub 下载或 App 探针负载；云端注入真实 archive 时仍以 Release 下载 SHA、唯一目录解包、active validator identity / orientation 摘要、App runtime readiness、identity reconciliation、external shadow OCR coverage 和 orientation gates 为验收证据。v1.69 起 active manifest 缺 `sourceImage` 必须输出 `sourceImageMissing`，缺或非布尔 `contractExampleOnly` 必须输出 source policy 错误并阻止 `readyForShadowOCR`。TextBox 可选 `sourceDirection`、`rotationDegrees` / `rotationDeg`、`linePolygons` 一旦提供，validator 和 Swift readiness 必须校验方向枚举、旋转范围和 line polygon 点位范围；`--print-required-files` 应输出 active 目录四件套和 forbidden active sources；对缺失的 `test/koharu_artifacts` 应在 `--allow-missing` 下返回 `manifestMissing`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided` 和缺失文件 blockers，不应额外混入 schema / coordinate 缺失噪音。
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

- `.xcresult`：当 `xcodeBuildRequired = true` 时必须包含 Xcode 结果包，例如 `TestResults/AITRANS-${version}-${short_sha}.xcresult`；文档 / 元数据快路径允许缺省，但必须在 manifest 写明 skip reason。
- `junit.xml`：CI 可读摘要。当前没有 XCTest 时，至少生成 build smoke 的 JUnit 摘要。
- `xcodebuild.log`：完整构建日志；build-skip 快路径时该文件保留 skip 说明。
- `ci-artifact-manifest.json`：结果包索引，包含 `version`、`branch`、`commitSha`、`runId`、`runAttempt`、`workflowName`、`createdAt`、`xcodeVersion`、`scheme`、`destination`、`resultBundlePath`、`junitPath`、`xcodebuildLogPath`、`failureSummaryPath`、`probeReportPath`。v1.14 起还包含 `koharuActiveArtifactValidationPath`、`koharuArtifactValidation`、`externalArtifactReadinessSummary` 和 `externalTextBoxShadowOCRSummary`，用于区分缺 artifact 阻塞路径和 ready/executed=true 路径；v1.65 起还包含 `koharuArtifactValidationOrientationSummary`，`externalTextBoxShadowOCRSummary` 透传 orientation 与 coverage 相关字段；v1.66 起还必须包含 `koharuArtifactValidationIdentitySummary`、App 侧 identity receipt / reconciliation summary 和 `koharuArtifactIdentityReconciliationMatch`；v1.69 起 ready artifact 的 shadow OCR coverage 还必须核对 `ocrExecutedCount > 0`、`ocrSucceededCount > 0`，并在 convergence report 的 report availability gate 里保留 `missingReportCount`、`missingReports` 和 `requiredReportSpan`；v1.72 起还包含 `koharuNativeArtifactContractDryRunSummary` 和 `koharuArtifactConvergenceGateSummary`，直接汇总 contract dry-run、coverage/orientation work item、gate status、blocks 和 `G-ci-fast-report-availability` decision signals；v1.74 起还包含 `koharuNativeLiteReportSummary` 与 `koharuNativeLiteConvergenceGateSummary`，直接汇总 v1.39-v1.46 detector-lite、shadow OCR、refinement、closed-loop、instance-lite、SegmentMask refinement-lite、bundle-lite 和 promotion gate-lite 的 verdict、counts、work item / gate status、blocks 和 nextAction；v1.77 起还包含 `artifactName`、`eventName`、`repository`、`ref`、`refName`、`runUrl`、`changedFilesCount`、`changedFilesSHA256` 和 `changedFiles`，用于 Agent C 直接核对结果包来源、GitHub run URL 和本次变更范围；v1.78 起还包含 `scopeDiffMethod`、`scopeDiffBaseSha` 和 `scopeDiffFallbackUsed`，用于判断 changed-files 是 checkout diff、targeted fetch diff 还是全仓 fallback；v1.79 起 `koharuArtifactValidationIdentitySummary` 还必须透传 manifest 声明的 `sourceImageSHA256Declared`、实际 `sourceImageSHA256Expected` 和 `sourceImageSHA256Matches`；v1.80 起 App receipt summary 和 `koharuArtifactIdentityReconciliationSummary` 也必须透传 source image SHA declared / expected / matches。
- v1.70 起 artifact requested 的云端结果还必须证明 `probe_mode != skip`，smoke 已硬核对 coverage work item / gate ID 与 status、orientation work item / gate ID 与 status、coverage gate passed、orientation blockers 存在时不得 passed，且 `1_ocr_probe_text.txt` 包含 coverage / orientation / App-side identity 摘要。
- `xcodeBuildRequired` / `xcodeBuildSkippedReason`：仅文档 / 元数据快路径允许 `xcodeBuildRequired = false`；Agent C 必须把它视作“未提供 Swift/Xcode 编译证据”，不能用于验收代码改动。
- `ci-failure-summary.md`：无论成功或失败都生成；失败时写清失败阶段、关键日志位置、建议 Agent B 先看哪些文件。
- `model-download.log` / `model-verify.log`：仅 `ci-fast` / `full` 探针模式要求，记录 Release 下载、cache 命中和 SHA256 校验；`probe_mode=skip` 必须在 manifest 写 `modelSetupSkippedReason`。
- `simulator-build.log` / `manga-probe.log`：仅 `ci-fast` / `full` 探针模式要求，记录 Debug simulator app 复用、安装、模型导入、探针启动、报告等待和导出；`probe_mode=skip` 必须保留 `probe-not-run.txt` 或 manifest skip reason。
- 若运行漫画探针：上传 `output/probe_report.json`、`output/clean_text_diagnostic.json`、`output/1_ocr_probe_text.txt` 和关键 PNG。

artifact 命名建议：

```text
aitrans-ci-${version}-${branch_slug}-${short_sha}-run${run_id}-attempt${run_attempt}
```

Agent C 取用规则：

- 只看当前 `codeb/...` HEAD 对应的 `commitSha`。
- 必须核对 manifest 的 `branch`、`commitSha`、`runId`、`runAttempt`。
- 涉及 external artifact 时，必须核对 manifest 内 `koharuArtifactValidation.verdict`、`koharuArtifactValidationIdentitySummary`、`koharuArtifactValidationOrientationSummary`、`externalArtifactReadinessSummary.readinessVerdict`、App 侧 identity receipt / reconciliation summary、`koharuArtifactIdentityReconciliationMatch.matchVerdict` 和 `externalTextBoxShadowOCRSummary.executed/candidateCount/ocrExecutedCount/ocrSucceededCount`，并确认这些值来自当前 `commitSha` 的结果包。
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
- 非 App 构建相关修改可只跑 `git diff --check` 和必要 JSON/YAML smoke，但要说明未跑 build 和探针的原因。
- 未经人工明确要求，不因为 Swift 代码变化就在本机默认跑 Xcode build 或完整漫画探针。
- 漫画探针或翻译链路修改后，最终回复必须汇总关键数字。
- 如果 clean text 仍失败，优先讨论模型质量，不要继续盲目调 OCR 或放宽规则。
