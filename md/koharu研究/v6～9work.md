# AITRANS v6-v9 Koharu 对齐进展报告

日期：2026-06-28  
范围：v6-v9 漫画 OCR / 翻译 / 覆盖探针工作  
依据：当前代码、`README.md`、`metrics/version_history.csv`、最新 `output/probe_report.json`、`output/clean_text_diagnostic.json`、`output/1_ocr_probe_text.txt`、`md/koharu研究/koharu图像识别链路研究.md`、`reference/koharu-main` 源码。

## 结论

v6-v9 的核心不是继续堆新模型，而是把 v5 后留下的几个关键问题查清：指标是否可信、底部气泡串扰到底是不是 crop 问题、bubble-first 能不能升级成主流程、词表和确定性纠错能不能直接救 OCR。

结论比较硬：v6-v9 让诊断和决策更可靠，但没有让主流程 OCR 分数明显提升。当前 v9 仍是：

- `totalBlocksDetected = 14`
- `groundTruthMatchedBlocks = 10`
- `groundTruthUnmatchedBlocks = 4`
- `averageCoreDialogueOCRSimilarity = 0.6131`
- `averageDecorativeOCRSimilarity = 0.8000`
- `wholePage.accuracyVsGroundTruth = 0.6131`
- `bubbleFirst.accuracyVsGroundTruth = 0.7397`
- `cleanTextDiagnostic.passRate = 0.4545`，确定性解码后为 `5/11`
- `passedBlocks = 1`
- `failedBlocks = 13`
- `translationFailureBreakdown = { ocrInputSuspect: 10, translationLanguageQualityFailure: 3 }`
- `frameworkComparison.consistencyPassed = true`

所以相对 Koharu，本项目已经补上了一部分轻量几何约束和可解释诊断，但还没有达到 Koharu 那种“检测框、文字 mask、气泡实例 mask、OCR crop、清字、渲染”全部由结构化中间产物驱动的状态。当前瓶颈仍在文字区域检测和 OCR 文本质量，不在覆盖渲染。

## v6-v9 做了多少

### v6：把诊断解码固定下来

v6 解决的是“数字能不能信”的问题。

代码层面：

- `LlamaRuntime` 支持按调用切换 `sampled` / `deterministic` 解码。
- 用户实际翻译和 summary 保持 `sampled`。
- 漫画探针、raw 诊断、clean text、tagged batch、纠错翻译对照走 `deterministic`。
- `ModelDecodingProfile.deterministic` 固定为 `seed = 42`、`temperature = 0`、不启用 top-k/top-p/min-p。
- 报告新增 `decodingMode`、`decodingSeed`、`diagnosticDecodingMode`、`productionDecodingMode`、`deterministicDecodingCheck`。
- 新增 `metrics/version_history.csv` 和 `scripts/append-version-metrics.py`，以后每版指标可追踪。

作用：

- 之前 clean text 的 `4/11`、`5/11`、`6/11` 波动，主要是模型采样噪声。
- v6 后同 prompt 连续两次输出字符级一致，`deterministicDecodingCheck.outputsIdentical = true`。
- 后续比较 OCR/几何改动时，LLM 侧不再随机漂移。

局限：

- v6 不修 OCR，只修“测量可信度”。
- v4 没有完整逐块 OCR 快照，无法回溯 `0.6196 -> 0.6131` 到底是文本变化还是匹配变化。

### v7：底部气泡串扰专项诊断

v7 处理 v5/v6 后最显眼的底部问题：`GET PESULTE...` 和 `What Whet are...`。

诊断结论：

- `GET PESULTE / SAMING CLUE TO SAVE THE / POOM BENG` 已有独立 `bubbleID = 5`，不是跨气泡串扰。扩大到所属气泡 bbox 后，二次 OCR 反而更差，所以主流程保留 raw OCR。
- `What Whet are / every you! / talking` 归到 `bubbleID = 6`，这个气泡候选过大，同时覆盖左侧长建议气泡和右侧小问句，根因是气泡候选分割不够细。

尝试过但回退的方向：

- 检测层 seed 分裂。
- 小框优先。

回退原因：

- 会把正常块拆碎，导致 `totalBlocksDetected` 增到 16，未匹配升到 6 或 7。

最终保留的保守修复：

- 当 OCR bbox 只覆盖合理气泡的一部分时，二次预处理 OCR 可用所属气泡 bbox 作为 adaptive crop。
- 仍走 raw 词保留和回退护栏，不用真值参与生产选择。

实际效果：

