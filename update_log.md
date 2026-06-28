# 项目版本更新记录
本文记录 AITRANS 的正式版本、重要维护事项、关键决策和遗留问题。它不是流水账，细节证据优先看 `README.md`、`metrics/version_history.csv`、最新 `output/` 和 git 提交。

## 维护规则
- 每完成一个正式版本或重要任务后追加记录。
- 记录必须包含：版本或任务名、日期、核心变更、关键文件、验证结果、遗留事项。
- 文档整理、目录迁移、回滚、打捞等不伪装成新版本，写入“历史维护记录”。
- 若核心逻辑、测试规范或项目行为变化，必须同步更新本日志、`md/flow/flow.md`、`md/flow/flowchart.md` 或 `md/test/test.md`。
- 涉及漫画探针或翻译链路时，README 近期记录和 `metrics/version_history.csv` 必须 append-only 更新。

## 当前状态
日期：2026-06-28

当前项目是 SwiftUI iOS 本地翻译原型，主线已从普通翻译 UI 转到漫画截图 OCR、本地翻译、覆盖合成和探针诊断。最新可用基线来自当前 `output/probe_report.json`、`output/clean_text_diagnostic.json` 和 `metrics/version_history.csv` 的 v9 行：

- `sourceImage = test/1.png`
- `engineUsed = Local GGUF`
- `decodingMode = deterministic`
- `decodingSeed = 42`
- `totalBlocksDetected = 14`
- `groundTruthMatchedBlocks = 10`
- `groundTruthUnmatchedBlocks = 4`
- `averageCoreDialogueOCRSimilarity = 0.6131`
- `averageDecorativeOCRSimilarity = 0.8000`
- `wholePageAccuracyVsGroundTruth = 0.6131`
- `bubbleFirstAccuracyVsGroundTruth = 0.7397`
- `frameworkComparison.consistencyPassed = true`
- `cleanTextDiagnostic.passRate = 0.4545`
- `passedBlocks = 1`
- `failedBlocks = 13`
- `translationFailureBreakdown = { ocrInputSuspect: 10, translationLanguageQualityFailure: 3 }`
- `likelyRuleFalseFailureBlocks = []`

当前结论：

- 当前瓶颈是 OCR 文本质量和 Gemma 270M 翻译能力，不是覆盖绘制，也不是规则过严。
- bubble-first 对照核心准确率高于整页路径，但会漏掉 `Let's Battle!`，不能直接替换主流程。
- Vision `customWords` 对当前图最终合并文本无变化，`changedBlockIndexes = []`。
- 确定性 OCR 纠错能提升部分相似度，但翻译收益不稳定，仍只做探针对照。
- tagged batch 翻译分支格式崩坏，不替换逐块翻译。

## 历史记录
### 项目初始与多页 SwiftUI 原型
日期：2026-06 中旬
依据提交：`c988066` 到 `b7376d8`、`2b1a4f7`、`9a1a456`、`43f6890`、`ae7fe12`

核心变更：

- 建立 SwiftUI iOS App 骨架和 Xcode 工程。
- 形成文本翻译、历史、提示词、模型、Pro、开发调试等多页结构。
- `TranslationSessionStore` 成为状态和持久化中心。
- 本地状态落到 `Application Support/AITRANS/state.json`。
- 引入 Apple Vision OCR、Speech、StoreKit 2 占位和本地模型目录概念。

关键文件：

- `AITRANS/App/AITRANSApp.swift`
- `AITRANS/Views/ContentView.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/VisionOCRService.swift`
- `README.md`

验证结果：

- 历史记录显示 `plutil`、asset JSON 检查、iOS Simulator build 和 generic iOS build 曾通过。
- 当时 CoreSimulator service 不稳定，未完成完整点击交互测试。

遗留事项：

- UI 已可用，但主线质量依赖后续 OCR、模型和探针。

### LLM 接口、自测和 Local 模型路径
日期：2026-06 中旬
依据提交：`92f2a8c`、`84d00bb`、`c529c6b`

核心变更：

