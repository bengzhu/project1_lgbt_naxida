# 合同目录与测试分层

> 状态：current。版本合同数量较大，使用稳定 glob + 主题前缀路由，不逐篇复制历史内容。

## 快速定位

| 合同/入口 | 路径 | 覆盖对象 |
| --- | --- | --- |
| 全部版本 Python 合同 | [`scripts/test-v*.py`](../../../scripts/) | 416 个当前 tracked 合同；文件名中的 `vX...` 是历史/边界主题，不代表都要重跑 |
| 非版本 Speech 合同 | [`scripts/test-speech-*.py`](../../../scripts/) | Speech 接线、质量 evaluator |
| Python evaluator | [`scripts/evaluate-*.py`](../../../scripts/) | benchmark/corpus/report schema 语义 |
| Swift harness/evaluator | [`scripts/fixtures/`](../../../scripts/fixtures/) 与 `scripts/*evaluator.swift` | 需要编译/运行的 runtime evidence；默认云端 |
| shell smoke/runtime | [`scripts/run-*.sh`](../../../scripts/) 与 `scripts/test-*-runtime.sh` | 云端模型、Core ML、App 或外部依赖路径 |
| 版本/指标工具 | [`scripts/resolve-project-version.py`](../../../scripts/resolve-project-version.py)、[`scripts/append-version-metrics.py`](../../../scripts/append-version-metrics.py) | 工程版本和 metrics 记录 |
| UI/结果工具 | [`scripts/capture-ui-evidence.sh`](../../../scripts/capture-ui-evidence.sh)、[`scripts/capture-bundled-image-translation-ui.sh`](../../../scripts/capture-bundled-image-translation-ui.sh)、[`scripts/export-probe-output.sh`](../../../scripts/export-probe-output.sh) | 云端截图/结果包导出 |

## 按模块路由合同

- 图片 UI/Store：`test-v3*image-*`、`test-v31*image-*`、`test-v32*image-*`、`test-v39*image-*`。
- 独立 OCR 检测页：`scripts/test-v3390-image-ocr-detection-ui-contract.py`，覆盖 tab/输入/语言版式/overlay/复查/导出/诊断以及 test2 v3388 overlay 别名。
- 日语 OCR/geometry：`test-v3156*`–`test-v3279*`、`test-v3295*`、`test-v3305*`–`test-v361*` 中的 `japanese`/`ocr`/`layout`。
- 翻译/context/QA：`test-v3286*`–`test-v3299*`、`test-v3300*`–`test-v380*` 中的 `translation`/`context`/`gguf`。
- Koharu/artifact/探针：`test-v32*`、`test-v19*`、`test-v20*` 及 `koharu`/`manga`/`artifact` 命名合同；真实外部 artifact 只走 cloud-only gate。
- Speech：`scripts/test-speech-quality-contract.py`、`scripts/test-speech-recognition-contract.py`、`scripts/test-speech-quality-evaluator.swift`、`scripts/validate-speech-corpus.py`。
- benchmark/schema：`scripts/test-v3280-japanese-benchmark-contract.py`、`scripts/test-v3282*`–`test-v3294*` 以及 `scripts/evaluate-japanese-*.py`。

## 测试选择规则

1. 先按 `git diff --name-only <base>...HEAD` 选择直接覆盖修改符号的合同，再跑 `git diff --check`；不自动跑全部历史合同。
2. Swift/Xcode 工程、App 资源或 target 变更，在云端保留基础 simulator build；跨公共协议/状态时只加一个最近的边界合同。
3. 出现 Core ML/llama.cpp/runtime 运行入口时默认交给 GitHub Actions；本机只做安全预扫和文本/语法检查。
4. `test/2.png`、UI 截图、Koharu/GGUF、授权语料和目标设备属于显式可选证据，不随普通代码变更自动运行。
5. 失败后按 failure summary 重跑修复集合；不以旧 artifact 或 fast 包替代当前 SHA 的 full evidence。

## 何时更新本索引

新增合同命名域、测试层、runtime harness 入口或静态跳过规则时更新；单个合同内容变化通常不改索引。
