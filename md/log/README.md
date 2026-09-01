# 日志目录

`md/log/` 是 AITRANS 所有 Markdown 日志的统一目录。架构、测试和入口文档不承载版本流水账。

## 分类

- `update_log.md`：默认更新日志，按版本或主题记录变化、验证证据和遗留风险。
- 专项日志：只有单条更新无法清楚表达时才新建，例如 `ocr-investigation.md`、`release-validation.md`；在 `update_log.md` 中留下链接。

## 写法

- 每条只写：做了什么、为什么、验证了什么、还缺什么。
- commit、PR、CI run 和指标只在确实有追溯价值时记录，不复制完整控制台输出。
- 不把日志反向复制到 `AGENTS.md`、`README.md`、`md/flow/`、`md/test/test.md` 或 `md/index/`。
- 稳定架构或制度真正变化时，先精简更新对应权威文档，再在日志中记录变化。
