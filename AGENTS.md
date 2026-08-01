# AGENTS.md
本文是 AITRANS 的核心入口记忆、项目总览、硬规则和多 Agent 工作流。保持精简；历史细节看 `update_log.md`，当前架构看 `md/flow/flow.md`，测试选择看 `md/test/test.md`。

## 0. 角色召唤和身份标识
- 用户消息以 `agenta`、`a:` 或 `A:` 开头，表示召唤 Agent A。
- 用户消息以 `agentb`、`b:` 或 `B:` 开头，表示召唤 Agent B。
- 用户消息以 `agentc`、`c:` 或 `C:` 开头，表示召唤 Agent C。
- 用户消息以 `agentx`、`x:` 或 `X:` 开头，表示召唤 Agent X；Agent X 面向大目标，自动循环调度 Agent A/B/C 和并发子 agent 协作推进、验证、修复与再迭代，单轮最多开启 6 个子 agent，并及时重分配任务以加速收口。
- 没有这些前缀时，按普通 Codex 任务处理；若任务需要 A/B/C 边界，先提醒用户指定角色或说明本轮按普通任务执行。
- Agent A 最终回复第一行必须写：`我是 Agent A。`
- Agent B 最终回复第一行必须写：`我是 Agent B。`
- Agent C 最终回复第一行必须写：`我是 Agent C。`
- Agent X 最终回复第一行必须写：`我是 Agent X。`

## 1. 项目核心事实
AITRANS 是 SwiftUI iOS 本地 AI 翻译原型。当前重点是漫画截图 OCR、本地翻译、覆盖合成和探针诊断链路。

