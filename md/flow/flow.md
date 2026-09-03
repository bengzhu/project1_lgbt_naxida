# AITRANS 当前架构与流程

本文只描述当前稳定架构、数据流和跨层边界。版本变化、验证记录、PR/SHA/run ID 和临时指标统一写入 [`md/log/`](../log/)。代码定位从 [`md/index/index.md`](../index/index.md) 开始。

## 1. 分层架构

| 层 | 主要职责 | 关键入口 |
| --- | --- | --- |
| App/UI | 页面、用户输入、状态展示和无障碍语义 | `AITRANSApp`、`ContentView`、`Views/` |
| 网页浏览状态 | tabs/activeTabID、漫画页阶段、URL、内存缩略图、滚动位置、导航能力与 WKWebView 意图 | `BrowserModel`、`MangaBrowserView` |
| 状态与调度 | 唯一业务状态、异步任务、持久化、导出和服务编排 | `TranslationSessionStore` |
| OCR 与布局 | Vision OCR、漫画区域、Manga OCR、几何融合和阅读顺序 | `VisionOCRService`、`ComicTextBubbleDetectorService`、`MangaOCRService`、`ImageOCRLayoutEngine` |
| 翻译模型 | Mock、本地 GGUF、prompt、采样、输出清洗和 QA | `MockGemmaService`、`GemmaLocalService`、`LlamaRuntime` |
| Speech | 授权、录音/文件识别、取消隔离和事后质量评估 | Store、`SpeechQualityProbeService`、`SpeechQualityEvaluator` |
| 诊断与验证 | 漫画覆盖探针、benchmark、合同和机器可读报告 | `MangaOverlayProbeService`、`scripts/`、`benchmarks/`、`output/` |

`TranslationSessionStore` 是唯一翻译业务中心。View 不直接调用模型、OCR、Speech 或持久化；服务不直接拥有 SwiftUI 页面状态。漫画浏览器不属于翻译业务链路，由非持久化 `BrowserModel` 独立持有网页状态。

## 2. App 入口与界面

`AITRANSApp` 创建一个 Store 并注入 SwiftUI 环境。`ContentView` 根据设备宽度使用 `TabView` 或 `NavigationSplitView`，路由到七个功能入口：

- 文本：输入、粘贴、翻译和摘要。
- 图片：OCR、逐块翻译、复查、定位、修正和导出。
- 漫画：内嵌 WKWebView、网页导航与纯 UI 翻译悬浮球，不调用翻译链路。
- OCR 检测：OCR-only 工作台，不进入翻译或 LLM。
- 音频：Apple Speech 实时/文件识别和后续翻译。
- 历史：查看和恢复已保存会话。
- 设置：外观、提示词、模型、Pro 占位和开发入口。

UI 私有状态只用于焦点、展开、筛选和暂存输入。会改变业务结果、历史或任务生命周期的动作必须调用 Store。

漫画浏览器例外地把非业务网页状态集中在 `BrowserModel`：View 只提交加载、前进、后退、刷新、重试与标签操作意图，WKWebView Coordinator 只回写当前标签的页面阶段、URL、进度、滚动与导航能力。`activeTabID` 是唯一活动源；切换前抓取缩略图并保存 URL/滚动位置，后台标签只留值快照且释放 WKWebView，切回才重建。地址编辑、菜单展开和球拖拽是 View 私有展示状态；浏览器仍不做磁盘持久化。

## 3. 漫画网页浏览

```text
标签选择 -> BrowserModel.activeTabID -> 唯一活动 WKWebView
  -> 地址输入与 http(s) 规范化 -> WKNavigation/UI/scroll delegate + KVO
  -> 当前标签页面/进度/滚动/导航状态
  -> 切换前缩略图 + URL + scrollOffset，后台释放 WebView
  -> WebView 上层 Safari 胶囊 + 标签切换器 + 翻译球占位 UI
```

- 无 scheme 自动补 `https://`；ATS 保持系统默认，HTTP 被拦截时显示明确原因。
- `_blank` 在当前页加载；非 http(s) 与 App Store 链接尝试交系统，无法处理和下载响应显示提示。
- 加载失败与网页内容进程终止各有独立恢复 UI；只有成功加载后显示翻译球。
- WKWebView 白色浅色背景铺满屏幕，顶部 content inset 避开状态栏；主 TabView 在漫画页隐藏。
- 下滑将三胶囊收成域名小胶囊并同步收起退出按钮/翻译球，上滑或回到顶部 spring 恢复，不改变 WebView 尺寸。

## 4. 文本翻译

```text
用户输入
  -> TranslationSessionStore 组装 ModelGenerationRequest
  -> 当前引擎（Mock 或 Local）
  -> 译文 / 摘要 / 错误
  -> Store 提交当前会话和历史投影
  -> View 展示
```

- Mock 用于界面和数据流冒烟。
- Local 由 `GemmaLocalService` 生成 prompt，通过 `LlamaRuntime` 调用 llama.cpp 与沙盒 GGUF。
- 模型缺失、模板不支持、上下文超限、分词/decode 失败都在服务边界返回错误，不能伪造成功。
- 用户翻译使用产品采样策略；确定性解码只用于明确的诊断和对照。

## 5. 普通图片翻译

