# AITRANS v5 Koharu 轻量几何优化工作总结

日期：2026-06-27  
范围：Codex 任务 v5，Agent 0-9  
依据：当前代码、README 近期记录、git 记录、`output/probe_report.json`、`output/clean_text_diagnostic.json`、`md/koharu研究/koharu图像识别链路研究.md`

## 结论先行

相对 v5 开始前，这轮让主流程的“几何约束、诊断可解释性、覆盖渲染可靠性”明显变好，但没有证明主流程 OCR 文本准确率有显著提升。

最重要的变化不是 Apple Vision OCR 本身变强，而是原来“整页 OCR observations -> 空间合并 -> 翻译 -> 粗覆盖”的链条，被补上了气泡 ID、跨气泡禁止合并、长图 slice 诊断、自适应 crop、气泡安全区、离屏碰撞检查、glyph mask、纯色背景填充、batch tagged 翻译对照等中间层。现在报告能解释每个块属于哪个气泡、是否跨气泡合并被拒绝、crop 是否被气泡限制、渲染是否越界、glyph mask 是否生成、纯色填充是否触发。

但如果只问“OCR 读出来的英文有没有明显更准”，答案要保守：主流程核心对话 OCR 相似度从 v5 前基线约 `0.6196` 到当前 `0.6131`，没有提升；`totalBlocksDetected` 从 12 到 14，主要是气泡边界硬约束拆开了旧的错误合并，不是 OCR 文字识别变准。bubble-first 对照仍比整页主流程高，当前为 `0.7397`，但它仍是对照路径，不是主流程替换。

## 当前最终数字

最新 `output/probe_report.json`：

- `totalBlocksDetected = 14`
- `groundTruthMatchedBlocks = 10`
- `groundTruthUnmatchedBlocks = 4`
- `averageCoreDialogueOCRSimilarity = 0.6131`
- `averageDecorativeOCRSimilarity = 0.8000`
- `frameworkComparison.consistencyPassed = true`
- `wholePage.accuracyVsGroundTruth = 0.6131`
- `bubbleFirst.accuracyVsGroundTruth = 0.7397`
- `cleanTextDiagnostic.passRate = 0.3636`
- `passedBlocks = 1`
- `failedBlocks = 13`
- `translationFailureBreakdown = { ocrInputSuspect: 9, translationLanguageQualityFailure: 4 }`
- `likelyRuleFalseFailureBlocks = []`
- `glyphMaskBlocks = 11`
- `backgroundFillAppliedBlocks = [2, 4, 6, 7]`
- `backgroundFillSkippedBlocks = [0, 1, 3, 8, 9, 10, 12]`
- `renderCollisionUnresolvedBlocks = []`
- `renderTextTruncatedBlocks = []`
- `syntheticSliceOCR.residualOverlapDuplicateCount = 0`
- `batchTranslationComparison.batchPassRate = 0`

注意：`cleanTextDiagnostic.passRate` 和翻译通过块数受本地 LLM 非确定性影响，不能拿单次值当几何 Agent 的收益。原因见后文疑点排查。

## v5 前后的主流程变化

v5 前可信基线来自 README v21：

- 人工真值 12 条：11 dialogue + 1 decorative。
- 主流程整页 OCR 最终块 `totalBlocksDetected = 12`。
- 可信匹配 `10 matched / 2 unmatched`。
- 核心对话 OCR 相似度 `0.6196`。
- 装饰标题 OCR 相似度 `0.8000`。
- bubble-first 核心 OCR 相似度 `0.7397`。
- clean text diagnostic `4/11`，`passRate = 0.3636`。

v5 后：

- 主流程最终块 `14`，可信匹配仍为 `10`，未匹配增至 `4`。
- 核心对话 OCR 相似度 `0.6131`，略低于 v5 前 `0.6196`。
- 装饰标题仍为 `0.8000`。
- bubble-first 对照仍为 `0.7397`。
- 几何和渲染指标大量补全，且跨气泡合并、crop clamp、safe layout、碰撞检查、glyph mask、背景填充都有明细证据。

