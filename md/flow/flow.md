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
- 核心 PNG：`1_debug_boxes.png`、`1_translated_overlay.png`。
- `full` 模式还输出多张诊断 PNG，包括 `1_probe_contact_sheet.png`。

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
  -> external TextBoxes shadow OCR（仅 readiness ready 时执行，每块最多 1 个 externalArtifact.textBoxCrop，不替换主输入）
  -> internal structure bottleneck routing（聚合 OCR / bubble / crop / translation / render 证据，只写报告和 TXT）
  -> reading order structure audit（审计阅读顺序、气泡归属、多块气泡和结构动作，只写报告和 TXT）
  -> structure action candidate matrix（把结构建议转成 report-only work candidates）
  -> Koharu Artifact DAG（阶段账本、首次阻塞与下游影响）
  -> Koharu stage gap replication plan（canonical stage 差距、work package、promotion gate、逐块复刻计划）
  -> Koharu native replication scoreboard（stage scorecard、gate ledger、block scorecard、next work items）
  -> Native TextBox proxy ledger（质量账本、候选来源、gate、stoplist、候选冻结）
  -> BubbleMask assignment / split scoreboard（归属、分割、same-bubble sibling layout、render gate 评分板）
  -> SegmentMask proxy coverage scoreboard（glyph 清字边界、coverage、background fill、render mask 账本）
  -> Koharu Artifact convergence report（canonical artifact 收敛矩阵、逐块 path、work item closure、gate ledger）
  -> JSON / TXT / PNG 输出
