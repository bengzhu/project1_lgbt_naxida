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

## 协作与云端验证

- 日常工作主分支是 `smalldata_test`；`main` 只作外观展示，不合并日常开发成果。
- Agent B 候选实现分支使用 `codeb/vX.Y-短标题`，push 后创建 PR 到 `smalldata_test` 并由 GitHub Actions 重验证。
- 本机默认只跑轻量检查；除非人工明确要求，不默认跑本机 Xcode build 或漫画探针。
- Agent C 验收使用未加密的 `AITRANS CI Results` artifact，核对 `.xcresult`、`junit.xml`、`xcodebuild.log`、`ci-artifact-manifest.json` 和失败摘要。
- 云端验证必须先用 `gh auth login` 拿到 GitHub 权限，Agent C 才能下载 Actions 结果包。
- Agent C 下载的云端测试缓存默认放在 `/private/tmp/aitrans-c-review-<run_id>/`，由人工确认后删除。
- Agent C 通过 PR 合并后必须删除远端 `codeb/...` 候选分支，避免分支无限堆积；无权限删除时要明确说明。
- 现有加密软件包 artifact 只用于软件包交付，不作为 Agent C 验收依据。
- `AITRANS CI Results` 会从 Release `model-gemma-3-270m-it-qat-q4_0-v1` 下载 `gemma-3-270m-it-qat-Q4_0.gguf`，校验 SHA256 `3626e245220ca4a1c5911eb4010b3ecb7bdbf5bc53c79403c21355354d1e2dc6`，并用 Actions cache 复用 `.ci-models/`。当前只完成模型下载/缓存，完整探针还需后续把模型导入模拟器 App 沙盒。
- 云端探针会构建并安装 Debug simulator app，把缓存模型复制到 App sandbox 的 `Application Support/Models/Gemma-1.5B/model.gguf`，用 `AITRANS_RUN_MANGA_PROBE=1` 启动 App，导出本轮 `output/` 到未加密结果包。`Gemma-1.5B` 是历史目录名；实际文件必须用 Release asset 名、字节数和 SHA256 校验确认。验收口径是报告可解析、`engineUsed = Local GGUF`、`totalBlocksDetected > 0`、关键 JSON/TXT/PNG 可用；`overallPassed=false` 仍可能是当前模型质量基线，不单独作为 CI 失败。若探针超时，结果包会保留 `manga-probe.log`、`app-console.log` 和 `output/manga_probe_progress.json`；若进度长时间不更新，workflow 会提前收束日志，避免空等 60 分钟。

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
- `blocks[].bestGroundTruthType` / `groundTruthMatch` / `groundTruthMatchThreshold`：人工真值匹配类型与是否可信匹配。低于阈值的块会标为 `unmatched`，不再强行配一个错误真值，也不纳入准确率统计。
- `blocks[].ocrLegacySimilarity` / `wordOrderPreserved`：保留旧相似度作对照，同时新增词级编辑距离相似度和词序信号。词序错乱的 OCR 会明显降分，避免旧算法把乱序文本算成高准确。
- `blocks[].failureReasons`：失败块的具体原因，例如 `翻译等于原文`、`翻译是占位答复`、`中文字符不足`、`翻译不像中文`。
- `blocks[].qualityNotes`：非硬失败排查线索，例如 `translationContainsFullOCRText`、`latinLetters=27`、`cjkCharacters=4`。
- `blocks[].translationDecisionTrace` / `translationFailureDetail`：逐块记录 raw 分类、候选分类、每条硬判定布尔值和失败归因；用于确认失败来自模型 raw 输出、OCR 输入、候选抽取，还是规则误伤。
- `blocks[].ocrProbeNotes`：逐块记录 OCR 和人工真值的相似度、质量标签、已知 OCR 混淆提示。
- `diagnostics`：本轮整体排查汇总，统计通过/失败块、空候选、占位输出、复读原文、非中文输出、raw 输出类型、候选抽取丢弃、平均 OCR 真值相似度、疑似 OCR 问题块、疑似规则误伤块、失败分类分布、中文候选失败原因分布、翻译语言质量通过/失败块、硬通过但质量可疑块。
- `diagnostics.averageCoreDialogueOCRSimilarity` / `averageDecorativeOCRSimilarity` / `groundTruthMatchedBlocks` / `groundTruthUnmatchedBlocks` / `wordOrderFailedBlocks` / `repeatedKeywordFailures`：可信匹配后的核心对话/装饰文字分开统计、未匹配块计数、词序失败块和高频专有名词损坏追踪。
- `configuration.currentBlockSource`：记录当前块来源。当前是 `fusedWholePageBubble`，即 whole-page OCR 与 bubble-first OCR 的无真值融合主流程。
- `configuration.preprocessing`：记录本轮预处理增强开关，包含灰度、对比亮度、自适应二值化、裁切放大、锐化和放大倍数。
- `configuration.customLexiconEnabled` / `customLexicon`：记录 Vision `customWords` 是否启用和本轮词表。
- `blocks[].rawOcrText` / `afterPreprocessingOcrText` / `finalTextUsedForTranslation`：记录原始 OCR、裁切预处理后二次 OCR、最终送翻译文本。当前预处理结果只用于对比展示，不替换整图 OCR 主流程。
- `blocks[].correctionEnabled` / `afterCorrectionText` / `correctionRejectedReason` / `correctionPrompt` / `correctionRawOutput` / `correctionErrorCode`：记录 OCR 纠错后处理链路。护栏拒绝时 `afterCorrectionText` 保留原文，`correctionRejectedReason` 写明长度、词数、新词或空输出原因。
- `blocks[].deterministicCorrectionText` / `deterministicCorrectionAppliedRules` / `deterministicCorrectionSimilarity`：记录探针专用确定性 OCR 纠错候选。当前只做量化对比，不替换 `finalTextUsedForTranslation`，避免半修正文本污染翻译链路。
- `blocks[].deterministicCorrectionTranslationCandidate` / `deterministicCorrectionTranslationRawOutput` / `deterministicCorrectionTranslationPassed` / `deterministicCorrectionTranslationFailureDetail`：仅对确定性纠错相似度确有提升的块，额外跑一次纠错文本翻译对照。该结果只用于探针，不替换主覆盖图和主翻译输入。
- `correctionGuardrailTest`：固定构造 `XQZ 12 ///` -> `The City Battler Tournament starts in a few days.` 的过度纠错测试，用来证明护栏会拒绝模型瞎猜。
- `lexiconComparison`：同图同参数下 Vision `customWords` 开/关对比，记录总块数和发生变化的块编号。
- `visionAPIComparison`：旧 `VNRecognizeTextRequest` 与 iOS 18+ Swift 原生 `RecognizeTextRequest` 的 0° OCR 对比。当前只作为独立探针，不替换主流程。
- `frameworkComparison`：整页 OCR 与 bubble-first 对照。差集列表、交集数量和汇总准确率都从最终明细现场计算，`consistencyPassed` 必须为 `true`；如果计数和列表不一致，会写入 `consistencyWarnings`。
- `fusionComparison` / `fusionResults`：whole-page 与 bubble-first 的融合主流程审计。候选选择只用 bbox、bubbleID、文本相似度、OCR 置信度和文本质量等无真值信号；ground truth 只用于事后评估。报告会记录被选来源、竞争候选、替换原因和拒绝原因。
- `preCropTextBoxPlanReport`：TextRegion crop 前生成的 Koharu 式上游 TextBox plan artifact。每块最多保留 3 个 plan，使用 fused seed bbox、BubbleMask majority、subRegion、split candidate、safe rect 和 glyph/SegmentMask proxy 等无真值信号排序；只用于 shadow OCR，不替换 `finalTextUsedForTranslation`。
- `cropExperimentReport`：TextRegion crop 的 shadow-only 实验矩阵。control 使用当前 TextRegion crop，每块最多额外跑 3 个候选；v18 起优先使用 `preCropTextBoxPlan.*` 作为 shadow 来源。`bestShadowCandidate` 只进入 JSON/TXT 报告，不替换 `finalTextUsedForTranslation`，也不放宽 `textRegionCropReport.adoptedCount`。
- `textBoxPlanFailureReport`：v19 新增的 plan / candidate / block 三级失败归因和晋级门槛审计。它用 `sourcePlanID` 关联 pre-crop plan 与 shadow OCR candidate，记录 promotion checks、blockers、primary failure category 和 recommended action；只解释为什么 `betterThanControl` 未晋级，不改变 `finalTextUsedForTranslation`、主覆盖图或 `adoptedCount`。
- `lineTextBoxPlanReport` / `lineCropExperimentReport`：v20 新增的 Koharu 式行级 TextBox / deskew shadow 验证层。目标块动态来自 `textBoxPlanFailureReport.continueGeometryResearchBlocks`，当前为 `[1, 6, 10]`；每块最多 4 个 line-level plan，候选变体以 `lineTextBoxPlan.*` 开头，只进 shadow OCR 和报告，不写回 `finalTextUsedForTranslation`、主覆盖图、`blockPassed` 或 `textRegionCropReport.adoptedCount`。
- `externalArtifactReadinessReport`：v21 / v1.11 新增的真实 TextBoxes / BubbleMask / SegmentMask artifact 适配前证据闸门。它只解析 `test/koharu_artifacts/` 下 manifest 和外部 JSON，做 schema、坐标、bbox 和 block alignment 校验；没有真实 artifact 时必须输出明确阻塞，不把现有 Vision OCR、pre-crop plan 或 line plan 伪装成 detector 输出。
- `cleanTextDiagnostic` / `output/clean_text_diagnostic.json`：跳过 OCR，直接把 `test/1.ground_truth.json` 中的 dialogue 真值送入当前翻译链路，用于判断失败来自 OCR 噪声还是当前 Local 模型/判定链路。
- `overallPassed`：至少 1 个块、所有块通过质量判定、两张 PNG 非空才为 `true`。
- `outputDirectoryCleaned` / `retainedOutputFiles` / `outputCleanupPolicy`：记录本轮输出目录是否按清理策略重建，以及本轮最终保留的 PNG/JSON 文件名。

