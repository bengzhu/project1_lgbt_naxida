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

### 漫画覆盖翻译探针

开发页新增 `运行漫画覆盖翻译探针`，固定读取 bundle 内 `test/1.png`，不污染当前会话、历史或普通图片翻译状态。流程：

1. 读取 `test/1.png`。
2. 先按可配置比例裁掉浏览器 UI / 广告 / 底部导航，本次默认 `topRatio = 0.235`、`bottomRatio = 0.14`。
3. 对裁切后的漫画内容做 2x 放大，再做 0°、90°、180°、270° 四次 Apple Vision OCR，识别英文文字块。
4. 将旋转图坐标还原成原图像素 bbox，坐标约定为左上角原点 `[x, y, width, height]`；输出绘制同样使用左上角坐标，避免上下翻转。
5. 对 OCR 候选按 bbox 重叠、文本相似度、相邻行/段落空间关系合并，目标是一个对话框对应一个逻辑块。
6. 对每个合并块复用当前英译中极简提示词 `把以下翻译成中文：` 和当前引擎翻译；Local 模式记录真实 `llama.cpp` prompt/raw output，Mock 模式标记为模拟。
7. 质量判定失败时也会绘制覆盖层，文本为 `翻译失败` + OCR 原文，并在报告写入失败原因，避免静默跳过。
8. 生成 `Application Support/AITRANS/Output/1_debug_boxes.png`、`1_translated_overlay.png` 和 `probe_report.json`。

探针报告字段：

- `sourceImage`：固定 `test/1.png`。
- `engineUsed`：实际适配器显示名。
- `totalBlocksDetected`：最终保留文本块数。
- `blocks[].bbox`：原图像素坐标，左上角原点。
- `blocks[].rotationAngleUsed`：该块来自 0/90/180/270 哪个 OCR 角度。
- `blocks[].prompt` / `rawOutput` / `errorCode`：真实输入输出或错误。
- `blocks[].checks`：`ocrNotEmpty`、`translationNotEmpty`、`translationNotEqualOriginal`、`translationNotContainOriginal`、`looksLikeChinese`。
- `blocks[].translationCandidate`：从 raw output 中抽取出来用于质量判定和覆盖绘制的候选译文。
- `blocks[].rawOutputClassification` / `candidateClassification` / `failureCategory`：分别记录模型 raw 输出类型、候选译文类型和失败归因。常见值包括 `chinese`、`nonChinese`、`placeholder`、`repeatedOriginal`、`symbolsOnly`、`modelOutputFailure`、`ocrInputSuspect`、`ruleFalseFailureSuspected`。
- `blocks[].bestGroundTruthText` / `ocrGroundTruthSimilarity` / `ocrQualityLabel`：把当前 OCR 文本和 `test/1.ground_truth.json` 的人工真值做相似度对照，用于判断翻译差是否先由 OCR 输入错误导致。
- `blocks[].failureReasons`：失败块的具体原因，例如 `翻译等于原文`、`翻译是占位答复`、`中文字符不足`、`翻译不像中文`。
- `blocks[].qualityNotes`：非硬失败排查线索，例如 `translationContainsFullOCRText`、`latinLetters=27`、`cjkCharacters=4`。
- `diagnostics`：本轮整体排查汇总，统计通过/失败块、空候选、占位输出、复读原文、非中文输出、raw 输出类型、候选抽取丢弃、平均 OCR 真值相似度、疑似 OCR 问题块、疑似规则误伤块。
- `configuration.currentBlockSource`：记录当前块来源。当前是整图 OCR observations 的空间聚类/去重，即 (a)，不是图像层面的气泡连通域检测。
- `configuration.preprocessing`：记录本轮预处理增强开关，包含灰度、对比亮度、自适应二值化、裁切放大、锐化和放大倍数。
- `configuration.customLexiconEnabled` / `customLexicon`：记录 Vision `customWords` 是否启用和本轮词表。
- `blocks[].rawOcrText` / `afterPreprocessingOcrText` / `finalTextUsedForTranslation`：记录原始 OCR、裁切预处理后二次 OCR、最终送翻译文本。当前预处理结果只用于对比展示，不替换整图 OCR 主流程。
- `blocks[].correctionEnabled` / `afterCorrectionText` / `correctionRejectedReason` / `correctionPrompt` / `correctionRawOutput` / `correctionErrorCode`：记录 OCR 纠错后处理链路。护栏拒绝时 `afterCorrectionText` 保留原文，`correctionRejectedReason` 写明长度、词数、新词或空输出原因。
- `correctionGuardrailTest`：固定构造 `XQZ 12 ///` -> `The City Battler Tournament starts in a few days.` 的过度纠错测试，用来证明护栏会拒绝模型瞎猜。
- `lexiconComparison`：同图同参数下 Vision `customWords` 开/关对比，记录总块数和发生变化的块编号。
- `visionAPIComparison`：旧 `VNRecognizeTextRequest` 与 iOS 18+ Swift 原生 `RecognizeTextRequest` 的 0° OCR 对比。当前只作为独立探针，不替换主流程。
- `overallPassed`：至少 1 个块、所有块通过质量判定、两张 PNG 非空才为 `true`。