- 默认 `MockGemmaService` 用于 UI 和数据流冒烟。
- `Local` 模式通过 `GemmaLocalService` + `LlamaRuntime` + `llama.cpp` 加载 GGUF。
- 当前内置最小模型是 `Gemma 3 270M IT QAT Q4_0`，适合验证下载、加载、接口和闪退风险，不适合作为翻译质量基准。
- 更强小模型对比可以考虑 `Qwen2.5-0.5B-Instruct-GGUF q4_k_m`，但不要在没有任务要求时擅自更换模型。
- GGUF 不进仓库。云端手动探针从 Release `model-gemma-3-270m-it-qat-q4_0-v1` 下载并缓存 `gemma-3-270m-it-qat-Q4_0.gguf`，按 SHA256 校验后导入模拟器 App 沙盒。
- 当前正式版本号 `3.79`：普通图片 OCR 的 blocks 会在逐块翻译期间继续供用户查看、定位和局部预览，但所有会改变当前结果或复查进度的动作只在 `imageTranslationState == .translated` 开放。`ImageTranslationPanel` 的 `canModifyImageTranslation` 还会在导出重绘期保持禁用，统一保护 OCR 修正、Vision OCR 恢复、已忽略 block 恢复与旁贴／覆盖方式；`canReviewImageTranslation` 保护开始／继续／重启复查及行／局部预览的完成／撤销。Store 的 mark／reopen／reset 同样拒收未完成状态，成功 OCR 修正会先恢复 translated 再沿用既有自动复查，避免 blocks 在逐块翻译中已可见时提前写入会话进度。v3.42 在仍有实际 block 而操作被状态门锁住时显示 View 私有警示状态行；覆盖方式、开始／重启复查、局部预览与结果行的修正／恢复／复查及忽略 block 恢复，都会复用 `imageModificationUnavailableDetail` 或 `imageReviewUnavailableDetail` 作为 VoiceOver 的具体禁用原因。v3.43 继续保留局部预览前后按钮的 disabled 边界，并让可用状态读出“定位上一个／下一个文字块”、首尾状态读出“当前已是筛选结果中的第一个／最后一个文字块”；结果行主定位提示按 `isSelected` 在“取消此文字块在图片中的定位”和“在图片预览中定位此文字块”之间切换。v3.44 让同一对前后按钮再读出 `navigationPositionAccessibilityValue`：有位置时为“当前位置 (positionText)”（如 `1 / 3`），无位置时为“未显示筛选位置”，不新增 Store 状态。v3.45 让完整图片预览中的 OCR 覆盖块也复用结果行的定位提示：已定位时读出“取消此文字块在图片中的定位”，未定位时读出“在图片预览中定位此文字块”，保持图片入口和列表入口语义一致。v3.46 让图片预览加载与失败状态提供稳定的 VoiceOver label/value，重试提示明确只重建屏幕预览、不重新 OCR 或翻译。v3.47 让图片命令栏的照片／文件、取消、重试、重新识别、导出与清空操作提供作用域明确的 VoiceOver hint，照片选择器会按是否已有图片动态区分首次选择与替换；v3.48 让完整图片预览提供稳定的容器 label/value/hint，汇总识别块数量、待复查数量和当前定位位置，并把重复朗读的原始背景图设为无障碍隐藏；这些只是 View 语义，不新增 Store 或持久化状态。它覆盖 loading／recognizing／translating／failed 和导出重绘，并明确逐块翻译仍可查看／定位；本版不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径、ground truth、metrics 或 `output`，不能作为 OCR、翻译、识别或 Koharu 质量提升证据。v3.37–v3.40 的规范化无语义关闭、弃改保护、确认无误分流、键盘／滚动收起、保存期输入锁定和 revision-scoped 关闭后焦点交接继续保留。v3.36 的开发控制台 readiness 摘要仍只读已有报告；缺真实四件套时仍显示 `manifestMissing / stopUntilArtifactsProvided`。v3.26 CI receipt 传播规则不变，artifact 继续记录父 SHA、state 和元数据判定；传播路径不是新的 Swift/Xcode 编译证据。v3.49 让图片输入语言与目标语言菜单的 VoiceOver hint 按运行中、Pro 门槛、无图片、已完成和失败／取消重试状态分流：运行中明确需完成或取消，Pro 锁定说明不会污染文本页语言，已完成输入语言说明会重新识别和翻译、目标语言说明会重新翻译当前图片，失败／取消说明下一次重试使用新语言；选回当前内容语言会撤销待重试差异。v3.50 让照片与文件导入按钮在读取、OCR 或翻译进行中明确说明选择新图片会取消当前任务并开始新的本机 OCR 与翻译，同时保持有意设计的替换入口、Store run-id 隔离与现有 import controls 可用。v3.51 让图片状态行成为单一的 VoiceOver 状态元素，动态读出当前阶段、逐块进度和下一步操作，并区分载入／Vision OCR／翻译、导出重绘、分享准备、失败和完成状态。该改动只改善 View 语义，不新增 Store／持久化状态，也不改变 OCR、翻译、renderer/export、探针或质量基线。v3.52 让图片结果行的 VoiceOver value 在定位状态之外读出 OCR 置信度、低置信／方向待定、人工修正、复查进度和等待翻译，并继续沿用定位 hint；只改善 View 语义，不新增 Store／持久化或改变 OCR、翻译、renderer/export、探针和质量基线。v3.53 让已忽略 OCR 文字块恢复行成为稳定的 VoiceOver 上下文，读出不在图片预览／导出／转录、是否保留现有译文和恢复是否可用，同时保留恢复按钮的禁用原因与焦点交接；只改善 View 语义，不新增 Store／持久化或改变 OCR、翻译、renderer/export、探针和质量基线。v3.54 修复图片状态行 VoiceOver value 的实际实现回归：使用动态 `statusTitle`／`statusDetail` 插值，而不是字面量，保证当前阶段、逐块进度、失败、导出重绘和完成详情能被实时朗读；同步强化 v3.51 回归合同，仍不新增 Store／持久化或改变 OCR、翻译、renderer/export、探针和质量基线。v3.55 让开发控制台的 Koharu readiness 状态成为稳定的 VoiceOver 上下文，读出 verdict、缺失四件套、下一步和 shadow-only 边界；缺少工件时明确给出 `test/koharu_artifacts/` 与四个文件名。该改动只改善开发者操作与诊断可理解性，不新增 Store／持久化，不调用第二次探针，不改变 active artifact gate、普通图片 OCR、翻译、renderer/export、Koharu 主路径或质量基线。v3.56 让漫画覆盖翻译探针状态行成为单一、稳定的 VoiceOver 上下文，按载入、Vision OCR、翻译、绘制、完成和失败读出状态详情；运行按钮明确 bundle 内 `test/1.png`、Output 诊断文件和只影响漫画探针的边界。该改动只改善开发者操作语义，不新增 Store／持久化，不改变普通图片 OCR、翻译、renderer/export、Koharu 主路径或质量基线。v3.57 让开发控制台的漫画探针逐块结果成为稳定的 VoiceOver 诊断上下文，按 block index 读出 PASS/FAIL、OCR 原文、旋转角度、置信度、质量标签、译文与失败详情；展开提示明确只属于漫画探针，不改变普通图片 OCR、翻译或覆盖图。该改动只改善开发者操作语义，不新增 Store／持久化状态、不读取 ground truth 作为候选、不改变漫画探针诊断、renderer/export、Koharu 主路径或质量基线。v3.58 让图片复查结果行提供稳定的 VoiceOver label/value：label 明确“图片文字块 + OCR 原文”，value 在等待翻译时读出等待状态、完成后读出译文，并为空 OCR 提供稳定回退；只改善 View 语义，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。v3.59 让完整图片预览的覆盖文字块与图片复查结果行共用稳定的 VoiceOver label“图片文字块 + OCR 原文”，空 OCR 回退为“空”，并保留既有等待翻译／译文 value、定位 hint 和选中状态；该改动只改善 View 语义，不新增 Store／持久化状态，不改变选择、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。 v3.60 让完整图片预览的覆盖文字块与图片复查结果行对齐 VoiceOver value：读出 OCR 置信度（clamp 到 0–100%）、人工修正、低置信／方向待定、待复查／本次已复查及等待翻译／译文；相邻与替换模式共用这套上下文，只改善 View 语义，不新增 Store／持久化状态，不改变选择、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。 仓库尚无真实 Koharu 四件套、Speech 音频或真实竖排图片 corpus，不声称 OCR、翻译或识别质量提升。
- v3.61 让图片复查结果行和完整图片预览的 VoiceOver 上下文消费既有 Vision OCR 方向证据：已判定的横排／竖排与有限方向置信度会进入 value，结果行显示已知方向，OCR 置信度显示安全夹到 0–100%；只改善 View 语义，不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。
- v3.62 让图片识别结果摘要复用既有 `ImageOCRResultSummary.horizontalBlockCount` 与 `verticalBlockCount`，在摘要中显示横排／竖排数量；不新增 Store／持久化状态，不重新运行 OCR／翻译，不改变 renderer/export、漫画探针、Koharu 主路径或质量基线。
- v3.63 让“识别结果”摘要成为单一 VoiceOver header，复用既有摘要 value，并按无图片、翻译未完成、没有待复查块和可复查状态给出下一步 hint；不新增 Store／持久化状态，不重新运行 OCR／翻译，不改变 renderer/export、漫画探针、Koharu 主路径或质量基线。
- v3.64 统一图片 OCR 置信度安全边界：`ImageOCRResultSummary`、布局引擎、结果行和覆盖层把非有限值回退为 0、越界值夹到 0–1；无效置信度继续进入低置信复查，不得污染平均值或触发百分比转换崩溃。该修复不改变 OCR 候选、翻译、renderer/export、漫画探针或 Koharu 主路径。
- v3.69 在图片结果行和完整图片预览的 VoiceOver 摘要中提前报告无效或过期 OCR 框的“定位不可用”数量；结果行保留 OCR 修正和切换文字块入口，并以位置不可用图标提供可见提示。该版本只消费 `NormalizedImageRect.normalizedToUnit()` 的既有边界，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu、ground truth、metrics 或 output；真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。
- v3.70 让完整图片预览的 VoiceOver hint 按无效或过期 OCR 框数量分流：有效文字块才说明可打开局部放大，异常文字块明确局部预览不可用；保留 OCR 修正、切换文字块和既有状态门。该版本只消费同一 `NormalizedImageRect.normalizedToUnit()` 边界，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu、ground truth、metrics 或 output；真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。
- v3.71 让开发控制台的 Koharu readiness 摘要显示坐标、mask payload、mask 拓扑和工件身份门控，并在 VoiceOver/可复制摘要中说明阻塞项与 CI 对账要求；只读既有 report，不创建或修改 active `test/koharu_artifacts`，不放宽 readiness gate，不改变普通图片 OCR、翻译、renderer/export、漫画探针或 Koharu 主路径。真实四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。
- 当前 App bundle ID 是 `com.local.aitransform114`；云端探针必须从构建产物 `Info.plist` 动态读取，禁止在 workflow 再硬编码。
- 当前可信基线以 `update_log.md`、`metrics/version_history.csv`、最新 `output/probe_report.json` 和 `output/clean_text_diagnostic.json` 为准，不在本入口长篇复制指标。

