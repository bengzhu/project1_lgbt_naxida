# AITRANS iOS Prototype

这是一个基于 SwiftUI 的 iOS 本地 AI 翻译原型。当前版本不下载真实 Gemma 模型，默认使用 `MockGemmaService` 模拟 Gemma 1.5B 的翻译、总结和耗时输出，先用于 Xcode 测试 App 外形、页面互通、数据流和本地存储。

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

当前仓库为了在 CoreSimulator runtime 不可用的环境里完成 Xcode 构建验证，暂时没有把 `Assets.xcassets` 放进 target 的 Resources build phase；图标资源仍保留在项目目录中。你的本机 Simulator 正常后，可以在 Xcode 里把 `Assets.xcassets` 加回 `Copy Bundle Resources`，并设置 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`。

## 当前界面

- `工作台`：主界面是一个简洁翻译框，输入文字后点击 `翻译`，会使用当前提示词和 Mock/Local 模型接口生成译文；默认免费目标语言为中文和英语。
- `历史`：查看和搜索本地会话记录，打开历史会话会回到工作台并恢复对应转录、摘要、语言、提示词和模型设置；也可以通过系统文件面板导出/导入 JSON 或清空历史。
- `提示词`：选择内置提示词，新增自定义提示词，复制或编辑自定义提示词。
- `模型`：切换 `Mock` / `Local` 引擎，查看模型目录，导入或移除本地 GGUF 文件，运行自检，调整 temperature 和 max tokens，查看真实模型接入接口说明。

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
- Local 模式在未下载模型时是否按预期回退到 Mock。

模型文件不放进仓库。模型页的 `导入 GGUF` 会把你选择的 `.gguf` 文件复制到 App 沙盒内并统一命名为：

```text
Application Support/Models/Gemma-1.5B/model.gguf
```

如果没有这个文件，界面会显示 Local 未就绪，但生成会自动回退到 Mock，保证原型仍可使用。`移除模型` 只删除 App 沙盒中的 `model.gguf`，不影响原始文件。

## 大模型接入点

- `AITRANS/Models/TranscriptModels.swift`
  - `LocalLanguageModeling` 是统一模型协议。
  - `ModelGenerationRequest` 包含任务类型、语言、提示词、上下文和采样参数。
  - `ModelGenerationResult` 返回文本、摘要、引擎名、token 数和耗时。
  - `ModelStreamEvent` 和 `LocalLanguageModeling.stream(_:)` 预留逐 token 流式输出接口；默认实现会把一次性生成结果包装成流式事件，真实推理层可覆写。
- `AITRANS/Services/MockGemmaService.swift`
  - 当前模拟 Gemma 1.5B 输出。
- `AITRANS/Services/GemmaLocalService.swift`
  - 真实本地模型占位层，目前只检查 `model.gguf`，后续可以替换为 Core ML、llama.cpp/gguf 或 MediaPipe LLM Inference。
- `AITRANS/Services/TranslationSessionStore.swift`
  - 负责页面共享状态、本地 JSON 存储、导入/导出、历史清理、自检、Mock/Local 回退和生成请求组装。

真实模型接入时，优先替换 `GemmaLocalService.generate(_:)` 内部实现，不需要改 UI 和历史数据结构。

## 当前验证

- `plutil -lint AITRANS/Resources/Info.plist AITRANS.xcodeproj/project.pbxproj` 通过。
- `jq empty AITRANS/Resources/Assets.xcassets/.../Contents.json` 通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ... generic/platform=iOS Simulator ... CODE_SIGNING_ALLOWED=NO build` 通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ... generic/platform=iOS ... CODE_SIGNING_ALLOWED=NO build` 通过。
- 本机当前 CoreSimulator service 不可用，所以还没有完成真实模拟器启动和点击交互测试。

fafamimi