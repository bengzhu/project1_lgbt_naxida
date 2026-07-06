# 项目流程图
本文用 Mermaid 图展示 `md/flow/flow.md` 的当前核心逻辑。读图时先看左到右的主链路，再看向下分叉的诊断和输出产物。

## 1. 项目核心逻辑图
这张图描述 App 从用户入口到状态调度、OCR/模型服务、持久化和探针输出的关系。

```mermaid
flowchart TD
  %% 用户入口：文本、图片、音频、开发页探针
  A["用户操作 / test 固定素材"] --> B["SwiftUI UI 层<br/>文本 / 图片 / 音频 / 历史 / 设置 / 开发页"]

  %% 状态中心：所有业务动作统一进入 store
  B --> C["TranslationSessionStore<br/>统一状态、调度、持久化、诊断"]

  %% 文本翻译分支：普通用户输入
  C --> D["文本翻译请求<br/>ModelGenerationRequest"]
  D --> E["LocalLanguageModeling<br/>Mock 或 Local"]
  E --> F["MockGemmaService<br/>UI 和数据流冒烟"]
  E --> G["GemmaLocalService<br/>GGUF 本地模型适配"]
  G --> H["LlamaRuntime<br/>llama.cpp C API 封装"]

  %% 图片 OCR 分支：普通图片翻译
  C --> I["普通图片翻译<br/>VisionOCRService"]
  I --> J["ImageTranslationBlock<br/>bbox + OCR 文本 + 译文"]
  J --> K["图片旁贴 / 覆盖 UI"]

  %% 音频分支：Apple 本机语音识别
  C --> L["音频识别<br/>Apple Speech on-device"]
  L --> D

  %% 漫画探针分支：固定 test/1.png
  C --> M["漫画覆盖翻译探针<br/>test/1.png"]
  M --> N["MangaOverlayProbeService<br/>裁切、多角度 OCR、气泡归属、合并"]
  N --> O["逐块翻译和质量判定<br/>失败块仍写报告和绘制"]
  O --> P["探针模式门控<br/>ci-fast / full / skip"]
  P --> Q["覆盖渲染<br/>safeLayoutRect / glyph mask / 核心 PNG"]

  %% 输出：持久化和调试产物
  C --> R["state.json<br/>会话、历史、提示词、设置"]
  Q --> S["App 沙盒 Output<br/>JSON / TXT / PNG"]
  S --> T["scripts/export-probe-output.sh<br/>导出到项目根 output/"]
  T --> U["metrics/version_history.csv<br/>长期指标 append-only"]
```

## 2. 漫画探针执行流
这张图只看 `test/1.png` 的 OCR、翻译和覆盖合成链路。实线是主流程，旁路节点是诊断对照，不能在未验证前替代主流程。