- v3.65 让图片 OCR 修正 sheet 的低置信度提示复用 ImageOCRResultSummary.normalizedConfidence，非有限／越界值在百分比格式化前安全归一化；历史 v3.47–v3.64 图片合同同步接纳后续正式版本。该改动只改善 View 语义，不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、漫画探针或 Koharu 主路径。
- v3.66 对 Vision OCR bounding box 做有限、正面积、整矩形单位坐标归一化，布局引擎过滤 NaN/∞、零面积和完全越界 observation，避免异常 geometry 进入覆盖、定位或阅读排序；新增 geometry evaluator，历史 v3.47–v3.65 图片合同同步接纳后续正式版本。该安全边界不改变 OCR 候选、翻译、renderer/export、漫画探针或 Koharu 主路径。
- v3.67 将 finite／正面积／单位空间整矩形边界复用到 Codable `NormalizedImageRect` 的图片预览、局部定位和导出 renderer；旧会话或外部解码的异常框跳过显示/绘制，不新增 Store／持久化状态，不改变 OCR 候选、翻译、漫画探针或 Koharu 主路径。历史 v3.47–v3.66 图片合同同步接纳后续正式版本。
- v3.68 让无效或过期 OCR 框的局部放大明确显示“局部预览不可用”，不再把整图误作当前文字块；保留关闭、编辑 OCR 原文和切换文字块入口，并用 VoiceOver hint 说明边界。图片 OCR 修正对照仍可编辑，不新增 Store／持久化状态，不改变 Vision OCR、翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。

