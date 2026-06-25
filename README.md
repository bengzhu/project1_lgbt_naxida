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

项目根目录的 `test/` 已作为 folder resource 打进 App bundle。往 `test/` 放入音频或 OCR 图片后，需要重新构建安装 App，Pro 页的测试按钮才会扫描到新文件。

## 当前界面

- `工作台`：主界面是一个简洁翻译框，输入文字后点击 `翻译`，会使用当前提示词和 Mock/Local 模型接口生成译文；默认免费目标语言为中文和英语。
- `历史`：查看和搜索本地会话记录，打开历史会话会回到工作台并恢复对应转录、摘要、语言、提示词和模型设置；也可以通过系统文件面板导出/导入 JSON 或清空历史。
- `提示词`：选择内置提示词，新增自定义提示词，复制或编辑自定义提示词。当前支持 `英译中` / `中译英` 两套提示词内容，界面可切换方向查看和编辑；生成请求会按当前源语言/目标语言自动选择对应指令。
- `模型`：切换 `Mock` / `Local` 引擎，查看模型目录，下载内置 Gemma 270M GGUF，导入或移除本地 GGUF 文件，运行自检，单独运行 LLM 接口自测，调整 temperature 和 max tokens，查看真实模型接入接口说明。
- `开发`：在模型页输入密码 `114514` 开启。用于调试真实翻译接口，有一个用户输入框、一个“大模型实际输入”框、一个“大模型实际输出/错误代码”框，并新增批量 raw 探针。Local 模式会展示实际送入 `llama.cpp` 的完整 prompt 和 raw 输出，不做清洗、隐藏、重试或屏蔽；Mock 模式会明确标记为模拟输出，不代表真实模型。
- `Pro`：从首页独立出来的 Pro 功能页，包含订阅入口、长按麦克风同声传译、音频文件本机识别测试、图片 OCR 翻译、`test/` 固定测试入口和后台翻译路线说明。

## Pro / 内购占位

当前已接入 StoreKit 2 订阅骨架，但还没有 App Store Connect 线上商品。发布前需要在 App Store Connect 创建同 ID 自动续期订阅，并把价格配置为约 1 美元/月：

- 预留商品 ID：`com.local.aitrans.pro.monthly`。
- 展示价格：`$0.99/月`。
- `开通 Pro` 会尝试读取 StoreKit 商品并购买；如果 App Store Connect 未配置商品，会显示未找到商品。
- `校验订阅` 会读取 `Transaction.currentEntitlements` 并同步 Pro 状态。
- `开发解锁` 仍保留为本地调试开关，便于真机测试未上架功能。
- 免费：中文、英语文本翻译。
- Pro：解锁日语、法语、德语目标语言。
- Pro：解锁同声传译入口。同声传译在 Pro 页长按麦克风开始采集，松手结束，Apple Speech 本机识别结果先进入文本框，再点击按钮交给当前 Mock/Local 翻译接口。识别侧使用 `requiresOnDeviceRecognition = true`，支持情况取决于设备、系统和语言包。
- Pro：音频文件断网识别测试入口。选择音频后，App 会复制到沙盒，用 `SFSpeechURLRecognitionRequest` 和 `requiresOnDeviceRecognition = true` 做 Apple 本机识别，成功后自动交给当前大模型翻译。
- Pro：`test/` 音频/OCR 测试入口。App 会扫描 bundle 内 `test/` 的首个匹配文件；音频支持 `.m4a`、`.wav`、`.mp3`、`.caf`，图片支持 `.png`、`.jpg`、`.jpeg`、`.heic`。未找到文件时会显示 `test/ 未找到可测试音频/图片`。
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
- 提示词模板：内置模板和用户新增模板；新版本同时保存 `英译中` 和 `中译英` 两套指令。旧 JSON 只有单个 `instruction` 时会自动迁移为两个方向，不丢自定义提示词。
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

模型页的 `运行接口自测` 会按当前语言方向构造翻译输入，要求输出非空、不能等于原文、不能包含原文、不能是占位答复，并且要像目标语言。英译中曾出现模型原样返回英文的问题，后续排查必须优先使用接口自测和开发页 raw 探针，不要只看 UI 结果猜测。

开发页 raw 探针用于定位这几类问题：

- “运行原始接口”：按当前语言方向测试单条输入。Local 模式下这是送入 `llama.cpp` 的真实字符串和 raw 输出；Mock 模式只展示模拟请求预览。
- “运行批量探针”：依次跑 `Keep the model on device.`、`The meeting starts at 9:30 tomorrow.`、`Save the transcript locally.`、`请把会议记录保存在本地。`、`明天九点半开始会议。`，覆盖英译中和中译英。
- “大模型实际输入”：完整展示 app 当前送给模型的 prompt，包括语言方向、输入文本和当前方向提示词。Local 模式下这是送入 `llama.cpp` 的真实字符串。
- “大模型实际输出”：展示 `llama.cpp` raw 输出，不做 trim、clean、重试或 fallback；批量探针会逐条显示 prompt、raw output/error 和判定。
- “错误代码”：模型缺失、加载失败、上下文过长、分词失败或 decode 失败时直接显示错误类型和 `localizedDescription`。
- 如果 raw 输出正常但普通翻译失败，优先查 `GemmaLocalService.cleanTranslationOutput` 和目标语言校验；如果 raw 输出已经复读原文，优先查 prompt、采样和模型质量。

