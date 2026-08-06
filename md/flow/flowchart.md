# 项目流程图
v3.121 图片 OCR 失败／取消且没有待重试语言变更时，VoiceOver 可在图片翻译状态上直接执行受门控的“重试当前图片”action；源图片不可用时提示重新选择图片，仍只属于 View，不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31076710802`、PR #185 fast `31077094866`、merge fast `31077152440` 均通过。
v3.120 图片 OCR 的待重试语言状态现在可直接执行受门控的“重试当前图片”VoiceOver action，复用既有 Store retry；只属于 View，不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31075361390`、PR #184 fast `31075697828`、merge fast `31075745893` 均通过。
v3.119 图片 OCR 失败／取消后若待重试语言真正改变，VoiceOver 焦点交给“重试语言已更新”状态行；该 handoff 复用 revision-scoped generation，只属于 View，不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31074379707`、PR #183 fast `31074819588`、merge fast `31074863470` 均通过。
v3.118 漫画探针报告若有阻断 readiness，先把共享 VoiceOver focus 交给“Koharu 工件就绪状态”，再由筛选变化回到逐块结果；只属于 View，不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31073337578`、PR #182 fast `31073688262`、merge fast `31073828173` 均通过。
v3.117 漫画诊断筛选变化先收起旧展开详情，再通过 generation requester 聚焦新筛选首项；reset 只属于 View，不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31072107788`、PR #181 fast `31072405558`、merge fast `31072447592` 均通过。
v3.116 漫画探针诊断筛选、重跑终态和逐块展开／收起共用 View 私有焦点 generation，最新 VoiceOver 请求胜出；新 probe loading 使旧请求失效，不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31071423891`、PR #180 fast `31071714254`、merge fast `31071752236` 均通过。
v3.115 图片 OCR VoiceOver 焦点请求按 generation 与 imageTranslationRevision 仲裁，只保留最新动作；该 View-only handoff 不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31070650744`、手动 full `31070655111`、PR #179 fast `31070940503`、merge fast `31070976672` 均通过。
v3.114 新探针 loading 会收起旧漫画诊断详情并阻止旧焦点回抢，结果行读出当前展开状态；只读 View 状态，不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31069913494`、手动 full `31069918901`、PR #178 fast `31070264175`、merge fast `31070323190` 均通过。
v3.113 漫画探针逐块诊断展开后聚焦详细诊断容器，收起后返回结果行；只读既有 report，不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31068769954`、手动 full `31068778764`、PR #177 fast `31069311041`、merge fast `31069349841` 均通过。
v3.112 普通图片 OCR 在新 revision 完成或失败后恢复 VoiceOver 焦点：有 blocks 时聚焦当前筛选的首个 OCR 结果，没有 blocks 时聚焦动态图片状态行；revision guard 防止旧任务抢回焦点。该 View-only handoff 不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31067968394`、PR #176 fast `31068324104`、merge fast `31068365757` 均通过。
v3.111 漫画探针重跑在报告更新后恢复 VoiceOver 焦点：有 blocks 时聚焦当前筛选的首个诊断 block，没有 blocks 时聚焦明确的“未生成逐块诊断”重试状态；loading 先清除旧焦点。该 View-only handoff 不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31067283530`、PR #175 fast `31067583454`、merge fast `31067629934` 均通过。
v3.110 普通图片 OCR 筛选焦点按来源仲裁：用户切换筛选时交给首个可见结果，程序化复查／恢复／预览动作保留明确焦点，revision 重置清除意图并保留空态；该 View-only 改动不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31066203170`、PR #174 fast `31066589776`、merge fast `31066628727` 均通过。

v3.108 漫画诊断筛选切换到有结果时把 VoiceOver 焦点交给第一个可见 block，空筛选仍使用可操作空态；该 View-only handoff 不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31063355633`、PR #172 fast `31063761078`、merge fast `31063805810` 均通过。

v3.107 筛选没有结果时，普通图片 OCR 与漫画诊断页将 VoiceOver 焦点交给明确空态，读出筛选类别、`0 / 总数` 和切换筛选的下一步；该 View-only handoff 不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31020576411`、PR fast `31062338507`、merge fast `31062372361` 均通过。

v3.106 普通图片 OCR 与漫画探针筛选器的 VoiceOver value 显示当前类别、显示数／总数，图片筛选再显示复查已完成／剩余数；仅改善 View 语义，不新增 Store 状态，不改变 OCR、翻译、renderer/export 或主流程。候选 full `31017118790`、PR fast `31017809552`、merge fast `31017909329` 均通过，真实 Koharu 四件套仍缺失。

v3.105 诊断总览把既有收敛报告的开放／已闭环／要求停止工单、block path/work-item ledger 规模、状态 breakdown 和真实外部工件边界显示在状态、可复制摘要和 VoiceOver 中；不新增 Store 状态，不改变 OCR、翻译、renderer/export 或主流程。候选 full `31015086472`、PR fast `31015765732`、merge fast `31015838087` 均通过。