- 指标保持稳定：`14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`。
- 目标块 OCR 没有实质改善。
- 关键收获是排除了“放宽 crop/跨气泡合并能解决”的错误方向。

### v8：评估 bubble-first 能否升级为主候选源

v8 是架构决策，不是盲目切主流程。

最新对比：

- `wholePage.accuracyVsGroundTruth = 0.6131`
- `bubbleFirst.accuracyVsGroundTruth = 0.7397`
- `blocksFoundByBoth = 8`
- `blocksOnlyInWholePage = ["Let's Battle!"]`
- `blocksOnlyInBubbleFirst = ["What are you even talking about?", "We need to get results at this tournament to save the gaming club from being disbanded."]`
- `matchedGroundTruthUnionCount = 11`
- `consistencyPassed = true`

决策：

- 不把 bubble-first 直接替换成唯一主流程。

原因：

- bubble-first 确实找到整页路径漏掉/识别差的两条重要内容。
- 但整页路径独有的 `Let's Battle!` 是真实对话，不是噪声。
- 如果现在直接改成 bubble-first 主源，会丢真实内容。

当前正确方向：

- 未来应做“bubble-first 主候选 + whole-page 真实内容兜底”的融合架构。
- 不能简单二选一。

### v9：词表和确定性纠错复盘

v9 回答两个问题：Vision `customWords` 是否有效，确定性 OCR 纠错是否可以进主流程。

词表重测：

- 默认词表：`Senpai`、`City Battler`、`Tournament`、`Ren`、`Battler`
- `lexiconComparison.changedBlockIndexes = []`
- 开/关词表最终块数均为 `14`

结论：

- 对当前图，Vision `customWords` 没有改变最终合并文本。
- 它不是解决 `RATTLER -> BATTLER`、`PEN DAYS -> FEW DAYS`、`TRANINS`、`SUGSESTION`、`LOSIC` 的主要路径。

确定性纠错对照：

- 改善块：`[2, 4, 7, 8, 10, 12]`
- 翻译对照通过：`[2, 4]`
- 翻译对照失败：`[7, 8, 10, 12]`

典型案例：

- `THE CITY RATTLER / STATE IN A PEN DAYS.` 可修到 `THE CITY BATTLER / STARTS IN A FEW DAYS.`
- `PLAY ONLING...` 可修到 `PLAY ONLINE...`
- `SENPAIS SENPArS LOSIC.` 会被修成 `SENPAI'S SENPAI'S LOGIC.`，仍不干净。
- `GET PESULTE...` 只能部分修为 `GET RESULTS / SAVING CLUE... / ROOM BEING`，不能恢复真值。

决策：

- 不把确定性纠错候选纳入主流程。
- 原因是收益不稳定，且目前确定性规则缺少完整长度/词数/证据护栏。
- 继续作为探针对照保留。

## 当前 AITRANS OCR 图像识别链

当前主链路仍以 Apple Vision 为 OCR 主体，但已经有几何约束和诊断层。

核心数据流：

```text
test/1.png
  -> 裁掉浏览器 UI / 广告 / 底部导航
  -> 内容区 2x 放大
  -> 0/90/180/270 Vision OCR
  -> OCR candidates
  -> 传统近白连通域 + OCR seed 生成 bubble candidates
  -> 每个 OCR candidate 分配 bubbleID 或 unassigned
  -> 同 bubbleID 内合并，跨 bubble 禁止合并
  -> final OCR blocks
  -> 自适应 crop 二次 OCR 诊断，clamp 到 bubble bbox
  -> 确定性 OCR 纠错对照，不替换主文本
  -> 逐块本地 LLM 翻译
  -> clean text / batch tagged / bubble-first / slice OCR 对照诊断
  -> glyph mask / 背景色估计 / safeLayoutRect / 离屏碰撞检查
  -> 覆盖图、OCR overlay、bubble overlay、contact sheet、JSON、txt
```

核心执行流：

```text
MangaOverlayProbeService.recognizeTextBlocks
  -> detectBubbleCandidates
  -> recognizeRawCandidates
       -> 长宽比 <= 2.85：整页内容 OCR
       -> 长宽比 > 2.85：竖向 slice OCR + 坐标还原 + 去重
  -> assignBubble
  -> mergeCandidatesIntoBlocks
  -> bubbleGeometryDiagnostics / sliceDiagnostics

TranslationSessionStore.runMangaOverlayProbe
  -> 每块预处理 OCR / 纠错诊断
  -> 每块 localService.rawTranslationProbe
  -> runTaggedBatchTranslationComparison
  -> runCleanTextDiagnostic
  -> runDeterministicDecodingCheck
  -> applySafeLayoutAndRenderingDiagnostics
  -> write probe_report / overlays / contact sheet
```

