# 验证、基准与 CI

> 状态：current。按“本地静态合同 → benchmark/schema → 云端 workflow/结果包”划分；验证证据不自动等于产品质量声明。

## 边界

本模块管理 Python 静态合同、Swift runtime harness、benchmark evaluator、schema/fixture、云端 smoke 和 CI 结果包。它验证相邻模块的边界，不拥有 App 业务状态，也不把固定样本外推为通用 OCR/翻译质量。

## 快速定位

| 任务 | 文件/目录 | 入口 |
| --- | --- | --- |
| CI 分流、manifest、receipt | [`.github/workflows/ci-results.yml`](../../../.github/workflows/ci-results.yml) | `ci_scope`、`japanese_benchmark`、`ci-results`、`test2_image_translation_ui` |
| test2 UI workflow | [`.github/workflows/test2-image-translation-ui.yml`](../../../.github/workflows/test2-image-translation-ui.yml) | `test2-image-translation-ui` |
| 手动 Koharu parity | [`.github/workflows/koharu-mit48-parity.yml`](../../../.github/workflows/koharu-mit48-parity.yml) | `mit48-reference-parity` |
| IPA 构建交付 | [`.github/workflows/build.yml`](../../../.github/workflows/build.yml) | `build`、`package` |
| 静态/版本合同 | [`scripts/test-v*.py`](../../../scripts/) | 按主题合同文件名路由 |
| benchmark evaluator | [`scripts/evaluate-*.py`](../../../scripts/) | OCR/translation/corpus evaluator |
| cloud smoke | [`scripts/run-*.sh`](../../../scripts/) | 云端依赖/外部 artifact 路径 |
| 固定输入 | [`test/`](../../../test/)、[`benchmarks/`](../../../benchmarks/) | 图片、语料、schema、fixture |

## 验证层级

```text
静态合同/语法
  -> 精准 benchmark/schema evaluator
  -> task-scoped CI full（必要时 Xcode）
  -> 手动 test2 UI / Koharu / artifact evidence
```

PR fast 不是候选编译证据；只有与当前实现 SHA 完全一致的 full receipt 才能支撑合并验收。`probe_mode=skip`、artifact 缺失、`manifestMissing` 和质量 report 的 `overallPassed=false` 必须按各自语义记录，不能互相替代。

## 相关索引

- [`合同目录与测试分层`](index-validation-contracts.md)
- [`OCR/翻译/渲染 benchmark`](index-validation-benchmarks.md)
- [`CI profile、证据与未运行边界`](index-validation-ci.md)
- [`资源、target 与完整文件图`](../index-assets/index-assets.md)

## 何时更新本索引

新增测试层、workflow job、validation profile、结果包字段、artifact gate 或 benchmark schema 时更新；单个版本合同的实现细节留在合同文件和 `md/test/test.md`。