v3.104 逐块漫画探针行把既有 Koharu convergence block path、开放工单和执行边界显示在结果行、可复制摘要和 VoiceOver 中；未闭环工单或 report-only 边界统一使用 warning/仅报告，不新增 Store 状态，不改变 OCR、翻译、renderer/export 或主流程。候选 full `31013385953`、PR fast `31014071238`、merge fast `31014141913` 均通过。

v3.103 诊断总览把既有 native promotion、artifact contract dry-run、artifact identity reconciliation 与 convergence 的晋级边界显示在状态、可复制摘要和 VoiceOver 中；不新增 Store 状态，不改变 OCR、翻译、renderer/export 或主流程。候选 full `31011231211`、PR fast `31011777761`、merge fast `31011846424` 均通过。

v3.102 逐块漫画探针行把既有 pipeline resolver、work-order、外部工件请求包和 native replay 的执行边界显示在结果行，并同步进入 VoiceOver；不新增 Store 状态，不改变 OCR、翻译、renderer/export 或主流程。候选 full `31009117560`、PR fast `31009686004`、merge fast `31009749466` 均通过。

v3.101 逐块漫画探针行把既有 bottleneck、model-floor、render-fit 与 artifact-DAG 诊断依据显示在结果行，并同步进入 VoiceOver；不新增 Store 状态，不改变 OCR、翻译、renderer/export 或主流程。候选 full `30993659770`、PR fast `30994207268`、merge fast `30994272480` 均通过。

v3.100 逐块漫画探针行把既有 internal/floor/render/DAG report-only ledger 的推荐下一步与 Koharu 工件门控显示在结果行，并同步进入 VoiceOver；不新增 Store 状态，不改变 OCR、翻译、renderer/export 或主流程。候选 full `30992318412`、PR fast `30992932438`、merge fast `30993004271` 均通过。

v3.99 逐块漫画探针行把已有 OCR／翻译／布局 report-only risk set 显示为风险标签，并同步进入 VoiceOver value/hint；不新增 Store 状态，不改变 OCR、翻译、renderer/export 或主流程。候选 full `30991030339`、PR fast `30991418709`、merge fast `30991478674` 均通过。

本文用 Mermaid 图展示 `md/flow/flow.md` 的当前核心逻辑。读图时先看左到右的主链路，再看向下分叉的诊断和输出产物。

当前正式版本：`3.121`。 v3.56 让漫画覆盖翻译探针状态行按阶段提供 VoiceOver 状态 value/hint，运行按钮明确 test/1.png、Output 和只影响探针诊断的范围，不新增 Store／持久化状态。 v3.57 让漫画探针逐块结果按 block index、PASS/FAIL、OCR 原文、置信度、译文和失败详情提供 VoiceOver 上下文，展开提示保持探针诊断边界，不新增 Store／持久化状态。 v3.58 让图片复查结果行按 OCR 原文提供稳定 VoiceOver label，value 区分等待翻译与真实译文并处理空 OCR 回退，不新增 Store／持久化状态。 v3.59 让完整图片预览的覆盖文字块与图片复查结果行共用稳定的 VoiceOver label“图片文字块 + OCR 原文”，空 OCR 回退为“空”，并保留既有等待翻译／译文 value、定位 hint 和选中状态；该改动只改善 View 语义，不新增 Store／持久化状态，不改变选择、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。 v3.60 让完整图片预览的覆盖文字块与图片复查结果行对齐 VoiceOver value：读出 OCR 置信度（clamp 到 0–100%）、人工修正、低置信／方向待定、待复查／本次已复查及等待翻译／译文；相邻与替换模式共用这套上下文，只改善 View 语义，不新增 Store／持久化状态，不改变选择、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。

图片输入／目标语言菜单的 VoiceOver hint 按运行中、Pro 门槛、无图片、已完成和失败／取消重试状态分流；运行中保持 disabled 边界，完成后分别说明重新识别／翻译或重新翻译当前图片，选回当前内容语言撤销待重试差异。照片与文件导入按钮在读取、OCR 或翻译进行中说明选择新图片会取消当前任务并开始新的本机 OCR 与翻译，同时保留替换入口与 Store run-id 隔离。图片状态行现在以单一 VoiceOver 元素读出当前阶段、进度和下一步操作；图片结果行还会在定位状态之外读出 OCR 置信度、低置信／方向待定、人工修正、复查进度和等待翻译；已忽略 OCR 文字块恢复行还会读出移除范围、译文保留和恢复可用性。该 View 语义不新增 Store／持久化状态。v3.54 修复图片状态 value 的字面量回归，改为实时插值 `statusTitle`／`statusDetail`，不新增 Store／持久化状态。 v3.55 让 Koharu readiness 缺失工件的下一步和 shadow-only 边界可被 VoiceOver 一次读清，不新增 Store／持久化状态。v3.61 让图片复查结果行和完整图片预览消费既有方向证据：显示横排／竖排及有限方向置信度，OCR 置信度显示夹到 0–100%；只改善 View 语义，不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、探针或 Koharu 主路径。

