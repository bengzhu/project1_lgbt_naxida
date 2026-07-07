# 项目版本更新记录
本文记录 AITRANS 的正式版本、重要维护事项、关键决策和遗留问题。README 不再写更新记录；细节证据优先看本日志、`metrics/version_history.csv`、最新 `output/` 和 git 提交。

## 维护规则
- 每完成一个正式版本或重要任务后追加记录。
- 记录必须包含：版本或任务名、日期、核心变更、关键文件、验证结果、遗留事项。
- 文档整理、目录迁移、回滚、打捞等不伪装成新版本，写入“历史维护记录”。
- 若核心逻辑、测试规范或项目行为变化，必须同步更新本日志、`md/flow/flow.md`、`md/flow/flowchart.md` 或 `md/test/test.md`。
- 涉及漫画探针或翻译链路的可量化版本时，`metrics/version_history.csv` 必须 append-only 更新；README 不再追加近期记录。

## 当前漫画指标基线
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
- v1.13 新增 `externalTextBoxShadowOCRReport` 后，云端 run `28381772143` 已验证默认缺 active artifact 时 `executed = false`、`gateVerdict = manifestMissing`、`candidateCount = 0`、`ocrExecutedCount = 0`、`promotedExternalShadowBlocks = []`、`skippedBlocks = [0...12]`。
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
- v1.13 新增 external TextBoxes shadow OCR 接入口，完全由 `externalArtifactReadinessReport.externalTextBoxesShadowOCRAllowed` 门控；ready 前只写阻塞报告，ready 后每块最多 1 个 `externalArtifact.textBoxCrop` 候选，只进 JSON / TXT，不替换主 OCR、翻译、覆盖或通过判定。
- Vision `customWords` 对当前图最终合并文本无变化，`changedBlockIndexes = []`。
- 确定性 OCR 纠错能提升部分相似度，但翻译收益不稳定，仍只做探针对照。
- tagged batch 翻译分支格式崩坏，不替换逐块翻译。

## 历史记录
### v1.85：Koharu Native Draft Artifact Tool
日期：2026-07-07

依据：v1.84 已把真实 Koharu handoff 后的 CI 结果核对清单补齐，但本地仍缺一个低风险工具，把 AITRANS 当前 probe block / bubble / glyph-mask proxy 以四件套 contract 形状导出，供外部 detector / handoff 开发快速对齐字段。该工具必须保持非 active、非真实 detector 输出，避免把 proxy 冒充为 `test/koharu_artifacts/`。

核心变更：

- 新增 `scripts/make-koharu-native-draft-artifacts.py`，从 `output/probe_report.json` 生成 `build/koharu_native_draft/1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`。
- draft manifest 固定 `contractExampleOnly=true`，记录当前 `test/1.png` SHA256、生成来源、TextBox / Bubble / SegmentMask 来源和 count；当前旧 probe_report 缺 detector-lite 字段时，TextBoxes / BubbleMask 会从最终 probe blocks fallback 生成。
- 生成的草稿目录只用于 contract shape / validator smoke，validator 正确结果是 `verdict = contractExampleOnly`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`，不得复制到 active `test/koharu_artifacts/`。
- artifact contract README 和测试规范同步该工具的用途、命令和禁止项。

关键文件：

- `scripts/make-koharu-native-draft-artifacts.py`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`python3 -B -m py_compile scripts/make-koharu-native-draft-artifacts.py`、`python3 scripts/make-koharu-native-draft-artifacts.py --out build/koharu_native_draft`、`python3 scripts/validate-koharu-artifacts.py --root build/koharu_native_draft`。草稿生成 13 个 TextBox、10 个 bubble summary、`segmentGlyphPixelCount = 92827`，validator 输出 `verdict = contractExampleOnly`、`sourceImageSHA256Matches = true`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`。

遗留事项：

- 本版本不生成真实 Koharu 四件套、不写入 `test/koharu_artifacts/`、不上传 Release、不触发手动 `ci-fast/full`，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 真正复刻效果仍需要外部 detector / Koharu 真实 TextBoxes、BubbleMask、SegmentMask 注入后跑 `ci-fast/full`；后续编译提速建议单独拆 `writeOCRProbeText` 到扩展文件，再云端 Xcode build 验证。

### v1.84：Koharu Handoff CI Result Review Packet
日期：2026-07-07

依据：v1.83 已把 Release archive 本地 inspection proof 写入 handoff packet，但真实 handoff 仍要等 GitHub Actions 手动 `ci-fast/full` 结果包证明 App runtime 实际读取同一组四件套。继续补交付后 Agent C 的云端结果包核对清单，避免错 run、旧包、错 commit 或只凭本地 inspection 放行。

核心变更：

- `handoffPacket` 新增 `ghRunWatchCommand` 和 `ghRunDownloadCommand`，用 `<run-id>` 占位指导人工在 workflow dispatch 后等待并下载 `AITRANS CI Results` 未加密结果包。
- `handoffPacket.ciResultReview` 和 `expected*Assertions` 新增机器可读核对清单，覆盖必需结果文件、探针输出文件、manifest identity、Release tag / asset / SHA 回显、Koharu validator identity / orientation、逐文件 cloud identity rows、App runtime readiness、identity reconciliation、external shadow OCR coverage、orientation blockers、TXT 摘要 needles 和旧包拒收规则。
- CI static package smoke 只断言这些 review / assertion 字段的 shape 和关键语义，不访问 GitHub、不下载 run、不启动模拟器、不把本地 `releaseArchive.inspection` 写成云端 runtime proof。
- artifact contract README 和测试规范同步 v1.84 handoff 后置 review 口径。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`python3 -B -m py_compile scripts/validate-koharu-artifacts.py`、workflow YAML parse、JSON parse、Koharu valid / orientation / invalid fixture 矩阵、`test/koharu_artifacts --allow-missing`、fixture package handoff packet、`python3 -m json.tool /tmp/koharu-handoff-v184.json` 和新增 `ciResultReview` / structured assertions 字段 smoke。
- 云端 `AITRANS CI Results` run `28864811074` 通过，artifact `aitrans-ci-unversioned-smalldata_test--13591a80d066-run28864811074-attempt1` 已核对：`branch = smalldata_test`、`commitSha = 13591a80d0663fb3fed83f74e2cb03ddf851a05e`、`runId = 28864811074`、`runAttempt = 1`、`workflowName = AITRANS CI Results`、`xcodeBuildRequired = false`、`xcodeBuildSkippedReason = non_app_build_related_fast_path`、`probeMode = skip`、`scopeDiffMethod = checkout_before`、`scopeDiffFallbackUsed = false`、`koharuValidatorExtendedRequired = true`；`junit.xml` 为 5 tests / 0 failures；fixture package smoke 证明 `releaseArchiveInspectionPassed = true`、`releaseArchiveInspectionVerdict = contractExampleOnly`、`candidateDirectoryCount = 1`、`ghRunWatchCommand` / `ghRunDownloadCommand` 存在、`ciResultReview.requiredResultFiles` 覆盖四个必需文件、`expectedCloudIdentityRows = 5`、`expectedCIManifestAssertions = 14`、`expectedAppRuntimeAssertions = 10`、`expectedExternalShadowOCRAssertions = 8`、`expectedConvergenceAssertions = 6`、`staleRunRejectionAssertions = 5`。
- 同轮 `AITRANS - Build IPA` run `28864811123` 通过，archive 10m45s，IPA package 6s。

遗留事项：

- 本版本仍不生成真实 Koharu 四件套、不上传 Release、不触发手动 `ci-fast/full`，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 真实验收仍必须由人工提供外部 detector 输出，按 handoff packet 上传 Release、dispatch `ci-fast/full`，再用 `ciResultReview` 核对云端 App runtime readiness、identity reconciliation、external shadow OCR coverage 和 orientation gates。

### v1.83：Koharu Handoff Archive Inspection Proof
日期：2026-07-07

依据：v1.82 已提供 `--inspect-release-archive` 和带 repo 的 Release upload / workflow dispatch 命令，但 handoff packet 本身还没有把“将上传的 archive 已按 CI 唯一四件套目录规则复验”作为结构化 proof 带给人工和 Agent C。继续补真实 artifact handoff 交付闭环，不新增 report-only 探针层，不改 Swift 主链路。

核心变更：

- `--package-release-archive` 生成 zip 后会立即用 `inspect_release_archive()` 复验该 zip，并把结果写入 `handoffPacket.releaseArchive.inspection`，包含 validation verdict、candidate directory、member count、artifact identity summary 和 orientation summary。
- `handoffPacket` 新增 `releaseArchiveInspectionPassed`、`releaseArchiveInspectionVerdict`、`inspectReleaseArchiveCommand` 和 `expectedCIManifestEcho`，让上传前 proof、Release asset SHA、workflow dispatch 参数和 Agent C 云端 manifest 核对点在同一个 JSON 中闭合。
- handoff ready 现在要求真实 validator verdict、archive SHA 和本地 archive inspection proof 同时成立；`contractExampleOnly` fixture 仍可用于 smoke，但不会被标记为 release / dispatch ready。
- `AITRANS CI Results` static checks 只在 fixture package smoke 中断言 handoff inspection proof，不把 inspection 重新塞回真实 Release 注入主路径，避免增加 workflow 启动风险。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`python3 -B -m py_compile scripts/validate-koharu-artifacts.py`、workflow YAML parse、JSON parse、Koharu valid / orientation / invalid fixture 矩阵、`test/koharu_artifacts --allow-missing`、handoff packet、package 拒绝 / 成功 zip 布局、`--inspect-release-archive` 成功 / 空 archive / 双 candidate archive 失败路径、fixture handoff inspection proof、active-like handoff ready + inspection proof。
- 云端 `AITRANS CI Results` run `28861251800` 通过，artifact `aitrans-ci-unversioned-smalldata_test--642c1e2d5683-run28861251800-attempt1` 已核对：`branch = smalldata_test`、`commitSha = 642c1e2d5683339c6c8ae33fc0ff1437bdf17bb7`、`runId = 28861251800`、`runAttempt = 1`、`workflowName = AITRANS CI Results`、`xcodeBuildRequired = false`、`xcodeBuildSkippedReason = non_app_build_related_fast_path`、`probeMode = skip`、`scopeDiffMethod = checkout_before`、`scopeDiffFallbackUsed = false`、`koharuValidatorExtendedRequired = true`；package smoke 证明 `releaseArchiveInspectionPassed = true`、`releaseArchiveInspectionVerdict = contractExampleOnly`、`candidateDirectoryCount = 1`、`expectedCIManifestEcho` 存在，`junit.xml` 为 5 tests / 0 failures。
- 同轮 `AITRANS - Build IPA` run `28861251831` 通过。

遗留事项：

- 本版本仍不生成真实 Koharu 四件套、不上传 Release、不触发手动 `ci-fast/full`，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 真实验收仍必须由人工提供外部 detector 输出，按 handoff packet 上传 Release 并 dispatch `ci-fast/full` 后，核对云端 App runtime readiness、identity reconciliation、external shadow OCR coverage 和 orientation gates。

### v1.82：Koharu Release Archive Inspect and Upload Commands
日期：2026-07-07

依据：v1.81 已能从本地四件套生成 Release zip 和 `workflow_dispatch` 参数，但真实 P0 handoff 仍有两个易错点：上传前本地 archive 是否符合 CI 唯一目录规则，以及上传到 GitHub Release / 触发 workflow 是否指向正确 repo。继续补这段交付闭环，比新增 report-only 探针层更接近 `v1.38-current-gap-to-koharu.md` 要求的真实 artifact 注入。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 `--inspect-release-archive <zip|tar>`，用 CI 同口径安全解包并检查 archive 中是否恰好有一个包含四个标准 JSON 的目录，输出 archive size/SHA、members、candidate directory 和 validator verdict。
- handoff packet 新增 `--repo`、`--probe-mode` 参数，输出结构化 `releaseUpload`，并生成带 `--repo` 的 `ghReleaseUploadCommand`、`ghWorkflowDispatchCommand` 和 `ghRunListCommand`；默认不加 `--clobber`，避免误覆盖 Release asset。
- `AITRANS CI Results` 继续沿用既有 Release archive 下载、SHA 校验、唯一四件套目录解包、active validator identity / orientation 摘要和 App runtime 证据链；`--inspect-release-archive` 定位为上传前本地 preflight，不作为本轮云端 manifest 新字段。
- CI static checks 保留 package smoke 和 handoff 命令 repo / quote 检查；archive inspect 的 0 / 多 candidate 失败路径由本地轻量验证覆盖，避免在 workflow 内增加容易破坏 GitHub job 启动的复杂脚本块。
- artifact contract README 和测试规范同步 upload / inspect / dispatch / run list 的交付步骤和验收口径。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 初次提交 `b0c643e` 的 `AITRANS CI Results` run `28855767837` 未能创建 job；后续修复移除 workflow 内 release archive inspection 注入、manifest 和 failure summary 钩子，只保留本地 validator / handoff 能力。
- 本地轻量验证通过：`git diff --check`、`python3 -B -m py_compile scripts/validate-koharu-artifacts.py`、workflow YAML parse、JSON parse、Koharu valid / orientation / invalid fixture 矩阵、`test/koharu_artifacts --allow-missing`、handoff packet、package 拒绝 / 成功 zip 布局、`--inspect-release-archive` 成功 / 空 archive / 双 candidate archive 失败路径、active-like handoff ready smoke。
- 云端结果包待本修复 commit push 后确认：本版本只改 Python validator、workflow static checks 和文档，预期 push CI 走 build-skip；workflow / validator 变化会触发 extended Koharu validator matrix 和 package smoke。

遗留事项：

- 本版本仍不生成真实 Koharu 四件套、不上传 Release、不触发手动 `ci-fast/full`，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 真实验收仍必须由人工提供外部 detector 输出，运行 package / inspect / upload / dispatch 命令后，核对云端 App runtime readiness、identity reconciliation、external shadow OCR coverage 和 orientation gates。

### v1.81：Koharu Release Handoff Packet Preflight
日期：2026-07-07

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 已明确当前下一步仍是 P0：拿真实 `TextBoxes / BubbleMask / SegmentMask` 四件套，通过 Release archive 注入手动 `ci-fast/full`，看 App runtime readiness、identity reconciliation、external shadow OCR coverage 和 orientation gates。v1.79-v1.80 已收紧 source image SHA contract，但外部 detector 输出到 GitHub Release / workflow_dispatch 的交付路径仍需要人工拼 zip、算 SHA、填参数，容易错包或漏填。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 `--emit-handoff-packet`，在 validator 摘要外输出 Release upload / `workflow_dispatch` handoff 清单，包含 source image SHA、四件套 size/SHA、orientation summary、建议的 `probe_mode=ci-fast`、`koharu_artifact_release_tag`、`koharu_artifact_asset`、`koharu_artifact_sha256`、`koharu_artifact_required=true` 和 `gh workflow run` 模板。
- 新增 `--package-release-archive <zip>`，把当前 root 下解析出的四件套打成一个 zip；zip 内只包含一个目录和四个标准 JSON，贴合 CI 的唯一目录检查。
- 打包默认只接受 `verdict = readyForShadowOCR`；`contractExampleOnly` examples 不会被标记为 handoff ready，`--allow-fixture-package` 仅用于本地 smoke。
- handoff packet 区分当前离线 root 的 `externalTextBoxesShadowOCRAllowed` 与 CI 注入 active 目录后的 expected readiness，避免把非 active 路径误读成 App 已消费 artifact。
- 打包路径增加源文件覆盖保护，`ghWorkflowDispatchCommand` 对 tag / asset / SHA 参数做 shell quote。
- `AITRANS CI Results` static checks 增加 package smoke：验证 `contractExampleOnly` fixture 默认拒绝打包、`--allow-fixture-package` 生成单目录四标准 JSON，并检查带空格 dispatch 参数 quote。
- artifact contract README 和测试规范同步新的 preflight / package 命令与 CI package smoke 预期。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`python3 -m py_compile scripts/validate-koharu-artifacts.py`、workflow YAML parse、JSON parse、Koharu valid / orientation / invalid fixture 矩阵、`test/koharu_artifacts --allow-missing`、handoff packet、package 拒绝 / 成功 zip 布局和 quote smoke。
- 云端 `AITRANS CI Results` run `28854050132` 通过，artifact `aitrans-ci-unversioned-smalldata_test--54a94b6e992f-run28854050132-attempt1` 已核对：`branch = smalldata_test`、`commitSha = 54a94b6e992f06d5e7d1704d1634d87aca3dffb6`、`xcodeBuildRequired = false`、`xcodeBuildSkippedReason = non_app_build_related_fast_path`、`probeMode = skip`、`scopeDiffMethod = checkout_before`、`scopeDiffFallbackUsed = false`、`koharuValidatorExtendedRequired = true`、`probeOutputRetainedFiles = ["probe-not-run.txt"]`，package fixture smoke 产物存在且 verdict 为 `contractExampleOnly`。
- 同轮 `AITRANS - Build IPA` run `28854050100` 通过。

遗留事项：

- 本版本不生成真实 Koharu 四件套，不上传 Release，不触发手动 `ci-fast/full`，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 真实验收仍必须由人工提供外部 detector 输出，运行 handoff packet 生成 zip，上传 Release 后手动 dispatch，并核对云端 App runtime 证据。

### v1.80：App Runtime Source Image SHA Gate
日期：2026-07-07

依据：v1.79 已让 Python validator / CI static smoke 要求 Koharu active manifest 声明 `sourceImageSHA256` 并匹配当前仓库 `test/1.png`，但 Swift App runtime readiness 仍主要核对 source image 路径和 App 可见文件 size / SHA256。如果外部 artifact manifest 在 App 探针内缺失、格式错误或声明了旧图 SHA，必须由 App 侧 readiness、identity receipt、contract dry-run 和 identity reconciliation 同步阻塞，避免 validator 与 runtime handoff 口径分叉。

核心变更：

- `MangaOverlayExternalArtifactManifest` 解析 `sourceImageSHA256`，并记录字段存在性、类型有效性和标准化 SHA。
- `externalArtifactReadinessReport.coordinateValidation` 新增 declared / expected / fieldPresent / typeValid / matches 字段；Swift readiness 现在对缺失、非 64 位 hex 或不匹配 runtime bundle `test/1.png` SHA 的 manifest 输出 `sourceImageSHA256Missing` / `sourceImageSHA256Invalid` / `sourceImageSHA256Mismatch`，并阻止 `readyForShadowOCR`。
- `externalArtifactReadinessReport.artifactIdentityReceipt` 新增 `sourceImageSHA256Declared`、`sourceImageSHA256Expected`、`sourceImageSHA256Matches`；`identityVerdict = activeArtifactIdentityRecorded` 现在要求 manifest SHA 与 App runtime 可见 source image SHA 匹配。
- `koharuNativeArtifactContractDryRunReport` 的 manifest required fields 增加 `sourceImageSHA256=<expected>`，App-side identity gate 也消费 `sourceImageSHA256Matches`。
- `koharuArtifactIdentityReconciliationReport` 顶层新增 declared / expected / matches，`readyForCIManifestComparison` 只有在 source image SHA match 为 true 时才能通过。
- `1_ocr_probe_text.txt` 摘要、CI post-export smoke、`ci-artifact-manifest.json` 的 App receipt / identity reconciliation summaries 和 failure summary 都透传 App runtime source image SHA declared / expected / matches。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `.github/workflows/ci-results.yml`
- `README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、JSON 解析、workflow YAML parse、workflow Python heredoc 编译、Koharu validator valid / invalid fixture 矩阵。
- 云端 `AITRANS CI Results` run `28851345305` 通过，artifact `aitrans-ci-unversioned-smalldata_test--5668ab847c01-run28851345305-attempt1` 已核对：`branch = smalldata_test`、`commitSha = 5668ab847c0148201e26010a95de2a92306a92a4`、`xcodeBuildRequired = true`、`xcode build = success`、`probeMode = skip`、`scopeDiffMethod = checkout_before`、`scopeDiffFallbackUsed = false`、`changedFiles = ["AITRANS/Models/TranscriptModels.swift"]`。
- 同轮 `AITRANS - Build IPA` archive 编译阶段已成功，但上传 archive log 时 GitHub artifact service 多次 timeout，属于打包 artifact 上传失败，不是 Swift 编译失败。

遗留事项：

- 本版本不新增真实 Koharu 四件套，不改变 OCR / LLM / renderer / 覆盖图 / active artifact，不追加 `metrics/version_history.csv`。
- 需要真实 handoff 验收时，仍需手动 `workflow_dispatch` 选择 `ci-fast` 或 `full` 并注入 Koharu artifact archive，核对 App receipt 与 reconciliation 的 `sourceImageSHA256Matches = true`。

### v1.79：Koharu Source Image SHA Contract Gate
日期：2026-07-07

依据：v1.66-v1.78 已让 CI / App 侧记录 source image 和四件套 size / SHA256 identity，但 Koharu active manifest 仍只声明 `sourceImage = test/1.png`，没有强制声明“本 artifact 是基于当前仓库这张 `test/1.png` 生成”。如果外部 detector 用旧图、裁切图或错图导出，路径和尺寸可能看似正确，后续云端 handoff 仍有误接风险。

核心变更：

- `scripts/validate-koharu-artifacts.py` 要求 manifest 声明 `sourceImageSHA256`，并校验它必须匹配当前仓库 `test/1.png` 的实际 SHA256：`9c3dc0ee9dfc4a6b664c4b4dd32e5b74b214f6f0d16f32ef97ef02ce47c2ed21`。
- validator 输出新增 `sourceImageSHA256`、`expectedSourceImageSHA256`、`sourceImageSHA256Matches`，`artifactIdentitySummary` 新增 `sourceImageSHA256Declared`、`sourceImageSHA256Expected`、`sourceImageSHA256Matches`，并新增 `sourceImageSHA256Missing` / `sourceImageSHA256Invalid` / `sourceImageSHA256Mismatch` verdict。
- CI 注入真实 Koharu artifact 和 valid fixture smoke 都会断言 manifest 声明 SHA 与仓库 source image SHA 一致；完整 invalid fixture 矩阵新增 `source_image_sha_missing` 和 `source_image_sha_mismatch`。
- artifact contract README、`md/test/test.md` 和示例 manifests 同步新的 source image SHA contract。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/artifact_contract/examples/**/1.manifest.json`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 待本轮本地轻量验证与 push 后云端结果包确认：预期 workflow / validator / contract 变更会触发 extended Koharu invalid fixture matrix，且本轮仍不涉及 Swift / Xcode 工程 / `test/` 素材，预期 `xcodeBuildRequired = false`。

遗留事项：

- 本版本不新增真实 Koharu 四件套，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 如果未来 `test/1.png` 变更，所有 active artifact 和 contract fixtures 必须同步新的 `sourceImageSHA256`，否则 validator 应阻塞 handoff。

### v1.78：CI Scope Targeted Fetch Closure
日期：2026-07-07

依据：v1.76 用 `fetch-depth: 2` 修复了普通单提交 push 的 scope diff，但遗留事项仍指出：如果一次 push 包含多提交且 `github.event.before` 不在最近 2 个提交内，`Detect CI scope` 仍会回退 `git ls-files`，把 `changed-files.txt` 变成全仓列表，进而误触发 Xcode build 和 extended Koharu validator。v1.77 已让结果包可追溯，本轮继续把 scope diff 方法本身变成可审计证据。

核心变更：

- `Detect CI scope` 在 checkout 内找不到 `github.event.before` 时，先执行定向 `git fetch --no-tags --depth=1 origin <before>`，成功后继续按真实 before SHA diff。
- 只有 checkout 和 targeted fetch 都无法拿到 before commit 时，才回退 `git ls-files` 全仓列表。
- CI 输出、manifest 和 failure summary 新增 `scopeDiffMethod`、`scopeDiffBaseSha`、`scopeDiffFallbackUsed`，Agent C 可判断 changed-files 是否来自 `checkout_before`、`targeted_fetch` 或 `full_repo_fallback`。
- `md/test/test.md` 同步多提交 push 的 scope diff 验收口径。

关键文件：

- `.github/workflows/ci-results.yml`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 待本轮本地轻量验证与 push 后云端结果包确认：普通单提交 push 预期 `scopeDiffMethod = checkout_before`、`scopeDiffFallbackUsed = false`；若后续出现多提交 push 且 before 不在浅克隆内，预期使用 `targeted_fetch` 而不是全仓 fallback。

遗留事项：

- 本版本不新增真实 Koharu 四件套，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 若极端情况下 GitHub 不允许按 SHA 定向 fetch，workflow 仍会显式记录 `full_repo_fallback`，避免 Agent C 把全仓 changed-files 误认为精确 diff。

### v1.77：CI Artifact Provenance Self-Trace
日期：2026-07-07

依据：v1.76 已让 build-skip 结果包更干净，但 Agent C 下载未加密 artifact 后仍需要从 GitHub UI 或 `gh run view` 反查 run URL、artifact name、event/ref/repository 和变更范围。后续真实 Koharu artifact handoff 会更依赖“拿到的包就是目标 run / 目标提交 / 目标变更”的机器可核对证据，因此本轮继续增强 CI 结果包可追溯性。

核心变更：

