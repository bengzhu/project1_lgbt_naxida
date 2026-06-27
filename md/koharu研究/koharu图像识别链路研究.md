# Koharu 图像识别链路研究

日期：2026-06-27  
对象：`reference/koharu-main`  
目标：分析 Koharu 在 OCR/LLM 模型之外，为漫画图像识别、气泡定位、OCR 输入质量、清字覆盖做了哪些逻辑算法优化，并提炼 AITRANS 可借鉴方案。

## 结论摘要

Koharu 的图像识别质量不是靠“更强 OCR 模型”单点完成，而是靠分阶段几何约束：

1. 先检测文本区域、气泡区域和版面区域，形成 `TextBoxes`、`SegmentMask`、`BubbleMask` 三类中间产物。
2. OCR 只在检测出的文本块 crop 上运行，不直接扫整页。
3. 对长图会分片检测，再把检测框坐标还原、去重、合并。
4. 文本像素 mask 会被限制在扩张后的文本框内，避免把背景线条误认为文字。
5. 气泡 mask 使用“每个气泡一个 ID”的实例分割结果，不只是二值 mask。
6. 渲染阶段用气泡 ID mask 做安全区、字体大小二分搜索、透明像素碰撞检测，避免译文跑出气泡。
7. 翻译是批量 tagged blocks，要求模型保留 `[1]`、`[2]` 顺序，输出再按 tag 解析，降低块错位。

AITRANS 当前主线仍偏“整页 Vision OCR observations -> 空间聚类 -> 翻译”，已有 bubble-first 对照和预处理，但还没有把气泡实例 mask、文字像素 mask、版面过滤、长图分片、OCR crop 几何约束纳入主流程。下一步最值得借鉴的不是直接移植 Koharu 模型，而是先引入这些轻量算法约束。

## Koharu 完整图像识别链条

Koharu pipeline 用 artifact 声明各阶段依赖，DAG 自动排序。核心 artifact 包括：

- `SourceImage`：原图。
- `TextBoxes`：文字块节点。
- `SegmentMask`：文字像素清字 mask。
- `BubbleMask`：气泡内部实例 mask。
- `OcrText`：每个文字块 OCR 文本。
- `FontPredictions`：字体、颜色、描边、方向预测。
- `Translations`：翻译文本。
- `Inpainted`：清字后图。
- `FinalRender`：最终合成图。

默认配置是：

- detector：`pp-doclayout-v3`
- segmenter：`comic-text-detector-seg`
- bubble_segmenter：`speech-bubble-segmentation`
- font_detector：`yuzumarker-font-detection`
- ocr：`paddle-ocr-vl-1.6`
- inpainter：`lama-manga`
- renderer：`koharu-renderer`

实际完整链路：

1. 读取 source image。
2. detector 产出文字框 `TextBoxes`。
3. segmenter 基于文字框和模型概率图产出 `SegmentMask`。
4. bubble segmenter 产出每个气泡独立 ID 的 `BubbleMask`。
5. font detector 对每个文字框 crop 做字体/颜色/方向预测。
6. OCR 对每个文字框 crop 识别文字，写回同一 Text node。
7. LLM 批量翻译带编号的 OCR 文本。
8. inpainter 用 `SegmentMask + BubbleMask + TextBoxes` 扩张/约束清字区域。
9. renderer 用气泡 ID mask 计算安全布局框，自动调字号，检查译文 sprite 是否越界。

这个设计和 AITRANS 的区别：Koharu 的每一步都产出可复用几何中间层，后续步骤不是“盲信 OCR 文本”，而是持续用 bbox、mask、bubble ID、direction、font size 来约束。

## 关键非模型算法优化

### 1. 文本框不是 OCR observations 合并，而是独立检测结果

Koharu 多个 detector 都产出 `TextRegion`：

- `pp-doclayout-v3`：过滤 label，只保留 `content`、`text`、`title` 类区域；剔除太小区域；重叠超过 0.9 的框去重；高宽比大于 `1.15` 判定竖排。
- `anime-text-yolo`：letterbox 到 640，映射 bbox 回原图，按类别 NMS。
- `comic-text-bubble-detector`：RT-DETR 同时检测气泡和文字，文字类框会做重叠/包含合并。
- `comic-text-detector`：YOLO 文本框 + UNet/DBNet 文字像素 mask。

这说明 Koharu 不把 OCR 自身的 observation 当作唯一版面分析来源。OCR 的职责是识别，文本区域定位由检测/版面模型负责。

AITRANS 可借鉴：先用当前 bubble-first 结果作为 TextBoxes 主候选，再让 Vision OCR 只在候选 crop 内识别。不要继续依赖整页 OCR observation 反推气泡边界。