当前已经具备的能力：

- 浏览器 UI / 广告 / 底部导航裁切。
- 0/90/180/270 OCR。
- 长图 slice OCR 机制，`test/1.png` 不触发，合成长图可触发。
- 气泡 ID 分配。
- 跨气泡禁止合并。
- crop 自适应 padding 和气泡 clamp。
- clean text 诊断。
- bubble-first 对照。
- Vision customWords 开关对照。
- 新旧 Vision API 对照。
- tagged batch 翻译对照。
- 确定性 OCR 纠错对照。
- glyph mask、纯色背景填充、safe layout、离屏渲染碰撞检查。
- 跨版本指标 CSV。

当前还不具备的能力：

- 真正的文本区域检测模型。
- 真正的气泡实例 mask。
- 真正的文字像素分割 mask。
- line polygon / 透视矫正 / 局部 deskew。
- bubble-first 和 whole-page 的可靠融合主流程。
- 基于 mask 的清字 inpainting。
- 字体/方向/颜色预测。
- 更强 OCR 模型或 OCR 多引擎投票。
- 翻译模型质量基准，当前 Gemma 270M 仍太弱。

## Koharu 的核心数据流和执行流

Koharu 不是“整页 OCR 然后合并”，而是 artifact DAG。

源码中的关键 artifact：

- `SourceImage`
- `TextBoxes`
- `SegmentMask`
- `BubbleMask`
- `OcrText`
- `FontPredictions`
- `Translations`
- `Inpainted`
- `RenderedSprites`
- `FinalRender`

Koharu 数据流：

```text
SourceImage
  -> detector 生成 TextBoxes
  -> segmenter 生成 SegmentMask
  -> bubble segmenter 生成 BubbleMask，且每个气泡是独立 ID
  -> OCR 只在 TextBoxes crop 上跑，写回 OcrText
  -> font detector 预测字体/方向/颜色
  -> LLM 以 tagged blocks 批量翻译
  -> inpainter 用 SegmentMask + BubbleMask + TextBoxes 清字
  -> renderer 用 BubbleMask 计算安全区、排版、碰撞检查、最终合成
```

Koharu 执行流：

```text
EngineInfo 声明 needs / produces
  -> DAG resolver 按 Artifact 依赖排序
  -> 每个 Engine 读取 scene/page/blob
  -> run() 返回 Op 列表
  -> ProjectSession apply ops
  -> 下游 Engine 读取上游产物继续处理
```

Koharu 的核心强点：

- 检测、OCR、翻译、清字、渲染之间靠结构化 artifact 连接，不靠临时字符串和 bbox 列表。
- OCR 之前已经有 TextBoxes，OCR 只是识别，不负责版面发现。
- `BubbleMask` 是实例 ID mask，不是 bbox，也不是二值图。
- renderer 的 `BubbleIndex` 会按 seed bbox 下的 bubble ID 像素数确定所属气泡，再用 distance transform 求安全区。
- `SegmentMask` 会被 TextBoxes 约束，避免背景线条误入文字 mask。
- 渲染时会生成 sprite，并检查非透明像素是否落在气泡内部。
- LLM 翻译使用 numbered tags，并要求不合并、不拆分、不乱序。

## AITRANS 和 Koharu 对照

| 能力 | Koharu | AITRANS v9 | 差距 |
| --- | --- | --- | --- |
| 流水线组织 | Artifact DAG | 单服务探针流程 + 报告结构 | AITRANS 还不是可组合 pipeline |
| 文本区域定位 | 专用 detector 产出 TextBoxes | Vision OCR observations 反推 + bubble seed | 关键差距，OCR 还承担定位职责 |
| 气泡表达 | 实例 ID mask | `bubbleID + bbox`，无真实 mask | 只能做矩形约束，不能处理尾巴/凹陷/重叠 |
| OCR 输入 | TextBox crop OCR | 整页/切片 OCR 为主，crop OCR 是诊断 | OCR 输入质量仍受整页缩放影响 |
| 长图 | 分片检测 + 合并 | 已有 slice OCR 机制 | 机制有了，但真实长图样本和主流程验证不足 |
| 文字 mask | 模型概率 mask + TextBoxes refine | 轻量二值化 glyph mask | AITRANS 是保守近似，容易漏/误，不能替代 segmenter |
| 清字 | SegmentMask + inpainting | glyph 区域填充/半透明覆盖 | 还没有真正 inpainting |
| 安全区 | distance transform + 最大安全矩形 | bbox inset + 分区 safe rect | 矩形气泡尚可，不规则气泡不足 |
| 渲染碰撞 | sprite 非透明像素检查气泡 mask | sprite 非透明像素检查 safe rect | 已借鉴核心思想，但边界来源弱 |
| 批量翻译 | tagged batch 主流程 | tagged batch 诊断，当前失败 | 受 Gemma 270M 格式能力限制 |
| 字体/方向 | font detector | 无 | 覆盖图风格还不能贴近原图 |

