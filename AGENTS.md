# AITRANS 后续 Codex Agent 提示词

你是接手 `AITRANS` 项目的 Codex 工程 agent。这个仓库是一个 SwiftUI iOS 本地 AI 翻译原型，当前重点不是普通翻译 UI，而是漫画截图 OCR、本地翻译、覆盖合成和探针诊断链路。请按本文工作，不要重新猜项目结构。

## 0. 接手前必须做

每次开始任务先读：

1. `README.md`
2. `git status --short`
3. 最近 git 记录：`git log --oneline -5`
4. 如果任务涉及漫画探针，再读：
   - `AITRANS/Services/MangaOverlayProbeService.swift`
   - `AITRANS/Services/TranslationSessionStore.swift`
   - `AITRANS/Models/TranscriptModels.swift`
   - `test/1.ground_truth.json`
   - 最新 `output/probe_report.json`
   - 最新 `output/1_ocr_probe_text.txt`

不要假设 README 里的历史数字都仍可作为验收。以最新 `probe_report.json` 和当前代码为准。

## 1. 项目定位

AITRANS 是 SwiftUI iOS 本地翻译原型：

- 默认 `MockGemmaService` 用于 UI 和数据流冒烟。
- `Local` 模式通过 `llama.cpp` 加载 GGUF，在设备或模拟器本地生成翻译。
- 当前内置最小模型是 `Gemma 3 270M IT QAT Q4_0`，它适合验证下载、加载、接口和闪退风险，不适合当翻译质量基准。
- 当前质量验证更应考虑 `Qwen2.5-0.5B-Instruct-GGUF` 的 `q4_k_m`，但不要在没有任务要求时擅自更换模型。

## 2. 当前重点链路

漫画覆盖翻译探针固定读取 bundle 内 `test/1.png`：

1. 裁掉浏览器 UI / 广告 / 底部导航。
2. 对漫画内容做 Vision OCR。
3. 合并 OCR observations 为逻辑文字块。
4. 用极简英译中 prompt 翻译：`把以下翻译成中文：`
5. 覆盖绘制译文；失败块也要绘制 `翻译失败 + OCR 原文`，不能静默跳过。
6. 输出调试 PNG、JSON 和纯文本报告到 App 沙盒 `Application Support/AITRANS/Output/`。
7. 再用 `scripts/export-probe-output.sh` 导出到项目根 `output/`。

输出目录每轮都必须清理，不能堆积旧图。当前报告会记录：

- `outputDirectoryCleaned`
- `outputCleanupRemovedItemCount`
- `outputFileCountAfterCleanup`
- `retainedOutputFiles`
- `outputCleanupPolicy`

## 3. 当前真实基线

截至 README v21，`test/1.png` 的可信基线是：

- 人工真值：`12` 条，`11 dialogue + 1 decorative`
- 整页 OCR 最终块：`totalBlocksDetected = 12`
- 可信匹配：`10 matched / 2 unmatched`
- 整页核心对话平均 OCR 相似度：`0.6196`
- 装饰标题平均 OCR 相似度：`0.8000`
- bubble-first 核心对话平均 OCR 相似度：`0.7397`
- clean text diagnostic：`4/11` 通过，`passRate = 0.3636`
- 高频专有名词损坏：`repeatedKeywordFailures = { "senpai's": 2 }`
- 双框架一致性：`consistencyPassed = true`

旧数字 `0.8378 / 0.8755` 已确认不可信。原因：

- 旧 `test/1.ground_truth.json` 不完整。
- 旧匹配逻辑会强行把 OCR 块配到不相关真值。
- 旧相似度算法对词序错乱过于宽容。

后续不要再用旧 `accuracyVsGroundTruth = 0.8378 / 0.8755` 做验收，只能作为历史对照。

## 4. 关键代码位置

- `AITRANS/Services/MangaOverlayProbeService.swift`
  - 漫画探针主流程、OCR、合并、渲染、报告、contact sheet。
- `AITRANS/Services/TranslationSessionStore.swift`
  - 翻译请求组装、候选选择、质量判定、clean text diagnostic、开发页状态。
- `AITRANS/Models/TranscriptModels.swift`
  - 探针报告模型、块模型、diagnostics、framework comparison、clean text diagnostic 模型。
- `AITRANS/Services/GemmaLocalService.swift`
  - 真实本地模型层，封装 llama.cpp 调用和输出清洗。
- `AITRANS/Services/LlamaRuntime.swift`
  - llama.cpp C API 封装。
