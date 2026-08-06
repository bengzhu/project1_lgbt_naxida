# 项目核心流程文档
本文只记录 AITRANS 当前真实架构和运行流程，不写历史流水账。历史看 `update_log.md`。

## 0. 一句话总览
v3.116 的 Developer Console 漫画探针诊断焦点由 `MangaProbeSection` 的 View 私有 generation 统一仲裁：筛选、重跑终态和逐块展开／收起只保留最新 VoiceOver handoff；新 probe loading 使旧请求失效，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。候选 full `31071423891`、PR #180 fast `31071714254`、merge fast `31071752236` 均通过。
v3.115 普通图片 OCR 的焦点 handoff 使用 View 私有 generation + revision guard，快速筛选／定位／复查时旧异步请求不会覆盖最新动作；不进入 Store、OCR、翻译或 renderer/export。候选 full `31070650744`、手动 full `31070655111`、PR #179 fast `31070940503`、merge fast `31070976672` 均通过。
v3.114 的漫画探针逐块诊断在新 loading 时用 View 私有 reset token 收起旧详情并抑制旧焦点回抢，结果行 VoiceOver 明确展开／收起状态；不进入 Store 或探针链路。候选 full `31069913494`、手动 full `31069918901`、PR #178 fast `31070264175`、merge fast `31070323190` 均通过。
v3.113 的 Developer Console 漫画探针逐块诊断在展开后把 VoiceOver 焦点交给稳定的详细诊断容器，收起后回到原结果行；详情复用既有 report-only 风险、下一步和执行边界，不进入 Store 或探针链路。候选 full `31068769954`、手动 full `31068778764`、PR #177 fast `31069311041`、merge fast `31069349841` 均通过。
v3.112 的普通图片 OCR 在新 `imageTranslationRevision` 进入 `.translated` 或 `.failed` 后恢复 VoiceOver 焦点：有 blocks 时交给当前筛选的首个结果行，没有 blocks 时交给动态图片状态行；revision guard 阻止旧任务在后续图片开始后抢焦点。该 View-only 改动不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。候选 full `31067968394`、PR #176 fast `31068324104`、merge fast `31068365757` 均通过。
v3.111 的 Developer Console 漫画探针重跑在报告写入后恢复 VoiceOver 焦点：有 blocks 时交给当前筛选的首个诊断 block，没有 blocks 时交给“未生成逐块诊断”状态；loading 仍清除旧筛选焦点。该 View-only handoff 不新增 Store、持久化、OCR、翻译、renderer/export 或探针报告状态，不改变 Koharu active gate、metrics 或 output。新增终态焦点合同；候选 full `31067283530`、PR #175 fast `31067583454`、merge fast `31067629934` 均通过。
v3.110 的普通图片 OCR 筛选焦点使用 View 私有意图仲裁：用户筛选变化聚焦首个可见结果，程序化复查／恢复／预览选择变化保留显式行、预览或完成态焦点；revision 重置清除待处理意图并保留空态回退。新增合同与历史合同兼容更新不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。候选 full `31066203170`、PR #174 fast `31066589776`、merge fast `31066628727` 均通过。

v3.108 的 Developer Console 漫画诊断筛选在切换到有结果的类别后，将 VoiceOver 焦点交给第一个可见 block；筛选只读既有报告，空筛选仍交给可操作空态，焦点 identity 只存在于 View。候选 full `31063355633`、PR #172 fast `31063761078`、merge fast `31063805810` 均通过，探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`。

v3.107 的图片 OCR 与漫画诊断筛选器在无结果时把 VoiceOver 焦点交给可操作空态：读出当前筛选、`0 / 总数` 与恢复筛选路径；焦点与空态只在 View 内处理，不进入 Store、持久化、OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31020576411`、PR fast `31062338507`、merge fast `31062372361` 均通过。

v3.106 的普通图片 OCR 与漫画探针筛选器共用动态 VoiceOver 筛选上下文：当前类别、显示数／总数和图片复查已完成／剩余数只在 View 计算，不进入 Store，也不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31017118790`、PR fast `31017809552`、merge fast `31017909329` 均通过。

v3.105 的 Developer Console 漫画探针诊断总览只读消费既有收敛报告的闭环快照，汇总开放／已闭环／要求停止工单、block path/work-item ledger 规模、状态 breakdown 和真实外部工件边界；快照同时用于状态 tone、可复制 summary 与 VoiceOver，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。

v3.104 的 Developer Console 逐块漫画探针行只读消费既有 `MangaKoharuArtifactConvergenceReport` 的 block path、开放工单与执行边界，统一显示首阻断、结构瓶颈、真实工件等待、工单状态和 CI-fast/full/外部工件边界；同一上下文进入 action summary、结果行和 VoiceOver，未闭环工单或 report-only 边界保持 warning/仅报告，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。

v3.103 的 Developer Console 漫画探针诊断总览只读消费 native promotion、artifact contract dry-run、artifact identity reconciliation 与 convergence 报告，显示晋级 verdict、dry-run/active export 边界、真实工件与 CI manifest 身份对账和未闭环工单；该摘要同时用于状态行、可复制文本和 VoiceOver，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。

v3.102 的 Developer Console 逐块漫画探针行继续只读消费 pipeline resolver、work-order、外部工件请求包和 native replay 的执行数据，显示目标执行项、首阻断、CI-fast/full/外部工件门与禁止本地调参边界；执行边界、建议、依据和真实工件门共用视觉/VoiceOver 摘要，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。

v3.101 的 Developer Console 逐块漫画探针行继续只读消费既有 bottleneck、model-floor、render-fit 与 artifact-DAG 证据，显示“为什么这样分流”及首阻断阶段；推荐下一步、诊断依据和真实工件门控共用视觉/VoiceOver 摘要，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。

v3.100 的 Developer Console 逐块漫画探针行只读消费既有 internal/floor/render/DAG report ledger，显示当前 block 的推荐下一步，并在存在 readiness 阻断时同步显示真实 Koharu 工件门控；视觉与 VoiceOver 共用该摘要，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。

v3.99 的 Developer Console 逐块漫画探针行只读消费当前 `MangaOverlayProbeReport` 的 OCR、翻译和布局风险集合；视觉标签与 VoiceOver value/hint 共用同一集合，帮助解释筛选结果，但不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。

当前项目主链路是：用户输入文本、音频或图片，`TranslationSessionStore` 统一调度本地状态、Apple OCR/Speech、Mock/Local 模型和持久化；漫画探针独立读取 `test/1.png`，生成 OCR、翻译、覆盖合成和诊断报告。

```text
用户操作 / test 固定素材
  -> SwiftUI 页面
  -> TranslationSessionStore
  -> OCR / Speech / Model Adapter
  -> 质量判定 / 诊断汇总
  -> UI 展示 / state.json / output 调试产物
```

v3.72 的 Developer Console readiness 摘要仍只读探针已有报告：v1 `summary-only` 工件显示 v2 mask payload／topology“未要求”，真实 v2 工件继续显示实际失败与阻塞；解释后的状态同时进入 VoiceOver hint 和可复制摘要。该 View-only/report-only 分支不创建 active 工件、不改变 readiness gate、普通图片 OCR、翻译、renderer/export、漫画探针或 Koharu 主路径。

v3.73 的图片复查列表对空 OCR 的已忽略 block 提供稳定显示与无障碍回退：视觉行显示“空 OCR 原文”，VoiceOver label 显示“空”，恢复 action 与焦点身份仍由既有 View/Store 边界管理，不新增业务状态或改变识别路径。

v3.74 统一普通图片 OCR 结果行与完整图片预览的旁贴／覆盖文字块空 OCR 回退：原文为空时显示“空 OCR 原文”，旁贴／覆盖仍以非空译文优先；该 View-only 变化不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、复查、探针或 Koharu 主路径。
v3.75 让 OCR 修正参考图与完整图片局部聚焦预览在原文为空时仍有稳定 VoiceOver value，统一使用“空”回退，非空原文保持原样；该 View-only 变化不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、复查、探针或 Koharu 主路径。
v3.76 将完整图片局部聚焦预览的“局部放大”视觉角标标为 accessibility hidden，避免与父容器稳定的定位 label/value 重复朗读；所有操作按钮、选择状态和 OCR 上下文不变。该 View-only 变化不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、复查、探针或 Koharu 主路径。
v3.77 在无效或过期 OCR 框的局部预览中隐藏不可用状态子视图，统一由父容器的 VoiceOver hint 说明“局部预览不可用；仍可关闭、编辑 OCR 原文或切换文字块”，避免 contain 层级重复朗读；操作和 Store ownership 不变。
v3.78 关闭完整图片局部聚焦预览时，使用既有 `reviewRowAccessibilityFocusID` 将 VoiceOver 焦点交回对应 OCR 结果行；该交接只在 View 私有状态中运行，不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、复查、探针或 Koharu 主路径。