所以，“主流程变好”要分层回答：

- OCR 文字准确率：没有明确变好。
- OCR/文本块几何归属：变好。每块有 `bubbleID` 或明确未归属，跨气泡合并会被拒绝。
- 长图机制：变好。合成长图触发 slice OCR，并完成坐标还原和重叠去重。
- crop 控制：变好。自适应 padding 和气泡 clamp 已进入诊断链路。
- 覆盖渲染：明显变好。所有块有安全区，越界通过字号回退解决，无未解决碰撞和截断。
- 清字/背景覆盖准备：变好。已有 glyph mask 和低方差纯色气泡填充。
- 翻译质量：没有因 v5 几何优化变好，主要瓶颈仍是 Gemma 270M 和 OCR 输入错误。

## 9 个 Agent 做了什么

### Agent 0：现状核查

确认 v4 基线已经修正：真值补全为 12 条，相似度换成词序敏感的词级 Levenshtein，双框架对比改为从明细现场计算并做一致性校验，`clean_text_diagnostic.json` 用来判断模型/判定链路，不参与生产候选选择。

当时明确的真实基线是：整页主流程 `12` 块，可信核心对话 OCR 相似度 `0.6196`，bubble-first `0.7397`，clean text `4/11 = 0.3636`。

### Agent 1：气泡升级为主几何信号

新增结构化气泡和文字区域诊断：

- 气泡候选：`id`、`bbox`、`area`、`confidence`。
- 文字区域：`bbox`、`bubbleID`、`source`、`confidence`、assignment method。
- 块级字段：`bubbleID`、`bubbleAssignmentMethod`、`crossBubbleMergeRejected`。

每个 Vision OCR observation 会按重叠面积或中心点投票归属气泡；归属不明确则保留 `bubbleID = null`。合并逻辑改为同气泡内合并，跨气泡禁止合并。OCR crop 也被限制在所属气泡 bbox 内。

实际效果：块数从 12 变 14，因为气泡边界变成硬约束后，底部旧的跨气泡合并被拆开。`GET PESULTE...` 和 `What Whet...` 没有被 OCR 修好，但已有明确归属，不再靠跨气泡合并凑分。

### Agent 2：长图 / slice OCR

新增长宽比阈值触发的竖向切片 OCR：

- `test/1.png` 内容区长宽比约 `1.39 <= 2.85`，默认不触发。
- 合成测试图 `synthetic:test/1.png-content-x3` 长宽比 `4.17 > 2.85`，触发 3 个竖向切片。
- 切片间 20% 重叠。
- slice bbox 的 y 坐标还原到原图。
- 用 IoU、包含关系、文本相似度、`bubbleID` 去重。
- 新增 `sliceIndex`、`sliceOverlapDeduped`、`syntheticSliceOCR`。

当前合成长图结果：raw 候选 `667`，重叠去重 `8`，最终 `659`，`residualOverlapDuplicateCount = 0`。这证明机制跑通，但不是主流程 OCR 准确率提升。

### Agent 3：OCR crop 自适应扩张

把固定比例 crop 扩张改为按字号/方向自适应：

- 用 bbox 短边估算字号。
- 横排 y padding 大于 x padding。
- 竖排反过来。
- crop clamp 到所属气泡 bbox。
- 保留固定 crop 作为对照。
- 增加丢词回退机制和人为超窄 crop 自测。

新增字段包括 `cropPaddingX`、`cropPaddingY`、`cropClampedByBubble`、`cropCandidatePreservesRawWords`、`adaptivePreprocessingOcrText`、`fixedPreprocessingOcrText`、`cropFallbackTriggered`、`cropStrategyUsed`。

