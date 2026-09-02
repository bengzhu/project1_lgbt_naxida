# UI 路由与图片复查操作

> 状态：current。View 是 Store 的展示/动作投影；本页只保留入口和高风险交互路由。

## 快速定位

| 屏幕/主题 | 文件 | 关键符号 |
| --- | --- | --- |
| 根路由、tab、Phone/iPad | [`AITRANS/Views/ContentView.swift`](../../../AITRANS/Views/ContentView.swift) | `ContentView`、`PhoneRootView`、`TabletRootView`、`AppTabRouter`、`LibraryHubView` |
| 视觉系统与共享组件 | [`AppTheme.swift`](../../../AITRANS/Views/AppTheme.swift)、[`AppComponents.swift`](../../../AITRANS/Views/AppComponents.swift) | `AppFeature`、`AppPageHeader`、`AppCanvasBackground`、`appSurface` |
| 文本翻译 | [`AITRANS/Views/TextTranslationView.swift`](../../../AITRANS/Views/TextTranslationView.swift) | `TextTranslationView`、`TranslationInputPane`、`TranslationOutputPane` |
| 图片翻译主屏 | [`AITRANS/Views/ImageTranslationViews.swift`](../../../AITRANS/Views/ImageTranslationViews.swift) | `ImageTranslationView`、`ImageTranslationPanel`、`ImageTranslationPreview` |
| OCR 检测工作台 | [`AITRANS/Views/ImageOCRDetectionView.swift`](../../../AITRANS/Views/ImageOCRDetectionView.swift) | `ImageOCRDetectionView`、`ImageOCRDetectionCanvas`、`ImageOCRDetectionResultRow`、`OCRDetectionDiagnostics` |
| 图片结果行/局部预览/编辑 | 同上 | `ImageTranslationBlockRow`、`ImageTranslationFocusPreview`、`ImageOCRCorrectionSheet` |
| 图片 overlay/竖排显示 | 同上 | `ImageTranslationOverlayBlock`、`ImageTranslationVerticalText` |
| 图片结构/几何编辑 | [`ImageOCRBlockStructureEditor.swift`](../../../AITRANS/Views/ImageOCRBlockStructureEditor.swift)、[`ImageOCRGeometryEditor.swift`](../../../AITRANS/Views/ImageOCRGeometryEditor.swift) | editor Views |
| 音频、历史、设置 | [`AudioTranslationView.swift`](../../../AITRANS/Views/AudioTranslationView.swift)、[`HistoryView.swift`](../../../AITRANS/Views/HistoryView.swift)、[`SettingsView.swift`](../../../AITRANS/Views/SettingsView.swift) | screen Views |
| Prompt/模型/Developer Console | [`PromptLibraryView.swift`](../../../AITRANS/Views/PromptLibraryView.swift)、[`ModelManagementView.swift`](../../../AITRANS/Views/ModelManagementView.swift)、[`DeveloperConsoleView.swift`](../../../AITRANS/Views/DeveloperConsoleView.swift) | settings destinations |
| UI evidence fixtures | [`AITRANS/Views/AppPreviewSupport.swift`](../../../AITRANS/Views/AppPreviewSupport.swift) | `AppPreviewScenario` |

## 操作数据流

```text
View action / accessibility action
  -> TranslationSessionStore public method
  -> @Published state + focus generation
  -> View updates focus/preview/filter
```

iPhone 一级导航固定为文本、图片、OCR、音频、资料库五项；历史与设置从资料库的两个大入口进入。iPad 侧栏直接按“创作 / 工具 / 资料”分组。两种布局只改变导航层级，不合并图片翻译与 OCR-only 工作台的业务边界。

六个功能域通过 `AppFeature` 同时绑定编号、英文眉题、图标和自适应浅/深色功能色；颜色不是唯一识别手段。页面 Hero 入场动效必须响应 Reduce Motion，描边必须响应 Increase Contrast。

OCR 检测页是独立的一页式流程：图片/相册/拍照/粘贴自动进入 OCR，原图显示编号框和质量颜色，结果行点击后高亮对应区域；语言与版式分开选择，显式日语竖排才开启 90°/270° 方向复读。取消/重试、单块复读、手动编辑、复制全部和 TXT/JSON 导出都只作用于 OCR 检测状态。

图片复查的入口有结果行、完整 overlay 和局部 focus preview 三类；编辑、恢复 Vision、单块重识别、重译、忽略、review 和前后导航必须回到发起来源或明确的下一结果。焦点 ID、筛选集合和局部预览生命周期属于 View；block 内容、review progress、failure generation 属于 Store。

## 禁止路径与风险

- View 不直接操作 `TranslationSessionStore.persistenceURL`、模型 runtime 或探针报告。
- “取消重新识别此文字块”只能调用 scoped block cancel；整图取消按钮才调用 `cancelImageTranslation()`。
- `ImageTranslationOverlayBlock` 的竖排绘制必须保持与 OCR `sourceDirection`/overlay mode 的边界，不把显示方向改成 OCR 方向事实。
- OCR 检测页不得调用图片翻译或 LLM；其模型原始 confidence 只用于同引擎复查门控，不能把 Vision 与 Manga OCR 当成同一标尺。
- UI evidence scenario 使用 `MockGemmaService` 和临时 persistence；不要把 preview fixture 当生产 OCR/翻译证据。

## 相关测试

- [`test-v187-ui-interaction-contract.py`](../../../scripts/test-v187-ui-interaction-contract.py)、[`test-v188-home-ui-contract.py`](../../../scripts/test-v188-home-ui-contract.py)：全 App 交互/首页。
- [`test-v313-image-block-focus-contract.py`](../../../scripts/test-v313-image-block-focus-contract.py)、[`test-v3150-image-focus-restore-action-contract.py`](../../../scripts/test-v3150-image-focus-restore-action-contract.py)：图片焦点和恢复动作。
- [`test-v3247-image-ocr-rerecognition-review-focus-contract.py`](../../../scripts/test-v3247-image-ocr-rerecognition-review-focus-contract.py)、[`test-v3248-image-ocr-rerecognition-failure-focus-contract.py`](../../../scripts/test-v3248-image-ocr-rerecognition-failure-focus-contract.py)：重识别完成/失败焦点。
- [`test-v3289-image-ocr-block-structure-editor-contract.py`](../../../scripts/test-v3289-image-ocr-block-structure-editor-contract.py)、[`test-v3289-image-ocr-geometry-editor-contract.py`](../../../scripts/test-v3289-image-ocr-geometry-editor-contract.py)：结构/几何编辑。
- [`test-v3390-image-ocr-detection-ui-contract.py`](../../../scripts/test-v3390-image-ocr-detection-ui-contract.py)：独立 OCR 检测页、CI overlay 别名和版本路由。

## 何时必须更新本索引

新增屏幕、导航 destination、accessibility action、focus handoff、UI evidence scenario 或图片复查入口时更新；纯样式改动只需 `git diff --check`，不扩散到根索引。
