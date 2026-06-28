# Prompt 目录
本目录保存每轮 Agent A 写给 Agent B 的详细实现提示词。

## 命名规则
- 阶段目录：`md/prompt/v0（项目初始化）/`、`md/prompt/v1（漫画探针）/`、`md/prompt/v2（模型质量）/`。
- 提示词文件：`v0.1（建立迭代文档）.md`、`v1.0（主流程融合）.md`。
- 人工指定版本时按人工指定。
- 人工未指定时由 Agent A 自动判断，从 `v0.1` 开始递增。
- 同阶段小任务、修复、优化递增小版本。
- 大任务、架构阶段或重要里程碑新开大版本。

## 每份提示词必须包含
- 版本号。
- 版本分配依据。
- 背景。
- 目标。
- 非目标。
- 当前架构依据。
- 实现步骤。
- 关键文件。
- 测试要求。
- 文档更新要求。
- 验收标准。
- 风险和禁止项。

## 当前项目写作要求
- 先读 `AGENTS.md`、`update_log.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`。
- 涉及漫画探针时，必须引用最新 `output/probe_report.json` 和 `metrics/version_history.csv` 的真实数字。
- 不得把旧 `0.8378 / 0.8755` 当成当前验收基线。
- 不得要求 Agent B 使用 ground truth 做生产候选选择。
- 不得把 bubble-first、确定性纠错或 batch 翻译直接切主流程，除非提示词先要求做证据收集和验收门槛。