实际效果：自适应 crop 相对固定 crop 有好有坏，README 记录更好块 `[1, 6, 8]`，更差块 `[2, 3, 5, 12]`，接近持平 `[0, 4, 13]`。这一步改善了 crop 的可控性，但没有证明整体 OCR 分数提升。

### Agent 4：气泡安全区

新增 bbox inset 版安全区，不做 distance transform：

- 单块气泡使用气泡 bbox inset。
- 多块同气泡做分区安全区，不把多个文字块抢同一大区域。
- 新增 `safeLayoutRect`、`safeLayoutSource`。

真实多块同气泡案例：`bubbleID = 6` 的块 8/9 分别有独立安全区，没有合并抢位。

### Agent 5：离屏渲染碰撞检查和字号回退

覆盖绘制前先生成离屏文字 sprite/mask，扫描非透明像素是否落在安全区内。若越界，缩小字号重排，直到不越界或达到最小字号/截断策略。

新增字段：

- `renderCollisionChecked`
- `renderCollisionInitialOverflow`
- `renderCollisionResolved`
- `renderFontSize`
- `renderMinFontSizeReached`
- `renderTextTruncated`
- `renderNonTransparentBounds`

当前结果：`renderCollisionCheckedBlocks = 14`，`renderCollisionUnresolvedBlocks = []`，`renderTextTruncatedBlocks = []`。长句 `SUGSESTION THE / OVERRULED...` 能通过字号回退落在安全区内。

### Agent 6：轻量 glyph mask

新增传统图像处理版文字像素 mask：

- 在气泡 crop 内灰度化。
- 用局部阈值二值化。
- 连通域过滤过大/过小区域。
- 连通域必须在气泡内部，且与 Vision OCR bbox 有重叠。
- 对筛选 glyph 区域做 2px 膨胀。
- 新增 `glyphMaskPixelCount`、`glyphMaskRect`、`glyphMaskFillRects`。

当前结果：`glyphMaskBlocks = 11`。未归属块 5/11/13 的 glyph mask 为 0，符合“必须落在气泡内部”的硬约束。

### Agent 7：纯色气泡背景填充

在 glyph mask 外采样气泡背景：

- 用 RGB 中位数估计背景色。
- 计算颜色标准差。
- 低于阈值才当纯色气泡。
- 只填充 glyph mask 膨胀区域，不填整个 bbox。
- 高方差背景仍走原半透明策略。

当前纯色填充块为 `[2, 4, 6, 7]`；背景复杂或插画/线条穿过区域 `[0, 1, 3, 8, 9, 10, 12]` 保留原策略。这改善的是覆盖清洁度，不是 OCR 准确率。

### Agent 8：批量 tagged 翻译对照

新增 batch 诊断分支：

- 把 14 个块格式化成 `[0] text`、`[1] text`。
- 要求模型保留编号、不合并、不拆分、不解释。
- 解析 `missingTags`、`duplicateTags`、`outOfOrderTags`、unexpected tags。
- 结果只写 `batchTranslationComparison`，不替换逐块翻译、不替换 `blockPassed`、不替换逐块 raw output。

当前结果是负面：

- `totalCases = 14`
- `parsedCases = 0`
- `missingTags = [0...13]`
- `unexpectedTags = [14...24]`
- `duplicateTags = []`
- `outOfOrderTags = []`
- `sequentialPassRate = 0.0714`
- `batchPassRate = 0`
- `batchBetterBy = -0.0714`

结论：当前 Gemma 270M tagged batch 格式崩掉，不能作为主流程，只保留诊断价值。

### Agent 9：汇总验收和 README 更新

最终跑完整链路，导出 `output/`，并在 README 写入 Agent 8/9 总结。重点案例状态：