- 新增 LLM 接口自测和更严格的翻译探针。
- 确认本地模型路线优先走 `llama.cpp + GGUF`。
- 英译中自测开始拒绝返回原文、包含完整原文和不像目标语言的输出。
- 模型导入后统一复制为 `Application Support/Models/Gemma-1.5B/model.gguf`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Views/ContentView.swift`
- `README.md`

验证结果：

- `git diff --check` 通过。
- `plutil -lint` 通过。
- iOS Simulator build 和 generic iOS build 通过。

遗留事项：

- 当时 Local 仍偏接口接入和冒烟，真实翻译质量还需 raw 探针和模型对比。

### Developer Console、Pro 页和测试入口
日期：2026-06 中旬
依据提交：`6b7df35`、`7e552ed`、`9adb9a0`

核心变更：

- 新增开发者调试界面，展示真实 prompt、raw output 和错误。
- Pro 从首页迁移到独立底部 Tab。
- Pro 页新增 StoreKit 2 订阅骨架、长按麦克风同声传译、音频和 OCR 测试入口。
- 修复缺少 `test/` 空文件夹导致的编译失败。

关键文件：

- `AITRANS/Views/ContentView.swift`
- `AITRANS/Views/ProFeatureViews.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `test/.gitkeep`
- `README.md`

验证结果：

- README 记录了相关功能和入口。
- 编译失败由 `test/.gitkeep` 修复。

遗留事项：

- StoreKit 商品仍未上线，购买链路只能作为骨架。
- 语音和权限行为需要真机验证。

### 普通图片 OCR 翻译与漫画探针起步
日期：2026-06 中旬
依据提交：`f6f22e7`、`b95b97f`、`1daddcd`、`b5811b7`、`4a9eab4`、`4288e32`、`103d773`、`51fa18d`

核心变更：

- 普通图片翻译接入 Apple Vision OCR，支持按 bbox 旁贴或覆盖译文。
- 漫画截图 `test/1.png` 进入固定探针链路。
- 探针开始记录 OCR 坐标、逐块 prompt/raw output、debug boxes、translated overlay 和 JSON 报告。
- 引入内容裁切、2x 放大、多角度 OCR、空间聚类、预处理对照、OCR 纠错护栏、iOS 18+ RecognizeTextRequest 对比、customWords 和 bubble-first 初版对照。

关键文件：

- `AITRANS/Services/VisionOCRService.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `scripts/export-probe-output.sh`
- `test/1.png`
- `README.md`

验证结果：

- 多轮在 iPhone 17 Pro 模拟器运行 `test/1.png` 探针并导出 `output/`。
- 初期旧指标 `0.8378 / 0.8755` 后来被确认因真值不完整、强行匹配和旧相似度过宽而不可信。

遗留事项：

- OCR 已能定位文字区域，但文本误识别严重。
- Gemma 270M raw 输出常复读英文、空输出、占位或解释。

### v13-v20：失败诊断、质量门槛、纠错对照和总览输出
日期：2026-06 下旬
依据提交：`382d8ee` 到 `b5be534`

核心变更：

- 报告新增输出清理证明、`translationDecisionTrace`、`translationFailureDetail`、`translationFailureBreakdown`、`ocrProbeNotes`。
- `blockPassed` 质量门槛收紧，不再只凭含中文判定成功。
- 引入确定性 OCR 纠错候选、纠错覆盖图、纠错后翻译对照和 `1_ocr_probe_text.txt`。
- 新增 `1_bubble_text_overlay.png` 和 `1_probe_contact_sheet.png`，便于优先看总览图。
- `outputCleanupRemovedItemCount`、`outputFileCountAfterCleanup` 等字段证明输出目录每轮重建。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`
- `README.md`

验证结果：

- 多轮 `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` 通过。
- 多轮模拟器探针导出。
- `git diff --check` 通过。
- v20 时 `totalBlocksDetected = 12`、`passedBlocks = 0`、`failedBlocks = 12`，输出目录保留 14 个本轮文件。

遗留事项：

- 当前未完成的是翻译质量可用。
- Local Gemma 270M raw 输出不稳和 OCR 原句错误仍是主因。

### v21：结构化真值、可信匹配和新基线
日期：2026-06 下旬
依据：`README.md` 近期记录

核心变更：

- `test/1.ground_truth.json` 改为 12 条结构化真值：11 条 `dialogue`、1 条 `decorative`。
- 真值匹配改为可拒绝匹配，低于阈值标记 `unmatched`。
- 相似度改用词级 Levenshtein，保留旧 `ocrLegacySimilarity` 作对照。
- 核心对话和装饰标题分开统计。
- 新增 clean text diagnostic，直接把 dialogue 真值送入翻译链路。

关键文件：

- `test/1.ground_truth.json`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- 当轮可信基线为 `totalBlocksDetected = 12`、`10 matched / 2 unmatched`、核心对话 `0.6196`、装饰标题 `0.8000`、bubble-first `0.7397`、clean text `4/11`。

遗留事项：

- README 中旧 `0.8378 / 0.8755` 只能作为历史对照，不再用于验收。

### Agent 1-2：气泡几何约束和长图 slice OCR 诊断
日期：2026-06 下旬
依据提交：`ad56eae`、README Agent 1-2 记录