```

探针运行模式：

- `full`：开发页按钮和人工 full 回归默认模式，运行完整 shadow-only 对照、diagnostic PNG 和 contact sheet。
- `ci-fast`：GitHub Actions 日常 `codeb/**` / `smalldata_test` push 默认模式，仍使用真实 simulator、Local GGUF、`test/1.png`、deterministic 解码、whole-page OCR、bubble-first 融合、逐块翻译、失败块覆盖、clean text diagnostic 和 external artifact gate；跳过 lexicon / Vision API / slice / TextRegion crop shadow / crop experiment / line shadow / tagged batch / 模型纠错 / 纠错翻译对照 / contact sheet 等高成本诊断。
- `skip`：只允许 workflow 手动跳过探针，manifest 必须写明 `probeSkippedReason`；App 侧不会把 skip 当作可验收探针运行。

报告会在 `configuration.probeRunMode`、`configuration.probeFastPathEnabled`、`configuration.skippedDiagnostics` 和 `manga_probe_progress.json` 中记录模式、跳过项、保留输出文件和阶段耗时。

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
  -> internalStructureBottleneckReport
  -> routingDrivenTranslationComparisonReport / ocrCharacterDamageAuditReport
  -> readingOrderStructureAuditReport
  -> structureActionCandidateReport
  -> koharuArtifactDAGReport
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
  -> Agent B 创建 PR：base=smalldata_test, head=codeb/...
  -> GitHub Actions 运行 build / JSON / 静态检查 / 可用探针
  -> GitHub Actions 上传未加密 CI 结果包
  -> Agent C 通过 PR 和结果包核对 diff、日志、manifest 和 artifact
      -> 失败：C 输出退回清单，B 按结果包日志继续修
      -> 通过：C 更新核心文档，经 PR merge 合并回 smalldata_test
      -> C 删除远端 codeb/... 候选分支
```

分支规则：

- `main` 只作为外观展示分支，禁止合并日常开发成果。
- `smalldata_test` 是当前远端真实工作主分支；若旧提示词写成 `samlldata_test`，以 `origin/smalldata_test` 为准。
- `codeb/vX.Y-短标题` 是 Agent B 候选实现分支。
- Agent B push 后默认创建 PR 到 `smalldata_test`；Agent C 通过 PR merge 收口。
- Agent C 合并后必须删除远端 `codeb/...` 候选分支，或说明没有权限删除，避免长期堆积。

结果包规则：

- 加密打包 workflow 只负责软件包交付，不作为 Agent C 验收依据，不为验收改动密码或解密流程。
- Agent C 使用独立未加密 CI 结果包验收，至少核对 `.xcresult`、`junit.xml`、`xcodebuild.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`。
- `ci-artifact-manifest.json` 必须能追溯 `version`、`branch`、`commitSha`、`runId`、`runAttempt`、`workflowName`、`scheme`、`destination`、结果路径和探针报告路径。
- 云端失败时，workflow 必须保留日志和失败摘要，Agent C 按结果包指出应交回 Agent B 修复的失败阶段和日志位置。
- 云端结果包 workflow 会从 Release `model-gemma-3-270m-it-qat-q4_0-v1` 下载 `gemma-3-270m-it-qat-Q4_0.gguf`，校验 SHA256 `3626e245220ca4a1c5911eb4010b3ecb7bdbf5bc53c79403c21355354d1e2dc6`，并缓存到 `.ci-models/`。
- 云端 CI 单次 Debug simulator build 同时产出 `.xcresult` 和可安装 App；探针步骤只定位并复用该 App，不重复完整 `xcodebuild build`。
- 云端漫画探针会创建并启动 iPhone 模拟器，安装 `com.local.aitrans`，把缓存 GGUF 复制到 App sandbox `Application Support/Models/Gemma-1.5B/model.gguf`，用 `AITRANS_RUN_MANGA_PROBE=1` 和 `AITRANS_MANGA_PROBE_MODE` 启动 App，等待并导出本轮 `output/`。
- `ci-artifact-manifest.json` 必须记录 `probeMode`、`probeFastPathEnabled`、`probeSkippedDiagnostics`、`probeOutputRequiredFiles`、`probeOutputRetainedFiles`、`simulatorAppReusedFromXcodeBuild` 和 `simulatorAppPath`。
- 云端探针验收报告可解析、`engineUsed = Local GGUF`、`totalBlocksDetected > 0` 和关键产物存在；`overallPassed=false` 不单独判 CI 失败，因为当前质量基线本身仍有失败块。
- 本阶段不提交模型文件，Release asset 是云端模型来源。

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
- v1.13 `externalTextBoxShadowOCRReport` 是 readiness 通过后的 external TextBoxes shadow OCR 层；每个 fused block 最多选 1 个 `externalArtifact.textBoxCrop`，选择只使用 IoU、center containment、confidence、bubble alignment 和面积比例，不使用 ground truth。默认缺 active artifact 时 `executed=false`、`candidateCount=0`、所有块 skipped；即使有 better-than-control 候选也只进入 report / TXT，不改变 `finalTextUsedForTranslation`、主覆盖图、`blockPassed` 或 `textRegionCropReport.adoptedCount`。
- v1.18 `internalStructureBottleneckReport` 是 AITRANS 自有探针的结构瓶颈路由层；它从最终 blocks、post-fusion cleanup、TextRegion crop、TextBox plan failure、BubbleMask、assignment correction、split candidate、external readiness 和翻译失败分类现场汇总 `primaryBottleneck` / `recommendedNextAction`，不依赖外部 artifact，不改变主流程文本、覆盖图或通过判定。
- v1.19 `routingDrivenTranslationComparisonReport` 只针对 `modelTranslationQuality` 路由块做最多 5 个 strict prompt deterministic 对照，复用既有候选抽取、分类和质量判定；结果只写 JSON / TXT，不替换漫画主 prompt、主译文、`blockPassed`、失败分类或覆盖图。
- v1.19 `ocrCharacterDamageAuditReport` 只针对 `ocrCharacterDamage` / `ocrInputSuspect` / 低相似度块做 token 级损坏审计；ground truth 仅用于探针诊断，报告 damaged / missing / extra / substitution token、line break risk、TextBox / SegmentMask 证据和 crop blockers，不参与生产候选选择或文本替换。
- v1.20 `readingOrderStructureAuditReport` 是 Koharu 式页面结构计划审计层；它从最终 blocks、bbox、bubbleID / maskDominantBubbleID、safeLayoutRect、TextBox / SegmentMask proxy、post-fusion cleanup 和路由报告现场计算 proposed reading order、bubble group、same-bubble siblings、归属/分割/重复风险和结构动作建议。该报告只写 JSON / TXT，不改变 `blocks` 顺序、批量输入、翻译文本、覆盖图、cleanup、候选选择或通过判定。
- v1.21 `structureActionCandidateReport` 把 v1.20 的结构建议转成可执行 shadow 候选矩阵，候选类型覆盖阅读顺序、气泡归属、气泡拆分、同气泡 sibling layout、重复保护、TextBox/SegmentMask 证据要求、渲染 safe-area reflow 和人工复核。它输出 control/shadow metrics、delta、promotion verdict、blockers 和 next step，只使用已有报告与几何/渲染/shadow OCR 摘要，不新增 OCR / LLM 调用，不重排 `blocks`，不改变翻译输入、覆盖图、`blockPassed`、失败分类、cleanup 或 metrics；缺真实 Koharu artifact 时只输出阻塞和 `provideRealKoharuArtifact`。
- v1.22 `koharuArtifactDAGReport` 是 Koharu 式 Artifact DAG 阶段账本；它把 SourceImage、ContentCrop、OCR、BubbleMask、TextBoxes、SegmentMask、translation、render 和 v1.21 结构动作候选组织成 dependency edges、stage summaries 和逐块 trace，定位每块 `firstBlockingStage` 与 `downstreamImpact`。该报告只复用既有证据，不新增 OCR / LLM，不改变主流程；缺真实 active artifact 时只阻塞真实 TextBoxes / BubbleMask / SegmentMask promotion，不把当前主流程整体判废。
- v1.23 `koharuStageGapReplicationReport` 把 v1.22 DAG 转成 Koharu canonical stage 差距、最小 work package、promotion gate 和逐块复刻计划。它区分 `realKoharuArtifactReady`、`aitransInternalReady`、`aitransProxyOnly`、`shadowOnly`、`missingExternalArtifact` 等能力状态，标出哪些阶段可用 `ci-fast` 继续验证、哪些需要 `full` 探针、哪些必须等待真实 `test/koharu_artifacts/`。该报告仍只写 JSON / TXT，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- v1.24 `koharuNativeReplicationScoreboardReport` 只依赖 AITRANS 自己的 probe 输出，把 v1.23 stage gap / work package 转成 native stage scorecard、gate ledger、block scorecard 和下一轮 work items。它不要求真实 external artifact；缺 artifact 只作为 `externalOptionalMissing` 可选外部路径状态，不阻塞 native scoreboard。所有 priority、gate 和 nextAction 使用 ground-truth-free decision signals；`test/1.ground_truth.json` 相关数字只能作为 evaluation-only 指标。报告明确区分 native / proxy / shadow / stop / model-limited / render-stable 状态，并把已证伪的 crop / line / deskew 本地试参加入 stoplist；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- v1.25 `nativeTextBoxProxyLedgerReport` 执行 v1.24 的 `WI-native-textbox-artifact-scorecard`，把现有 TextBox / crop / line / BubbleMask / SegmentMask / OCR damage / v1.24 scoreboard 证据整理成 Native TextBox proxy 质量账本。它输出 `blockLedgers[]`、`candidateLedgers[]`、`gateLedger[]` 和 `stoplist[]`，区分 `reportOnlyStable`、`shadowOnlyEligible`、`frozenByStoplist`、word preservation / BubbleMask / SegmentMask / OCR damage / model floor 阻塞和 `manualReviewOnly`。候选冻结、排序、qualityStatus 和 nextAction 只能使用 ground-truth-free decision signals；ground truth 只进入 evaluationSignals。报告只写 JSON / TXT，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- v1.26 `bubbleMaskAssignmentSplitScoreboardReport` 执行 v1.24 的 `WI-bubblemask-assignment-split-scorecard`，把现有 BubbleMask proxy、归属修正、split candidate、reading order、structure action、Koharu native scoreboard 和 Native TextBox ledger 证据整理成 BubbleMask 归属 / 分割 / sibling 布局评分板。它输出 `blockScorecards[]`、`bubbleScorecards[]`、`splitCandidateLedgers[]`、`siblingLayoutScorecards[]` 和 `gateLedger[]`，区分 `consistent`、`correctionRecommendedReportOnly`、`correctionAppliedToCropClampOnly`、`maskConflict`、`splitCandidateEligibleReportOnly`、`sameBubbleSiblingLayoutStable`、`needsRealBubbleMask` 和 render mask 状态。assignment、split、sibling layout、nextAction 和 promotion blockers 只能使用 ground-truth-free decision signals；ground truth 只进入 evaluationSignals。报告只写 JSON / TXT，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect` 或 `configuration.currentBlockSource`。
- v1.27 `segmentMaskProxyCoverageScoreboardReport` 执行 v1.24 的 `WI-segmentmask-proxy-coverage-scorecard`，把现有 glyph mask、SegmentMask proxy、TextBox 覆盖、BubbleMask 覆盖、safe rect、背景填充和渲染碰撞证据整理成 SegmentMask proxy 覆盖评分板。它输出 `blockScorecards[]`、`cleanupLedgers[]` 和 `gateLedger[]`，区分 `usableProxyCoverage`、`usableForCleanupOnly`、弱 TextBox / BubbleMask / safe rect 覆盖、清字边界、background fill guardrail、render mask 状态和 `needsRealSegmentMask`。coverage、cleanup、nextAction 和 gate 只能使用 ground-truth-free decision signals；ground truth 只进入 evaluationSignals。报告只写 JSON / TXT，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为或 `configuration.currentBlockSource`。
- v1.28 `koharuArtifactConvergenceReport` 把 v1.22 DAG、v1.23 stage gap、v1.24 native scoreboard、v1.25 TextBox、v1.26 BubbleMask、v1.27 SegmentMask、external artifact readiness、clean text model floor、diagnostics 和最终 blocks 收敛为 Koharu canonical artifact 矩阵、逐块 artifact path、work item closure ledger 和 gate ledger。它关闭前三个 native/proxy scoreboard 的 report-only 工作项，把未闭合项集中到 `WI-translation-model-floor-comparison`、`WI-render-regression-lock` 和 `WI-external-artifact-optional-handoff`；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、渲染逻辑或 `configuration.currentBlockSource`。ground truth 只进入 evaluationSignals，不参与 firstBlockingArtifact、primaryNextAction、work item status 或 gate。
- v1.18 post-fusion cleanup 新增保守 `duplicateOrFragment` 拒绝规则，只使用 bbox 强重叠/邻域、bubble 或 mask-safe 邻域、token 覆盖、信息分、OCR 错误启发和保护文本检查；不使用 ground truth，不跨气泡合并，不删除 decorative 标题。
- v1.12 / v22 外部 artifact 契约把 active 输入固定为 `test/koharu_artifacts/`，把非活动 fixture 固定为 `md/koharu研究/artifact_contract/examples/`，并用 `scripts/validate-koharu-artifacts.py` 在进入 App 探针前校验 schema、路径、坐标、bbox、confidence、source image、TextBoxes、BubbleMask summary 和 SegmentMask summary。只有 `readinessVerdict = readyForShadowOCR`、`activeArtifactsDirectory = true` 且 `contractExampleOnly = false` 时，`externalTextBoxesShadowOCRAllowed` 才能为 true。
- v1.14 validator / CI 闭环不新增 detector 输入；缺真实 active artifact 时继续阻塞，并在 validator JSON 与 `ci-artifact-manifest.json` 中记录 `requiredFiles`、`nextAction`、`readinessBlockers`、`externalArtifactReadinessSummary` 和 `externalTextBoxShadowOCRSummary`，方便 Agent C 确认云端拿到的是缺 artifact 阻塞路径还是 executed=true 路径。
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
