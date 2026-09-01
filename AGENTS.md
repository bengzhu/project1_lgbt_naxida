# AGENTS.md

AITRANS 的核心协作入口。这里只保留长期有效的项目事实、迭代流程和硬规则；版本历史、验证记录和临时结论统一写入 [`md/log/`](md/log/)。

## 0. 角色召唤

- `agenta`、`a:`、`A:`：Agent A，负责分析和任务提示词。
- `agentb`、`b:`、`B:`：Agent B，负责实现和候选验证。
- `agentc`、`c:`、`C:`：Agent C，负责独立验收和收口。
- `agentx`、`x:`、`X:`：Agent X，负责大目标拆解、并发调度和循环收敛，自动循环调度 Agent A/B/C 和并发子 agent 协作推进、验证、修复与再迭代；单轮最多开启 6 个子 agent。
- 没有前缀时按普通 Codex 任务处理；若任务确实需要 A/B/C 边界，先说明本轮角色。

对应角色的最终回复第一行必须分别写 `我是 Agent A。`、`我是 Agent B。`、`我是 Agent C。` 或 `我是 Agent X。`。

## 1. 项目核心事实

- AITRANS 是 iOS 17+、SwiftUI、Swift 6 的本地 AI 翻译原型，包含文本、图片、OCR 检测、音频、历史和设置六个入口。
- `TranslationSessionStore` 是运行状态、任务调度、模型选择和持久化的唯一业务中心；View 只读取 Store 投影并调用公开方法。
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

## 3. 每轮工作流程

1. 读取 `AGENTS.md`、`git status --short`、最近提交和 [`md/index/index.md`](md/index/index.md)。
2. 按任务只读相关源码、三级索引和必要流程；需要历史证据时再读 `md/log/`，需要测试选择时再读 `md/test/test.md`。
3. 明确目标、非目标、changed-files 范围、风险与验收标准；保留用户已有改动，不做无关重构。
4. 小步实现，并按 `md/test/test.md` 选择 `baseline + direct + optional` 验证。没有共享依赖、失败或用户要求，不扩大到历史测试全集。
5. 仅在职责或稳定流程变化时更新入口/流程文档；版本变更、验证结果和遗留问题写入 `md/log/`。
6. 收口前检查 diff、链接、未跟踪文件、测试结果和未验证范围；禁止把旧 artifact 或静态合同冒充当前运行证据。

日常定位不要通读全部历史合同。漫画/OCR/翻译任务通常从以下入口继续：

- 普通图片 OCR：`VisionOCRService`、`MangaOCRService`、`ComicTextBubbleDetectorService`、`ImageOCRLayoutEngine`。
- 状态与 UI：`TranslationSessionStore` 和对应 SwiftUI View。
- 本地翻译：`GemmaLocalService`、`LlamaRuntime`、`LocalModelPromptProfile`。
- 漫画探针：`MangaOverlayProbeService`、`test/1.png`、当前 `output/`。
- Speech：`SpeechQualityProbeService`、`SpeechQualityEvaluator`、`test/speech_corpus/`。

## 4. 架构与质量硬边界

- UI 不直接读写 `state.json`，不直接调用 OCR、Speech、模型 runtime 或探针服务绕过 Store。
- 图片、Speech、模型和导出异步任务必须使用当前 run/task/revision identity；取消、替换或重试后的旧回调不得覆盖新状态。
- 普通图片、OCR-only 工作台、漫画探针和 benchmark 必须保持边界清晰，诊断结果不能静默晋级为产品主路径。
- ground truth、参考 transcript、fixture 和人工理想框只能用于事后评估，不能参与候选生成、排序、纠错或生产输出。
- 用户实际翻译使用产品采样策略；确定性解码只用于明确的诊断、对照和合同路径。
- 失败块、失败原因和未匹配项必须保留，不能为改善报表而静默删除或放宽门槛。
- 没有真实语料、目标设备、模型或工件时必须报告未执行/阻塞，不得声称 OCR、翻译、Speech 或 Koharu 质量提升。
- 不提交 GGUF，不擅自更换默认模型，不把内置小模型的接口成功解释为质量成功。

## 5. Git 与云端验证

- `main` 仅作外观展示；日常工作基线是 `smalldata_test`，候选分支使用 `codeb/vX.Y-短标题`。
- Agent B 从最新 `smalldata_test` 建候选分支，提交到以 `smalldata_test` 为 base 的 PR；Agent C 只验收候选 HEAD 对应的精确 SHA。
- push、merge、删除远端分支或其他远端状态变更前，必须再次确认目标不是 `main`。
- 候选合并或终止后清理 `codeb/...` 分支；无权限时明确说明。
- 默认本地只做轻量检查，Xcode build、完整探针和重型 runtime 验证交给 GitHub Actions；用户明确要求本机验证时例外。
- 候选核心代码使用 task-scoped full；PR/merge fast 只能复用已核对的 full receipt，不能冒充新编译证据。候选 SHA 改变后必须重新验证。
- 云端结果包必须未加密、可追溯，并绑定 branch、commit SHA、run/attempt 和 validation profile；软件交付用的加密包不能替代验收包。

## 6. Agent 职责

### Agent A

- 默认不改代码，分析目标和风险。
- 在 `md/prompt/` 生成给 Agent B 的版本化提示词，写清目标、非目标、分支、changed-files、验收标准、测试范围和禁止项。

### Agent B

- 在候选分支小步实现，不做无关重构。
- 完成直接验证并提供 branch、SHA、PR、CI、artifact 和未验证范围；失败后只修复受影响范围并重新产生当前 SHA 证据。

### Agent C

- 独立核对实际 diff、架构边界、精确 SHA 的 CI 与 artifact。
- 失败则给出可执行退回清单；通过后才允许合并到 `smalldata_test`，并完成候选分支清理和必要日志收口。

### Agent X

- 将大目标拆成可独立验证的子任务，调度 A/B/C 或子 agent，持续复核、修复和再验证，直到满足同一验收标准。

## 7. 测试与文档收口

- 测试选择、Speech 质量探针、漫画探针和 CI artifact 规则统一见 [`md/test/test.md`](md/test/test.md)。
- 当前跨层架构见 [`md/flow/flow.md`](md/flow/flow.md)，图示见 [`md/flow/flowchart.md`](md/flow/flowchart.md)。
- 所有变更至少运行 `git diff --check`；文档变更还要检查 Markdown 本地链接和路径存在性。
- 未运行的 build、探针、真机或真实模型验证必须说明原因，不能省略。
- 有意义的功能、修复、流程或验证结论以简短条目写入 `md/log/update_log.md`；只写变化、证据和遗留风险，不复制整段流程规范。

## 8. 最终回复

最终回复使用中文，并按实际任务简洁列出：改动与关键文件、当前分支及远端影响、已运行验证与结果、未运行项及原因、已知风险和下一步。涉及远端操作时附 branch/PR/SHA；涉及质量链路时只报告本轮真实测得且可追溯的数字。