- `ci-artifact-manifest.json` 新增 `artifactName`、`eventName`、`repository`、`ref`、`refName` 和 `runUrl`，让结果包自带 GitHub run 与 artifact identity。
- `ci-artifact-manifest.json` 新增 `changedFilesCount`、`changedFilesSHA256` 和 `changedFiles`，直接记录本轮 scope detection 的文件列表和稳定哈希。
- `ci-failure-summary.md` 同步打印 run URL、event/ref/repository、artifact name、changed files count 和 changed files SHA256，便于失败时快速定位。
- `md/test/test.md` 补充 v1.77 结果包 provenance 字段验收口径。

关键文件：

- `.github/workflows/ci-results.yml`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 待本轮本地轻量验证与 push 后云端结果包确认：预期 manifest 能解析并包含 self-trace 字段；failure summary 顶部能直接看到 run URL、artifact name 和 changed-files 摘要。本轮仍是 CI / 文档变更，预期 `xcodeBuildRequired = false`。

遗留事项：

- 本版本不新增真实 Koharu 四件套，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 若未来需要限制 manifest 体积，可保留 `changedFilesSHA256` 和 count，将完整 `changedFiles` 迁移为单独文件引用；当前普通 push 变更列表很小，直接内嵌更利于验收。

### v1.76：CI Scope Diff Accuracy / Skip Probe Artifact Hygiene
日期：2026-07-07

依据：v1.75 云端 push run `28844582258` 虽然只改 workflow 和日志，但 `changed-files.txt` 回退成全仓列表，导致 `xcodeBuildRequired = true` 并额外跑 Xcode build。原因是 `actions/checkout` 默认浅克隆只含当前提交，`Detect CI scope` 找不到 `github.event.before` 时只能回退 `git ls-files`。这会削弱非 App 改动的 build-skip 加速路径。同轮审计还发现 `probe_mode=skip` 会把仓库中已有的旧 `output/` 复制进结果包，容易让 Agent C 误读为本次云端探针产物。

核心变更：

- `AITRANS CI Results` 的 checkout 增加 `fetch-depth: 2`，让普通单提交 push 能 diff 到 `github.event.before`，避免浅克隆缺 before commit 时误判全仓变化。
- `Copy available probe outputs` 只在 `probe_mode != skip` 且 `manga_probe` 成功时复制本轮 `output/`；skip 或探针失败时只写 `output/probe-not-run.txt`，不再把 checked-in 旧 JSON / TXT / PNG 混入本次 CI artifact。
- `md/test/test.md` 补充 scope detection 和 skip probe artifact hygiene 要求，明确 build-skip 结果包不能被旧探针输出污染。

关键文件：

- `.github/workflows/ci-results.yml`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 待本轮本地轻量验证与 push 后云端结果包确认：预期本次仅 workflow / 文档变更时 `xcodeBuildRequired = false`，`xcodeBuildSkippedReason = non_app_build_related_fast_path`，`changed-files.txt` 只列本次变更文件；`probeMode = skip` 时 `probeReportPath` 为空，`probeOutputRetainedFiles = ["probe-not-run.txt"]`。

遗留事项：

- `fetch-depth: 2` 覆盖普通单提交 push；若后续一次 push 包含多提交且 `before` 不在最近 2 个提交内，仍可能回退全仓列表。需要时再升级为按 SHA 定向 fetch，而不是直接全量 checkout。
- 本版本不新增真实 Koharu 四件套，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。

### v1.75：CI Manifest Step Split / Workflow Startup Fix
日期：2026-07-07

依据：v1.74 把 native-lite manifest 摘要直接塞进 `Write manifest`，使该 GitHub Actions 单步脚本从上一版约 20k 字符增长到约 26k 字符。最新 push 的 `AITRANS CI Results` run `28844255398` 在 0 秒失败且没有 job/log，`gh run view` 明确提示 workflow file issue；这符合单步 `run:` 脚本过大导致 workflow 启动前被拒绝的风险。

核心变更：

- `AITRANS CI Results` 保留 v1.74 的 `koharuNativeLiteReportSummary` 与 `koharuNativeLiteConvergenceGateSummary` manifest 字段，但改由独立 `Append native-lite manifest summary` step 读取已生成的 `ci-artifact-manifest.json` 和可用 `probe_report.json` 后追加。
- `Write manifest` step 恢复到上一轮成功版本的脚本体积，避免继续触发 workflow 启动阶段失败；native-lite 追加 step 在 `probe_mode=skip` 时仍写出字段，值来自空 probe summary，便于 Agent C 看到字段存在。
- 产物结构、字段名、probe 路径、Swift 逻辑、OCR / LLM / renderer 和 active artifact gate 不变。

关键文件：

- `.github/workflows/ci-results.yml`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`.github/workflows/ci-results.yml` YAML parse、workflow Python heredoc 语法编译、`python3 -m json.tool` 解析 `test/1.ground_truth.json` / `output/probe_report.json` / `output/clean_text_diagnostic.json`。
- 拆分后 workflow 单步脚本体积：`Write manifest = 20176 chars`，`Append native-lite manifest summary = 5996 chars`。

遗留事项：

- 需要 push 后重新触发 `AITRANS CI Results`，下载结果包确认 manifest 字段存在且本次 run 不再 0 秒失败。
- 本版本不新增真实 Koharu 四件套，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.74：Native-Lite CI Summary / Gap Roadmap Refresh
日期：2026-07-07

依据：v1.39-v1.46 的 detector-lite、shadow OCR、refinement、closed-loop、BubbleMask instance-lite、SegmentMask refinement-lite、bundle-lite 和 promotion gate-lite 已进入 Swift 报告与 convergence，但云端 `ci-artifact-manifest.json` / `ci-failure-summary.md` 仍主要汇总 external artifact handoff、contract dry-run、identity 和 external shadow OCR。Agent C 若要判断 native-lite 阻塞，仍需深挖完整 `probe_report.json`；同时 `md/koharu研究/v1.38-current-gap-to-koharu.md` 的推荐路线仍把部分已完成 report-only 层写成未来任务。

核心变更：

- `AITRANS CI Results` manifest 新增 `koharuNativeLiteReportSummary`，直接汇总 v1.39-v1.46 native-lite report 的 verdict、关键 count、TextBox -> SegmentMask linkage breakdown、needs-real-artifact blocks 和 promotion preview 状态。
- manifest 新增 `koharuNativeLiteConvergenceGateSummary`，直接摘出 detector-lite、shadow OCR、refinement、closed-loop、BubbleMask instance-lite、SegmentMask refinement-lite、bundle-lite、promotion gate-lite 及 linkage work item / gate 的 status、blocks、nextAction 和 decision signals。
- `ci-failure-summary.md` 的 Koharu artifact gate 区块新增 native-lite report / convergence gate 摘要，方便 Agent C 在失败摘要里直接看到 native-lite 阻塞位置。
- `ci-fast/full` smoke 扩展 `1_ocr_probe_text.txt` needles，要求 native-lite report summary 存在，防止 TXT 快照悄悄丢失 v1.39-v1.46 证据。
- `md/koharu研究/v1.38-current-gap-to-koharu.md` 标注原推荐版本路线为历史判断，说明 v1.39-v1.46 已以 report-only / proxy 形式完成；当前下一步仍是注入真实四件套跑 `ci-fast/full`，不是重复实现同名 detector-lite / promotion gate。
- README 与测试规范同步 v1.74 manifest 字段和验收口径。

关键文件：

- `.github/workflows/ci-results.yml`
- `README.md`
- `md/test/test.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`.github/workflows/ci-results.yml` YAML parse、workflow 内 11 个 Python heredoc 语法编译、`python3 -m json.tool` 解析 `test/1.ground_truth.json` / `output/probe_report.json` / `output/clean_text_diagnostic.json`、基于云端 `ci-fast` run `28842227463` artifact 的 native-lite manifest summary helper 离线 smoke。

遗留事项：

- 本版本不新增 detector、OCR、LLM、PNG、renderer 或 active Koharu artifact，不改变主 OCR、翻译、覆盖图、report-only 账本语义或漫画质量指标，不追加 `metrics/version_history.csv`。
- 缺真实 `test/koharu_artifacts/` 时，native-lite 仍是 proxy / report-only；真实收益仍必须等外部四件套注入后看 external shadow OCR、orientation 和 identity handoff。

### v1.73：Cloud ci-fast Evidence / Swift Warning Cleanup
日期：2026-07-07

依据：v1.72 新增 CI manifest 的 Koharu contract dry-run 与 convergence gate summary 后，需要用真实云端 `ci-fast` 探针确认这些字段在非 skip 路径可用；同一轮 Xcode 日志显示 4 处 Swift unused-value warning，虽不影响构建，但会增加后续 Agent C 读日志噪声。

核心变更：

- 云端手动 `ci-fast` run `28842227463` 已验证 commit `599443891e780155ba62773a6e1bdc7090b3ee6c` 的未加密 CI 结果包可用：GGUF 下载 / SHA 校验、静态检查、Xcode build、模拟器 build、漫画探针和 artifact 上传均成功。
- 结果包 `aitrans-ci-unversioned-smalldata_test--599443891e78-run28842227463-attempt1` 的 manifest 匹配 `branch = smalldata_test`、`runAttempt = 1`、`workflowName = AITRANS CI Results`、`probeMode = ci-fast`、`mangaProbeOutcome = success`；`junit.xml` 为 5 tests / 0 failures，并包含 `.xcresult`、`probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt` 和核心 PNG。
- 真实探针路径已填充 `koharuNativeArtifactContractDryRunSummary` 与 `koharuArtifactConvergenceGateSummary`；缺 active artifact 时 contract dry-run 正确为 `blockedByMissingActiveArtifacts`，coverage / orientation gate 保持 open / not evaluated，`G-ci-fast-report-availability` 为 passed 且 `requiredReportSpan = v1.24-v1.70`。
- 清理 `MangaOverlayProbeService` 与 `TranslationSessionStore` 中不参与逻辑的 unused-value 绑定，减少 Xcode build 日志噪声，不改变主 OCR、翻译、覆盖图、report-only 账本或 active artifact gate。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `update_log.md`

验证结果：

- 云端 `ci-fast` 探针：run `28842227463` 成功，`engineUsed = Local GGUF`、`decodingMode = deterministic`、`totalBlocksDetected = 13`、`passedBlocks = 1`、`failedBlocks = 12`、clean text `5 / 11` 通过，缺 active artifact 的 external shadow OCR 正确阻塞在 `manifestMissing`。

遗留事项：

- 本版本不新增 detector、OCR、LLM、PNG、renderer 或 active Koharu artifact，不改变漫画质量指标，不追加 `metrics/version_history.csv`。
- 缺真实 `test/koharu_artifacts/` 时，external TextBox shadow OCR / orientation path 仍只能验证阻塞和报告完整性；真实 artifact handoff 仍需后续注入四件套后再跑 `ci-fast` / `full`。

### v1.72：CI Artifact Convergence Gate Summary Closure
日期：2026-07-07

依据：v1.70-v1.71 已要求 Agent C 核对 coverage / orientation convergence gate、contract dry-run 和 App-side identity，但 `ci-artifact-manifest.json` 与 `ci-failure-summary.md` 仍主要打印 validator / readiness / shadow OCR 原始摘要，Agent C 需要深挖 `probe_report.json` 才能看到 work item / gate status、blocks 和 `G-ci-fast-report-availability` decision signals。

核心变更：

- `AITRANS CI Results` manifest 新增 `koharuNativeArtifactContractDryRunSummary` 和 `koharuArtifactConvergenceGateSummary`，直接汇总 contract dry-run、App-side identity、coverage / orientation work item 与 gate、identity reconciliation gate、`G-ci-fast-report-availability` 的 decision signals。
- artifact-requested smoke 新增 `G-ci-fast-report-availability.requiredReportSpan = v1.24-v1.70`、`missingReportCount`、`missingReports` 断言，并扩展 TXT needles，确保 coverage / orientation / OCR success / App-side identity 摘要存在。
- `ci-failure-summary.md` 的 Koharu artifact gate 区块补充 external shadow OCR counts、contract dry-run safety、coverage / orientation convergence work item / gate 状态和 report availability signals，降低 Agent C 找错包或漏看 blocker 的概率。
- README、flow、测试规范同步 build-skip 快路径口径：只有 `xcodeBuildRequired=true` 时 `.xcresult` 是必需编译证据，build-skip 必须看 manifest skip reason。

关键文件：

- `.github/workflows/ci-results.yml`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`.github/workflows/ci-results.yml` YAML parse、workflow 内 6 个 Python heredoc 语法编译、`python3 -m json.tool` 解析 `test/1.ground_truth.json` / `output/probe_report.json` / `output/clean_text_diagnostic.json`、Koharu validator allow-missing、`contract_example_only_invalid --expect-fail`、新增 manifest summary helper 离线 smoke。

遗留事项：

- 该版本不新增 detector、OCR、LLM、PNG、renderer 或 active Koharu artifact；未重新跑完整漫画探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.71：Convergence Dependency Span / CI Handoff Documentation Closure
日期：2026-07-07

依据：v1.70 已完成 App/CI artifact handoff strict closure 并通过云端 push 快验，但 `koharuArtifactConvergenceReport`、测试规范和 artifact contract README 仍有少量 v1.68 / v1.69 口径残留，容易让后续 Agent C 按旧 dependency span 或 validator-only preflight 验收。

核心变更：

- `G-ci-fast-report-availability` 的 threshold、`requiredReportSpan` 和 notes 从 `v1.24-v1.68` 更新为 `v1.24-v1.70`，纳入 shadow OCR coverage closure 与 App/CI handoff strict closure。
- `README.md`、`md/flow/flow.md`、`md/test/test.md` 明确：填写 Koharu artifact archive 时必须跑 `ci-fast` 或 `full`，不能用 `probe_mode=skip`；coverage / orientation work item 与 gate ID、status、TXT 摘要和 App-side identity 都是验收证据。
- `md/koharu研究/artifact_contract/README.md` 将旧 v1.15 清单改成 v1.70+ active artifact / validator preflight 清单，并明确 validator 通过不等于 Agent C 可验收，云端闭环还必须核对 contract dry-run、identity reconciliation、shadow OCR coverage 和 orientation blockers。
- `md/koharu研究/v1.38-current-gap-to-koharu.md` 补 v1.70 云端 run 证据和 v1.71 后补充。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、`python3 -m json.tool output/probe_report.json`、`python3 -m json.tool output/clean_text_diagnostic.json`、`swiftc -parse $(rg --files AITRANS -g '*.swift')`、`scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`、valid fixture validator、`contract_example_only_invalid --expect-fail`。

遗留事项：

- 该版本不新增 detector、OCR、LLM、PNG、renderer 或 active Koharu artifact；未重新跑完整漫画探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.70：Koharu Artifact App / CI Handoff Strict Closure
日期：2026-07-07

依据：v1.69 已把 validator manifest 显式字段和 external shadow OCR coverage gate 收紧，但 App 侧仍需要显式保留 manifest 字段缺失 / 类型错误证据；CI smoke 也需要核对 `ocrSucceededCount`、coverage / orientation work item 与 gate ID；同时 “填写 Koharu artifact archive 但 `probe_mode=skip`” 会导致只验证下载和 validator，不能证明 App 实际消费 artifact。

核心变更：

- `MangaOverlayExternalArtifactManifest` 新增 `sourceImageFieldPresent`、`sourceImageTypeValid`、`contractExampleOnlyFieldPresent`、`contractExampleOnlyTypeValid`，让 Swift readiness 能区分缺字段、类型错误和真实值。
- `externalArtifactReadinessReport` / `externalArtifactIdentityReceipt` / nextAction 新增 `sourceImageMissing`、`contractExampleOnlyMissing`、`contractExampleOnlyInvalid` 分支；ready artifact 的 orientation gate 未闭合时从 warning 收紧为 blocked。
- `1_ocr_probe_text.txt` 的 external TextBox shadow OCR 行补出 `ocrSucceeded`，convergence 摘要补出 coverage / orientation work item status、gate status 和 gate blocks。
- GitHub Actions extended validator matrix 新增 `contract_example_only_invalid`；artifact requested 的探针 smoke 硬核对 `ocrSucceededCount > 0`、coverage / orientation work item 与 gate ID、coverage gate passed，以及 orientation gate 不得在仍有 blockers 时 passed。
- CI metadata 禁止 Koharu artifact archive 与 `probe_mode=skip` 组合；真实四件套注入必须用 `ci-fast` 或 `full` 产生 App 侧证据。
- 同步更新 Koharu contract README、流程文档、流程图和测试规范；新增 invalid fixture `contract_example_only_invalid`。

关键文件：

- `.github/workflows/ci-results.yml`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/artifact_contract/examples/invalid/contract_example_only_invalid/*`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、YAML smoke、JSON 解析、Swift `swiftc -parse`、Koharu validator matrix。
- 云端 push 快验通过：commit `6b53da9bb3005afbc9bc4bd5d1a8d05e06ca37cf`；`AITRANS CI Results` run `28840108595` 成功，manifest 匹配 `branch = smalldata_test`、`commitSha = 6b53da9bb3005afbc9bc4bd5d1a8d05e06ca37cf`、`xcodeBuildRequired = true`、`xcodeBuildOutcome = success`、`.xcresult` 存在，JUnit `5` tests / `0` failures，默认 push `probeMode = skip`、`mangaProbeOutcome = skipped`，extended validator required 并正确拒绝 `contract_example_only_invalid`。
- 云端打包通过：`Build IPA` run `28840108614` 成功。
- 未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked / identity missing。
- 该版本不新增 detector、OCR、LLM、PNG 或 renderer 算法，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.69：External Artifact Validator / Shadow OCR Coverage Closure Gate
日期：2026-07-07

依据：v1.65-v1.68 已把真实 Koharu artifact 的 validator identity、App-side receipt、identity reconciliation 和 external shadow OCR coverage 接进 CI / convergence，但仍有两个闭环风险：一是 validator 对 active manifest 缺 `sourceImage` 或缺 `contractExampleOnly` 会走默认值，可能放宽真实 artifact 准入；二是 convergence 的 external shadow OCR coverage 只要求 `executed = true` 和 `candidateCount > 0`，没有把实际 crop OCR 执行数 / 成功数纳入闭合条件，且 ready artifact 未闭合时 gate status 仍是 warning。

核心变更：

