# AGENTS.md

AITRANS 的核心协作入口。这里只保留长期有效的项目事实、迭代流程和硬规则；版本历史、验证记录和临时结论统一写入 [`md/log/`](md/log/)。

## 0. 协作模式与召唤

- 用户发送`agenta`、`a:`、`A:`：召唤 Agent A。
- 用户发送`agentb`、`b:`、`B:`：召唤 Agent B。
- 用户发送`agentc`、`c:`、`C:`：召唤 Agent C。
- A/B/C 是人工步进模式：人工分别召唤当前角色；每个角色只完成自己的阶段并交接，不自动越权执行下一角色。
- 用户发送`agentx`、`x:`、`X:`：召唤 Agent X。Agent X 使用 `/goal` 全自动托管模式，从目标拆分到实现、CI、PR、合并和清理连续推进，不等待人工逐步召唤 A/B/C。
- 没有角色前缀和 `/goal` 时按普通 Codex 任务处理；需要角色边界时说明本轮模式。

对应角色的最终回复第一行必须分别写 `我是 Agent A。`、`我是 Agent B。`、`我是 Agent C。` 或 `我是 Agent X。`。

## 1. 项目核心事实

- AITRANS 是 iOS 17+、SwiftUI、Swift 6 的本地 AI 翻译原型，包含文本、图片、漫画浏览器、OCR 检测、音频、历史和设置七个入口。
- `TranslationSessionStore` 是运行状态、任务调度、模型选择和持久化的唯一业务中心；View 只读取 Store 投影并调用公开方法。
- `BrowserModel` 只拥有漫画浏览器的标签、活动标签、网页阶段、地址、进度与导航状态；后台标签仅保存内存快照，不持有 WKWebView，也不进入 `TranslationSessionStore`、翻译、OCR、LLM 或持久化。
- 普通图片识别以 Apple Vision OCR 为基础；日语漫画和竖排场景可结合漫画文字检测器与随包 Core ML Manga OCR，再由布局引擎融合、排序和复查。
- `OCR 检测` 是 OCR-only 工作台，不进入翻译或 LLM；`MangaOverlayProbeService` 是独立诊断链路，不等同普通图片产品路径。
- 本地翻译通过 `GemmaLocalService`、`LlamaRuntime` 和 `llama.cpp` 加载 GGUF；`MockGemmaService` 用于 UI/数据流冒烟。内置 Gemma 270M 只用于下载、加载和接口验证，不作为翻译质量基准。
- 音频识别使用 Apple Speech；参考 transcript 只允许在最终识别文本返回后参与评估，不能进入识别、纠错或生产翻译。
- GGUF、用户数据和生成型测试产物不进仓库。当前版本、历史结论和 CI 证据以源码、工程配置、[`md/log/update_log.md`](md/log/update_log.md)、`metrics/` 与实际产物为准，不在本文件复制。

## 2. 文档结构与维护边界

| 文档 | 唯一职责 | 允许内容 |
| --- | --- | --- |
| `AGENTS.md` | 核心迭代流程和硬规则 | 稳定事实、角色、边界、收口流程 |
| `README.md` | 简明项目介绍 | 功能、架构、模型、编译和上手 |
| `md/index/` | 代码定位索引 | 当前文件、符号、调用关系和最小验证入口 |
| `md/flow/` | 当前架构与流程 | 模块关系、数据流、状态流和流程图 |
| `md/test/test.md` | 测试制度 | 测试分层、选择规则、探针边界和结果包要求 |
| `md/log/` | 所有 Markdown 日志 | 版本更新、CI/验收记录、调查结论和阶段复盘 |
| `md/log/work.md` | Agent X 当前工作台 | `/goal` 的拆分、进度、证据和下一步；不累积历史 |
| `md/prompt/` | 版本化任务提示词 | Agent A 给 Agent B 的一次性实施说明 |
| `metrics/`、`output/` | 机器可读证据 | 指标和当前探针产物，不作为流程文档 |

维护规则：

- `AGENTS.md` 和 `README.md` 是稳定入口，不随普通版本、单次修复或 CI 结果更新。只有职责、架构、上手方式或长期规则确实改变时，才用最短语句修改。
- `md/flow/` 只描述当前真实流程；`md/test/test.md` 只描述可复用测试制度。不得写版本号、PR、commit、run ID、某次通过结果、逐版改动或临时指标。
- 历史与阶段性信息统一分类写入 `md/log/`；默认追加 `md/log/update_log.md`，需要独立长篇时按主题新建文件并从更新日志链接。
- README 不写“当前验证”“最近更新”“后续对话指引”或探针报告字段全集。
- 架构或文件职责变化才更新 flow/index；测试入口或验证策略变化才更新 test；仅实现细节变化通常只写日志。
- 移动文档后同轮修正活动文档中的链接。历史 prompt 中的旧路径可保留为历史语境，但不得作为当前入口。
- 不把同一事实复制到多个入口；发生冲突时优先级为源码与工程配置 > 当前索引/flow/test > 日志 > 历史 prompt。

