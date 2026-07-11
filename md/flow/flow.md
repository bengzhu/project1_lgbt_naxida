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
- 音频页展示 Apple Speech 本机识别能力、识别运行摘要、识别文本、译文和取消入口。

关键文件：

- `AITRANS/Views/ContentView.swift`
- `AITRANS/Views/AppTheme.swift`
- `AITRANS/Views/AppComponents.swift`
- `AITRANS/Views/TextTranslationView.swift`
- `AITRANS/Views/TextWorkspaceBackground.swift`
- `AITRANS/Views/TextWorkspacePasteButton.swift`
- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS/Views/AudioTranslationView.swift`
- `AITRANS/Views/HistoryView.swift`
- `AITRANS/Views/PromptLibraryView.swift`
- `AITRANS/Views/SettingsView.swift`
- `AITRANS/Views/ModelManagementView.swift`
- `AITRANS/Views/DeveloperConsoleView.swift`
- `AITRANS/Views/ProFeatureViews.swift`
- `AITRANS/Views/AppPreviewSupport.swift`

正式版本：`1.88`（文本首页科技工作台 + PasteButton + keyboard toolbar 已收口）。

当前布局：

- iPhone 使用文本、图片、音频、历史、设置五入口 `TabView`。
- iPad 使用 `NavigationSplitView`；宽内容优先输入/输出或主检查区/状态区并排，空间不足时通过 `ViewThatFits` 降为单列。
- 文本页头和模型状态位于工作区 `ScrollView` 外的顶部 safe-area inset；键盘自动聚焦只滚动语言栏与输入/输出工作区，页头不会进入系统状态栏区域。
- 文本首页根层使用独立 `TextWorkspaceBackground`：静态冷中性渐变、稳定技术网格和输入到译文的导向线路只服务文本页，不改变其他页面的 `AppCanvasBackground`。
- 文本输入继续直接绑定 `store.draftText`。系统 `PasteButton(payloadType: String.self)` 只在用户点击时接收纯文本：空输入直接写入，已有输入换行追加，不读取或改写剪贴板后台状态，不自动触发翻译。
- 文本页持有唯一 `FocusState`；keyboard toolbar 的“完成”、翻译、新会话和离开文本 Tab 都会先结束焦点。翻译随后仍调用 `store.submitDraft`，没有新增第二套 draft 或业务 store。
- compact-width 文本页在 XXL Dynamic Type 起或输入已聚焦时，才在根 `VStack` 中把 48pt 净空放在 `ScrollView` 之后，使大字号内容与键盘“完成”区域终止于浮动 Tab Bar 上方；标准字号且键盘关闭时不插入该净空，首屏保留完整粘贴与翻译动作。该机制不是内容尾部 padding，也不依赖会被浮动栏覆盖的 bottom safe-area inset。
- `TextWorkspacePasteButton` 内部的真实系统 `PasteButton` 继续承担纯文本粘贴、隐私授权和兼容内容禁用语义；不可点击的实底中文 `Label("粘贴", systemImage: "doc.on.clipboard")` 覆盖系统 locale 标签，不绕开系统粘贴 API。
- `AppTheme` 提供语义颜色、间距、圆角、动效、触控和宽度 token；`AppComponents` 提供页头、区段、状态、按钮、空状态、指标和页面宽度原语。
- 日间/夜间颜色来自 `Assets.xcassets` 的 luminosity variants；`AppAppearance` 通过 `AppStorage` 选择跟随系统、日间或夜间，不进入业务 `state.json`。
- 所有业务按钮只调用 store 公开方法；UI 不直接操作 `state.json`、模型 runtime、Speech task、Vision OCR 或漫画探针服务。
- 实时录音保留触控按住手势，同时提供默认 accessibility action；VoiceOver / Voice Control 激活会在 `beginProLiveSpeechCapture` 与 `endProLiveSpeechCapture` 之间切换。
- 设置页持有显式 `NavigationPath`；`isDeveloperModeEnabled` 关闭时清空 path，开发控制台不能在权限关闭后继续停留或操作。
- `AppPreviewScenario` 通过临时 URL 和 `performsStartupWork=false` 隔离预览，不恢复或持久化生产数据。DEBUG CI 可用 `AITRANS_UI_EVIDENCE_SCENARIO` 复现 11 个截图状态；`audioRecognizing` 同时设置真实 capturing 状态以覆盖 Reduce Motion 分支，生产启动不读取这些场景。
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
- `speechRecognitionRunSummary`：记录音频文件或实时麦克风识别的模式、语言、离线要求、耗时、词数、分段数、平均置信度、最终文本和失败原因。

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

### 1.6 音频识别和翻译
职责：通过 Apple Speech 做本机语音识别，再把识别文本交给统一模型翻译入口。

输入：

- 用户选择的音频文件。
- Pro 页长按麦克风采集的实时音频。
- 当前源语言的 Speech locale 和本机识别能力。

输出：

- `lastRecognizedSpeechText` 或 `proLiveTranscriptText`。
- 翻译后的 `TranscriptLine`。
- `speechRecognitionRunSummary`，用于 UI 展示模式、locale、本机识别要求、耗时、词数、分段数、置信度和错误。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Views/ContentView.swift`
- `AITRANS/Views/ProFeatureViews.swift`