探针验收重点：

- `probe_report.json` 不应包含广告横幅、地址栏、翻页导航、系统状态栏等浏览器 UI 文本。
- `1_debug_boxes.png` 中同一对话框不应出现密集堆叠红框；一个气泡通常对应一个块。
- `1_translated_overlay.png` 中所有绘制文本必须正向可读；即使某块来自旋转 OCR，也不允许倒置或镜像。
- `blockPassed = false` 的块也必须出现在覆盖图上，并保留失败原因，不能静默隐藏。
- 每次运行会先清空 App 沙盒 `Application Support/AITRANS/Output/`，`scripts/export-probe-output.sh` 也会先清空项目根 `output/`，避免新旧 PNG / JSON 混在一起。
- 输出图片包括 `1_debug_boxes.png`、`1_translated_overlay.png`、`1_ocr_text_overlay.png`、`1_block_crops.png`、`1_preprocessed_content.png`。其中 `1_block_crops.png` 是块裁切放大预处理拼图，用于目测二值化/锐化是否过激。
- 翻译失败排查规范：先看 `failureCategory`，再看 `rawOutputClassification` 和 `candidateClassification`。如果 `failureCategory = ocrInputSuspect`，优先修 OCR/合并/裁切；如果是 `modelOutputFailure`，优先换模型、调采样或 prompt；如果是 `ruleFalseFailureSuspected`，才优先放宽判定规则。不要只看覆盖图猜测失败原因。
- OCR 质量排查规范：先按 `ocrGroundTruthSimilarity` 从低到高看 `blocks[].finalTextUsedForTranslation`。本探针用 `test/1.ground_truth.json` 做真值；换测试图时应同步更新真值文件，否则相似度只作参考。

模拟器跑完后，把沙盒输出导出到项目根 `output/`：

```sh
scripts/export-probe-output.sh
```

如需指定设备：

```sh
scripts/export-probe-output.sh booted
```

也可用 DEBUG 环境变量自动触发，适合命令行探针：

