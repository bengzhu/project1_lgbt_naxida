# UI 路由与图片复查操作

> 状态：current。View 是 Store 的展示/动作投影；本页只保留入口和高风险交互路由。

## 快速定位

| 屏幕/主题 | 文件 | 关键符号 |
| --- | --- | --- |
| 根路由、tab、Phone/iPad | [`AITRANS/Views/ContentView.swift`](../../../AITRANS/Views/ContentView.swift) | `ContentView`、`PhoneRootView`、`TabletRootView`、`AppTabRouter`、`LibraryHubView` |
| Apple Translation 会话宿主 | [`AITRANS/Views/AppleTranslationTaskHost.swift`](../../../AITRANS/Views/AppleTranslationTaskHost.swift) | `AppleTranslationTaskHost`、`translationTask` |
| 视觉系统与共享组件 | [`AppTheme.swift`](../../../AITRANS/Views/AppTheme.swift)、[`AppComponents.swift`](../../../AITRANS/Views/AppComponents.swift) | `AppFeature`、`AppPageHeader`、`AppCanvasBackground`、`appSurface` |
| 文本翻译 | [`AITRANS/Views/TextTranslationView.swift`](../../../AITRANS/Views/TextTranslationView.swift) | `TextTranslationView`、`TranslationInputPane`、`TranslationOutputPane`、`TextSessionUtilityBar` |
| 图片翻译主屏 | [`AITRANS/Views/ImageTranslationViews.swift`](../../../AITRANS/Views/ImageTranslationViews.swift) | `ImageTranslationView`、`ImageTranslationPanel`、`ImageTranslationPreview` |
| 漫画内嵌浏览器 | [`AITRANS/Views/MangaBrowserView.swift`](../../../AITRANS/Views/MangaBrowserView.swift)、[`AITRANS/Models/BrowserModel.swift`](../../../AITRANS/Models/BrowserModel.swift) | `MangaBrowserView`、`BrowserWebView`、`BrowserModel` |
| OCR 检测工作台 | [`AITRANS/Views/ImageOCRDetectionView.swift`](../../../AITRANS/Views/ImageOCRDetectionView.swift) | `ImageOCRDetectionView`、`ImageOCRDetectionCanvas`、`ImageOCRDetectionResultRow`、`OCRDetectionDiagnostics` |
| 图片结果行/局部预览/编辑 | 同上 | `ImageTranslationBlockRow`、`ImageTranslationFocusPreview`、`ImageOCRCorrectionSheet` |
| 图片 overlay/竖排显示 | 同上 | `ImageTranslationOverlayBlock`、`ImageTranslationVerticalText` |
| 图片结构/几何编辑 | [`ImageOCRBlockStructureEditor.swift`](../../../AITRANS/Views/ImageOCRBlockStructureEditor.swift)、[`ImageOCRGeometryEditor.swift`](../../../AITRANS/Views/ImageOCRGeometryEditor.swift) | editor Views |
| 音频、历史、设置 | [`AudioTranslationView.swift`](../../../AITRANS/Views/AudioTranslationView.swift)、[`HistoryView.swift`](../../../AITRANS/Views/HistoryView.swift)、[`SettingsView.swift`](../../../AITRANS/Views/SettingsView.swift) | `AudioWorkspaceMode`、`SpeechCapabilityDisclosure`、历史操作 `Menu`、`SettingsAdvancedSection` |
| Prompt/引擎/模型/Developer Console | [`PromptLibraryView.swift`](../../../AITRANS/Views/PromptLibraryView.swift)、[`ModelManagementView.swift`](../../../AITRANS/Views/ModelManagementView.swift)、[`DeveloperConsoleView.swift`](../../../AITRANS/Views/DeveloperConsoleView.swift) | settings destinations、翻译引擎菜单 |
| UI evidence fixtures | [`AITRANS/Views/AppPreviewSupport.swift`](../../../AITRANS/Views/AppPreviewSupport.swift) | `AppPreviewScenario` |

## 操作数据流

```text
View action / accessibility action
  -> TranslationSessionStore public method
  -> @Published state + focus generation
  -> View updates focus/preview/filter
```

iPhone `TabView` 增加“漫画”，一级项为文本、图片、漫画、OCR、音频、资料库；紧凑宽度下由系统承载超出五项的 More 导航。历史与设置从资料库的两个大入口进入。资料库拥有手机端下钻导航栈，设置作为 destination 复用该导航上下文，不再嵌套第二个 `NavigationStack`；设置独立展示时仍自带导航容器。iPad 侧栏把漫画归入“创作”，OCR 保持独立“工具”。这些布局不合并图片翻译、OCR-only 工作台或网页浏览边界。

七个功能域通过 `AppFeature` 同时绑定编号、英文眉题、图标和自适应浅/深色功能色；颜色不是唯一识别手段。共享页面顶栏采用标准字号下 92pt 的紧凑横向基线并填满页面内容宽度，动态字体可按内容向下扩展以避免裁切；入场动效必须响应 Reduce Motion，描边必须响应 Increase Contrast。

