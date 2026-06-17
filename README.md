# AITRANS iOS Prototype

这是一个基于 SwiftUI 的 iOS 本地 AI 翻译原型。默认使用 `MockGemmaService` 做界面和数据流冒烟；切换到 `Local` 并导入 GGUF 后，App 会通过 `llama.cpp` 加载本地模型生成翻译或总结。

## 运行

1. 用 Xcode 打开 `AITRANS.xcodeproj`。
2. 选择 iPhone 模拟器或已连接的 iPhone。
3. 运行 `AITRANS` target。

如果命令行构建提示当前开发目录不是完整 Xcode，可以临时这样构建：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

当前仓库暂时没有把 `Assets.xcassets` 放进 target 的 Resources build phase；图标资源仍保留在项目目录中。需要 App 图标时，可以在 Xcode 里把 `Assets.xcassets` 加回 `Copy Bundle Resources`，并设置 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`。

## 当前界面

- `工作台`：主界面是一个简洁翻译框，输入文字后点击 `翻译`，会使用当前提示词和 Mock/Local 模型接口生成译文；默认免费目标语言为中文和英语。
- `历史`：查看和搜索本地会话记录，打开历史会话会回到工作台并恢复对应转录、摘要、语言、提示词和模型设置；也可以通过系统文件面板导出/导入 JSON 或清空历史。
- `提示词`：选择内置提示词，新增自定义提示词，复制或编辑自定义提示词。
- `模型`：切换 `Mock` / `Local` 引擎，查看模型目录，导入或移除本地 GGUF 文件，运行自检，单独运行 LLM 接口自测，调整 temperature 和 max tokens，查看真实模型接入接口说明。

## Pro / 内购占位

当前没有接入真实 StoreKit 购买，`开通 Pro` 是开发测试开关，后续可替换为 StoreKit 2 商品状态：

- 预留商品 ID：`com.local.aitrans.pro.monthly`。
- 免费：中文、英语文本翻译。
- Pro：解锁日语、法语、德语目标语言。
- Pro：解锁同声传译入口。同声传译仍走本地模型翻译；语音识别侧使用 Apple Speech 框架检测 `supportsOnDeviceRecognition`，可用时后续可在 `SFSpeechRecognitionRequest` 上设置 `requiresOnDeviceRecognition` 强制本地识别。支持情况取决于设备、系统和语言包。
- Pro：音频文件断网识别测试入口。选择音频后，App 会复制到沙盒，用 `SFSpeechURLRecognitionRequest` 和 `requiresOnDeviceRecognition = true` 做 Apple 本机识别，成功后自动交给当前大模型翻译。
- Pro：后台一键翻译入口已做开发占位。iOS 普通 App 不能像 Android 一样常驻覆盖其他 App 的任意悬浮窗；可行路线是 Share Extension 处理截图/文本，或 ReplayKit Broadcast Upload Extension 在用户显式启动屏幕广播后处理屏幕帧。
- Pro：图片翻译已接入开发版流程。选择图片后，App 使用 Apple Vision `VNRecognizeTextRequest` 本机 OCR 得到文字块和 `boundingBox`，逐块交给当前本地模型翻译，并在图片预览上提供“旁贴”和“覆盖”两种定位展示模式。

## 离线 OCR / 屏幕翻译方案

当前结论基于 Xcode 26.5 SDK 头文件能力：

- 图片翻译不一定需要额外 OCR 模型。Apple Vision 提供 `VNRecognizeTextRequest`，能返回 `VNRecognizedTextObservation`，包含识别文本和位置框；这适合断网本机 OCR。
- 当前图片翻译流水线是：图片输入 -> Vision OCR 得到文字块和 `boundingBox` -> 按行/块送入本地 Gemma 翻译 -> 在图片预览层按原坐标旁贴译文，或用半透明译文块覆盖原文区域。
- 如果后续需要更强的漫画/竖排/复杂版面能力，可以增加本地 OCR/版面分析模型，但第一版优先用 Vision，减少模型体积和部署风险。
- 后台一键屏幕翻译不能依赖普通 App 悬浮窗覆盖全系统页面。iOS 可考虑两条合规路线：用户分享截图到 App/Share Extension；或用 ReplayKit Broadcast Upload Extension 获取屏幕帧，再在扩展或主 App 协作里跑 OCR/翻译。

## 本地数据

数据保存在 App sandbox 的 Application Support 目录：

```text
Application Support/AITRANS/state.json
```

`state.json` 保存：

- 当前会话：转录行、摘要、语言、模式、提示词、模型引擎、会话时长。
- 历史记录：最多保留 60 个会话。
- 提示词模板：内置模板和用户新增模板。
- App 设置：当前引擎、语言、选中的提示词、temperature、max tokens、开发期 Pro 开关。

历史页的 `导出 JSON` 会先额外写出：

```text
Application Support/AITRANS/aitrans-export.json
```

随后会打开系统文件导出面板，方便把同一份 JSON 保存到 Files、iCloud Drive 或其他位置。

历史页的 `导入 JSON` 可以选择同结构的 `aitrans-export.json` 或 `state.json`。导入时会先归档当前会话，再合并历史和提示词；内置提示词会保留，同 ID 的会话或提示词不会重复导入。

模型页的 `运行自检` 会检查：

- 本地 JSON 是否可写入并解码。
- Gemma 1.5B Mock 是否能生成非空输出。
- LLM 接口是否能收到模拟输入，并从当前适配器回传非空输出。
- Local 模式是否已经安装 GGUF 模型。

模型文件不放进仓库。模型页可以直接下载内置最小模型，也可以手动 `导入 GGUF`。内置模型固定为：

- `Gemma 3 270M IT QAT Q4_0`
- 下载地址：[`ggml-org/gemma-3-270m-it-qat-GGUF`](https://huggingface.co/ggml-org/gemma-3-270m-it-qat-GGUF)
- 文件：`gemma-3-270m-it-qat-Q4_0.gguf`
- 大小：`241,410,624 bytes`，约 230 MB
- SHA256：`3626e245220ca4a1c5911eb4010b3ecb7bdbf5bc53c79403c21355354d1e2dc6`

App 下载时会写入临时 `model.gguf.download`，成功校验后原子替换为 `model.gguf`。同名模型只保留一个；如果已安装，点击下载不会重复保存。`移除模型` 会删除 `model.gguf` 和未完成的临时下载文件。

无论内置下载还是手动导入，模型都会复制到 App 沙盒内并统一命名为：

```text
Application Support/Models/Gemma-1.5B/model.gguf
```

如果没有这个文件，界面会显示 Local 未就绪。普通翻译会临时回退 Mock，避免界面卡死；LLM 接口自测和诊断会明确提示缺少模型。`移除模型` 只删除 App 沙盒中的 `model.gguf` 和临时下载，不影响原始文件或远程模型。

## 本地 LLM 模型准备

当前项目先按 `llama.cpp + GGUF` 方向接入。原因是 `llama.cpp` 官方仓库带有 `examples/llama.swiftui`，说明它是一个在 iPhone 上运行本地推理的 SwiftUI 示例；而本项目的模型导入器已经限制 `.gguf` 文件。MLC LLM 的 iOS 路线也可行，但它需要 `mlc_llm package` 生成 runtime、tokenizer 和已转换/编译的 MLC 权重，不是直接导入 `.gguf`。

先下载其中一个 `.gguf` 到 Mac：

- 首推翻译冒烟：[`Qwen/Qwen2.5-0.5B-Instruct-GGUF`](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF)，文件选 `qwen2.5-0.5b-instruct-q4_k_m.gguf`，约 469 MB。体积仍小，中文/英文测试更稳。
- 极小体积冒烟：[`unsloth/SmolLM2-135M-Instruct-GGUF`](https://huggingface.co/unsloth/SmolLM2-135M-Instruct-GGUF)，文件选 `SmolLM2-135M-Instruct-Q4_K_M.gguf`，约 101 MB。适合测加载和接口，不适合判断翻译质量。
- 最小 Gemma 路线：[`ggml-org/gemma-3-270m-it-qat-GGUF`](https://huggingface.co/ggml-org/gemma-3-270m-it-qat-GGUF)，文件选 `gemma-3-270m-it-qat-Q4_0.gguf`，约 230 MB；或 [`ggml-org/gemma-3-270m-it-GGUF`](https://huggingface.co/ggml-org/gemma-3-270m-it-GGUF) 的 `Q8_0` 版本。

Mac 机外先测：

```sh
brew install llama.cpp