- `GET PESULTE / SAMING CLUE TO SAVE THE / POOM BENG`：仍未匹配，OCR 相似度约 `0.25`。有独立 `bubbleID = 5`，纯色 glyph 填充生效，没有为了凑分跨气泡合并。
- `What Whet are / every you! / talking`：仍未匹配，OCR 相似度约 `0.3333`。bubble-first 对照能找到真值 `What are you even talking about?`，说明方向对，但整页主 OCR 仍差。
- `THE CITY RATTLER / STATE IN A PEN DAYS.`：仍错，确定性候选可修为 `THE CITY BATTLER / STARTS IN A FEW DAYS.`，但不替换主流程。
- `SUGSESTION THE / OVERRULED...`：只确定性修正到 `SUGGESTION...`，背景复杂，未做纯色填充。
- `SENPAIS / SENPArS / LOSIC`：仍存在，确定性候选可修到 `SENPAI'S ... LOGIC`，但几何约束不能根治专有名词损坏。

## 当前识别链路

当前漫画探针主链路是：

1. 固定读取 `test/1.png`。
2. 裁掉浏览器 UI、广告、底部导航。
3. 对漫画内容 2x 放大，跑 0/90/180/270 Apple Vision OCR。
4. 生成气泡候选，并给 OCR observation 分配 `bubbleID`。
5. 合并 OCR 候选时只允许同气泡内合并，跨气泡拒绝。
6. 生成主流程文字块，每块保留 bbox、bubbleID、assignment method、source、confidence。
7. 对块做 OCR crop 复识别诊断，crop 会按字号/方向自适应 padding，并 clamp 到所属气泡。
8. 确定性 OCR 纠错只作探针对照，不替换主流程输入。
9. 逐块送当前 Local/Mock 翻译，记录 prompt、raw output、candidate、失败分类。
10. batch tagged 翻译作为对照分支，不替换逐块主流程。
11. 翻译后计算气泡安全区、glyph mask、背景色、离屏碰撞和字号回退。
12. 渲染覆盖图、OCR overlay、bubble overlay、contact sheet、JSON、纯文本报告。
13. 运行 clean text diagnostic，用真值文本直送模型，判断模型质量。
14. 运行 bubble-first、slice OCR 等对照诊断。

## 两个数字波动疑点的解释

### 疑点 1：cleanTextDiagnostic.passRate 为什么在 Agent 间波动

结论：这是本地 LLM 非确定性造成的噪声，不是 Agent 2/3/6/7 让 clean text 变好或变差。

证据：

1. `runCleanTextDiagnostic` 只读取 `test/1.ground_truth.json` 的 dialogue 真值，逐条调用 `localService.rawTranslationProbe(for:)`，完全跳过 OCR、气泡、crop、glyph mask 和渲染。
2. `LlamaRuntime.loadModelIfNeededLocked` 的 sampler 使用了：
   - `llama_sampler_init_top_k(40)`
   - `llama_sampler_init_top_p(0.90, 1)`
   - `llama_sampler_init_min_p(0.05, 1)`
   - `llama_sampler_init_temp(0.2)`
   - `llama_sampler_init_dist(UInt32.random(in: 1...UInt32.max))`
3. 也就是说每次模型加载时 seed 是随机的，且 temperature/top-p/top-k 采样都不是贪心确定性解码。即使输入完全一样，输出也可能不同。
4. 近期 git/README 记录里，clean text 从 Agent 1 的 `0.4545` 到 Agent 3 的 `0.5455`，再到 Agent 6/7 的 `0.4545`，最终当前是 `0.3636`。这些 Agent 的核心改动分别是气泡几何、crop、glyph/background/render，不应影响“真值文本直送模型”的输入。

所以，`5/11`、`6/11`、`4/11` 之间不能解读为 OCR/几何算法收益。它只能说明当前 Gemma 270M 翻译链路本身不稳定。后续若要把 clean text 当可比较指标，必须固定 seed，或改成 temperature 0 / greedy，或每个版本跑多次取均值和方差。

### 疑点 2：纯渲染 Agent 后 translationFailureBreakdown 为什么会回退