```sh
AITRANS_RUN_MANGA_PROBE=1
```

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
- 本次未提交工作区：开发页新增 `test/1.png` 漫画覆盖翻译探针。实现多角度 Vision OCR、bbox 像素坐标还原、逐块英译中 raw prompt/raw output 报告、`1_debug_boxes.png`、`1_translated_overlay.png` 和 `probe_report.json` 沙盒输出。
- 本次未提交工作区：新增 `scripts/export-probe-output.sh`，用 `xcrun simctl get_app_container` 从模拟器沙盒导出 `Application Support/AITRANS/Output/` 到项目根 `output/`。已知限制：导出依赖手动脚本；背景色采样优先可读性，不追求完美还原气泡。
- 本次未提交工作区 v2：漫画覆盖探针新增内容区域裁切、2x OCR 放大、候选文本相似度去重、段落/对话框空间聚类、聚类后二次合并；修复输出 PNG 坐标系不一致导致的译文倒置/镜像问题。
- 本次未提交工作区 v2：翻译失败块不再跳过覆盖绘制，改为显示 `翻译失败` + OCR 原文，并在 `probe_report.json` 写入 `failureReasons`；开发页块详情同步显示失败原因。
- 本次未提交工作区 v3：探针输出目录每轮先清空，导出脚本也会重建项目根 `output/`，避免旧图缓存堆积或污染验收。
- 本次未提交工作区 v3：`probe_report.json` 新增 `translationCandidate` 和 `qualityNotes`。翻译质量判定改为记录 raw output -> candidate -> checks 的链路；`翻译包含完整原文` 不再单独作为硬失败，但空输出、原文复读、占位答复、中文字符不足、非中文仍会失败。
- 本次未提交工作区 v3 实测：用 iPhone 17 Pro 模拟器自动探针 `AITRANS_RUN_MANGA_PROBE=1` 跑 `test/1.png`，导出到 `output/`。本次 `totalBlocksDetected = 12`、`blockPassed=false` 为 7 个、`overallPassed=false`，`output/` 只包含 `1_debug_boxes.png`、`1_translated_overlay.png`、`probe_report.json` 三个最新文件。失败主要分三类：Gemma raw 输出原文/非中文，如 `IVE ARRIVED AT REN- SENPAI'S HOUSE.`；模型输出占位答复，如 `以下是翻译成中文：`；OCR 本身有明显误读，如 `THE CITY RATTLER STATE IN A PEN DAYS.`、`THOUGH THOUSH EVEN`、`SUGSESTION THE OVERRULED`。
- 本次未提交工作区 v4：已明确当前 12 个块来自 (a) 整图 OCR observations 的空间聚类/去重，不是 (b) 图像层面的气泡检测；第 5 节气泡检测仍是后续新增能力。
- 本次未提交工作区 v4：新增预处理增强配置和报告链路字段。当前子步骤均有开关：灰度、对比/亮度、自适应二值化、裁切放大、锐化；每块报告 `rawOcrText`、`afterPreprocessingOcrText`、`finalTextUsedForTranslation`。
- 本次未提交工作区 v4 实测：iPhone 17 Pro 模拟器跑 `test/1.png`，`totalBlocksDetected = 12`、预处理改变 11 个块、实际用于翻译 0 个预处理结果、`blockPassed = 2`、`overallPassed=false`。结论：当前默认预处理组合过激，二值化/锐化会把漫画网点和边框噪声放大，`1_block_crops.png` 中可见黑白块明显污染文字；因此本轮只把预处理结果作为对比证据，不替换主流程。
- 本次未提交工作区 v4：新增 `1_ocr_text_overlay.png`、`1_block_crops.png`、`1_preprocessed_content.png` 三份结果图。部署目标仍是 iOS 17.0，`RecognizeTextRequest` 新 API 必须后续用 `@available(iOS 18, *)` 条件接入；本轮只记录该限制，尚未启用新 API/自定义词表对比/气泡优先路径。
- 本次未提交工作区 v5：探针运行开始先重建 App 沙盒 `Output/`，渲染时再次重建，导出脚本继续重建项目根 `output/`；每轮只保留最新 `probe_report.json` 和 5 张 PNG，避免旧图缓存堆积。
- 本次未提交工作区 v5：`probe_report.json` 新增 `diagnostics` 汇总，并收紧失败原因记录：空翻译不再连带标成“等于原文/占位/不像中文”；模板行如 `以下是翻译成中文：` 不再当有效候选。`qualityNotes` 记录 raw/candidate 长度、CJK/Latin 字数、疑似 OCR 错词和疑似规则误伤。
- 本次未提交工作区 v5 实测结论：当前失败不是规则太严。`cjkButFailedCandidates = 0`、`likelyRuleFalseFailureBlocks = []`，主要问题是模型 raw 输出空/英文/占位，以及 OCR 原句已经错，如 `THE CITY RATTLER`、`TRANINS SPECIAL`、`SUGSESTION`、`LOSIC`。
- 本次未提交工作区 v6：新增 OCR 纠错后处理模块，默认在漫画探针中开启。纠错 prompt 使用简洁模板；Local 模式记录真实 `correctionPrompt`/`correctionRawOutput`，Mock 模式原样回传；护栏按长度变化、词数变化和无依据新词拒绝高风险改写。
- 本次未提交工作区 v6 实测：iPhone 17 Pro 模拟器跑 `test/1.png`，12 个块均启用纠错；当前 Gemma 270M raw 纠错输出没有一条通过护栏，`finalTextUsedForTranslation` 全部保留原始 OCR。拒绝原因主要是长度变化超过 30% 或纠错输出为空。固定护栏测试 `XQZ 12 ///` -> `The City Battler Tournament starts in a few days.` 被拒绝，原因 `长度变化 390% 超过 30%`。结论：护栏生效，但当前小模型不能作为可靠 OCR 纠错器。
- 本次未提交工作区 v7：Vision OCR 接入 `customWords` 自定义词表，当前默认词表为 `Senpai`、`City Battler`、`Tournament`、`Ren`、`Battler`；主流程启用词表，同时探针独立跑词表开/关对比，写入 `lexiconComparison`。
- 本次未提交工作区 v7 实测：iPhone 17 Pro 模拟器跑 `test/1.png`，词表开/关最终合并块数均为 12，`changedBlockIndexes = []`。结论：本图里自定义词表没有改变最终块文本；它适合给专有名词/语言校正提供提示，不解决 `FEW`->`PEN`、`TOURNAMENT`->`TOUINAMENT` 这类常见词误识别。
- 本次未提交工作区 v7：新增 iOS 18+ Swift 原生 `RecognizeTextRequest` 对比探针，用 `@available(iOS 18.0, *)` 隔离，不替换旧 `VNRecognizeTextRequest` 主流程。iOS 26.5 模拟器实测新 API 可用，0° OCR observation 数旧/新均为 82，样本序列一致，`changed = false`。
- 本次未提交工作区 v8：新增 `test/1.ground_truth.json`，并把 `test/1.png` 的整页 OCR 与独立 bubble-first 近白连通域探针做框架对比。整页路径仍是主流程；bubble-first 当前只作对照，不替换主路径。
- 本次未提交工作区 v8 实测：整页路径 `totalBlocksDetected = 12`、`accuracyVsGroundTruth = 0.8378`、耗时约 65s；bubble-first 只检测到 2 块、`accuracyVsGroundTruth = 0.3857`、耗时约 31s。结论：现阶段真正气泡检测仍不成熟，近白连通域会把大面积页面合成一个巨大块，后续需要更强的气泡边界检测。
- 本次未提交工作区 v9：确认输出清理链路：探针开始重建 App 沙盒 `Output/`，渲染时再次重建，导出脚本重建项目根 `output/`；本轮导出后 `output/` 只有 8 个最新文件：`probe_report.json`、`1_debug_boxes.png`、`1_translated_overlay.png`、`1_ocr_text_overlay.png`、`1_block_crops.png`、`1_preprocessed_content.png`、`1_bubble_debug.png`、`1_bubble_crops.png`。
- 本次未提交工作区 v9：`probe_report.json` 增加 `rawOutputClassification`、`candidateClassification`、`failureCategory`、`bestGroundTruthText`、`ocrGroundTruthSimilarity`、`ocrQualityLabel`，并在 `diagnostics` 汇总 raw 输出失败、候选抽取、平均 OCR 相似度和低相似度块。候选抽取修复 `| 谢谢！` 这类管道前缀输出被错误抽空的问题；占位规则补充 `翻译成中文`、`最常用的翻译`、`我个人觉得` 等解释型输出。
- 本次未提交工作区 v9 实测：iPhone 17 Pro 模拟器跑 `test/1.png` 后 `totalBlocksDetected = 12`、`passedBlocks = 3`、`failedBlocks = 9`、`averageOCRGroundTruthSimilarity = 0.6846`、`likelyRuleFalseFailureBlocks = []`、`candidateExtractorDroppedRawOutputs = 0`。结论：本轮未发现“真实翻译成功但规则太严误杀”的块；主要问题是 OCR 输入错误和当前 Gemma 270M raw 输出不稳定。
- 本次未提交工作区 v9 OCR 排查结果：低相似/可疑块集中在 `THE CITY RATTLER / STATE IN A PEN DAYS.`、`GET PESULTE / SAMING CLUE TO SAVE THE / POOM BENG`、`What Whet are / every you! / talking`、`City Battler / Offline. / Tournament` 等。即使 OCR 基本找到了位置，部分英文文本本身已经错到会误导翻译，因此翻译质量差不能只靠放宽中文判定解决。
- 本次未提交工作区 v10：继续排查“翻译失败”规则。`blockPassed` 不再因为 OCR 真值相似度低自动失败，OCR 风险改由 `failureCategory`、`qualityNotes`、`diagnostics.likelyOCRIssueBlocks` 单独记录；raw 输出里带 `以下是翻译成中文` 这类模板噪声时，只要候选抽取出非占位中文，不再一票否决。占位规则补充 `请你提供`、`更多上下文`、`更好地理解`，避免解释/拒答型中文被误判为有效译文。
- 本次未提交工作区 v10 实测：iPhone 17 Pro 模拟器重新跑 `test/1.png` 并导出，项目根 `output/` 清理后只保留 9 个最新文件：`probe_report.json` 和 8 张 PNG。最终 `totalBlocksDetected = 12`、`passedBlocks = 3`、`failedBlocks = 9`、`averageOCRGroundTruthSimilarity = 0.6846`、`likelyRuleFalseFailureBlocks = []`、`cjkButFailedCandidates = 0`、`candidateExtractorDroppedRawOutputs = 0`。结论：本轮未发现规则太严导致的真实中文译文误杀；失败主要是模型 raw 输出空/英文/占位/复读，或 OCR 英文已经错。
- 本次未提交工作区 v10 OCR 原句排查：高相似但模型失败包括 `THAT'S / RIGHT, / NOW / I'M-`、`IVE ARRIVED AT REN- SENPAI'S HOUSE.`、`LET'S / BATTLER!`；低相似或可疑 OCR 包括 `THE CITY RATTLER / STATE IN A PEN DAYS.`、`THAT'S / WE'RE WHY / TRANINS SPECIAL`、`THIS IS AN / TOURNAMENT. DOING IT / WOULD MAKE WOLLD MAKE ONLINE`、`GET PESULTE / SAMING CLUE TO SAVE THE / POOM BENG`、`What Whet are / every you! / talking`。整页 OCR 仍明显强于 bubble-first：`wholePage accuracy = 0.8378 / 12 blocks / 62.5s`，`bubbleFirst accuracy = 0.2487 / 1 block / 17.6s`。
- 本次未提交工作区 v11：优化 bubble-first 探针候选保留策略。之前 `1_bubble_seed_debug.png` 里已有多个 OCR seed 框，但最终 `1_bubble_debug.png` 只剩 1 个，是 seed 被 white component 重叠过滤压掉。现在改为 seed-first：先保留去重后的 `ocrSeed` 候选，再补充不重叠的 `whiteComponent`；`ocrSeed` crop 走原图 2x 放大 OCR，不套默认二值化/锐化，避免预处理过激导致空结果。
- 本次未提交工作区 v11 实测：iPhone 17 Pro 模拟器跑 `test/1.png` 后，bubble-first 从 `1 block / accuracy 0.2487 / foundBoth 1` 提升到 `8 blocks / accuracy 0.6915 / foundBoth 6`；`blocksOnlyInWholePage` 从 7 条降到 2 条：`Or at least, that seems to be Senpai's logic.`、`Let's Battle!`。已知局限：底部多个相邻气泡仍会被 seed 大框混在一起，部分文本串扰明显，后续需要按 crop 内文本行/列再切分。

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
- `test/1.png` 漫画覆盖探针已在 iPhone 17 Pro 模拟器运行并导出：`output/probe_report.json`、`output/1_debug_boxes.png`、`output/1_translated_overlay.png` 均非空。调试图框线明显；覆盖图能盖住部分原文并绘制译文，但受 OCR 小块切分和当前 Local GGUF 翻译质量影响，结果仍不适合作为最终产品效果。
