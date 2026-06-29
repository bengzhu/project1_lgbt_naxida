# Prompt 目录
本目录保存每轮 Agent A 写给 Agent B 的详细实现提示词。

## 命名规则
- 阶段目录：`md/prompt/v0（项目初始化）/`、`md/prompt/v1（漫画探针）/`、`md/prompt/v2（云端协作）/`。
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

## Agent 召唤约定
- 用户消息以 `agenta`、`a:` 或 `A:` 开头，表示召唤 Agent A。
- 用户消息以 `agentb`、`b:` 或 `B:` 开头，表示召唤 Agent B。
- 用户消息以 `agentc`、`c:` 或 `C:` 开头，表示召唤 Agent C。
- Agent A / B / C 最终回复第一行分别必须写 `我是 Agent A。`、`我是 Agent B。`、`我是 Agent C。`

## v2 云端协作提示词要求
- v2 阶段用于协作制度、分支流、GitHub Actions、结果包和云端验证改造，不归入漫画探针 v1 小优化。
- Agent A 写给 Agent B 的 v2 提示词必须写明分支建议：从 `smalldata_test` 开 `codeb/vX.Y-短标题`。若旧材料写 `samlldata_test`，以当前远端真实分支 `origin/smalldata_test` 为准。
- 提示词必须说明默认不跑本机 Xcode build / 漫画探针，除非人工明确要求本机测试。
- 提示词必须要求 Agent B push 分支后由 GitHub Actions 生成未加密 CI 结果包。
- 提示词必须要求 Agent C 按 `version`、`branch`、`commitSha`、`runId`、`runAttempt` 和 artifact manifest 验收，不能拿旧包或错包。
- 提示词必须区分加密软件包 artifact 与未加密 CI 结果包：action 软件包有密码时不改动，Agent C 只拿结果包。
- 若云端编译失败，提示词必须要求 workflow 保留 `xcodebuild.log`、`junit.xml`、`.xcresult`、`ci-failure-summary.md` 和 `ci-artifact-manifest.json`，由 Agent C 指明日志位置并退回 Agent B 修复。
- GGUF 云端模型依赖已知，后续通过 GitHub Release + workflow 下载 + 缓存解决；v2 提示词不得要求提交 GGUF。

## 当前项目写作要求
- 先读 `AGENTS.md`、`update_log.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`。
- 涉及漫画探针时，必须引用最新 `output/probe_report.json` 和 `metrics/version_history.csv` 的真实数字。
- 不得把旧 `0.8378 / 0.8755` 当成当前验收基线。
- 不得要求 Agent B 使用 ground truth 做生产候选选择。
- 不得把 bubble-first、确定性纠错或 batch 翻译直接切主流程，除非提示词先要求做证据收集和验收门槛。