```text
照片 / 相机 / 文件 / 剪贴板
  -> Store 建立新的 image task/revision
  -> VisionOCRService
     -> Apple Vision OCR
     -> 日语时按需使用漫画文字检测 + bundled Manga OCR
  -> ImageOCRLayoutEngine 融合、排序和方向判定
  -> ImageTranslationBlock 列表
  -> Store 逐块翻译
  -> 复查 / OCR 修正 / 忽略与恢复
  -> 旁贴或覆盖渲染
  -> 稳定导出与分享
```

稳定边界：

- Apple Vision 是通用 OCR 基础；Manga OCR 是日语漫画/竖排的受控补充，不替代所有图片识别。
- OCR 候选先经过有限几何、置信度、语言证据和 owner 约束，再由布局引擎生成产品 block。
- OCR blocks 可在逐块翻译时显示，但修改结果和复查进度只在最终可修改状态开放。
- 筛选、选中与 VoiceOver 焦点通常是 View 私有投影；修正、忽略、恢复、复查进度和导出由 Store 管理。
- 新图片、重试、取消、修正和导出都绑定 task/revision identity；旧回调和旧文件不能覆盖当前图片。
- renderer 只消费有效的单位坐标几何；无效或过期框不显示、不定位、不绘制。

## 6. OCR 检测工作台

```text
图片输入
  -> 独立 OCR detection task
  -> VisionOCRService / 日语 Manga OCR 补充
  -> OCR blocks + provenance + geometry
  -> 原图 overlay / 筛选 / 编辑 / 复制 / TXT / JSON
```

该入口复用 OCR 服务但拥有独立 Store 状态树。它不创建图片翻译会话、不调用 LLM、不生成译文，也不把人工编辑反向写入普通图片任务。

## 7. 音频识别与翻译

```text
麦克风或音频文件
  -> Store 建立 speech run ID
  -> Apple Speech 授权与 on-device recognition
  -> 最终 transcript
  -> 当前翻译引擎
  -> transcript / 译文 / 运行摘要
```

- checking、recognizing 和 translating 都必须可取消。
- Speech callback 和翻译 Task 必须核对当前 run ID；取消或重试后的旧回调直接丢弃。
- 质量探针是独立事后评估：Apple Speech 返回最终文本后，参考 transcript 才进入 evaluator。
- Speech 语料和报告规则见 [`md/test/test.md`](../test/test.md)。

## 8. 漫画覆盖诊断

`MangaOverlayProbeService` 固定读取测试素材，执行内容裁切、OCR/漫画候选、文字块融合、逐块翻译、质量判定、覆盖绘制和报告生成。

```text
test/1.png
  -> OCR 与结构候选
  -> 融合后的逻辑文字块
  -> 翻译与失败分类
  -> debug / overlay / JSON / TXT
  -> App 沙盒 Output
  -> scripts/export-probe-output.sh
  -> 项目根 output/
```

诊断报告、Koharu proxy、external artifact、BubbleMask、SegmentMask、TextBox 和各类 shadow 对照在明确晋级前都保持 report-only。它们不得改变普通图片 OCR、生产翻译、renderer、`blockPassed` 或候选选择。

ground truth 只用于事后匹配和统计。失败块、未匹配块、原始 OCR 和失败原因必须保留，不能静默删除。

## 9. 持久化与产物

- App 状态：`Application Support/AITRANS/state.json`。
- 本地模型：`Application Support/Models/Gemma-1.5B/model.gguf`。
- App 运行期诊断：`Application Support/AITRANS/Output/`。
- 导出的当前探针产物：仓库根 `output/`。
- 测试输入：`test/`；benchmark schema/fixture：`benchmarks/`。
- 版本与验证日志：`md/log/`；可量化历史：`metrics/`。

持久化和导出只由 Store/对应服务管理。清理必须限定在已验证的 ownership 根目录，拒绝路径逃逸、符号链接和未知文件类型。

## 10. 并发与状态约束

- 文本、图片、OCR-only、Speech、模型下载和导出各自使用明确 identity；开始新任务会使旧任务失效。
- UI 只提交意图，异步结果必须在 Store 再次核对 identity 后才能写入。
- 取消是状态转换，不是只隐藏进度；旧任务后续完成也不得复活。
- Preview 和 UI evidence 场景使用隔离存储，不恢复或污染生产状态。
- 开发模式关闭后，开发页面导航和可操作状态必须同步失效。

## 11. 不允许破坏的边界

- 不创建第二套 Store 或在 View 直接写持久化。
- 不用 ground truth、参考 transcript、fixture 或人工理想框参与生产候选决策。
- 不把 OCR-only、探针、benchmark 或 shadow 报告伪装成产品主路径。
- 不因诊断失败而放宽质量门、删除失败样本或覆盖原始证据。
- 不把内置小模型、单张固定图片或静态合同当作通用质量证明。
- 不提交 GGUF、用户数据、临时构建目录或运行期沙盒产物。

## 12. 文档维护

- 本文只在模块职责、主数据流、ownership 或长期边界变化时更新。
- 小功能、版本行为、CI 结论、commit/PR/run 和指标写入 [`md/log/update_log.md`](../log/update_log.md)，不追加到本文。
- 图示与本文件同步维护于 [`flowchart.md`](flowchart.md)；代码文件定位由 `md/index/` 负责，不在本文维护完整文件清单。