v3.62 的图片识别结果摘要继续由 `ImageOCRResultSummary` 计算，并在已有平均置信度、低置信、竖排和方向待定信息之外显示横排 block 数；该摘要只改善复查入口的可读性，不新增 Store／持久化状态、不重跑 OCR／翻译，也不改变 renderer/export、漫画探针、Koharu 或质量基线。

v3.63 将“识别结果”摘要合并为单一 VoiceOver header，复用已有摘要 value，并按无图片、翻译未完成、无待复查块和可复查状态读出下一步 hint；该改动只改善图片复查可操作性，不新增 Store／持久化状态、不重跑 OCR／翻译，也不改变 renderer/export、漫画探针、Koharu 或质量基线。

v3.64 的图片 OCR 置信度先经过统一安全归一化：有限值夹到 `0...1`，NaN/∞ 回退为 0；同一边界供布局、摘要、复查筛选、结果行和覆盖层使用，避免无效数值污染用户提示。该修复不新增 Store／持久化状态、不改变 OCR 候选、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.65 让图片 OCR 修正 sheet 的低置信度百分比也接入共享安全归一化；异常值不会污染显示，不新增 Store／持久化状态，不改变 OCR 候选、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.66 的 Vision OCR bounding box 先经过 finite／positive-area／unit-space 整矩形归一化，布局引擎丢弃仍无效的 observation；覆盖、定位和阅读排序不再接收 NaN/∞ 或越界几何。该改动只强化图片几何安全，不改变 OCR 候选、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.67 将该几何边界复用到 `NormalizedImageRect` 的旧会话读取、图片覆盖、局部预览和导出；无效 block 不显示也不绘制，避免异常框污染用户操作或导出 PNG，不改变 OCR 候选、翻译、漫画探针、Koharu 或质量基线。

v3.68 让无效或过期 OCR 框的局部放大显示明确不可用状态，不再把整图作为当前文字块回退；关闭、编辑 OCR 原文和切换文字块入口保留，VoiceOver hint 会读出该边界。修正对照仍可编辑，不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.69 让结果行与完整图片预览的 VoiceOver 摘要提前报告无效或过期 OCR 框的“定位不可用”数量，结果行显示位置不可用图标并保留 OCR 修正、切换文字块入口；只消费既有几何安全边界，不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.70 让完整图片预览的 VoiceOver hint 按定位不可用数量区分有效文字块和异常文字块：前者可打开局部放大，后者明确局部预览不可用；不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.71 让开发控制台的 Koharu readiness 摘要同时显示坐标、mask payload、mask 拓扑和工件身份门控，并在 VoiceOver/可复制摘要中保留阻塞项与 CI 对账边界；只读既有报告，不创建 active 工件，不改变 OCR、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.72 在 readiness 诊断分支中把 v1 `summary-only` 的 v2 mask payload／topology 状态读作“未要求”，而不是“失败”；真实 v2 工件仍沿用实际 gate/blocker。VoiceOver 与可复制摘要共享这套解释，且不创建 active 工件、不改变主链路或质量基线。

v3.73 在图片复查分支为被忽略且 OCR 原文为空的 block 显示“空 OCR 原文”，并让 VoiceOver label 使用“空”回退；恢复按钮、焦点交接和 Store ownership 不变。

v3.74 统一普通图片 OCR 结果行与完整图片预览的旁贴／覆盖文字块空 OCR 回退：原文为空时显示“空 OCR 原文”，旁贴／覆盖仍以非空译文优先；该 View-only 变化不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、复查、探针或 Koharu 主路径。
v3.75 让 OCR 修正参考预览与完整图片局部聚焦预览在空 OCR 原文时以“空”作为 VoiceOver value 回退，避免定位／对照入口失去上下文；非空原文、选择与 Store ownership 不变。
v3.76 将局部聚焦预览的“局部放大”角标设为无障碍隐藏，保留父容器的已定位文字块上下文与关闭／修正／复查／导航入口，避免重复朗读。
v3.77 将无效局部预览的纯状态子视图设为无障碍隐藏，保留父容器的不可用说明与关闭／修正／复查／导航入口，避免重复朗读。
v3.78 关闭局部聚焦预览后，将 VoiceOver 焦点交回对应 OCR 结果行；焦点交接使用 View 私有 identity，不进入 Store 或产品处理链路。

v3.79 局部聚焦预览的上一个／下一个文字块导航在更新筛选后的目标选择后，将 VoiceOver 焦点交给新的预览容器；导航仍只消费 View 私有选择、位置 value 与边界 disabled 状态，不新增 Store／持久化状态，也不改变 OCR、翻译、renderer/export、复查、探针或 Koharu 主路径。

v3.80 筛选器隐藏当前选中 OCR block 时，先清除局部预览选择，再按“首个可见结果行 → 复查完成状态 → 筛选器”顺序寻找焦点目标；该 handoff 仅在 View 私有 accessibility focus 中运行，不进入 Store 或 OCR/翻译处理链路。