整体估计：如果把 Koharu 的链路完整度视作 100%，AITRANS 当前在“轻量几何诊断与渲染约束”上约完成 35%-45%，在“真正 OCR 识别质量链路”上约完成 20%-30%。主要缺口不是某个字段，而是 TextBoxes、SegmentMask、BubbleMask 三个强中间层还没有产品级实现。

## 目前改进得怎么样

已经改进明显的部分：

- 诊断可信：v6 后 LLM 诊断可复现。
- 失败解释清楚：能区分 OCR 输入问题、模型输出问题、翻译语言质量问题。
- 气泡几何更硬：跨气泡合并被拒绝，且有 `crossBubbleMergeRejectedBlocks`。
- 渲染更稳：`renderCollisionUnresolvedBlocks = []`、`renderTextTruncatedBlocks = []`。
- 清字准备更好：`glyphMaskBlocks = 11`，纯色填充块 `[2, 4, 6, 7]`。
- 长图机制可用：合成长图 3 slices，`residualOverlapDuplicateCount = 0`。

没有改进或证据不足的部分：

- 主流程 OCR 核心相似度仍是 `0.6131`，没有超过 v5 前 `0.6196`。
- 未匹配仍是 4 块。
- `What Whet are / every you! / talking` 仍未修好。
- `GET PESULTE...` 仍未修好。
- `RATTLER/PEN DAYS/TRANINS/SUGSESTION/LOSIC` 等字符级损坏仍在。
- `customWords` 本图无效果。
- 确定性纠错不能直接进主流程。
- batch tagged 翻译在 Gemma 270M 上格式崩，`parsedCases = 0`。

所以，目前 v6-v9 对“工程可控性”和“路线判断”的提升大于对“OCR 文本准确率”的提升。

## 还差多少可以优化，优化什么原理，有什么作用

### 1. Bubble-first + whole-page 融合主流程

原理：

- 以 bubble-first 作为主要候选，因为它在当前图上核心准确率更高。
- 保留 whole-page 中真实存在但 bubble-first 漏掉的块，例如 `Let's Battle!`。
- 用 IoU、文本相似度、bubbleID、ground-truth-free 质量评分去重。

作用：

- 吃到 bubble-first 的收益，同时不丢整页独有真实文本。
- 这是最贴近当前代码、风险最低的下一步。

风险：

- 不能用 `test/1.ground_truth.json` 参与生产选择。
- 不能为了提高分数跨气泡合并。

### 2. 改进气泡候选分割

原理：

- 当前 `detectBubbleCandidates` 主要靠近白连通域和 OCR seed 扩张。
- 对 #9 这种相邻气泡，bbox 容易并大。
- 下一步可以做 seed 分区、白色连通域 watershed/切缝检测、按 OCR seed 投票拆分大气泡、重叠小气泡优先。

作用：

- 解决 `What Whet...` 所在的大 bbox 把多个气泡包在一起的问题。
- 后续 safe rect、crop clamp、glyph mask 都会受益。

风险：

- v7 已证明粗暴分裂会拆碎正常块，所以必须有回归保护：总块数、未匹配数、跨气泡拒绝数都要稳定。

### 3. 让 OCR 真正跑在 text region crop 上

原理：

- Koharu 是先 TextBoxes，再 OCR crop。
- AITRANS 现在仍主要是整页/切片 OCR observation 反推文本块。
- 可先用现有 bubble-first / OCR seed / 轻量连通域生成 text region，再在 region crop 上 OCR。

作用：

- 减少整页缩放导致的小字损坏。
- 让 OCR 的职责从“定位+识别”收敛到“识别”。

风险：

- text region 如果不准，会漏字或扩大串扰。
- 必须保留 whole-page fallback。

### 4. 从 bbox 安全区升级到 mask 安全区

原理：

