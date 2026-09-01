# OCR、翻译与渲染 benchmark

> 状态：current。benchmark 是协议/证据入口；固定样本结果不自动构成产品泛化结论。

## 快速定位

| 领域 | 根目录 | 评估入口 |
| --- | --- | --- |
| 日语 OCR | [`benchmarks/japanese_ocr/README.md`](../../../benchmarks/japanese_ocr/README.md) | `schema/`、`fixtures/`、`oracle/`、`examples/`、`scripts/evaluate-japanese-ocr-*.py` |
| 日语翻译 | [`benchmarks/japanese_translation/README.md`](../../../benchmarks/japanese_translation/README.md) | `schema/`、`fixtures/`、`examples/`、`scripts/evaluate-japanese-translation-*.py` |
| 日语渲染/mask | [`benchmarks/japanese_render/README.md`](../../../benchmarks/japanese_render/README.md) | `schema/`、`examples/mask_artifacts/`、`scripts/evaluate-japanese-mask-artifact-readiness.py` |
| 固定 App 输入 | [`test/1.png`](../../../test/1.png)、[`test/2.png`](../../../test/2.png)、[`test/jap.jpg`](../../../test/jap.jpg)、[`test/1.ground_truth.json`](../../../test/1.ground_truth.json) | App/test2/Koharu smoke 输入 |
| 语音 corpus | [`test/speech_corpus/`](../../../test/speech_corpus/) | Speech quality validator |

## 协议边界

- `schema/*.json` 定义输入/报告形状；`examples/` 是可读 fixture，不是生产数据。
- OCR benchmark 需要明确 engine、source image、geometry、direction、confidence 和 quality gate；不要只用文本相似度代表 geometry 质量。
- 翻译 benchmark 需要区分 source/target、text kind、context、术语、标签、数字、源文泄漏和输出长度。
- holdout/corpus readiness 的 ground truth 只能在 benchmark/evaluator 作用域中使用，不能进入 `VisionOCRService`、`GemmaLocalService` 或生产候选选择。
- Koharu/GPL artifact 只用于云端 reference parity；缺少授权语料/真实 GGUF/目标设备时必须记录验证缺口。

## 相关 evaluator

- [`evaluate-japanese-ocr-benchmark.py`](../../../scripts/evaluate-japanese-ocr-benchmark.py)、`evaluate-japanese-ocr-line-signal.py`、`evaluate-japanese-ocr-engine-candidate.py`、`evaluate-japanese-ocr-engine-selector.py`、`evaluate-japanese-ocr-multi-engine.py`。
- [`evaluate-japanese-translation-benchmark.py`](../../../scripts/evaluate-japanese-translation-benchmark.py)、`evaluate-japanese-translation-context-qa.py`、`evaluate-japanese-translation-model-comparison.py`。
- [`evaluate-japanese-corpus-readiness.py`](../../../scripts/evaluate-japanese-corpus-readiness.py)、[`evaluate-japanese-mask-artifact-readiness.py`](../../../scripts/evaluate-japanese-mask-artifact-readiness.py)。

## 何时更新本索引

新增领域/schema、改变 holdout/ground-truth 使用边界、引入新 evaluator 或改变结果包需要保留的 benchmark 文件时更新。
