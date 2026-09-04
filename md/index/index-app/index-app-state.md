# 应用状态、任务与持久化

> 状态：current。主题是运行时 state ownership 和异步生命周期，不描述每个 View 的布局。

## 快速定位

| 任务/符号 | 文件路径 | 关键入口 |
| --- | --- | --- |
| Store 初始化、恢复、启动任务 | [`AITRANS/Services/TranslationSessionStore.swift`](../../../AITRANS/Services/TranslationSessionStore.swift) | `init`、`restoreSnapshot()`、`runLaunch...IfNeeded()` |
| 翻译引擎选择/持久化 | 同上、[`AITRANS/Models/TranscriptModels.swift`](../../../AITRANS/Models/TranscriptModels.swift) | `selectedEngine`、`selectEngine(_:)`、`AppSettings` |
| 文本翻译 | 同上 | `submitDraft()` |
| 图片会话 | 同上 | `beginImageTranslationTask`、`runImageTranslationPipeline`、`translateImage`、`translateImageData` |
| 浏览器翻译会话 | 同上、[`AITRANS/Models/BrowserModel.swift`](../../../AITRANS/Models/BrowserModel.swift) | `updateBrowserPageIdentity`、`translateBrowserCapture`、`invalidateBrowserTranslation` |
| 浏览器广告规则状态 | [`AITRANS/Services/AdBlockStore.swift`](../../../AITRANS/Services/AdBlockStore.swift)、[`AdBlockModels.swift`](../../../AITRANS/Models/AdBlockModels.swift) | `AdBlockStore.send(_:)`、`AdBlockState`、`AdBlockPreferences` |
| 广告规则缓存/转换 | [`AdBlockRuleRepository.swift`](../../../AITRANS/Services/AdBlockRuleRepository.swift)、[`AdBlockRuleCompiler.swift`](../../../AITRANS/Services/AdBlockRuleCompiler.swift) | `refresh(force:)`、`AdBlockRuleCompiler.compile(_:)` |
| DEBUG 浏览器诊断录制 | [`BrowserDebugLogStore.swift`](../../../AITRANS/Services/BrowserDebugLogStore.swift) | `BrowserDebugLogStore.send(_:)`、`recordScriptMessage`、`recordNavigation`、`exportData(for:)` |
| 音频翻译配置身份 | 同上 | `SpeechTranslationConfiguration`、`beginSpeechRecognitionRun`、`invalidateTranslationRunsForConfigurationChange` |
| 图片单块操作 | 同上 | `retryImageTranslationBlock`、`rerecognizeImageTranslationBlock`、`correctImageTranslationBlock`、`cancelImageTranslationBlockRetry`、`cancelImageTranslationBlockRerecognition` |
| 图片结构/复查 | 同上 | `splitImageTranslationBlock`、`mergeImageTranslationBlocks`、`moveImageTranslationBlock`、`markImageTranslationBlockReviewed`、`ignoreImageTranslationBlock` |
| 整图取消/重试/清空 | 同上 | `cancelImageTranslation`、`retryImageTranslation`、`rerunImageRecognition`、`clearImageTranslation` |
| 会话模型与快照 | [`AITRANS/Models/TranscriptModels.swift`](../../../AITRANS/Models/TranscriptModels.swift) | `ImageTranslationState`、`ImageTranslationBlock`、`ImageTranslationPersistenceSnapshot`、`AppPersistenceSnapshot` |

## 状态流

```text
用户动作
  -> Store 生成 task/generation 并更新 @Published 状态
  -> OCR / model / export service
  -> Store 检查当前 task、revision、block ID
  -> 原子提交成功/失败/取消状态
  -> persist()（只在产品状态边界）
  -> View 从 Store 投影
```

图片会话的输入数据、源文件副本、blocks、Vision baseline、review IDs、ignored snapshots、翻译语言和 overlay/export 状态必须保持同一 session/revision。单块修正/重识别成功时只替换该 block 的产品字段并刷新该 block 翻译；失败或取消保留原 block。