探针验收重点：

- `probe_report.json` 不应包含广告横幅、地址栏、翻页导航、系统状态栏等浏览器 UI 文本。
- `1_debug_boxes.png` 中同一对话框不应出现密集堆叠红框；一个气泡通常对应一个块。
- `1_translated_overlay.png` 中所有绘制文本必须正向可读；即使某块来自旋转 OCR，也不允许倒置或镜像。
- `blockPassed = false` 的块也必须出现在覆盖图上，并保留失败原因，不能静默隐藏。
- 每次运行会先清空 App 沙盒 `Application Support/AITRANS/Output/`，`scripts/export-probe-output.sh` 也会先清空项目根 `output/`，避免新旧 PNG / JSON 混在一起。
- 输出包括 `1_debug_boxes.png`、`1_translated_overlay.png`、`1_ocr_text_overlay.png`、`1_deterministic_correction_overlay.png`、`1_deterministic_translation_overlay.png`、`1_block_crops.png`、`1_preprocessed_content.png`、`1_bubble_debug.png`、`1_bubble_seed_debug.png`、`1_bubble_crops.png`、`1_bubble_text_overlay.png`、`1_probe_contact_sheet.png`、`1_ocr_probe_text.txt`。其中 `1_block_crops.png` 是块裁切放大预处理拼图，用于目测二值化/锐化是否过激；`1_deterministic_correction_overlay.png` 用于直接对比原 OCR 和确定性纠错候选；`1_deterministic_translation_overlay.png` 用于查看“纠错后再翻译”是否通过；`1_bubble_text_overlay.png` 把 bubble-first OCR 文本贴回原图，方便和全图 OCR overlay 并排看；`1_probe_contact_sheet.png` 把全图 OCR、气泡 OCR、气泡裁切、翻译覆盖和纠错对照拼成 2 列总览；`1_ocr_probe_text.txt` 是每块 OCR、纠错候选、raw output、候选译文、失败原因、质量备注和判定轨迹的纯文本快照，便于不用 `jq` 也能排查 OCR 原句。
- 翻译失败排查规范：先看 `failureCategory`，再看 `rawOutputClassification` 和 `candidateClassification`。如果 `failureCategory = ocrInputSuspect`，优先修 OCR/合并/裁切；如果是 `modelOutputFailure`，优先换模型、调采样或 prompt；如果是 `translationLanguageQualityFailure`，说明模型给了中文或半中文，但候选本身过短、混入未翻译英文或像解释文本；如果是 `ruleFalseFailureSuspected`，才优先放宽判定规则。不要只看覆盖图猜测失败原因。
- 翻译规则排查规范：如果 `likelyRuleFalseFailureBlocks = []`，说明本轮没有发现“真实中文译文被规则误杀”。`cjkButFailedCandidates` 只表示“候选含中文但未过端到端质量门”，需继续看 `cjkFailureBreakdown`；中文候选存在不等于通过，硬通过前还会检查解释/列表型输出、长原文短译文、中英混排和 OCR 输入质量。
- OCR 质量排查规范：先按 `ocrGroundTruthSimilarity` 从低到高看 `blocks[].finalTextUsedForTranslation`。本探针用 `test/1.ground_truth.json` 做真值；换测试图时应同步更新真值文件，否则相似度只作参考。
- 可信准确率规范：只看 `groundTruthMatch = matched` 的块；核心对话和 `decorative` 装饰标题分开统计。`unmatched` 块必须保留在明细里，但不能混进平均准确率。旧版 `accuracyVsGroundTruth = 0.8378 / 0.8755` 使用了不完整真值和过宽相似度，只能作为历史对照，不能再作为验收数字。
- 干净文本诊断规范：如果 `cleanTextDiagnostic.passRate` 仍低，说明即使没有 OCR 噪声，当前翻译模型/输出风格也不稳定；这时不要只调 OCR 或放宽质量规则。
- 解码规范：用户实际翻译仍使用 `sampled` 路径，llama.cpp 采样链为 top-k/top-p/min-p + `temperature = 0.2` + 随机 seed；漫画探针、`clean_text_diagnostic`、逐块 raw 翻译、确定性纠错翻译对照和 tagged batch 诊断使用 `deterministic` 路径，固定 `seed = 42` 并走 `temperature = 0` + greedy 解码。`probe_report.json` 顶层、`configuration`、`cleanTextDiagnostic` 和 `batchTranslationComparison` 会记录 `decodingMode` / `decodingSeed`。
- 跨版本指标规范：版本历史、关键决策和验证结果统一写入 `update_log.md`。涉及漫画探针或翻译链路的可量化版本，推荐先跑完整探针并导出 `output/`，再执行 `python3 scripts/append-version-metrics.py --version vN --notes "..."`。`metrics/version_history.csv` 不放在 `output/`，不会被 `scripts/export-probe-output.sh` 清理；不要覆盖或删除历史行。

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