## 2. 每轮必读
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

README 不再承载历史基线；涉及验收时以当前代码、`update_log.md`、最新 `output/`、`metrics/version_history.csv` 和实际测试结果为准。

## 3. 架构硬边界
- `TranslationSessionStore` 是 UI 状态、模型调用、历史、诊断和持久化的统一调度中心。
- UI 层只触发 store 方法，不绕开 store 直接改持久化、模型状态或报告状态。
- Speech 授权、识别和翻译回调必须按当前 run ID 隔离；取消或重试后，旧回调不得覆盖新状态。
- Speech 质量 corpus 的参考 transcript 只能在 Apple Speech 返回最终文本后参与评估；禁止用于识别请求、候选选择、纠错或生产翻译。中日文没有稳定分词器时只报告 CER，不把字符编辑率标成 WER。
- 普通图片 OCR 使用 `VisionOCRService`；漫画覆盖探针使用 `MangaOverlayProbeService` 的独立诊断链路。
- 用户实际翻译和 summary 走 sampled 解码；漫画探针、raw 诊断、clean text、batch 对照和纠错翻译对照走 deterministic 解码。
- `test/1.ground_truth.json` 只能用于探针验证和统计，不能用于真实产品路径或生产候选选择。
- action 打包软件包当前有密码保护；不要为 Agent C 验收改动或解密该包。Agent C 只看独立未加密的 CI 结果包。

v3.72 继续只读 Koharu readiness report：当 schema 为 v1 且 bubble/segment payload verdict 都是 `legacySummaryOnly` 时，Developer Console 显示“未要求（v1 summary-only）”与“未要求（v2 拓扑）”，并在 VoiceOver/可复制摘要中说明 v2 门控尚未要求；真实 v2 工件仍保留实际 payload/topology 失败与阻塞。该版本不创建或修改 active 工件、不放宽 gate、不改变 OCR、翻译、renderer/export、漫画探针或 Koharu 主路径，也不能作为质量提升证据。

v3.73 让空 OCR 的已忽略文字块在视觉行显示“空 OCR 原文”，VoiceOver label 显示“空”，避免空字符串让用户误以为行缺失；非空文本、恢复入口、焦点和 Store ownership 保持不变。该 View-only 改动不改变 Vision OCR、翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。