v3.79 完整图片局部聚焦预览的上一个／下一个文字块仍只按当前筛选后的 View 顺序移动选择；选中目标后立即调用 `moveReviewAccessibilityFocus(to: reviewPreviewAccessibilityFocusID(targetBlockID))`，让 VoiceOver 焦点跟随新的预览容器。该交接不进入 Store 或产品处理链路，位置 value、首尾 disabled 边界和既有复查状态保持不变；同步的 v3.14 合同只放宽等价的局部 target ID 赋值写法。

v3.80 当 `reviewFilter` 隐藏当前选中的图片 OCR block 时，`clearHiddenReviewSelection()` 清除 View 私有选择并将焦点交给首个可见结果行；没有可见待复查 block 时，按既有完成态或筛选器焦点 identity 交接。该路径不写 Store、不重新 OCR／翻译，避免筛选切换后 VoiceOver 停留在已卸载的局部预览容器。

v3.81 结果行或完整图片覆盖块选中 OCR block 后，toggleSelection(of:) 与 selectBlockFromPreview(_:) 将 VoiceOver 焦点交给对应局部预览；取消定位时回到对应结果行。焦点 handoff 只在 View 私有 AccessibilityFocusState 中运行，不进入 Store、OCR、翻译或 renderer/export 链路。

v3.82 漫画覆盖探针在失败 fallback 含显式换行时，`wrappedLines` 按段落保留换行与空行，fit plan、碰撞检测和 CoreText 绘制共享同一行预算；该路径只改善探针诊断布局，不进入普通图片 OCR、翻译、Store、ground truth、Koharu active artifact 或质量基线。

v3.83 的 `makeKoharuRenderSpriteFitPlannerReport` 直接复用 `wrappedLines(text, fontSize:maxFontSize, maxWidth:rect.width)` 的换行结果，按真实行数计算预算，并将 block／render lock 的 `renderTextTruncated` 进入 failure fallback 风险。这样 block 5 的诊断会如实显示 `12 lines / fontBudgetOverflowRisk / failureFallbackLongTextRisk`，不再把实际截断报告为 `currentSpriteFits`。该 report-only 修复不进入普通图片 OCR、翻译、Store、ground truth、生产 renderer/export、Koharu active artifact 或质量基线。

v3.84 的 `makeKoharuRenderSpriteFitPlannerReport` 继续复用既有渲染锁证据：`renderMinFontSizeReached` 进入逐 block ledger、decision signal、`renderMinFontSizeReachedBlocks` 汇总和 `G-render-sprite-fit-min-font-evidence` report-only gate；block 5 的 ci-fast 报告因此明确记录最小字号压力与实际截断。该诊断只读并不提升或改变 OCR、翻译、Store、ground truth、生产 renderer/export、Koharu active artifact gate、metrics 或 output。

v3.85 的 `MangaKoharuRenderRegressionLockReport` 继续从既有 block/render lock 汇总 `renderMinFontSizeReached`，并把该证据贯穿逐 block decision trace、`renderMinFontSizeReachedBlocks`、report-only gate 与 Developer Console 摘要；只改善诊断可观测性，不进入 OCR、翻译、Store、ground truth、生产 renderer/export、Koharu active artifact 或质量基线。

v3.86 修正漫画探针 render-lock 输出 ledger 的构建时序：`probe_report.json` 与最终重写的 `1_ocr_probe_text.txt` 现在使用 planned-final-write 状态，避免报告在重写前把必需 OCR 文本误判为空；成功 ci-fast 报告因此同时给出 `coreOutputFilesNonEmpty=true` 与 `G-render-core-png-retained=passed`，真实 block 5 截断仍单独阻塞 `G-render-no-text-truncation`。该 report-only 路径不改变 OCR、翻译、Store、ground truth、生产 renderer/export、Koharu active artifact gate、metrics 或 output。

v3.87 让 render-lock 输出检查把 planned final write 的推荐动作与实际状态对齐：`plannedFinalReportWrite` 与 `plannedFinalOCRTextRewrite` 在 `nonEmpty=true` 时返回 `keepReportOnly`，缺失或未检查输出才返回 `inspectRenderOutputExport`；新增 v3.87 合同并接入 Koharu changed-file/full 路由。该 report-only 修复不改变 OCR、翻译、Store、ground truth、生产 renderer/export、Koharu active artifact gate、metrics 或 output。云端 ci-fast 仍保留 block 5 的实际截断与 `openRenderIssueDetected`，不能作为质量提升证据。

v3.88 将 `G-render-core-png-retained` 的成功动作与 `outputFileChecks` 对齐：完整且非空的 retained 输出只读报告，缺失/空输出才进入导出检查；新增 v3.88 合同和 CI 路由。该诊断不改变 OCR、翻译、renderer/export 或 Koharu active artifact gate，ci-fast 仍保留 block 5 截断风险。

v3.89 让 Developer Console 的 `outputFiles` 摘要直接汇总 required 输出的 `recommendedAction`（如 `keepReportOnly=5`），与核心输出 gate 共用既有 report-only 状态；新增 v3.89 合同和 CI 路由。该诊断不改变 OCR、翻译、renderer/export 或 Koharu active artifact gate，ci-fast 仍保留 block 5 截断风险和 `manifestMissing` readiness。

v3.90 漫画探针失败覆盖只在显示层压缩 OCR continuation 的显式换行，保留完整 OCR fallback 与 `翻译失败` 标记；安全布局、fit planner 和实际覆盖绘制消费同一显示变换，ci-fast 的 block 5 从截断风险变为 `renderTextTruncated=false`、`renderMinFontSizeReached=false`，render lock 为 `renderStableWithProxyBoundaries`。该 probe-render 诊断修复不改变 OCR、翻译、Store、普通图片 renderer/export、ground truth、Koharu active artifact gate 或质量基线；真实四件套仍缺失。
v3.91 Developer Console 新增只读漫画探针“诊断分流”上下文：消费既有 `MangaOverlayProbeReport` 的 OCR／翻译模型／覆盖布局／Koharu readiness 信号，展示 baseline／variant floor 与下一步，并让失败 block 显示 failureCategory 及 VoiceOver 分流。该 View-only 改动不新增 Store／持久化、不调用第二次探针、不改变 OCR、翻译 prompt／model、renderer/export、metrics 或 output；full `30886955217`、同 SHA ci-fast `30887582600`、PR fast `30888608909`、merge fast `30888676363` 对精确 SHA/receipt 均通过。ci-fast 仍保持 13 blocks／12 failures、render lock stable、model floor `promptVariantRegresses` 和 readiness `manifestMissing / stopUntilArtifactsProvided`，真实 Koharu 四件套、Speech corpus 与竖排图片 corpus 仍缺失。
v3.92 图片 OCR 复查在既有待复查并集之外提供低置信与方向待定的 View 本地筛选，且忽略文字块后沿当前筛选保持定位；Developer Console 的漫画逐块结果提供全部／失败／OCR／翻译／布局只读诊断筛选。两者均不新增 Store／持久化、不改变 OCR、翻译、renderer/export、探针报告或主流程。full `30889811326`、PR fast `30890241624`、merge fast `30890322575` 对 exact SHA/receipt 均通过；push 未运行漫画探针，真实 Koharu 四件套仍缺失。

v3.93 当 `imageTranslationRevision` 变化时，图片复查 View 将本地筛选恢复为“全部”，并清除旧 block 选择与 VoiceOver 焦点，覆盖新图、重试、重新识别和清空，避免旧风险筛选造成空结果误导。该改动只消费既有 Store revision 信号，不新增 Store／持久化或改变 OCR、翻译、预览、导出、漫画探针与质量基线；full `30890823578`、PR fast `30891431628`、merge fast `30891485989` 均通过，真实 Koharu 四件套仍缺失。