v3.81 结果行和完整图片覆盖块选中 OCR block 后，将 VoiceOver 焦点交给对应局部预览；取消定位时回到对应结果行。该路径只改变 View 私有焦点，不改变 OCR、翻译、renderer/export、探针或 Koharu 主链路。
v3.82 漫画探针失败覆盖的文本布局按显式换行分段测量；fit plan 与实际绘制共用换行结果，碰撞未解决与实际截断继续如实记录。该诊断路径不改变 OCR、翻译、renderer/export、Koharu 或质量基线。
v3.83 Koharu fit planner 复用 `wrappedLines` 的显式换行预算，并读取实际 `renderTextTruncated`，使失败覆盖的报告从“currentSpriteFits”改为可解释的 long-text risk；只改诊断 report，不改变 OCR、翻译、renderer/export、Koharu active artifact gate 或质量基线。

v3.84 Koharu fit planner 继续传播 `renderMinFontSizeReached`，让逐 block、汇总与 report-only gate 对齐实际渲染锁证据；只改善诊断可观测性，不改变 OCR、翻译、renderer/export、active artifact gate 或质量基线。

v3.85 Koharu render-lock report 汇总 `renderMinFontSizeReached`，让 block、顶层列表、gate 与诊断摘要共享最小字号压力证据；只改 report，不改变 OCR、翻译、renderer/export、active artifact gate 或质量基线。

v3.86 Koharu render-lock 输出 ledger 识别 `probe_report.json` 与最终重写 `1_ocr_probe_text.txt` 的 planned-final-write 时序，避免把实际非空 OCR 文本误判为空；ci-fast 报告现在能区分 `G-render-core-png-retained=passed` 与真实 block 5 的文字截断风险。该诊断只改 report，不改变 OCR、翻译、renderer/export、active artifact gate 或质量基线。

v3.87 Koharu render-lock 输出检查继续只读报告状态：planned final write 且 `nonEmpty=true` 的 `probe_report.json` / `1_ocr_probe_text.txt` 推荐动作统一为 `keepReportOnly`，缺失或未检查输出才引导 `inspectRenderOutputExport`。该诊断只改 report，不改变 OCR、翻译、renderer/export、active artifact gate 或质量基线；云端探针仍诚实保留 block 5 的实际截断风险。

v3.88 Koharu render-lock 的 `G-render-core-png-retained` gate 现在消费与 `outputFileChecks` 相同的推荐动作：required 输出 retained 且非空时为 `keepReportOnly`，缺失/空输出才为 `inspectRenderOutputExport`。只改 report 诊断，不改变 OCR、翻译、renderer/export、active artifact gate 或质量基线；block 5 截断仍保持开放风险。

v3.89 Developer Console 的 `outputFiles` 摘要新增 required 输出 `recommendedAction` breakdown（ci-fast 实际为 `actionBreakdown=keepReportOnly=5`），与核心输出 gate 共用既有 report-only 数据；只改诊断可读性，不改变 OCR、翻译、renderer/export、active artifact gate 或质量基线，block 5 截断和 `manifestMissing` readiness 仍如实保留。

v3.90 漫画探针失败覆盖保留完整 OCR fallback 和 `翻译失败` 标记，仅在显示层把 OCR continuation 的显式换行压缩为空格；fit planner、safe-layout 诊断和实际绘制共用该变换。ci-fast 报告的 block 5 无 `renderTextTruncated`／最小字号锁，render lock 为 `renderStableWithProxyBoundaries`；该 report/render-only 修复不改变 OCR、翻译、renderer/export、Koharu active artifact gate 或质量基线，真实四件套仍缺失。
v3.91 开发控制台在漫画探针报告下增加只读“诊断分流”节点：把 OCR 疑似、翻译模型／语言质量、覆盖布局和 Koharu 工件门控汇总为下一步，并在失败 block 行显示现有 failureCategory；不改变探针候选、翻译、renderer/export 或主流程。full `30886955217`、ci-fast `30887582600`、PR fast `30888608909`、merge fast `30888676363` 均通过，真实四件套仍缺失。
v3.92 在普通图片 OCR 复查分支增加低置信／方向待定筛选，并保持待复查风险并集、当前筛选定位和无障碍空态；漫画探针分支增加只读全部／失败／OCR／翻译／布局筛选。筛选只消费既有结果，不改变 OCR、翻译、覆盖绘制或 Store。候选 full `30889811326`、PR fast `30890241624`、merge fast `30890322575` 均通过，真实 Koharu 四件套仍缺失。

v3.93 在 Store 图片 revision 变化时重置普通图片复查的 View 私有筛选、旧选择和焦点，避免新图沿用旧风险筛选而显示空结果；不改变 OCR、翻译、renderer/export、探针或 Store。候选 full `30890823578`、PR fast `30891431628`、merge fast `30891485989` 均通过，真实 Koharu 四件套仍缺失。

v3.94 漫画探针失败入口在 bundle 查找前清空旧状态，并在缺失 `test/1.png` 时重建 App 沙盒 `Output`；失败报告保留清理计数与清理是否成功，清理失败不会把旧输出当成本轮结果。该 report-only/状态一致性修复不改变 OCR、翻译、renderer/export 或 Koharu active gate；full `30893309273`、PR fast `30893920011`、merge fast `30893993759` 均通过，真实四件套仍缺失。