结论：同样主要是 LLM 非确定性噪声；没有发现 Agent 6/7 把 glyph/background 逻辑耦合进 OCR 或翻译判定。

证据：

1. 主流程顺序是先逐块翻译，之后才调用 `applySafeLayoutAndRenderingDiagnostics`。
2. `applySafeLayoutAndRenderingDiagnostics` 只写入这些字段：
   - `safeLayoutRect`
   - `safeLayoutSource`
   - `glyphMaskPixelCount`
   - `glyphMaskRect`
   - `glyphMaskFillRects`
   - `backgroundFillApplied`
   - `backgroundColorStdDev`
   - `backgroundFillColor`
   - `renderCollision...`
3. 它没有修改：
   - `finalTextUsedForTranslation`
   - `rawOutput`
   - `translationCandidate`
   - `candidateClassification`
   - `failureCategory`
   - `blockPassed`
4. `translationFailureBreakdown` 是 `makeMangaOverlayProbeDiagnostics` 从最终 `blocks` 明细里统计未通过块的 `failureCategory`。而 `failureCategory/blockPassed` 已经在 `translateMangaProbeBlock` 阶段由本地模型 raw output、candidate、质量规则、OCR 风险决定。
5. 因为 `translateMangaProbeBlock` 也走 `localService.rawTranslationProbe`，它和 clean text 一样受随机 seed 和采样影响。相同 OCR 输入在不同探针运行中可能得到不同 raw output，导致通过块数和失败分类变化。

因此，Agent 6/7 后通过块数从 2 变 1，不应解读为 glyph mask 或背景填充让翻译变差。更准确的说法是：本轮报告中的翻译通过率是单次非确定性模型输出，不能作为纯几何/渲染 Agent 的收益指标。Agent 6/7 的可信指标应看 `glyphMaskBlocks`、`backgroundFillAppliedBlocks`、`backgroundFillSkippedBlocks`、`renderCollision...`，而不是 clean text pass rate 或翻译通过块数。

## 相比 Koharu 已经补上的能力

已补上或部分补上的 Koharu 思路：

- 气泡从普通 bbox 对照升级为主几何信号：已有 `bubbleID`、bubble assignment、跨气泡合并拒绝。
- 长图 slice OCR：已有阈值触发、20% 重叠、坐标还原、去重和合成样本测试。
- crop 自适应扩张：已有字号/方向 padding 和气泡 clamp。
- 气泡安全区：已有 bbox inset 简化版和多块同气泡分区。
- 渲染碰撞检查：已有离屏文字 mask、字号回退、非透明像素边界记录。
- glyph mask：已有局部阈值、连通域过滤、OCR bbox 重叠约束和膨胀。
- 纯色气泡背景填充：已有中位数背景色、标准差判断和 glyph 区域局部填充。
- tagged batch translation：已有诊断分支和 tag 解析失败记录。

这些都是 Koharu 报告里 P0/P1/P2 的轻量算法方向，且没有引入新模型、没有迁移 Koharu 权重。

## 相比 Koharu 仍缺什么

差距仍然很大，主要在模型级版面/分割能力：

- 没有独立 text detector。AITRANS 仍依赖 Apple Vision OCR observations 反推文字块；Koharu 有 detector 先给 TextBoxes。
- 没有真实气泡实例 mask。AITRANS 目前主要是 bbox/近似几何；Koharu 有 speech-bubble-segmentation 输出 ID mask。
- 没有 text segmentation 概率图。AITRANS 的 glyph mask 是传统阈值和连通域，Koharu 有 comic-text-detector-seg。
- 没有 line polygon/透视矫正。AITRANS 只做 0/90/180/270 和 bbox crop；Koharu 可对文字行 polygon 做 warp。
- 没有 distance transform 安全区。AITRANS 当前是 bbox inset 简化版；Koharu 能基于 bubble mask 找最大安全矩形。
- 没有 inpainting。AITRANS 只做半透明覆盖或纯色 glyph 填充；Koharu 有 LAMA/Flux 等修补策略。
- 没有字体/颜色预测。AITRANS 覆盖文字仍是通用排版；Koharu 有 font detector 和 renderer。
- batch translation 对当前小模型不可用。Koharu 的 tagged batch 依赖更能遵守格式的模型；AITRANS 当前 Gemma 270M 会 tag 崩坏。