v3.74 让普通图片 OCR 结果行与旁贴／覆盖预览在 `block.original` 为空时显示稳定“空 OCR 原文”回退；旁贴／覆盖仍保持非空译文优先。该 View-only 变化不新增 Store／持久化状态、不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。
v3.75 让 `ImageOCRCorrectionReferencePreview` 与 `ImageTranslationFocusPreview` 在 `block.original` 为空时用 View 私有 `accessibilityOriginalText` 提供“空”回退，避免参考／局部定位 VoiceOver value 变成无上下文空白；非空原文保持原样。该修复不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、复查、漫画探针、Koharu、ground truth、metrics 或 output；真实 Koharu 四件套、Speech corpus 与竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。
v3.76 隐藏 `ImageTranslationFocusPreview` 中仅用于视觉提示的“局部放大”角标，避免该装饰标签与父容器的“已定位文字块局部放大”VoiceOver label/value 重复朗读；参考预览原有装饰角标隐藏、关闭／修正／复查／前后定位与 OCR 上下文保持不变。该 View-only 修复不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、复查、漫画探针、Koharu、ground truth、metrics 或 output；真实 Koharu 四件套、Speech corpus 与竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。
v3.77 让 `ImageTranslationFocusPreview` 的无效几何状态子视图从 VoiceOver 树隐藏，父容器继续提供不可用原因和“关闭、编辑 OCR 原文或切换文字块”的统一 hint，避免 `contain` 层级重复朗读；参考预览、关闭／修正／复查／前后定位与 OCR 上下文保持不变。该 View-only 修复不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、复查、漫画探针、Koharu、ground truth、metrics 或 output；真实 Koharu 四件套、Speech corpus 与竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。

v3.78 让关闭 `ImageTranslationFocusPreview` 后的 VoiceOver 焦点回到对应 OCR 结果行，避免局部预览容器消失后焦点丢失；使用既有 View 私有 focus identity，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、复查、漫画探针、Koharu、ground truth、metrics 或 output。该版本只改善图片操作可理解性，不声称 OCR、翻译、识别或 Koharu 质量提升。

v3.79 让 `selectAdjacentBlock(offset:)` 在按当前筛选顺序选中目标 OCR block 后立即把 VoiceOver 焦点交给新的局部预览容器，前后导航继续保留位置 value、首尾 disabled 边界和 View 私有 focus identity；同步让 v3.14 历史合同接受等价的局部 target ID 赋值。该 View-only 改动不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、复查、漫画探针、Koharu、ground truth、metrics 或 output，不声称 OCR、翻译、识别或 Koharu 质量提升。

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

## 5. Git 分支和云端验证工作流
- `main`：外观展示分支。禁止 Agent B / C 把日常开发成果合并到 `main`。
- `smalldata_test`：本仓库实际工作主分支。若外部提示词写成 `samlldata_test`，以当前远端真实分支 `origin/smalldata_test` 为准。
- `codeb/vX.Y-短标题`：Agent B 候选实现分支，例如 `codeb/v2.0-cloud-ci-workflow`。
- Agent B 每轮从最新 `smalldata_test` 开 `codeb/...` 分支，完成后 push。
- Agent B push 后默认创建 Pull Request，base 为 `smalldata_test`，head 为 `codeb/...`。
- Agent C 从 PR / 远端 `codeb/...` 分支验收；通过后优先通过 PR merge 合并到 `smalldata_test`。
- 任何 Agent 在 `git push`、`git merge`、删除远端分支或改变远端状态前，都必须确认目标不是 `main`。
- Agent C 合并后必须删除远端 `codeb/...` 候选分支，或确认 GitHub PR 的 delete branch 已执行；没有权限删除时必须说明，避免候选分支无限堆积。

默认验证路径：