v3.95 漫画探针报告为空 blocks 时，开发控制台改为显示“本次探针未生成文字块”及可访问的失败/重试上下文，并隐藏不适用的诊断筛选器；有 blocks 时才显示逐块筛选。该 View-only 变化不改变 OCR、翻译、覆盖绘制、Koharu gate 或 Store；full `30984932342`、PR fast `30985360673`、merge fast `30985413482` 均通过，真实四件套仍缺失。

v3.96 漫画探针诊断分流的状态色遵循 readiness 门控：active Koharu 工件缺失或阻断时保持 warning，只有门控不阻断且报告通过时才显示 success；不改变探针报告、OCR、翻译或覆盖绘制。full `30985776084`、PR fast `30986258687`、merge fast `30986307343` 均通过，真实四件套仍缺失。

v3.97 漫画探针的布局筛选与诊断摘要共享 fit planner/render-lock 的既有风险集合；字号预算紧张、sprite 包含和 sibling overlap 会进入只读布局分流，但不会进入生产 renderer 或普通图片 OCR。ci-fast `30986469563` 提供 10/7/6 风险观察，full `30987210261`、PR fast `30987676638`、merge fast `30987725142` 均通过。

v3.98 漫画探针 OCR 与翻译筛选、triage 摘要共享 `mangaProbeOCRRiskBlockSet` 与 `mangaProbeTranslationRiskBlockSet`，并集既有 diagnostics、model-floor 和 failureCategory；这只改善 report-only 分流一致性，不改变 OCR、翻译、renderer/export 或主流程。full `30988262491`、PR fast `30988802078`、merge fast `30988876405` 均通过。

## 1. 项目核心逻辑图
这张图描述 App 从用户入口到状态调度、OCR/模型服务、持久化和探针输出的关系。