v3.94 漫画探针在每次运行前清空旧 report/blocks；缺少 bundle `test/1.png` 时重建 App 沙盒 `Output` 并把清理数量/成功状态写入失败报告，避免旧 blocks 或旧 PNG/JSON 污染当前诊断。清理失败会显式标记旧输出可能残留。该修复不改变 OCR、翻译、renderer/export、Koharu active gate 或质量基线；full `30893309273`、PR fast `30893920011`、merge fast `30893993759` 均通过，真实四件套仍缺失。

v3.95 当漫画探针报告没有逐块 OCR blocks 时，Developer Console 显示明确的无 blocks 状态并隐藏诊断筛选器；VoiceOver 复用现有探针消息并说明 `test/1.png`／Output 清理后的重试范围。存在 blocks 时保持既有只读诊断筛选和逐块上下文。该 View-only 修复不新增 Store／持久化、不重跑探针或改变 OCR、翻译、renderer/export、Koharu gate 与质量基线；full `30984932342`、PR fast `30985360673`、merge fast `30985413482` 均通过，真实 Koharu 四件套仍缺失。

v3.96 `MangaProbeDiagnosticTriageSummary` 在 active Koharu artifact gate 被阻断时优先显示 warning；即使 blocks 全部通过，也不会用 success 色暗示 shadow OCR 已就绪，只有非阻断且 report 通过才显示 success。该 View-only/report-only 修复不新增 Store／持久化、不调用探针或改变 OCR、翻译、renderer/export 与质量基线；full `30985776084`、PR fast `30986258687`、merge fast `30986307343` 均通过，真实四件套仍缺失。

v3.97 漫画探针布局筛选和 triage 摘要复用同一只读 render risk 集合，补上 fit planner 的字号预算、sprite 包含、相邻 block 重叠、失败覆盖风险及 render-lock 证据，避免顶层渲染错误为空时隐藏 report-only 压力。该改动不改变 OCR、翻译、renderer/export、Store 或 Koharu gate；ci-fast `30986469563` 观察到 10/7/6 风险，full `30987210261`、PR fast `30987676638`、merge fast `30987725142` 均通过，真实四件套仍缺失。

v3.98 漫画探针 OCR 与翻译诊断筛选、triage 摘要共享两个只读 risk set，统一消费 diagnostics、model-floor、translation failureCategory 与 OCR 疑似证据；该改动只修正报告分流一致性，不改变 OCR、翻译、renderer/export、Store 或 Koharu gate。候选 full `30988262491`、PR fast `30988802078`、merge fast `30988876405` 均通过，真实四件套仍缺失。

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
- 音频页展示 Apple Speech 本机识别能力、识别运行摘要、识别文本、译文和取消入口；checking、recognizing、translating 三种运行态均可取消。

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

当前正式版本：`3.116`。普通图片的 OCR blocks 在 OCR 完成后的逐块翻译期间仍可查看、定位和显示局部预览，但改变结果或复查进度的入口必须等待 `imageTranslationState == .translated`。`canModifyImageTranslation` 还要求不在导出重绘期，统一保护 OCR 修正、恢复 Vision OCR、恢复已忽略 block 与旁贴／覆盖切换；`canReviewImageTranslation` 统一保护开始／继续／重启复查及完成／撤销。Store 的 mark／reopen／reset 会二次拒收未完成状态；成功 OCR 修正先恢复 `.translated`，再沿用既有自动复查，避免已可见的中间 blocks 提前持久化会话进度。v3.43 的局部预览前后导航继续只更新 View 私有选择：可用按钮向 VoiceOver 说明定位上一个／下一个文字块，筛选首尾的 disabled 按钮明确说明已到第一个／最后一个文字块；结果行主定位提示按当前是否已选中切换为取消定位或在图片预览中定位。v3.44 在同一对前后按钮上追加当前位置 accessibility value：有筛选位置时读出“当前位置 1 / 3”一类上下文，无位置时读出“未显示筛选位置”，仍只消费既有 `positionText`。v3.45 让完整图片预览中的 OCR 覆盖块也复用结果行的定位提示，已定位时读出取消此文字块在图片中的定位，未定位时读出在图片预览中定位此文字块，保持图片入口和列表入口语义一致。v3.46 让图片预览加载与失败卡片提供稳定的 VoiceOver label/value，重试提示明确只重建屏幕预览、不重新 OCR 或翻译。v3.47 让照片／文件、取消、重试、重新识别、导出和清空按钮说明具体影响范围，PhotosPicker 会动态说明是首次选择还是替换当前图片；v3.48 让完整图片预览容器汇总识别块数量、待复查数量和当前定位位置，并隐藏重复朗读的原始背景图；这些 hint/value 只改善 View 可理解性，不改变 Store、OCR、翻译、renderer/export、探针或质量基线。v3.49 让图片输入语言与目标语言菜单的 VoiceOver hint 按运行中、Pro 门槛、无图片、已完成和失败／取消重试状态分流：运行中明确需完成或取消，Pro 锁定说明不会污染文本页语言，已完成输入语言说明会重新识别和翻译、目标语言说明会重新翻译当前图片，失败／取消说明下一次重试使用新语言；选回当前内容语言会撤销待重试差异。v3.50 让照片与文件导入按钮在读取、OCR 或翻译进行中明确说明选择新图片会取消当前任务并开始新的本机 OCR 与翻译，同时保持有意设计的替换入口与 Store run-id 隔离。v3.51 让图片状态行成为单一的 VoiceOver 状态元素，动态读出 `statusTitle` 与 `statusDetail`，并按载入、Vision OCR、逐块翻译、导出重绘、分享准备、失败和完成分流下一步操作提示；仍只消费既有 Store 状态，不新增 Store／持久化状态，也不改变 OCR、翻译、renderer/export、探针或质量基线。v3.52 让图片结果行主 Button 的 VoiceOver value 在定位状态之外读出 OCR 置信度、低置信／方向待定、人工修正、待复查／本次已复查和等待翻译；该改动只改善 View 语义，不新增 Store／持久化状态，也不改变 OCR、翻译、renderer/export、探针或质量基线。v3.53 让已忽略 OCR 文字块恢复行成为稳定的 VoiceOver 上下文，读出不在图片预览／导出／转录、是否保留现有译文和恢复是否可用，同时保留恢复按钮的禁用原因与焦点交接；只改善 View 语义，不新增 Store／持久化或改变 OCR、翻译、renderer/export、探针和质量基线。v3.54 修复图片状态行 VoiceOver value 的实际实现回归：改用动态 `statusTitle`／`statusDetail` 插值，避免朗读字面量占位符；v3.51 合同同步锁定真实插值。该版本只改善 View 语义，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径、ground truth、metrics 或 output。v3.55 让开发控制台的 Koharu readiness 状态行提供稳定 label/value/hint：缺少真实四件套时直接提示 `test/koharu_artifacts/`、manifest/TextBoxes/BubbleMask/SegmentMask 文件名和 shadow-only 边界；只读消费既有 readiness report，不调用第二次探针、不写 Store，也不改变普通图片 OCR、翻译、renderer/export 或 active artifact gate。v3.37 的首尾空白规范化、v3.24 的弃改保护、v3.25 确认无误分流、v3.38 键盘清焦点、v3.39 滚动收起、v3.40 保存期输入锁定和 v3.30–v3.35 revision-scoped `onDismiss` 焦点交接均保持不变。本版不创建 Store／持久化状态，不改 Vision OCR、模型、renderer/export、漫画探针、Koharu 主路径或质量基线。v3.36 的 `MangaKoharuArtifactReadinessSummary` 仍只读既有 report，ready 仍只代表下次探针可尝试 shadow OCR，不是 App-side coverage、真机 UI 或质量证据。v3.26 CI receipt 传播规则不变；真实竖排图片 corpus、Speech corpus 与 Koharu 真实四件套运行态仍待提供。 v3.56 让漫画覆盖翻译探针状态行按阶段提供 VoiceOver 状态 value/hint，运行按钮明确 test/1.png、Output 和只影响探针诊断的范围，不新增 Store／持久化状态。 v3.57 让漫画探针逐块结果按 block index、PASS/FAIL、OCR 原文、置信度、译文和失败详情提供 VoiceOver 上下文，展开提示保持探针诊断边界，不新增 Store／持久化状态。 v3.58 让图片复查结果行提供稳定的 VoiceOver label/value：label 明确图片文字块与 OCR 原文，value 区分等待翻译与真实译文并处理空 OCR 回退；只改善 View 语义，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 或质量基线。 v3.59 让完整图片预览的覆盖文字块与图片复查结果行共用稳定的 VoiceOver label“图片文字块 + OCR 原文”，空 OCR 回退为“空”，并保留既有等待翻译／译文 value、定位 hint 和选中状态；该改动只改善 View 语义，不新增 Store／持久化状态，不改变选择、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。 v3.60 让完整图片预览的覆盖文字块与图片复查结果行对齐 VoiceOver value：读出 OCR 置信度（clamp 到 0–100%）、人工修正、低置信／方向待定、待复查／本次已复查及等待翻译／译文；相邻与替换模式共用这套上下文，只改善 View 语义，不新增 Store／持久化状态，不改变选择、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。

