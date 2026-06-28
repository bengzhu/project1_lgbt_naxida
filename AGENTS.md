# AGENTS.md
本文是 AITRANS 的核心入口记忆、项目总览、基本规则和多 Agent 工作流。保持精简；历史细节看 `update_log.md`，当前架构看 `md/flow/flow.md`，测试选择看 `md/test/test.md`。

## 1. 项目总览
AITRANS 是 SwiftUI iOS 本地 AI 翻译原型。当前重点不是普通翻译 UI，而是漫画截图 OCR、本地翻译、覆盖合成和探针诊断链路。

核心事实：

- 默认 `MockGemmaService` 用于 UI 和数据流冒烟。
- `Local` 模式通过 `GemmaLocalService` + `LlamaRuntime` + `llama.cpp` 加载 GGUF。
- 当前内置最小模型是 `Gemma 3 270M IT QAT Q4_0`，适合验证下载、加载、接口和闪退风险，不适合当翻译质量基准。
- 质量对比优先考虑更强小模型，例如 `Qwen2.5-0.5B-Instruct-GGUF q4_k_m`，但不要在没有任务要求时擅自更换模型。

## 2. 必读顺序
每轮开始先读：

1. `README.md`
2. `AGENTS.md`
3. `git status --short`
4. `git log --oneline -5`
5. `update_log.md`
6. `md/flow/flow.md`
7. `md/flow/flowchart.md`
8. `md/test/test.md`

涉及漫画探针、OCR、覆盖绘制、翻译质量或报告模型时，继续读：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `test/1.ground_truth.json`
- 最新 `output/probe_report.json`
- 最新 `output/clean_text_diagnostic.json`
- 最新 `output/1_ocr_probe_text.txt`

不要假设 README 的历史数字仍可验收；以当前代码、最新 `output/`、`metrics/version_history.csv` 和实际测试结果为准。

## 3. 核心架构边界
- `TranslationSessionStore` 是 UI 状态、模型调用、历史、诊断和持久化的统一调度中心。
- UI 层只触发 store 方法，不绕开 store 直接改持久化、模型状态或报告状态。
- 普通图片 OCR 使用 `VisionOCRService`；漫画覆盖探针使用 `MangaOverlayProbeService` 的独立诊断链路。
- 用户实际翻译和 summary 走 sampled 解码；漫画探针、raw 诊断、clean text、batch 对照和纠错翻译对照走 deterministic 解码。
- `test/1.ground_truth.json` 只能用于探针验证和统计，不能用于真实产品路径或生产候选选择。
- 模型文件不进仓库。

## 4. 漫画探针硬规则
漫画覆盖翻译探针固定读取 bundle 内 `test/1.png`：

```text
test/1.png
  -> 裁掉浏览器 UI / 广告 / 底部导航
  -> Vision OCR
  -> 合并 OCR observations 为逻辑文字块
  -> 极简英译中 prompt：把以下翻译成中文：
  -> 覆盖绘制译文或失败文本
  -> 输出 JSON / TXT / PNG 到 App 沙盒 Output
  -> scripts/export-probe-output.sh 导出到项目根 output/
```

必须遵守：

- 失败块必须保留在 `probe_report.json` 的 `blocks` 明细中。
- 失败块必须在覆盖图上显示 `翻译失败 + OCR 原文`，不能静默跳过。
- 失败块必须写入 `blockPassed = false`、`failureReasons`、`translationDecisionTrace`、`translationFailureDetail`。
- 输出目录每轮必须清理，不能混入旧 PNG / JSON。
- 可信匹配必须能拒绝；低于阈值写 `groundTruthMatch = "unmatched"`，且不纳入平均准确率。
- OCR 相似度使用词级 Levenshtein；保留 `ocrLegacySimilarity` 和 `wordOrderPreserved`。
- 核心对话 `dialogue` 和装饰标题 `decorative` 必须分开统计。

禁止：

- 不要用 ground truth 做生产候选选择。
- 不要把旧 `accuracyVsGroundTruth = 0.8378 / 0.8755` 当当前基线。
- 不要只看 `cjkCharacters > 0` 判定翻译成功。
- 不要因为 clean text 失败就继续盲目调 OCR。
- 不要在未证明收益前把 deterministic correction、bubble-first 或 batch translation 替换为主流程。

## 5. 当前真实基线
当前可信基线以最新 `output/probe_report.json`、`output/clean_text_diagnostic.json` 和 `metrics/version_history.csv` 为准。最近记录的 v12 / 当前输出基线是：