- `scripts/validate-koharu-artifacts.py` 现在要求 manifest 显式声明 `sourceImage = test/1.png` 和布尔型 `contractExampleOnly`；缺失分别输出 `sourceImageMissing` / `contractExampleOnlyMissing`，非布尔 `contractExampleOnly` 输出 `contractExampleOnlyInvalid:*`，均阻止 `readyForShadowOCR`。
- 新增 invalid fixtures：`source_image_missing` 与 `contract_example_only_missing`，并接入 GitHub Actions extended Koharu validator matrix。
- `koharuArtifactConvergenceReport` 的 `WI/G-external-textbox-shadow-ocr-coverage` 在真实 artifact ready 后新增 `ocrExecutedCount > 0` 和 `ocrSucceededCount > 0` 闭合条件；未闭合时 gate status 从 warning 升为 blocked。
- `G-ci-fast-report-availability` 的 threshold / decision signals 更新为当前 v1.24-v1.68 依赖集合，并写出 `missingReportCount`、`missingReports` 和 `requiredReportSpan`，避免旧 v1.24-v1.27 文案误导 Agent C。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/artifact_contract/examples/invalid/source_image_missing/*`
- `md/koharu研究/artifact_contract/examples/invalid/contract_example_only_missing/*`
- `update_log.md`

验证结果：

- 本地轻量验证已通过；云端 commit `c1d5990df733d5593de57b4631c8e4120658dcb7` 的 `AITRANS CI Results` run `28839023072` 成功，`Build IPA` run `28839023071` 成功。默认 push 探针为 `skip`，未生成新的漫画探针报告。

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked / identity missing。
- 该版本不新增 OCR / LLM / PNG，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.68：Koharu Artifact Identity Reconciliation Gate
日期：2026-07-06

依据：v1.67 已把 App 探针 runtime 可见的 source image 与四件套 size / SHA256 写入 `artifactIdentityReceipt`，但 Agent C 仍需要手工把这些值与 `ci-artifact-manifest.koharuArtifactValidationIdentitySummary` 对齐。真实 artifact handoff 需要一个可机器核对的对账表和 CI match verdict，防止 validator 校验的是一组文件、App 消费的是另一组文件。

核心变更：

- 新增 `koharuArtifactIdentityReconciliationReport`，把 App receipt 规范化为 SourceImage + manifest / TextBoxes / BubbleMask / SegmentMask 五行 ledger，逐行写出 App size / SHA256、receipt 状态、contract dry-run identity status，以及 CI manifest identity 的 size / SHA 字段路径。
- `koharuArtifactConvergenceReport` 新增 `WI-koharu-artifact-identity-reconciliation` / `G-koharu-artifact-identity-reconciliation-ready`，并让 external shadow OCR coverage gate 在真实 artifact ready 后同时要求 reconciliation ready。
- GitHub Actions 在注入真实 Koharu artifact 并跑 `ci-fast/full` 后，会比较 validator identity 与 App reconciliation rows 的 size / SHA256，失败时阻断；`ci-artifact-manifest.json` 新增 App receipt summary、reconciliation summary 和 `koharuArtifactIdentityReconciliationMatch`。
- `1_ocr_probe_text.txt` 新增 reconciliation report、逐文件对账行和 convergence work item 摘要，方便 Agent C 直接核对。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `.github/workflows/ci-results.yml`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本轮本地轻量验证见最终回复。

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时 reconciliation 会保持 App receipt incomplete / not ready。
- 该版本不新增 OCR / LLM / PNG，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.67：App-Side Koharu Artifact Identity Receipt
日期：2026-07-06

依据：v1.66 已在 validator / CI manifest 中记录 Release archive 注入的四件套 identity，但 App 侧探针报告仍缺少运行时实际可见文件的 size / SHA256 receipt。Agent C 需要同时核对 CI manifest identity 与 `probe_report.json` 中 App runtime receipt，才能确认不是只下载 / 校验了 archive，而是 App 探针确实消费到同一组 active artifact 文件。

核心变更：

- `externalArtifactReadinessReport` 新增 `artifactIdentityReceipt`，记录 App bundle / runtime 中 `test/1.png`、manifest、TextBoxes、BubbleMask、SegmentMask 的存在性、size、SHA256、manifest schema / coordinate space / generatedBy / generatedAt / contractExampleOnly 和 `identityVerdict`。
- `koharuNativeArtifactContractDryRunReport` 新增 App 侧 identity 顶层摘要，并把每个 required file 的 `fileSizeBytes`、`sha256`、`identityStatus` 写入 dry-run file ledger；真实 artifact ready 时，contract dry-run ready 现在要求 App 侧 receipt 完整。
- `koharuArtifactConvergenceReport` 的 external shadow OCR coverage decision signals 透传 App 侧 identity verdict / files / hashes，`1_ocr_probe_text.txt` 同步打印 App 侧 identity 摘要和 required file SHA，方便 Agent C 对齐 `ci-artifact-manifest.koharuArtifactValidationIdentitySummary`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本轮本地轻量验证见最终回复。

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时 App 侧 receipt 会稳定记录 active 目录缺失 / required identity files missing。
- 该版本不新增 OCR / LLM / PNG，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.66：Koharu Artifact Identity / Contract Dry-Run Coverage Gate
日期：2026-07-06

依据：v1.65 已把 orientation summary 和 external shadow OCR coverage gate 接进 CI / convergence，但真实 Koharu archive 注入仍缺少两个验收细节：一是 Agent C 不能快速核对 active 四件套的文件身份是否与本轮 Release archive / source image 对齐；二是 `WI/G-external-textbox-shadow-ocr-coverage` 只要求 readiness 与 shadow OCR executed / candidateCount，还没有把 contract dry-run verdict 和 dry-run 边界安全纳入同一个闭环。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 `artifactIdentitySummary`，输出 source image、manifest、TextBoxes、BubbleMask、SegmentMask 的路径、存在性、size、SHA256，并透传 `generatedBy`、`generatedAt`、`contractExampleOnly`、schema、source image 和 coordinate space。
- GitHub Actions 注入 Koharu artifact archive 时只接受唯一一个同时包含四件套的目录，避免从多个目录各取一个 `rglob()[0]` 拼出错包；`ci-artifact-manifest.json` 透传 `koharuArtifactValidationIdentitySummary`，`ci-failure-summary.md` 打印 identity 摘要。
- `koharuArtifactConvergenceReport` 的 `WI-external-textbox-shadow-ocr-coverage` / `G-external-textbox-shadow-ocr-coverage` 在真实 artifact ready 后新增 contract dry-run 前置条件：`contractDryRunVerdict = activeArtifactsReadyForShadowOCR`、`dryRunOnly = true`、`activeExportAllowed = false`，再要求 `externalTextBoxShadowOCRReport.executed = true` 且 `candidateCount > 0`。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本轮本地轻量验证见最终回复。

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked / identity empty-or-missing / orientation summary。
- 该版本不新增 OCR / LLM / PNG，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.65：External TextBox Shadow OCR Coverage / Validator Orientation Summary
日期：2026-07-06

依据：v1.64 已能防止 external TextBox orientation partial / unsupported path 被 convergence 误判为闭环，但仍有两类证据缺口：一是 validator 只校验方向元数据是否合法，没有在 CI 结果包中汇总 TextBox 的竖排、旋转、line polygon 与 unsupported 风险；二是 artifact `readyForShadowOCR` 只证明四件套可解析，不证明 App 侧 external shadow OCR 已执行并产生 block-matched candidate。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 `orientationMetadataSummary`，汇总 sourceDirection / orientation category / rotation plan / line polygon / vertical / right-angle rotation / arbitrary rotation / unsupported reason，缺 active artifact 时也稳定输出空摘要。
- `ci-artifact-manifest.json` 新增 `koharuArtifactValidationOrientationSummary`，`ci-failure-summary.md` 的 Koharu artifact gate 区块同步打印 validator orientation 摘要，方便 Agent C 在模拟器探针前核对外部 TextBox 方向风险。
- `koharuArtifactConvergenceReport` 新增 `WI-external-textbox-shadow-ocr-coverage` / `G-external-textbox-shadow-ocr-coverage`。真实 artifact ready 后，若 `externalTextBoxShadowOCRReport` 缺失、`executed=false` 或 `candidateCount=0`，ExternalArtifacts stage 会进入 `externalShadowOCRCoverageBlocked`，orientation gate 也不会被误判为 passed / closed。
- `1_ocr_probe_text.txt` 追加 `convergenceExternalShadowOCRCoverage` 和 `convergenceExternalTextBoxOrientation` 摘要。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/artifact_contract/README.md`
- `update_log.md`

验证结果：

- 本轮本地轻量验证见最终回复。

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked / validator empty orientation summary。
- 该版本不新增 OCR / LLM / PNG，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.64：External TextBox Orientation Partial / Unsupported Convergence Gate
日期：2026-07-06

依据：v1.63 已能在真实 artifact ready 后对竖排或接近 90/180/270 度的 external TextBox 执行有上限 rotation shadow OCR，并在候选 / block summary 写出 unsupported reason。但 `koharuArtifactConvergenceReport` 仍主要消费 `orientationShadowPathNotExecutedBlocks`，存在“orientation path 已部分执行但仍因 line polygon warp 或任意角度 deskew unsupported 而未闭环，却被 convergence 看成 closed/passed”的风险。

核心变更：

- `externalTextBoxShadowOCRReport` 新增 `orientationShadowPathPartialBlocks`、`orientationUnsupportedBlocks`、`orientationUnsupportedReasonBreakdown`，把“已执行 rotation OCR 但仍有 unsupported orientation feature”的块提升到 report 级摘要。
- `orientationReadinessVerdict = orientationShadowPathExecuted` 现在要求无 not-executed blocks 且无 unsupported blocks；部分执行会保持 `orientationShadowPathPartiallyExecuted`。
- `koharuArtifactConvergenceReport` 的 ExternalArtifacts stage、`WI-external-textbox-orientation-shadow-path` 和 `G-external-textbox-orientation-shadow-path` 改为同时消费 executed / partial / notExecuted / unsupported / unsupported reason breakdown，line polygon warp 与任意角度 deskew 会继续作为 convergence blockers 暴露。
- `1_ocr_probe_text.txt` 的 external TextBox shadow OCR 汇总追加 `orientationPartial`、`orientationUnsupported` 和 `orientationUnsupportedReasons`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `git diff --check`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked 报告。
- 该版本仍不实现 line polygon crop / warp 或任意角度 deskew，只防止这类 unsupported orientation path 被 convergence 误判为已闭环。
- 该版本不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed` 或 active artifact，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.63：External TextBox Orientation Rotation Shadow OCR
日期：2026-07-06

依据：v1.62 已把 external TextBox 的 `sourceDirection`、`linePolygons` 和 `rotationDegrees` 纳入 orientation ledger，并阻止需要 orientation-aware path 但未执行的候选进入 would-promote 预览。`md/koharu研究/v1.38-current-gap-to-koharu.md` 要求从报告堆叠转向真实 TextBox / 竖排方向 shadow path。当前可安全复用的 OCR 能力是 crop 后 0/90/180/270 旋转，不具备任意角度 deskew 或 line polygon warp。

核心变更：

- `externalTextBoxShadowOCRReport` 在真实 `test/koharu_artifacts/` readiness 通过后，对竖排 TextBox 和接近 90/180/270 度的 rotation TextBox 执行有上限的 rotation shadow OCR；竖排使用 `ja-JP/ja/en-US/en` Vision language profile。
- 候选和逐块 summary 新增 `orientationAttemptedRotations`、`orientationSelectedRotation`、`orientationRecognitionLanguages`、`orientationUnsupportedReason`，让 JSON / TXT 能证明 orientation path 是否真的执行、选了哪个旋转、以及为何仍阻塞。
- `orientationReadinessVerdict` 区分 `orientationShadowPathExecuted`、`orientationShadowPathPartiallyExecuted`、`orientationShadowPathNeededNotExecuted`；line polygon warp 和任意角度 deskew 仍以 blocker 阻止 would-promote 预览。
- `1_ocr_probe_text.txt` 的 external TextBox shadow OCR 逐块摘要和报告汇总追加 rotation / language / unsupported 证据。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `git diff --check`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked 报告。
- 该版本只支持 90 度倍数 rotation shadow OCR，不实现任意角度 deskew 或 line polygon crop / warp。
- 该版本不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed` 或 active artifact，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.62：External TextBox Orientation Shadow Ledger
日期：2026-07-06

依据：v1.61 已把 external TextBox 可选 `sourceDirection`、`rotationDegrees` / `rotationDeg`、`linePolygons` 纳入 validator 和 Swift readiness，但 ready 后的 `externalTextBoxShadowOCRReport` 仍只透传少量 metadata，未把“竖排 / line polygon / rotation 需要 orientation-aware shadow path，而当前未执行”作为可审计 gate。`md/koharu研究/v1.38-current-gap-to-koharu.md` 明确 line polygon 和竖排方向主路径是 AITRANS 距 Koharu 的关键差距。

核心变更：

- `MangaOverlayExternalTextBoxShadowOCRCandidate`、`BlockSummary` 和 `Report` 新增 external TextBox orientation ledger：规范化 `sourceDirection`、orientation 分类、line polygon 数量、rotation blocks、vertical blocks、orientation shadow path needed / executed / not executed blocks 和 report verdict。
- `makeExternalTextBoxShadowOCRReport` 在选择 external TextBox 后记录方向元数据；当 TextBox 声明 vertical / linePolygons / non-zero rotation 时，写入 `orientationShadowPathNeededNotExecuted` blocker，阻止其进入 `wouldPromoteByExistingGateReportOnly`。
- `koharuArtifactConvergenceReport` 新增 `WI-external-textbox-orientation-shadow-path` 和 `G-external-textbox-orientation-shadow-path`，把缺失 orientation-aware shadow OCR 路径暴露到 convergence work item / gate。
- `1_ocr_probe_text.txt` external shadow OCR 明细和汇总追加 sourceDirection、orientation、linePolygons、rotation、orientation shadow needed / executed / verdict。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `git diff --check`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不执行 rotation / deskew / line polygon crop OCR，只记录 orientation shadow path 缺口并阻止 report-only promote 预览误判。
- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`。
- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.61：Koharu TextBox Direction Metadata Gate
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 明确 AITRANS 距 Koharu 的关键差距包括真实 TextBoxes、line polygon 和竖排方向主路径。v1.60 已拦住伪造来源，但 TextBox 可选 `sourceDirection`、`rotationDegrees` / `rotationDeg`、`linePolygons` 仍主要是透传或浅校验，真实四件套即使带坏方向元数据也可能进入 App readiness。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 TextBox 可选方向元数据校验：`sourceDirection` 必须落在 horizontal / vertical / vertical-rl / vertical-lr / unknown 等枚举内，`rotationDegrees` / `rotationDeg` 必须是有限数值且在 `[-360, 360]`，`linePolygons` 必须是非空 polygon 数组且点位在 `test/1.png` 原图范围内。
- Swift `externalArtifactReadinessReport` 使用同类校验，把 TextBox metadata 错误并入 coordinate validation，阻止离线 validator 和 App readiness 口径分叉。
- 新增 invalid fixture `md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid/`，并加入 CI extended validator matrix。
- artifact contract README、README、flow 和 test 文档同步说明：方向/旋转/line polygon 仍是可选字段，但提供时必须有效，供后续竖排 / line polygon shadow path 使用。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `AITRANS/Services/TranslationSessionStore.swift`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid/`
- `md/koharu研究/artifact_contract/README.md`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；只加强真实四件套方向元数据准入。
- 该版本不执行 rotation / deskew / line polygon crop OCR；下一步可在 `externalTextBoxShadowOCRReport` 中做 report-only vertical / line polygon shadow path。
- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### CI 维护：Build IPA archive artifact handoff
日期：2026-07-06

依据：`AITRANS - Build IPA` workflow 在 `Build using xcodebuild` job 已成功归档并上传 xcarchive，但 `Fakesign and package IPA` job 固定下载 `archive.xcarchive.tar.zip`，当 `IPA_PASSWORD` 为空或 secret 不可用导致上游实际上传 `archive.xcarchive.tar` 时，下游会报 `Artifact not found for name: archive.xcarchive.tar.zip`。

核心变更：

- `.github/workflows/build.yml` 将上游实际生成的 xcarchive artifact 文件名写入 step output，并作为 build job output 传给 package job。
- `Download xcarchive` 不再固定下载 `.zip`，而是使用 `needs.build.outputs.archive_artifact`。
- `Extract xcarchive` 同时支持 `.tar.zip` 和 `.tar`，保持有密码和无密码两种打包路径。

关键文件：

- `.github/workflows/build.yml`
- `update_log.md`

验证结果：

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml"); puts "yaml ok"'`
- `git diff --check`

未跑本机 Xcode build / 模拟器漫画探针；该维护只修 GitHub Actions 打包 artifact 交接，按规则交给云端 workflow 验证。

遗留事项：

- 该维护项不改变未加密 `AITRANS CI Results` 验收口径，不改变漫画探针质量，不追加 `metrics/version_history.csv`。

### v1.60：Koharu Artifact GeneratedBy Source Policy Gate
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 明确 P0 是真实 Koharu artifact 输入。v1.59 已强化注入后 App 侧消费证明，但 active package 仍需要防止“格式正确、来源却是 manual / fixture / Vision OCR / proxy / ground truth”的四件套通过到 shadow OCR。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 active manifest `generatedBy` source policy：`contractExampleOnly=false` 时必须声明真实 detector / segmenter 来源；缺失返回 `generatedByMissing`，命中 `manual`、`fixture`、`Vision OCR`、`pre-crop`、`line plan`、`BubbleMask proxy`、`SegmentMask proxy`、`ground truth`、`handwritten` 等禁用来源词返回 `forbiddenGeneratedBy`。
- Swift `externalArtifactReadinessReport` 使用同一 source policy，把 `generatedByMissing` / `forbiddenGeneratedBy` 阻塞在 `readyForShadowOCR` 之前，并给出 `stopUntilRealDetectorSourceDeclared`。
- 新增 invalid fixture `md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden/`，并加入 CI extended validator matrix。
- `README.md`、`md/flow/flow.md`、`md/test/test.md` 和 artifact contract README 同步说明：Agent C 验收真实四件套时必须核对 `generatedBy` 不是禁用来源。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `AITRANS/Services/TranslationSessionStore.swift`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden/`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `md/koharu研究/artifact_contract/README.md`
- `update_log.md`

验证结果：

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；只加强真实四件套来源准入。
- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### CI 维护：push 快验范围检测与 validator 精简
日期：2026-07-06

依据：人工要求精简当前测试，让云端 CI 加速，避免每次非 App 构建相关调整都跑完整 Xcode build 或完整 artifact invalid fixture 矩阵。

核心变更：

- `AITRANS CI Results` 新增变更范围检测：非 App 构建相关 push 可跳过 Xcode build，结果包保留 `xcodebuild.log` skip 说明，并在 manifest 写入 `xcodeBuildRequired`、`xcodeBuildSkippedReason`、`changedFilesPath`。
- Swift、Xcode 工程、`build-apple/`、资源、`test/` 素材、手动 `ci-fast/full` 或 Koharu artifact 注入仍强制 Xcode build。
- Xcode build 步骤增加 20 分钟上限，启用 `COMPILER_INDEX_STORE_ENABLE=NO` 并使用 quiet build log，减少默认云端耗时和日志体积。
- Koharu artifact validator 完整 invalid fixture 矩阵只在 validator、artifact contract 或 workflow 相关文件变化时运行；普通 push 只跑 valid example、active allow-missing 和 required-files 核心校验。
- `AGENTS.md`、`README.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md` 同步新 CI 口径；非 App 构建相关 build-skip 不能当作 Swift/Xcode 编译证据。

关键文件：

- `.github/workflows/ci-results.yml`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`

遗留事项：

- 该维护项不改变漫画探针质量，不追加 `metrics/version_history.csv`。
- Swift / Xcode 代码改动仍需要云端 Xcode build；手动探针仍需 `workflow_dispatch` 选择 `ci-fast` 或 `full`。

### v1.59：Injected Koharu Artifact App-Readiness Smoke
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 把 P0 定为真实 Koharu artifact 输入。此前 workflow 已能下载、校验、解压并 validator 检查四件套，但手动探针的 smoke 仍可能只证明 CI 注入步骤成功，未强制证明 App 内 `externalArtifactReadinessReport` 和 external TextBox shadow OCR 真消费到了 active artifact。

核心变更：

- 手动 `workflow_dispatch` 注入 Koharu artifact 且运行 `ci-fast/full` 时，`manga-probe.log` 的 post-export smoke 会读取 `output/probe_report.json`，强制核对 App 侧 `externalArtifactReadinessReport.readinessVerdict = readyForShadowOCR`、`activeArtifactsDirectory = true`、`contractExampleOnly = false`、`externalTextBoxesShadowOCRAllowed = true`，以及 manifest / TextBoxes / BubbleMask / SegmentMask 全部 found。
- 同一 smoke 会核对 `externalTextBoxShadowOCRReport.executed = true` 且 `candidateCount > 0`，避免只验证静态四件套存在却没有进入 shadow OCR。
- 同一 smoke 会核对 `koharuNativeArtifactContractDryRunReport.contractDryRunVerdict = activeArtifactsReadyForShadowOCR`，并确认 `dryRunOnly = true`、`activeExportAllowed = false`，保持 active artifact 写入边界。
- TXT smoke 新增注入路径 needle：`externalArtifacts: readiness=readyForShadowOCR`、`shadowOCRAllowed=true`、`nativeArtifactContractDryRunReport`、`nativeArtifactContractDryRunPreview`。
- `README.md`、`md/flow/flow.md`、`md/test/test.md` 同步说明：Agent C 不能只看 Release 下载、SHA、解压或 validator 日志，必须看 App 侧探针报告。

关键文件：

- `.github/workflows/ci-results.yml`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；只强化注入后云端验收证据。
- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.58：TextBox Segment Linkage Reaches Convergence
日期：2026-07-06

依据：v1.57 已把 TextBox -> SegmentMask linkage 传播到 bundle-lite 和 promotion gate，但最终 `koharuArtifactConvergenceReport` 仍需要显式消费这些 work item / gate，避免 bundle / promotion 层已经阻塞弱 linkage、收敛层却只按旧 artifact stage 给出下一步。

核心变更：

- `koharuArtifactConvergenceReport` 新增 bundle / promotion linkage review 聚合，把 v1.57 的 review / blocked blocks 继续传播到 convergence stage、block path、work item closure ledger 和 gate ledger。
- TextBoxes / SegmentMask convergence stage 会在 weak、fallback、rejected 或 wrong-bubble linkage 存在时输出 linkage-blocked status、affected blocks、decision signals 和 blocked work items。
- 逐块 artifact path 会把 `primaryStructuralBottleneck` 收束到 `textBoxSegmentMaskLinkage`，并优先给出 `auditTextBoxSegmentLinkageBeforeBundleReadiness` 或 `auditTextBoxSegmentLinkageBeforePromotion`。
- 新增 convergence work items / gates：`WI-koharu-native-artifact-bundle-lite-textbox-segment-linkage`、`WI-koharu-native-promotion-gate-lite-textbox-segment-linkage`、`G-koharu-convergence-bundle-lite-textbox-segment-linkage`、`G-koharu-convergence-promotion-lite-textbox-segment-linkage`。
- `1_ocr_probe_text.txt` 新增 `convergenceBundleTextBoxSegmentLinkage` 和 `convergencePromotionTextBoxSegmentLinkage` 摘要，云端 `ci-fast` smoke 会检查 JSON 字段和 TXT needle。
- 本轮仍是 report-only：不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不改变主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `.github/workflows/ci-results.yml`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。
- 真正的 Koharu 能力仍依赖真实 TextBoxes / BubbleMask / SegmentMask 四件套或模型级 detector 输出；native-lite linkage 只作为 report-only gate。

### v1.57：TextBox Segment Linkage Propagates to Bundle / Promotion
日期：2026-07-06

依据：v1.56 已在 SegmentMask refinement-lite 中记录 selected TextBox -> SegmentMask linkage，但 v1.45 bundle-lite 和 v1.46 promotion gate 仍主要看组件可用性，缺少把 rejected / fallback / wrong-bubble TextBox linkage 继续向 bundle readiness 和 promotion eligibility 传播的阻塞口径。

核心变更：

- `MangaKoharuNativeArtifactBundleLiteBlockLedger` 新增 `selectedTextBoxSegmentLinkVerdict`、`textBoxSegmentLinkageStatus`、`textBoxSegmentLinkageRisk`；报告新增 `textBoxSegmentLinkBreakdown` 和 `textBoxSegmentLinkageReviewBlocks`。
- `koharuNativeArtifactBundleLiteReport` 新增 `TextBoxSegmentMaskLinkage` consistency edge；fallback、weak、rejected 或 wrong-bubble linkage 会把 `primaryBlockingArtifact` 指向 `TextBoxes`，并把 `nextAction` 收束到 `auditTextBoxSegmentLinkageBeforeBundleReadiness`。
- `MangaKoharuNativePromotionBlockLedger` 新增 `textBoxSegmentLinkVerdict` 和 `textBoxSegmentLinkagePromotionStatus`；报告新增 `textBoxSegmentLinkBreakdown` 和 `textBoxSegmentLinkageBlockedBlocks`。
- `koharuNativePromotionGateLiteReport` 会把弱 linkage 写入 TextBoxes / SegmentMask promotion status、`mustNotPromoteReasons`、probe bottleneck 和 `auditTextBoxSegmentLinkageBeforePromotion`，防止 SegmentMask proxy 因局部可用而被误判可晋级。
- 新增 linkage work items / gates：`WI-koharu-native-artifact-bundle-lite-textbox-segment-linkage`、`G-native-artifact-bundle-lite-textbox-segment-linkage`、`WI-koharu-native-promotion-gate-lite-textbox-segment-linkage`、`G-native-promotion-gate-lite-textbox-segment-linkage`。
- `1_ocr_probe_text.txt` 新增 bundle / promotion 的 `textBoxSegmentLink=` 逐块摘要，以及报告级 `nativeArtifactBundleLiteTextBoxSegmentLink`、`nativePromotionTextBoxSegmentLink` 汇总。
- 本轮仍是 report-only：不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不改变主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`

遗留事项：

- 未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。
- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.56：TextBox -> SegmentMask Linkage Gate
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 TextBoxes / SegmentMask 差距：Koharu 是 TextBoxes 先产出，再约束 SegmentMask；AITRANS 已有 detector-lite 和 SegmentMask refinement-lite，但两者之间缺少可审计 linkage，容易出现 SegmentMask 看似可用、实际来自弱 TextBox / rejected TextBox / fallback bbox 的假闭环。

核心变更：

- `MangaKoharuNativeTextBoxDetectorLiteCandidate` 新增 `relatedBlockRelations[]`，记录 candidate 与 block 的 overlap、center containment、same-bubble 和 relation reason。
- `MangaKoharuNativeTextBoxDetectorLiteBlockLedger` 新增 best candidate relation 字段：coverage ratio、center-contained、same-bubble、candidate verdict 和 shadow OCR eligibility。
- `koharuNativeTextBoxDetectorLiteReport` 新增 `blockRelationBreakdown`。
- `MangaKoharuNativeSegmentMaskRefinementLiteCandidateLedger` 新增来源 TextBox linkage 字段：source TextBox verdict、shadow eligibility、block overlap、same-bubble、accepted-for-SegmentMask 和 link verdict。
- `MangaKoharuNativeSegmentMaskRefinementLiteBlockLedger` 新增 selected source TextBox candidate ID / link verdict。
- `koharuNativeSegmentMaskRefinementLiteReport` 新增 `textBoxSegmentLinkBreakdown`、`segmentFromAcceptedTextBoxCount`、`segmentFromRejectedTextBoxCount`、`segmentFromFallbackBBoxCount`。
- 新增 gates：`G-native-segmentmask-refinement-lite-textbox-linkage-audited` 和 `G-native-segmentmask-refinement-lite-no-rejected-textbox-silent-selection`。
- `1_ocr_probe_text.txt` 的 TextBox / SegmentMask native-lite summary 输出 candidate relation、selected link verdict、accepted/rejected/fallback 计数。
- 本轮不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不替换主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`

遗留事项：

- Linkage gate 仍只审计 native-lite proxy TextBoxes；真实能力需要 active Koharu TextBoxes / SegmentMask 四件套或模型级 detector 输出。
- 后续可把该 linkage 接入 `koharuNativeArtifactBundleLiteReport` / promotion gate 的 consistency edges，使 rejected / fallback TextBox 约束直接影响 artifact readiness。

### v1.55：BubbleMask Sibling Sprite Collision Preview
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P5 渲染方向和 Koharu renderer 的 same-bubble sprite collision 思路：v1.54 已检查单块 sprite bounds 是否落在 block-scoped safe rect 内，本轮继续 report-only 检查同一个 instance-lite bubble 下多个 rendered sprite bounds 是否互相重叠。

核心变更：

- `MangaKoharuNativeBubbleMaskInstanceLiteBlockLedger` 新增 `sameInstanceRenderSpriteOverlapCount` 和 `spriteSiblingCollisionPolicy`。
- `MangaKoharuNativeBubbleMaskInstanceLiteSiblingLedger` 新增 `renderSpriteOverlapCount` 和 `sameBubbleSpriteCollisionPolicy`。
- `koharuNativeBubbleMaskInstanceLiteReport` 新增 `spriteSiblingCollisionBreakdown`。
- `makeKoharuNativeBubbleMaskInstanceLiteReport` 现在对 same-instance sibling blocks 的 `renderNonTransparentBounds` 做 bounded overlap 计数，并输出 `sameInstanceSpritesSeparated`、`sameInstanceSpriteOverlapManualReview`、`missingRenderSpriteBounds` 或 `singleBlockOrNoInstance`。
- 新增 gate `G-native-bubblemask-instance-lite-sibling-sprite-collision`，只证明同 instance sprite collision 已进入账本，不写回 renderer。
- `1_ocr_probe_text.txt` 的 block / sibling / summary 行输出 sibling sprite overlap 和 collision policy。
- CI 维护：Koharu artifact archive 注入前会清空 `test/koharu_artifacts/`，避免残留 active 文件影响四件套 validator；测试文档同步 schema/path invalid fixtures 和 skip/探针结果包口径。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `.github/workflows/ci-results.yml`
- `README.md`
- `AGENTS.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`

遗留事项：

- 这仍是 bounds-level sibling collision preview，不是 Koharu renderer 的逐像素 alpha mask collision；真实能力需要 active BubbleMask 或 renderer-side sprite alpha gate。
- Rawls 子 agent 建议的 TextBox -> SegmentMask linkage gate 是下一轮高收益候选；本轮先收窄在 P5 sibling sprite collision，避免一次改动跨太多报告结构。

### v1.54：BubbleMask Block-Scoped Sprite Containment Preview
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P5 渲染方向和 Koharu renderer 的 mask collision 思路：先 report-only 检查 rendered sprite 非透明 bounds 是否落在所属 block 的 scoped safe rect 内，再考虑未来是否接入真实 renderer gate。

核心变更：

- `MangaKoharuNativeBubbleMaskInstanceLiteBlockLedger` 新增 `spriteBlockScopedSafeRectContainmentRatio`、`spriteContainedByBlockScopedSafeRect`、`spriteContainmentPolicy`。
- `koharuNativeBubbleMaskInstanceLiteReport` 新增 `spriteBlockScopedContainmentBreakdown`，保留旧 `spriteContainmentBreakdown` 的 instance-lite mask coverage 语义。
- v1.43 block ledger 现在用现有 `renderNonTransparentBounds` 和 `instanceLiteBlockScopedSafeRect` 计算 report-only containment ratio；`>= 0.995` 视为 `spriteWithinBlockScopedSafeRect`，缺 bounds / 缺 scoped safe rect 时明确记录 missing 状态。
- `1_ocr_probe_text.txt` 的 `nativeBubbleMaskInstanceLiteBlockLedger` 行输出 `spriteScopedContainmentRatio`、`spriteContainedByScopedSafeRect`、`spriteContainmentPolicy`；summary 输出 `nativeBubbleMaskInstanceLiteBlockScopedSpriteContainment`。
- 本轮不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不重新渲染，不写回主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField 报告、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`

遗留事项：

- 这仍是 bounds-level preview，不是 Koharu 逐像素 alpha mask collision；真实能力需要 active BubbleMask 或 renderer-side sprite alpha gate。
- 当前本地 `output/` 不含 v1.43+ 新字段；真实 JSON / TXT 结果以后续手动 GitHub Actions `ci-fast/full` 结果包为准。

### v1.53：BubbleMask Instance-Lite Sibling Safe Rect Policy
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P3 方向，以及 Koharu renderer 行为：同一个 bubble ID 下多个 text block 不应全部扩展到同一个最大 safe rect，否则会制造 sibling layout collision。

核心变更：

- `MangaKoharuNativeBubbleMaskInstanceLiteBlockLedger` 新增 `instanceLiteBlockScopedSafeRect` 和 `instanceLiteSafeRectPolicy`。
- `MangaKoharuNativeBubbleMaskInstanceLiteSiblingLedger` 新增 `blockScopedSafeRectOverlapCount` 和 `sameBubbleSafeRectPolicy`。
- `koharuNativeBubbleMaskInstanceLiteReport` 新增 `safeRectPolicyBreakdown`。
- 单 block instance 继续使用 v1.51 的 mask-derived instance safe rect；同 instance 多 block 时，report-only `instanceLiteBlockScopedSafeRect` 使用 block seed rect，避免把同一个最大 safe rect 复制给 siblings。
- `distanceFieldSafeRectFromInstanceLite` 在同 instance 多 block 场景写入 block-scoped rect，并把 `distanceFieldSafeRectSource` 标为 `nativeBubbleMaskInstanceLiteBlockScopedSeedRect`。
- 新增 gate `G-native-bubblemask-instance-lite-sibling-safe-rect-policy`，只证明 policy report-only，不写回主流程。
- `1_ocr_probe_text.txt` 的 block / sibling / summary 行新增 safe rect policy 和 block-scoped overlap 输出。
- 本轮不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不写回主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField 报告、renderer、`blockPassed`、失败分类或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`

遗留事项：

- 仍是 native-lite report-only 近似；真实 Koharu BubbleMask 仍需要 active artifact 或更强 detector 输出。
- 当前本地 `output/` 不含 v1.43+ 新字段；真实 JSON / TXT 结果以后续手动 GitHub Actions `ci-fast/full` 结果包为准。

### v1.52：SegmentMask Refinement-Lite Containment Ratio Gate
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P3 / SegmentMask 差距，以及子 agent 对 v1.44 的只读复核：已有 TextBox-constrained glyph mask，但 `maskContainedByTextBox` / `maskContainedByBubble` 只是弱布尔，不能表达 Koharu-like mask containment 证据。

核心变更：

- `MangaKoharuNativeSegmentMaskRefinementLiteCandidateLedger` / `BlockLedger` 新增 `maskContainedByTextBoxRatio`、`maskContainedByBubbleRatio`、`maskMajorityInstanceLiteID`、`maskMajorityBubbleID`、`maskMajorityCoverage`、`maskMajorityAgreement`。
- `koharuNativeSegmentMaskRefinementLiteReport` 新增 `maskMajorityAgreementBreakdown`。
- v1.44 正常候选在 `maskBBox` 生成后用 `rectContainmentRatio` 计算 TextBox / Bubble containment ratio；block ledger 的 `maskContainedByTextBox` / `maskContainedByBubble` 改为 ratio 阈值判定，而不是只看是否缺 constraint。
- majority agreement 使用 v1.43 instance-lite ledger / instance bbox / bubble ID 做 report-only 一致性判断；不重算真实 SegmentMask 像素多数票，不把它冒充真实 Koharu SegmentMask。
- `1_ocr_probe_text.txt` summary 追加 `nativeSegmentMaskRefinementLiteMajorityAgreement`，candidate / block ledger 行输出 containment ratio 与 majority agreement。
- 本轮仍不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不写回主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`

遗留事项：

- v1.52 仍是 native-lite report-only 近似；真实 SegmentMask 还需要 active artifact 或 detector 输出。
- 当前本地 `output/` 不含 v1.44+ 新字段；真实 TXT / JSON 输出以后续手动 GitHub Actions `ci-fast/full` 结果包为准。

### v1.51：BubbleMask Instance-Lite 像素派生 Safe Rect
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P3 方向，继续把 BubbleMask instance-lite 从 bbox 代理推向像素 ID mask / safe area 证据；本轮仍不接 active Koharu artifact、不新增 OCR / LLM / PNG、不替换主 OCR / 翻译 / 覆盖 / 通过判定。

核心变更：

- `koharuNativeBubbleMaskInstanceLiteReport` 的 `instanceLiteSafeRect` / `distanceFieldSafeRectFromInstanceLite` 不再由 instance bbox 简单内缩生成，改为从对应 instance 的源图像像素 offset 派生。
- 新增轻量 mask-derived safe rect 逻辑：先按 row / column run 估计到 mask 边界的内侧距离并做 erosion；若实例太薄无法形成 eroded core，则回退到高覆盖 row / column projection core。
- same-bubble sibling overlap 和逐块 block ledger 共用同一份 `instanceSafeRectsByID`，避免 block 与 sibling ledger 使用不同 safe rect 口径。
- block decision signals 新增 `safeRectSource = maskDerivedInstanceLitePixels` / `nil`，保持 schema 不变。
- 所有结果仍是 report-only；不写回 `safeLayoutRect`、DistanceField 报告、renderer、OCR 输入、翻译输入、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `git diff --check`

遗留事项：

- 该 safe rect 仍是 AITRANS native-lite report-only 近似，不代表真实 Koharu `BubbleMask` distance field 已接入。
- 真实 P3 收益仍需手动 GitHub Actions `ci-fast/full` 结果包检查 `koharuNativeBubbleMaskInstanceLiteReport` 的 block / sibling ledger。

### v1.50：Detector-Lite 竖排 Rotation Shadow OCR
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P2 方向，向 Koharu 的竖排 / 方向处理能力靠近；本轮不新建 active artifact、不新增 LLM、不替换主 OCR / 翻译 / 覆盖 / 通过判定。

核心变更：

- `koharuNativeTextBoxDetectorLiteShadowOCRReport` 复用既有 `directionHint` / `rotationApplied` 字段，对 v1.39 `verticalCandidate` 做有上限的 `[0,90]` crop OCR shadow 对照。
- `verticalCandidate` crop OCR 使用受限 `ja-JP/ja/en-US/en` Vision language profile；横排候选保留默认 0 度 / 英语路径。
- v1.40 候选选择按当前 block 与 bbox 的 overlap / center containment 优先于全局 detector score，降低 same-bubble sibling 共享错误高分候选的风险。
- full 模式每块最多跑 2 个候选时，block ledger 的 `selectedCandidateID` 现在记录本块 report-only 最佳 shadow OCR 候选，v1.41 refinement 跟随该最佳 ID。
- rotation 对照仍按候选计入既有每块选择预算：`ci-fast` 每块最多 1 个 detector-lite 候选、`full` 每块最多 2 个；不会新增候选池或 promotion 路径。
- 旋转结果选择只使用无真值 OCR 质量分和当前文本 word preservation；ground truth 仍只写 evaluation signals，不参与候选选择、OCR 执行、gate 或 nextAction。
- 新增 gate `G-native-textbox-detector-lite-shadow-ocr-vertical-rotation-budget`，记录 vertical candidate 数、实际采用 rotation 数和 rotation breakdown。
- `1_ocr_probe_text.txt` summary 新增 `nativeTextBoxDetectorLiteShadowOCRRotation`，每个 `nativeTextBoxDetectorLiteShadowOCRCandidate` 输出 `rotation=`。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`

验证计划：

- 本地运行 Swift parse、workflow YAML parse、`git diff --check`、JSON smoke 和 Koharu artifact validator smoke。
- 本轮不跑本地 Xcode build 或模拟器漫画探针；真实 v1.50 `rotationApplied` 结果以手动 GitHub Actions `ci-fast/full` 输出为准。

遗留事项：

- 当前 `test/1.png` 是英文横排样例，可能不会稳定触发大量 `verticalCandidate`；P2 真正收益仍需要竖排日语样例或云端结果包证明。
- 该路径仍是 detector-lite shadow OCR，不代表真实 Koharu TextBoxes / OCR 已接入，也不替换主流程。

### v1.49：Detector-Lite 每 Bubble 多候选池
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P1 要求，在没有真实 Koharu artifact 时继续改进 native TextBoxes detector-lite；本轮仍不伪造 active artifact、不使用 Vision OCR 文本 / ground truth / pre-crop / line / TextRegion crop 结果生成候选，不改变主 OCR、翻译、覆盖或通过判定。

核心变更：

- `koharuNativeTextBoxDetectorLiteReport` 从每个 bubble 单一暗连通域 union 候选，改为每个 bubble 有上限的预 OCR candidate pool：最多 4 个 component-cluster TextBox 候选 + 1 个 diagnostic union fallback。
- component-cluster 候选按 bubble 内连通域 gap / projection split 生成；union fallback 仅用于诊断，固定 `shadowOCREligible = false`，避免在 v1.40 `ci-fast` 每块 1 个候选预算下抢占 shadow OCR。
- detector-lite candidate ID 改为稳定零填充序号 `NTBDL-<bubbleID>-<NN>`，并按 bubble、shadow OCR eligibility、score、ID 稳定排序。
- 多候选到 current block 的关系改为 bbox overlap / center containment 优先；component-cluster 无匹配时才回退同 bubble 最近块，避免同 bubble sibling 全部共享同一高分候选。
- `G-native-textbox-detector-lite-candidate-pool-cap` gate 记录候选池上限，文档和测试口径同步要求 `bubbleLedgerCount == evaluatedBubbleCount`、candidate pool 有上限且 union fallback 不参与 shadow OCR。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`

验证计划：

- 本地运行 Swift parse、workflow YAML parse、`git diff --check`、JSON smoke 和 Koharu artifact validator valid / invalid / active-missing smoke。
- 本轮不跑本地 Xcode build 或模拟器漫画探针；完整 build 和真实 `ci-fast/full` 探针仍交给 GitHub Actions。

遗留事项：

- 多候选池仍是 proxy-not-real Koharu TextBoxes；真实晋级仍需要 Release 注入真实 Koharu artifact archive 并通过 active artifact validator。
- 手动 `ci-fast/full` 才会运行 v1.40/v1.41 shadow OCR / refinement OCR；push 默认快验仍保持 probe skip 以控制云端耗时。

### v1.48 Koharu active artifact CI intake 与契约硬化
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P0 要求从 report-only 转向真实 `test/koharu_artifacts/` 输入。本轮不伪造 active artifact、不复制 examples、不使用 Vision OCR / pre-crop / line / proxy / ground truth / 手写框生成四件套。

核心变更：

- `AITRANS CI Results` 新增手动 `workflow_dispatch` 输入 `koharu_artifact_release_tag`、`koharu_artifact_asset`、`koharu_artifact_sha256`、`koharu_artifact_required`。
- 当提供真实 Koharu artifact archive 时，CI 在 Xcode build 前从 Release 下载、校验 SHA256、解压，并只复制 `1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json` 到 `test/koharu_artifacts/`，随后运行 validator。`koharu_artifact_required=true` 时注入或 validator 失败会阻断工作流。
- `ci-artifact-manifest.json` 新增 Koharu artifact 注入来源、required 状态、注入结果、Release tag、asset、SHA 和注入日志路径，Agent C 可区分缺 artifact 阻塞路径与真实 artifact 注入路径。
- `scripts/validate-koharu-artifacts.py` 将 `schemaVersion` 缺失 / 不匹配变成 readiness 阻塞，`schemaVersion` 必须为 `aitrans.koharu_artifact_contract.v1`。
- Python validator 和 Swift readiness 都拒绝 manifest artifact path 使用绝对路径或 `..` 逃逸 active artifact root，避免 active manifest 指向目录外文件。
- 新增 invalid fixtures：`schema_mismatch` 和 `path_escape`，并加入 CI 静态检查 `--expect-fail`。

关键文件：

- `.github/workflows/ci-results.yml`
- `scripts/validate-koharu-artifacts.py`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `md/flow/flow.md`
- `README.md`

验证结果：

- 本轮应通过轻量检查：Swift parse、workflow YAML parse、`git diff --check`、JSON parse、validator valid / invalid / active missing。
- 本轮不跑本地 Xcode build 或模拟器漫画探针；完整 build 和 `ci-fast/full` 仍交给 GitHub Actions。

遗留事项：

- 当前仓库默认仍没有真实 active `test/koharu_artifacts/`，因此不能声称 `externalTextBoxShadowOCRReport.executed = true` 已验证。
- 下一步若有真实 Koharu archive，手动 `workflow_dispatch` 填写 Koharu artifact 输入并选择 `ci-fast`，验收 `koharuArtifactValidation.verdict = readyForShadowOCR`、Swift readiness ready、external shadow OCR executed。
- 若短期仍无真实 artifact，下一步按 v1.38 P1 改进 native TextBoxes detector-lite：每个 bubble 生成多个 OCR 前 TextBox 候选，而不是将全部暗连通域 union 成单一大框。

### 维护：AITRANS CI Results 默认快验加速
日期：2026-07-06

本轮根据 Agent X 目标和云端 CI 速度要求，精简默认云端验证路径；不修改漫画探针算法、不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`。

核心变更：

- `AITRANS CI Results` 增加 `concurrency`，同一 ref 新 run 会取消旧 run，避免连续 push 堆积 macOS runner。
- `push` 到 `smalldata_test` / `codeb/**` 默认 `probe_mode=skip`，只跑静态检查、Xcode build、manifest 和未加密结果包；不下载 GGUF、不创建模拟器、不安装 App、不跑漫画探针。
- 手动 `workflow_dispatch` 仍可选择 `ci-fast` 或 `full` 跑真实 simulator + Local GGUF 漫画探针。
- `probe_mode=skip` 时 JUnit 把 GGUF model / simulator / manga probe 跳过视为快验成功，并在 manifest 写 `probeSkippedReason = default_push_fast_ci_or_manual_skip` 与 `modelSetupSkippedReason = probe_mode_skip_fast_ci_does_not_need_model`。
- 手动探针模式下，GGUF cache 只在 SHA 校验成功后保存；build 或模型校验失败时不再继续定位 App 或启动模拟器。
- 手动探针导入模型到 App sandbox 时优先使用 APFS clone `cp -c`，失败再回退普通复制。
- 手动探针新增 `probeNoProgressTimeoutSeconds`，`ci-fast` 180 秒、`full` 300 秒内若没有生成 progress 文件会提前失败，避免 App 未启动时等满总超时。

关键文件：

- `.github/workflows/ci-results.yml`
- `README.md`
- `AGENTS.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `update_log.md`

验证计划：

- 本地运行 YAML 解析、`git diff --check` 和现有 JSON smoke。
- 未跑本机 build / 探针；push 后默认云端快验应只检查静态项和 Xcode build。需要漫画探针结果时手动触发 `workflow_dispatch` 的 `ci-fast` 或 `full`。

遗留事项：

- 手动 `ci-fast` 内部仍会运行 v1.40 / v1.41 detector-lite shadow OCR / refinement OCR 等额外 Vision crop OCR；若后续还嫌手动探针慢，需要在 Swift run options 中新增更细粒度门控并同步 v1.29-v1.46 验收口径。

### v1.47：Koharu Native Artifact Contract Dry-Run 四件套准入干跑
日期：2026-07-06

依据：Agent X 继续沿 `md/koharu研究/v1.38-current-gap-to-koharu.md` 推进，避免继续只堆抽象报告，转向真实 Koharu artifact 四件套准入的机器可验 dry-run。本轮修改 Swift 探针报告模型、TXT 摘要和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeArtifactContractDryRunReport`，在 v1.46 `koharuNativePromotionGateLiteReport` 后生成。
- 报告把 v1.46 `candidateExportPreviews[]` 映射到 active 四件套 contract：`test/koharu_artifacts/1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`。
- 报告写出 `sourceImage = test/1.png`、`coordinateSpace = originalImageTopLeftPixels`、`activeInputDirectory`、`examplesDirectory`、required files、required fields、missing fields、forbidden source breakdown、validator commands 和 gate ledger。
- `koharuArtifactConvergenceReport` 现在把 v1.47 纳入 `referenceReports`、`workItemLedger` 和 `gateLedger`，用 `WI-koharu-native-artifact-contract-dry-run` / `G-koharu-native-artifact-contract-dry-run-executed` 明确记录真实四件套 intake 仍阻塞或 ready。
- `activeExportAllowed = false`、`dryRunOnly = true`，native-lite / proxy preview 只做 contract dry-run，不创建、复制或修改 active `test/koharu_artifacts/`。
- `1_ocr_probe_text.txt` 新增 dry-run summary、required file、preview、gate、validator command 和 forbidden active source 摘要。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证计划：

- 本地运行 Swift parse、YAML 解析、`git diff --check`、JSON smoke 和 Koharu artifact validator 正反例。
- 云端手动 `workflow_dispatch` 的 `ci-fast` 应证明 `koharuNativeArtifactContractDryRunReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`requiredFileCount >= 4`、`contractGateCount >= 6`、`dryRunOnly = true`、`activeExportAllowed = false`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`，`koharuArtifactConvergenceReport.referenceReports` 包含该报告，`workItemLedger` / `gateLedger` 包含 `WI-koharu-native-artifact-contract-dry-run` / `G-koharu-native-artifact-contract-dry-run-executed`，且 `1_ocr_probe_text.txt` 包含 `nativeArtifactContractDryRunRequiredFile` 和 `nativeArtifactContractDryRunPreview`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.47 新字段；以 PR 后云端结果包为准。
- v1.47 仍不代表真实 Koharu `TextBoxes` / `BubbleMask` / `SegmentMask` 已接入；下一步仍需要真实 active 四件套或更强 detector 输出通过 validator。

### v1.46：Koharu Native Promotion Gate-Lite 探针驱动晋级门槛
日期：2026-07-03
依据：`md/prompt/v1（漫画探针）/v1.46（KoharuNativePromotionGateLite探针驱动晋级门槛）.md`。本轮修改 Swift 探针报告模型、native-lite promotion gate 聚合账本、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativePromotionGateLiteReport`，在 v1.45 Native Artifact Bundle-Lite 后、最终 convergence 刷新前生成。
- 报告只消费 final blocks、diagnostics、v1.39-v1.45 native-lite reports、RenderSprite fit、Render Regression Lock、Translation Model Floor、clean text diagnostic 和 external artifact readiness。
- 每个 final block 输出 report-only promotion ledger，覆盖 TextBoxes / BubbleMask / SegmentMask / OcrText / Translations / RenderedSprites / FinalRender 的晋级状态、primary blocking artifact、probe bottleneck、promotion eligibility、nextAction 和 `mustNotPromoteReasons`。
- 新增 canonical stage gates，覆盖 TextBoxes、BubbleMask、SegmentMask、OcrText、Translations、RenderedSprites、FinalRender 和 ExternalArtifacts。
- 新增 `nativeCandidateExportPreview`，只在 JSON / TXT 中预览未来 AITRANS-native candidate artifact 可能需要的字段、来源、bbox、风险和 validator 要求；本轮不创建、不复制、不修改 active `test/koharu_artifacts/`。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativePromotionGateLiteReport`；convergence 新增 `WI-koharu-native-promotion-gate-lite` 和 `G-koharu-native-promotion-gate-lite-executed`。
- `1_ocr_probe_text.txt` 新增 promotion gate summary、stage gate、逐块 block ledger、candidate export preview 和 work item 摘要。
- 本轮不新增 OCR / LLM / PNG，不更换模型，不接 active artifact，不改变主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.46（KoharuNativePromotionGateLite探针驱动晋级门槛）.md`

验证计划：

- 本轮 Agent B 本地运行轻量 Swift 语法检查、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativePromotionGateLiteReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`stageGateCount >= 8`、`candidateExportPreviewCount >= 1` 或明确 blocked / warning reason、`workItemCount >= 1`、`gateCount >= 8`、`promotionGateLite = true`、`nativePromotionPreviewOnly = true`、所有 proxy-not-real 边界为 true、`externalArtifactsRequiredForThisReport = false`、`groundTruthUsedForDecision = false`，核心 breakdown 非空或上游缺失时明确 warning / blocked gate，convergence 包含 v1.46 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、stage gate、逐块 promotion ledger、candidate preview 和 work item。

遗留事项：

- 旧仓库根 `output/` 不含 v1.46 新字段；以 PR 后云端结果包为准。
- v1.46 仍是 native promotion gate-lite report-only 晋级门槛层，不代表真实 Koharu `TextBoxes` / `BubbleMask` / `SegmentMask` / `OcrText` / `RenderedSprites` 已接入，也不代表 OCR 或翻译质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.45：Koharu Native Artifact Bundle-Lite 结构一致性闭环
日期：2026-07-03
依据：`md/prompt/v1（漫画探针）/v1.45（KoharuNativeArtifactBundleLite结构一致性闭环）.md`。本轮修改 Swift 探针报告模型、native-lite artifact bundle 聚合账本、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeArtifactBundleLiteReport`，在 v1.44 SegmentMask refinement-lite 后、最终 convergence 刷新前生成。
- 报告只消费 final blocks、v1.39-v1.42 detector-lite / shadow OCR / refinement / closed-loop、v1.43 BubbleMask instance-lite、v1.44 SegmentMask refinement-lite、RenderSprite fit、Render Regression Lock、Translation Model Floor、external artifact readiness 和 diagnostics。
- 每个 final block 组装 report-only bundle：selected TextBox / Bubble / Segment component、OCR evidence、translation route、render evidence、artifact consistency verdict、primary blocking artifact 和 nextAction。
- 新增逐块 consistency edges，覆盖 TextBoxWithinBubble、SegmentMaskWithinTextBox、SegmentMaskWithinBubble、FinalOCRBBoxAlignedWithTextBox、SameBubbleSiblingMaskNonOverlap、SeamOrSplitRiskExplainsConflict、RenderSpriteContainedByBundleSafeArea 和 ModelFloorSeparatesGeometryFromTranslation。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeArtifactBundleLiteReport`；convergence 新增 `WI-koharu-native-artifact-bundle-lite` 和 `G-koharu-native-artifact-bundle-lite-executed`。
- `1_ocr_probe_text.txt` 新增 bundle-lite summary、逐块 block ledger、consistency edge 和 work item 摘要。
- 本轮不新增 OCR / LLM / PNG，不更换模型，不创建或接入 active Koharu artifact，不改变主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.45（KoharuNativeArtifactBundleLite结构一致性闭环）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse` 轻量 Swift 语法检查、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeArtifactBundleLiteReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`bundleLedgerCount == totalBlocksDetected`、`consistencyEdgeCount >= totalBlocksDetected`、`workItemCount >= 1`、`gateCount >= 8`、`nativeBundleLite = true`、TextBoxes / BubbleMask / SegmentMask proxy 边界为 true、`externalArtifactsRequiredForThisReport = false`、`groundTruthUsedForDecision = false`，核心 breakdown 非空或上游缺失时明确 warning / blocked gate，convergence 包含 v1.45 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、逐块 block ledger、consistency edge 和 work item。

遗留事项：

- 旧仓库根 `output/` 不含 v1.45 新字段；以 PR 后云端结果包为准。
- v1.45 仍是 native artifact bundle-lite report-only 结构一致性闭环，不代表真实 Koharu `TextBoxes` / `BubbleMask` / `SegmentMask` / `RenderedSprites` 已接入，也不代表 OCR 或翻译质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.44：Koharu Native SegmentMask Refinement-Lite 文字像素掩码影子复刻
日期：2026-07-03
依据：`md/prompt/v1（漫画探针）/v1.44（KoharuNativeSegmentMaskRefinementLite文字像素掩码影子复刻）.md`。本轮修改 Swift 探针报告模型、TextBox 约束文字像素 mask refinement-lite 账本、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeSegmentMaskRefinementLiteReport`，在 v1.43 instance-lite BubbleMask 之后、最终 convergence 刷新前生成。
- 报告只使用源图像像素、detector-lite TextBox 候选、final blocks、v1.43 instance-lite BubbleMask、现有 glyph / SegmentMask proxy、render lock 和翻译失败分类，生成 TextBox-constrained glyph pixel mask 的 candidate / block / sibling / gate 账本。
- `groundTruthUsedForDecision = false`，ground truth 只进入 evaluation signals；像素阈值、TextBox 选择、mask 生成、route、nextAction、verdict 和 gate 都不使用真值。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeSegmentMaskRefinementLiteReport`；convergence 新增 `WI-koharu-native-segmentmask-refinement-lite` 和 `G-koharu-native-segmentmask-refinement-lite-executed`。
- `1_ocr_probe_text.txt` 新增 SegmentMask refinement-lite report summary、candidate ledger、逐块 block ledger 和 same-bubble sibling ledger 摘要。
- 本轮不新增 OCR / LLM / PNG，不更换模型，不创建 active Koharu artifact，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.44（KoharuNativeSegmentMaskRefinementLite文字像素掩码影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `git diff --check`、JSON 解析、Koharu validator smoke，并用轻量 Swift parse 检查新增 Swift 语法。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeSegmentMaskRefinementLiteReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`candidateLedgerCount >= totalBlocksDetected`、`gateCount >= 8`、`nativeRefinementLite = true`、`proxyNotRealKoharuSegmentMask = true`、`usesSourceImagePixels = true`、`usesTextBoxConstraints = true`、`usesBubbleMaskConstraints = true`、`groundTruthUsedForDecision = false`，核心 breakdown 非空或像素证据不足时明确 blocked / warning gate，convergence 包含 v1.44 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate ledger、逐块 block ledger 和 sibling ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.44 新字段；以 PR 后云端结果包为准。
- v1.44 仍是 native SegmentMask refinement-lite report-only 影子复刻，不代表真实 Koharu `SegmentMask` / `TextBoxes` / `BubbleMask` 已接入，也不代表 OCR 或翻译质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.43：Koharu Native BubbleMask Instance-Lite 像素实例掩码影子复刻
日期：2026-07-03
依据：`md/prompt/v1（漫画探针）/v1.43（KoharuNativeBubbleMaskInstanceLite像素实例掩码影子复刻）.md`。本轮修改 Swift 探针报告模型、像素 instance-lite BubbleMask 账本、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeBubbleMaskInstanceLiteReport`，在 v1.42 detector-lite closed-loop 之后、最终 convergence 刷新前生成。
- 报告只使用源图像内容裁切区像素、现有 bubble geometry、final blocks、glyph / SegmentMask proxy、BubbleIndex / DistanceField / seam / RenderSprite fit、detector-lite closed-loop 和 render lock 证据，生成近白连通域 instance-lite ID mask 账本。
- 输出 `instances[]`、`blockLedgers[]`、`siblingLedgers[]`、`adjacencyLedgers[]` 和 `gateLedger[]`，逐块记录 current bubble、instance-lite majority、safe rect 对照、sprite containment、translation failure route、detector-lite route、primary bottleneck 和 nextAction。
- `groundTruthUsedForDecision = false`，ground truth 只进入 evaluation signals；mask 生成、majority assignment、route、nextAction、verdict 和 gate 都不使用真值。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeBubbleMaskInstanceLiteReport`；convergence 新增 `WI-koharu-native-bubblemask-instance-lite` 和 `G-koharu-native-bubblemask-instance-lite-executed`。
- `1_ocr_probe_text.txt` 新增 instance-lite report summary、实例账本、逐块 majority assignment、sibling / adjacency 和 convergence v1.43 work item / gate 摘要。
- 本轮不新增 OCR / LLM / PNG，不更换模型，不创建 active Koharu artifact，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.43（KoharuNativeBubbleMaskInstanceLite像素实例掩码影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `git diff --check`、JSON 解析、Koharu validator smoke，并用轻量 Swift parse 检查新增 Swift 语法。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeBubbleMaskInstanceLiteReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`gateCount >= 8`、`nativeInstanceLite = true`、`proxyNotRealKoharuBubbleMask = true`、`usesSourceImagePixels = true`、`groundTruthUsedForDecision = false`、核心 breakdown 非空或像素证据不足时明确 blocked / warning gate，convergence 包含 v1.43 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、instance ledger、逐块 block ledger、sibling 和 adjacency ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.43 新字段；以 PR 后云端结果包为准。
- v1.43 仍是 native BubbleMask instance-lite report-only 影子复刻，不代表真实 Koharu `BubbleMask` / `TextBoxes` / `SegmentMask` 已接入，也不代表 OCR 或翻译质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.42：Native TextBox Detector-Lite 闭环裁决与结构路由
日期：2026-07-03
依据：`md/prompt/v1（漫画探针）/v1.42（NativeTextBoxDetectorLite闭环裁决与结构路由）.md`。本轮修改 Swift 探针报告模型、detector-lite 闭环裁决与结构路由账本、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeTextBoxDetectorLiteClosedLoopReport`，在 v1.41 refinement 之后、最终 convergence 刷新前生成。
- 报告消费 v1.39 detector-lite、v1.40 shadow OCR、v1.41 refinement、final blocks、BubbleMask / SegmentMask proxy、翻译失败分类、Translation Model Floor、Render Regression Lock 和 external artifact readiness，产出 candidate family ledger、逐块 closed-loop route、stoplist、full-probe review、真实 artifact 需求、模型地板和 render lock 路由。
- route / nextAction / gate / candidate family verdict 只使用 ground-truth-free decision signals；ground truth 只写入 evaluationSignals。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeTextBoxDetectorLiteClosedLoopReport`；convergence 新增 `WI-koharu-native-textbox-detector-lite-closed-loop-router` 和 `G-koharu-native-textbox-detector-lite-closed-loop-router-executed`。
- `1_ocr_probe_text.txt` 新增 detector-lite closed-loop report summary、candidate family rollup 和逐块 `nativeTextBoxDetectorLiteClosedLoopBlockLedger`。
- 本轮不新增 OCR / LLM / PNG，不更换模型，不接入外部 artifact，不改变主 OCR、翻译输入、覆盖图、`finalTextUsedForTranslation`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.42（NativeTextBoxDetectorLite闭环裁决与结构路由）.md`

验证计划：

- 本轮 Agent B 本地运行 `git diff --check`、JSON 解析、Koharu validator smoke，并用轻量 Swift 解析检查新增 Swift 语法。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeTextBoxDetectorLiteClosedLoopReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`candidateFamilyCount == totalBlocksDetected`、`gateCount >= 8`，核心 route / verdict / bottleneck / nextAction breakdown 非空或上游缺失时明确 `blockedByMissingUpstreamReports`，convergence 包含 v1.42 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate family 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.42 新字段；以 PR 后云端结果包为准。
- v1.42 仍是 detector-lite report-only 路由，不代表真实 Koharu TextBoxes / BubbleMask / SegmentMask 已接入，也不代表模型质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.41：Native TextBox Detector-Lite 闭环二次候选与 Refinement Shadow OCR
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.41（NativeTextBoxDetectorLite闭环二次候选与RefinementShadowOCR）.md`。本轮修改 Swift 探针报告模型、detector-lite refinement shadow OCR 链路、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeTextBoxDetectorLiteRefinementReport`，执行顺序在 v1.40 `koharuNativeTextBoxDetectorLiteShadowOCRReport` 之后、最终 `koharuArtifactConvergenceReport` refresh 之前。
- target selection 只使用 v1.40 shadow OCR outcome、block failure category、模型地板、渲染锁和 detector-lite relation 等 ground-truth-free 信号；ground truth 只写入 evaluation signals。
- refined candidate bbox 只从 v1.39 `nativeDetectorLite` 父候选出发，用 source image 暗像素 envelope、projection band、directional padding 和 bubble ID 一致时的保守 bubble clip 二次收紧。
- `ci-fast` 总 refinement OCR 预算限制为 `<= min(6,totalBlocksDetected)`，每块最多 1 个；`full` 每块最多 2 个且仍有总上限。
- candidate / block ledger 输出 base bbox、refined bbox、refinement strategy、target reason、OCR raw / normalized text、quality delta vs current / detector-lite shadow、word preservation、evaluation-only ground truth similarity delta、outcome 和 report-only rejection reasons。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeTextBoxDetectorLiteRefinementReport`；convergence 新增 `WI-koharu-native-textbox-detector-lite-refinement` 和 `G-koharu-native-textbox-detector-lite-refinement-executed`。
- `1_ocr_probe_text.txt` 新增 detector-lite refinement report summary、refined candidate ledger 和逐块 `nativeTextBoxDetectorLiteRefinementBlockLedger`。
- 本轮不新增 LLM 调用，不更换模型，不接入外部 artifact，不改变主 OCR、翻译输入、覆盖图、`finalTextUsedForTranslation`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.41（NativeTextBoxDetectorLite闭环二次候选与RefinementShadowOCR）.md`

验证计划：

- 本轮 Agent B 本地运行 `git diff --check`、JSON 解析、Koharu validator smoke，并用轻量 Swift parse 检查新增 Swift 语法。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeTextBoxDetectorLiteRefinementReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`ocrExecutedCount <= min(6,totalBlocksDetected)`、`gateCount >= 8`，核心 breakdown 非空或无 target 时明确 blocked ledger，convergence 包含 v1.41 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate ledger 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.35-v1.41 新字段；以 PR 后云端结果包为准。
- v1.41 仍是 detector-lite refinement shadow-only，不代表真实 Koharu TextBoxes / BubbleMask / SegmentMask 已接入，也不代表模型质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.40：Native TextBox Detector-Lite Shadow OCR 评估闭环
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.40（NativeTextBoxDetectorLiteShadowOCR评估闭环）.md`。本轮修改 Swift 探针报告模型、受限 detector-lite crop OCR 评估链路、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeTextBoxDetectorLiteShadowOCRReport`，只消费 v1.39 `koharuNativeTextBoxDetectorLiteReport.candidates` 中 `shadowOCREligible = true` 的 `nativeDetectorLite` 候选。
- `ci-fast` 每块最多执行 1 个 detector-lite bbox OCR，`full` 每块最多 2 个；候选选择只使用 detector-lite score、bubble / glyph / block 关系、direction hint 和 ledger 信号。
- candidate ledger 输出 source candidate、bbox、crop padding、scale、OCR raw / normalized text、empty / failed / succeeded、word preservation、quality delta、evaluation-only ground truth similarity delta、outcome 和 report-only rejection reasons。
- block ledger 覆盖所有最终 blocks，记录 selected candidate、shadow OCR text、当前 / shadow OCR quality、better / worse / same / empty / failed / notSelected、primary bottleneck、nextAction 和 whyNotPromoted。
- 报告明确 `groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`、`proxyNotRealKoharuOCR = true`；ground truth 只进 evaluation signals。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeTextBoxDetectorLiteShadowOCRReport`；convergence 新增 `WI-koharu-native-textbox-detector-lite-shadow-ocr` 和 `G-koharu-native-textbox-detector-lite-shadow-ocr-executed`。
- `1_ocr_probe_text.txt` 新增 detector-lite shadow OCR report summary、candidate OCR ledger 和逐块 `nativeTextBoxDetectorLiteShadowOCRBlockLedger`。
- 本轮不新增 LLM 调用，不更换模型，不使用 ground truth 决定候选、排序、OCR 执行、nextAction 或 gate，不改变主 OCR、翻译输入、覆盖图、`finalTextUsedForTranslation`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.40（NativeTextBoxDetectorLiteShadowOCR评估闭环）.md`

验证计划：

- 本轮 Agent B 本地运行 `git diff --check`、JSON 解析、Koharu validator smoke，并用轻量 Swift 解析检查新增 Swift 语法。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeTextBoxDetectorLiteShadowOCRReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`selectedCandidateCount <= totalBlocksDetected`、`ocrExecutedCount == selectedCandidateCount`、`gateCount >= 8`，核心 breakdown 非空或无候选时明确 blocked ledger，convergence 包含 v1.40 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate ledger 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.35-v1.40 新字段；以 PR 后云端结果包为准。
- shadow OCR 可能全部 empty / worse；这属于本轮要显式记录的评估结果，不能静默跳过，也不能因此替换主流程。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.39：Koharu Native TextBox Detector-Lite 预 OCR 影子复刻
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.39（KoharuNativeTextBoxDetectorLite预OCR影子复刻）.md`。本轮修改 Swift 探针报告模型、像素 / 几何候选层、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeTextBoxDetectorLiteReport`，只用 source image 像素、bubble geometry、BubbleMask proxy 和 glyph / SegmentMask proxy 生成 OCR 前 `nativeDetectorLite` TextBox 候选。
- 候选输出 `candidateID`、bbox、sourceBubbleID、directionHint、dark pixel density、connected component count、projection peak count、bubble coverage、glyph overlap、score、verdict、shadow OCR eligibility、matched / related block indexes、decision / evaluation signals 和 rejection reasons。
- 新增 block / bubble / gate ledger，逐块记录 best candidate、coverage verdict、bubble assignment risk、segment evidence、OCR input risk、model floor、render lock、primary bottleneck 和 next action；逐 bubble 记录 coverage、split / sibling risk 和 real BubbleMask 需求。
- 报告明确 `groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`、`externalArtifactsRequiredForThisReport = false`；ground truth 只进入 evaluation signals。
- 默认不执行 detector-lite shadow OCR，不新增 LLM 调用；不使用 Vision OCR 文本、`test/1.ground_truth.json`、pre-crop plan、line plan 或 TextRegion crop 结果生成 / 排序候选。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeTextBoxDetectorLiteReport`；convergence 新增 `WI-koharu-native-textbox-detector-lite` 和 `G-koharu-native-textbox-detector-lite-executed`。
- `1_ocr_probe_text.txt` 新增 detector-lite report summary、candidate ledger、bubble ledger 和逐块 `nativeTextBoxDetectorLiteBlockLedger`。
- 本轮不改变主 OCR、whole-page / bubble-first 融合、post-fusion cleanup、翻译输入、translation prompt、模型、`blockPassed`、失败分类、覆盖绘制、`safeLayoutRect`、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.39（KoharuNativeTextBoxDetectorLite预OCR影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeTextBoxDetectorLiteReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`candidateCount >= 1`、`gateCount >= 8`，breakdown 非空，`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`，convergence 包含 detector-lite reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate ledger、bubble ledger 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.35-v1.39 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.38：Koharu RenderSprite 排版适配影子复刻
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.38（KoharuRenderSprite排版适配影子复刻）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

退回修复：

- PR #28 云端 run `28571459833` 在 Xcode build 阶段失败，`xcodebuild.log` 指向 `MangaOverlayProbeService.swift` 中 `MangaKoharuRenderSpriteLayoutCandidateLedger(...)` 大表达式 type-check 超时，后续模拟器安装因缺 bundle ID 连带失败，探针未运行且结果包只保留 `output/probe-not-run.txt`。
- 修复方式是把 RenderSprite layout candidate ledger 的嵌套 `flatMap` / `map` / struct 初始化拆成显式局部 helper 和 `for` 循环，先落地 `candidateID`、`candidateArea`、`areaDeltaVsCurrent`、`decisionSignals`、`evaluationSignals` 等中间变量；字段语义和 report-only 输出不变。
- 本修复不改主 OCR、翻译输入、覆盖绘制、`safeLayoutRect`、DistanceField safe rect、`renderFontSize`、`renderNonTransparentBounds`、`blockPassed`、失败分类、active artifacts 或 `configuration.currentBlockSource`。
- Build IPA #94 run `28574373590` 在合并 commit `902e836` 的 Release archive / `iphoneos` / whole-module optimization 阶段失败，`xcodebuild-archive.log` 指向 `MangaOverlayProbeService.swift:1744` 的 `Task.detached` 大闭包 type-check 超时，并提示该 `await` 内没有 async 操作。本次修复移除 `makeKoharuBubbleAdjacencySeamReport` 外层无必要 `Task.detached` / `.value` 包装，保留原报告计算、字段和 report-only 语义；不改主 OCR、翻译输入、覆盖绘制、`safeLayoutRect`、DistanceField safe rect、RenderSprite fit planner、`blockPassed`、失败分类、active artifacts 或 `configuration.currentBlockSource`。

核心变更：

- 新增 `koharuRenderSpriteFitPlannerReport`，只基于 AITRANS 现有 `safeLayoutRect`、`renderFontSize`、`renderNonTransparentBounds`、render collision、失败 fallback 文本、v1.30 Render Regression Lock、v1.35 BubbleIndex、v1.36 DistanceField 和 v1.37 seam 证据，构建 RenderedSprites 字体预算、换行压力、sprite containment、layout candidate、same-bubble sibling fit 和 failure overlay fit 账本。
- 报告输出 `blockLedgers[]`、`layoutCandidateLedgers[]`、`siblingLedgers[]` 和 `gateLedger[]`，记录 `translationCandidate` / `failureFallback` 渲染文本来源、字符统计、候选 rect、字体预算、seam / sibling / render lock 风险、proxy boundary 和 report-only next action。
- 报告明确 `groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuRenderer = true`、`proxyNotRealBubbleMask = true`；ground truth 只进入 evaluation signals。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuRenderSpriteFitPlannerReport`；convergence 新增 `WI-koharu-render-sprite-fit-planner` 和 `G-koharu-render-sprite-fit-planner-executed`。
- `1_ocr_probe_text.txt` 新增 RenderSprite fit planner summary、layout candidate、sibling fit group 和逐块 `renderSpriteFit`。
- 报告只做 report-only 诊断；不新增 OCR / LLM，不重新渲染 PNG，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`renderFontSize`、`renderNonTransparentBounds`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.38（KoharuRenderSprite排版适配影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuRenderSpriteFitPlannerReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`layoutCandidateCount >= totalBlocksDetected`、`gateCount >= 10`，breakdown 非空，`proxyNotRealKoharuRenderer = true`、`proxyNotRealBubbleMask = true`，convergence 包含 RenderSprite fit planner reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、layout candidate、sibling fit 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.35-v1.38 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.37：Koharu 气泡邻接切缝影子复刻
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.37（Koharu气泡邻接切缝影子复刻）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

退回修复：

- PR #27 云端 run `28564459237` 中 static checks、Xcode build 和 simulator build 通过，但 `mangaProbeOutcome=failure`；`manga-probe.log` 停在 `render-output-start` 后，最终未生成 `probe_report.json`。
- 修复 `koharuBubbleAdjacencySeamReport` 的 proxy mask gap 计算：从整图 mask 像素全量收集 + 双重循环，改为 bubble bbox 内边界采样、样本上限和远距离 bbox gap 近似，保持 report-only 语义和字段含义。
- 在 render 后 Koharu 后置报告链新增进度点，覆盖 BubbleIndex、DistanceField、Bubble adjacency seam、最终 convergence refresh、TXT 重写和 `probe_report` 写入起点，便于云端失败时定位具体卡点。

核心变更：

- 新增 `koharuBubbleAdjacencySeamReport`，只基于 AITRANS 现有 rounded-rect BubbleMask proxy、BubbleIndex、DistanceField、split candidate、same-bubble sibling、OCR damage 和 render lock 证据，构建 bubble adjacency graph、seam candidate ledger 和逐块 seam 风险账本。
- 报告输出 `pairLedgers[]`、`seamCandidateLedgers[]`、`blockLedgers[]` 和 `gateLedger[]`，记录 bbox gap / overlap、proxy mask gap、shared split / sibling / conflict 信号、seam orientation / corridor、assignment conflict、safe-area risk、render lock 和 report-only next action。
- 报告明确 `proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false` 和 `diagnosticOnly = true`；ground truth 只进入 evaluation signals。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuBubbleAdjacencySeamReport`；convergence 新增 `WI-koharu-bubble-adjacency-seam` 和 `G-koharu-bubble-adjacency-seam-executed`。
- `1_ocr_probe_text.txt` 新增 Bubble adjacency seam summary、pair ledger、seam candidate ledger 和逐块 `bubbleSeamBlockLedger`。
- 报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.37（Koharu气泡邻接切缝影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuBubbleAdjacencySeamReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`evaluatedBubbleCount == bubbleMaskReport.instanceCount`、`blockLedgerCount == totalBlocksDetected`、`pairLedgerCount >= 1`、`seamCandidateCount >= bubbleSplitCandidateReport.candidateCount`、`gateCount >= 10`，breakdown 非空，`proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`，convergence 包含 Bubble adjacency seam reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、pair ledger、seam candidate 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.37 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.36：Koharu DistanceField 安全区影子复刻
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.36（KoharuDistanceField安全区影子复刻）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuDistanceFieldSafeAreaReport`，只基于 AITRANS 现有 rounded-rect BubbleMask proxy ID mask，在每个 bubble bbox 内计算 two-pass chamfer 8-neighbor distance field、safe pixels、safe pixel bbox 和 histogram maximum safe rect。
- 报告输出 bubble / block / same-bubble sibling 三层 ledger，对比当前 `safeLayoutRect`、v1.35 `koharuBubbleIndexShadowLedgerReport` 的 shadow safe rect、distance-field safe rect、render sprite containment、render lock 和 split / sibling 风险。
- 报告明确 `proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false` 和 `diagnosticOnly = true`；ground truth 只进入 evaluation signals。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuDistanceFieldSafeAreaReport`；convergence 新增 `WI-koharu-distance-field-safe-area` 和 `G-koharu-distance-field-safe-area-executed`。
- `1_ocr_probe_text.txt` 新增 DistanceField summary、safe pixel / safe rect / sprite containment breakdown、bubble ledger、sibling ledger 和逐块 `distanceFieldBlockLedger`。
- 报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.36（KoharuDistanceField安全区影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuDistanceFieldSafeAreaReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`bubbleLedgerCount == bubbleMaskReport.instanceCount`、`blockLedgerCount == totalBlocksDetected`、`gateCount >= 10`，breakdown 非空，`proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`，convergence 包含 DistanceField reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、bubble ledger、sibling ledger 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.36 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.35：Koharu BubbleIndex 影子账本与安全区复刻
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.35（KoharuBubbleIndex影子账本与安全区复刻）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuBubbleIndexShadowLedgerReport`，从现有 BubbleMask proxy、BubbleMask 归属修正、split candidate、reading order、BubbleMask assignment / split scoreboard、render lock、native replay matrix 和最终 blocks 聚合 Koharu BubbleIndex 影子账本。
- 报告输出 block / bubble / same-bubble sibling 三层 ledger，审计当前 `bubbleID`、shadow majority bubble、mask-safe rect 对照、同气泡 sibling 分区、split 风险、render lock、primary bottleneck 和 next action。
- 报告明确 `proxyNotRealBubbleMask = true`，ground truth 只进 evaluation signals，不参与 assignment、safe area、sibling partition、gate 或 next action 决策。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuBubbleIndexShadowLedgerReport`；convergence 新增 `WI-koharu-bubble-index-shadow-ledger` 和 `G-koharu-bubble-index-shadow-ledger-executed`。
- `1_ocr_probe_text.txt` 新增 BubbleIndex summary、assignment / safe-area / sibling breakdown、bubble ledger、sibling ledger 和逐块 `koharuBubbleIndexBlockLedger`。
- 报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`blockPassed`、失败分类、post-fusion cleanup、候选选择、glyph mask、背景填充、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.35（KoharuBubbleIndex影子账本与安全区复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 退回修复：PR #25 云端 run `28523199970` 在 `TranslationSessionStore.swift` 的 `MangaKoharuWorkOrderBlockRoute` 大表达式 type-check 超时；本轮拆分 work order route 与 BubbleIndex block ledger 的 signal / evaluation / mustNotPromote 子表达式，保持 report-only 语义不变。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuBubbleIndexShadowLedgerReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`evaluatedBubbleCount == bubbleMaskReport.instanceCount`、`bubbleLedgerCount == bubbleMaskReport.instanceCount`、`gateCount >= 12`，breakdown 非空，`proxyNotRealBubbleMask = true`，convergence 包含 BubbleIndex reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、bubble ledger、sibling ledger 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.35 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.34：Koharu 本地算法复刻执行矩阵与探针评估账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.34（Koharu本地算法复刻执行矩阵与探针评估账本）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeAlgorithmReplayMatrixReport`，从 resolver、work order router、external artifact request packet、convergence、TextBox / BubbleMask / SegmentMask scoreboards、translation floor、render lock、diagnostics 和最终 blocks 聚合 Koharu 本地算法复刻执行矩阵。
- 报告固定输出 canonical stage matrix，覆盖 `SourceImage`、`ContentCrop`、`TextBoxes`、`BubbleMask`、`SegmentMask`、`OcrText`、`Translations`、`RenderedSprites`、`FinalRender` 和 `ExternalArtifacts`。
- 报告固定输出 replay candidates，覆盖融合主流程审计、post-fusion / OCR 质量路由、TextBox stoplist、BubbleMask 归属 / 分割、SegmentMask 覆盖、translation model floor、render lock 和 external artifact handoff。
- 每块新增 replay route，记录 primary candidate、primary Koharu stage、bottleneck、external / model floor / render lock / stoplist 状态和 next action。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeAlgorithmReplayMatrixReport`；convergence 新增 `WI-koharu-native-algorithm-replay-matrix` 和 `G-koharu-native-algorithm-replay-matrix-executed`。
- `1_ocr_probe_text.txt` 新增 replay matrix summary、`candidateQueue`、`stageMatrix` 和逐块 `koharuNativeReplayRoute`。
- 报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充、active artifacts 或 `configuration.currentBlockSource`。ground truth 只进入 evaluation signals，不参与 candidate status、budget、gate、route 或 next action。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.34（Koharu本地算法复刻执行矩阵与探针评估账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeAlgorithmReplayMatrixReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 10`、`candidateCount >= 9`、`blockRouteCount == totalBlocksDetected`、`gateCount >= 14`，固定 candidate queue 存在，缺 active artifact 时 external candidate blocked，crop / line / deskew stoplist 仍关闭，model floor / OCR / render lock 分开路由，convergence 包含 replay matrix reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate queue、stage matrix 和逐块 route。

遗留事项：

- 旧仓库根 `output/` 不含 v1.34 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.33：Koharu 外部 Artifact 请求包与准入缺口账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.33（Koharu外部Artifact请求包与准入缺口账本）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuExternalArtifactRequestPacketReport`，从 v1.32 `koharuWorkOrderRouterReport`、external readiness gate、external TextBox shadow OCR、TextBox / BubbleMask / SegmentMask scoreboards、render lock、translation floor、convergence 和最终 blocks 聚合真实外部 artifact 请求包。
- 固定枚举 active `test/koharu_artifacts/` 四件套：`1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`，并为每个 required file 写出 schema 字段、坐标系、解析/契约状态、validator command、blocked reason、next action 和 forbidden sources。
- 新增 `artifactRequirements[]` 覆盖真实 `TextBoxes`、`BubbleMask`、`SegmentMask`，明确当前 proxy 只能作为 why-needed / current limitation 证据，不能冒充 Koharu detector artifact。
- 新增逐块 `blockRequests[]`，每块记录 primary work order、primary bottleneck、needs TextBoxes / BubbleMask / SegmentMask、external readiness、external shadow OCR gate、stoplist、model floor、render lock、manual review、current proxy evidence、missing real artifact reasons、forbidden local actions 和 next action。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuExternalArtifactRequestPacketReport`；convergence 新增 `WI-koharu-external-artifact-request-packet` 和 `G-koharu-external-artifact-request-packet-executed`。
- `1_ocr_probe_text.txt` 新增 request packet summary、`requiredFiles` 摘要、`artifactRequirements` 摘要和逐块 `koharuExternalArtifactRequest` 行。
- 报告只做 report-only 诊断；不创建、复制、修改或提交 active `test/koharu_artifacts/`，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充、渲染逻辑或 `configuration.currentBlockSource`。ground truth 只进入 evaluation signals，不参与 request、gate、next action 或 promotion 决策。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.33（Koharu外部Artifact请求包与准入缺口账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuExternalArtifactRequestPacketReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`requiredFileCount >= 4`、`artifactRequirementCount >= 3`、`blockRequestCount == totalBlocksDetected`、`gateCount >= 13`，缺 active artifact 时 verdict 为 missing / waiting / blocked 类状态，required files 覆盖四件套，requirements 覆盖 TextBoxes / BubbleMask / SegmentMask，forbidden sources 非空，convergence 包含 request packet reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 request packet summary、required files、artifact requirements 和逐块 request。

遗留事项：

- 旧仓库根 `output/` 不含 v1.33 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.32：Koharu WorkOrder Router 执行工作单与收益预算
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.32（KoharuWorkOrderRouter执行工作单与收益预算）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuWorkOrderRouterReport`，从 v1.31 `koharuPipelineResolverReport` 派生固定 work orders、逐块 routes、budget ledger 和 gate ledger。
- 固定 work order 覆盖 resolver ledger 收口、本地 crop / line / deskew stoplist、真实 TextBoxes / BubbleMask / SegmentMask 请求、render lock 保持、translation model floor handoff、external artifact package handoff 和 manual review。
- 逐块 route 输出 primary / secondary work order、primary bottleneck、模型地板、render lock、stoplist、真实 artifact 需求、CI/full/external 预算和下一步动作。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuWorkOrderRouterReport`；convergence 新增 `WI-koharu-workorder-router` 和 `G-koharu-workorder-router-executed`。
- `1_ocr_probe_text.txt` 新增 router report summary、`workOrderQueue` 摘要和逐块 `koharuWorkOrderRoute` 行。
- 报告只做 report-only 诊断；不新增 OCR / LLM、不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充或 `configuration.currentBlockSource`。ground truth 只进入 evaluation signals，不参与 work order routing、priority、budget 或 next action。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.32（KoharuWorkOrderRouter执行工作单与收益预算）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuWorkOrderRouterReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`workOrderCount >= 7`、`blockRouteCount == totalBlocksDetected`、`gateCount >= 10`，breakdown 非空，缺 active artifact 时 external work orders 保持 blocked/missing，convergence 包含 router reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 router summary、work order queue 和逐块 route。

遗留事项：

- 旧仓库根 `output/` 不含 v1.32 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.31：Koharu Pipeline Resolver 影子 DAG 阶段调度与阻塞传播
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.31（KoharuPipelineResolver影子DAG阶段调度与阻塞传播）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuPipelineResolverReport`，用 Koharu `EngineInfo.needs / produces`、DAG resolver 和 Op preview 的结构组织现有 AITRANS 探针证据。
- 报告输出 `nodes[]`、`edges[]`、逐块 `blockTraces[]`、`executionQueue[]`、`opPreviews[]` 和 `gateLedger[]`，覆盖 SourceImage、ContentCrop、Vision OCR、BubbleCandidates、BubbleMask/TextBox/SegmentMask proxy、OcrText、FusionCleanup、Translations、GlyphErase proxy、RenderedSprites proxy、FinalRender 和 ExternalArtifacts。
- 逐块 trace 输出 `firstBlockedNodeID`、`firstBlockedReason`、downstream blocked nodes、recommended execution item、next action、requires external artifact 和 stoplisted local tuning 状态。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuPipelineResolverReport`；convergence 新增 `WI-koharu-pipeline-resolver-shadow-dag` 和 `G-koharu-pipeline-resolver-executed`。
- `1_ocr_probe_text.txt` 新增 resolver report summary、`resolverExecutionQueue` 摘要和逐块 `koharuPipelineResolverTrace` 行。
- 报告只做 report-only 诊断；不新增 OCR / LLM、不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充或 `configuration.currentBlockSource`。ground truth 只进入 evaluation signals，不参与 resolver 决策。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.31（KoharuPipelineResolver影子DAG阶段调度与阻塞传播）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuPipelineResolverReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`nodeCount >= 12`、`edgeCount >= 12`、`blockTraceCount == totalBlocksDetected`、`executionQueueCount >= 6`、`opPreviewCount >= 4`、`gateCount >= 8`，breakdown 非空，`externalArtifacts` 缺 active artifact 时保持 blocked/missing，convergence 包含 resolver reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 resolver summary、execution queue 和逐块 trace。

遗留事项：

- 旧仓库根 `output/` 不含 v1.31 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.30：Koharu Render Regression Lock 覆盖渲染回归锁与 FinalRender 账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.30（KoharuRenderRegressionLock覆盖渲染回归锁与FinalRender账本）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuRenderRegressionLockReport`，执行 v1.28 未闭合的 `WI-render-regression-lock`。
- 报告聚合现有 final blocks、`safeLayoutRect`、mask-safe rect、render collision、render mask overflow、glyph mask、background fill、失败块 fallback 覆盖文本和 App 沙盒输出文件状态，输出 RenderedSprites / FinalRender 回归锁。
- 顶层输出 `renderLockVerdict`、render / safe layout / background fill / glyph mask / failure overlay / output file breakdown、核心输出文件状态、逐块 `blockLocks[]`、`artifactStages[]`、`outputFileChecks[]` 和 `gateLedger[]`。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuRenderRegressionLockReport`；`WI-render-regression-lock` 可从 v1.28 的未执行 open 状态推进为 `closedReportOnly` 或 `openRenderIssueDetected`，并同步 `G-render-regression-lock-executed` gate。
- `1_ocr_probe_text.txt` 新增报告级 render lock summary、render issue / output file 摘要、convergence render work item 摘要和逐块 `renderLock` 行。
- 报告只做 report-only 诊断；不重新渲染、不解析 PNG 像素证明逐块文字、不新增 OCR / LLM、不改变主 OCR、主翻译、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、渲染逻辑或 `configuration.currentBlockSource`。`proxyNotRealKoharuRenderer = true` 表示 AITRANS 当前不是 Koharu 真实 renderer、RenderedSprites artifact 或 inpainting。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.30（KoharuRenderRegressionLock覆盖渲染回归锁与FinalRender账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuRenderRegressionLockReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLocks.count == totalBlocksDetected`、`artifactStages.count >= 5`、`gateLedger.count >= 13`、`outputFileChecks` 覆盖核心 JSON/TXT/PNG，`failureOverlayRequiredBlocks` 覆盖所有失败块，`koharuArtifactConvergenceReport.referenceReports` 包含新 report，`WI-render-regression-lock` 不再只是 v1.28 未执行 open 状态，且 `1_ocr_probe_text.txt` 包含新 summary、逐块 `renderLock` 和 convergence render work item 摘要。

遗留事项：

- 旧仓库根 `output/` 不含 v1.30 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.29：Translation Model Floor 对照矩阵与 Koharu 翻译地板账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.29（TranslationModelFloor对照矩阵与Koharu翻译地板账本）.md`。本轮修改 Swift 探针报告模型、deterministic clean text strict prompt 诊断、Koharu convergence work item 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `translationModelFloorComparisonReport`，执行 v1.28 未闭合的 `WI-translation-model-floor-comparison`。
- 报告复用 `cleanTextDiagnostic` 的 dialogue baseline cases，额外运行 deterministic `strictChineseOnlyV1` prompt 变体，记录 baseline / variant prompt、raw output、candidate、raw / candidate classification、failure reasons、pass state 和 prompt variant outcome。
- 报告聚合 noisy final blocks、v1.19 `routingDrivenTranslationComparisonReport`、`batchTranslationComparison` 和 `koharuArtifactConvergenceReport` work item，输出 `floorVerdict`、clean/noisy 计数、prompt outcome breakdown、failure reason breakdown 和 gate ledger。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `translationModelFloorComparisonReport`，`WI-translation-model-floor-comparison` 可从 v1.28 的未执行 open 状态推进为 `closedReportOnly` 或 `openModelFloorConfirmed`；这只表示对照账本已执行，不表示模型质量问题已解决。
- `1_ocr_probe_text.txt` 新增报告级 `translationModelFloorComparisonReport` summary、逐条 `translationFloorCleanCase` 和逐块 `translationFloorNoisyBlock` 摘要。
- 报告只做 report-only 诊断；clean text ground truth 只用于模型地板评估，不参与 noisy OCR 候选选择、主 prompt、主译文、覆盖图、`blockPassed`、失败分类、质量规则、模型选择或 metrics history。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.29（TranslationModelFloor对照矩阵与Koharu翻译地板账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `translationModelFloorComparisonReport.enabled = true`、`evaluatedCleanCaseCount == cleanTextDiagnostic.totalCases`、`evaluatedNoisyBlockCount == totalBlocksDetected`、`baselinePassRate == cleanTextDiagnostic.passRate`、`floorVerdict` 和 breakdown 非空、`gateLedger.count >= 9`、`koharuArtifactConvergenceReport.referenceReports` 包含新 report、`WI-translation-model-floor-comparison` 不再只是 v1.28 未执行 open 状态，且 `1_ocr_probe_text.txt` 包含新 summary、clean case 摘要和逐块 noisy block 摘要。

遗留事项：

- 旧仓库根 `output/` 不含 v1.29 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.28：Koharu Artifact 收敛矩阵与下一步决策账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.28（KoharuArtifact收敛矩阵与下一步决策账本）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuArtifactConvergenceReport`，聚合 v1.22 `koharuArtifactDAGReport`、v1.23 `koharuStageGapReplicationReport`、v1.24 `koharuNativeReplicationScoreboardReport`、v1.25 `nativeTextBoxProxyLedgerReport`、v1.26 `bubbleMaskAssignmentSplitScoreboardReport`、v1.27 `segmentMaskProxyCoverageScoreboardReport`、external artifact readiness、clean text diagnostic、diagnostics 和最终 blocks。
- 报告顶层输出 `source = AITRANSProbe`、`referencePipeline = Koharu`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true` 和 `externalArtifactsRequiredForThisReport = false`。
- `stages[]` 输出 SourceImage、ContentCrop、TextBoxes、BubbleMask、SegmentMask、OcrText、Translations、Inpainted、RenderedSprites、FinalRender 和 ExternalArtifacts 的 convergence matrix。
- `blockPaths[]` 为每个最终块输出 TextBox / BubbleMask / SegmentMask / OCR / translation / render 状态、`firstBlockingArtifact`、`primaryStructuralBottleneck`、model floor、render lock、real artifact 需求和下一步 action。
- `workItemLedger[]` 固定收束 `WI-native-textbox-artifact-scorecard`、`WI-bubblemask-assignment-split-scorecard`、`WI-segmentmask-proxy-coverage-scorecard`，并把未闭合项集中到 `WI-translation-model-floor-comparison`、`WI-render-regression-lock` 和 `WI-external-artifact-optional-handoff`。
- `gateLedger[]` 固定包含 no-main-flow-mutation、no-ground-truth-decision、v1.25 / v1.26 / v1.27 work item closure、translation model floor open、render regression lock open、external artifact optional、proxy boundary 和 ci-fast report availability。
- `1_ocr_probe_text.txt` 新增报告级 `koharuArtifactConvergenceReport` summary 和逐块 `koharuArtifactPath` 摘要。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、渲染逻辑或 `configuration.currentBlockSource`。ground truth 只进入 evaluationSignals，不参与 firstBlockingArtifact、primaryNextAction、work item status 或 gate。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.28（KoharuArtifact收敛矩阵与下一步决策账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuArtifactConvergenceReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 9`、`blockPathCount == totalBlocksDetected`、`workItemLedgerCount >= 6`、`gateCount >= 10`，关键 breakdown 非空，前三个 proxy work item 在 `closedWorkItems` 中，open work items 至少包含 translation model floor、render regression lock 或 external optional handoff，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `koharuArtifactPath`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.28 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.27：SegmentMask Proxy 覆盖评分板与 Glyph 清字边界账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.27（SegmentMaskProxy覆盖评分板与Glyph清字边界账本）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `segmentMaskProxyCoverageScoreboardReport`，执行 v1.24 的 `WI-segmentmask-proxy-coverage-scorecard`，聚合现有 glyph mask、SegmentMask proxy、TextBox 覆盖、BubbleMask 覆盖、safe rect、背景填充和渲染碰撞证据。
- 报告顶层输出 `source = AITRANSProbe`、`referenceWorkItemID = WI-segmentmask-proxy-coverage-scorecard`、`referenceKoharuArtifact = SegmentMask`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true` 和 `proxyNotRealSegmentMask = true`。
- `blockScorecards[]` 为每个最终块输出 coverage status、cleanup status、render mask status、glyph / TextBox / BubbleMask / safe rect 覆盖、background fill、render collision、TextBox / BubbleMask ledger 状态、must-not-promote reasons 和 nextAction。
- `cleanupLedgers[]` 采用每个最终块一条的稳定计数规则，记录 glyph 清字边界、background fill guardrail、allowed cleanup use、blocked cleanup reasons、`inpaintingImplemented = false` 和 `proxyOnly = true`。
- `gateLedger[]` 固定包含 no-main-flow-mutation、no-ground-truth-decision、proxy boundary、glyph available、TextBox / BubbleMask / safe rect coverage、background fill guardrail、render mask collision、TextBox ledger boundary、BubbleMask boundary 和 real SegmentMask artifact boundary。
- `1_ocr_probe_text.txt` 新增报告级 `segmentMaskProxyCoverageScoreboardReport` summary 和逐块 `segmentMaskProxyScoreboard` 摘要。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.27（SegmentMaskProxy覆盖评分板与Glyph清字边界账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `segmentMaskProxyCoverageScoreboardReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`glyphMaskBlockCount == segmentMaskReport.glyphMaskBlocks`、`blockScorecards.count == totalBlocksDetected`、`cleanupLedgerCount >= glyphMaskBlockCount`、`gateLedger.count >= 12`，关键 breakdown 非空，`proxyNotRealSegmentMask = true`，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `segmentMaskProxyScoreboard`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.27 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.26：BubbleMask 归属分割评分板与 Sibling 布局账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.26（BubbleMask归属分割评分板与Sibling布局账本）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `bubbleMaskAssignmentSplitScoreboardReport`，执行 v1.24 的 `WI-bubblemask-assignment-split-scorecard`，聚合现有 BubbleMask proxy、归属修正、split candidate、reading order、structure action、Koharu native scoreboard 和 Native TextBox ledger 证据。
- 报告顶层输出 `source = AITRANSProbe`、`referenceWorkItemID = WI-bubblemask-assignment-split-scorecard`、`referenceKoharuArtifact = BubbleMask`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false` 和 `diagnosticOnly = true`。
- `blockScorecards[]` 为每个最终块输出 assignment status、split risk、same-bubble sibling layout、mask safe rect、render mask status、TextBox ledger status、decision / evaluation signals、must-not-promote reasons 和 nextAction。
- `bubbleScorecards[]` 为每个 BubbleMask proxy 实例输出 blocks、冲突块、归属修正块、split candidate、same-bubble sibling groups、render overflow、instance status 和 primary risk。
- `splitCandidateLedgers[]` 和 `siblingLayoutScorecards[]` 把既有 split candidate 与同气泡 sibling 布局整理成 report-only 账本，不扩大 crop clamp，不改 `safeLayoutRect`。
- `gateLedger[]` 固定包含 no-main-flow-mutation、no-ground-truth-decision、assignment consistency、correction report-only、split report-only、sibling layout、render mask collision、protected text、TextBox ledger boundary 和 real artifact boundary。
- `1_ocr_probe_text.txt` 新增报告级 `bubbleMaskAssignmentSplitScoreboardReport` summary 和逐块 `bubbleMaskScoreboard` 摘要。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.26（BubbleMask归属分割评分板与Sibling布局账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 退回修复：云端 run `28489045515` 在 `TranslationSessionStore.swift` 触发 Swift 编译失败，原因是 v1.26 scoreboard helper 对 `Bool` 字段 `bubbleIDConsistent` 调用了 `map`；已改为对可选 mask 本身转换为 `"true"` / `"false"` / `"nil"`，不改变报告语义或主流程。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `bubbleMaskAssignmentSplitScoreboardReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`evaluatedBubbleCount == bubbleMaskReport.instanceCount`、`blockScorecards.count == totalBlocksDetected`、`bubbleScorecards.count == bubbleMaskReport.instanceCount`、`splitCandidateLedgers.count == bubbleSplitCandidateReport.candidateCount`、`gateLedger.count >= 10`，关键 breakdown 非空，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `bubbleMaskScoreboard`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.26 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.25：Native TextBox Proxy 质量账本与候选冻结
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.25（NativeTextBoxProxy质量账本与候选冻结）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `nativeTextBoxProxyLedgerReport`，执行 v1.24 的 `WI-native-textbox-artifact-scorecard`，聚合现有 TextBox / crop / line / BubbleMask / SegmentMask / OCR damage / v1.24 scoreboard 证据。
- 报告顶层输出 `source = AITRANSProbe`、`referenceWorkItemID = WI-native-textbox-artifact-scorecard`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false` 和 `diagnosticOnly = true`。
- `blockLedgers[]` 为每个最终块输出 qualityStatus、candidateSources、word preservation、protected keyword、bubble / segment / OCR damage / translation model / render gate、stoplist 命中、mustNotPromoteReasons 和 nextAction。
- `candidateLedgers[]` 汇总 fused seed bbox、TextRegion crop control、pre-crop TextBox plan、crop experiment shadow、line TextBox plan、line crop shadow 等既有候选证据；候选只做 report-only 账本，不写回主流程。
- `gateLedger[]` 固定包含 no-main-flow-mutation、no-ground-truth-decision、word preservation、protected keywords、stoplist freeze、bubble containment、segment support、OCR damage、model floor 和 render stability。
- `stoplist[]` 冻结已证伪的 crop / line / deskew 本地试参，过期条件只能是未来证据条件，不通过降低阈值解冻。
- `1_ocr_probe_text.txt` 新增报告级 `nativeTextBoxProxyLedgerReport` summary 和逐块 `nativeTextBoxProxyLedger` 摘要。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.25（NativeTextBoxProxy质量账本与候选冻结）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 退回修复：云端 run `28452180814` 在 `TranslationSessionStore.swift` 触发 Swift 编译失败，原因是 v1.25 ledger helper 误读不存在的 `MangaOverlayTextRegionCropDiagnostic.candidatePreservesRawWords` 字段；已改为使用现有 `rawWordPreservationRatio >= 0.72` 推导，并移除同 helper 未使用的 BubbleMask 字典，不改变报告语义或主流程。
- 退回修复：云端 run `28453929047` 在 `makeNativeTextBoxProxyLedgerReport` 的 `blockLedgers` 大闭包触发 Swift 类型检查超时；已拆为显式 helper / 子表达式并改用显式循环生成 block ledger，同时清理 v1.24 scoreboard helper 未使用的 `mask` 变量，不改变报告语义或主流程。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `nativeTextBoxProxyLedgerReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgers.count == totalBlocksDetected`、`gateLedger.count >= 10`，关键 breakdown 非空，stoplist 覆盖既有 crop / line stop blocks，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `nativeTextBoxProxyLedger`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.25 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.24：Koharu 本地复刻 Scoreboard 与 Gate Ledger
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.24（Koharu本地复刻Scoreboard与GateLedger）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeReplicationScoreboardReport`，只用 AITRANS 自己的 probe 输出，把 v1.23 stage gap / work package 转成 stage scorecard、gate ledger、block scorecard 和下一轮 work items。
- 报告顶层输出 `source = AITRANSProbe`、`referencePipeline = Koharu`、`externalArtifactsRequiredForThisReport = false`、`groundTruthUsedForDecision = false` 和 `groundTruthUsedForEvaluationOnly = true`。
- `stageScorecards[]` 覆盖 `sourceImage`、`contentCrop`、`nativeTextBoxes`、`nativeBubbleMask`、`nativeSegmentMask`、`ocrText`、`translations`、`glyphEraseOrInpaintProxy`、`renderedSprites` 和 `finalRender`，区分 native / proxy / shadow / stop / model-limited / render-stable 状态。
- `gateLedger[]` 新增 no-main-flow-mutation、no-ground-truth-decision、native TextBox word preservation / stoplist、bubble conflict、SegmentMask inside bubble、clean text model floor、failure overlay、render no-overflow 和 external artifact optional 等 gate。
- `blockScorecards[]` 为每个最终块输出 OCR / bubble / segment / translation / render gate 状态、stoplist 证据、推荐 work item 和 next action；priority 和 nextAction 不读取 ground truth。
- `recommendedNextWorkItems[]` 明确把已证伪的 crop / line / deskew 本地试参加入 stoplist，下一步转向 native TextBox / BubbleMask / SegmentMask 评分、translation model floor 对照和 render regression lock。
- `1_ocr_probe_text.txt` 新增报告级 `koharuNativeReplicationScoreboardReport` summary 和逐块 `koharuNativeBlockScorecard` 摘要。
- 缺真实 `test/koharu_artifacts/` 只记为 `externalOptionalMissing` 可选外部路径，不阻塞 native scoreboard；但仍不能把 Vision OCR、pre-crop plan、line plan、BubbleMask proxy 或 SegmentMask proxy 冒充成真实 Koharu artifact。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.24（Koharu本地复刻Scoreboard与GateLedger）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeReplicationScoreboardReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`stageScorecardCount >= 9`、`gateCount >= 8`、`workItemCount >= 1`，关键 breakdown 非空，`externalArtifactsRequiredForThisReport = false`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`，每个 `stageScorecards[]` / `gateLedger[]` 的决策字段不使用 ground truth，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `koharuNativeBlockScorecard`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.24 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.23：Koharu 阶段差距复刻计划与晋级门槛
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.23（Koharu阶段差距复刻计划与晋级门槛）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuStageGapReplicationReport`，把 v1.22 `koharuArtifactDAGReport` 转成 Koharu canonical stage 差距、work package、promotion gate 和逐块复刻计划。
- 报告覆盖 `sourceImage`、`contentCrop`、`textBoxes`、`bubbleMask`、`segmentMask`、`ocrText`、`translations`、`cleanTextDiagnostic`、`inpaintOrGlyphErase`、`renderedSprites` 和 `finalRender`。
- 每个 stage gap 写出当前 AITRANS 能力、artifact kind、source reports、gap category、replication readiness、最小输入、现有/缺失证据、受影响块、promotion gates、stop conditions 和推荐 work package。
- 每个 work package 写出优先级、目标阶段/块、是否可在 `ci-fast` 验证、是否需要 full probe、是否必须真实 external artifact、预期指标移动、rollback / stop 条件和非目标。
- 每个 block 输出 `firstBlockingStageFromDAG`、`primaryGapCategory`、目标 canonical stage、推荐 work package、最小证据、禁止晋级原因、是否需要 full / real artifact 和下一步动作。
- `1_ocr_probe_text.txt` 新增报告级 `koharuStageGapReplicationReport` summary 和逐块 `koharuStageGapPlan` 摘要。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择或 `configuration.currentBlockSource`。
- 缺真实 active `test/koharu_artifacts/` 时，真实 TextBoxes / BubbleMask / SegmentMask 仍保持 `manifestMissing` / `stopUntilArtifactsProvided` 阻塞，不能把 Vision OCR、pre-crop plan、line plan、BubbleMask proxy 或 SegmentMask proxy 冒充成 Koharu artifact。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.23（Koharu阶段差距复刻计划与晋级门槛）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuStageGapReplicationReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`canonicalStageCount >= 9`、`workPackageCount >= 1`，关键 breakdown 非空，`stageGaps[].diagnosticOnly = true`、`stageGaps[].groundTruthUsedForPlanning = false`、`stageGaps[].wouldChangeMainFlow = false`，每个 promotion gate 的 `groundTruthUsedForDecision = false`，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `koharuStageGapPlan`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.23 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.22：Koharu 式 Artifact DAG 阶段账本与瓶颈闭环
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.22（Koharu式ArtifactDAG阶段账本与瓶颈闭环）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuArtifactDAGReport`，把 SourceImage、ContentCrop、Vision OCR、BubbleMask、TextBoxes、SegmentMask、OCR text、shadow crop、external artifact gate、translation、render layout 和 v1.21 结构动作候选组织成 Koharu 式 Artifact DAG 阶段账本。
- 报告级输出 dependency edges、stage summaries、stage status / artifact kind / first blocking stage / downstream impact breakdown，以及真实 artifact gate verdict / next action。
- 每块输出 `blockTraces[]`，包含 `firstBlockingStage`、`firstBlockingReason`、`downstreamImpacts`、关键 `stageTraces`、v1.21 候选 verdict 和 `recommendedNextAction`。
- 缺真实 active `test/koharu_artifacts/` 时，只把需要真实 TextBoxes / BubbleMask / SegmentMask 的 promotion 标为 `missingRequiredArtifact`，不把当前主流程整体判废。
- `1_ocr_probe_text.txt` 新增报告级 `koharuArtifactDAGReport` summary 和逐块 `koharuArtifactTrace` 摘要，便于不打开巨大 JSON 时定位首次阻塞阶段。
- 该报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.22（Koharu式ArtifactDAG阶段账本与瓶颈闭环）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 退回修复：云端 run `28433914248` 在 `TranslationSessionStore.swift` 的 v1.22 DAG 报告构建处触发 Swift 6 编译失败；已改为显式 optional Bool 字符串转换、显式 closure 和多步局部统计，降低 type-check 压力，不改变报告语义或主流程。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuArtifactDAGReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 8`、`edgeCount >= 8`，关键 breakdown 非空，每条 dependency edge 的 `diagnosticOnly = true`、`wouldChangeMainFlow = false`，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `koharuArtifactTrace`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.22 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.21：结构动作候选矩阵与 Shadow 执行评估
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.21（结构动作候选矩阵与Shadow执行评估）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `structureActionCandidateReport`，把 v1.20 `readingOrderStructureAuditReport` 的结构建议转成 shadow-only 候选矩阵。
- 候选类型覆盖 `readingOrderReindex`、`bubbleAssignmentReview`、`bubbleSplitShadow`、`sameBubbleSiblingLayout`、`duplicateFragmentProtection`、`textBoxEvidenceRequired`、`segmentMaskEvidenceRequired`、`renderSafeAreaReflow` 和 `manualReviewOnly`。
- 每个候选写出 `plannedOperation`、`expectedBenefit`、`executionMode`、control/shadow metrics、delta、`promotionVerdict`、`promotionBlockers` 和 `recommendedNextStep`。
- 报告级汇总 candidate type、promotion verdict、next step、report-only would improve、blocked、needs real artifact、render reflow、bubble split / assignment、duplicate protection 和 manual review blocks。
- `1_ocr_probe_text.txt` 新增报告级 `structureActionCandidateReport` summary 和每块 `structureActionCandidates` 摘要，包含跳过原因和 delta summary。
- 报告只复用已有几何、渲染和 shadow OCR 摘要，不新增 OCR / LLM 调用；不改变 `blocks` 顺序、batch 输入、`finalTextUsedForTranslation`、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- 缺真实 Koharu TextBoxes / BubbleMask / SegmentMask artifact 时只输出阻塞和 `provideRealKoharuArtifact`，不得用 Vision OCR、pre-crop plan、line plan、BubbleMask proxy 或 SegmentMask proxy 冒充 detector 输出。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.21（结构动作候选矩阵与Shadow执行评估）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `structureActionCandidateReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`candidateCount >= 1`，关键 breakdown 非空，每个 candidate 的 `diagnosticOnly = true`、`groundTruthUsedForPlanning = false`、`wouldChangeMainFlow = false`，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块摘要。

遗留事项：

- 旧仓库根 `output/` 不含 v1.21 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.20：阅读顺序与气泡归属结构计划审计
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.20（阅读顺序与气泡归属结构计划审计）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `readingOrderStructureAuditReport`，从最终 blocks、bbox、safe layout、bubbleID、BubbleMask、TextBox / SegmentMask proxy、post-fusion cleanup 和 v1.18 / v1.19 路由证据现场计算阅读顺序与结构计划审计。
- 每块写出 `currentOrderIndex`、`proposedReadingOrderIndex`、`orderConfidence`、`bubbleGroupID`、同气泡 sibling、气泡归属风险、分割/合并风险、重复/碎片风险、保护标记、结构动作建议和 `mustNotPromoteReasons`。
- 报告级汇总 `orderChangedBlocks`、`lowConfidenceOrderBlocks`、`multiBlockBubbleGroups`、`maskConflictBlocks`、`splitRiskBlocks`、`duplicateOrFragmentRiskBlocks` 以及 TextBox / SegmentMask / 风险 / 动作 breakdown。
- `1_ocr_probe_text.txt` 新增报告级 `readingOrderStructureAuditReport` summary 和每块 `readingOrderStructureAudit` 摘要。
- 报告只做诊断，不改变 `blocks` 顺序、batch 输入、`finalTextUsedForTranslation`、翻译候选、`blockPassed`、失败分类、post-fusion cleanup 或覆盖图。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.20（阅读顺序与气泡归属结构计划审计）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `readingOrderStructureAuditReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`cases.count == totalBlocksDetected`，关键 breakdown 非空，`1_ocr_probe_text.txt` 包含新 summary 和逐块摘要，且 v1.18 / v1.19 报告仍存在。

遗留事项：

- 旧仓库根 `output/` 不含 v1.20 新字段；以 PR 后云端结果包为准。
- 阅读顺序启发式可能和漫画叙事顺序不一致，本轮只输出 report-only 风险和建议，不应用到主流程。

### v1.19：路由驱动翻译对照与 OCR 损坏审计
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.19（路由驱动翻译对照与OCR损坏审计）.md`。本轮修改 Swift 探针报告模型和诊断 TXT；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `routingDrivenTranslationComparisonReport`，从 v1.18 `internalStructureBottleneckReport` 中选择最多 5 个 `modelTranslationQuality` 块，运行 deterministic `strictChineseOnlyV1` prompt 对照。
- strict prompt 对照复用现有候选抽取、raw / candidate 分类、质量 checks、failure reasons 和 language quality gate，只记录 control / variant / improvement / blockers，不替换主流程 prompt、译文、`blockPassed`、失败分类或覆盖图。
- 新增 `ocrCharacterDamageAuditReport`，只审计 `ocrCharacterDamage`、`ocrInputSuspect` 或 `ocrGroundTruthSimilarity < 0.72` 的块，输出 damaged / missing / extra / substitution token、重复关键词损坏、line break risk、TextBox / SegmentMask 证据、crop blockers 和 recommended action。
- OCR 损坏审计允许使用 `test/1.ground_truth.json` 做探针诊断，但不参与生产候选选择、排序、cleanup、promotion 或文本替换。
- `1_ocr_probe_text.txt` 新增两个 report 的逐块摘要和报告级 summary。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.19（路由驱动翻译对照与OCR损坏审计）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明两个新 report 都存在，`routingDrivenTranslationComparisonReport.evaluatedCaseCount <= 5`，`ocrCharacterDamageAuditReport.evaluatedBlockCount > 0`，`1_ocr_probe_text.txt` 包含逐块摘要，且 `configuration.currentBlockSource` 仍为 `fusedWholePageBubble`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.19 新字段；以 PR 后云端结果包为准。
- strict prompt 对照可能变好、变差或无变化，均只作为诊断信号，不代表本轮主流程质量提升。

### v2.3：云端导入 GGUF 并运行漫画探针
日期：2026-06-29
依据：云端验证基础设施改造；本轮修改 CI 和 DEBUG 启动逻辑，不刷新仓库根 `output/`，不追加 `metrics/version_history.csv` 漫画指标行。

核心变更：

- `AITRANS CI Results` workflow 在下载并校验 Release GGUF 后，构建 Debug simulator app。
- workflow 动态选择可用 iOS runtime 和 iPhone simulator device type，创建临时模拟器并安装 `com.local.aitrans`。
- workflow 把 `.ci-models/gemma-3-270m-it-qat-Q4_0.gguf` 复制到 App sandbox `Application Support/Models/Gemma-1.5B/model.gguf`，并校验 SHA256。
- workflow 用 `AITRANS_RUN_MANGA_PROBE=1` 启动 App，等待 `probe_report.json`，校验 `engineUsed = Local GGUF`、`totalBlocksDetected > 0` 和 `blocks` 非空，然后导出本轮 `output/` 到未加密 CI 结果包。
- DEBUG 启动探针逻辑在发现本地模型已安装时自动切换 `selectedEngine = .local`，避免 CI 误用 Mock。
- workflow 将云端探针等待上限提高到 3600 秒，每分钟打印 App 沙盒 `Output` 快照和 `manga_probe_progress.json`，失败时也复制已有 `output/` 到结果包。
- workflow 若发现 `manga_probe_progress.json` 连续 10 分钟不更新，会提前收束日志并失败，避免 App 已启动但探针主任务未推进时空等 3600 秒。
- DEBUG 漫画探针会在 `Output/manga_probe_progress.json` 写入当前阶段、耗时和块数，便于判断卡在 OCR、翻译、渲染还是报告写入。
- DEBUG 启动探针现在会写入 `launch-task-start`、`probe-entry`、`probe-task-start` 等阶段；缺 `test/1.png`、重复运行和运行异常都会写入进度或失败报告，避免只有 `launch-trigger-received` 而没有后续证据。
- workflow 同时通过 `SIMCTL_CHILD_*`、`launchctl setenv`、普通 argv 和 `-AITRANS_RUN_MANGA_PROBE 1` UserDefaults 参数触发 DEBUG 探针；App 侧同时识别环境变量、启动参数和 UserDefaults，并在收到触发后立即写入 `launch-trigger-received` 进度。
- DEBUG 漫画探针启动时跳过 `refreshSpeechRecognitionCapabilities()`，避免云端启动先查询多语言 Speech asset，延迟或干扰探针触发。
- workflow 在开始探针前清空仓库根 `output/`，成功后必须从 App 沙盒导出新 `output/`，并强制校验 `probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt` 和关键 PNG，避免把 checkout 自带旧报告误当云端结果。
- workflow 在导入模型时打印 Release asset、历史目录路径、SHA256 校验和字节数，避免把 `Models/Gemma-1.5B` 目录名误判为 1.5B 模型。
- 结果包新增 `simulator-build.log`、`manga-probe.log`、`app-console.log`、`probe-device-id.txt`、`probe-app-container.txt`、`output/manga_probe_progress.json` 等排查线索。

关键文件：

- `.github/workflows/ci-results.yml`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/test/test.md`
- `md/flow/flow.md`
- `update_log.md`

验证结果：

- 本轮应运行 `git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、workflow smoke 和 YAML 解析。
- 本机不运行 Xcode build / 漫画探针；完整探针由推送后的 GitHub Actions 验证。

验收口径：

- 云端探针报告可解析。
- `engineUsed = Local GGUF`。
- `totalBlocksDetected > 0` 且 `blocks` 非空。
- `probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt` 和关键 PNG 上传到结果包。
- `overallPassed=false` 不单独视为 CI 失败，因为当前模型质量基线仍包含失败块。

已知云端尝试：

- run `28360252442` 在 commit `161383946abb1edcc5929b72df748aa3d5a7d44e` 上完成模型校验、静态检查、Xcode build 和 simulator build，但 `manga-probe.log` 显示 900 秒内未生成 `probe_report.json`，因此不作为通过结果。
- run `28361773796` 在 commit `0c22574dd060a3623e793e314648a4ca6ec55805` 上进入 `Run cloud manga probe` 后 App 已启动但 `Output` 目录持续为空；该现象指向启动触发未进入 App 探针入口，已取消并改为多触发。
- run `28363254764` 在 commit `0c3140b9960061083cec50e17a7538acfa900b49` 上因 workflow 内 `simctl spawn ps` 在 iOS 模拟器中不可用而提前失败；artifact 里的 `output/` 来自 checkout 旧文件，不作为云端探针通过结果。后续已改为清空旧 `output/` 并要求从 App 沙盒导出新结果。
- run `28363769439` 在 commit `5728c14b3dfb26570ff9e5fcbf9eb13cdd631a73` 上清空旧 `output/` 后仍未生成沙盒报告，已取消；App 日志显示启动早期在查询 Speech assets，因此后续跳过云端探针启动时的 Speech capability refresh。
- run `28364280623` 在 commit `3075339a63dad07e887a61c383268d2653c69eb5` 上模型下载、SHA256 校验、Xcode build 和 simulator build 均成功；`manga_probe_progress.json` 停在 `launch-trigger-received`，说明 App 已收到触发但未进入探针主任务。该 run 的模型文件位于历史目录 `Gemma-1.5B`，但 SHA256 和 `241410624` 字节大小确认实际是 Release 的 Gemma 270M GGUF，不是模型传错。
- `AITRANS - Build IPA` run `28364280582` 同 commit 的 archive 失败为 exit 65，GitHub step 只保留 `xcpretty` 摘要，缺少具体 Swift/link/sign 原始错误；workflow 已改为使用 latest stable Xcode、显式 `generic/platform=iOS` destination，并上传 `xcodebuild-archive.log`，同时不改变加密打包密码流程。
- 后续修复把等待上限、App 侧进度文件、停滞检测和日志收集补齐；验收必须看新 run 的 manifest 和 artifact。

遗留事项：

- 若 GitHub-hosted runner 的模拟器启动、App 容器读取或探针耗时不稳定，应优先查看 `manga-probe.log`、`app-console.log`、`output/manga_probe_progress.json` 和 `simulator-build.log`，再决定是否拆分成独立 probe workflow 或继续削减探针云端耗时。

### v1.13 / v22：外部 TextBoxes shadow OCR 候选接入
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.13（外部TextBoxes Shadow OCR候选接入）.md`、PR #3、`AITRANS CI Results` run `28381772143`。本轮修改 Swift 报告模型和探针诊断链路；完整 build / 探针已由 GitHub Actions 验证，仓库根 `output/` 未刷新，长期指标追加到 `metrics/version_history.csv` v22 行。

核心变更：

- 新增 `MangaOverlayExternalTextBoxShadowOCRReport`、block summary 和 candidate report 模型。
- 探针在生成 `externalArtifactReadinessReport` 后运行 external TextBoxes shadow OCR gate；只有 `readinessVerdict = readyForShadowOCR`、`activeArtifactsDirectory = true`、`contractExampleOnly = false` 且 `externalTextBoxesShadowOCRAllowed = true` 才执行 OCR。
- 默认缺 `test/koharu_artifacts/` 时新 report 明确写 `executed = false`、`candidateCount = 0`、`ocrExecutedCount = 0`、所有块 skipped，阻塞原因来自 readiness verdict。
- readiness 通过时，每个 fused block 最多选择 1 个 `externalArtifact.textBoxCrop` candidate；选择只使用 external TextBox 与 block 的 IoU、中心点包含、confidence、bubble alignment 和面积比例等无真值信号。
- external TextBox crop 复用本地 Vision OCR，只把 OCR 文本、quality delta、word preservation、promotion blockers 和 report-only verdict 写入 `probe_report.json` 与 `1_ocr_probe_text.txt`。
- `promotedExternalShadowBlocks` 保持空；若候选满足既有 gate，只写 `wouldPromoteByExistingGateBlocks`，不替换 `finalTextUsedForTranslation`、主覆盖图、`blockPassed`、`configuration.currentBlockSource` 或 `textRegionCropReport.adoptedCount`。
- README、flow、flowchart 和 test 文档同步说明 real detector artifact、contract fixture、readiness gate、external shadow OCR report 和主流程之间的边界。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- Agent B 本地轻量检查通过：`git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、`python3 -m json.tool output/probe_report.json`、`python3 -m json.tool output/clean_text_diagnostic.json`，以及 Koharu artifact validator valid / invalid / allow-missing。
- Agent C 核对 PR #3：base `smalldata_test`、head `codeb/v1.13-external-textbox-shadow-ocr`、head commit `790f72cfc05e354d65351827694748b5db3de0a3`。
- 云端 `AITRANS CI Results` run `28381772143` / attempt `1` 通过；manifest 匹配 `version = v1.13`、`branch = codeb/v1.13-external-textbox-shadow-ocr`、`commitSha = 790f72cfc05e354d65351827694748b5db3de0a3`、`workflowName = AITRANS CI Results`。
- 结果包 `aitrans-ci-v1.13-codeb-v1.13-external-textbox-shadow-ocr--790f72cfc05e-run28381772143-attempt1` 包含 `.xcresult`、`junit.xml`、`xcodebuild.log`、`simulator-build.log`、`manga-probe.log`、`app-console.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md` 和 `output/`。
- `junit.xml`：5 tests、0 failures；GGUF download / verify、static checks、Xcode build、simulator build、manga probe 全部 success。
- 云端探针：`engineUsed = Local GGUF`、`decodingMode = deterministic`、`decodingSeed = 42`、`totalBlocksDetected = 13`、`outputDirectoryCleaned = true`、`overallPassed = false`。
- v1.13 gate 结果：`externalArtifactReadinessReport.readinessVerdict = manifestMissing`、`externalTextBoxesShadowOCRReport.executed = false`、`candidateCount = 0`、`ocrExecutedCount = 0`、`promotedExternalShadowBlocks = []`、`skippedBlocks = [0...12]`。
- 质量数字未因本轮 shadow-only gate 改变：`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、`averageCoreDialogueOCRSimilarity = 0.7106`、`averageDecorativeOCRSimilarity = 0.8000`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- `overallPassed = false` 仍来自当前 Gemma 270M / OCR 质量基线，不作为本轮 v1.13 gate 失败。

验收口径：

- 缺 active artifact 时 shadow OCR 不执行，不新增 `externalArtifact.*` OCR candidate。
- `contractExampleOnly = true` 时 shadow OCR 不执行。
- 真实 active artifact ready 时才允许 external TextBoxes shadow OCR，且每块最多 1 个 candidate。
- candidate 选择和 report-only promotion 不使用 ground truth。
- external OCR 结果只进 report / TXT，不改变主输入、主覆盖图、通过判定或 TextRegion crop adopted 数。

遗留事项：

- 当前仓库默认仍没有真实 active `test/koharu_artifacts/`；若 Koharu 或人工提供 artifact，必须先跑 validator，再由云端探针验证新 report 的 `executed=true` 路径。

### v1.14：Koharu artifact 注入校验与 CI 摘要闭环
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.14（真实KoharuArtifact注入与ShadowOCR验证闭环）.md`。当前没有真实 `test/koharu_artifacts/` active artifact，因此本轮走缺 artifact 路径 B；不创建 active artifact，不刷新漫画指标，不追加 `metrics/version_history.csv`。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 `--print-required-files`，可直接打印 Koharu / 外部 detector 侧需要交付的 active 四件套。
- validator 摘要新增 `readyForShadowOCR`、`nextAction`、`readinessBlockers`、`requiredFiles` 和 `activeArtifactPolicy`，缺 active artifact 时明确返回 `manifestMissing`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided`。
- `AITRANS CI Results` 静态检查会把 `test/koharu_artifacts` validator 摘要写入 `ci-results/koharu-active-artifacts-validation.json`。
- `ci-artifact-manifest.json` 新增 `koharuActiveArtifactValidationPath`、`koharuArtifactValidation`、`externalArtifactReadinessSummary` 和 `externalTextBoxShadowOCRSummary`，Agent C 可直接核对缺 artifact 阻塞路径或未来 executed=true 路径。
- `ci-failure-summary.md` 新增 Koharu artifact gate 小节，列出 active directory、verdict、shadow OCR allowed、nextAction 和 blockers。
- `md/koharu研究/artifact_contract/README.md` 新增从 Koharu 导出到 AITRANS contract 的最小转换要求，继续禁止 examples、Vision、pre-crop plan、line plan、proxy mask、ground truth 或手写理想框冒充真实 detector 输出。
- README、flow、flowchart 和 test 文档同步 v1.14 validator / CI 闭环边界。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.14（真实KoharuArtifact注入与ShadowOCR验证闭环）.md`

验证结果：

- Agent B 本地轻量检查通过：`git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、`python3 -m json.tool output/probe_report.json`、`python3 -m json.tool output/clean_text_diagnostic.json`、validator valid / invalid `--expect-fail`、`--print-required-files` 和 `test/koharu_artifacts --allow-missing`。
- Agent C 核对 PR #4：base `smalldata_test`、head `codeb/v1.14-koharu-artifact-validation-loop`、head commit `2cf9ed0e2db39152006f257236e7e63ad51828da`。
- 云端 `AITRANS CI Results` run `28417554480` / attempt `1` 通过；manifest 匹配 `version = v1.14`、`branch = codeb/v1.14-koharu-artifact-validation-loop`、`commitSha = 2cf9ed0e2db39152006f257236e7e63ad51828da`、`workflowName = AITRANS CI Results`。
- 结果包 `aitrans-ci-v1.14-codeb-v1.14-koharu-artifact-validation-loop--2cf9ed0e2db3-run28417554480-attempt1` 包含 `.xcresult`、`junit.xml`、`xcodebuild.log`、`simulator-build.log`、`manga-probe.log`、`app-console.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`、`koharu-active-artifacts-validation.json` 和 `output/`。
- `junit.xml`：5 tests、0 failures；GGUF download / verify、static checks、Xcode build、simulator build、manga probe 全部 success。
- `koharu-active-artifacts-validation.json`：`verdict = manifestMissing`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided`、`missingArtifacts = [manifest, TextBoxes, BubbleMask, SegmentMask]`，并列出 active 四件套 `requiredFiles`。
- 云端探针：`engineUsed = Local GGUF`、`decodingMode = deterministic`、`decodingSeed = 42`、`totalBlocksDetected = 13`、`outputDirectoryCleaned = true`、`overallPassed = false`。
- App 侧 gate 摘要：`externalArtifactReadinessReport.readinessVerdict = manifestMissing`、`activeArtifactsDirectory = false`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided`。
- Shadow OCR 摘要：`externalTextBoxShadowOCRReport.executed = false`、`candidateCount = 0`、`ocrExecutedCount = 0`、`ocrSucceededCount = 0`、`promotedExternalShadowBlocks = []`、`wouldPromoteByExistingGateBlocks = []`、`skippedBlocks = [0...12]`。
- 质量数字未因本轮 CI 可见性改造改变：`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、`averageCoreDialogueOCRSimilarity = 0.7106`、`averageDecorativeOCRSimilarity = 0.8000`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- Agent C 已通过 PR #4 merge 到 `smalldata_test`，merge commit `a758117`；远端 `codeb/v1.14-koharu-artifact-validation-loop` 已由 PR merge 命令请求删除。

遗留事项：

- 当前仍没有真实 active `test/koharu_artifacts/`，因此不能验证 `externalTextBoxShadowOCRReport.executed = true` 或 OCR 收益。
- 下一步需要 Koharu 或人工提供 `1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`，先由 validator 达到 `readyForShadowOCR`，再通过云端探针核对 executed=true。

### v1.15：Koharu 真实 artifact 交付包 handoff
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.15（Koharu真实Artifact交付包与executed验证）.md`。当前仍没有真实 `test/koharu_artifacts/` active artifact，因此本轮走路径 B；不创建 fake active artifact，不调 Vision crop / line deskew，不刷新漫画指标，不追加 `metrics/version_history.csv`。

核心变更：

- 新增 Agent A v1.15 提示词，明确下一步只验证真实 Koharu / 外部 detector 四件套的 `readyForShadowOCR` 与 `externalTextBoxShadowOCRReport.executed=true`。
- 在 `md/koharu研究/artifact_contract/README.md` 新增 v1.15 真实交付包清单，面向 Koharu / 人工列出四个必需文件、每个文件最低字段、坐标系、图像尺寸、禁止来源、validator 命令和 ready 后的云端验收字段。
- 确认当前 active 目录不存在，validator 阻塞仍是 `manifestMissing`、`nextAction = stopUntilArtifactsProvided`，缺 `manifest`、`TextBoxes`、`BubbleMask`、`SegmentMask`。

关键文件：

- `md/prompt/v1（漫画探针）/v1.15（Koharu真实Artifact交付包与executed验证）.md`
- `md/koharu研究/artifact_contract/README.md`
- `update_log.md`

验证结果：

- 本轮应运行 `git diff --check`、JSON 解析和 Koharu artifact validator valid / invalid / allow-missing / print-required-files。
- 当前 `test/koharu_artifacts` 不存在；`python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing` 返回 `verdict = manifestMissing`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided`。
- 未跑本机 build / 探针；本轮是文档和交付清单收口，不涉及 Swift 代码或探针产物刷新。

验收口径：

- 没有真实 active artifact 时，v1.15 不能声称已验证 `executed=true`。
- 不得把 contract examples、Vision OCR、pre-crop plan、line plan、BubbleMask proxy、SegmentMask proxy、ground truth 或手写框复制到 `test/koharu_artifacts/`。
- Koharu / 人工交付真实四件套后，必须先通过 validator，再由云端探针验证 `readyForShadowOCR` 与 `externalTextBoxShadowOCRReport.executed = true`。

遗留事项：

- 下一步需要 Koharu / 人工提供 `test/1.png` 对应的真实 detector / segmenter 四件套：`1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`。

### v1.16：云端 CI 分层加速与探针快模式
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.16（云端CI分层加速与探针快模式）.md`。本轮是 CI / DEBUG 探针运行制度改造，不刷新漫画质量指标，不追加 `metrics/version_history.csv`。

核心变更：

- `AITRANS CI Results` 新增 `workflow_dispatch` 输入 `probe_mode = ci-fast / full / skip`；`codeb/**` 和 `smalldata_test` push 默认 `ci-fast`。
- 云端 CI 改为单次 Debug simulator build：`Xcode build` 产出 `.xcresult` 和可安装 app，后续步骤只定位并复用 app，不再重复完整 simulator build。
- `ci-fast` 仍安装真实 simulator app、导入 Release GGUF、读取真实 `test/1.png`、使用 deterministic 解码，保留 whole-page OCR、bubble-first 融合、post-fusion cleanup、逐块 Local GGUF 翻译、失败块覆盖、核心 PNG、`probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、Koharu readiness gate 和 external TextBoxes shadow OCR gate。
- `ci-fast` 跳过高成本 shadow-only / 对照层：lexicon comparison、Vision API comparison、synthetic slice、TextRegion crop shadow、crop experiment、TextBox plan failure、line crop、模型 OCR 纠错、确定性纠错翻译、tagged batch、contact sheet 和诊断 PNG。
- DEBUG 探针新增 `AITRANS_MANGA_PROBE_MODE` 读取；报告配置新增 `probeRunMode`、`probeFastPathEnabled`、`skippedDiagnostics`。
- `manga_probe_progress.json` 新增 mode、fast path、跳过项、已保留输出文件和阶段耗时字段。
- manifest 新增 `probeMode`、`probeFastPathEnabled`、`probeSkippedReason`、`probeTimeoutSeconds`、`probeStallTimeoutSeconds`、`probeDurationSeconds`、`probeSkippedDiagnostics`、`probeOutputRequiredFiles`、`probeOutputRetainedFiles`、`probeReportSummary`、`simulatorAppReusedFromXcodeBuild` 和 `simulatorAppPath`。
- `ci-fast` 等待上限为 1800 秒，停滞阈值 300 秒，每 30 秒打印进度；`full` 保留 3600 秒和 600 秒停滞阈值。
- README、flow、flowchart 和 test 文档同步说明 fast / full / skip 边界和 Agent C 验收字段。

关键文件：

- `.github/workflows/ci-results.yml`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.16（云端CI分层加速与探针快模式）.md`

验证结果：

- 本轮 Agent B 本地应运行轻量检查、Koharu validator valid / invalid / allow-missing / print-required-files，以及 workflow YAML smoke。
- 未跑本机 Xcode build / 漫画探针；按规则推送 `codeb/v1.16-ci-probe-fastpath` 后交给 GitHub Actions 验证。
- Agent C 核对 PR #6：base `smalldata_test`、head `codeb/v1.16-ci-probe-fastpath`、head commit `ccd57e4906bf14eaa5b27253fae2d82fa24b581a`。
- 云端 `AITRANS CI Results` run `28420791001` / attempt `1` 通过；manifest 匹配 `version = v1.16`、`branch = codeb/v1.16-ci-probe-fastpath`、`commitSha = ccd57e4906bf14eaa5b27253fae2d82fa24b581a`、`workflowName = AITRANS CI Results`。
- 结果包 `aitrans-ci-v1.16-codeb-v1.16-ci-probe-fastpath--ccd57e4906bf-run28420791001-attempt1` 包含 `.xcresult`、`junit.xml`、`xcodebuild.log`、`simulator-build.log`、`manga-probe.log`、`app-console.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`、`koharu-active-artifacts-validation.json` 和 `output/`。
- `junit.xml`：5 tests、0 failures；GGUF download / verify、static checks、Xcode build、simulator app locate、manga probe 全部 success。
- manifest：`probeMode = ci-fast`、`probeFastPathEnabled = true`、`simulatorAppReusedFromXcodeBuild = true`、`probeTimeoutSeconds = 1800`、`probeStallTimeoutSeconds = 300`、`probeDurationSeconds = 150`。
- 云端探针：`engineUsed = Local GGUF`、`decodingMode = deterministic`、`decodingSeed = 42`、`totalBlocksDetected = 13`、`outputDirectoryCleaned = true`、`overallPassed = false`。
- `ci-fast` 保留输出满足要求：`probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、`1_debug_boxes.png`、`1_translated_overlay.png`、`manga_probe_progress.json`；额外保留 bubble debug PNG。
- `configuration.probeRunMode = ci-fast`、`probeFastPathEnabled = true`，`skippedDiagnostics` 包含 lexicon / Vision API / synthetic slice / TextRegion crop / crop experiment / line crop / tagged batch / correction / contact sheet / diagnostic PNG 等高成本诊断。
- 质量数字：`passedBlocks = 1`、`failedBlocks = 12`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、`averageCoreDialogueOCRSimilarity = 0.6987`、`averageDecorativeOCRSimilarity = 0.8000`、`cleanTextDiagnostic.passRate = 0.4545`。
- Koharu gate：`externalArtifactReadinessReport.readinessVerdict = manifestMissing`、`externalTextBoxesShadowOCRAllowed = false`、`externalTextBoxShadowOCRReport.executed = false`、`candidateCount = 0`、`ocrExecutedCount = 0`、`promotedExternalShadowBlocks = []`、`skippedBlocks = [0...12]`。
- PR #6 已通过 GitHub merge 合并到 `smalldata_test`，merge commit `226de189e1cec63c23130eaf1389c112068ee68e`。

验收口径：

- PR base 必须是 `smalldata_test`，不能指向 `main`。
- `ci-results.yml` 不再重复完整 simulator build。
- 默认云端结果包 manifest 应显示 `probeMode = ci-fast`、`probeFastPathEnabled = true`、`simulatorAppReusedFromXcodeBuild = true`、`engineUsed = Local GGUF`、`totalBlocksDetected > 0` 和关键输出文件。
- `full` 仍可由手动 workflow_dispatch 触发；`skip` 只能用于文档-only 或人工明确跳过，并必须写 `probeSkippedReason`。

遗留事项：

- v1.16 仍不提供真实 active `test/koharu_artifacts/`，因此不能声称验证了 `externalTextBoxShadowOCRReport.executed = true`。

### v1.17：Koharu 真实 artifact 首包缺失退回
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.17（Koharu真实Artifact首包接入与收益归因）.md`。当前仍没有真实 `test/koharu_artifacts/` active artifact，因此本轮走路径 B；不创建 fake active artifact，不改 Swift / CI / 探针主流程，不刷新漫画指标，不追加 `metrics/version_history.csv`。

核心变更：

- 新增 Agent A v1.17 提示词，明确下一步只在真实 Koharu / 外部 detector 四件套到位后验证 `readyForShadowOCR`、云端 `executed=true` 和 shadow OCR 收益归因。
- 新增 `md/koharu研究/v1.17-artifact-first-pass.md`，记录当前第一事实：仓库没有真实 active artifact，因此不能验证 `externalTextBoxShadowOCRReport.executed = true`，也不能判断 Koharu OCR 收益。
- 面向 Koharu / 人工列出首包必须回答的问题：detector 来源、原图坐标转换、bbox 越界、核心对话覆盖、Bubble instance 覆盖、SegmentMask 尺寸、`contractExampleOnly=false`、validator ready 和云端 App bundle 可读。
- 确认本轮不创建 `test/koharu_artifacts/`，不复制 examples，不用 Vision OCR、pre-crop plan、line plan、BubbleMask proxy、SegmentMask proxy、ground truth 或手写框生成 active artifact。

关键文件：

- `md/prompt/v1（漫画探针）/v1.17（Koharu真实Artifact首包接入与收益归因）.md`
- `md/koharu研究/v1.17-artifact-first-pass.md`
- `update_log.md`

验证结果：

- Agent B 本地轻量检查通过：`git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、`python3 -m json.tool output/probe_report.json`、`python3 -m json.tool output/clean_text_diagnostic.json`，以及 Koharu artifact validator valid / invalid / allow-missing / print-required-files。
- Agent C 核对 PR #7：base `smalldata_test`、head `codeb/v1.17-koharu-artifact-first-pass`、head commit `9e467bd089a74f5ced7858a0a243bf5a4ab76d14`。
- 云端 `AITRANS CI Results` run `28422226573` / attempt `1` 通过；manifest 匹配 `version = v1.17`、`branch = codeb/v1.17-koharu-artifact-first-pass`、`commitSha = 9e467bd089a74f5ced7858a0a243bf5a4ab76d14`、`workflowName = AITRANS CI Results`。
- 结果包 `aitrans-ci-v1.17-codeb-v1.17-koharu-artifact-first-pass--9e467bd089a7-run28422226573-attempt1` 包含 `.xcresult`、`junit.xml`、`xcodebuild.log`、`simulator-build.log`、`manga-probe.log`、`app-console.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`、`koharu-active-artifacts-validation.json` 和 `output/`。
- `junit.xml`：5 tests、0 failures；GGUF download / verify、static checks、Xcode build、simulator build、manga probe 全部 success。
- 云端探针：`probeMode = ci-fast`、`engineUsed = Local GGUF`、`decodingMode = deterministic`、`decodingSeed = 42`、`totalBlocksDetected = 13`、`outputDirectoryCleaned = true`、`overallPassed = false`。
- 质量数字：`passedBlocks = 1`、`failedBlocks = 12`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、`averageCoreDialogueOCRSimilarity = 0.6987`、`averageDecorativeOCRSimilarity = 0.8000`、`cleanTextDiagnostic.passRate = 0.4545`。
- Koharu gate：`koharuActiveArtifactsDirectoryPresent = false`、`externalArtifactReadinessReport.readinessVerdict = manifestMissing`、`externalTextBoxesShadowOCRAllowed = false`、`externalTextBoxShadowOCRReport.executed = false`、`candidateCount = 0`、`ocrExecutedCount = 0`、`promotedExternalShadowBlocks = []`、`skippedBlocks = [0...12]`。
- 本轮未跑本机 build / 探针；文档-only 修改按规则交给云端验证。没有真实 active artifact，因此仍不能触发云端 `executed=true` 收益验证。

验收口径：

- 没有真实 active artifact 时，v1.17 不能声称已验证 `executed=true` 或 Koharu OCR 收益。
- 若下一轮提供真实四件套，必须先通过 validator，再由云端 `ci-fast` 证明 `activeArtifactsDirectory = true`、`externalTextBoxesShadowOCRAllowed = true`、`externalTextBoxShadowOCRReport.executed = true`、`candidateCount > 0`、`ocrExecutedCount > 0`。
- 即使 external OCR 有收益，也仍是 shadow-only；不得替换 `finalTextUsedForTranslation`、主覆盖图、`blockPassed`、`configuration.currentBlockSource` 或 `textRegionCropReport.adoptedCount`。

遗留事项：

- 下一步仍需要 Koharu / 人工提供 `test/1.png` 对应的真实 detector / segmenter 四件套：`1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`。

### 方向修正：Koharu 作为算法参考，不再等待外部 artifact
日期：2026-06-30
依据：人工确认“真实 Koharu artifact 没办法跑；不管 Koharu 的结果，只向它的算法和框架靠近，用 AITRANS 自己跑出的图片结果分析 OCR 准确率、气泡、翻译情况，并继续优化算法结构”。本记录是项目方向修正，不是漫画探针质量版本；不刷新 `output/`，不追加 `metrics/version_history.csv`。

核心决策：

- 不再把真实 `test/koharu_artifacts/` 四件套作为后续主线阻塞项。
- 保留现有 external artifact contract、validator、App readiness gate 和 `externalTextBoxShadowOCRReport`，作为将来如果有人提供真实 detector 输出时的可选防伪/诊断入口；但日常优化不等待它。
- Koharu 后续定位调整为算法和框架参考，而不是外部运行依赖。可借鉴的方向包括 TextBoxes 思想、BubbleMask / SegmentMask 中间层、气泡实例归属、mask-safe layout、crop / OCR 候选晋级门槛、失败归因、清字/覆盖结构和 artifact DAG 式诊断。
- 后续主要使用 AITRANS 自己的 `test/1.png` 探针、云端 `ci-fast` / `full` 输出、`probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、关键 PNG 和 `metrics/version_history.csv` 来分析 OCR 准确率、气泡归属/分割、翻译失败分类、覆盖渲染和结构性瓶颈。
- 真实外部 artifact 仍不得伪造；不要用 contract examples、Vision OCR、pre-crop plan、line plan、BubbleMask proxy、SegmentMask proxy、ground truth 或手写框冒充 detector 输出。
- 后续 Agent A 提示词应优先围绕本项目可执行的算法结构优化：例如 OCR block 合并/去重、bubble-first 与 whole-page 融合、气泡分割与归属修正、TextBox/SegmentMask proxy 质量归因、crop 候选晋级、翻译 prompt / 模型对照、报告摘要和可视化排查，而不是继续要求 Koharu / 人工交付四件套。

关键文件：

- `update_log.md`
- `md/koharu研究/koharu图像识别链路研究.md`
- `md/koharu研究/v6～9work.md`
- `md/koharu研究/v1.17-artifact-first-pass.md`
- `md/prompt/v1（漫画探针）/v1.17（Koharu真实Artifact首包接入与收益归因）.md`

验证结果：

- 本轮应运行 `git diff --check`。
- 本轮只改方向记录，不涉及 Swift 代码、CI workflow、探针报告模型或 `output/` 产物。
- 未跑本机 build / 探针；按规则，后续涉及 Swift / 漫画探针改动时仍交给云端验证。

后续执行口径：

- Agent A 下一版提示词不再以“缺真实 Koharu artifact”为阻塞结论。
- Agent B 不应再围绕 `manifestMissing` 做重复文档或 fake artifact 工作。
- Agent C 验收后续算法优化时，重点看当前分支 HEAD 的云端结果包、报告字段、关键 PNG、OCR/气泡/翻译指标和是否保持主流程边界。
- external artifact gate 可以保留在报告中显示 `manifestMissing`，这只是可选外部输入缺失，不再代表主线无法继续。

### v1.18：内部结构瓶颈路由与保守碎片清理
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.18（Koharu式内部结构瓶颈路由与保守清理）.md`。本轮修改 Swift 探针报告模型、post-fusion cleanup 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `internalStructureBottleneckReport`，从最终 blocks、post-fusion cleanup、TextRegion crop、TextBox plan failure、BubbleMask、assignment correction、split candidate、external readiness 和翻译失败分类聚合结构瓶颈路由。
- 每块写出 `primaryBottleneck`、`secondaryBottlenecks`、`recommendedNextAction`、`evidence` 和 `mustNotPromoteReasons`；报告级汇总 primary breakdown、recommended action breakdown、dialogue / decorative breakdown 和关键 block 列表。
- `1_ocr_probe_text.txt` 增加 `internalStructureBottleneck` 逐块摘要；`ci-fast` 也生成该报告，不只在 full 模式生成。
- post-fusion cleanup 新增保守 `duplicateOrFragment` 规则，使用 bbox 强重叠/邻域、bubble 或 mask-safe 邻域、token 覆盖、信息分、OCR 错误启发和保护文本检查清理低信息碎片。
- `fusionComparison.postFusionCleanup.rejectedBlocks[]` 增加 `relatedKeptBlockIndex`、`qualityScore`、`protectedTextMatched` 和 ground-truth-free `evidence`，便于 Agent C 审计拒绝原因。
- 保护文本扩展包含 `The City Battler Tournament starts in a few days.`；external artifact 缺失只作为 optional note，不再作为主线阻塞。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证计划：

- 本轮 Agent B 本地运行轻量检查：`swiftc -parse` 目标 Swift 文件、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `internalStructureBottleneckReport.evaluatedBlockCount = totalBlocksDetected`，breakdown 非空，`1_ocr_probe_text.txt` 含 `internalStructureBottleneck`，且 `configuration.currentBlockSource` 仍为 `fusedWholePageBubble`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.18 新字段；以 PR 后云端结果包为准。
- 若云端 OCR 波动导致新 duplicate/fragment cleanup no-op，本轮仍应通过瓶颈路由报告提供可审计价值；不得为了让 block 数变化而硬编码 block index 或使用 ground truth。

Agent C 退回复修：

- PR #8 初次云端 run `28424308991` 虽然 CI success，但 artifact 显示 post-fusion cleanup 从 `16 -> 11`，误删了远距离真实文本，并产生 `post-fusion cleanup reduced block count below target floor: 11` warning，因此未通过验收。
- 根因 1：`duplicateOrFragment` 的 `sameDominantNeighborhood` 把两个 `nil` 的 `safeLayoutRect` / `maskSafeRect` 当成同邻域证据。修复后只有非空且相等的 safe / mask rect，或真实 same bubble / bbox 重叠 / bbox 邻近，才算邻域证据。
- 根因 2：`internalStructureBottleneckReport` 用 rejected 的 `originalFusedBlockIndex` 去匹配 cleanup 后已重编号的 `block.index`，导致保留块被误标为 `duplicateOrFragment`。修复后保留块写入 `postFusionCleanupOriginalFusedBlockIndex` note，rejected 原始索引只用于报告汇总；逐块 primary / secondary 不再用 rejected 原始索引误判最终保留块。
- 本修复不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`；重新 push 后仍由 GitHub Actions 生成新的 ci-fast artifact 供 Agent C 验收。

Agent C 最终验收：

- PR #8 base 为 `smalldata_test`，head 为 `codeb/v1.18-internal-structure-routing`，最终验收 commit 为 `74d81dce9d90af57058575428c71721e3fd7534f`。
- 云端 `AITRANS CI Results` run `28425069180` / attempt `1` 通过；artifact `aitrans-ci-v1.18-codeb-v1.18-internal-structure-routing--74d81dce9d90-run28425069180-attempt1` 的 manifest 匹配 `version = v1.18`、`branch = codeb/v1.18-internal-structure-routing`、`commitSha = 74d81dce9d90af57058575428c71721e3fd7534f`、`workflowName = AITRANS CI Results`。
- 结果包包含 `.xcresult`、`junit.xml`、`xcodebuild.log`、`ci-failure-summary.md`、`ci-artifact-manifest.json`、`output/probe_report.json`、`output/clean_text_diagnostic.json`、`output/1_ocr_probe_text.txt` 和关键 PNG。
- `junit.xml`：5 tests、0 failures；GGUF verify、static checks、Xcode build、simulator build、manga probe 均为 success。
- 云端探针：`engineUsed = Local GGUF`、`decodingMode = deterministic`、`decodingSeed = 42`、`configuration.currentBlockSource = fusedWholePageBubble`、`probeRunMode = ci-fast`、`totalBlocksDetected = 13`、`outputDirectoryCleaned = true`、`overallPassed = false`。
- post-fusion cleanup 复验通过：`blockCountBeforeCleanup = 16`、`blockCountAfterCleanup = 13`、`rejectedBlockCount = 3`、`warnings = []`、`missingKeyTexts = []`；`THAT'S RIGHT...` 和 `IVE ARRIVED...` 真实文本保留，初次 run 的远距离误删已消失。
- `internalStructureBottleneckReport` 复验通过：`evaluatedBlockCount = 13`，`primaryBottleneckBreakdown = { bubbleAssignmentOrSplit: 2, modelTranslationQuality: 5, ocrCharacterDamage: 5, passed: 1 }`，`recommendedActionBreakdown` 非空，`duplicateOrFragmentBlocks = []`，`postFusionRejectedDuplicateOrFragmentBlocks = []`，`1_ocr_probe_text.txt` 含逐块 `internalStructureBottleneck` 摘要和 `postFusionCleanupOriginalFusedBlockIndex` 证据。
- 质量数字：`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、`averageCoreDialogueOCRSimilarity = 0.6987`、`averageDecorativeOCRSimilarity = 0.8000`、`passedBlocks = 1`、`failedBlocks = 12`、`translationFailureBreakdown = { modelOutputFailure: 3, ocrInputSuspect: 7, translationLanguageQualityFailure: 2 }`、`likelyRuleFalseFailureBlocks = []`、`cleanTextDiagnostic.passRate = 0.4545`。
- `overallPassed = false` 仍来自当前 Gemma 270M / OCR 质量基线，不作为本轮结构路由和 cleanup 修复失败。

### v2.2：GitHub Release GGUF 下载与 Actions 缓存
日期：2026-06-29
依据：云端验证基础设施改造；未刷新 `output/`，未追加 `metrics/version_history.csv` 漫画指标行。

核心变更：

- `AITRANS CI Results` workflow 新增 Release 模型下载、SHA256 校验和 Actions cache。
- 模型来源固定为 Release `model-gemma-3-270m-it-qat-q4_0-v1` 的 `gemma-3-270m-it-qat-Q4_0.gguf`。
- SHA256 固定为 `3626e245220ca4a1c5911eb4010b3ecb7bdbf5bc53c79403c21355354d1e2dc6`。
- 结果包 manifest 新增 `modelReleaseTag`、`modelAsset`、`modelSha256`、`modelCacheKey`、`modelCacheHit`、`modelLocalPath`、`modelDownloadOutcome`、`modelVerifyOutcome`。
- 结果包新增或保留 `model-download.log`、`model-verify.log`，失败摘要中列出模型下载和校验状态。

关键文件：

- `.github/workflows/ci-results.yml`
- `README.md`
- `md/test/test.md`
- `md/flow/flow.md`
- `update_log.md`

验证结果：

- 本轮应运行 `git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、workflow smoke 和 YAML 解析。
- 未运行本机 Xcode build / 漫画探针；按规则交给云端验证。

遗留事项：

- v2.2 只解决模型下载、校验和缓存；下一步才把 `.ci-models/gemma-3-270m-it-qat-Q4_0.gguf` 导入模拟器 App 沙盒的 `Application Support/Models/Gemma-1.5B/model.gguf`，再运行完整漫画探针和导出 `output/`。

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

### v22：Koharu 外部 Artifact 契约与离线 Validator
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.12（Koharu外部Artifact契约与Shadow OCR入口）.md`

核心变更：

- 新增 `md/koharu研究/artifact_contract/README.md`，明确 active 输入目录是 `test/koharu_artifacts/`，非活动 fixture 目录是 `md/koharu研究/artifact_contract/examples/`。
- 新增 valid / invalid contract fixtures；valid fixture 标记 `contractExampleOnly=true`，只用于 schema / parser smoke，不代表真实 detector 输出。
- 新增 `scripts/validate-koharu-artifacts.py`，用 Python 标准库校验 manifest、fallback 路径、TextBoxes、Bubble instances、SegmentMask summary、source image、坐标系、bbox、confidence 和图片尺寸。当前 `test/1.png` 文件名为 `.png`，实际 header 是 JPEG，validator 同时支持 PNG / JPEG header。
- Swift `externalArtifactReadinessReport` 新增 active/example 区分、manifest / artifact 路径、`generatedBy` 和 `externalTextBoxesShadowOCRAllowed`；`contractExampleOnly`、坐标缺失、坐标不匹配、source image 不匹配、bbox / SegmentMask 尺寸错误现在有更明确的 verdict / nextAction。
- GitHub Actions 静态检查加入 artifact validator，并在 `ci-artifact-manifest.json` 记录 validator 日志路径、是否运行和 active artifact 目录是否存在。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `.github/workflows/ci-results.yml`
- `scripts/validate-koharu-artifacts.py`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/artifact_contract/examples/`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本轮应运行 `git diff --check`、JSON 解析和 artifact validator smoke。
- 本轮不跑本机 Xcode build / 漫画探针；Swift build、云端探针和结果包由 PR 后 GitHub Actions 验证。
- 这是 contract / validator 版本，不刷新 `output/`，不追加 `metrics/version_history.csv` 漫画指标行。

遗留事项：

- 当前仓库仍没有真实 `test/koharu_artifacts/` active artifact；没有真实 detector / segmenter 输出时，App 探针应继续阻塞在 `manifestMissing` 或 `artifactFilesMissing`。
- 下一轮只有在人工或外部 Koharu 侧提供真实 TextBoxes / BubbleMask / SegmentMask artifact 后，才允许准备 `externalArtifact.*` shadow OCR candidate；仍不得替换主输入或放宽 promotion gate。

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
### README 更新记录收口到 update_log
日期：2026-06-29

核心变更：

- 删除 README 中的“近期优化记录”长段落，README 改为只保留项目说明、当前用法和稳定规则。
- 明确版本历史、关键决策、验证结果和遗留问题统一写入 `update_log.md`。
- 同步修正 `AGENTS.md` 和 README 中“更新 README 近期记录”的旧维护规则。
- 保留 `metrics/version_history.csv` 作为漫画探针和翻译链路可量化版本的 append-only 指标表。

关键文件：

- `README.md`
- `AGENTS.md`
- `update_log.md`

验证结果：

- 本轮是文档-only 流程收口，按规则运行轻量静态检查。

遗留事项：

- 历史条目已在 `update_log.md` 汇总；后续不要再向 README 追加更新记录。

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