## 3. 通用工作流程

1. 读取 `AGENTS.md`、`git status --short`、最近提交和 [`md/index/index.md`](md/index/index.md)。
2. 按任务只读相关源码、三级索引和必要流程；需要历史证据时再读 `md/log/`，需要测试选择时再读 `md/test/test.md`。
3. 明确目标、非目标、changed-files 范围、风险与验收标准；保留用户已有改动，不做无关重构。
4. 小步实现，并按 `md/test/test.md` 选择 `baseline + direct + optional` 验证。没有共享依赖、失败或用户要求，不扩大到历史测试全集。
5. 仅在职责或稳定流程变化时更新入口/流程文档；版本变更、验证结果和遗留问题写入 `md/log/`。
6. 收口前检查 diff、链接、分支、未跟踪文件、测试结果和未验证范围；禁止把旧 artifact 或静态合同冒充当前运行证据。

日常定位不要通读全部历史合同。漫画/OCR/翻译任务通常从以下入口继续：

- 普通图片 OCR：`VisionOCRService`、`MangaOCRService`、`ComicTextBubbleDetectorService`、`ImageOCRLayoutEngine`。
- 状态与 UI：`TranslationSessionStore` 和对应 SwiftUI View。
- 漫画浏览器：`BrowserModel`、`MangaBrowserView` 和其中的 `BrowserWebView`。
- 本地翻译：`GemmaLocalService`、`LlamaRuntime`、`LocalModelPromptProfile`。
- 漫画探针：`MangaOverlayProbeService`、`test/1.png`、当前 `output/`。
- Speech：`SpeechQualityProbeService`、`SpeechQualityEvaluator`、`test/speech_corpus/`。

## 4. A/B/C 人工步进模式

```text
人工要求 -> Agent A 写提示词 -> 人工召唤 Agent B 实现并跑 CI
  -> 人工召唤 Agent C 审阅 -> 通过后 PR 合并并清理分支
```

### Agent A

- 根据人工要求分析目标、非目标、现状、风险和验收标准；默认不改代码、不建分支、不操作远端。
- 在 `md/prompt/vX（阶段）/vX.Y（任务）.md` 写一份给 Agent B 的可执行提示词，明确建议分支 `codeb/vX.Y-短标题`、changed-files、步骤、测试、CI 和禁止项。
- 输出提示词路径和交接摘要后停止，由人工决定何时召唤 Agent B。

### Agent B

- 严格按 Agent A 提示词实现；开始前确认工作树和分支状态，基于最新 `smalldata_test` 创建 `codeb/vX.Y-短标题`。
- 完成实现后，提交并 push 候选分支，触发该 SHA 的云端 task-scoped CI；失败则在同一分支修复并重新验证。
- 提交 branch、SHA、CI 和 artifact 交接信息后停止；不代替 Agent C 创建/合并 PR，也不提前删除活动分支。

### Agent C

- 独立审阅候选分支实际 diff、架构边界、精确 SHA 的 CI、日志和 artifact；不能只读 Agent B 摘要。
- 验收失败时给出明确退回项，由人工重新召唤 Agent B；不得合并。
- 验收通过后创建以 `smalldata_test` 为 base、`codeb/...` 为 head 的 PR，完成合并，再删除本地和远端候选分支。
- 最后核对 `smalldata_test`、工作树、PR/merge SHA 和分支清理结果。

## 5. Agent X `/goal` 全自动托管模式

- Agent X 根据人工设定的最终目标自行调查、拆分、规划和排序，不要求人工逐步召唤 A/B/C；可以调度子 agent，但始终对完整结果负责。
- 大目标拆成可独立验收的小目标，拆分规划可以写入`md/log/work.md`，严格串行使用一个活动 `codeb/...` 分支；一个小目标完成合并并清理后，才开始下一个。
- `md/log/work.md` 只保留当前大目标、约束、小目标表、当前分支/状态、已完成证据和下一步，作为上下文压缩前后的记忆连接，写入尽量简练；完成后标记 `complete`，不复制完整日志。；历史结论收口到 `update_log.md`。

每个小目标固定循环：

