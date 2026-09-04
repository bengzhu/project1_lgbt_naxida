# Agent X 工作台

> 仅供 Agent X `/goal` 全自动托管使用。这里保存当前事实，不追加历史；长期结论写入 `update_log.md`。

## 2026/09/04

### 当前总目标

完成漫画内嵌浏览器广告拦截、DEBUG 请求/DOM 日志、规则更新与原生编译、JS/cosmetic 双层防御、设置/悬浮球联动，以及网页截图 OCR 译文重绘坐标修复；不引入 GPL-3.0 库或代码。

### 约束与验收

- `AdBlockStore` 独立于 `TranslationSessionStore`/`BrowserModel`，以状态机与 Intent 管理规则、任务、错误和 WebView 防护；View 不直接配置拦截器。
- 网络层只用 `WKContentRuleList`；JS 在命名 `WKContentWorld` 中运行；cosmetic 规则必须可逆、域名限定并禁止正文根节点误杀。
- 规则文本可消费 AdGuard/OISD；不复制或链接 GPL converter/scriptlet/ExtendedCSS 代码。所有规则源、许可、接受/跳过语法和缓存版本可追溯。
- DEBUG 日志只观察漫画 WKWebView 的 Resource Timing、资源错误、DOM 插入、媒体、弹窗和导航元数据，不读取请求/响应正文，不进入生产拦截或翻译持久化。
- 重绘使用同一窗口坐标基准映射截图矩形与 SwiftUI overlay；无目标设备证据时只报告合同/编译通过并保留人工测试页流程。
- 每个候选均运行 task-scoped 浏览器合同与当前 SHA 云端 iOS build；通过后 PR 合入 `smalldata_test` 并清理分支。

### 规划小目标（1/4）

| 小目标 | 状态 |
| --- | --- |
| M1 `AdBlockStore`、ETag/版本缓存、保守规则转换与原生双列表编译 | 已合入 `smalldata_test`（PR #468，merge `f3eb639d`；exact-SHA CI success） |
| M2 WKWebView 网络/隔离 JS/cosmetic 接线，设置与悬浮球实时联动 | 实现完成，待提交并跑 exact-SHA CI |
| M3 `#if DEBUG` 浏览器诊断录制、导出、删除与资料库入口 | 待开始 |
| M4 窗口坐标重绘修复、目标站手测流程、架构/索引/许可和总体验收 | 待开始 |

### 已确认事实

- 基线：`smalldata_test@1d4ded92604de130d59fad4eeb02d6952b1d66b7`；开始时本地/远端仅 `main`、`smalldata_test`，工作树干净。
- 2026-09-04 官方网页核验：AdGuard 知识库仍列出 Base、Chinese、Mobile Ads、Popups/Other Annoyances 的 `FiltersRegistry` 订阅；四个选定 raw URL 均返回 HTTP 200 与 ETag。OISD 搜索结果仍列 `big.oisd.nl`/`small.oisd.nl`，但本环境 TLS 直连失败，故只作可失败补充源。
- AdGuard 规则仓库文本标注 GPL-3.0；本目标只按用户授权远端消费数据，不提交规则、不引入其 GPL-3.0 代码。App 端转换器为本项目自研 Swift。
- 现有防护只有两条硬编码域名规则，编译/JS 位于 `BrowserWebView.Coordinator`；`[class*="ad"]` 等宽泛 selector 是页面消失风险，必须拆除。
- 现有 overlay 直接把 `WKWebView.bounds` 中的截图 rect 当 SwiftUI ZStack 本地 rect；WebView 单独 `ignoresSafeArea` 时可能产生固定安全区偏移。

### 当前分支/状态

- 当前分支：`codeb/v3.408-adblock-runtime`；工作树包含 M2 代码、合同和索引改动，尚未提交。
- M2 已通过本地 v3408 运行时合同（5/5）、既有浏览器合同与 AdBlock Swift smoke/typecheck；完整 App build 交给候选 SHA 云端 CI。

### 下一步

提交并 push M2，触发 exact-SHA `[browser-only]` full CI；核对 artifact 与 Xcode build 后创建 PR、合并并清理候选，再进入 M3 DEBUG 诊断日志模块。