## 权威边界与禁止路径

- `TranslationSessionStore` 是唯一的运行时状态和持久化调度中心；View、Preview 和 evaluator 不可直接写 JSON 或模型状态。
- `AdBlockStore` 是浏览器防护的独立规则状态中心，不进入翻译持久化；规则仓库 actor 负责 ETag、版本缓存与清理，转换 actor 只接受可安全映射到 WebKit 的保守子集，未知语义显式跳过。
- `ImageOCRLayoutBlock`、`ImageOCRCandidate`、shadow ledger 是 OCR 内部/诊断数据；不要把 ephemeral owner、candidate ledger 或 external artifact 字段写入产品 snapshot。
- `CancellationError` 必须经过当前 task/content guard；旧回调只能退出，不能回滚到错误 session。
- 引擎、语言、prompt、术语或采样变化必须先失效活动中的浏览器、图片和音频翻译；音频最终 transcript 使用 run 开始时冻结的配置并排除历史/参考 transcript。
- 改变 snapshot 字段、清理图片目录、分享/导出生命周期时，检查同一 Store 中的 `persistedLocationDisplay`、文件复制和 orphan cleanup。

## 相关测试与测试路由

- [`test-v328-image-review-session-continuity-contract.py`](../../../scripts/test-v328-image-review-session-continuity-contract.py)：复查 session 连续性。
- [`test-v3289-image-translation-session-persistence-contract.py`](../../../scripts/test-v3289-image-translation-session-persistence-contract.py)：快照/图片 session 持久化。
- [`test-v3263-image-ocr-scoped-rerecognition-cancel-contract.py`](../../../scripts/test-v3263-image-ocr-scoped-rerecognition-cancel-contract.py)：单块取消不扩大到整图。
- [`test-v3290-image-translation-render-safety-contract.py`](../../../scripts/test-v3290-image-translation-render-safety-contract.py)：保存前的渲染安全边界。
- [`test-v3407-adblock-foundation-contract.py`](../../../scripts/test-v3407-adblock-foundation-contract.py)、[`test-adblock-rule-compiler.swift`](../../../scripts/test-adblock-rule-compiler.swift) 与 [`test-adblock-rule-repository.swift`](../../../scripts/test-adblock-rule-repository.swift)：广告规则 Store/缓存合同、转换行为和 ETag/304/清理 smoke。
- 涉及 Store/Swift 的改动默认只做静态合同和 `git diff --check`；本机 build/runtime 按 [`AGENTS.md`](../../../AGENTS.md) 交给云端。

浏览器广告运行时接线：

- AdBlockStore.prepareWebViewConfiguration / attachWebView / applyProtection 是唯一的 WKContentRuleList 挂载边界。
- AdBlockWebScript 使用 AITRANS.AdBlock 命名 WKContentWorld，处理自动播放/全屏、复制限制和明确反广告检测兜底。
- 设置页与翻译悬浮球只发送 AdBlockStore Intent；开关即时更新且不重建 WKWebView。

对应测试：scripts/test-v3408-adblock-runtime-contract.py。

DEBUG 浏览器日志链路由 `BrowserDebugLogStore` 独立持有：命名 `WKContentWorld` 只上报 Resource Timing、资源错误、DOM 插入、媒体、弹窗和导航元数据；当前 tab identity 门控事件，限制每会话 2,000 条、最多 20 个会话，停止后才落盘并允许 JSON 导出/删除。脚本与悬浮球/资料库入口均在 `#if DEBUG` 下，永不进入广告拦截或翻译状态。

对应测试：`scripts/test-v3409-browser-debug-log-contract.py`。

## 何时必须更新本索引

新增 `@Published` 权威状态、task/generation、snapshot 字段、Store public action、文件清理或取消/恢复语义时更新；只改 View 的焦点或文案转到 [`UI 路由与复查操作`](index-app-ui.md)。