v3.61 的图片复查结果行和完整图片预览继续消费 `ImageTranslationBlock` 已有的 `sourceDirection`／`directionConfidence`：已判定的横排／竖排会显示并进入 VoiceOver value，方向置信度先做有限值检查和 0–100% clamp；结果行的 OCR 置信度显示也做同样的 0–100% 边界保护。该改动只改善复查上下文和异常数据下的显示稳定性，不新增 Store／持久化状态，不改变 Vision OCR、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.48 的完整图片预览继续遍历完整 `store.imageTranslationBlocks`，但在 ready 容器上增加 View 私有 VoiceOver label/value/hint：汇总文字块总数、风险块扣除当前图片会话 `reviewedBlockIDs` 后的待复查数和当前定位位置；原始背景 `Image` 设为 `.accessibilityHidden(true)`，避免重复朗读。该上下文只改善可操作性，不创建 Store／持久化状态，也不改变 OCR、翻译、选择、renderer/export 或探针路径。

v3.62 的图片识别结果摘要复用 `ImageOCRResultSummary.horizontalBlockCount` 与 `verticalBlockCount`，在方向风险之外显示横排／竖排 block 数，帮助用户快速判断当前图片的方向分布。该改动只改善摘要的 View 语义，不新增 Store／持久化状态，不重新运行 Vision OCR／模型翻译，也不改变 renderer/export、漫画探针、Koharu 或质量基线。

v3.63 将图片“识别结果”摘要设为一个稳定的无障碍 header：value 继续消费 `store.imageTranslationSummary`，hint 仅根据现有 blocks、翻译状态和待复查集合说明选择图片、查看定位或更新复查进度的下一步。该 View 语义不新增 Store／持久化状态，不重新运行 Vision OCR／模型翻译，也不改变 renderer/export、漫画探针、Koharu 或质量基线。

v3.64 将图片 OCR 置信度边界集中为安全归一化：布局引擎先清理 observation confidence，`ImageOCRResultSummary` 再用同一语义计算平均值与低置信集合，结果行／覆盖层也复用该边界显示百分比。非有限值按 0 处理并保留复查风险，避免 NaN 传播或 `Int` 转换崩溃；不改变 OCR 候选、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.65 让图片 OCR 修正 sheet 的低置信度提示复用 ImageOCRResultSummary.normalizedConfidence，在百分比格式化前处理 NaN/∞ 与越界值；仍只改善 View 显示，不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.66 在 Vision OCR 输出进入布局前统一做有限、正面积、单位坐标整矩形归一化；布局引擎再次过滤异常 observation，保证覆盖、局部定位和阅读排序只消费有效几何。该安全边界不改变 OCR 候选、翻译、renderer/export、漫画探针、Koharu 或质量基线；无效 geometry 会被安全丢弃而不是生成越界 block。

v3.67 让 `NormalizedImageRect.normalizedToUnit()` 成为旧会话／外部解码 block 的消费边界：完整图片覆盖和局部定位对无效框不生成 View，导出 renderer 对无效框返回空 rect；有效框保持既有裁剪和布局语义，不写回持久化，也不改变 OCR、翻译、漫画探针、Koharu 或质量基线。

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
- OCR 修正 sheet 的首尾空白归一化仅存在于 View 私有 `normalizedCorrectedOriginal`：它把 clean dismissal、discard protection、确认无误／重译文案和 Store 输入对齐；同一 sheet 的 `correctedOriginalFocused` 也仅在 View 内控制多行输入与键盘“完成”，取消、忽略确认、保存前会清焦点。两者都不把 UI dirty／键盘 state 写入 Store，也不把无语义变化送进模型。
- 漫画探针报告生成后，开发控制台的 Koharu readiness 摘要只读取 `report.externalArtifactReadinessReport`：ready / missing / invalid 状态和可复制缺件／nextAction 用于协调真实四件套，不直接访问 artifact 目录、不触发新 probe；它始终标为 shadow-only，不改变主 OCR、翻译、覆盖图、`blockPassed`、`currentBlockSource`、metrics 或 `output/`。
- 实时录音保留触控按住手势，同时提供默认 accessibility action；VoiceOver / Voice Control 激活会在 `beginProLiveSpeechCapture` 与 `endProLiveSpeechCapture` 之间切换。
- 设置页持有显式 `NavigationPath`；`isDeveloperModeEnabled` 关闭时清空 path，开发控制台不能在权限关闭后继续停留或操作。
- `AppPreviewScenario` 通过临时 URL 和 `performsStartupWork=false` 隔离预览，不恢复或持久化生产数据。DEBUG CI 可用 `AITRANS_UI_EVIDENCE_SCENARIO` 复现 14 张运行态证据，其中两个 wide iPad 场景分别覆盖文本空态和图片成功/风险复查态；`audioRecognizing` 设置 capturing 状态覆盖 Reduce Motion，`audioTranslating` 设置非空 transcript + translating 状态覆盖取消翻译入口，生产启动不读取这些场景。
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
- `speechQualityProbeReport`：记录 corpus/manifest/audio 身份、Apple Speech 最终文本、WER/CER、延迟、分段、置信度和失败分类；参考文本只在识别完成后进入纯评测器。

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
- 用户在图片页选择的输入语言和目标语言。

输出：

