# AITRANS iOS Prototype

这是一个基于 SwiftUI 的 iOS 本地 AI 同声传译原型。当前版本不下载真实 Gemma 模型，默认使用 `MockGemmaService` 模拟 Gemma 1.5B 的翻译、总结和耗时输出，先用于 Xcode 测试 App 外形、页面互通、数据流和本地存储。

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

- `工作台`：实时同传主界面，可以切换模式、源语言、目标语言、提示词，输入文本或点击麦克风模拟实时转录。
- `历史`：查看和搜索本地会话记录，打开历史会话会回到工作台并恢复对应转录、摘要、语言、提示词和模型设置；也可以导出/导入 JSON 或清空历史。
- `提示词`：选择内置提示词，新增自定义提示词，复制或编辑自定义提示词。
- `模型`：切换 `Mock` / `Local` 引擎，查看模型目录，运行自检，调整 temperature 和 max tokens，查看真实模型接入接口说明。

## 本地数据

数据保存在 App sandbox 的 Application Support 目录：

```text
Application Support/AITRANS/state.json
```

`state.json` 保存：

- 当前会话：转录行、摘要、语言、模式、提示词、模型引擎、会话时长。
- 历史记录：最多保留 60 个会话。
- 提示词模板：内置模板和用户新增模板。
- App 设置：当前引擎、语言、选中的提示词、temperature、max tokens。

历史页的 `导出 JSON` 会额外写出：

```text
Application Support/AITRANS/aitrans-export.json
```

历史页的 `导入 JSON` 可以选择同结构的 `aitrans-export.json` 或 `state.json`。导入时会先归档当前会话，再合并历史和提示词；内置提示词会保留，同 ID 的会话或提示词不会重复导入。

模型页的 `运行自检` 会检查：

- 本地 JSON 是否可写入并解码。
- Gemma 1.5B Mock 是否能生成非空输出。
- Local 模式在未下载模型时是否按预期回退到 Mock。

模型文件不放进仓库。Local 模式会检查：

```text
Application Support/Models/Gemma-1.5B/model.gguf
```

如果没有这个文件，界面会显示 Local 未就绪，但生成会自动回退到 Mock，保证原型仍可使用。

## 大模型接入点

- `AITRANS/Models/TranscriptModels.swift`
  - `LocalLanguageModeling` 是统一模型协议。
  - `ModelGenerationRequest` 包含任务类型、语言、提示词、上下文和采样参数。
  - `ModelGenerationResult` 返回文本、摘要、引擎名、token 数和耗时。
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