### 2. 长图分片检测，避免整页缩小损失小字

`comic-text-bubble-detector` 对高宽比大于 `3.5` 的图做竖向 slices：

- 目标 slice 高度约为 `width * 3.0`。
- slice 之间有 `20%` 高度重叠。
- 最后一片过短时减少 slice 数。
- 检测后把每片 bbox 的 y 坐标加回原图。
- 最后按 label、IoU、包含关系、垂直距离、x overlap、size ratio 合并重复框。

这对手机长截图非常关键。整页 resize 到固定输入时，小字会被压缩；分片能保留局部字号。

AITRANS 可借鉴：对 `test/1.png` 之外的长截图引入 tile/slice OCR。即使继续用 Apple Vision，也可以先按气泡/内容区域切片，每片单独 OCR，再还原坐标去重。

### 3. 多重合并/去重规则

Koharu 的合并不是简单 IoU：

- 绝对重叠或 IoU 超阈值合并。
- 一个框大部分包含另一个框时保留更合理区域。
- slice 重叠产生的重复框按 label 合并。
- 垂直相邻且 x 方向重叠、大小相近、左右边界接近的框可以合并成同一文本块。
- 合并后检查面积，避免把远距离区域合成巨框。

AITRANS 当前有 OCR candidate 聚类，但可以补充“同气泡 ID 优先合并、跨气泡禁止合并、面积膨胀上限、slice 去重来源记录”。

### 4. 文字像素 mask 被文本框裁剪约束

`comic-text-detector-seg` 先得到概率 mask，再调用 `refine_segmentation_mask`：

- 若没有 TextBoxes，mask 直接清空，避免无约束误擦。
- 对每个文本框计算扩张 crop bounds。
- 把所有扩张框 rasterize 成 `in_bounds_mask`。
- 只保留“在扩张文本框内且概率超过阈值”的像素。
- 进行小半径膨胀。
- 最后再裁回扩张框范围，防止膨胀逃逸到背景。

这类算法的核心价值不是 inpainting，而是给 OCR/覆盖提供“文字真实像素分布”。它能避免把角色线条、背景纹理、气泡边缘当文本。

AITRANS 可借鉴：在 iOS 上可先做轻量版：对 bubble crop 做二值化/边缘连通域，连通域必须落在气泡内部且与 Vision OCR bbox 有足够重叠，才作为有效文字区域。先不需要引入 UNet。

### 5. OCR crop 根据文字方向、字号和 line polygons 动态扩张

Koharu 的 `expanded_text_block_crop_bounds`：

- 普通 detector 框直接裁 bbox。
- CTD 或有 line polygons 时，会把 line polygon 和 bbox 合并后再裁。
- 根据 `detected_font_size_px` 计算 padding。
- 横排：x padding 较小，y padding 较大。
- 竖排：x padding 较大，y padding 较小。
- 所有裁切都 clamp 到图像范围。

它还支持 line polygon 透视/旋转校正：

- 对每条文字 polygon 做 `warp_line_region`。
- 计算四边形长宽，映射成规整矩形。
- 竖排文字会旋转到 OCR 更容易识别的方向。
- 没有 line polygon 时 fallback 到 bbox crop。

AITRANS 可借鉴：当前 crop 扩张是固定比例。可改为字体/框尺寸自适应 padding，并按横排/竖排不同方向扩张。对 Vision 识别到的倾斜文本，可增加局部 deskew，而不是只做 0/90/180/270 整图旋转。

### 6. 气泡 mask 是实例 ID，不是二值图

`speech-bubble-segmentation` 输出每个气泡 region 的 mask。App 层会按面积从大到小排序并绘制 ID mask：

- 背景为 0。
- 每个气泡是 1..255 的独立 ID。
- 大气泡先画，小气泡后画，重叠时小气泡保留自己的 ID。

这让后续算法能判断“某个文本块属于哪个气泡”，也能禁止跨气泡合并和跨气泡覆盖。

AITRANS 可借鉴：当前 bubble-first 不应只输出 `[bbox]`，应输出 `bubbleID + bubbleMask + bbox + textBlocksInside`。即使气泡由传统图像算法得到，也要保留实例 ID。

### 7. BubbleIndex：从气泡 mask 计算安全布局区

Koharu renderer 的 `BubbleIndex` 做了几件关键事：