- `test/1.ground_truth.json`
  - 当前漫画图人工真值，结构为 `{ "text": "...", "type": "dialogue|decorative" }`。
- `scripts/export-probe-output.sh`
  - 从 CoreSimulator App 容器导出探针输出到项目根 `output/`。

## 5. 探针输出文件

常见最新输出：

- `output/probe_report.json`
- `output/clean_text_diagnostic.json`
- `output/1_ocr_probe_text.txt`
- `output/1_probe_contact_sheet.png`
- `output/1_debug_boxes.png`
- `output/1_translated_overlay.png`
- `output/1_ocr_text_overlay.png`
- `output/1_bubble_text_overlay.png`
- `output/1_bubble_crops.png`
- `output/1_deterministic_correction_overlay.png`
- `output/1_deterministic_translation_overlay.png`
- `output/1_block_crops.png`
- `output/1_preprocessed_content.png`

看质量时优先打开 `1_probe_contact_sheet.png`，再按问题查看单图。

## 6. 必须遵守的质量原则

### 6.1 不隐藏失败

任何 OCR 块翻译失败，都必须：

- 保留在 `probe_report.json` 的 `blocks` 明细中。
- 在覆盖图上显示出来。
- 写入 `blockPassed = false` 和明确 `failureReasons`。
- 记录 `translationDecisionTrace` 和 `translationFailureDetail`。

不要因为失败就跳过绘制。

### 6.2 不用真值做生产决策

`test/1.ground_truth.json` 只能用于探针验证和统计，不能用于真实产品路径的候选选择。

候选选择必须依赖非真值信号，例如：

- OCR / Vision 置信度
- 文本质量评分
- raw OCR 与预处理 OCR 的词保留关系
- 合理的长度、字符、词序启发式

可以用真值验证这个策略是否变好，但不能把真值作为选择依据。

### 6.3 可信匹配必须能拒绝

真值匹配不能强行配最近项。低于阈值的块必须标为：

```json
"groundTruthMatch": "unmatched"
```

`unmatched` 块保留在报告里，但不纳入准确率平均。

### 6.4 相似度必须词序敏感

当前使用词级 Levenshtein 相似度，并保留旧相似度 `ocrLegacySimilarity` 作对照。不要退回对词序错乱过于宽容的算法。

报告中必须保留：

- `ocrGroundTruthSimilarity`
- `ocrLegacySimilarity`
- `wordOrderPreserved`

### 6.5 核心对话和装饰标题分开统计

`test/1.ground_truth.json` 中：

- `dialogue` 是核心对话。
- `decorative` 是装饰性标题，例如 `City Battler Offline Tournament 開催!!`。

平均准确率必须区分：

- `averageCoreDialogueOCRSimilarity`
- `averageDecorativeOCRSimilarity`

不要混在一起算一个看似好看的总分。

## 7. 翻译失败排查顺序

不要只看覆盖图猜原因。按这个顺序查：

1. `failureCategory`
2. `rawOutputClassification`
3. `candidateClassification`
4. `translationCandidate`
5. `failureReasons`
6. `qualityNotes`
7. `ocrProbeNotes`
8. `cleanTextDiagnostic`

判断规则：

- `ocrInputSuspect`：优先修 OCR、合并、裁切、纠错或气泡路径。
- `modelOutputFailure`：优先查模型 raw 输出、采样、prompt 或换模型。
- `translationLanguageQualityFailure`：模型给了中文或半中文，但候选质量差，比如太短、混英文、解释型输出。
- `ruleFalseFailureSuspected`：才考虑放宽判定规则。

如果 `likelyRuleFalseFailureBlocks = []`，不要声称“规则太严格”。当前多轮实测都指向：Gemma 270M 翻译能力和 OCR 输入错误是主要瓶颈。

## 8. 当前已知问题

1. Gemma 270M 翻译质量差：
   - clean text direct-to-model 只有 `4/11` 通过。
   - 常见问题：复读英文、混入 `Senpai's house` / `meaningless` / `disbanded`、输出解释或列表。

2. OCR 找到区域但文本仍错：
   - `THE CITY RATTLER / STATE IN A PEN DAYS.`
   - `THAT'S / WE'RE WHY / TRANINS SPECIAL`
   - `SUGSESTION THE / OVERRULED...`
   - `SENPAIS / SENPArS / LOSIC`

3. Vision `customWords` 对当前图最终合并文本没有明显改变：
   - `changedBlockIndexes = []`
   - 不能指望它单独解决常见词误识别。

