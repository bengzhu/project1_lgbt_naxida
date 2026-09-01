# 术语、context 与输出 QA

> 状态：current。主题是 prompt 上下文和模型输出的资格判断，不拥有模型推理。

## 快速定位

| 任务/符号 | 文件路径 | 关键入口 |
| --- | --- | --- |
| 翻译种类与输出上限 | [`AITRANS/Models/TranslationContextQuality.swift`](../../../AITRANS/Models/TranslationContextQuality.swift) | `TranslationTextKind`、`defaultMaximumOutputCharacters` |
| 日语类型推断 | 同上 | `TranslationTextKindClassifier.inferJapaneseKind(...)` |
| 术语记忆 | 同上 | `TranslationTermMemoryEntry`、`TranslationTermStatus` |
| 只读 batch context | 同上 | `TranslationReadOnlyBatchItem`、`TranslationPromptContext` |
| context scope | 同上 | `bound(...)`、`normalized(...)`、`scopedToSingleBlock(...)`、`promptSection()` |
| 输出 policy/QA | 同上 | `TranslationOutputPolicy`、`TranslationBatchQualityEvaluator` |
| service 清洗接线 | [`AITRANS/Services/GemmaLocalService.swift`](../../../AITRANS/Services/GemmaLocalService.swift) | `cleanTranslationOutput`、`cleanMangaBlockOutput`、`cleanJapaneseRawCompletionOutput` |

## QA 数据流

```text
source blocks + approved terms + completed read-only context
  -> bounded prompt section
  -> model output
  -> tag/parser + language/source leakage + numeric/term/length checks
  -> TranslationBatchQualityReport
  -> Store commits only accepted block output
```

普通逐块翻译和漫画 `[N]` batch 共享底层 policy helper，但 scope 不相同：普通 block context 不能读取未来/未完成结果；batch tag 必须一对一、顺序稳定；失败块可以在 Store 中重试，但失败输出不能污染下一批 context。

## 权威边界与禁止路径

- 术语条目的 status、scope、language pair 和 canonical form 必须在 `TranslationPromptContext` 过滤后才进入 prompt；revoked/不匹配条目只保留审计，不参与生成。
- context 是只读完成结果的 bounded projection，不是 sampler memory，也不能成为持久化的隐式翻译状态。
- `TranslationBatchQualityEvaluator` 的报告是提交前门控；不能通过放宽标签、目标语言密度或源文泄漏检查来掩盖模型错误。
- shared-Han 日语→中文是显式边界；仅因输出与源文相似不能自动判定成功，必须遵守当前 policy。

## 相关测试与验证路由

- `scripts/test-v3287-japanese-translation-model-comparison-contract.py`、[`test-v3288-japanese-translation-context-qa-contract.py`](../../../scripts/test-v3288-japanese-translation-context-qa-contract.py)：benchmark/context QA。
- `scripts/test-v336*`–`scripts/test-v380*`：术语、context、类型、标签、目标语言、metadata 和逐块 QA 合同；当前 v3.389 prompt 合同见 [`test-v3389-japanese-few-shot-translation-contract.py`](../../../scripts/test-v3389-japanese-few-shot-translation-contract.py)。
- [`benchmarks/japanese_translation/`](../../../benchmarks/japanese_translation/)：schema、fixture、模型比较和 context QA 输入。

## 何时更新本索引

增加/修改 term memory、context scope、text kind、QA failure category、标签格式、语言/数字/长度门控或持久化边界时更新，并核对 Store 的逐块提交路径。