- `ImageTranslationBlock`
- 识别结果摘要由 `ImageOCRResultSummary` 从当前 blocks 计算：显示已翻译/总块数、夹取到 `0...1` 后的平均 Vision 置信度、低于 `50%` 的块数，以及竖排与 unknown 方向计数。空结果不虚构平均值。成功图片在 Store-owned 原图仍存在时提供“重新识别”，复用当前内容的输入/目标语言凭据并走既有 task ID、render/share 失效和源文件保留链路；View 不读文件或直接启动 OCR。
- 检查列表可在“全部 / 待复查”间切换。待复查是低于 `50%` 或方向为 nil / unknown 的并集，重叠块只计一次且保留原始顺序；行内以图标和文字展示具体原因。筛选仅是 View 私有展示状态，图片预览、覆盖、翻译、导出和分享继续使用当前活动的 `imageTranslationBlocks`；只有 v3.29 经确认的误识别忽略才会通过 Store 改变这个活动集合，绝不由筛选隐式删块。
- 检查列表行可切换 View 私有 selected block ID；选中行显示取景框标记，图片预览仅对相同 ID 的完整产品 block 增加边框。图片 revision 变化会清除选择；切到“待复查”后若选中块被隐藏也会清除。该联动不写 Store、不筛预览 blocks、不改变导出或持久化。
- OCR 完成后的逐块翻译期间，截图、blocks、选择、定位和局部预览保持可读，方便用户跟进中间结果；但 `canModifyImageTranslation` 只在 `.translated && !isRenderingExport` 时开放修正、恢复 Vision OCR、恢复已忽略 block 与覆盖方式，`canReviewImageTranslation` 只在 `.translated` 时开放开始／继续／重启、完成／撤销复查。v3.42 在存在活动 blocks 且任一动作仍锁定时显示只读警示状态行；覆盖方式、复查、局部预览、结果行和忽略恢复的禁用 VoiceOver hint 统一复用 `imageModificationUnavailableDetail`／`imageReviewUnavailableDetail`。v3.43 让局部预览前后按钮的 VoiceOver hint 随序列边界变化：可移动时说明定位上一个／下一个文字块，首尾 disabled 时说明当前已是筛选结果中的第一个／最后一个文字块；结果行主定位 hint 也随 `isSelected` 切换为取消此文字块定位或在图片预览中定位。v3.44 让这两个导航按钮的 accessibility value 同步读出既有 `positionText`（例如当前位置 1 / 3），无位置时明确说明未显示筛选位置。v3.45 让完整图片预览中的 OCR 覆盖按钮复用结果行的定位 hint，图片入口与列表入口听到同一套已定位／未定位操作语义。v3.46 让加载/失败卡片提供可访问状态 label/value，重试 hint 明确只生成屏幕预览，不会重新 OCR 或翻译。v3.47 让图片命令栏的照片／文件、取消、重试、重新识别、导出和清空按钮明确声明作用域，照片选择器还会区分首次选择与替换图片。提示按 loading／recognizing／translating／failed／export rendering 分流，逐块翻译明确仍可查看／定位但不能提交；这些 View 私有文案不写入 Store。Store 的 `markImageTranslationBlockReviewed`、`reopenImageTranslationBlockReview` 与 `resetImageTranslationReviewProgress` 也会拒收非 `.translated`，形成 UI 与业务两层边界。
- 在完整 `.translated` 时，风险结果行把定位与复查拆成两个同级 Button：主区域只切换定位，独立 44pt 图标动作直接完成并沿现有队列定位下一块，或撤销后把该块放回队列。入口在尚未完成任何块时显示“开始复查”，有进度时显示“继续复查”；风险原因与已复查状态纵向排列，避免窄 inspector 和 Dynamic Type 横向挤压。当前图片的已复查 block ID 由 Store 的内存状态统一持有，面板重建后不丢失；新图、取消和清空会重置，绝不写入持久化。View 仍只决定筛选、队列位置和展示焦点。
- 连续复查使用 View 私有 `AccessibilityFocusState<String?>`，并为结果行、局部放大和完成态分配不同 focus ID。开始/重启队列后焦点进入当前局部放大；行级快速动作保持在下一结果行，局部放大动作保持在下一块放大窗，撤销回到同来源当前块，最后一块完成则聚焦“本次复查完成”。焦点发布先 yield 一次并核对图片 revision，旧图片任务不得抢回焦点；只有焦点本身不进入 Store 或持久化。
- 每个 OCR 结果行提供独立 44pt 人工修正按钮，但只有完整 `.translated` 且未导出重绘才可打开。编辑 sheet 对空白输入前置禁用，保存时阻止重复提交和交互式关闭；View 只把 block ID 与修正文本交给 Store。Store 只调用一次目标块 sampled 翻译，并在回写前同时核对 correction ID、图片 task ID、block ID 和旧原文快照。失败时不改 block、transcript 或当前导出；成功时原子替换原文与译文、清除保存中标记、恢复 `.translated` 后再标记当前图片的人工修正状态和自动复查、同步对应 transcript，随后撤销旧 export/share 并复用 render ID 生命周期按当前覆盖模式重绘。新图片、清空和取消都会使旧 correction 失效；人工修正不写回 Vision OCR，也不进入漫画探针或 ground truth 路径。
- OCR 修正 sheet 会把当前图片的既有 `imageTranslationData` 交给 `ImagePreviewService` 生成最大边 2048px 的临时本地预览，再复用局部放大的 16:9 裁切和 bbox 几何显示当前文字块周边；黄色框、可读标签与 VoiceOver value 明确识别区域。预览 loading / unavailable 只影响这张对照图，不能阻止编辑、确认无误或现有的单块重译。低于 50% 置信度或方向 nil / unknown 时，sheet 复用 `ImageOCRResultSummary` 显示相应复查原因和“仅重译当前块”边界；该展示不新增 Store 状态、不调用 Vision OCR、不读取 Koharu artifact、不改 renderer / export / transcript / ground truth。
- 首次成功人工修正时，Store 只在当前图片内按 block ID 保存一份私有 Vision OCR 基线（原文、初始译文与几何/方向证据）；后续修正不覆盖该基线。已人工修正的结果行出现独立 44pt “恢复 Vision OCR”动作，恢复不调用模型，要求当前图片处于完成态且没有 correction in flight。成功后恢复完整基线 block、移除人工修正标记与当前图片会话的已复查标记、同步当前图片 transcript、撤销旧 export/share 并重绘；新图片和清空会丢弃基线。恢复风险块只会在确认 dialog 已关闭且 revision 仍匹配后把 VoiceOver 焦点回到结果行，避免把旧复查结论带回原 OCR。
- 点击“恢复 Vision OCR”先仅把当前 block 写入 `ImageTranslationPanel` 的 View 私有待确认状态；dialog 清楚说明会移除本次人工修正，取消不调用 Store、不改变任何图片状态。确认先核验待确认 block 仍匹配，再调用既有恢复方法；成功后只暂存结果行 focus ID 与当前 revision，保留 confirmation target 直到 `confirmationDialog` 关闭时 binding 回写。binding 清理 target 后只有 revision 一致才复用既有 yield 后焦点发布器；取消没有 pending 目标，图片 revision 变化会一并清空选择、编辑、待确认、pending 和焦点，旧 dialog 不得指向新图片。
- v3.29 的 OCR 修正 sheet 还提供“忽略此文字块”破坏性确认，明确说明未保存修正不会保存、该块会退出本次图片预览／导出／当前转录，且可在检查区恢复。忽略与检查区恢复同样只在完整 `.translated` 且未导出重绘时开放。确认后 View 只触发 Store：Store 以 block ID 保存当前完整 block、初始 OCR 顺序、人工修正标记和私有 Vision 基线，再从活动 blocks、已修正／已复查集合及基线映射中移除；同步当前图片 transcript、撤销旧 export/share 并重绘。恢复操作按初始排序插回 block，恢复原人工修正基线但不恢复“已复查”结论，风险块重新进入队列；所有活动块被忽略时移除当前图片 transcript 行并由既有 renderer 导出原图。忽略快照只在当前图片会话内保存，新图和清空会丢弃，绝不进入 `state.json`、Vision OCR、模型翻译、漫画探针或 Koharu 路径。
- v3.30 把 OCR 修正 sheet 成功后的 VoiceOver 焦点交接固定在 sheet 完整关闭之后：成功忽略保留原有“下一活动／待复查行，否则已忽略行”的目标；待复查队列中的成功修正保留原有“下一行／完成态”目标。View 私有的 pending focus 同时记录当前 `imageTranslationRevision`，`onDismiss` 只有在 revision 一致时才清空 pending 并复用既有 `moveReviewAccessibilityFocus`；图片 revision 变化会先清空 sheet、pending 与已发布焦点。该机制不新增 Store、持久化、OCR、翻译、renderer/export 或探针状态。
- v3.31 继续补齐成功人工修正的非队列返回：`completeReviewAfterCorrection` 先确认 block 仍在当前活动集合；仅当筛选为“待复查”、当前 block 属于风险集合且 Store 已标为已复查时才沿用下一行／完成态。非风险 block 和“全部”筛选下的风险 block 则保持当前选择，并通过同一个 revision-checked、sheet `onDismiss` handoff 回到已更新结果行。该 fallback 不改变 Store、复查集合、OCR、模型调用、转录、导出或探针路径。
- v3.33 补齐修正 sheet 的非成功退出：`beginCorrection` 在呈现 sheet 前先登记该 block 的结果行作为同一 View 私有 pending handoff 的回退。无修改取消、明确放弃未保存修正和允许的交互式关闭不修改 Store，因此关闭后的 revision 校验会把焦点带回发起行；成功确认／单块重译或忽略在关闭前覆盖此回退，继续使用既有下一块、完成态或忽略行。该规则不新增持久化、Vision OCR、模型、renderer/export、漫画探针或 Koharu 状态。
- 选中 block 时，预览从当前最大边 2048px 的缩略图裁切 16:9 局部放大窗；裁切范围至少覆盖 bbox 宽高的 1.8 倍，并以归一化宽 16%、高 10% 为下限，再夹取在顶左原点图片范围内。放大窗以至少 24pt 的警示色框再次标出原 bbox，提供命名明确的 44pt 关闭命令；v3.34 在关闭按钮下再提供可访问的 44pt “修正识别文字”铅笔入口。v3.41 让这个入口与结果行共享 `canModifyImageTranslation`：只有完整 translated、未导出重绘且 block 仍有效时才会登记 v3.33 的同一局部预览关闭回退并呈现既有 sheet；结果行 `beginCorrection` 保留结果行回退。快捷修正不重新解码 Store 原图、不调用 OCR / 翻译、不进入 renderer、导出或持久化；取消／放弃／无修改关闭仍经 `onDismiss` 返回对应发起位置，成功／忽略继续覆盖为既有队列或结果目标。
- 外层图片页使用单一 `ScrollViewReader`，`ImageTranslationPanel` 根部提供唯一 workspace anchor。结果行从未选中切到新 block 后才滚动到该 anchor；点击同一行取消选择不滚动。系统 Reduce Motion 开启时直接定位，否则只使用 `AppTheme.Motion.standard`。局部放大窗显示当前 block 在“全部/待复查”可见序列中的位置，并提供命名明确的 44pt 上一个/下一个按钮；导航按该序列移动，首尾按钮同时禁用和降调，不越界、不绕回、不改筛选或完整 blocks。
- 旁贴或覆盖预览与同模式 PNG 导出；Vision OCR bbox、SwiftUI 预览和导出 renderer 统一使用图片顶左原点坐标。活动文字块为空但当前图片仍存在（即 v3.29 全部块被用户忽略）时，renderer 仍必须安全绘制并发布原图，不得保留旧导出或产生空白状态。后台 render 只写 render ID 独占 staging PNG，已完成图片切换模式会使旧导出失效并按 render ID / 图片 task ID / mode 验明身份后发布 `aitrans-export-<render UUID>-<base>-translated.png` 稳定文件，旧 detached render 不得覆盖新任务。覆盖模式重渲染公开 `idle / rendering / failed` 状态；rendering 时 Store 与 Picker 双重拒绝重复切换，当前失败显示 danger 并提供同模式重试，无 staging URL 也必须进入可重试失败。新任务、清空或其他内容失效会取消 render Task、更新 render ID 并复位状态。启动时会扫描 `Application Support/ImageTranslations` 直属文件，分账接管带 Store marker 的稳定导出、`<task UUID>-<name>` 输入副本和 `.<base>-translated-<render UUID>.staging.png`，清理上次异常退出残留；普通后缀文件、wrong-kind、目录外、嵌套、escape、symlink 和 dangling symlink 一律拒绝。新任务、清空或模式重渲染会撤销公开 export URL 并删除当前 Store-owned 稳定导出；正常 input/staging 清理同样必须携带可信 workspace 与对应文件类型，删除失败也登记 orphan ownership。所有删除失败项都在后续生命周期继续重试。分享前由 Store 在 `ImageTranslationShares/<share UUID>/` 创建人类可读 `<base>-translated.png` 硬链接或副本，并公开 request-scoped `idle / preparing / failed` 状态；准备中禁用重复导出，当前请求失败覆盖翻译成功色调。Store request ID 与 View presentation ID 共同拒绝晚到结果和旧 Task 的 `nil` 回写，dismiss / export 失效 / View 离开与启动恢复统一清理分享目录并复位反馈，删除失败保留 ownership。
- 任务启动时固定输入/目标语言，并分别记录 actual-content 与 pending-Retry 凭据；只要 content 凭据尚未被 clear，从 `.loading` 到失败/取消即使图片 data/blocks 为空，结果标题和菜单回退也继续使用任务实际语言，不受跨页全局语言漂移影响。失败或取消且 Store-owned source 仍可重试时，菜单只在选择与 actual-content 不同时写入独立 pending 字段并显示“重试语言已更新”；选回 actual-content 会把对应 pending 归一化为 `nil`，两项均无差异时提示消失，不会改写或误标屏幕上保留的 OCR/译文。Retry 优先消费 pending，再回退 actual-content，任务开始即清空 pending。clear 同时清空两组凭据，cancel 保留 actual-content。已完成图片选择不同输入语言会从沙盒原图重新 OCR + 翻译，选择不同目标语言会重新翻译；运行中菜单禁用且 Store 拒绝改写本次凭据。
- 图片输入语言选择先检查 `isProUnlocked`；免费模式的非当前菜单项显示 `lock.fill`，拒绝时只更新 Store-owned 反馈并由菜单显示 Alert，不得修改跨页 `sourceLanguage`、content 或 pending。VoiceOver hint 同步说明 Pro 门槛。目标语言继续由 `selectTargetLanguage` / `canUseLanguage` 判定，英语、中文等免费目标不增加额外图片 Pro 门槛。
- 图片来源入口先调用 Store-owned `requestImageTranslationAccess()`。只有 Pro 模式才实例化 `PhotosPicker` 并提供 file importer 动作；免费模式显示两个 `lock.fill` 命令并用 Alert 展示 Store 反馈，不进入系统照片或文件选择流程。`translateImage(from:)` 与 `translateImageTransfer` 的底层 Pro guard 继续作为纵深防线。
- 图片清空命令先显示附着于 `ImageCommandBar` 的破坏性确认，明确列出当前图片、识别结果、译文和导出文件；取消不调用 Store，只有确认按钮调用一次既有 `clearImageTranslation()`，其 task/source/export/share 清理边界不变。
- 图片预览不再在 SwiftUI task 中通过 `UIImage(data:)` 解压 Store 原始 Data。`ImagePreviewService` 使用 `Task.detached` + ImageIO 生成最大边 2048px 的已缓存 `CGImage`，应用 EXIF transform 且不缓存完整 source；外层 task 取消会取消后台任务。View 同时记录 preview revision，只有与当前 `imageTranslationRevision` 一致时才显示；数据已载入但预览未就绪时显示准备状态，生成失败时可只递增本地 attempt 重试预览，不重跑 OCR / 翻译。Store 原始 Data、OCR、覆盖坐标与导出输入保持不变。
- 普通图片 OCR 对每个 observation 记录 `horizontal / vertical / unknown` 方向证据。只有日语/中文 prior、bbox 高宽比至少 `1.6`、高度至少 `0.035`，并且包含至少两个 CJK 字符或具有同列邻居且没有近同行邻居时，才进入竖排路径；孤立单字高框、同行 CJK 碎片及非 CJK 高框继续走横排/unknown fallback。横排按上到下、行内左到右聚类；竖排按列从右到左、列内上到下聚类，两种方向不会互相合并。方向、置信度与 reason 随 `ImageTranslationBlock` 保留，不改变漫画探针链路。

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
- 识别中和翻译中状态分开展示；用户可取消正在检查、识别或翻译的音频任务。
- 每次识别生成独立 run ID；实时语音翻译会续接一个新的翻译 run token。授权、Speech result/error、模型翻译和 summary 回调只有在 run ID 仍匹配且 Task 未取消时才能更新 store。
- `speechTranslationTask` 由 store 持有。取消先失效 run ID，再取消 Speech recognition / translation Task；新 run 在生成新 token 前取消并清空旧翻译 Task，避免旧 defer 或旧回调污染立即重试。
- 麦克风权限 `await` 返回后必须复验 run ID 与 capture request；模型翻译 `await` 返回后必须在 transcript、summary、状态或错误写入前复验 Speech 所有权。