```mermaid
flowchart TD
  %% 输入：固定 bundle 素材
  A["test/1.png<br/>固定漫画截图"] --> B["裁切内容区<br/>去掉浏览器 UI、广告、底部导航"]

  %% OCR：整页与气泡候选
  B --> C["2x 放大 + 0/90/180/270 Vision OCR<br/>生成 OCR candidates"]
  C --> D["气泡候选检测<br/>white component + OCR seed"]
  D --> E["bubbleID 归属<br/>unassigned 块保留"]
  E --> F["同 bubble 合并<br/>跨 bubble 合并拒绝"]
  F --> W["whole-page OCR blocks<br/>保留原始对照"]
  D --> J["bubble-first OCR candidates<br/>气泡 crop 内识别和拆块"]
  W --> G["fused OCR blocks<br/>whole-page + bubble-first 融合"]
  J --> G
  G --> X["fusionComparison / fusionResults<br/>选择、替换、拒绝可审计"]
  X --> Y["post-fusion cleanup<br/>重复 / 碎片 / 低信息块拒绝"]
  Y --> U["BubbleMask 子区域诊断<br/>block-local subregion"]
  U --> BM["BubbleMask 实例 ID 近似<br/>mask-safe layout / collision / crop coverage"]
  BM --> BA["BubbleMask 归属修正 / split candidate<br/>ground-truth-free 保守采用"]
  BA --> PTB["preCropTextBoxPlanReport<br/>TextRegion crop 前上游 plan / shadow-only"]
  PTB --> V["TextRegion crop OCR<br/>split / corrected bubble / subregion / bubble / content clamp + 护栏回退"]
  V --> GV["ground-truth-free crop 护栏选择<br/>不放宽 adopted 规则"]
  GV --> TB["TextBox / SegmentMask 派生证据层<br/>crop 后诊断 / failure attribution"]
  D --> Z["bubbleAudits<br/>过大气泡和分割候选诊断"]
  Z --> U

  %% 诊断旁路：不替代主流程
  TB --> H["自适应 crop 二次 OCR<br/>诊断和候选对照"]
  TB --> I["确定性 OCR 纠错候选<br/>只做对照"]
  TB --> K["slice OCR 对照<br/>长图触发"]

  %% 翻译：逐块主路径
  TB --> L["逐块英译中<br/>Mock 或 Local GGUF"]
  L --> M["候选抽取与质量判定<br/>raw / candidate / failureCategory"]
  M --> N["失败块保留<br/>blockPassed=false + failureReasons"]

  %% 报告和渲染
  N --> O["safeLayoutRect<br/>多块同气泡分区"]
  O --> P["glyph mask + 背景估计<br/>纯色块才填充"]
  P --> MODE{"probeRunMode"}
  MODE -- "full" --> CE["cropExperimentReport<br/>control + pre-crop plan shadow OCR"]
  MODE -- "ci-fast" --> EAR
  CE --> TBF["textBoxPlanFailureReport<br/>plan / candidate / block 失败归因与晋级 blockers"]
  TBF --> LTB["lineTextBoxPlanReport / lineCropExperimentReport<br/>目标块行级 TextBox / deskew shadow 验证"]
  LTB --> EAR["externalArtifactReadinessReport<br/>真实 TextBoxes / BubbleMask / SegmentMask 适配前证据闸门 + App-side identity receipt"]
  EAR --> ETS["externalTextBoxShadowOCRReport<br/>ready 后每块最多 1 个 externalArtifact.textBoxCrop / shadow-only"]
  ETS --> ESC["external TextBox shadow OCR coverage gate<br/>ready 后要求 identity reconciliation + contract dry-run + executed + candidateCount > 0"]
  ESC --> ETO["external TextBox orientation-aware shadow OCR<br/>bounded rotation OCR / partial 与 unsupported 进入 convergence blockers"]
  ETO --> ISR["internalStructureBottleneckReport<br/>OCR / bubble / crop / translation / render 路由诊断"]
  ISR --> RTA["routingDrivenTranslationComparisonReport<br/>modelTranslationQuality 块 strict prompt 对照 / report-only"]
  RTA --> TMF["translationModelFloorComparisonReport<br/>clean text baseline + strict prompt 地板对照"]
  ISR --> ODA["ocrCharacterDamageAuditReport<br/>OCR 损坏 token 审计 / report-only"]
  ISR --> ROA["readingOrderStructureAuditReport<br/>阅读顺序 / 气泡归属 / 结构动作审计 / report-only"]
  ROA --> SAC["structureActionCandidateReport<br/>结构动作候选矩阵 / shadow 执行评估 / report-only"]
  SAC --> KAD["koharuArtifactDAGReport<br/>Artifact DAG 阶段账本 / firstBlockingStage / report-only"]
  KAD --> KSG["koharuStageGapReplicationReport<br/>canonical stage 差距 / work package / promotion gate / report-only"]
  KSG --> KNS["koharuNativeReplicationScoreboardReport<br/>stage scorecard / gate ledger / block scorecard / next work items"]
  KNS --> NTB["nativeTextBoxProxyLedgerReport<br/>TextBox proxy quality ledger / gates / stoplist"]
  NTB --> BMS["bubbleMaskAssignmentSplitScoreboardReport<br/>assignment / split / sibling layout scorecard"]
  BMS --> SMS["segmentMaskProxyCoverageScoreboardReport<br/>glyph cleanup / coverage / render mask ledger"]
  SMS --> KRL["koharuRenderRegressionLockReport<br/>RenderedSprites / FinalRender lock ledger"]
  KRL --> KPR["koharuPipelineResolverReport<br/>needs / produces DAG resolver / op preview"]
  KPR --> KWR["koharuWorkOrderRouterReport<br/>work orders / routes / budget gates"]
  KWR --> KER["koharuExternalArtifactRequestPacketReport<br/>required files / artifact requests / gate ledger"]
  KER --> KNR["koharuNativeAlgorithmReplayMatrixReport<br/>native replay candidates / stage matrix / block routes"]
  KNR --> KBI["koharuBubbleIndexShadowLedgerReport<br/>BubbleIndex majority mask / safe area / sibling partition"]
  KBI --> KDF["koharuDistanceFieldSafeAreaReport<br/>distance field / safe pixels / maximum safe rect"]
  KDF --> KAS["koharuBubbleAdjacencySeamReport<br/>adjacency graph / seam candidate ledger"]
  KAS --> KRS["koharuRenderSpriteFitPlannerReport<br/>font budget / layout candidate / sibling fit ledger"]
  KRS --> KNT["koharuNativeTextBoxDetectorLiteReport<br/>pre-OCR TextBox candidates + block relation"]
  KNT --> KNSO["koharuNativeTextBoxDetectorLiteShadowOCRReport<br/>detector-lite TextBoxes -> OCR / vertical rotation shadow loop"]
  KNSO --> KNTR["koharuNativeTextBoxDetectorLiteRefinementReport<br/>detector-lite parent bbox refinement + shadow OCR"]
  KNTR --> KNTCL["koharuNativeTextBoxDetectorLiteClosedLoopReport<br/>closed-loop route / stoplist / artifact routing"]
  KNTCL --> KNBM["koharuNativeBubbleMaskInstanceLiteReport<br/>instance mask / scoped safe rect / sprite + sibling collision"]
  KNBM --> KNSMR["koharuNativeSegmentMaskRefinementLiteReport<br/>TextBox-linked SegmentMask refinement / containment ratio"]
  KNSMR --> KNABL["koharuNativeArtifactBundleLiteReport<br/>TextBoxes / BubbleMask / SegmentMask consistency + linkage closure"]
  KNABL --> KNPG["koharuNativePromotionGateLiteReport<br/>probe-driven promotion gates / linkage-blocked preview"]
  KNPG --> KNCD["koharuNativeArtifactContractDryRunReport<br/>four-file contract dry-run / App-side identity receipt / validator commands"]
  KNCD --> KIR["koharuArtifactIdentityReconciliationReport<br/>App receipt -> CI manifest identity field paths / size-SHA ledger"]
  KIR --> KAC["koharuArtifactConvergenceReport<br/>artifact convergence matrix / linkage + identity reconciliation + external shadow coverage + orientation gates"]
  TMF --> KAC
  P --> Q["核心覆盖图 / debug boxes<br/>full 额外 OCR 图 / bubble 图 / contact sheet"]
  M --> R["probe_report.json<br/>从明细实时汇总"]
  X --> R
  Y --> R
  V --> R
  GV --> R
  PTB --> R
  TB --> R
  CE --> R
  TBF --> R
  LTB --> R
  EAR --> R
  ETS --> R
  ESC --> R
  ETO --> R
  ISR --> R
  RTA --> R
  TMF --> R
  ODA --> R
  ROA --> R
  SAC --> R
  KAD --> R
  KSG --> R
  KNS --> R
  NTB --> R
  BMS --> R
  SMS --> R
  KRL --> R
  KPR --> R
  KWR --> R
  KER --> R
  KNR --> R
  KBI --> R
  KDF --> R
  KAS --> R
  KRS --> R
  KNT --> R
  KNSO --> R
  KNTR --> R
  KNTCL --> R
  KNBM --> R
  KNSMR --> R
  KNABL --> R
  KNPG --> R
  KIR --> R
  KAC --> R
  Z --> R
  M --> S["clean_text_diagnostic.json<br/>跳过 OCR 测模型"]
  S --> TMF
  M --> T["1_ocr_probe_text.txt<br/>逐块文本快照"]
  CE --> T
  TBF --> T
  LTB --> T
  EAR --> T
  ETS --> T
  ESC --> T
  ETO --> T
  ISR --> T
  RTA --> T
  TMF --> T
  ODA --> T
  ROA --> T
  SAC --> T
  KAD --> T
  KSG --> T
  KNS --> T
  NTB --> T
  BMS --> T
  SMS --> T
  KRL --> T
  KPR --> T
  KWR --> T
  KER --> T
  KNR --> T
  KBI --> T
  KDF --> T
  KAS --> T
  KRS --> T
  KNT --> T
  KNSO --> T
  KNTR --> T
  KNTCL --> T
  KNBM --> T
  KNSMR --> T
  KNABL --> T
  KNPG --> T
  KIR --> T
  KAC --> T
```