核心变更：

- 引入气泡候选几何约束，把 OCR candidate 分配到 `bubbleID`。
- 同一 bubble 内合并，跨 bubble 合并被拒绝。
- 新增长图竖向 slice OCR 诊断，长宽比超过阈值时分片 OCR、坐标还原和重叠去重。
- 合成长图机制测试验证 3 个竖向切片和 20% 重叠去重。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `md/koharu研究/v5work.md`
- `README.md`

验证结果：

- `test/1.png` 默认不触发 slice，主图结果保持 `14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`、装饰 `0.8000`。
- 合成长图触发 3 个竖向切片，重叠去重链路跑通。

遗留事项：

- 块数从 12 增至 14，是气泡边界拒绝旧跨气泡合并导致，不是 OCR 阈值变激进。
- 底部相邻气泡仍有分割问题。

### Agent 3：自适应 crop 与回退自测
日期：2026-06 下旬
依据提交：`da9d574`

核心变更：

- OCR 二次 crop 从固定比例扩张改为自适应 padding。
- 横排文本 y padding 大于 x padding，竖排相反。
- crop clamp 到所属气泡 bbox。
- 新增固定 crop 对照、自适应 crop 字段和人为超窄 crop 回退自测。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- build、模拟器探针、JSON 解析、`git diff --check` 通过。
- `totalBlocksDetected = 14`、`10 matched / 4 unmatched`、核心 OCR `0.6131`、装饰 `0.8000`、clean text `0.5455`。
- `cropFallbackSelfTest.triggered = true`。

遗留事项：

- 真实 `test/1.png` 未触发实际 fallback。
- 自适应 crop 有提升块也有变差块，不能按真值驱动生产选择。

### Agent 4-5：安全布局区和离屏碰撞检查
日期：2026-06 下旬
依据提交：`b65d904`

核心变更：

- 新增 `safeLayoutRect` 和 `safeLayoutSource`。
- 单块气泡使用气泡 bbox inset，多块同气泡使用分区安全区。
- 覆盖绘制前用离屏 alpha mask 检查文字越界，通过字号回退解决。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- build、完整探针、导出、JSON 解析、`git diff --check` 通过。
- `safeLayoutRectBlocks = 14`、`renderCollisionCheckedBlocks = 14`。
- `renderCollisionUnresolvedBlocks = []`、`renderTextTruncatedBlocks = []`。

遗留事项：

- 该轮改善渲染布局，不改变 OCR 准确率。

### Agent 6-7：glyph mask 和纯色背景填充
日期：2026-06 下旬
依据提交：`0ab70d0`、`08438e9`

核心变更：

- 对已归属气泡块生成轻量 glyph mask。
- mask 使用局部阈值、连通域过滤、OCR bbox 重叠约束和膨胀。
- 低纹理背景区域使用 RGB 中位数做纯色填充，高纹理或插画区域保留半透明覆盖。
- 未归属气泡块不生成 mask。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- build、完整探针、导出、JSON 解析、`git diff --check` 通过。
- `glyphMaskBlocks = 11`。
- 纯色填充触发块 `[2, 4, 6, 7]`。
- 未归属块 `5/11/13` 的 mask 为 0，符合气泡内约束。

遗留事项：

- glyph mask 和背景填充只影响覆盖可读性，不修 OCR 文本。

### Agent 8-9：tagged batch 诊断和 v5 汇总
日期：2026-06 下旬
依据提交：`6e1aa7f`、`613ca14`

核心变更：

- 新增 `batchTranslationComparison` tagged 批量翻译诊断。
- 批量分支只写报告，不替换逐块翻译、`blockPassed`、raw output 或 fallback。
- 完成 Agent 1-9 汇总，确认几何约束改善归属、裁切、渲染和跨气泡隔离。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `output/probe_report.json`

验证结果：

- batch 诊断负面：`parsedCases = 0`、`missingTags = [0...13]`、`unexpectedTags = [14...24]`。
- 逐块通过率 `0.0714`，批量通过率 `0`。
- 完整探针基线仍为 `14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`。

遗留事项：

- Gemma 270M 不适合 tagged batch 翻译主流程。
- 几何约束不能根治专有名词和 OCR 字符损坏。

### v6：确定性诊断解码和跨版本指标
日期：2026-06-27
依据提交：`d316ab2`、`metrics/version_history.csv`

核心变更：

- `LlamaRuntime` 支持按调用切换 sampled 和 deterministic 解码。
- 用户实际翻译和 summary 保持 sampled。
- raw 诊断、漫画探针、clean text、batch 和纠错翻译对照使用 deterministic，固定 `seed = 42`。
- 新增 `metrics/version_history.csv` 和 `scripts/append-version-metrics.py`。