4. 确定性 OCR 纠错能提升相似度，但翻译仍未必通过：
   - 修正 OCR 后，Gemma 270M 仍可能复读或输出英文。
   - 当前纠错候选只做探针对照，不替换主流程。

5. bubble-first 当前比整页 OCR 可信核心准确率更高，但仍是探针对照路径，不是主流程替换。

## 9. 后续优先级建议

按优先级推进，不要同时大改所有东西：

### P0：模型质量对比

下一轮优先引入或手动导入更强的小模型做对比，例如 `Qwen2.5-0.5B-Instruct-GGUF q4_k_m`。

必须复用现有诊断：

- 开发页 raw 探针
- `clean_text_diagnostic.json`
- 漫画覆盖探针

对比时记录：

- clean text pass rate
- raw 输出类型分布
- 是否仍复读英文
- 是否仍输出解释/列表
- 漫画端到端 `blockPassed`

### P1：OCR / bubble-first 继续降噪

目标不是让块数更高，而是让每个最终块更接近真实对话框。

重点：

- 减少 bubble-first 重复块。
- 让底部相邻气泡拆分更稳。
- 保留 `What are you even talking about?`、`We need to get results...` 等当前 bubble-first 找到而整页漏/差的块。
- 不要让浏览器 UI、广告、导航进入 OCR。

### P2：OCR 纠错策略

当前 LLM 纠错护栏有效，但 Gemma 270M 纠错不可用。后续可评估：

- 更强模型纠错。
- 更小范围的确定性规则。
- 专有名词词表。
- 只在相似度和词形证据足够时替换主翻译输入。

替换主流程前必须用探针证明收益。

### P3：产品化 UI

当前不优先。除非用户明确要求，否则不要先做：

- 开发页可视化开关 UI
- ReplayKit / 悬浮窗
- 音频功能扩展
- 大规模产品界面重构

## 10. 运行和验证命令

命令行构建：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

导出模拟器探针输出：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/export-probe-output.sh booted
```

如果需要指定设备，使用实际 device id：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/export-probe-output.sh <DEVICE_ID>
```

注意：读取 CoreSimulator App 容器通常需要更高权限；在受限环境中要请求批准。

JSON 检查：

```sh
python3 -m json.tool test/1.ground_truth.json
python3 -m json.tool output/probe_report.json
python3 -m json.tool output/clean_text_diagnostic.json
```

空白检查：

```sh
git diff --check
```

## 11. 每轮完成标准

每次改漫画探针或翻译链路，至少做到：

1. 构建通过，或明确说明未构建原因。
2. 重新跑探针，或明确说明未跑原因。
3. 导出最新 `output/`。
4. 检查 `probe_report.json`、`clean_text_diagnostic.json` 可解析。
5. 汇总关键数字：
   - `totalBlocksDetected`
   - `groundTruthMatchedBlocks`
   - `groundTruthUnmatchedBlocks`
   - `averageCoreDialogueOCRSimilarity`
   - `averageDecorativeOCRSimilarity`
   - `frameworkComparison.consistencyPassed`
   - `cleanTextDiagnostic.passRate`
   - `likelyRuleFalseFailureBlocks`
   - `translationFailureBreakdown`
6. 更新 `README.md` 的“近期优化记录”，写清：
   - 改了什么
   - 验证了什么
   - 新数字是什么
   - 仍有什么风险

## 12. 禁止事项

- 不要把旧 `0.8378 / 0.8755` 当新基线。
- 不要用 ground truth 参与生产候选选择。
- 不要失败时静默跳过覆盖绘制。
- 不要只看 `cjkCharacters > 0` 就判定翻译成功。
- 不要因为 clean text 失败就继续盲目调 OCR。
- 不要在未证明收益前把确定性纠错候选替换为主翻译输入。
- 不要把模型文件提交进仓库。
- 不要清理或回退用户未要求回退的改动。
- 不要大范围重构 SwiftUI UI，除非任务明确要求。

## 13. 给后续 Codex 的默认执行口径

接到新任务时，用下面口径工作：

1. 先读 README 和本文件，确认当前基线。
2. 再定位相关代码，不凭记忆改。
3. 小步修改，每一步都能用探针或 JSON 证明。
4. 数字从明细实时算，不维护两套统计。
5. 失败分类要诚实，不为好看调数字。
6. 如果 clean text 仍失败，优先讨论模型质量，而不是继续放宽规则。
7. 最终回复用中文，给出改动、验证、关键数字和产物路径。