- `configuration.currentBlockSource = fusedWholePageBubble`
- `totalBlocksDetected = 13`
- `postFusionCleanup.blockCountBeforeCleanup = 16`
- `postFusionCleanup.blockCountAfterCleanup = 13`
- `postFusionCleanup.rejectedBlockCount = 3`
- `groundTruthMatchedBlocks = 13`
- `groundTruthUnmatchedBlocks = 0`
- `averageCoreDialogueOCRSimilarity = 0.7106`
- `averageDecorativeOCRSimilarity = 0.8000`
- `wholePageAccuracyVsGroundTruth = 0.5972`
- `bubbleFirstAccuracyVsGroundTruth = 0.7300`
- `frameworkComparison.consistencyPassed = true`
- `fusionComparison.consistencyPassed = true`
- `fusion.fused.accuracyVsGroundTruth = 0.7384`
- `cleanTextDiagnostic.passRate = 0.4545`
- `textRegionCropReport.totalRegions = 13`
- `textRegionCropReport.cropSucceededCount = 10`
- `textRegionCropReport.adoptedCount = 0`
- `textRegionCropReport.rejectedCount = 13`
- `passedBlocks = 1`
- `failedBlocks = 12`
- `translationFailureBreakdown = { modelOutputFailure: 2, ocrInputSuspect: 7, translationLanguageQualityFailure: 3 }`
- `likelyRuleFalseFailureBlocks = []`

当前结论：

- 主要瓶颈是 OCR 文本质量和 Gemma 270M 翻译能力，不是覆盖绘制，也不是规则过严。
- Vision `customWords` 对当前图最终合并文本无明显改变。
- deterministic correction 只做探针对照，不替换主翻译输入。
- 主流程已切到 whole-page + bubble-first 融合；`Let's Battle!` 没丢，bubble-first 独有的两条真实内容也进入融合结果。
- post-fusion cleanup 已把 16 个融合块压到 13 个，拒绝重复/碎片块但保留三条关键真实内容。
- TextRegion crop OCR 候选层已接入报告，但本轮 13 个块全部被护栏回退，没有替换主翻译输入。
- `bubbleAudits` 只做气泡分割风险审计，不替换主流程；当前重点观察 `bubbleID 4/6/7`。
- tagged batch translation 当前格式崩坏，只保留诊断分支。

## 6. 翻译失败排查顺序
不要只看覆盖图猜原因。按顺序查：

1. `failureCategory`
2. `rawOutputClassification`
3. `candidateClassification`
4. `translationCandidate`
5. `failureReasons`
6. `qualityNotes`
7. `ocrProbeNotes`
8. `cleanTextDiagnostic`

判断口径：

- `ocrInputSuspect`：优先修 OCR、合并、裁切、纠错或气泡路径。
- `modelOutputFailure`：优先查模型 raw 输出、采样、prompt 或换模型。
- `translationLanguageQualityFailure`：模型给了中文或半中文，但候选太短、混英文、像解释或列表。
- `ruleFalseFailureSuspected`：才考虑放宽判定规则。

如果 `likelyRuleFalseFailureBlocks = []`，不要声称“规则太严格”。

## 7. Agent A/B/C 迭代工作流
### 人工
人工提出目标、边界、禁止项、验收标准和测试要求，并把入口文档、历史日志、核心流程、测试规范和相关上下文交给 Agent A。

### Agent A：目标分析与提示词
Agent A 默认不直接写代码。必须读取入口文档、历史日志、核心流程、测试规范和相关源码，明确本轮目标、非目标、边界、依赖、风险、关键文件、测试要求和验收标准。输出写给 Agent B 的版本化提示词，保存到 `md/prompt/vX（阶段）/vX.Y（任务）.md`。

### Agent B：实现与测试
Agent B 按 Agent A 提示词小步实现，不做无关重构。必须按 `md/test/test.md` 选择测试层级，记录具体命令和结果，说明未跑测试的原因，不伪造验证，不回滚用户或其他 Agent 的改动。

### Agent C：验收与核心文档更新
Agent C 查看实际 diff，核对测试结果，检查架构边界、测试充分性、文档同步和未说明风险。通过后更新 `md/flow/flow.md`、`md/flow/flowchart.md`，必要时追加 `update_log.md` 和 `metrics/version_history.csv`。

## 8. 测试规则
- 文档-only 修改至少运行 `git diff --check`。
- Swift 或 Xcode 工程修改至少运行命令行 build。
- 漫画探针、翻译链路或报告模型修改必须重新跑探针、导出最新 `output/`、解析 JSON，并汇总关键数字。
- 读取 CoreSimulator App 容器通常需要更高权限；受限环境中要请求批准或明确说明未导出原因。

常用命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/export-probe-output.sh booted
```

```sh
python3 -m json.tool test/1.ground_truth.json
python3 -m json.tool output/probe_report.json
python3 -m json.tool output/clean_text_diagnostic.json
git diff --check
```

## 9. 文档规则
- `AGENTS.md` 是唯一核心入口文档。
- `update_log.md` 记录版本历史、关键决策、验证结果和遗留问题。
- `md/flow/flow.md` 只写当前真实架构和运行流程。
- `md/flow/flowchart.md` 必须与 `flow.md` 同步。
- `md/test/test.md` 是测试选择依据。
- `md/prompt/` 保存 Agent A 的版本化实现提示词。
- 功能更新或 bug 修复后，按影响同步更新 README 近期记录、`update_log.md`、flow/test 文档和 `metrics/version_history.csv`。

## 10. 交付格式
最终回复使用中文，至少包含：

- 改了什么。
- 关键文件。
- 已运行的验证命令和结果。
- 未运行的测试及原因。
- 涉及漫画探针或翻译链路时，汇总关键数字。
- 已知风险和下一步建议。