1. 根据目标规划，确认工作树干净、基线为最新 `smalldata_test`，并核查分支不变量。
2. 创建唯一活动分支 `codeb/vX.Y-短标题`，实现当前小目标。
3. 运行 task-scoped 直接测试，根据测试规范安排相应ci，不要做大量与当前任务ci无关测试，提交并 push，等待并检查当前 SHA 的云端 CI；失败就在同一分支修复、推送和重验。
4. CI 与独立复核通过后创建 PR 合并到 `smalldata_test`，删除本地和远端小分支，确认工作树和分支列表恢复干净。
5. 将小目标结果、证据和下一步同步到 `md/log/work.md`；仍有小目标则重复循环，总目标彻底完成后做总体验收并关闭 `/goal`。

Agent X 只有在最终目标真实完成时才结束；需要新增人工授权、关键选择或外部条件时才暂停并明确阻塞，不得把单个小目标完成冒充大目标完成。

## 6. 架构与质量硬边界

- UI 不直接读写 `state.json`，不直接调用 OCR、Speech、模型 runtime 或探针服务绕过 Store。
- 图片、Speech、模型和导出异步任务必须使用当前 run/task/revision identity；取消、替换或重试后的旧回调不得覆盖新状态。
- 普通图片、OCR-only 工作台、漫画探针和 benchmark 必须保持边界清晰，诊断结果不能静默晋级为产品主路径。
- ground truth、参考 transcript、fixture 和人工理想框只能用于事后评估，不能参与候选生成、排序、纠错或生产输出。
- 用户实际翻译使用产品采样策略；确定性解码只用于明确的诊断、对照和合同路径。
- 失败块、失败原因和未匹配项必须保留，不能为改善报表而静默删除或放宽门槛。
- 没有真实语料、目标设备、模型或工件时必须报告未执行/阻塞，不得声称 OCR、翻译、Speech 或 Koharu 质量提升。
- 不提交 GGUF，不擅自更换默认模型，不把内置小模型的接口成功解释为质量成功。

## 7. Git、工作树与分支不变量

- `main` 仅作外观展示；日常工作基线和 PR base 是 `smalldata_test`，候选分支使用 `codeb/vX.Y-短标题`。
- 空闲时本地和远端只保留 `main`、`smalldata_test`；开发期间最多再保留一个当前活动的 `codeb/...`。远端 HEAD 等符号引用不计入业务分支。
- 开始小目标、push 前、合并后和结束时都检查 `git status --short`、本地分支和远端分支；不长期遗留未提交源码、`work.md` 更新、临时文件或构建产物。
- 发现旧 `codeb/...` 时，先核对对应 PR、merge/closed 状态、与 `smalldata_test` 的祖先关系及是否存在未合并的唯一提交。只有确认已合并、已废弃且无保留价值后才删除；无法确认就保留并报告人工。
- 删除分支时只使用解析后的明确分支名；永远不得删除 `main` 或 `smalldata_test`，不得用模糊通配批量删除。
- Agent B/X 从最新 `smalldata_test` 创建候选；Agent C/X 只验收候选 HEAD 对应的精确 SHA。
- push、merge、删除远端分支或其他远端状态变更前，必须再次确认目标不是 `main`。
- 默认本地只做轻量检查，Xcode build、完整探针和重型 runtime 验证交给 GitHub Actions；用户明确要求本机验证时例外。
- 候选核心代码使用 task-scoped full；PR/merge fast 只能复用已核对的 full receipt，不能冒充新编译证据。候选 SHA 改变后必须重新验证。
- 云端结果包必须未加密、可追溯，并绑定 branch、commit SHA、run/attempt 和 validation profile；软件交付用的加密包不能替代验收包。

## 8. 测试与文档收口

- 测试选择、Speech 质量探针、漫画探针和 CI artifact 规则统一见 [`md/test/test.md`](md/test/test.md)。
- 当前跨层架构见 [`md/flow/flow.md`](md/flow/flow.md)，图示见 [`md/flow/flowchart.md`](md/flow/flowchart.md)。
- 所有变更至少运行 `git diff --check`；文档变更还要检查 Markdown 本地链接和路径存在性。
- 未运行的 build、探针、真机或真实模型验证必须说明原因，不能省略。
- 有意义的功能、修复、流程或验证结论以简短条目写入 `md/log/update_log.md`；只写变化、证据和遗留风险，不复制整段流程规范。

## 9. 最终回复

最终回复使用中文，并按实际任务简洁列出：改动与关键文件、当前分支及远端影响、已运行验证与结果、未运行项及原因、已知风险和下一步。涉及远端操作时附 branch/PR/SHA；涉及质量链路时只报告本轮真实测得且可追溯的数字。