禁止：

- 不要把 Apple Speech 结果绕过 store 直接写入历史。
- 不要把未授权、设备不支持或空识别文本伪装成成功。

### 1.6.1 语音识别质量探针
职责：对版本化真实音频 corpus 运行 Apple 本机 Speech，并以确定性算法生成可审计质量报告，不参与产品识别候选选择。

输入：

- `test/speech_corpus/manifest.json`。
- 同目录真实音频；每项声明 SHA256、字节数、locale 和参考 transcript。

输出：

- `Output/speech_quality_report.json`。
- `Output/speech_quality_report.txt`。
- 英文等空格分词语言的词级 WER，以及所有语言的 CER、延迟、分段、平均置信度和失败 breakdown。

关键文件：

- `AITRANS/Models/SpeechQualityModels.swift`
- `AITRANS/Services/SpeechQualityEvaluator.swift`
- `AITRANS/Services/SpeechQualityProbeService.swift`
- `scripts/validate-speech-corpus.py`

规则：

- `TranslationSessionStore` 持有探针状态、run ID 和取消入口；UI 不直接调用服务。
- runner 强制 `requiresOnDeviceRecognition = true`，逐项先校验音频身份。
- 参考 transcript 只传给识别完成后的 evaluator，不传给 `SFSpeechURLRecognitionRequest`。
- 中文、日文没有稳定词分割时 `wordErrorRate = nil`，只报告 CER。
- corpus 缺失时报告 `manifestMissing` / `qualityExecuted=false`，不产生质量结论。

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
  -> external TextBoxes shadow OCR（仅 readiness ready 时执行；v2.0 稳定最大基数匹配保证 block / TextBox 一对一；v2.1 把 OCR outcome 与 assignment geometry 分账，weak / Bubble unknown 可执行 shadow OCR但不能关闭 gate；每块最多 1 个 externalArtifact.textBoxCrop，不替换主输入）
  -> external TextBox orientation-aware shadow OCR（真实 artifact ready 后对竖排 / 近 90 度倍数旋转 TextBox 执行有上限 rotation OCR；v1.92 对合法凸四点 line polygon 透视校正后逐行 OCR；v1.97 隔离单行失败并保留成功行；v1.99 要求 polygon point 属于其 TextBox bbox 容差范围，partial / fallback / 全部失败与任意角度 rotation 继续进入 convergence blockers）
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

