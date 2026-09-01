# 翻译运行时、prompt 与模型文件

> 状态：current。主题是从 `ModelGenerationRequest` 到本地模型输出的执行边界。

## 快速定位

| 任务/符号 | 文件路径 | 关键入口 |
| --- | --- | --- |
| service 调度/翻译分流 | [`AITRANS/Services/GemmaLocalService.swift`](../../../AITRANS/Services/GemmaLocalService.swift) | `generate(request:)`、`generateTranslation(for:)`、`generateMangaBlockTranslation(for:)` |
| 普通 translation candidates | 同上 | `translationMessages(for:)`、`translationPromptBodies(for:)` |
| v3.389 raw fallback | 同上 | `japaneseRawCompletionPrompt(for:)`、`cleanJapaneseRawCompletionOutput(...)` |
| llama.cpp context/sampler | [`AITRANS/Services/LlamaRuntime.swift`](../../../AITRANS/Services/LlamaRuntime.swift) | `generate(messages:fallbackProfile:maxTokens:...)`、`generateRaw(...)` |
| chat template profile | [`AITRANS/Models/LocalModelPromptProfile.swift`](../../../AITRANS/Models/LocalModelPromptProfile.swift) | `renderPrompt`/`fallbackPrompt` 相关方法 |
| 模型下载/校验状态 | [`AITRANS/Services/LocalModelDownloadService.swift`](../../../AITRANS/Services/LocalModelDownloadService.swift)、[`AITRANS/Models/TranscriptModels.swift`](../../../AITRANS/Models/TranscriptModels.swift) | `ModelDownloadProgress`、`BuiltInLocalModel` |

## 执行流

```text
TranslationSessionStore
  -> LocalLanguageModeling request
  -> GemmaLocalService
     -> chat messages + approved fallback profile
     -> LlamaRuntime / llama.cpp
     -> cleanTranslationOutput / batch parser / QA
  -> Store commits translation or failure
```

当前普通日语 translation 顺序是：pair-specific few-shot chat candidates → 既有 chat candidates → 最后才是窄范围 raw completion。raw 路径只接受单行，并拒绝语言标签和 metadata marker；这是一条失败可收束的 fallback，不是新的质量证明。

漫画批量路径保留 `[N]` 标签和 bounded generation（当前 runtime context 约束下的 token budget）；不要把普通逐块 raw fallback 直接接到漫画 batch。

## 权威边界与禁止路径

- `LlamaRuntime` 负责线程安全的模型/context/sampler 和 chat rendering；Store 不直接调用 llama.cpp。
- 模型缺失、chat template 不支持、prompt 超长、tokenization/decode 失败都应留在 service error boundary；不得伪造翻译成功。
- `ModelDecodingProfile.sampled` 用于实际翻译；deterministic 仅给诊断/benchmark/合同路径，不能改变生产输出 policy。
- GGUF 是用户设备本地文件，下载服务负责 source/size/SHA 校验；不要把模型写入仓库或把测试模型当生产资源。

## 相关测试与验证路由

- [`test-v3286-local-gguf-chat-template-contract.py`](../../../scripts/test-v3286-local-gguf-chat-template-contract.py) 与 runtime：chat template/fallback profile。
- `scripts/test-v3383*`–`scripts/test-v3389*`：普通日语 prompt/raw/few-shot 边界；当前 v3.389 合同是 [`test-v3389-japanese-few-shot-translation-contract.py`](../../../scripts/test-v3389-japanese-few-shot-translation-contract.py)。
- [`test-v3236-image-japanese-koharu-tolerant-batch-translation-contract.py`](../../../scripts/test-v3236-image-japanese-koharu-tolerant-batch-translation-contract.py)：漫画 batch 容错边界。
- 涉及 GGUF/llama.cpp 的真实运行按 [`CI profile`](../index-validation/index-validation-ci.md) 交给云端；本机不默认下载/运行模型。

## 何时更新本索引

改变模型路径/identity、context 长度、chat template、采样 profile、candidate 顺序、raw fallback 或 batch token budget 时更新，并同步翻译 QA 索引和对应合同。
