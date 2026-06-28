# AGENT.md
本文是 AITRANS 的入口记忆、总览、基本规则和多 Agent 迭代工作流。详细漫画探针约束仍以 `AGENTS.md` 为准。

## 1. 项目总览
AITRANS 是 SwiftUI iOS 本地 AI 翻译原型，当前主线是漫画截图 OCR、本地翻译、覆盖合成和可复现探针诊断。

## 2. 必读文件
每轮开始按顺序读取：

1. `README.md`
2. `AGENTS.md`
3. `git status --short`
4. `git log --oneline -5`
5. `update_log.md`
6. `md/flow/flow.md`
7. `md/flow/flowchart.md`
8. `md/test/test.md`

涉及漫画探针、OCR、覆盖绘制、翻译质量或诊断报告时，继续读取：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `test/1.ground_truth.json`
- `output/probe_report.json`
- `output/clean_text_diagnostic.json`
- `output/1_ocr_probe_text.txt`

## 3. 项目基本规则
- 以当前代码、最新 `output/probe_report.json`、`metrics/version_history.csv` 和实际测试结果为准，不用旧 README 数字替代验收。
- 默认 `MockGemmaService` 只用于 UI 和数据流冒烟；Local 模式通过 `GemmaLocalService`、`LlamaRuntime` 和 GGUF 走真实本地模型。
- 当前内置 `Gemma 3 270M IT QAT Q4_0` 只适合验证下载、加载、接口和崩溃风险，不作为翻译质量基准。
- `TranslationSessionStore` 是 UI 状态、模型调用、历史、诊断和持久化的统一调度中心。
- `test/1.ground_truth.json` 只能用于探针统计和验证，不能进入生产候选选择。

## 4. 架构边界
- UI 层只通过 `TranslationSessionStore` 触发业务动作，不绕开 store 直接改持久化或模型状态。
- 普通图片 OCR 使用 `VisionOCRService`；漫画覆盖探针使用 `MangaOverlayProbeService` 的独立诊断链路。
- 用户实际翻译保持 sampled 解码；漫画探针、raw 诊断、clean text、batch 对照和纠错对照使用 deterministic 解码。
- 漫画探针失败块必须保留在报告和覆盖图中，不允许静默跳过。
- bubble-first、确定性纠错、customWords、slice OCR 和 batch translation 当前都是诊断或对照链路，未证明收益前不能替换主流程。

## 5. 标准迭代工作流
### 人工
人工提出目标、边界、禁止项、验收标准和测试要求，并把本入口文件及相关上下文交给 Agent A。

### Agent A：目标分析与提示词
Agent A 默认不写代码，负责分析目标并写给 Agent B 的实现提示词。必须读取入口文档、历史日志、核心流程、测试规范和相关源码，明确目标、非目标、风险、关键文件、测试要求和验收标准。提示词写入 `md/prompt/vX（阶段）/vX.Y（任务）.md`。

### Agent B：实现与测试
Agent B 按 Agent A 提示词小步实现，优先保留现有架构边界。必须按 `md/test/test.md` 选择测试层级，记录实际命令和结果，说明未跑测试的原因，不伪造验证。

### Agent C：验收与核心文档更新
Agent C 查看实际 diff 和测试证据，判断是否满足人工目标和 Agent A 提示词。通过后更新 `md/flow/flow.md`、`md/flow/flowchart.md`，必要时追加 `update_log.md` 和 `metrics/version_history.csv`。

## 6. 测试规则
- 文档-only 修改至少运行 `git diff --check`。
- Swift 或项目配置修改至少运行命令行 build。
- 漫画探针、翻译链路或报告模型修改必须重新跑探针、导出 `output/`、解析 JSON，并汇总关键数字。
- 读取 CoreSimulator App 容器通常需要更高权限；受限环境中必须说明未导出的原因或请求批准。

## 7. 文档规则
- `AGENT.md` 只放入口规则和工作流。
- `AGENTS.md` 保留漫画探针详细约束。
- `update_log.md` 记录版本历史、关键决策、验证和遗留问题，不写流水账。
- `md/flow/flow.md` 只描述当前真实架构和运行流程。
- `md/flow/flowchart.md` 必须与 `flow.md` 同步。
- `md/test/test.md` 是测试选择依据。
- `md/prompt/` 只保存 Agent A 的版本化实现提示词。

## 8. 交付格式
最终回复使用中文，至少包含：

- 改了什么。
- 关键文件。
- 已运行的验证命令和结果。
- 未运行的测试及原因。
- 关键探针数字，若本轮涉及漫画探针或翻译链路。
- 已知风险和建议下一步。

## 9. 禁止项
- 不要把旧 `0.8378 / 0.8755` 当作当前 OCR 验收基线。
- 不要用 ground truth 做生产候选选择。
- 不要隐藏失败块或只绘制通过块。
- 不要只看 `cjkCharacters > 0` 判定翻译成功。
- 不要把 clean text 失败归咎为 OCR 问题。
- 不要在未证明收益前把确定性纠错、bubble-first 或 batch 翻译切成主流程。
- 不要提交模型文件。
- 不要回退用户或其他 Agent 的改动。
- 不要无任务要求地大改 SwiftUI 产品界面。