## 3. Agent 迭代流程图
这张图描述以后每轮任务如何从人工目标进入 Agent A、Agent B、GitHub Actions 和 Agent C。默认重验证在云端，本机只做轻量检查；`main` 不参与日常开发合并。

```mermaid
flowchart TD
  %% 人工输入：目标和约束
  H["人工提出目标<br/>功能、边界、禁止项、验收标准"] --> A1["Agent A<br/>读入口文档、历史、flow、test 和相关源码"]

  %% Agent A 输出版本化提示词
  A1 --> A2["Agent A 分析<br/>目标、非目标、风险、测试、验收"]
  A2 --> P["md/prompt/vX（阶段）/vX.Y（任务）.md<br/>写给 Agent B 的实现提示词"]

  %% Agent B 实现、轻量检查和推送
  P --> B0["从 smalldata_test 开分支<br/>codeb/vX.Y-短标题"]
  B0 --> B1["Agent B<br/>按提示词小步实现"]
  B1 --> B2["本地轻量检查<br/>git diff --check / JSON / YAML smoke"]
  B2 --> B3["push codeb/...<br/>不合并 main"]
  B3 --> B4["创建 PR<br/>base=smalldata_test / head=codeb/..."]

  %% 云端验证和结果包
  B4 --> G1["GitHub Actions<br/>变更范围检测 / 静态检查 / 必要时 Xcode build / 手动 ci-fast 探针"]
  G0["workflow_dispatch<br/>可选 full 或 skip"] --> G1
  G1 --> G2["未加密 CI 结果包<br/>xcresult / junit.xml / xcodebuild.log / manifest / failure summary / Koharu gate 摘要"]
  G1 --> G3["加密打包 workflow<br/>软件包交付，Agent C 不以此验收"]

  %% Agent C 验收和文档同步
  G2 --> C1["Agent C<br/>核对 HEAD commit、diff、Actions 结论、日志和 artifact"]
  C1 --> CFail{"是否通过"}
  CFail -- "失败" --> R["退回清单<br/>失败阶段、日志路径、manifest、交给 B 修复"]
  R --> B1
  CFail -- "通过" --> C2["更新核心文档<br/>flow.md / flowchart.md / update_log.md"]
  C2 --> C3["PR merge 到 smalldata_test<br/>禁止合并到 main"]
  C3 --> C4["删除远端 codeb/...<br/>避免候选分支堆积"]

  %% 回到人工
  C4 --> H2["人工复核<br/>确认后进入下一轮"]
  H2 --> H
```