当前默认提示词是极简模板：

- 英译中：`把以下翻译成中文：`
- 中译英：`Translate the following into English:`

Local prompt 现在只拼当前方向指令和输入文本，减少长预设污染模型 raw 输出。JA/FR/DE Pro 翻译仍走通用 fallback。

## 语音 / OCR 测试规范

`test/` 用于固定测试素材，不用于保存用户数据或模型文件：

```text
test/
  sample.m4a
  sample.png
```

测试流程：

1. 把语音或图片放进项目根目录 `test/`。
2. 重新构建安装 App，因为 `test/` 是 bundle resource。
3. 在 App 内打开 `Pro`，使用 `开发解锁` 或有效订阅解锁 Pro。
4. 点击 `运行 test/ 音频` 或 `运行 test/ OCR`。
5. 音频会走 `SFSpeechURLRecognitionRequest` + `requiresOnDeviceRecognition = true`，识别文本再交给当前 Mock/Local 翻译接口。
6. 图片会走 `VNRecognizeTextRequest`，识别文字块和 `boundingBox` 后逐块翻译。

空目录预期结果：

- `运行 test/ 音频`：显示 `test/ 未找到可测试音频`。
- `运行 test/ OCR`：显示 `test/ 未找到可测试图片`。

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

## 近期优化记录

这些记录结合了最近 git 提交，方便后续新开对话快速接上当前状态：

- `92f2a8c`：新增 Mock LLM 接口自测、模型格式说明、GGUF 下载建议和命令行冒烟流程。结论是 iOS 本地模型先走 `llama.cpp + GGUF`。
- `84d00bb` / `c529c6b`：修复英译中接口问题，增加更严格的翻译探针。当前自测会判定“返回原文”“输出包含原文”“输出不像目标语言”为失败。
- `6b7df35`：新增开发者调试界面；Pro 从首页迁移到独立底部 Tab；Pro 页新增 StoreKit 2 订阅骨架和长按麦克风同声传译流程。
- 本次未提交工作区：提示词拆成 `英译中` / `中译英` 两套方向指令，默认提示词改为极简 `把以下翻译成中文：` / `Translate the following into English:`；Local prompt 改为只拼当前方向指令和输入。
- 本次未提交工作区：开发页新增 5 句批量 raw 探针。Local 模式展示真实 `llama.cpp` prompt/raw output；Mock 模式明确标记为模拟输出，不能当作真实模型质量判断。
- 本次未提交工作区：项目根 `test/` 已打进 App bundle，Pro 页新增 `运行 test/ 音频` 和 `运行 test/ OCR` 测试入口。当前 `test/` 为空，空目录预期会显示未找到可测试文件。

## 后续对话指引

- 新开对话时，先读本 README，再读 `git status --short` 和最近 5 条 `git log --oneline`。
- 排查翻译问题时，先用模型页 `运行接口自测` 和开发页 raw 探针确认输入、输出、错误，再改 prompt 或清洗逻辑。
- 英译中优先用这些探针句测试：`The meeting starts at 9:30 tomorrow.`、`Keep the model on device.`、`Save the transcript locally.`。
- 中译英优先用这些探针句测试：`请把会议记录保存在本地。`、`明天九点半开始会议。`。
- 当前内置 Gemma 270M 适合验证下载、加载、接口和闪退风险，不适合作为翻译质量基准；质量验证优先换 `Qwen2.5-0.5B-Instruct-GGUF` 的 `q4_k_m`。
- 每次功能更新或 bug 修复后，都要在本 README 的“近期优化记录”追加 1-3 条简短记录，写清改了什么、验证了什么、还有什么风险，便于后续对话继承上下文。

## 当前验证

- `plutil -lint AITRANS/Resources/Info.plist AITRANS.xcodeproj/project.pbxproj` 通过。
- `jq empty AITRANS/Resources/Assets.xcassets/.../Contents.json` 通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ... generic/platform=iOS Simulator ... CODE_SIGNING_ALLOWED=NO build` 通过。本次构建日志里 CoreSimulatorService 有沙盒警告，但构建最终成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ... generic/platform=iOS ... CODE_SIGNING_ALLOWED=NO build` 通过。
- 已确认 Debug iOS Simulator app bundle 内嵌 `llama.framework`。
- `git diff --check` 通过。
