# 完整 App/资源/工程文件图

> 状态：current。此页用精确路径把当前 tracked App 文件接入索引；大型合同/benchmark 使用稳定 glob，见[`合同目录`](../index-validation/index-validation-contracts.md)。新增文件后必须归入相应分组。

## App 入口

- [`AITRANS/App/AITRANSApp.swift`](../../../AITRANS/App/AITRANSApp.swift)

## Models

| 文件 | 主题 |
| --- | --- |
| [`BrowserModel.swift`](../../../AITRANS/Models/BrowserModel.swift) | 漫画浏览器 tabs/activeTabID、网页阶段、缩略图、滚动和导航状态 |
| [`ImageOCRProvenance.swift`](../../../AITRANS/Models/ImageOCRProvenance.swift) | candidate/engine/crop/selector provenance |
| [`ImageOCRResultSummary.swift`](../../../AITRANS/Models/ImageOCRResultSummary.swift) | confidence、review、direction 摘要 |
| [`ImageOCRReviewFilter.swift`](../../../AITRANS/Models/ImageOCRReviewFilter.swift) | 图片复查筛选 |
| [`ImageTranslationRenderSafety.swift`](../../../AITRANS/Models/ImageTranslationRenderSafety.swift) | 图片 overlay/export 安全 |
| [`JapaneseOCRTextNormalizer.swift`](../../../AITRANS/Models/JapaneseOCRTextNormalizer.swift) | 日语 OCR 文本归一化 |
| [`KoharuMaskPayloadEvaluator.swift`](../../../AITRANS/Models/KoharuMaskPayloadEvaluator.swift) | Koharu mask payload report evaluator |
| [`LocalModelPromptProfile.swift`](../../../AITRANS/Models/LocalModelPromptProfile.swift) | chat/fallback prompt profile |
| [`SpeechQualityModels.swift`](../../../AITRANS/Models/SpeechQualityModels.swift) | Speech corpus/report schema |
| [`TranscriptModels.swift`](../../../AITRANS/Models/TranscriptModels.swift) | session、transcript、image/manga/probe models |
| [`TranslationContextQuality.swift`](../../../AITRANS/Models/TranslationContextQuality.swift) | text kind、term/context、translation QA |

## Services

| 文件 | 主题 |
| --- | --- |
| [`AppleTranslationService.swift`](../../../AITRANS/Services/AppleTranslationService.swift) | Apple Translation 适配、语言映射、批量请求与生命周期 |
| [`BrowserDebugLogStore.swift`](../../../AITRANS/Services/BrowserDebugLogStore.swift) | DEBUG-only 漫画 WKWebView 元数据录制、持久化、导出与删除 |
| [`ComicTextBubbleDetectorService.swift`](../../../AITRANS/Services/ComicTextBubbleDetectorService.swift) | bundled Core ML 漫画文字区域检测 |
| [`GemmaLocalService.swift`](../../../AITRANS/Services/GemmaLocalService.swift) | 本地 GGUF 翻译/总结 service |
| [`ImageOCRLayoutEngine.swift`](../../../AITRANS/Services/ImageOCRLayoutEngine.swift) | OCR geometry、融合、阅读顺序 |
| [`ImagePreviewService.swift`](../../../AITRANS/Services/ImagePreviewService.swift) | 图片解码/预览缩放 |
| [`LlamaRuntime.swift`](../../../AITRANS/Services/LlamaRuntime.swift) | llama.cpp model/context/sampler |
| [`LocalModelDownloadService.swift`](../../../AITRANS/Services/LocalModelDownloadService.swift) | GGUF 下载、校验、安装 |
| [`MangaOCRService.swift`](../../../AITRANS/Services/MangaOCRService.swift) | bundled Manga OCR 单 crop/batch |
| [`MangaOverlayProbeService.swift`](../../../AITRANS/Services/MangaOverlayProbeService.swift) | 漫画覆盖诊断/探针 |
| [`MockGemmaService.swift`](../../../AITRANS/Services/MockGemmaService.swift) | Preview/UI evidence mock |
| [`SpeechQualityEvaluator.swift`](../../../AITRANS/Services/SpeechQualityEvaluator.swift) | Speech 指标计算 |
| [`SpeechQualityProbeService.swift`](../../../AITRANS/Services/SpeechQualityProbeService.swift) | Speech corpus 运行/报告 |
| [`TranslationSessionStore.swift`](../../../AITRANS/Services/TranslationSessionStore.swift) | App 状态与跨模块调度中心 |
| [`VisionOCRService.swift`](../../../AITRANS/Services/VisionOCRService.swift) | Apple Vision OCR 与日语候选恢复 |

## Views