- 除非人工明确要求“本机测试”“本地 build”“本地跑探针”“本地 xcodebuild”，否则完整 build、Xcode 测试、漫画探针、报告生成和重验证默认交给 GitHub Actions。
- 本地仍可做 `git diff --check`、JSON 解析、YAML smoke 等轻量检查；这些不算重负载本机测试。
- Agent B 完成版本核心代码后 push `codeb/...`：`validationProfile=full`，只运行本任务涉及的领域契约；App 构建相关变更再跑一次 Xcode build。成功后 workflow 为该 SHA 写 `AITRANS CI/full-validation` status，并上传未加密结果包。
- PR 只在 opened / reopened / ready-for-review 时运行 `validationProfile=fast`；不监听 synchronize，避免修复 push 同时触发 full + PR fast。fast 只跑基础静态/路由契约并记录 skip reason，不重复 Xcode、Speech/UI/Koharu 大契约或截图。
- 合并到 `smalldata_test` 后，workflow 读取 merge 第二父 SHA 的 full-validation status；只有 `success` 才走 fast follow-up，并把该 receipt 传播到 merge SHA，否则自动回退 full。C 退回后新的核心修复 push 必须重新产生 full 收据。
- 其后的纯 README / AGENTS / update log / `md/` / metrics `smalldata_test` 提交只有父 receipt 为 success 时可走 fast；父 receipt 缺失或失败时必须强制当前头部 Xcode build，不能用文档提交掩盖未验证代码。结果包必须保留 smalldata 父 SHA、state、元数据判定和强制 full 判定。
- Speech 功能默认只跑 Xcode build、Speech run-id/取消/翻译链路契约、质量算法契约和 corpus validator，不采 UI 截图；缺少 `test/speech_corpus/manifest.json` 时 validator 必须写 `manifestMissing`、`qualityExecuted=false`，不能伪造质量结果。漫画/翻译改动需要结果图时手动跑 `ci-fast/full`，只验收探针输出 PNG，不等同 UI evidence。
- UI evidence 默认跳过；只有重大 UI 任务在候选核心 commit 使用 `[ui evidence]`，或手动 `workflow_dispatch ui_evidence_mode=full` 才运行。普通 UI 小改、Speech、PR 和 merge 不截图。
- Koharu artifact validator 的完整 invalid fixture 矩阵只在 Koharu validator、artifact contract 或 CI workflow 相关 full 任务中运行；其他任务不加载该领域套件。
- GitHub Actions push 默认 `probe_mode=skip`，不启动模拟器漫画探针；需要云端探针验收时手动 `workflow_dispatch` 选择 `ci-fast` 或 `full`。
- 现有加密打包 workflow 只在软件包交付时手动 `workflow_dispatch`，不再随 `smalldata_test` merge 自动 archive；Agent C 不以该包验收。
- 独立 CI 结果包必须未加密，至少包含 `junit.xml`、`xcodebuild.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`；`xcodeBuildRequired=true` 时还必须包含 `.xcresult`，手动探针运行还必须包含可用的 `output/` 报告。
- 若 `workflow_dispatch` 注入 Koharu artifact archive，Agent C 必须核对 Release / artifact / App / CI identity、validator、orientation、dry-run 与 reconciliation 证据。external shadow OCR 除 executed / candidate / OCR count sanity 外，还必须核对 TextBox ID 非空唯一、matched / succeeded / failed / skipped 分区一致、`duplicateAssignedTextBoxIDs = []`、`coverageVerdict = complete`、`successfulCoverageRatio = 1`，且 `WI/G-external-textbox-shadow-ocr-coverage` closed / passed；不得用任意一个 OCR 成功或注入步骤日志冒充完整 coverage。
- 若注入 artifact 的 TextBox 带 `sourceDirection`、`linePolygons` 或 `rotationDegrees`，Agent C 还必须核对 `orientationShadowPathPartialBlocks`、`orientationUnsupportedBlocks`、`orientationUnsupportedReasonBreakdown`、convergence 的 `WI/G-external-textbox-shadow-ocr-coverage` 和 `WI/G-external-textbox-orientation-shadow-path`，确认 no-candidate / partial / unsupported 未被误判为 `closedReportOnly` 或 passed。
- 注入 contract v2 artifact 时，Agent C 必须同时核对 validator / App / manifest 的 `maskTopologyGateReady`、`maskTopologyValidation` / `maskTopologyReport`，以及 convergence `WI/G-external-mask-topology-linkage`。assignment 必须复用 external shadow OCR 的稳定一对一 TextBox 结果；missing / duplicate block 或 TextBox、foreign / no-bubble / orphan / multiply-assigned pixels、cross-Bubble / orphan component 或 partition 不守恒时不得 passed。
- 若云端失败，Agent B 根据结果包中的失败摘要、日志路径和 manifest 修复后继续 push，不改回默认本机循环。

## 6. Agent A/B/C 职责
### Agent A
- 默认不改代码。
- 读取入口文档、历史、流程、测试规范和相关源码。
- 输出写给 Agent B 的版本化提示词，保存到 `md/prompt/vX（阶段）/vX.Y（任务）.md`。
- 提示词必须明确目标、非目标、分支名建议、测试层级、CI 期望、验收标准和禁止项。

### Agent B
- 从最新 `smalldata_test` 开 `codeb/vX.Y-短标题` 分支。
- 按 Agent A 提示词小步实现，不做无关重构。
- 默认本地只跑轻量检查；除非人工明确要求，不跑本机完整 Xcode build 或漫画探针。
- 完成后集中 push 核心候选 commit，让 GitHub Actions 运行一次 task-scoped full；通过后再创建 PR 到 `smalldata_test`，PR 只跑 fast follow-up。若 C 退回，修复 push 重新跑对应 full。
- 最终回复必须列出分支名、PR 链接、commit SHA、push 结果、CI 入口或 run 信息、本地已跑检查、未跑测试原因、artifact 名称；若 Actions 尚未完成，必须说明等待云端结果。