关键文件：

- `AITRANS/Services/LlamaRuntime.swift`
- `AITRANS/Services/GemmaLocalService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `metrics/version_history.csv`
- `scripts/append-version-metrics.py`

验证结果：

- build、探针、导出、JSON 解析、`git diff --check` 通过。
- `deterministicDecodingCheck.outputsIdentical = true`。
- v6 指标：`14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`、clean text `0.4545`。

遗留事项：

- v4 缺完整逐块 OCR 快照，无法字符级回溯 `0.6196 -> 0.6131`。

### v7：底部气泡串扰诊断和保守 crop 修复
日期：2026-06-27
依据提交：`c5bd626`、`metrics/version_history.csv`

核心变更：

- 专项排查 `GET PESULTE...` 和 `What Whet...`。
- 当 OCR bbox 只覆盖合理气泡的一部分时，二次预处理 OCR 使用所属气泡 bbox 做 adaptive crop。
- 检测层 seed 分裂和小框优先实验因回归被回退。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `metrics/version_history.csv`

验证结果：

- build、完整探针、导出、JSON 解析、`git diff --check` 通过。
- 指标保持 `14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`、clean text `0.4545`。

遗留事项：

- 目标 OCR 没有实质改善。
- 后续应改气泡候选分割，而不是放宽跨气泡合并。

### v8：bubble-first 主流程切换评估
日期：2026-06-28
依据提交：`ce577b7`、`metrics/version_history.csv`

核心变更：

- 重新评估 bubble-first 能否替换整页主候选源。
- 结论是不推进架构改造，本轮只做证据收集和决策。

关键文件：

- `README.md`
- `metrics/version_history.csv`
- `output/probe_report.json`

验证结果：

- build、模拟器探针、导出、JSON 解析、`git diff --check` 通过。
- `blocksFoundByBoth = 8`。
- `blocksOnlyInWholePage = ["Let's Battle!"]`。
- `blocksOnlyInBubbleFirst = ["What are you even talking about?", "We need to get results at this tournament to save the gaming club from being disbanded."]`。
- `frameworkComparison.consistencyPassed = true`。

遗留事项：

- bubble-first 可作为未来融合候选，但不能直接独占主流程。
- 未来若推进，需要 whole-page 真实内容兜底和去重报告字段。

### v9：词表、确定性纠错和 OCR 错误结构复盘
日期：2026-06-28
依据提交：`d3080c4`、`metrics/version_history.csv`、`md/koharu研究/v6～9work.md`

核心变更：

- 复测 Vision `customWords`：开关词表最终文本无变化。
- 复盘确定性 OCR 纠错候选：只保留诊断对照，不进入主流程。
- 总结低相似和未匹配块结构，确认问题不是 `Senpai` 单点，而是专有名词和常见词混淆共同存在。

关键文件：

- `README.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `md/koharu研究/v6～9work.md`

验证结果：

- 最新指标：`totalBlocksDetected = 14`、`10 matched / 4 unmatched`、核心 OCR `0.6131`、装饰 `0.8000`、whole-page `0.6131`、bubble-first `0.7397`、clean text `0.4545`、`passedBlocks = 1`、`failedBlocks = 13`。
- `translationFailureBreakdown = { ocrInputSuspect: 10, translationLanguageQualityFailure: 3 }`。
- `likelyRuleFalseFailureBlocks = []`。

遗留事项：

- 文字区域检测和 OCR 文本质量仍是核心瓶颈。
- 下一轮优先做更强小模型对比，如 Qwen2.5-0.5B-Instruct-GGUF q4_k_m，或推进 bubble-first + whole-page 融合，而不是继续放宽质量规则。

## 历史维护记录
### 建立多 Agent 迭代文档体系
日期：2026-06-28

核心变更：

- 新增标准入口 `AGENT.md`，保留 `AGENTS.md` 作为漫画探针详细约束。
- 新增 `md/prompt/README.md`、`md/test/test.md`、`md/flow/flow.md`、`md/flow/flowchart.md`。
- 根据 git 记录、README 和指标 CSV 整理本 `update_log.md`。

关键文件：

- `AGENT.md`
- `update_log.md`
- `md/prompt/README.md`
- `md/test/test.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`

验证结果：

- 本轮为文档-only 任务，按 `md/test/test.md` 只需静态检查。

遗留事项：

- 后续每轮由 Agent A 按 `md/prompt/README.md` 的命名规则写入具体实现提示词。