漫画浏览器隐藏 Phone `TabView` 底栏，WKWebView 以白色浅色页面通铺屏幕，并通过顶部 content inset 避开状态栏；左上退出、Safari 式三胶囊底栏和 48pt 翻译球均是覆盖层。下滑时底栏收成 36pt 域名胶囊并同步收起退出/翻译球，上滑或到顶恢复。`BrowserModel` 以 `activeTabID` 管理独立标签值状态；切换前保存缩略图、URL 与滚动位置，后台标签释放 WKWebView，返回时只重建当前实例。翻译菜单与拖拽仍是非持久化展示状态，不接翻译链路。

重点页面采用渐进呈现：文本页只保留输入、译文和会话工具条，不重复展示最近翻译；手机音频页通过分段选择一次显示实时或文件工作区，iPad 保留双栏；历史导入/导出/清理归入操作菜单；设置的 Pro 能力说明和开发解锁归入“高级与开发”折叠区。低频入口收起时不得移除原有 Store action、破坏确认流程或仅靠颜色表达状态。

OCR 检测页是独立的一页式流程：图片/相册/拍照/粘贴自动进入 OCR，原图显示编号框和质量颜色，结果行点击后高亮对应区域；语言与版式分开选择，显式日语竖排才开启 90°/270° 方向复读。取消/重试、单块复读、手动编辑、复制全部和 TXT/JSON 导出都只作用于 OCR 检测状态。

图片复查的入口有结果行、完整 overlay 和局部 focus preview 三类；编辑、恢复 Vision、单块重识别、重译、忽略、review 和前后导航必须回到发起来源或明确的下一结果。焦点 ID、筛选集合和局部预览生命周期属于 View；block 内容、review progress、failure generation 属于 Store。

## 禁止路径与风险

- View 不直接操作 `TranslationSessionStore.persistenceURL`、模型 runtime 或探针报告。
- 漫画浏览器非 http(s) 链接只交系统或显示不支持提示；下载响应不得静默失败，`target=_blank` 必须回到当前 WebView。
- “取消重新识别此文字块”只能调用 scoped block cancel；整图取消按钮才调用 `cancelImageTranslation()`。
- `ImageTranslationOverlayBlock` 的竖排绘制必须保持与 OCR `sourceDirection`/overlay mode 的边界，不把显示方向改成 OCR 方向事实。
- OCR 检测页不得调用图片翻译或 LLM；其模型原始 confidence 只用于同引擎复查门控，不能把 Vision 与 Manga OCR 当成同一标尺。
- UI evidence scenario 使用 `MockGemmaService` 和临时 persistence；不要把 preview fixture 当生产 OCR/翻译证据。

## 相关测试

- [`test-v187-ui-interaction-contract.py`](../../../scripts/test-v187-ui-interaction-contract.py)、[`test-v188-home-ui-contract.py`](../../../scripts/test-v188-home-ui-contract.py)：全 App 交互/首页。
- [`test-v3400-immersive-ui-contract.py`](../../../scripts/test-v3400-immersive-ui-contract.py)、[`test-v3401-focused-workspaces-contract.py`](../../../scripts/test-v3401-focused-workspaces-contract.py)、[`test-v3402-compact-header-settings-contract.py`](../../../scripts/test-v3402-compact-header-settings-contract.py)：功能视觉身份、聚焦工作区、紧凑顶栏、资料库/设置导航所有权和 visual-task CI 路由。
- [`test-v3404-manga-browser-ui-contract.py`](../../../scripts/test-v3404-manga-browser-ui-contract.py)：漫画 tab、BrowserModel/tab ownership、单 WKWebView 生命周期、安全区/浅色页面、Safari 胶囊、失败 UI 与翻译占位菜单的直接静态合同。
- [`test-v313-image-block-focus-contract.py`](../../../scripts/test-v313-image-block-focus-contract.py)、[`test-v3150-image-focus-restore-action-contract.py`](../../../scripts/test-v3150-image-focus-restore-action-contract.py)：图片焦点和恢复动作。
- [`test-v3247-image-ocr-rerecognition-review-focus-contract.py`](../../../scripts/test-v3247-image-ocr-rerecognition-review-focus-contract.py)、[`test-v3248-image-ocr-rerecognition-failure-focus-contract.py`](../../../scripts/test-v3248-image-ocr-rerecognition-failure-focus-contract.py)：重识别完成/失败焦点。
- [`test-v3289-image-ocr-block-structure-editor-contract.py`](../../../scripts/test-v3289-image-ocr-block-structure-editor-contract.py)、[`test-v3289-image-ocr-geometry-editor-contract.py`](../../../scripts/test-v3289-image-ocr-geometry-editor-contract.py)：结构/几何编辑。
- [`test-v3390-image-ocr-detection-ui-contract.py`](../../../scripts/test-v3390-image-ocr-detection-ui-contract.py)：独立 OCR 检测页、CI overlay 别名和版本路由。

## 何时必须更新本索引

新增屏幕、导航 destination、accessibility action、focus handoff、UI evidence scenario 或图片复查入口时更新；纯样式改动只需 `git diff --check`，不扩散到根索引。