规则：

- 文件识别和实时识别都强制 `requiresOnDeviceRecognition = true`。
- UI 只调用 store 方法，不直接创建 Speech recognizer。
- 识别中和翻译中状态分开展示；用户可取消正在检查或识别的音频任务。
- 每次识别生成独立 run ID；授权、Speech result/error 和翻译完成回调只有在 run ID 仍匹配时才能更新 store。

禁止：

- 不要把 Apple Speech 结果绕过 store 直接写入历史。
- 不要把未授权、设备不支持或空识别文本伪装成成功。

### 1.7 漫画覆盖翻译探针
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
  -> Translation Model Floor 对照矩阵（clean text baseline + strict prompt variant，report-only）
  -> glyph mask / 背景估计 / 安全布局 / 离屏碰撞检查
  -> TextRegion crop shadow 实验矩阵（control + pre-crop plan 候选，不替换主输入）
  -> TextBox plan 失败归因与晋级门槛审计（解释 blockers，不替换主输入）
  -> line-level TextBox / deskew shadow 验证（仅目标块，不替换主输入）
  -> external artifact readiness gate（真实 TextBoxes / BubbleMask / SegmentMask 输入解析、校验、App 侧 identity receipt、sourceImageSHA256 match 和阻塞报告）
  -> external TextBoxes shadow OCR（仅 readiness ready 时执行，每块最多 1 个 externalArtifact.textBoxCrop，不替换主输入；ready 后 candidate coverage 也进入 convergence gate）
  -> external TextBox orientation-aware shadow OCR（真实 artifact ready 后对竖排 / 近 90 度倍数旋转 TextBox 执行有上限 rotation OCR；partial / unsupported / line polygon / 任意角度进入 convergence blockers，阻塞误判闭环）
  -> internal structure bottleneck routing（聚合 OCR / bubble / crop / translation / render 证据，只写报告和 TXT）
  -> reading order structure audit（审计阅读顺序、气泡归属、多块气泡和结构动作，只写报告和 TXT）
  -> structure action candidate matrix（把结构建议转成 report-only work candidates）
  -> Koharu Artifact DAG（阶段账本、首次阻塞与下游影响）
  -> Koharu stage gap replication plan（canonical stage 差距、work package、promotion gate、逐块复刻计划）
  -> Koharu native replication scoreboard（stage scorecard、gate ledger、block scorecard、next work items）
  -> Native TextBox proxy ledger（质量账本、候选来源、gate、stoplist、候选冻结）
  -> BubbleMask assignment / split scoreboard（归属、分割、same-bubble sibling layout、render gate 评分板）
  -> SegmentMask proxy coverage scoreboard（glyph 清字边界、coverage、background fill、render mask 账本）
  -> Koharu Render Regression Lock（RenderedSprites / FinalRender 回归锁、失败覆盖和核心 PNG 账本）
  -> Koharu Pipeline Resolver shadow DAG（needs / produces / dependency propagation / execution queue / op preview）
  -> Koharu WorkOrder Router（执行工作单、逐块路由、预算和 gate 账本）
  -> Koharu External Artifact Request Packet（真实 TextBoxes / BubbleMask / SegmentMask 请求包、required files、逐块缺口和准入 gate）
  -> Koharu Native Algorithm Replay Matrix（本地算法复刻候选、stage matrix、逐块 route、budget gate，report-only）
  -> Koharu BubbleIndex shadow ledger（多数 mask 归属、安全区、同气泡 sibling 分区、split 风险和 render lock，report-only）
  -> Koharu DistanceField SafeArea shadow report（rounded-rect proxy ID mask 的 distance field / safe pixels / maximum safe rect / sprite containment 对照，report-only）
  -> Koharu Bubble Adjacency Seam shadow report（BubbleMask proxy adjacency graph / seam candidate / block seam ledger，report-only）
  -> Koharu RenderSprite Fit Planner report（RenderedSprites 字体预算 / layout candidate / sibling fit / failure fallback 风险账本，report-only）
  -> Koharu Native TextBox Detector-Lite report（source image 像素 / bubble geometry 生成每 bubble 预 OCR TextBox 候选池，shadow-only）
  -> Koharu Native TextBox Detector-Lite Shadow OCR report（受限 detector-lite crop OCR / vertical rotation shadow 评估，report-only）
  -> Koharu Native TextBox Detector-Lite Refinement report（detector-lite 父 bbox 二次收紧 + 受限 refinement shadow OCR，report-only）
  -> Koharu Native TextBox Detector-Lite Closed Loop report（消费 detector-lite / shadow OCR / refinement 和结构诊断做闭环裁决与结构路由，report-only）
  -> Koharu Native BubbleMask Instance-Lite report（source image 像素近白连通域实例 ID mask 账本，report-only）
  -> Koharu Native SegmentMask Refinement-Lite report（TextBox 约束文字像素掩码 refinement 账本，report-only）
  -> Koharu Native Artifact Bundle-Lite report（TextBoxes / BubbleMask / SegmentMask / OCR / Translation / Render 结构一致性闭环，report-only）
  -> Koharu Native Promotion Gate-Lite report（探针驱动 native-lite artifact 晋级门槛 / candidate export preview，report-only）
  -> Koharu Native Artifact Contract Dry-Run report（四件套 artifact contract 必需字段 / sourceImageSHA256 / 禁止来源 / App 侧 identity receipt / validator 命令干跑，report-only）
  -> Koharu Artifact Identity Reconciliation report（App runtime receipt -> CI manifest identity 字段路径 / source image SHA match / size-SHA 对账表，report-only）
  -> Koharu Artifact convergence report（canonical artifact 收敛矩阵、逐块 path、work item closure、linkage / external shadow coverage / orientation gate ledger）
  -> JSON / TXT / PNG 输出