## 未来改进建议

短期优先：

1. 固定本地 LLM 探针随机性：固定 llama sampler seed，或提供 deterministic probe mode。否则 clean text 和翻译通过率不能做版本间精确对比。
2. 把 bubble-first 更稳地接入主流程候选，但仍要保持跨气泡禁止合并，不用真值做选择。
3. 优化底部相邻气泡：`GET PESULTE...` 和 `What Whet...` 说明当前整页 OCR 仍串扰/误读。
4. 加强专有名词和常见 OCR 混淆处理：`SENPAIS/SENPArS/LOSIC`、`RATTLER/PEN DAYS` 这类问题几何层解决不了。
5. 对 slice OCR 从合成样本扩展到真实长截图样本。

中期：

1. 实现基于气泡 mask 的 distance transform safe layout。
2. 增加 line-level 切分和局部 deskew/warp。
3. 把 glyph mask 用于清字/覆盖前擦除，而不只是报告和背景填充。
4. 引入更强小模型做 clean text 和漫画端到端翻译对比，例如 README 中建议的 Qwen2.5-0.5B q4_k_m。

长期接近 Koharu：

1. 评估 Core ML 可部署的 text detector。
2. 评估 speech bubble instance segmentation。
3. 评估 text segmentation / inpainting 模型体积、速度和许可证。
4. 建立多图测试集，而不是只看 `test/1.png`。

## 当前开发进展、现状和展望

当前 AITRANS 漫画 OCR/覆盖功能已经从“能跑探针”进入“有完整诊断链路”的阶段。它现在能裁掉浏览器 UI/广告，跑多角度 Vision OCR，做气泡归属，约束合并和 crop，生成安全区、glyph mask、背景填充和覆盖图，还能输出 JSON、overlay、contact sheet、纯文本快照。

实际产品效果仍不稳定。当前最弱的不是几何报告，而是 OCR 英文本身和本地 Gemma 270M 翻译。典型坏块仍包括：

- `GET PESULTE / SAMING CLUE TO SAVE THE / POOM BENG`
- `What Whet are / every you! / talking`
- `THE CITY RATTLER / STATE IN A PEN DAYS.`
- `SUGSESTION THE / OVERRULED...`
- `SENPAIS / SENPArS / LOSIC`

展望上，v5 的价值是把后续优化的地基打好了：以后每个 OCR/翻译/渲染变化都能被 bubble ID、slice index、crop padding、glyph mask、safe layout 和 failure category 解释清楚。下一阶段若要真的提升 OCR 准确率，应优先做更稳的文本区域检测/气泡实例分割/line-level crop，而不是继续调覆盖样式；若要提升端到端通过率，应先固定模型随机性并换更强的小模型做 clean text 对比。

## 验证记录

最近 git 记录显示：

- `da9d574`：Agent 3 完成并验收。
- `b65d904`：Agent 4/5 完成并验收。
- `0ab70d0`：Agent 6/7 完成并验收。
- `6e1aa7f`：Agent 8/9 完成审计并更新 README。

最近验证命令：

- `python3 -m json.tool output/probe_report.json` 通过。
- `python3 -m json.tool output/clean_text_diagnostic.json` 通过。
- `git diff --check` 通过。
- `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` 在 Agent 8/9 收尾时通过。

本文件没有重新读取 Koharu 源码；Koharu 对比基于既有研究报告 `md/koharu研究/koharu图像识别链路研究.md` 和当前 AITRANS 工作树。