- 扫描 ID mask，得到每个 bubble ID 的 bbox。
- 对每个气泡分别为横排和竖排计算 safe layout box。
- seed 文本框查找所属气泡时，不用 bbox 中心点，而是统计 seed bbox 下各 bubble ID 像素数，选择多数 ID。
- 安全区通过 distance transform 得到：离气泡边缘足够远的像素才算 safe。
- 如果 centroid 不够安全，会退到最大距离点或最近安全点。
- 在 safe map 上求最大安全矩形，作为译文布局区域。
- 横排默认 padding 是气泡短边 `12%`，竖排是 `20%`。

这比“把译文画在 OCR bbox 上”稳定得多，尤其对不规则气泡、尾巴、凹陷、相邻气泡有效。

AITRANS 可借鉴：覆盖绘制时先用 OCR bbox 匹配 bubble ID，再把译文布局框扩展到该气泡内部 safe rect。若同一个气泡有多个 OCR 块，则保留各自 seed box，避免多个译文抢同一安全区。

### 8. 渲染阶段有碰撞检测和字号搜索

Koharu 渲染不是一次性画文本：

- 根据图片尺寸给最小字号。
- 根据 layout box 给最大字号。
- 如果没有 bubble mask，就二分搜索最大可放入框内的字号。
- 如果有 bubble mask，先渲染 sprite，再检查非透明像素是否全部落在对应 bubble ID 内。
- 若越界，继续降低字号。
- 透明像素不会算作碰撞。
- 若显式字号存在，则尊重用户设置。

AITRANS 可借鉴：当前覆盖图可增加“先排版成离屏 mask，再检查是否越过气泡/原 bbox”的步骤。失败时缩小字号或分行，而不是固定画框。

### 9. 清字 mask 扩张受气泡 ID 约束

Koharu `expand_mask_for_inpainting`：

- 从文字像素 mask 出发，只扩张 glyph 像素，不填满整个文本框背景。
- 扩张半径由 `detected_font_size_px` 推导，有最小/最大 clamp。
- 对剩余连通域按短边比例扩张。
- 用 dominant bubble ID 限制扩张，防止清字区域跨到相邻气泡。
- 另有 `expand_mask_to_bubble_region_for_inpainting` 给 Flux 路径使用，会更激进地填充文本框区域。

AITRANS 可借鉴：如果后续做“覆盖前擦除英文”，不要直接覆盖整 bbox。先估计 glyph mask，再小半径扩张；只在所属气泡内处理，减少破坏角色/背景线条。

### 10. 纯色气泡快速填充

`apply_bubble_fill` 会对低方差气泡跳过 inpainting：

- 找到 mask 与 bubble mask 重叠的 bubble IDs。
- 对气泡内非文字区域采样背景色。
- 用每个通道中位数估计背景色。
- 计算颜色标准差，低于阈值才认为是纯色气泡。
- 只填充该气泡内的 masked pixels。
- 纹理复杂时保留 mask，交给 inpainting。

AITRANS 可借鉴：对大量白底对话框，直接用气泡背景中位色填充英文区域，比半透明覆盖更干净，且不需要模型。

### 11. inpainting 分块策略

Koharu 对清字修补有 HD strategy：

- `Original`：整图 pad 后前向。
- `Resize`：缩小长边到限制，修补后只恢复 mask 内像素，mask 外保持原图。
- `Crop`：按 mask 外轮廓找连通域，每个连通域加 margin 单独修补，再贴回。
- crop 内如果仍过大，再 fallback 到 resize。
- padding 用 symmetric reflection，满足模型 stride。

AITRANS 可借鉴：即使不用 inpainting 模型，也可以复用“按 mask 连通域生成局部工作窗口”的思路，减少 OCR/增强处理区域，避免整页预处理污染。

### 12. 批量翻译保持块编号

Koharu LLM 不是逐块独立 prompt，也不是把整页文本无结构发送。它把文本格式化成：

```text
[1]...
[2]...
```

系统提示明确要求：

- 保留每个编号 tag。
- 不合并、不拆分、不重排。
- 输出同样 tag 后接译文。

返回后用 tag parser 解析每块。如果没有 tag，则 fallback 到按行切分。

AITRANS 可借鉴：漫画探针现在逐块翻译，容易缺上下文，也慢。可以在保留失败明细的前提下增加 batch 翻译对照，用编号强约束输出映射，减少模型把多块顺序搞乱。

## 与 AITRANS 当前链路的差距

AITRANS 现状：

- 固定裁掉浏览器 UI/广告/底部导航。
- 对漫画内容 2x 放大，跑 0/90/180/270 Vision OCR。
- 合并 OCR observations 为逻辑文字块。
- 有预处理 crop 二次 OCR，但只作为候选。
- 有 bubble-first 对照，但不是主流程。
- 有确定性 OCR 纠错候选，但不替换主流程。
- 输出 `probe_report.json`、overlay、contact sheet 和诊断文本。