### Agent C
- 拉取 `codeb/...` 分支，查看实际 diff、文档同步、架构边界、GitHub Actions 结论、日志和 artifacts。
- 只能验收与当前 `codeb/...` HEAD 完全一致的 `commitSha`。
- 必须核对 `ci-artifact-manifest.json` 中的 `version`、`branch`、`commitSha`、`runId`、`runAttempt`、`workflowName`、`validationProfile`、`validationReason` 和 full-validation 收据字段，确认没有拿旧包、错包或其他分支的包。fast 结果不能单独冒充候选编译证据。
- 必须查看 `.xcresult` 或摘要、`junit.xml`、`xcodebuild.log`、`ci-failure-summary.md`；涉及探针时还必须检查云端生成或上传的 `probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt` 和关键 PNG。涉及 external TextBox 时，还必须检查 shadow OCR coverage、orientation partial / unsupported 摘要及 convergence gate 状态。
- 有 bug 或云端验证失败时，输出退回清单，说明应由 Agent B 修复的日志位置和失败原因，不合并。
- 通过后更新版本号和核心文档，通过 PR merge 合并到 `smalldata_test`，push。严禁合并到 `main`。
- 合并完成后删除远端 `codeb/...` 候选分支，或在最终回复说明未删除原因。

## 7. 测试选择
- 非 App 构建相关修改至少运行 `git diff --check`，可加 JSON/YAML smoke。
- 非 App 构建相关变更的云端 CI 可接受 `xcodeBuildRequired=false` 的 build-skip 结果包；Agent C 必须核对 manifest 的 skip reason，不能把它当作 Swift/Xcode 编译证据。
- Swift 或 Xcode 工程修改默认不在本机跑完整 build；按规则推分支交给 GitHub Actions 快验。
- Speech 质量算法修改至少运行 `scripts/test-speech-quality-contract.py`、纯 Swift evaluator contract 和 `scripts/validate-speech-corpus.py`；没有真实音频时只能验收算法与接线，不能给出 WER/CER 改善结论。
- 漫画探针、翻译链路或报告模型修改需要云端探针证据时，手动 `workflow_dispatch` 运行 `ci-fast` 或 `full` 生成报告；若当前云端因模拟器、GGUF、App 容器或外部 artifact 缺失不能稳定运行，必须在最终回复和文档中列明未验证范围、缺失依赖、是否影响验收和需要人工提供什么。
- 不得伪造测试结果，不得把旧 artifact 当新结果。

本地轻量命令：

```sh
git diff --check
python3 -m json.tool test/1.ground_truth.json
python3 -m json.tool output/probe_report.json
python3 -m json.tool output/clean_text_diagnostic.json
```

人工明确要求本机 build 时使用：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

## 8. 文档和版本收口
- `AGENTS.md` 是唯一核心入口文档。
- `update_log.md` 记录版本历史、关键决策、验证结果和遗留问题。
- `md/flow/flow.md` 只写当前真实架构和运行流程。
- `md/flow/flowchart.md` 必须与 `flow.md` 同步。
- `md/test/test.md` 是测试选择依据。
- `md/prompt/` 保存 Agent A 的版本化实现提示词。
- 功能更新或 bug 修复后，按影响同步更新 `update_log.md`、flow/test 文档和 `metrics/version_history.csv`；README 不再写更新记录，只保留项目说明、当前用法和稳定规则。
- 流程制度变更不伪装成漫画探针质量版本；未重新跑完整探针时不追加 `metrics/version_history.csv` 漫画指标行。

## 9. 最终回复格式
最终回复使用中文，至少包含：

- 改了什么。
- 关键文件。
- 当前分支名和是否触碰远端。
- 已运行的验证命令和结果。
- 未运行的测试及原因。
- 未跑本机 build / 探针时，明确写“未跑本机 build / 探针，按规则交给云端验证”。
- Agent C 通过后，说明 git commit / push / merge 结果和提交哈希；若未执行，说明原因。
- 涉及漫画探针或翻译链路时，汇总关键数字。
- 已知风险和下一步建议。