- `skip`：不下载 GGUF、不启动模拟器、不跑漫画探针，manifest 必须写明 `probeSkippedReason` 和 `modelSetupSkippedReason`。候选核心 push 的 task-scoped full 仍按需跑 Xcode；PR/已验证 merge 的 fast follow-up 复用候选 full 收据并跳过 Xcode。非 App full 也可写 `xcodeBuildRequired=false` 与任务级 skip reason。
- `ci-fast`：手动 `workflow_dispatch` 快速探针模式，使用真实 simulator、Local GGUF、`test/1.png`、deterministic 解码、whole-page OCR、bubble-first 融合、逐块翻译、失败块覆盖、clean text diagnostic 和 external artifact gate；跳过 lexicon / Vision API / slice / TextRegion crop shadow / crop experiment / line shadow / tagged batch / 模型纠错 / 纠错翻译对照 / contact sheet 等高成本诊断。
- `full`：开发页按钮和人工 full 回归默认模式，运行完整 shadow-only 对照、diagnostic PNG 和 contact sheet。

CI artifact version 优先从带 `vX.Y` 的候选 ref 解析；`smalldata_test` merge 等无版本 ref 必须回退读取 Xcode 工程唯一 `MARKETING_VERSION`。工程缺版本或多个 build configuration 的值不一致时 metadata step 直接失败，不得生成 `unversioned` 结果包。

手动 workflow 可选提供 Koharu artifact Release archive：`koharu_artifact_release_tag`、`koharu_artifact_asset`、`koharu_artifact_sha256`。CI 会在 Xcode build 前下载、校验、解压并只复制 `1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json` 到 `test/koharu_artifacts/`，随后跑 validator；`koharu_artifact_required=true` 时任一失败都会阻断工作流。该路径只接收真实 detector / segmenter 输出，不从 examples、Vision OCR、pre-crop、line、proxy、ground truth 或手写框生成 active artifact。v1.59 起，注入 archive 后的 `ci-fast/full` 还必须在 App 侧探针产物中证明 App 真消费到 artifact。v1.64-v1.99 的 orientation、identity、line polygon warp 与所属 bbox 门槛继续保留。v2.0 起 TextBox ID 必须非空且唯一，shadow OCR 使用稳定一对一最大基数匹配并要求完整 outcome partition。v2.1 起 Bubble instance ID 同样必须非空唯一；assignment 只有中心包含或 `IoU >= 0.10` 且 block / TextBox external Bubble ID matched 才可信。最终还要求 `geometryWeakBlockIndexes=[]`、`geometryUnknownBubbleBlockIndexes=[]`、`geometryCoverageRatio=1`、`geometryCoverageVerdict=complete` 才关闭 `WI/G-external-textbox-shadow-ocr-coverage`。v1.70 的注入 archive 禁止 `probe_mode=skip` 与 v1.97 exact repo/ref/SHA handoff 规则不变。

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

v3.68 的局部预览继续只消费 View 私有 crop：无效或过期 OCR 框让 crop 构造返回 `nil`，局部放大显示“局部预览不可用”，并通过 VoiceOver hint 告知仍可关闭、编辑 OCR 原文或切换文字块；OCR 修正对照仍可编辑。该边界不新增 Store／持久化状态，也不改变 Vision OCR、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.69 在结果行和完整图片预览的 VoiceOver 摘要中复用 `NormalizedImageRect.normalizedToUnit()` 判断定位可用性：无效或过期框提前读出“定位不可用”，结果行显示位置不可用图标，同时保留 OCR 修正和切换文字块入口。该 View-only 反馈不新增 Store／持久化状态，不改变 Vision OCR、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.70 让完整图片预览的 VoiceOver hint 根据定位不可用数量动态分流：有效文字块可打开局部放大，异常文字块明确局部预览不可用；继续保留既有状态门、OCR 修正和切换文字块入口。该 View-only 反馈不新增 Store／持久化状态，不改变 Vision OCR、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.71 的开发控制台仍消费漫画探针返回的单一 `MangaOverlayExternalArtifactReadinessReport`，但把下游门控拆成可读的坐标、mask payload、mask 拓扑和工件身份摘要；status row、VoiceOver hint 与可复制 code block 都明确当前阻塞和 CI 对账要求。该 View-only 改动不创建/修改 active `test/koharu_artifacts`，不放宽 shadow OCR gate，不改变普通图片 OCR、翻译、renderer/export、漫画探针或 Koharu 主路径；真实四件套缺失时仍保持 `manifestMissing / stopUntilArtifactsProvided`。

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
用户点击照片或图片文件入口
  -> Store 前置检查图片翻译 Pro 权限；拒绝则显示 Alert 且不打开系统选择器
  -> 授权后从 PhotosPicker 或文件选择器选择图片
  -> 图片页显式选择输入语言和目标语言（目标语言 Pro 门控）
  -> View 只把 loader / 带 selection UUID 的 result 交给 TranslationSessionStore
  -> Store 创建图片 task ID，立即固定本次源/目标语言并进入 loading
  -> 新照片 / 文件可抢占运行中任务；取消、清空和新 task 使旧 transfer 回调失效
  -> task UUID 隔离 sandbox 输入；await 后 identity 匹配才发布 retry source
  -> 被抢占的临时输入、被替换或清空的旧源删除；取消后的当前源可保留重试
  -> Retry 只在 failed，或取消后 idle 且 source 文件仍存在时显示
  -> translated 且 Store-owned source 仍存在时显示重新识别；复用内容语言与既有 run isolation
  -> 摘要显示平均置信、低置信块、竖排与方向待定数，不使用 ground truth
  -> 新任务 / 清空删除当前稳定导出；模式重渲染先删除被替代导出
  -> 重渲染发布 rendering 并禁用模式切换；当前失败显示 danger + 重试导出
  -> success / cancel / failure 按 render ID + 图片 task ID 收口，旧结果拒收
  -> App 启动分账接管 marker + render UUID 稳定导出、task UUID 输入副本和 render UUID staging
  -> 清理上次异常退出残留；正常 input / staging 删除也校验 workspace + 文件类型并登记失败 ownership
  -> 拒绝任意文件名 / wrong-kind / 目录外 / 嵌套 / escape / symlink / dangling symlink
  -> 删除失败保留对应 ownership，后续生命周期重试
  -> 分享时 Store 发布 preparing，创建 ImageTranslationShares/share UUID/可读文件名
  -> 准备中禁用重复导出；当前失败显示 danger，旧 request 不覆盖新状态
  -> dismiss / 新任务 / 清空 / 重渲染 / 启动时清理，晚到 share request 拒收
  -> VisionOCRService.recognizeTextBlocks
  -> 保守方向证据：CJK 高框竖排，否则 horizontal / unknown fallback
  -> 横排上->下/左->右；竖排列右->左、列内上->下；方向隔离聚类
  -> 每块按固定目标语言调用 translate
  -> ImageTranslationBlock
  -> 逐块翻译中只读查看 / 定位；仅 translated 后可改结果或复查进度
  -> 风险块的完成/撤销由当前图片会话 Store 状态维护；面板重建后继续，新图、取消和清空重置且不落盘
  -> 用户可在结果行修正单块 OCR 原文
  -> Store 以 correction ID + 图片 task ID + 旧原文快照隔离，只重译目标块
  -> 首次修正私有保留 Vision OCR 基线；可无模型恢复基线并重新打开该风险块复查
  -> 成功后更新当前图片 transcript 并触发同模式导出重绘；失败保留旧 block 与导出
  -> 旁贴或覆盖 UI
  -> 同模式顶左坐标 PNG 导出
