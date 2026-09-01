# 应用状态与界面

> 状态：current。按运行时状态 ownership 和 UI 投影划分，不把 SwiftUI 文件夹视为独立业务层。

## 边界

本模块负责 App 启动、五个工作区、`TranslationSessionStore` 的状态/任务生命周期、历史与图片复查操作，以及持久化快照的产品投影。OCR、模型推理和 Speech 算法由相邻模块拥有；View 只能通过 Store 的公开方法触发变化。

## 快速定位

| 任务/符号 | 文件 | 入口 |
| --- | --- | --- |
| App 入口与 Store 注入 | [`AITRANS/App/AITRANSApp.swift`](../../../AITRANS/App/AITRANSApp.swift) | `AITRANSApp` |
| 五个 tab、Phone/iPad 路由 | [`AITRANS/Views/ContentView.swift`](../../../AITRANS/Views/ContentView.swift) | `AppTab`、`ContentView`、`AppTabRouter` |
| 统一运行时状态/任务调度 | [`AITRANS/Services/TranslationSessionStore.swift`](../../../AITRANS/Services/TranslationSessionStore.swift) | `TranslationSessionStore` |
| 会话、图片 block、持久化模型 | [`AITRANS/Models/TranscriptModels.swift`](../../../AITRANS/Models/TranscriptModels.swift) | `TranscriptLine`、`ImageTranslationBlock`、`ImageTranslationPersistenceSnapshot`、`TranslationSessionRecord` |
| OCR 复查摘要与筛选 | [`AITRANS/Models/ImageOCRResultSummary.swift`](../../../AITRANS/Models/ImageOCRResultSummary.swift)、[`ImageOCRReviewFilter.swift`](../../../AITRANS/Models/ImageOCRReviewFilter.swift) | `ImageOCRResultSummary`、`ImageOCRReviewFilter` |
| 图片结构/几何编辑 | [`AITRANS/Views/ImageOCRBlockStructureEditor.swift`](../../../AITRANS/Views/ImageOCRBlockStructureEditor.swift)、[`ImageOCRGeometryEditor.swift`](../../../AITRANS/Views/ImageOCRGeometryEditor.swift) | editor Views |

## 上下游与权威状态

```text
AITRANSApp
  -> ContentView / AppTabRouter
  -> TranslationSessionStore
     -> OCR / translation / Speech services
  -> TextTranslationView / ImageTranslationViews / AudioTranslationView / ...
```

`TranslationSessionStore` 拥有当前 transcript、history、model 状态、图片 task、图片 blocks、翻译/复查进度、取消 generation、导出状态和持久化入口。View 的 `@State` 只保存导航、筛选、焦点、sheet 等展示状态；`ImageTranslationBlock` 是产品层 block，OCR 的 candidate/provenance/owner ledger 不应直接写入其中。

## 高风险边界

- UI 不直接调用模型、OCR、Speech 或 `persist()`；新增动作先确认是否应成为 Store API。
- 图片整图 task、单 block retry、单 block rerecognition 和 correction 使用不同的 task/generation；局部取消不得清除整图结果或复查进度。
- 新图、清空、整图取消和过期回调必须隔离 `imageTranslationTaskID`；旧异步结果不得覆盖新会话。
- 复查焦点、筛选和局部预览是 View 投影；reviewed/ignored/corrected 的真实集合由 Store 管理。
- 修改 `ImageTranslationPersistenceSnapshot`、图片文件生命周期或 `TranslationSessionRecord` 时，必须同时检查持久化合同和历史/分享路径。

## 相关索引

- [`状态、任务与持久化`](index-app-state.md)
- [`UI 路由与复查操作`](index-app-ui.md)
- [`图片 OCR 主路径`](../index-image/index-image-ocr.md)
- [`翻译运行时`](../index-translation/index-translation-runtime.md)
- [`完整 App 文件图`](../index-assets/index-assets-file-map.md)

## 何时更新本索引

新增工作区、改变 Store ownership、改变图片 session/persistence schema、移动 View/Model/Service 文件，或新增跨模块调用边界时更新本页；单纯文案/局部布局只更新对应 UI 三级索引。