## 后续对话指引

- 新开对话时，先读本 README，再读 `git status --short` 和最近 5 条 `git log --oneline`。
- 排查翻译问题时，先用模型页 `运行接口自测` 和开发页 raw 探针确认输入、输出、错误，再改 prompt 或清洗逻辑。
- 英译中优先用这些探针句测试：`The meeting starts at 9:30 tomorrow.`、`Keep the model on device.`、`Save the transcript locally.`。
- 中译英优先用这些探针句测试：`请把会议记录保存在本地。`、`明天九点半开始会议。`。
- 当前内置 Gemma 270M 适合验证下载、加载、接口和闪退风险，不适合作为翻译质量基准；质量验证优先换 `Qwen2.5-0.5B-Instruct-GGUF` 的 `q4_k_m`。
- 每次功能更新或 bug 修复后，都要在 `update_log.md` 追加简短记录，写清改了什么、验证了什么、还有什么风险；涉及漫画探针或翻译链路的可量化版本，再 append-only 追加 `metrics/version_history.csv`，便于后续对话继承上下文和画趋势。

## 当前验证

- `plutil -lint AITRANS/Resources/Info.plist AITRANS.xcodeproj/project.pbxproj` 通过。
- `jq empty AITRANS/Resources/Assets.xcassets/.../Contents.json` 通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ... generic/platform=iOS Simulator ... CODE_SIGNING_ALLOWED=NO build` 通过。本次构建日志里 CoreSimulatorService 有沙盒警告，但构建最终成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ... generic/platform=iOS ... CODE_SIGNING_ALLOWED=NO build` 通过。
- 已确认 Debug iOS Simulator app bundle 内嵌 `llama.framework`。
- `git diff --check` 通过。
- `test/1.png` 漫画覆盖探针已在 iPhone 17 Pro 模拟器运行并导出：`output/probe_report.json`、`output/1_debug_boxes.png`、`output/1_translated_overlay.png` 均非空。调试图框线明显；覆盖图能盖住部分原文并绘制译文，但受 OCR 小块切分和当前 Local GGUF 翻译质量影响，结果仍不适合作为最终产品效果。