```

### 2.3 音频翻译
```text
用户选择或长按录音
  -> Apple Speech on-device recognition
  -> recognized text
  -> store-owned speechTranslationTask
  -> TranslationSessionStore.translate
  -> await 后核对 Task cancellation + Speech run ID
  -> UI 展示
```

### 2.3.1 语音质量评测
```text
开发页或 DEBUG launch flag
  -> TranslationSessionStore.runSpeechQualityProbe
  -> 读取 manifest + 校验 manifest/audio SHA256/字节数
  -> Apple Speech URL recognition（on-device required）
  -> 最终 transcript 返回
  -> SpeechQualityEvaluator（参考文本仅在此处参与）
  -> 英文等词级 WER / 全语言 CER / latency / confidence / failure category
  -> Output/speech_quality_report.json + .txt
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
  -> Agent B 集中 push 核心 commit 到 codeb/...
  -> GitHub Actions 跑一次 task-scoped full：基础静态 + 相关领域契约 + 必要 Xcode build
  -> full 成功，为候选 SHA 写 AITRANS CI/full-validation status 并上传未加密结果包
  -> Agent B 创建 PR：base=smalldata_test, head=codeb/...
  -> PR opened/reopened/ready-for-review 只跑 fast；不监听 synchronize
  -> Agent C 通过 PR 和结果包核对 diff、日志、manifest 和 artifact
      -> 失败：C 输出退回清单，B 修复 push 并重新跑对应 full
      -> 通过：C 经 PR merge 合并回 smalldata_test
  -> merge workflow 核验第二父 full status：success 走 fast 并把 receipt 传播到 merge SHA，缺失/失败回退 full
  -> 后续 smalldata_test 纯元数据提交：父 propagated receipt=success 才 fast；缺失/失败强制当前头部 Xcode build
      -> C 删除远端 codeb/... 候选分支
```

分支规则：

- `main` 只作为外观展示分支，禁止合并日常开发成果。
- `smalldata_test` 是当前远端真实工作主分支；若旧提示词写成 `samlldata_test`，以 `origin/smalldata_test` 为准。
- `codeb/vX.Y-短标题` 是 Agent B 候选实现分支。
- Agent B push 后默认创建 PR 到 `smalldata_test`；Agent C 通过 PR merge 收口。
- Agent C 合并后必须删除远端 `codeb/...` 候选分支，或说明没有权限删除，避免长期堆积。

结果包规则：

- 加密打包 workflow 只在软件包交付时手动触发，不随 `smalldata_test` merge 自动 archive；不作为 Agent C 验收依据，不为验收改动密码或解密流程。
- Agent C 使用独立未加密 CI 结果包验收；`xcodeBuildRequired=true` 时必须核对 `.xcresult`，build-skip 快路径必须核对 skip reason，同时核对 `junit.xml`、`xcodebuild.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`。
- `ci-artifact-manifest.json` 必须能追溯 `version`、`branch`、`commitSha`、`runId`、`runAttempt`、`workflowName`、`validationProfile`、`validationReason`、复用 full SHA/status、各领域 required flags、`scheme`、`destination`、结果路径和探针报告路径。
- 云端失败时，workflow 必须保留日志和失败摘要，Agent C 按结果包指出应交回 Agent B 修复的失败阶段和日志位置。
- 手动探针 workflow 会从 Release `model-gemma-3-270m-it-qat-q4_0-v1` 下载 `gemma-3-270m-it-qat-Q4_0.gguf`，校验 SHA256 `3626e245220ca4a1c5911eb4010b3ecb7bdbf5bc53c79403c21355354d1e2dc6`，并缓存到 `.ci-models/`。
- 候选核心 push 默认 `validationProfile=full`、`probe_mode=skip`；PR fast 与有成功候选收据的 merge fast 只跑基础静态/路由契约。fast 不下载 GGUF、不创建模拟器、不安装 App、不跑 Xcode、不跑领域大契约。
- merge fast 会把已验证候选的 full receipt 传播到 merge SHA。后续 `smalldata_test` 纯 README / AGENTS / update log / `md/` / metrics 提交只有该父 receipt 为 success 时才允许 fast；artifact 记录 `smalldataParentSha`、`smalldataParentFullValidationState`、`smalldataIncrementalMetadataOnly`、`smalldataMetadataRequiresFullValidation` 和 `receiptPropagationAllowed`。父 receipt 缺失或失败时，当前头部必须执行 Xcode build；任何传播 fast 都不是新的编译证据。
- full 按 changed files 路由 Speech、UI、文本首页和 Koharu 契约。Speech 领域同时运行 run-id contract、质量算法 contract、纯 Swift evaluator 和 corpus validator；当前缺 corpus 时只记录 `manifestMissing`。UI evidence 仅由候选 commit `[ui evidence]` 或手动 `ui_evidence_mode=full` 启用；Speech 默认不截图。漫画/翻译结果图只来自手动 `ci-fast/full` 的探针 `output/`。
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
- v21 `externalArtifactReadinessReport` 是真实 TextBoxes / BubbleMask / SegmentMask 适配前证据闸门；它只读 `test/koharu_artifacts/` 或 manifest 指定文件，做解析、坐标校验和 block alignment。v3.2 起 contract v2 的 BubbleMask / SegmentMask 使用 `rowMajorRLE`，解码像素不得超过源图且必须精确等于 `width * height`；Bubble 重算唯一 `maskValue` 的 `pixelCount` / tight bbox，Segment 重算 glyph pixels / 四连通 components。v3.3 的 `maskTopologyReport` 与 `WI/G-external-mask-topology-linkage` 复用 `stableOneToOneExternalTextBoxShadowMatching`，要求全部 block / glyph 像素的 TextBox→SegmentMask→BubbleMask 归属唯一且 partition 守恒，foreign、no-bubble、orphan、overlap、duplicate 或 cross-Bubble component 都阻断。两个 gate 都保持 shadow-only，不改 OCR、翻译、renderer、`blockPassed` 或 `currentBlockSource`。v1 摘要仍可读取，但只标记 `legacySummaryOnly`。没有真实 artifact 时输出 `manifestMissing` / `stopUntilArtifactsProvided`，不能用现有 Vision OCR、pre-crop plan 或 line plan 伪装 detector 输出。
- v1.13 `externalTextBoxShadowOCRReport` 是 readiness 通过后的 external TextBoxes shadow OCR 层；选择只使用 IoU、center containment、confidence、bubble alignment 和面积比例，不使用 ground truth。默认缺 active artifact 时 `executed=false`、`candidateCount=0`、所有块 skipped；结果只进入 report / TXT，不改变主流程。v1.64-v1.99 的 orientation / polygon warp 与 partial blocker 继续保留。v2.0 起先构造所有合法 block / TextBox edge，再用确定性增广路径得到最大基数一对一 assignment并输出完整 outcome partition。v2.1 的 `spatialGeometryVerdict`、`bubbleAlignmentVerdict` 与 `assignmentGeometryTrusted` 记录逐 assignment 几何；report 顶层输出 trusted / weak / unknown Bubble blocks、阈值、ratio 和 verdict。OCR 与 geometry 两条 ledger 都 complete 才允许 `WI/G-external-textbox-shadow-ocr-coverage` 闭合。
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
- v1.12 / v22 外部 artifact 契约把 active 输入固定为 `test/koharu_artifacts/`，把非活动 fixture 固定为 `md/koharu研究/artifact_contract/examples/`，并用 `scripts/validate-koharu-artifacts.py` 在进入 App 探针前校验 schema、路径、坐标、bbox、confidence、source image、TextBoxes、BubbleMask 和 SegmentMask。v3.2 接受 `aitrans.koharu_artifact_contract.v1` 摘要兼容和 `v2` 像素载荷；v3.3 再输出 `maskTopologyValidation` / `maskTopologyGateReady`。云端注入验收必须为 v2，且 payload / topology 两个 gate 都为 true。manifest artifact path 必须留在 active 目录内，绝对路径和 `..` 逃逸都阻塞；既有身份、polygon 所属、TextBox / Bubble ID 唯一和 `generatedBy` 真实来源规则不变。只有 `readinessVerdict = readyForShadowOCR`、`activeArtifactsDirectory = true` 且 `contractExampleOnly = false` 时，`externalTextBoxesShadowOCRAllowed` 才能为 true；完整 mask convergence 还必须通过 `G-external-mask-pixel-payload` 和 `G-external-mask-topology-linkage`。
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