```

探针运行模式：

- `skip`：GitHub Actions push 默认快验模式，不下载 GGUF、不启动模拟器、不跑漫画探针，manifest 必须写明 `probeSkippedReason` 和 `modelSetupSkippedReason`。CI 会先检测变更范围；Swift / Xcode / 资源 / `test/` 素材变化仍跑 Xcode build，非 App 构建相关变更可跳过 Xcode build 并在 manifest 写 `xcodeBuildRequired=false` 与 skip reason。
- `ci-fast`：手动 `workflow_dispatch` 快速探针模式，使用真实 simulator、Local GGUF、`test/1.png`、deterministic 解码、whole-page OCR、bubble-first 融合、逐块翻译、失败块覆盖、clean text diagnostic 和 external artifact gate；跳过 lexicon / Vision API / slice / TextRegion crop shadow / crop experiment / line shadow / tagged batch / 模型纠错 / 纠错翻译对照 / contact sheet 等高成本诊断。
- `full`：开发页按钮和人工 full 回归默认模式，运行完整 shadow-only 对照、diagnostic PNG 和 contact sheet。

手动 workflow 可选提供 Koharu artifact Release archive：`koharu_artifact_release_tag`、`koharu_artifact_asset`、`koharu_artifact_sha256`。CI 会在 Xcode build 前下载、校验、解压并只复制 `1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json` 到 `test/koharu_artifacts/`，随后跑 validator；`koharu_artifact_required=true` 时任一失败都会阻断工作流。该路径只接收真实 detector / segmenter 输出，不从 examples、Vision OCR、pre-crop、line、proxy、ground truth 或手写框生成 active artifact。v1.59 起，注入 archive 后的 `ci-fast/full` 还必须在 App 侧探针产物中证明 `externalArtifactReadinessReport.readinessVerdict = readyForShadowOCR`、`externalTextBoxesShadowOCRAllowed = true`、`externalTextBoxShadowOCRReport.executed = true`、`candidateCount > 0` 和 contract dry-run ready，避免只验证下载 / 解压 / validator 而没有证明 App 真消费到 artifact。v1.64 起，若真实 TextBox 带 vertical source direction、近 90/180/270 度 rotation、linePolygons 或任意角度 rotation，`externalTextBoxShadowOCRReport` 会写入 attempted rotations、selected rotation、language profile、orientation shadow path needed / executed / partial / not executed、unsupported blocks 和 reason breakdown；line polygon warp 和任意角度 deskew 仍不执行，并继续进入 convergence blockers。v1.65 起，validator 先输出 `orientationMetadataSummary`，convergence 再用 `WI/G-external-textbox-shadow-ocr-coverage` 防止 ready artifact 在 shadow OCR 未执行或无 candidate 时被误判为闭环。v1.67 起，App 探针 runtime 在 `externalArtifactReadinessReport.artifactIdentityReceipt` 中记录 source image 与 active 四件套的 size / SHA256；v1.68 起 `koharuArtifactIdentityReconciliationReport` 把这些 App rows 映射到 `ci-artifact-manifest.koharuArtifactValidationIdentitySummary` 字段路径，Actions 注入探针后会生成 `koharuArtifactIdentityReconciliationMatch` 并要求 size/SHA256 逐项匹配。v1.69 起 coverage gate 还要求 `ocrExecutedCount > 0` 和 `ocrSucceededCount > 0`，ready artifact 下未闭合时 gate status 为 blocked。v1.70 起只要填写 Koharu artifact Release archive，`probe_mode` 必须是 `ci-fast` 或 `full`，不能用 `skip`，避免只校验下载包而没有 App 侧消费证据。

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
用户键入文本，或明确点击系统纯文本 PasteButton
  -> 空 draft 直接填入 / 非空 draft 换行追加
  -> store.draftText
  -> 点击翻译，先令 inputFocused = false
  -> TranslationSessionStore.submitDraft / makeRequest
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
  -> external artifact readiness gate / App-side identity receipt
  -> external TextBoxes shadow OCR / orientation-aware shadow path
  -> Koharu Native Artifact contract dry-run
  -> Koharu Artifact identity reconciliation
  -> Koharu Artifact convergence coverage / orientation gates
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
  -> GitHub Actions 运行 JSON / 静态检查 / Xcode build 快验
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
- Agent C 使用独立未加密 CI 结果包验收；`xcodeBuildRequired=true` 时必须核对 `.xcresult`，build-skip 快路径必须核对 skip reason，同时核对 `junit.xml`、`xcodebuild.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`。
- `ci-artifact-manifest.json` 必须能追溯 `version`、`branch`、`commitSha`、`runId`、`runAttempt`、`workflowName`、`scheme`、`destination`、结果路径和探针报告路径。
- 云端失败时，workflow 必须保留日志和失败摘要，Agent C 按结果包指出应交回 Agent B 修复的失败阶段和日志位置。
- 手动探针 workflow 会从 Release `model-gemma-3-270m-it-qat-q4_0-v1` 下载 `gemma-3-270m-it-qat-Q4_0.gguf`，校验 SHA256 `3626e245220ca4a1c5911eb4010b3ecb7bdbf5bc53c79403c21355354d1e2dc6`，并缓存到 `.ci-models/`。
- push 默认 `probe_mode=skip` 快验，只跑静态检查、按 `xcodeBuildRequired` 决定是否跑 Xcode build、manifest 和未加密结果包；不下载 GGUF、不创建模拟器、不安装 App、不跑漫画探针。
- 手动 `workflow_dispatch` 选择 `ci-fast` 或 `full` 时，云端 CI 单次 Debug simulator build 同时产出 `.xcresult` 和可安装 App；探针步骤只定位并复用该 App，不重复完整 `xcodebuild build`。
- 云端漫画探针会创建并启动 iPhone 模拟器，从构建 App 的 `Info.plist` 读取实际 bundle ID，安装 App，把缓存 GGUF 复制到 App sandbox `Application Support/Models/Gemma-1.5B/model.gguf`，用 `AITRANS_RUN_MANGA_PROBE=1` 和 `AITRANS_MANGA_PROBE_MODE` 启动 App，等待并导出本轮 `output/`。
- `ci-artifact-manifest.json` 必须记录 `probeMode`、`probeFastPathEnabled`、`probeSkippedDiagnostics`、`probeOutputRequiredFiles`、`probeOutputRetainedFiles`、`simulatorAppReusedFromXcodeBuild` 和 `simulatorAppPath`。
- push 快验验收静态检查通过；若 `xcodeBuildRequired=true` 还必须 Xcode build 通过，若 `xcodeBuildRequired=false` 必须在 manifest 写明 skip reason。手动探针验收 Release 模型可下载且 SHA 通过、报告可解析、`engineUsed = Local GGUF`、`totalBlocksDetected > 0` 和关键产物存在；`overallPassed=false` 不单独判 CI 失败，因为当前质量基线本身仍有失败块。
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
- v1.13 `externalTextBoxShadowOCRReport` 是 readiness 通过后的 external TextBoxes shadow OCR 层；每个 fused block 最多选 1 个 `externalArtifact.textBoxCrop`，选择只使用 IoU、center containment、confidence、bubble alignment 和面积比例，不使用 ground truth。默认缺 active artifact 时 `executed=false`、`candidateCount=0`、所有块 skipped；即使有 better-than-control 候选也只进入 report / TXT，不改变 `finalTextUsedForTranslation`、主覆盖图、`blockPassed` 或 `textRegionCropReport.adoptedCount`。v1.64 起 report 级写出 `orientationShadowPathPartialBlocks`、`orientationUnsupportedBlocks`、`orientationUnsupportedReasonBreakdown`；`orientationReadinessVerdict = orientationShadowPathExecuted` 必须同时满足无 not-executed 且无 unsupported。v1.69 起 convergence 要求 ready artifact 后 `externalTextBoxShadowOCRReport.executed = true`、`candidateCount > 0`、`ocrExecutedCount > 0` 且 `ocrSucceededCount > 0`，否则 `WI/G-external-textbox-shadow-ocr-coverage` 会以 blocked 阻塞 ExternalArtifacts closed 状态。
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
- v1.28 `koharuArtifactConvergenceReport` 把 v1.22 DAG、v1.23 stage gap、v1.24 native scoreboard、v1.25 TextBox、v1.26 BubbleMask、v1.27 SegmentMask、external artifact readiness、clean text model floor、diagnostics 和最终 blocks 收敛为 Koharu canonical artifact 矩阵、逐块 artifact path、work item closure ledger 和 gate ledger。它关闭前三个 native/proxy scoreboard 的 report-only 工作项，把未闭合项集中到 `WI-translation-model-floor-comparison`、`WI-render-regression-lock` 和 `WI-external-artifact-optional-handoff`；v1.58 起继续消费 v1.57 bundle-lite / promotion gate 的 TextBox -> SegmentMask linkage work item 与 convergence gate，把 weak / fallback / rejected / wrong-bubble linkage 传播到最终 path、stage、work item 和 gate；v1.64 起 `WI-external-textbox-orientation-shadow-path` / `G-external-textbox-orientation-shadow-path` 同时消费 executed / partial / notExecuted / unsupported / reason breakdown，partial 或 unsupported 不得进入 `closedReportOnly`；v1.65 起 `WI-external-textbox-shadow-ocr-coverage` / `G-external-textbox-shadow-ocr-coverage` 先检查 ready artifact 是否真的产生 external shadow OCR candidate；v1.68 起同一 coverage gate 也要求 `koharuArtifactIdentityReconciliationReport.readyForCIManifestComparison = true`，并通过 `WI-koharu-artifact-identity-reconciliation` / `G-koharu-artifact-identity-reconciliation-ready` 暴露 App receipt 与 CI manifest identity 的对账状态。该报告不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、渲染逻辑或 `configuration.currentBlockSource`。ground truth 只进入 evaluationSignals，不参与 firstBlockingArtifact、primaryNextAction、work item status 或 gate。
- v1.69 起 convergence coverage gate 进一步要求 ready artifact 后 `externalTextBoxShadowOCRReport.executed = true`、`candidateCount > 0`、`ocrExecutedCount > 0`、`ocrSucceededCount > 0`，否则 ExternalArtifacts 不得闭合；v1.70 起 App/CI handoff strict closure 还要求 artifact archive 不得配 `probe_mode=skip`，coverage / orientation work item 与 gate ID、status 必须进入 smoke 和 TXT 证据，orientation partial / unsupported blockers 存在时 gate 不得误判 passed。
- v1.29 `translationModelFloorComparisonReport` 执行 `WI-translation-model-floor-comparison`，用 `cleanTextDiagnostic` 的 dialogue baseline 和 `strictChineseOnlyV1` deterministic 变体做同源 clean text 对照，并汇总 noisy final blocks、v1.19 routing strict prompt、tagged batch 和 v1.28 convergence work item。它只分类当前模型 / prompt 地板，不换模型、不改主 prompt、不改逐块主译文、不改覆盖图、`blockPassed`、失败分类或质量规则；clean text ground truth 只进入模型地板评估和 evaluation-only 信号。
- v1.30 `koharuRenderRegressionLockReport` 执行 `WI-render-regression-lock`，把现有 safe layout、mask-safe rect、render collision、render mask overflow、glyph mask、background fill、失败块 fallback 覆盖文本和核心输出文件状态整理成 RenderedSprites / FinalRender 回归账本。它输出逐块 `blockLocks[]`、`artifactStages[]`、`outputFileChecks[]` 和 `gateLedger[]`，并让 convergence 中的 render work item 从未执行 open 推进为 `closedReportOnly` 或 `openRenderIssueDetected`。该报告只写 JSON / TXT，不重新渲染、不新增 OCR / LLM、不解析 PNG 像素做逐块证明、不改变覆盖绘制、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、主 OCR、主翻译、`blockPassed`、失败分类或 `configuration.currentBlockSource`；`proxyNotRealKoharuRenderer = true` 表示它不是 Koharu 真实 renderer / RenderedSprites / inpainting。
- v1.31 `koharuPipelineResolverReport` 在 render lock 之后、最终 convergence 刷新前生成，把现有报告组织成 Koharu 式 `needs` / `produces` / DAG resolver / Op preview 影子层。它输出 stage nodes、edges、逐块 first blocked node、downstream impact、execution queue、op previews 和 gates，并把 `WI-koharu-pipeline-resolver-shadow-dag` / `G-koharu-pipeline-resolver-executed` 联动进 convergence。该报告只写 JSON / TXT，不新增 OCR / LLM、不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充或 `configuration.currentBlockSource`。
- v1.32 `koharuWorkOrderRouterReport` 在 v1.31 resolver 之后、最终 convergence 刷新前生成，把 resolver execution queue、convergence、translation floor、render lock、TextBox / BubbleMask / SegmentMask scoreboards 和 external artifact gate 收束为固定 work orders、逐块 routes、budget ledger 和 gates。它输出 `workOrders[]`、`blockRoutes[]`、`budgetLedger` 和 `gateLedger[]`，并把 `WI-koharu-workorder-router` / `G-koharu-workorder-router-executed` 联动进 convergence。该报告只写 JSON / TXT，不新增 OCR / LLM、不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充或 `configuration.currentBlockSource`。
- v1.36 `koharuDistanceFieldSafeAreaReport` 在 v1.35 BubbleIndex 账本之后、最终 convergence 刷新前生成，只使用 AITRANS rounded-rect BubbleMask proxy ID mask，在每个 bubble bbox 内计算 two-pass chamfer 8-neighbor distance field、safe pixels、histogram maximum safe rect 和 block / sibling safe-area 对照。它输出 `bubbleLedgers[]`、`blockLedgers[]`、`siblingLedgers[]` 和 `gateLedger[]`，并把 `WI-koharu-distance-field-safe-area` / `G-koharu-distance-field-safe-area-executed` 联动进 convergence。该报告只写 JSON / TXT，不新增 OCR / LLM、不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`；ground truth 只进入 evaluation signals。
- v1.37 `koharuBubbleAdjacencySeamReport` 在 v1.36 DistanceField 账本之后、最终 convergence 刷新前生成，只使用 AITRANS 现有 rounded-rect BubbleMask proxy、BubbleIndex、DistanceField、split candidate、same-bubble sibling、OCR damage 和 render lock 证据。它输出 `pairLedgers[]`、`seamCandidateLedgers[]`、`blockLedgers[]` 和 `gateLedger[]`，并把 `WI-koharu-bubble-adjacency-seam` / `G-koharu-bubble-adjacency-seam-executed` 联动进 convergence。该报告只写 JSON / TXT，不新增 OCR / LLM、不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`；ground truth 只进入 evaluation signals。
- v1.38 `koharuRenderSpriteFitPlannerReport` 在 v1.37 seam 账本之后、最终 convergence 刷新前生成，只使用现有 `safeLayoutRect`、`renderFontSize`、`renderNonTransparentBounds`、render collision、失败 fallback、Render Regression Lock、BubbleIndex、DistanceField 和 seam 证据。它输出 `blockLedgers[]`、`layoutCandidateLedgers[]`、`siblingLedgers[]` 和 `gateLedger[]`，并把 `WI-koharu-render-sprite-fit-planner` / `G-koharu-render-sprite-fit-planner-executed` 联动进 convergence。该报告只写 JSON / TXT，不新增 OCR / LLM、不重新渲染 PNG、不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`renderFontSize`、`renderNonTransparentBounds`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`；ground truth 只进入 evaluation signals。
- v1.39 `koharuNativeTextBoxDetectorLiteReport` 在 v1.38 RenderSprite fit planner 之后、最终 convergence 刷新前生成。它只用 source image 像素、bubble geometry、BubbleMask proxy 和 glyph / SegmentMask proxy 生成 OCR 前 `nativeDetectorLite` TextBox 候选池，每个 bubble 最多 4 个 component-cluster 候选 + 1 个不参与 shadow OCR 的 diagnostic union fallback，输出 candidate、candidate->block relation、block、bubble 和 gate ledger，并把 `WI-koharu-native-textbox-detector-lite` / `G-koharu-native-textbox-detector-lite-executed` 联动进 convergence。该报告默认不执行 shadow OCR，不读取 Vision OCR 文本、ground truth、pre-crop plan、line plan 或 TextRegion crop 结果来生成 / 排序候选；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`；`proxyNotRealKoharuTextBoxes = true`。
- v1.40 `koharuNativeTextBoxDetectorLiteShadowOCRReport` 在 v1.39 detector-lite 之后生成，只消费 `shadowOCREligible = true` 的 nativeDetectorLite bbox；`ci-fast` 每块最多 1 个候选、`full` 每块最多 2 个。候选按当前 block 与 bbox 的 overlap / center containment 优先排序；full 模式 block ledger 记录本块 report-only 最佳 shadow OCR 候选。`verticalCandidate` 候选会做有上限的 `[0,90]` rotation shadow OCR 对照，使用 `ja-JP/ja/en-US/en` language profile 并记录 `rotationApplied`，选择只看无真值 OCR 质量和当前文本保词率；ground truth 只进 evaluation signals。该报告不新增 LLM，不写回主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、active artifacts 或 `configuration.currentBlockSource`。
- v1.41 `koharuNativeTextBoxDetectorLiteRefinementReport` 在 v1.40 detector-lite shadow OCR 之后、最终 convergence 刷新前生成。它只用 v1.39 / v1.40 内存报告、final blocks、source image pixels、bubble geometry 和既有诊断信号选择 target 并从 detector-lite 父 bbox 生成 refined bbox；`ci-fast` 总 OCR 预算为 `<= min(6,totalBlocksDetected)`，`full` 每块最多 2 个且有总上限。refined OCR 只进 JSON / TXT，不写回主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、active artifacts 或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals。
- v1.42 `koharuNativeTextBoxDetectorLiteClosedLoopReport` 在 v1.41 refinement 之后、最终 convergence 刷新前生成。它消费 v1.39 detector-lite、v1.40 shadow OCR、v1.41 refinement、final blocks、BubbleMask / SegmentMask proxy、翻译失败分类、Translation Model Floor、Render Regression Lock 和 external artifact readiness，把每块闭环路由到保留当前 fused OCR、full-probe 复核、停止 detector-lite 本地调参、等待真实 TextBoxes / BubbleMask / SegmentMask、模型地板或 render lock。该报告只写 JSON / TXT，不新增 OCR / LLM / PNG，不写回主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals，不参与 route、nextAction、gate 或 candidate family verdict。
- v1.43 `koharuNativeBubbleMaskInstanceLiteReport` 在 v1.42 closed-loop 之后、最终 convergence 刷新前生成。它只用 `test/1.png` 内容裁切区源像素、现有 bubble geometry、final blocks、glyph / SegmentMask proxy、BubbleIndex / DistanceField / seam / RenderSprite fit、detector-lite closed-loop 和 render lock 证据，生成 shadow-only 近白连通域 instance-lite ID mask 账本、逐块 majority assignment、由实例像素 erosion / projection 派生的 safe rect 对照、同 instance 多 block 的 block-scoped safe rect policy、block-scoped sprite containment preview、same-instance sibling sprite collision preview、sibling / adjacency 和 gate ledger。该报告不新增 OCR / LLM / PNG，不创建 active Koharu artifact，不把 instance-lite 冒充真实 Koharu `BubbleMask`，不写回 `safeLayoutRect`、DistanceField safe rect、renderer、主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals，不参与 mask 生成、route、nextAction、verdict 或 gate。
- v1.44 `koharuNativeSegmentMaskRefinementLiteReport` 在 v1.43 instance-lite 之后、最终 convergence 刷新前生成。它只用源图像像素、detector-lite TextBox 候选、final blocks、instance-lite BubbleMask、现有 glyph / SegmentMask proxy、render lock 和翻译失败分类，生成 TextBox 约束文字像素 mask refinement 的 candidate / block / sibling / gate 账本。candidate / block ledger 记录来源 TextBox candidate verdict、block overlap、same-bubble relation、accepted/fallback/rejected linkage verdict、mask 对 TextBox / Bubble 的 containment ratio，并用 v1.43 instance-lite ledger 输出 report-only majority agreement。该报告不新增 OCR / LLM / PNG，不创建 active Koharu artifact，不把 refinement-lite 冒充真实 Koharu `SegmentMask`，不写回主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals，不参与阈值、TextBox 选择、mask、route、nextAction、verdict 或 gate。
- v1.45 `koharuNativeArtifactBundleLiteReport` 在 v1.44 refinement-lite 之后、最终 convergence 刷新前生成。它只消费当前探针内存中的 final blocks、v1.39-v1.42 detector-lite / shadow OCR / refinement / closed-loop、v1.43 BubbleMask instance-lite、v1.44 SegmentMask refinement-lite、RenderSprite fit、Render Regression Lock、Translation Model Floor、external artifact readiness 和 diagnostics，组装每块 TextBox / BubbleMask / SegmentMask / OCR / Translation / Render 的 bundle-lite、consistency edges、primary blocking artifact、nextAction 和聚合 worklist。v1.57 起该报告还消费 v1.44 的 selected TextBox -> SegmentMask linkage，输出 `selectedTextBoxSegmentLinkVerdict`、`textBoxSegmentLinkageStatus`、`textBoxSegmentLinkageRisk`、`TextBoxSegmentMaskLinkage` edge、breakdown 和 review blocks；fallback、weak、rejected 或 wrong-bubble linkage 会阻塞 bundle readiness。该报告不新增 OCR / LLM / PNG，不创建或修改 active Koharu artifact，不把 bundle-lite 冒充真实 Koharu artifacts，不写回主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals，不参与 component 选择、edge、verdict、gate、route、nextAction 或 worklist。
- v1.46 `koharuNativePromotionGateLiteReport` 在 v1.45 bundle-lite 之后、最终 convergence 刷新前生成。它只消费当前探针内存中的 final blocks、diagnostics、v1.39-v1.45 native-lite reports、RenderSprite fit、Render Regression Lock、Translation Model Floor、clean text diagnostic 和 external artifact readiness，为每块输出 TextBoxes / BubbleMask / SegmentMask / OcrText / Translations / RenderedSprites / FinalRender 的晋级状态、stage gates、candidate export preview、work items 和 gate ledger。v1.57 起 promotion ledger 继承 bundle / SegmentMask linkage verdict，输出 `textBoxSegmentLinkVerdict`、`textBoxSegmentLinkagePromotionStatus`、breakdown 和 blocked blocks；fallback、weak、rejected 或 wrong-bubble linkage 会加入 `mustNotPromoteReasons` 并阻塞 SegmentMask promotion。该报告不新增 OCR / LLM / PNG，不更换模型，不创建或修改 active `test/koharu_artifacts/`，不把 promotion gate 冒充真实 Koharu promotion / detector / artifact，不写回主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals，不参与 promotion eligibility、stage gate、candidate preview、route、nextAction 或 worklist。
- v1.47 `koharuNativeArtifactContractDryRunReport` 在 v1.46 promotion gate 之后、最终 convergence 刷新前生成。它只消费 v1.46 candidate export preview 和 `externalArtifactReadinessReport`，把 native-lite / proxy 预览映射到 Koharu active 四件套 contract 的 required files、required fields、forbidden active sources、App 侧 identity receipt、validator commands 和 gate ledger，并把 `WI-koharu-native-artifact-contract-dry-run` / `G-koharu-native-artifact-contract-dry-run-executed` 联动进 convergence。v1.67 起 required file ledger 记录 `fileSizeBytes`、`sha256`、`identityStatus`，顶层记录 `appSideArtifactIdentityVerdict`、files present 和 hashes present；真实 active artifact ready 时，`contractDryRunVerdict = activeArtifactsReadyForShadowOCR` 还要求 App 侧 receipt 完整。该报告 `dryRunOnly = true`、`activeExportAllowed = false`，不创建、复制、修改 `test/koharu_artifacts/`，不新增 OCR / LLM / PNG，不改变主 OCR、翻译输入、覆盖图、renderer、`blockPassed`、失败分类、`safeLayoutRect`、`glyphMaskFillRects`、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`；ground truth 不参与 contract verdict、file status、preview readiness、nextAction 或 gates。
- v1.68 `koharuArtifactIdentityReconciliationReport` 在 contract dry-run 后、最终 convergence 刷新前生成。它只消费 App 侧 `artifactIdentityReceipt` 和 contract dry-run required files，输出 SourceImage + manifest / TextBoxes / BubbleMask / SegmentMask 的 App size / SHA256、对应 `ci-artifact-manifest.koharuArtifactValidationIdentitySummary` 字段路径、comparison status 和 gate ledger；不读取 CI manifest、不新增 OCR / LLM / PNG、不创建或修改 active artifact、不改变主流程。Actions 在真实 artifact 注入探针后会把 validator identity 与 App rows 做 size/SHA256 比对，并在 manifest 写入 `koharuArtifactIdentityReconciliationMatch`。
- v1.18 post-fusion cleanup 新增保守 `duplicateOrFragment` 拒绝规则，只使用 bbox 强重叠/邻域、bubble 或 mask-safe 邻域、token 覆盖、信息分、OCR 错误启发和保护文本检查；不使用 ground truth，不跨气泡合并，不删除 decorative 标题。
- v1.12 / v22 外部 artifact 契约把 active 输入固定为 `test/koharu_artifacts/`，把非活动 fixture 固定为 `md/koharu研究/artifact_contract/examples/`，并用 `scripts/validate-koharu-artifacts.py` 在进入 App 探针前校验 schema、路径、坐标、bbox、confidence、source image、TextBoxes、BubbleMask summary 和 SegmentMask summary。`schemaVersion` 必须等于 `aitrans.koharu_artifact_contract.v1`，manifest 内 artifact path 必须留在 active 目录内，绝对路径和 `..` 逃逸都阻塞；v1.69 起 manifest 缺 `sourceImage`、缺 `contractExampleOnly` 或 `contractExampleOnly` 非布尔值也会阻塞；TextBox 可选 `sourceDirection`、`rotationDegrees` / `rotationDeg`、`linePolygons` 一旦提供，必须通过方向枚举、旋转范围和点位范围校验；active manifest 的 `generatedBy` 必须声明真实 detector / segmenter 来源，缺失或声明为 manual / fixture / Vision OCR / proxy / ground truth / handwritten 来源也会阻塞。只有 `readinessVerdict = readyForShadowOCR`、`activeArtifactsDirectory = true` 且 `contractExampleOnly = false` 时，`externalTextBoxesShadowOCRAllowed` 才能为 true。
- v1.14 validator / CI 闭环不新增 detector 输入；缺真实 active artifact 时继续阻塞，并在 validator JSON 与 `ci-artifact-manifest.json` 中记录 `requiredFiles`、`nextAction`、`readinessBlockers`、`externalArtifactReadinessSummary` 和 `externalTextBoxShadowOCRSummary`，方便 Agent C 确认云端拿到的是缺 artifact 阻塞路径还是 executed=true 路径。v1.65 起 validator JSON 还包含 `orientationMetadataSummary`，CI manifest 透传为 `koharuArtifactValidationOrientationSummary`。v1.66 起 validator JSON 还包含 `artifactIdentitySummary`，记录 source image 与 manifest / TextBoxes / BubbleMask / SegmentMask 的存在性、size、SHA256、`generatedBy`、`generatedAt`、`contractExampleOnly`；CI manifest 透传为 `koharuArtifactValidationIdentitySummary`，failure summary 打印关键 identity，archive 注入只接受唯一一个同时包含四件套的目录。v1.67 起 App 侧探针报告也记录 `artifactIdentityReceipt`，Agent C 需要把 App runtime receipt 和 CI manifest identity 对齐。真实 artifact ready 后，convergence 的 external shadow OCR coverage gate 还要求 App 侧 identity receipt、contract dry-run verdict ready 且 `dryRunOnly=true`、`activeExportAllowed=false`，以及 external shadow OCR executed / candidate / OCR execution / OCR success 四项同时成立。
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