| 文件 | 主题 |
| --- | --- |
| [`AppleTranslationTaskHost.swift`](../../../AITRANS/Views/AppleTranslationTaskHost.swift) | SwiftUI `translationTask` 系统会话宿主 |
| [`AppComponents.swift`](../../../AITRANS/Views/AppComponents.swift) | 共用组件 |
| [`AppPreviewSupport.swift`](../../../AITRANS/Views/AppPreviewSupport.swift) | Preview/UI evidence scenario |
| [`AppTheme.swift`](../../../AITRANS/Views/AppTheme.swift) | 主题与布局常量 |
| [`AudioTranslationView.swift`](../../../AITRANS/Views/AudioTranslationView.swift) | 音频 UI |
| [`BrowserDebugLogView.swift`](../../../AITRANS/Views/BrowserDebugLogView.swift) | DEBUG-only 浏览器诊断日志管理、详情与导出 |
| [`ContentView.swift`](../../../AITRANS/Views/ContentView.swift) | 根路由/tab |
| [`DeveloperConsoleView.swift`](../../../AITRANS/Views/DeveloperConsoleView.swift) | 开发者诊断 UI |
| [`HistoryView.swift`](../../../AITRANS/Views/HistoryView.swift) | 历史会话 UI |
| [`ImageOCRBlockStructureEditor.swift`](../../../AITRANS/Views/ImageOCRBlockStructureEditor.swift) | block split/merge/move editor |
| [`ImageOCRGeometryEditor.swift`](../../../AITRANS/Views/ImageOCRGeometryEditor.swift) | geometry editor |
| [`ImageOCRProvenanceDisclosureView.swift`](../../../AITRANS/Views/ImageOCRProvenanceDisclosureView.swift) | provenance disclosure |
| [`ImageTranslationViews.swift`](../../../AITRANS/Views/ImageTranslationViews.swift) | 图片 OCR/翻译/overlay/复查 UI |
| [`MangaBrowserView.swift`](../../../AITRANS/Views/MangaBrowserView.swift) | 单活动 WKWebView、Safari 胶囊、标签切换器和翻译球占位 UI |
| [`ModelManagementView.swift`](../../../AITRANS/Views/ModelManagementView.swift) | 本地模型管理 |
| [`ProFeatureViews.swift`](../../../AITRANS/Views/ProFeatureViews.swift) | Pro/能力状态 UI |
| [`PromptLibraryView.swift`](../../../AITRANS/Views/PromptLibraryView.swift) | prompt library/editor |
| [`SettingsView.swift`](../../../AITRANS/Views/SettingsView.swift) | 设置/开发者入口 |
| [`TextTranslationView.swift`](../../../AITRANS/Views/TextTranslationView.swift) | 文本翻译 UI |
| [`TextWorkspaceBackground.swift`](../../../AITRANS/Views/TextWorkspaceBackground.swift) | 文本工作区背景 |
| [`TextWorkspacePasteButton.swift`](../../../AITRANS/Views/TextWorkspacePasteButton.swift) | 粘贴入口 |

## Product resources

| 路径 | 内容 |
| --- | --- |
| [`AITRANS/Resources/Assets.xcassets/`](../../../AITRANS/Resources/Assets.xcassets/) | 16 个 colorset/icon 内容文件 |
| [`AITRANS/Resources/ComicTextDetector/`](../../../AITRANS/Resources/ComicTextDetector/) | `ComicTextBubbleDetectorINT8.mlpackage`、conversion、license、notice |
| [`AITRANS/Resources/MangaOCR/`](../../../AITRANS/Resources/MangaOCR/) | 4 个 Core ML package、词表、conversion、license、notice |
| [`AITRANS/Resources/Info.plist`](../../../AITRANS/Resources/Info.plist) | bundle/权限配置 |

## 工程与验证入口

- [`AITRANS.xcodeproj/project.pbxproj`](../../../AITRANS.xcodeproj/project.pbxproj)
- [`.github/workflows/ci-results.yml`](../../../.github/workflows/ci-results.yml)
- [`.github/workflows/test2-image-translation-ui.yml`](../../../.github/workflows/test2-image-translation-ui.yml)
- [`.github/workflows/koharu-mit48-parity.yml`](../../../.github/workflows/koharu-mit48-parity.yml)
- [`.github/workflows/build.yml`](../../../.github/workflows/build.yml)
- [`build-apple/llama.xcframework/`](../../../build-apple/llama.xcframework/)（tracked build dependency）

## 测试输入

- [`test/1.ground_truth.json`](../../../test/1.ground_truth.json)
- [`test/1.png`](../../../test/1.png)
- [`test/2.png`](../../../test/2.png)
- [`test/jap.jpg`](../../../test/jap.jpg)
- [`test/speech_corpus/`](../../../test/speech_corpus/)

## 维护方式

`AITRANS/` 的 Swift 文件必须出现在本页对应表格；资源新增时补路径和用途。`scripts/` 的 420 个版本合同不复制到本页，统一由 [`scripts/test-v*.py`](../index-validation/index-validation-contracts.md) glob 覆盖，评估器/runner/fixture 由同页入口覆盖。