主要缺口：

- 没有独立 `TextBoxes` detector 层，仍依赖 OCR observations。
- bubble-first 没有形成可复用的实例 `BubbleMask` 和 `bubbleID`。
- OCR crop 没有受到“同一气泡内部”硬约束。
- 预处理是图像增强候选，不是几何约束链条。
- 没有文字像素 mask，因此无法判断“真正需要 OCR/覆盖/擦除的 glyph 区域”。
- 覆盖绘制没有用气泡形状安全区，也没有 sprite collision 检查。
- 翻译仍是逐块请求，缺少 batch tag 结构。

## AITRANS 可借鉴优化路线

### P0：把 bubble-first 升级为主几何信号

优先级最高，且不要求引入新模型。

建议新增内部结构：

```swift
struct ProbeBubbleRegion {
    let id: Int
    let bbox: CGRect
    let mask: CGImage?      // 初期可选，先 bbox 后 mask
    let area: CGFloat
    let confidence: Float?
}

struct ProbeTextRegion {
    let bbox: CGRect
    let bubbleID: Int?
    let source: String      // wholePageOCR / bubbleFirst / sliceOCR
    let confidence: Float?
}
```

流程建议：

1. 先输出气泡候选 ID。
2. 每个 Vision OCR observation 通过 bbox overlap 或中心点投票归属 bubble ID。
3. 同一 bubble 内做合并；跨 bubble 默认禁止合并。
4. OCR crop 时以 bubble bbox/safe rect 为边界，不让 crop 扩到相邻气泡。
5. 报告新增 `bubbleID`、`bubbleAssignmentMethod`、`crossBubbleMergeRejected`。

验收：

- 保持 `totalBlocksDetected` 不盲目增加。
- 重点看 `What are you even talking about?`、`We need to get results...` 是否从 unmatched/低相似度改善。
- 不能让广告/UI 文本进入 bubble IDs。

### P1：长图/局部 tile OCR

对长截图或内容高度较大图：

- 按内容宽度生成竖向 slices。
- 每片保留 15% 到 25% 重叠。
- 对每片单独 Vision OCR。
- bbox y 坐标还原到原图。
- 按 IoU、包含关系、文本相似度、bubble ID 去重。

这比整页 2x OCR 更稳，因为 Vision 在很长图上仍可能受缩放影响。

### P1：OCR crop 自适应扩张

替代固定 `expand(... by: 0.18)`：

- 用 bbox 短边估计字号。
- 横排文本：y padding 大于 x padding。
- 竖排文本：x padding 大于 y padding。
- crop 必须 clamp 在所属 bubble safe rect 或 bubble bbox 内。
- 若 crop 后 OCR 丢失 raw words，则回退原 crop。

报告可新增：

- `cropPaddingX`
- `cropPaddingY`
- `cropClampedByBubble`
- `cropCandidatePreservesRawWords`

### P1：气泡安全区 overlay

先实现简化版 Koharu `BubbleIndex`：

1. 如果有 bubble mask，用 distance transform 得到离边缘足够远的 safe pixels。
2. 求最大安全矩形。
3. 如果没有 mask，先用 bbox inset 近似。
4. 单块气泡把译文布局框扩展到 safe rect。
5. 多块同气泡保持各自 seed box。
6. 离屏渲染译文，检查非透明像素是否越出 bubble bbox/mask，越界就缩小字号。

这样即使 OCR/翻译还不完美，覆盖图会更接近可用产品形态。

### P2：轻量文字像素 mask

不急着引入 CTD/UNet。iOS 原生可先做：

- 在 bubble crop 内灰度化。
- 自适应阈值或 Sauvola/局部阈值。
- 连通域分析，过滤过大背景线条、过小噪声。
- 连通域必须和 Vision OCR bbox 有交集。
- 对 glyph mask 做小半径膨胀。
- 用 mask 生成更准确的 block crop、清字区域和覆盖背景。

注意：这不能用 ground truth 做生产决策，只能用 Vision 置信度、几何、连通域特征、词保留关系评估。

### P2：纯色气泡背景填充

先不做 inpainting 模型，也能改善覆盖：

1. 对每个气泡内非 glyph mask 区域采样颜色。
2. 用 RGB 中位数，不用平均值。
3. 计算标准差，低方差才填充。
4. 只填充 glyph mask 膨胀区域，不填整个框。
5. 高方差/纹理背景保留当前半透明覆盖策略。

这对普通白底漫画气泡很有效，工程量小。

### P2：批量 tagged translation 对照

