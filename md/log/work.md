# Agent X 工作台

> 仅供 Agent X `/goal` 全自动托管使用。这里保存当前事实，不追加历史；长期结论写入 `update_log.md`。

## 2026/09/04

### 当前总目标

完成漫画浏览器可视区/框选翻译、页面任务契约、浏览器加固与漫画阅读体验；同时让图片和音频在选择 Apple Translation 时走统一系统适配器。主界面 UI 不改，浏览器结果不进入普通图片、OCR-only、Speech 质量参考或历史持久化。

### 约束与验收

- `BrowserModel` 只拥有网页/标签/视口状态；Store 统一拥有 OCR、翻译、缓存、任务门禁和诊断投影。
- 页面身份覆盖 tab/document/navigation/content/layout/scroll generation 与稳定视口；配置、滚动、切页或布局变化先失效旧任务再释放资源。
- 安全、收藏、元素规则仅留在 App 沙盒；性能采样只进浏览器诊断，不改变翻译路由。
- 图片/音频复用 Apple Translation / Gemma / 预留路由；音频参考 transcript 只供事后质量评估。
- 候选 SHA 运行 task-scoped 直接合同与云端 iOS build；通过后再 PR 合并至 `smalldata_test` 并清理分支。

### 规划小目标（实现 4/4，已完成）

| 小目标 | 状态 |
| --- | --- |
| M1 浏览器翻译、框选、页面身份/缓存/资源契约 | 已实现，本地合同通过 |
| M2 广告/弹窗/重定向/元素消除/防劫持与收藏 | 已实现，本地合同通过 |
| M3 字体/字号/中英排版、沉浸 UX、进度与性能诊断 | 已实现，本地合同通过 |
| M4 图片/音频 Apple Translation、模拟器回退与配置竞态 | 已实现，本地合同通过 |

### 当前状态

- 总目标已完成并合入 `smalldata_test`：merge SHA `df15c006baa42c51c0f6d6593c16d3d43d0ec5f9`，PR [#466](https://github.com/bengzhu/project1_lgbt_naxida/pull/466)。候选 `codeb/v3.405-browser-translation` 已删除本地与远端。
- 已排雷：浏览器截图/覆盖身份门禁、截图及时释放、有界缓存、部分失败保留、跨站元素规则隔离、静默外部协议拦截、触摸/剪贴板启发式收紧、英文强制横排、竖排右到左、字号不越 OCR 框、滚动/缩放/加载稳定窗口、导航提交后才签发文档身份、标签缩略图限尺寸、内存警告与后台取消、Apple continuation 取消竞态、音频冻结配置与空 transcript context。
- 本地直接证据：v3.404/v3.405/v3.406、v3.400、Apple 引擎、Speech recognition/quality 合同通过；安全脚本 JS 语法、workflow YAML、plist/project、Markdown 链接与 Swift parse 通过。
- 云端精确候选 full CI：[33798439127](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/33798439127)，SHA `2887dd1959fd82a416a4bc8a9a585a74ca7f8f72`，Xcode 26.6 Simulator build success，JUnit `11/11`，浏览器/媒体/沉浸/Speech 合同通过，artifact 未加密且绑定 branch/SHA/run/profile。PR fast receipt：[33818064416](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/33818064416) 为同一 SHA 且 status success。实现合入后本地已 fast-forward 至 `smalldata_test@df15c006`。
- 未执行：本机完整 iOS build（仅 CommandLineTools）、真机 Apple Translation 语言包/视觉效果、真实网页手势与翻译质量探针；因此不把编译/静态合同外推为真机质量提升。下一步由人工在目标设备验收视觉交互与系统翻译语言包。

### 状态

- `complete`