- Koharu 的 `BubbleIndex` 使用气泡 ID mask 和 distance transform。
- AITRANS 当前是 bbox inset。
- 可以先用 Swift 原生生成二值/ID mask，再计算距离场或最大内接安全矩形。

作用：

- 不规则气泡、气泡尾巴、相邻重叠气泡的排版更稳。
- 渲染碰撞检查可以从“是否在矩形 safe rect 内”升级到“是否在真实气泡像素内”。

风险：

- 这改善渲染，不直接提升 OCR，报告中必须分开。

### 5. glyph mask 继续强化为清字 mask

原理：

- 当前 glyph mask 是灰度二值化 + 连通域 + OCR bbox overlap。
- 后续可加入局部阈值参数自适应、stroke 宽度估计、连通域方向/笔画比例过滤、与气泡 mask 联合约束。

作用：

- 白底气泡清字更干净。
- 可为未来 inpainting 提供 mask。

风险：

- 背景线条、网点、角色轮廓容易误判。
- 必须继续遵守“在气泡内部且与 Vision OCR bbox 重叠”两个条件。

### 6. 局部 deskew / line polygon

原理：

- Koharu 使用 line polygons 和 crop warp。
- AITRANS 目前只有整图 0/90/180/270，没有对斜行/变形文本做局部矫正。

作用：

- 有机会改善漫画斜体、透视字、局部小字。
- 对 `BATTLER`、`SUGSESTION` 这类字符混淆可能有帮助。

风险：

- 没有稳定 line polygon 前，deskew 容易引入新损坏。

### 7. 更强翻译模型和 OCR 模型对比

原理：

- 当前 Gemma 270M clean text 只有 `5/11`，即使跳过 OCR 也会失败。
- 需要引入更强小模型，例如 README 建议的 Qwen2.5-0.5B q4_k_m 做质量基准。
- OCR 层也可比较 Vision、PaddleOCR-VL、本地 OCR 或多 OCR 投票。

作用：

- 分清“OCR 错”和“模型不会翻译”。
- tagged batch 是否可用，取决于模型格式跟随能力。

风险：

- 不要把模型文件提交进仓库。
- 不要在未验证前替换主流程。

## 当前开发进展、现状、未来展望

### 开发进展

AITRANS 已经从早期简单图片 OCR 翻译，演进到一个可审计的漫画探针系统：

- 有固定测试图和人工真值。
- 有词序敏感 OCR 相似度。
- 有整页 vs bubble-first 框架对比。
- 有 clean text 模型诊断。
- 有确定性解码和跨版本 CSV。
- 有气泡 ID、slice OCR、crop 自适应、渲染碰撞、glyph mask、背景填充。
- 有 contact sheet、overlay、JSON、txt 多种排查产物。

### 当前现状

主流程可解释，但 OCR 文本质量还不够产品化。当前最真实的状态是：

- 位置基本能找到。
- 块归属比以前清楚。
- 覆盖图不容易越界。
- 白底气泡覆盖更干净。
- 但英文 OCR 仍有大量字符级错误。
- 当前本地翻译模型即使拿真值文本也不稳定。

### 未来展望

下一阶段应该按这条路线推进：

1. 先做 bubble-first + whole-page 融合，不直接替换，解决“bubble-first 更准但会漏 `Let's Battle!`”的问题。
2. 再做气泡候选分割优化，专攻 #9 这类相邻气泡误并。
3. 然后把 OCR 主输入从整页 observations 推向 text region crop。
4. 并行做 mask 安全区和 glyph mask 强化，但这些归类为渲染/清字质量，不冒充 OCR 准确率提升。
5. 最后引入更强模型对比，让 clean text、逐块翻译、tagged batch 有可靠模型基准。

目前不建议做的事：

- 不建议把确定性纠错直接替换主流程文本。
- 不建议把 Vision `customWords` 当主修复方案。
- 不建议把 bubble-first 直接作为唯一主源。
- 不建议用 ground truth 参与生产候选选择。
- 不建议用跨气泡合并凑相似度。

## 一句话总结

v6-v9 把“能不能相信数字”和“下一步该不该改架构”查清了：当前主流程 OCR 分数没有变好，但诊断稳定性、几何约束、渲染可靠性已经明显接近 Koharu 的思想。接下来真正能向 Koharu 靠近的，不是继续加词表或放宽规则，而是补上 TextBoxes、BubbleMask、SegmentMask 这三类强中间层，并把 bubble-first 与 whole-page 做可回退的融合主流程。