新增探针分支：

```text
[1]IVE ARRIVED...
[2]THAT'S RIGHT...
```

prompt 要求保留编号、不合并、不拆分、不解释。解析结果再映射回 block。这样可以：

- 给模型更多上下文。
- 降低多次调用的随机性。
- 保持每块报告明细。
- 直接记录 missing tag / duplicated tag / reordered tag。

但当前 Gemma 270M clean text 只有 `4/11` 通过，所以 batch 翻译不应替代 P0 模型质量对比，只能作为诊断对照。

### P3：引入专用检测/分割模型

如果要接近 Koharu 质量，最终需要考虑模型层：

- 小型 text detector：替代 Vision observation 反推文本框。
- speech bubble segmentation：产出实例气泡 mask。
- text segmentation mask：产出 glyph mask。

iOS 本地部署要评估 Core ML 转换、模型体积、Metal 性能和许可证。短期不建议一次性移植 Koharu Rust/Candle 模型。

## 推荐实施顺序

1. 把 bubble-first 输出结构化：`bubbleID + bbox + block assignment`。
2. 在主流程里用 bubble ID 限制 OCR 合并和 crop。
3. 加 slice OCR，对长图和当前测试图都输出对照指标。
4. 实现 bbox inset 版 safe layout rect，先不用 distance transform。
5. 增加离屏文本渲染碰撞检查和字号回退。
6. 增加轻量 glyph mask，用于 crop 质量和背景填充。
7. 再评估引入专用 detector/segmenter 模型。

## 对当前 `test/1.png` 的具体预期收益

结合最新 `output/1_ocr_probe_text.txt`：

- `GET PESULTE / SAMING CLUE...` 和 `What Whet are / every you! / talking` 这类底部相邻气泡，优先靠 bubble ID 拆分与 crop 限制改善。
- `THE CITY RATTLER / STATE IN A PEN DAYS.` 这类小字标题/对话，优先靠局部 slice、字号自适应 crop、文字像素 mask 改善。
- `SUGSESTION THE / OVERRULED...` 这类长文本，优先靠同气泡内 line ordering 和 crop 不跨气泡改善。
- `SENPAIS / SENPArS / LOSIC` 这类专有名词损坏，几何改善后仍可能需要词表/模型质量对比。

## 风险与边界

- 不要把 `test/1.ground_truth.json` 用进生产候选选择。只能用它验证策略。
- 不要为了提升相似度强行合并跨气泡文本。
- 轻量二值化可能把网点、速度线、角色轮廓当文字，必须用 bubble ID 和 OCR bbox 约束。
- batch translation 可能让弱模型输出格式崩坏，必须保留逐块 fallback 和详细诊断。
- 气泡安全区会改善覆盖，不等价于 OCR 准确率提升；报告指标要分开记录。

## 建议新增探针字段

- `bubbleID`
- `bubbleBBox`
- `bubbleAssignmentMethod`
- `bubbleCoverageRatio`
- `crossBubbleMergeRejected`
- `sliceIndex`
- `sliceOverlapDeduped`
- `ocrCropRect`
- `cropClampedByBubble`
- `safeLayoutRect`
- `glyphMaskPixelCount`
- `backgroundFillApplied`
- `backgroundColorStdDev`
- `batchTranslationTagStatus`

这些字段能让后续优化继续遵守项目原则：数字从明细实时算，不隐藏失败，不用真值参与生产决策。

## 参考文件

- `reference/koharu-main/koharu-app/src/pipeline/mod.rs`
- `reference/koharu-main/koharu-app/src/pipeline/artifacts.rs`
- `reference/koharu-main/koharu-app/src/config.rs`
- `reference/koharu-main/koharu-app/src/pipeline/engines/*.rs`
- `reference/koharu-main/koharu-ml/src/comic_text_detector/mod.rs`
- `reference/koharu-main/koharu-ml/src/comic_text_detector/postprocess.rs`
- `reference/koharu-main/koharu-ml/src/comic_text_bubble_detector/mod.rs`
- `reference/koharu-main/koharu-ml/src/speech_bubble_segmentation/mod.rs`
- `reference/koharu-main/koharu-ml/src/inpainting/mask.rs`
- `reference/koharu-main/koharu-ml/src/inpainting/balloon.rs`
- `reference/koharu-main/koharu-ml/src/inpainting/strategy.rs`
- `reference/koharu-main/koharu-renderer/src/text/latin.rs`
- `reference/koharu-main/koharu-app/src/renderer.rs`
- `reference/koharu-main/koharu-app/src/llm.rs`
- `reference/koharu-main/koharu-llm/src/prompt.rs`
