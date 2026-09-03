# 翻译引擎与本地模型运行时

> 状态：current。按“模型文件/运行时 → prompt 适配 → 输出 QA”划分；OCR 只提供已排序的源文本。

## 边界

本模块负责翻译引擎选择、Apple Translation 适配、本地 GGUF 下载与校验、llama.cpp 调用、chat template/fallback profile、输出清洗和批量 QA。它不拥有 OCR geometry、图片 session 状态或 Speech run 状态。

## 快速定位

| 任务/符号 | 文件 | 入口 |
| --- | --- | --- |
| Apple Translation 适配 | [`AITRANS/Services/AppleTranslationService.swift`](../../../AITRANS/Services/AppleTranslationService.swift) | `AppleTranslationService`、`generate(_:)`、`runPendingJob(with:)` |
| 系统会话宿主 | [`AITRANS/Views/AppleTranslationTaskHost.swift`](../../../AITRANS/Views/AppleTranslationTaskHost.swift) | `AppleTranslationTaskHost`、`translationTask` |
| 本地模型 service | [`AITRANS/Services/GemmaLocalService.swift`](../../../AITRANS/Services/GemmaLocalService.swift) | `GemmaLocalService`、`generate(request:)` |
| llama.cpp 封装 | [`AITRANS/Services/LlamaRuntime.swift`](../../../AITRANS/Services/LlamaRuntime.swift) | `loadModelIfNeeded`、`generate`、`generateRaw` |
| GGUF 下载/安装 | [`AITRANS/Services/LocalModelDownloadService.swift`](../../../AITRANS/Services/LocalModelDownloadService.swift) | `LocalModelDownloadService` |
| prompt profile/chat fallback | [`AITRANS/Models/LocalModelPromptProfile.swift`](../../../AITRANS/Models/LocalModelPromptProfile.swift) | `LocalModelPromptProfile`、`LocalModelChatMessage` |
| 翻译种类、术语、context、QA | [`AITRANS/Models/TranslationContextQuality.swift`](../../../AITRANS/Models/TranslationContextQuality.swift) | `TranslationPromptContext`、`TranslationBatchQualityEvaluator` |
| 非模型 UI/contract mock | [`AITRANS/Services/MockGemmaService.swift`](../../../AITRANS/Services/MockGemmaService.swift) | `MockGemmaService` |

## 相关索引

- [`运行时、prompt 与模型文件`](index-translation-runtime.md)
- [`术语、context 与输出 QA`](index-translation-qa.md)
- [`Store 状态与逐块翻译生命周期`](../index-app/index-app-state.md)
- [`翻译 benchmark 与 CI`](../index-validation/index-validation-benchmarks.md)、[`CI profile`](../index-validation/index-validation-ci.md)

## 高风险边界

- `TranslationSessionStore.selectedEngine` 是文本、图片和音频后续翻译的唯一引擎权威；Apple 与 Gemma 共享 `ModelGenerationRequest` / `ModelGenerationResult` 边界，预留引擎不得静默回退。
- `MockGemmaService` 只用于 Preview/UI evidence 和 Gemma 缺失时的既有受控冒烟，不是用户可选引擎，也不可作为模型质量证据。
- Apple Translation 程序化结果必须在 iOS 18+ 真机验证；模拟器的系统拒绝只能证明路由和失败收束，不能证明语言包或译文质量。
- manga `[N]` 批量翻译和普通文本/图片逐块翻译是不同 profile；标签顺序、context 和 QA 不能互相放宽。
- term memory、completed-only cross-batch context 是只读 prompt 输入；sampler state、未经批准的输出或未来批次结果不得写入 prompt。
- 翻译输出必须先通过清洗、源文泄漏、目标语言、数字/术语、标签、长度和逐块 QA，才能进入 Store。

## 何时更新本索引

新增模型引擎、prompt profile、chat/raw fallback、输出 policy、context 字段、QA gate 或 batch boundary 时更新；只改模型管理页面转到应用 UI 索引。