llama-cli \
  -m ~/Downloads/qwen2.5-0.5b-instruct-q4_k_m.gguf \
  -p "Translate to Simplified Chinese: Keep the model on device." \
  -n 128
```

如果想让 `llama.cpp` 直接从 Hugging Face 拉模型，也可以先试：

```sh
brew install llama.cpp
llama-cli -hf Qwen/Qwen2.5-0.5B-Instruct-GGUF:Q4_K_M \
  -p "Translate to Simplified Chinese: Keep the model on device." \
  -n 128
```

放进 App 测试时，不需要手工改名。运行 App 后进 `模型` -> `下载 Gemma`，或 `导入 GGUF` 选择下载好的 `.gguf`，App 会复制并命名为 `model.gguf`。

当前已用 `gemma-3-270m-it-qat-Q4_0.gguf` 做过命令行冒烟：

```sh
llama-cli -m llm/gemma-3-270m-it-qat-Q4_0.gguf \
  -st --no-display-prompt --no-warmup --no-perf \
  -n 80 --temp 0.1 \
  -p "Translate to Simplified Chinese. Output only the translation: Keep the model on device so private meeting content never leaves the phone."
```

结果：模型能正常加载并生成，速度约 130 tokens/s，但输出容易复读英文原句或 prompt，不稳定翻译成中文。因此它适合验证 GGUF 下载、加载、App 接口和闪退风险，不适合作为翻译质量测试模型。要验证翻译质量，优先换 `Qwen2.5-0.5B-Instruct-GGUF` 的 `q4_k_m` 文件。

如果本地需要重建 iOS `llama.xcframework`：

```sh
git clone --depth 1 https://github.com/ggml-org/llama.cpp.git third_party/llama.cpp
bash Tools/build-llama-ios-xcframework.sh
```

## 大模型接入点

- `AITRANS/Models/TranscriptModels.swift`
  - `LocalLanguageModeling` 是统一模型协议。
  - `ModelGenerationRequest` 包含任务类型、语言、提示词、上下文和采样参数。
  - `ModelGenerationResult` 返回文本、摘要、引擎名、token 数和耗时。
  - `ModelStreamEvent` 和 `LocalLanguageModeling.stream(_:)` 预留逐 token 流式输出接口；默认实现会把一次性生成结果包装成流式事件，真实推理层可覆写。
- `AITRANS/Services/MockGemmaService.swift`
  - 当前模拟输出，用于没有 GGUF 时测试 UI、历史和回退路径。
- `AITRANS/Services/GemmaLocalService.swift`
  - 真实本地模型层，使用 `llama.cpp` 的 `llama.xcframework` 加载沙盒中的 `model.gguf` 并生成。
- `AITRANS/Services/LlamaRuntime.swift`
  - 封装 llama.cpp C API，负责加载 GGUF、分词、逐 token 生成、UTF-8 拼接和运行时锁。
- `AITRANS/Services/TranslationSessionStore.swift`
  - 负责页面共享状态、本地 JSON 存储、导入/导出、历史清理、自检、Mock/Local 回退和生成请求组装。

真实模型替换时，优先换 `model.gguf` 或调整 `GemmaLocalService` 的 prompt/采样参数，不需要改 UI 和历史数据结构。

## 当前验证

- `plutil -lint AITRANS/Resources/Info.plist AITRANS.xcodeproj/project.pbxproj` 通过。
- `jq empty AITRANS/Resources/Assets.xcassets/.../Contents.json` 通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ... generic/platform=iOS Simulator ... CODE_SIGNING_ALLOWED=NO build` 通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ... generic/platform=iOS ... CODE_SIGNING_ALLOWED=NO build` 通过。
- 已确认 Debug iOS Simulator app bundle 内嵌 `llama.framework`。