```mermaid
flowchart TD
  %% 用户入口：文本、图片、音频、开发页探针
  A["用户操作 / test 固定素材"] --> NAV{"设备布局"}
  NAV -->|"iPhone"| TAB["五入口 TabView"]
  NAV -->|"iPad"| SPLIT["NavigationSplitView"]
  TAB --> B["拆分的 SwiftUI feature views<br/>文本 / 图片 / 音频 / 历史 / 设置 / 开发"]
  SPLIT --> B
  DS["AppTheme + AppComponents<br/>语义 token / 状态 / 44pt / 响应式布局"] --> B
  TWB["TextWorkspaceBackground<br/>静态网格 / 导向线路 / 文本页专属"] --> B
  SH["文本页顶部 safe-area inset<br/>页头 + 模型状态"] --> B
  SH -. "不参与键盘自动滚动" .-> D

  %% 状态中心：所有业务动作统一进入 store
  B --> C["TranslationSessionStore<br/>统一状态、调度、持久化、诊断"]

  %% 文本翻译分支：普通用户输入
  PASTE["用户点击纯文本 PasteButton"] --> APPEND{"draftText 是否为空?"}
  APPEND -->|"是"| FILL["直接写入 store.draftText"]
  APPEND -->|"否"| ADD["换行追加，不覆盖"]
  FILL --> C
  ADD --> C
  DONE["键盘完成 / 翻译 / 新会话 / 离开文本页"] --> FOCUS["inputFocused = false"]
  FOCUS --> C
  C --> D["submitDraft<br/>ModelGenerationRequest"]
  D --> E["LocalLanguageModeling<br/>Mock 或 Local"]
  E --> F["MockGemmaService<br/>UI 和数据流冒烟"]
  E --> G["GemmaLocalService<br/>GGUF 本地模型适配"]
  G --> H["LlamaRuntime<br/>llama.cpp C API 封装"]

  %% 图片 OCR 分支：普通图片翻译
  IMG_LANGUAGE["图片输入 / 目标语言菜单<br/>输入先验 Pro / 拒绝无跨页副作用<br/>actual content 与 pending Retry 分账<br/>选回 actual 清除 pending<br/>运行态冻结 / 完成态重跑"] --> C
  C --> IACCESS{"Store-owned 图片入口 Pro 授权?"}
  IACCESS -->|否| ILOCK["lock.fill + Pro Alert<br/>不打开系统选择器"]
  IACCESS -->|是| IT["PhotosPicker / 文件 importer<br/>Store-owned 图片 transfer<br/>task ID + 文件 selection UUID"]
  IT --> IG{"transfer / sandbox await 后<br/>task ID 仍匹配?"}
  IG -->|否| IDROP["丢弃旧回调并清理未采用输入<br/>不恢复旧 retry source"]
  IG -->|是| I["普通图片翻译<br/>VisionOCRService + 输入/目标语言快照"]
  ICANCEL["取消图片任务"] --> IRETRY{"sandbox source 已发布且仍存在?"}
  IRETRY -->|是| IR["idle + 显示重试"]
  IRETRY -->|否| IDROP
  ICLEAR["点击清空图片翻译"] --> ICONFIRM{"确认删除图片与结果?"}
  ICONFIRM -->|取消| IRETAIN["保留当前图片与结果"]
  ICONFIRM -->|确认| ICLEARED["Store 清理 task / source / export / share"]
  I --> ILAYOUT{"CJK + 明确高宽几何证据?"}
  ILAYOUT -->|是| IV["竖排列右到左<br/>列内上到下"]
  ILAYOUT -->|否| IH["横排 / unknown fallback<br/>上到下、行内左到右"]
  IV --> J["ImageTranslationBlock<br/>bbox + OCR + 方向证据 + 译文"]
  IH --> J
  J --> IQUALITY["OCR 结果摘要<br/>平均/低置信 + 竖排/方向待定<br/>全部 / 待复查筛选 + 行级快速复查<br/>逐块翻译中只读定位；锁定时状态行 / VoiceOver 说明原因<br/>仅 translated 后开放复查/修改<br/>当前图片会话复查进度由 Store 内存持有<br/>误识别忽略快照也仅当前会话保存<br/>新图 / 取消 / 清空按各自语义复位、不落盘<br/>Store-owned 重新识别"]
  IQUALITY --> ISELECT["View 私有 block 选择<br/>结果行取景框 + 预览覆盖高亮<br/>revision / 隐藏筛选清除"]
  IQUALITY --> IA11Y["VoiceOver 连续复查焦点<br/>行 / 局部放大 / 完成态分流<br/>图片覆盖与结果行复用定位提示<br/>加载/失败卡片读出状态与重试边界<br/>命令栏提示操作影响范围<br/>revision 拒收旧焦点"]
  IQUALITY --> ICORRECT["44pt 人工修正<br/>仅 translated + 非导出重绘开放<br/>非空校验 + 保存中锁定<br/>首尾空白规范化 + View 私有键盘焦点"]
  ICORRECT -. "打开修正页：结果行入口登记结果行回退；局部预览入口登记同一局部预览回退" .-> IA11YHANDOFF
  ICORRECT --> ICORRECTCONTEXT["修正 sheet 局部对照<br/>既有 2048px 预览裁切 + 黄色 bbox<br/>低置信 / 方向待定提示；失败不阻止编辑"]
  ICORRECTCONTEXT -. "语义修改才放弃确认；无修改 / trim 后仍等于原文可关闭" .-> IA11YHANDOFF
  ICORRECTCONTEXT --> IKEYBOARD["多行 OCR 输入<br/>键盘“完成” / 滚动时交互收起 / 取消 / 忽略确认 / 保存前清焦点<br/>保存中锁定输入；只改 View 键盘焦点／可见性"]
  ICORRECTCONTEXT --> IIGNORECONFIRM["识别有误？<br/>忽略文字块的明确确认<br/>未保存修正不会保存"]
  IIGNORECONFIRM -->|"确认"| IIGNORED["Store 当前会话快照<br/>原始顺序 + 人工修正 / Vision 基线<br/>移除 active block / preview / export / transcript<br/>不重新 OCR 或翻译"]
  IIGNORECONFIRM -->|"继续编辑"| ICORRECTCONTEXT
  IIGNORED --> IIGNOREDRESTORE["检查区已忽略列表<br/>仅 translated + 非导出重绘的 44pt 恢复动作<br/>可访问焦点；按原顺序插回，风险块重回待复查"]
  IIGNORED --> IRENDER
  IIGNOREDRESTORE --> IRENDER
  IKEYBOARD --> INORMALIZE{"trim 后原文改变?"}
  INORMALIZE -->|"否"| INOOP["确认无误<br/>Store no-op 标记复查<br/>不调用模型"]
  INOOP -. "sheet 关闭后复用既有成功焦点交接" .-> IA11YHANDOFF
  INORMALIZE -->|"是"| ICORRECTGATE{"correction ID + 图片 task ID<br/>block ID + 旧原文快照仍匹配?"}
  ICORRECTGATE -->|"否 / 翻译失败"| ICORRECTKEEP["保留旧 block / transcript / export"]
  ICORRECTGATE -->|"是"| ICORRECTCOMMIT["只重译目标 block<br/>成功确认风险块加入当前会话复查进度<br/>更新当前图片 transcript<br/>撤销旧 export/share"]
  ICORRECTCOMMIT --> IRENDER
  IIGNORED -. "sheet 关闭后（若有后继焦点）" .-> IA11YHANDOFF["View 私有焦点交接<br/>记录目标 focus ID + image revision<br/>onDismiss 核对后才发布"]
  ICORRECTCOMMIT -. "成功后覆盖回退；sheet 关闭后队列前进或回到已更新行" .-> IA11YHANDOFF
  IA11YHANDOFF -. "复用既有 revision/yield 焦点发布" .-> IA11Y
  ICORRECTCOMMIT --> IRESTORECONFIRM["已修正 block 的 44pt 恢复动作<br/>先确认移除本次人工修正；关闭后才交接焦点"]
  IRESTORECONFIRM -->|"确认"| IRESTORE["恢复 Vision OCR 原文 + 初始译文<br/>移除当前会话复查标记<br/>不调用模型，重新打开风险复查"]
  IRESTORECONFIRM -->|"取消 / 图片 revision 已变化"| IRESTOREKEEP["保留当前人工修正"]
  IRESTORE --> IRENDER
  IRESTORE --> IRESTOREA11Y["View 私有确认框关闭后焦点交接<br/>isPresented 关闭 + revision 核对后才发布"]
  IRESTOREA11Y -. "复用既有 revision/yield 焦点发布" .-> IA11Y
  ISELECT --> IFOCUS["已下采样预览局部裁切<br/>保留上下文 + bbox 再标记<br/>44pt 关闭 + 修正命令"]
  IFOCUS -->|"44pt 直接修正；仅 translated + 非导出重绘<br/>忙碌 / stale 时拒绝；非成功 onDismiss 回到同一局部预览"| ICORRECT
  ISELECT --> ISCROLL["唯一 workspace anchor<br/>新选择滚回图片工作区<br/>Reduce Motion 立即定位"]
  IFOCUS --> INAV["当前筛选序列前后导航<br/>位置值 + 首尾禁用<br/>可用/首尾分别说明定位与边界<br/>44pt 命名按钮"]
  IFOCUS -. "只联动展示；完整 blocks 不变" .-> IPREVIEW
  INAV -. "只更新 View 私有选择" .-> IPREVIEW
  IA11Y -. "只更新 View 私有焦点" .-> IPREVIEW
  IQUALITY -. "仅筛检查列表；完整 blocks 不变" .-> IPREVIEW
  J --> IPREVIEW["后台 ImageIO 预览下采样<br/>最大边 2048px + EXIF transform<br/>revision / cancellation 拒收旧结果<br/>准备 / 失败 / 本地重试反馈<br/>VoiceOver 容器汇总块数 / 待复查 / 定位；背景图隐藏"]
  IPREVIEW --> K["图片旁贴 / 覆盖 UI<br/>同模式顶左坐标 PNG 导出"]
  K --> IRENDER["覆盖模式重渲染<br/>rendering / failed / retry<br/>render ID 拒收晚到结果"]
  K --> IEXPORT["Store-owned 稳定导出<br/>新任务 / 清空 / 重渲染时清理"]
  ISTART["App 启动 workspace reconciliation<br/>marker + render UUID 导出 / task UUID 输入 / render UUID staging"] --> IEXPORT
  IEXPORT --> IGUARD{"直属 aitrans-export-renderUUID-*<br/>常规文件?"}
  IGUARD -->|是| IDELETE["删除被替代导出"]
  IGUARD -->|否| IREJECT["拒绝任意文件名 / wrong-kind / escape<br/>symlink / dangling symlink"]
  IDELETE --> IFAIL{"删除成功或已不存在?"}
  IFAIL -->|否| IKEEP["保留私有 ownership<br/>后续生命周期重试"]
  IEXPORT --> ISHARE["Store-owned 分享目录<br/>preparing / failed 反馈<br/>share UUID / 可读 leaf filename"]
  ISHARE --> ISHAREEND["dismiss / export 失效 / 启动<br/>request ID 拒收晚到并清理"]

  %% 音频分支：Apple 本机语音识别
  C --> LR["Speech run ID + store-owned translation Task<br/>取消 / 重试使旧回调失效"]
  LR --> L["音频识别<br/>Apple Speech on-device / requiresOnDeviceRecognition"]
  L --> LA{"授权 / 模型 await 后<br/>run ID 仍匹配且 Task 未取消?"}
  LA -->|否| LD["丢弃旧回调<br/>不写 state / transcript / summary"]
  LA -->|是| D
  L --> LV["speechRecognitionRunSummary<br/>输入 / locale / 耗时 / 词数 / 片段 / 置信度 / 失败原因"]
  AX["录音默认 accessibility action<br/>开始 / 停止"] --> L
  LC["checking / recognizing / translating<br/>均可取消"] --> LR

  %% Speech 质量分支：真实 corpus 事后评估
  C --> SQ["Speech quality probe<br/>versioned corpus + audio identity"]
  SQ --> SQR["Apple Speech URL recognition<br/>on-device required"]
  SQR --> SQE["事后 evaluator<br/>WER / CER / latency / confidence"]
  REF["reference transcript"] -. "只在最终识别文本返回后参与评估" .-> SQE
  SQE --> SQO["speech_quality_report.json / .txt<br/>failure breakdown + runtime identity"]

  SETTINGS["Settings NavigationPath"] --> DEVRESET{"开发模式仍开启?"}
  DEVRESET -->|"否"| SETTINGSROOT["清空 path / 返回设置根页"]

  %% 漫画探针分支：固定 test/1.png
  C --> M["漫画覆盖翻译探针<br/>test/1.png"]
  M --> N["MangaOverlayProbeService<br/>裁切、多角度 OCR、气泡归属、合并"]
  N --> O["逐块翻译和质量判定<br/>失败块仍写报告和绘制"]
  O --> P["探针模式门控<br/>ci-fast / full / skip"]
  P --> Q["覆盖渲染<br/>safeLayoutRect / glyph mask / 核心 PNG"]

  %% 输出：持久化和调试产物
  C --> R["state.json<br/>会话、历史、提示词、设置"]
  PREVIEW["隔离 Preview / DEBUG UI evidence 场景"] -. "仅展示状态，不执行业务服务" .-> B
  CONTRACT["v1.87 UI interaction contract<br/>动作接线 / AX / 导航 / Reduce Motion"] -. "CI 独立 testcase" .-> B
  HOME_CONTRACT["v1.88 home UI contract<br/>paste / keyboard / 背景 / 首页动作"] -. "CI 独立 testcase" .-> B
  Q --> S["App 沙盒 Output<br/>JSON / TXT / PNG"]
  M -. "报告已生成后仅读取 existing readiness" .-> DEVREADY["开发控制台 Koharu 就绪摘要<br/>ready / missing / invalid<br/>可复制缺件与 nextAction；shadow-only"]
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
  LTB --> EAR["externalArtifactReadinessReport<br/>v1 summary / v2 bounded mask RLE<br/>逐块 pixel shadow + App-side identity"]
  EAR --> EMP["WI/G-external-mask-pixel-payload<br/>Bubble majority + Bubble/Segment coverage<br/>TextBox containment / shadow-only"]
  EMP --> EMT["WI/G-external-mask-topology-linkage<br/>stable one-to-one TextBox assignment<br/>expected / foreign / orphan / component partition"]
  EAR --> ETS["externalTextBoxShadowOCRReport<br/>ready 后每块最多 1 个 externalArtifact.textBoxCrop / shadow-only"]
  ETS --> ESC["external TextBox shadow OCR coverage gate<br/>v2.1 一对一 + 完整 partition + OCR 全成功<br/>center-contained 或 IoU>=0.10 + Bubble ID matched + geometryCoverageRatio=1"]
  ESC --> ETO["external TextBox orientation-aware shadow OCR<br/>bounded rotation + v1.92 polygon warp + v1.97 逐行失败隔离<br/>v1.99 polygon 必须属于 TextBox bbox / 非法 artifact 阻塞"]
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
  KNPG --> KNCD["koharuNativeArtifactContractDryRunReport<br/>four-file contract dry-run / sourceImageSHA256 / App-side identity receipt / validator commands"]
  KNCD --> KIR["koharuArtifactIdentityReconciliationReport<br/>App receipt -> CI manifest identity field paths / source image SHA match / size-SHA ledger"]
  EMP -.-> KAC
  KIR --> KAC["koharuArtifactConvergenceReport<br/>artifact convergence matrix / mask pixel + linkage + identity reconciliation + external shadow coverage + orientation gates"]
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
  KNCD --> R
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
  KNCD --> T
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
  B2 --> B3["集中 push 候选核心 commit<br/>codeb/... / 不合并 main"]

  %% 云端验证和结果包
  B3 --> GF["Task-scoped full（一次）<br/>基础静态 + 相关领域契约 + 必要 Xcode build"]
  GF --> RCP["full-validation status<br/>绑定候选 SHA"]
  RCP --> B4["创建 PR<br/>base=smalldata_test / head=codeb/..."]
  B4 --> GFAST["PR fast follow-up<br/>opened / reopened / ready<br/>不监听 synchronize"]
  G0["workflow_dispatch<br/>full / fast / ci-fast / UI evidence"] --> G1["GitHub Actions task router"]
  GF --> G1
  GFAST --> G1
  G1 --> G2["未加密 CI 结果包<br/>profile / reuse receipt / required flags / logs / manifest"]
  PKG["手动 workflow_dispatch"] --> G3["加密 IPA 打包<br/>仅软件包交付，Agent C 不以此验收"]

  %% Agent C 验收和文档同步
  G2 --> C1["Agent C<br/>核对 HEAD commit、diff、Actions 结论、日志和 artifact"]
  C1 --> CFail{"是否通过"}
  CFail -- "失败" --> R["退回清单<br/>B 修复 push 后重新跑对应 full"]
  R --> B1
  CFail -- "通过" --> C2["更新核心文档<br/>flow.md / flowchart.md / update_log.md"]
  C2 --> C3["PR merge 到 smalldata_test<br/>禁止合并到 main"]
  C3 --> MR{"第二父 SHA<br/>full status = success?"}
  MR -- "是" --> MF["merge fast follow-up<br/>不重复 Xcode / 大契约 / 截图<br/>传播 full receipt 到 merge SHA"]
  MR -- "否" --> MFULL["自动回退 task-scoped full"]
  MF --> C4
  MFULL --> C4
  C4["删除远端 codeb/...<br/>避免候选分支堆积"]
  C4 -. "后续 smalldata_test 纯元数据 push" .-> DM{"父 propagated receipt<br/>是否为 success?"}
  DM -- "是" --> DFAST["fast follow-up<br/>记录父 receipt / 非新编译证据"]
  DM -- "否" --> DFULL["full + 当前 HEAD Xcode build"]

  %% 回到人工
  C4 --> H2["人工复核<br/>确认后进入下一轮"]
  DFAST --> H2
  DFULL --> H2
  H2 --> H
```
