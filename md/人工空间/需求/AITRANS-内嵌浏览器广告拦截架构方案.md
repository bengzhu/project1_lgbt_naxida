# AITRANS 内嵌浏览器广告拦截架构方案

> 面向漫画阅读场景的 WKWebView 广告拦截引擎选型、原生 API 分析与高级对抗技术设计

---

## 0. 结论先行（TL;DR）

1. **规则来源走"搭便车"模式**：以 AdGuard Base + Annoyances(Popups/Other Annoyances) + Mobile Ads + Chinese Filter 为主力，OISD 系列域名黑名单误杀率最低但只能做网络层拦截、没有 cosmetic 能力，两者互补而非二选一。
2. **网络层拦截用苹果原生 `WKContentRuleList`**——免费、不进 JS 环境、页面无法检测到你在拦截，性能最好，但天生不支持 JS 注入和 `:has()` 等扩展语法。
3. **cosmetic / 反检测 / 过程化过滤这部分，不要直接把 AdGuard 的 ExtendedCss / Scriptlets / SafariConverterLib 源码链接进你的 App 二进制**——这几个组件全部是 **GPL-3.0**，闭源商业 App 直接静态链接有著佐权传染风险。推荐架构：规则转换放在**构建期/服务端**跑（用它们的命令行工具，产物只是 JSON/文本数据，不含 GPL 代码），App 端自己写一个几百行的极简执行器去解释这些数据；或者改用 Brave 的 `adblock-rust`（**MPL-2.0**，对闭源商用友好得多）。
4. 你新发现的"点击下一页→弹全屏 AV 播放器，关 7 个才消停"，本质是**广告 SDK 的兜底逃逸行为**：你之前的 CSS 隐藏只是把广告容器藏起来，但触发脚本本身没被网络层拦截，脚本发现自己的正常展示位不可见后，摸底逃逸到"劫持这次点击手势 → 调用原生全屏播放"这条更暴力的路径。真正的解法是**连脚本请求一起在网络层掐断**，而不是只藏 UI。第 6 节给出完整根治方案。

---

## 1. 整体架构（与 `TranslationSessionStore` 模式对齐）

新增一个同级、职责单一的 **`AdBlockStore`**，遵循和 `TranslationSessionStore` 一模一样的纪律：View 只 dispatch intent，`WKWebViewConfiguration`、规则编译、规则更新、JS 注入的生命周期全部由 Store 调度，View 层严禁直接碰 `WKWebViewConfiguration`。

```
┌─────────────────────────────────────────────────────────────┐
│                        MangaReaderView                       │
│   （只做展示 + 发送 intent，例如 .openURL / .reportBadPage）  │
└───────────────────────────┬───────────────────────────────────┘
                             │ intent
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                         AdBlockStore                          │
│  State: rulesVersion, compiledListID, engineMode, lastError   │
│  Intent: .bootstrap / .refreshRules / .attach(to: webView)     │
│  Effect:                                                       │
│   ① RuleFetchTask   —— 拉取远端规则差量(带 ETag)                │
│   ② RuleCompileTask —— 交给 WKContentRuleListStore 编译并缓存    │
│   ③ ScriptInjectTask—— 生成 WKUserScript(cosmetic+反检测+procedural)│
│   ④ 三者都用 Task 句柄持有，新任务发起 = 旧任务 cancel（状态转换）   │
└───────────────────────────┬───────────────────────────────────┘
                             │ 产出 WKWebViewConfiguration
                             ▼
┌─────────────────────────────────────────────────────────────┐
│         WKWebView（由 Store 统一配置 configuration）            │
│  - userContentController.add(compiledContentRuleList)         │
│  - userContentController.addUserScript(cosmeticScript)         │
│  - uiDelegate = PopupGuard（拦截 window.open / 弹窗）            │
└─────────────────────────────────────────────────────────────┘
```

**诊断路径隔离**：规则命中日志、"广告拦截了什么"的调试面板，走单独的 `AdBlockDiagnosticsProbe`，只在 `#if DEBUG` 或专门的诊断 Store slice 里挂载，绝不把 `print`/埋点耦合进生产环境每次的 `WKContentRuleList` 编译或 `WKUserScript` 注入路径——否则每次翻页都要跑一遍诊断逻辑，白白拖慢主路径。

```swift
// MARK: - AdBlockStore 骨架（只展示状态机与并发安全部分）

@MainActor
final class AdBlockStore: ObservableObject {
    enum EngineMode { case native, hybrid } // native=纯WKContentRuleList, hybrid=+procedural引擎

    @Published private(set) var compiledListIdentifier: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: AdBlockError?

    private var refreshTask: Task<Void, Never>?      // 规则刷新任务句柄
    private var compileTask: Task<Void, Never>?       // 编译任务句柄

    enum Intent {
        case refreshRules(force: Bool)
        case attach(to: WKWebViewConfiguration)
    }

    func send(_ intent: Intent) {
        switch intent {
        case .refreshRules(let force):
            // 新任务使旧任务失效：取消是显式的状态转换，不是副作用
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in
                await self?.performRefresh(force: force)
            }
        case .attach(let configuration):
            compileTask?.cancel()
            compileTask = Task { [weak self] in
                await self?.applyCompiledRules(to: configuration)
            }
        }
    }

    private func performRefresh(force: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let ruleData = try await RuleRepository.fetchLatest(force: force)
            try Task.checkCancellation()
            let compiled = try await ContentRuleCompiler.compile(ruleData)
            try Task.checkCancellation()
            compiledListIdentifier = compiled.identifier
        } catch is CancellationError {
            return // 被新任务取代，安静退出，不当错误处理
        } catch {
            lastError = .refreshFailed(error)
        }
    }

    private func applyCompiledRules(to configuration: WKWebViewConfiguration) async {
        guard let identifier = compiledListIdentifier else { return }
        guard let list = try? await WKContentRuleListStore.default()
            .contentRuleList(forIdentifier: identifier) else { return }
        configuration.userContentController.add(list)
        configuration.userContentController.addUserScript(
            CosmeticScriptFactory.makeUserScript()
        )
    }
}
```

---

## 2. 模块一：规则与黑名单调研

| 规则集 | 定位 | 误杀率 | 对漫画/盗版站覆盖 | 维护活跃度 | 建议用途 |
|---|---|---|---|---|---|
| **AdGuard Base + EasyList (Optimized)** | 通用广告网络拦截 | 低 | 高（主流广告SDK覆盖全） | 每日更新 | 主力网络层规则 |
| **AdGuard Annoyances → Popups / Other Annoyances** | 专门对付弹窗、伪装关闭按钮、透明遮罩层 | 低 | **正对你的痛点** | 每日更新 | cosmetic 层主力 |
| **AdGuard Mobile Ads filter** | 移动端专属广告位（插屏、原生广告） | 低 | 高 | 每日更新 | 移动端场景必选 |
| **AdGuard Chinese Filter（含 antiadblock 分区）** | 中文站点专用，含反-反广告拦截规则 | 低（社区中文用户持续反馈） | **已有 colamanga.com、bilinovel.com 等国内主流盗版漫画/轻小说聚合站的专门规则条目**，包括清除广告注入的隐藏规则和绕过反-adblock 检测的脚本 | 活跃（GitHub issue 驱动，用户直接提交问题站点） | 必选，直接命中你的场景 |
| **uBlock Origin 资源库（scriptlet/resource）** | 反-反广告检测的通用脚本片段 | — | 通用性强 | 活跃 | procedural 层执行器的脚本资源来源 |
| **OISD (Big/NSFW 变体)** | 域名级黑名单，只做 DNS/网络层 | **业界最低**（人工审核+自动化测试） | 覆盖恶意软件/成人内容广告网络域名较全 | 活跃 | 作为网络层"第二道保险"，弥补 AdGuard 规则的漏网域名 |

**"搭便车"获取策略**：

- 全部通过公开 CDN/GitHub raw 地址订阅（如 `raw.githubusercontent.com/AdguardTeam/...`），**不接自建标注团队**，App 只做"拉取 → 转换 → 编译 → 缓存"四步流水线。
- 用 HTTP `ETag`/`If-None-Match` 或规则文件里自带的 `! Version:` 注释做增量检测，避免每次启动全量下载（这些规则文件几十上百 KB 到几 MB 不等，全量拉取既费流量也拖慢启动）。
- 更新频率：网络层规则（AdGuard Base/Chinese）建议每 6~12 小时轮询一次；cosmetic/procedural 规则可以更保守，每天一次即可，因为这类规则变更频率远低于广告域名轮换频率。
- **不要自己去"发现"新的广告域名**——AdGuard 的 Chinese Filter 本身就是靠国内用户在 GitHub issue 里提交坏站点驱动更新的，比你自己养一个小规模检测团队效率高得多，这正是"低维护成本"的核心。

---

## 3. 模块二：`WKContentRuleList` 原生方案

### 3.1 工作原理

`WKContentRuleList` 把 JSON 规则**编译成 bytecode**，在网络层（请求发出/响应到达之前）就完成匹配和拦截，**规则从不进入页面的 JS 执行环境，页面也看不到规则**——没有 content script、没有可被探测的注入痕迹，这是它相对"注入 JS 做拦截"的天然优势：反-反广告检测脚本根本没有攻击面可以探测你在用它。

### 3.2 编译与挂载（含缓存复用）

```swift
import WebKit

enum ContentRuleCompiler {
    // identifier 复用是关键：同一份规则内容用同一个 identifier 编译一次后，
    // WKContentRuleListStore 会持久化缓存，下次直接 contentRuleList(forIdentifier:) 取用，
    // 不需要重新编译（编译耗时见下方实测数据）
    static func compile(_ ruleData: CompiledRuleData) async throws -> CompiledResult {
        let identifier = "aitrans_rules_\(ruleData.version)"

        if let cached = try? await WKContentRuleListStore.default()
            .contentRuleList(forIdentifier: identifier) {
            return CompiledResult(identifier: identifier, list: cached)
        }

        return try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: ruleData.json
            ) { list, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let list = list {
                    continuation.resume(returning: CompiledResult(identifier: identifier, list: list))
                }
            }
        }
    }
}
```

规则 JSON 长这样（示例，非真实规则库内容）：

```json
[
  {
    "action": { "type": "block" },
    "trigger": { "url-filter": "ads-network-example\\.com" }
  },
  {
    "action": { "type": "css-display-none", "selector": ".floating-popup-overlay" },
    "trigger": { "url-filter": ".*" }
  }
]
```

### 3.3 致命局限性

| 局限 | 具体表现 | 对你场景的影响 |
|---|---|---|
| **不支持任意 JS 注入** | action 类型只有 `block` / `block-cookies` / `css-display-none` / `make-https` / `ignore-previous-rules`，没有"执行脚本"这个动作 | 无法用它解除长按/右键限制、无法做反-反广告检测的 scriptlet 对抗——这部分必须靠 `WKUserScript` 另开一条腿 |
| **不支持 uBlock 高级语法** | `:has()`/`:contains()` 等 ExtendedCSS 伪类、`##+js()` 脚本注入语法、HTML 过滤规则均**不支持**（HTML 过滤规则官方明确表示"以后也不会支持"） | 复杂 DOM 结构定位（比如"包含某个特征子元素的父容器"）做不到，必须用真正的浏览器 CSS 引擎（见第 5 节，其实 WebKit 原生就支持 `:has()`，走 JS 注入层解决即可） |
| **`$domain` 语法限制** | 不能在同一条规则里混合允许域名和排除域名（如 `$domain=a.com\|~b.com`），"任意 TLD"（`domain.*`）在 Safari 26 以下要靠替换成 Top100 TLD 硬编码兜底 | 转换社区规则时会有少量规则降级/丢失精度，属于可接受损耗 |
| **编译耗时随规则量非线性增长** | 冷编译实测：100 条 0.8ms，1000 条 2.8ms，5000 条 11.5ms，20000 条 46ms，50000 条 119ms | 如果直接怼进 AdGuard Base+Chinese Filter 全量（十万条级别），首次编译可能到几百毫秒到秒级，**必须做规则分层裁剪 + 编译结果持久化缓存**，不要每次冷启动都重新编译 |
| **规则数量配额要分清场景** | Safari 官方对"Safari App/Web Extension"形态的内容拦截器有 150,000 条规则的配额限制（AdGuard for Safari 靠拆成 6 个独立拦截器绕过到 90 万条）；但 AITRANS 是在**自己 App 内直接调用** `WKContentRuleListStore.compileContentRuleList`，不经过 Safari 扩展这套配额体系，实测上限更高（WebKit 侧曾把内部上限从早期版本上调到 30 万条量级） | 不要盲目照搬"Safari 扩展 15 万条"这个数字来限制自己，但**性能优化的必要性不变**——规则越多编译越慢、内存占用越高，建议按"网络层核心规则(几万条) + 按需加载的 Annoyances/Chinese 补充规则"分层组织，而不是一股脑塞一个巨型 JSON |

---

## 4. 模块三：替代/补充引擎方案对比

| 方案 | 网络拦截 | Cosmetic (display:none) | 扩展 CSS(`:has()`等) | Scriptlet/反检测注入 | 许可证 | 闭源商用友好度 | 包体积/内存影响 | 是否可被网页探测 |
|---|---|---|---|---|---|---|---|---|
| **纯 `WKContentRuleList`（苹果原生）** | ✅ | ✅(基础选择器) | ⚠️未文档化保证 | ❌ | 系统 API，无许可证问题 | ✅✅✅ 零风险 | 几乎 0（系统自带引擎） | ✅ 完全无感知（网络层，不进JS环境） |
| **Brave `adblock-rust`** | ✅ | ✅(内置cosmetic filtering) | 需自行拓展匹配逻辑 | ✅(内置 uBO 语法 scriptlet 解析) | **MPL-2.0** | ✅✅ 友好（文件级弱著佐权，正常作为依赖库使用不会传染你的闭源代码） | 中（Rust 静态库几 MB，全量引擎跑在设备端内存占用高于纯声明式方案） | ⚠️ 走 JS 注入执行 cosmetic/scriptlet 部分，存在被探测面，但网络拦截部分同样在原生层完成 |
| **AdGuard 全家桶**（SafariConverterLib + ExtendedCss + Scriptlets） | ✅(经转换为WKContentRuleList) | ✅ | ✅ | ✅ 功能最全，反-反广告规则库随社区持续更新 | **GPL-3.0（三个组件全部是）** | ❌❌ **高法律风险**：直接把源码编译进闭源 App 二进制可能触发著佐权传染，需法务复核；折中方案见下方 3.1 | 视用法 | ⚠️ 同 adblock-rust |
| **eyeo webext-sdk（Adblock Plus内核）** | ✅ | ✅ | 部分 | 部分(snippet filters) | 历史上核心组件多为 GPL，商用需直接联系 eyeo 洽谈授权 | ⚠️ 主要面向 Chromium/Firefox 浏览器扩展（Manifest V2/V3），**没有面向原生 iOS App 内嵌 WKWebView 的官方 SDK**；且默认商业模式是放行"Acceptable Ads"（可配置关闭，但要注意默认行为） | 不适用（非iOS原生形态） | 未知 |

### 4.1 关于 GPL-3.0 的关键架构技巧

AdGuard 的 `SafariConverterLib`（规则格式转换器）、`ExtendedCss`、`Scriptlets` 全部是 **GPL-3.0**。GPL-3.0 是强著佐权协议，如果你把这几个库的源码作为 Swift Package 直接编译进 AITRANS 的 App 二进制，理论上会要求整个组合作品（也就是你的 App）也以 GPL 兼容协议开源——这对一个商业闭源 App 是重大法律风险，**这部分请务必找法务或知识产权律师最终确认**，本文档不构成法律意见。

一个业界常见、风险更低的折中架构：

- **把 `SafariConverterLib` 的 `ConverterTool` 命令行工具放在你自己的构建流水线或后端服务器上跑**（不是 App 运行时链接），输入社区规则文本，输出两份东西：① 标准 `WKContentRuleList` JSON（喂给苹果原生 API，零许可证问题）② `advancedRulesText`（scriptlet/ExtendedCSS 语法的纯文本描述）。
- App 只从你自己的 CDN 下载这两份**数据文件**，不包含任何 GPL 代码本身。
- 数据文件里的 scriptlet/ExtendedCSS 语法，你自己写一个几百行的极简解释器去执行（第 5 节给代码思路）——这是"实现一个众所周知的技术手段"，不涉及复制 AdGuard 的具体代码表达。
- 如果嫌自研解释器麻烦，`adblock-rust`（MPL-2.0）是更省心的替代：直接把整个引擎作为依赖库链接进 App，用它内置的 cosmetic filtering + scriptlet resource assembler，许可证风险小得多。

---

## 5. 模块四：漫画场景高级拦截技术实现

### 5.1 Cosmetic Filtering（元素隐藏）

核心思路：`WKUserScript` 在 `.atDocumentStart` 注入一段 `<style>`，配合 `MutationObserver` 持续清理广告脚本**运行时动态插入**的悬浮层（静态 CSS 规则只能盖住页面加载时就存在的元素，对付不了 JS 运行后才 `appendChild` 进来的假关闭按钮/透明遮罩）。

```swift
enum CosmeticScriptFactory {
    static func makeUserScript() -> WKUserScript {
        let source = """
        (function() {
          const css = `
            .floating-popup-overlay,
            div[class^="layui-layer-"],
            .fake-close-btn,
            [style*="z-index: 999999"] { display: none !important; }
          `;
          const style = document.createElement('style');
          style.textContent = css;
          (document.head || document.documentElement).appendChild(style);

          // 持续清理运行时动态插入的可疑悬浮层：
          // 全屏透明遮罩层的典型特征——position fixed/absolute + 覆盖满屏 + 高 z-index
          const isSuspiciousOverlay = (el) => {
            const rect = el.getBoundingClientRect();
            const style = getComputedStyle(el);
            const coversFullScreen =
              rect.width >= window.innerWidth * 0.9 &&
              rect.height >= window.innerHeight * 0.9;
            const isFloating = style.position === 'fixed' || style.position === 'absolute';
            const highZIndex = parseInt(style.zIndex || '0', 10) > 9999;
            return coversFullScreen && isFloating && highZIndex;
          };

          const observer = new MutationObserver((mutations) => {
            for (const m of mutations) {
              for (const node of m.addedNodes) {
                if (node.nodeType === 1 && isSuspiciousOverlay(node)) {
                  node.remove();
                }
              }
            }
          });
          observer.observe(document.documentElement, { childList: true, subtree: true });
        })();
        """
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false // 广告常年藏在 iframe 里，必须覆盖所有 frame
        )
    }
}
```

> 注意 `isSuspiciousOverlay` 是启发式规则，务必配合 AdGuard Annoyances/Popups 这类**社区维护的精确选择器规则**一起用，别指望纯启发式能覆盖所有变种——这也是为什么第 2 节强调"搭便车"而不是自己造轮子。

### 5.2 Script Injection：解除长按/右键限制 + 反-反广告检测对抗

**解除长按/右键限制**（这是调用本地 Manga OCR 截图的前提，技术上属于"恢复浏览器原生默认行为"，不涉及攻击性代码）：

```javascript
// 很多盗版站为了"防止右键保存图片"，会监听 contextmenu / selectstart / touchstart
// 并 preventDefault，这里在 document 上用捕获阶段抢先拦截，阻止这些监听器生效
['contextmenu', 'selectstart', 'copy', 'dragstart'].forEach(evt => {
  document.addEventListener(evt, (e) => {
    e.stopImmediatePropagation();
  }, true); // 第三个参数 true = 捕获阶段，抢在页面自己的监听器之前执行
});

// 部分站点用 CSS 的 user-select:none / -webkit-touch-callout:none 达到同样效果，一并解除
const style = document.createElement('style');
style.textContent = `* { -webkit-touch-callout: default !important; user-select: auto !important; }`;
document.documentElement.appendChild(style);
```

**反-反广告检测的通用对抗模式**（不针对具体网站的探测代码，讲的是通用技术模式）：反-adblock 脚本常见手法是检测"某个广告容器的 `offsetHeight` 是否为 0"或"某个已知广告变量是否被 noop 化"，社区规则库（AdGuard Chinese Filter 的 antiadblock 分区）里已经积累了大量针对具体站点的 `set-constant`（把检测用的全局变量提前设为无害值）、`prevent-fetch`/`prevent-xhr`（拦截探测用的网络请求）这类 scriptlet。**这部分强烈建议直接消费社区规则数据，而不是自己逐站点摸索**——你截图里提到的"AV 视频广告"背后的广告网络，大概率也已经被社区盯上并有对应的对抗规则。

### 5.3 Procedural Filtering（`:has()` / XPath）

一个重要修正：`WKContentRuleList` 的 JSON 规则语法确实不支持 `:has()` 这类扩展 CSS，**但 WKWebView 底层就是完整的 WebKit/Safari 内核，而 Safari 从 15.4 开始就原生支持标准 CSS4 的 `:has()` 选择器**。也就是说，只要你是在 `WKUserScript` 注入的 `<style>` 标签或 `document.querySelectorAll()` 里用 `:has()`，**根本不需要额外的匹配引擎去"桥接"**，原生 CSS 引擎直接就能跑：

```javascript
// 精准剔除"包含某个广告特征子元素的父容器"——原生 :has()，无需额外引擎
const style = document.createElement('style');
style.textContent = `
  div:has(> iframe[src*="ads-network-example"]) { display: none !important; }
  .manga-page-container:has(video[autoplay]) video { display: none !important; }
`;
document.documentElement.appendChild(style);
```

同理，**XPath 也是浏览器原生能力**（`document.evaluate()`，DOM Level 3 标准），如果社区规则里有需要用 XPath 定位的场景，直接用原生 API 即可，同样不需要 Swift/JS 桥接：

```javascript
function removeByXPath(expression) {
  const result = document.evaluate(
    expression, document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null
  );
  for (let i = 0; i < result.snapshotLength; i++) {
    result.snapshotItem(i).remove();
  }
}
```

真正"原生 API 不支持、需要自己桥接"的只有 uBlock 语法里那些**非标准的自定义伪类**（比如 `:xpath()`、`:matches-css()` 这类 AdGuard/uBO 自造的语法糖），这部分需要你自己写一个几十行的小型解析器，把这些语法糖翻译成上面两种原生 API 调用——工作量比想象中小很多，因为真正的匹配能力都是浏览器原生给的，你只是在做语法转换。

---

## 6. 专题根治：点击「下一页」触发全屏 AV 广告弹窗

### 6.1 现象诊断

结合你的描述（"苹果播放器样式"= 原生 `<video>` 走 `webkitEnterFullscreen()` 进入系统级全屏播放器；"点下一页触发"；"关 7 个左右就没了"；"之前基础屏蔽掉了，结果现在强制全屏"），这是一个非常典型的**广告 SDK 兜底逃逸 + 点击劫持**组合拳：

1. **点击劫持**：广告脚本在 `document` 上挂了捕获阶段的点击/触摸监听器，或者在"下一页"按钮上方叠了一层透明遮罩。你点"下一页"这个手势，第一时间被广告脚本截获。
2. **借手势办事**：iOS 的视频自动播放策略要求"必须有真实用户手势触发"，广告脚本正是**借用你点下一页这个真实手势**，在同一个事件回调里同步调用 `video.play()` + `video.webkitEnterFullscreen()`，WebKit 认为这是合法的用户发起操作，于是放行。
3. **兜底逃逸是关键**：你之前用 CSS 把广告的正常展示位 `display:none` 掉了，但**触发广告的那段 JS 脚本请求本身没有被网络层拦截**，脚本照常加载执行；很多视频广告 SDK 的逻辑是"如果检测到自己该展示的容器不可见/尺寸为0，就升级到全屏兜底模式硬广"——你只藏了 UI，没掐掉脚本，反而把它从"安分的内嵌广告"逼成了"更暴力的全屏弹窗广告"。
4. **7 个左右就没了**：符合广告联盟"瀑布流"投放的典型行为——多个广告网络按顺序轮流尝试展示，每个网络都有自己的单次会话曝光频次上限，全部触顶后自然停止。

### 6.2 分层根治方案

**第一层：从根上掐断脚本请求（最重要，优先做）**

用 Mac 上的 Safari Web Inspector 远程调试 WKWebView（Safari → 开发 → 你的设备 → 对应页面），在点击"下一页"的瞬间观察 Network 面板，抓到实际发起视频广告的那个脚本域名，把它加入你的 `WKContentRuleList` 高优先级自定义黑名单（不要只等社区规则更新，遇到新域名先自己临时加，同时上报给对应的 issue tracker）。这一步做对了，后面的防御层基本用不上。

**第二层：`WKUIDelegate` 拦截弹窗/新窗口**

```swift
final class PopupGuard: NSObject, WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // 返回 nil = 直接拒绝创建新窗口，绝大多数弹窗式/popunder 广告靠 window.open() 实现，
        // 只要不实现这个方法或者返回 nil，这类弹窗从源头上就打不开
        return nil
    }
}

// 配置时保持默认值即可（false），这本身就是最强的一道防线：
// javaScriptCanOpenWindowsAutomatically 默认为 false 时，
// window.open() 根本不会触发 createWebViewWith 这个回调，弹窗直接失败
let preferences = WKPreferences()
preferences.javaScriptCanOpenWindowsAutomatically = false
```

**第三层：媒体播放配置 + 已知 iOS 18 回归问题的兜底**

```swift
let configuration = WKWebViewConfiguration()
configuration.allowsInlineMediaPlayback = true       // 让视频优先走内联播放而不是系统全屏
configuration.mediaTypesRequiringUserActionForPlayback = .all // 要求所有媒体类型都需要真实用户交互
```

⚠️ 已知坑：iOS 18 上有开发者反馈即使设置了 `allowsInlineMediaPlayback = true`，某些视频仍会自动切到全屏（Apple Developer Forums 上有相关报告），**不要只依赖这一个配置项**，务必叠加下面的 JS 层防御。

**第四层：JS 注入兜底——直接废掉原生全屏能力**

考虑到 AITRANS 是漫画阅读器，页面里**理论上不应该有任何合法的全屏原生视频需求**，最简单粗暴也最彻底的方案是把 `webkitEnterFullscreen` 和 `requestFullscreen` 直接 no-op 掉：

```javascript
(function() {
  // 彻底禁用原生视频全屏入口——漫画阅读场景没有合法全屏视频需求，直接锁死
  if (window.HTMLMediaElement) {
    HTMLMediaElement.prototype.webkitEnterFullscreen = function() {
      console.warn('[AITRANS] blocked webkitEnterFullscreen attempt');
    };
  }
  const originalRequestFullscreen = Element.prototype.requestFullscreen;
  Element.prototype.requestFullscreen = function() {
    console.warn('[AITRANS] blocked requestFullscreen attempt');
    return Promise.reject(new Error('blocked by AITRANS'));
  };

  // 强制所有 video 元素带上 playsinline，多一层保险
  const forceInline = (video) => {
    video.setAttribute('playsinline', 'true');
    video.setAttribute('webkit-playsinline', 'true');
  };
  document.querySelectorAll('video').forEach(forceInline);
  new MutationObserver((mutations) => {
    for (const m of mutations) {
      for (const node of m.addedNodes) {
        if (node.nodeName === 'VIDEO') forceInline(node);
        if (node.querySelectorAll) node.querySelectorAll('video').forEach(forceInline);
      }
    }
  }).observe(document.documentElement, { childList: true, subtree: true });
})();
```

这段脚本用 `.atDocumentStart` 注入、`forMainFrameOnly: false`（覆盖 iframe），放进 `AdBlockStore` 统一管理的 `WKUserScript` 列表里即可，和第 5.1 节的 cosmetic 脚本合并成一个 `CosmeticScriptFactory` 产出。

### 6.3 效果预期

第一层（网络拦截）生效后，理想情况下这个广告网络的脚本根本不会被加载，后面三层完全用不上；第二到第四层是"万一漏网之鱼"的纵深防御。四层叠加之后，即便某天又冒出一个新的广告联盟用同样的套路，用户体验上的最坏情况也只是"安静地什么都没发生"，而不是"手动关 7 个全屏弹窗"。

---

## 7. 踩坑清单

| 坑 | 说明 | 应对 |
|---|---|---|
| 内存限制 | 大规则集 + adblock-rust/自研引擎常驻内存，叠加 llama.cpp 模型本身就吃内存，iOS 后台/前台内存压力下容易被系统杀掉 | 规则引擎和 GGUF 推理引擎错峰加载；监听 `didReceiveMemoryWarning` 主动释放非核心规则的编译产物缓存 |
| WKWebView 跨域问题 | 注入的 `WKUserScript` 默认作用域是 page world，可能和站点自身脚本变量冲突；iframe 广告和主 frame 跨域时，某些 DOM 读取会被跨域策略挡住 | 用 `WKContentWorld` 隔离你的注入脚本（避免污染/被污染页面全局变量）；跨域 iframe 内容拿不到就靠网络层拦截兜底，不强求 JS 层一定能摸到 |
| 编译耗时拖慢首帧 | 全量规则冷编译可能到几百毫秒 | 编译结果用 `WKContentRuleListStore` 的 identifier 缓存复用，只有规则版本变化才重新编译；App 启动时先用上一次缓存的规则给 WebView 用，编译新规则放后台异步跑，下次生效 |
| GPL 传染风险 | 见第 4.1 节 | 构建期跑转换工具、App 只消费数据文件；或改用 MPL-2.0 的 adblock-rust；务必让法务复核最终方案 |
| 过度激进的 cosmetic 规则误伤正常翻页 UI | 启发式全屏遮罩检测（5.1节）可能误伤漫画阅读器自己的全屏阅读模式/加载中蒙层 | 给自己 App 的合法全屏元素打上白名单 class/data 属性，检测逻辑里先排除；上线前用真机在多个尺寸/机型上跑一遍回归 |
| iOS 18 `allowsInlineMediaPlayback` 已知失效场景 | 见 6.2 节第三层 | 不要单独依赖配置项，务必叠加 JS 层的 `webkitEnterFullscreen` 拦截 |

---

## 参考资料

- WKContentRuleList 编译性能实测：https://avelino.run/an-engine-is-not-a-benchmark/
- WKContentRuleList 规则上限调整历史：https://bugs.webkit.org/show_bug.cgi?id=205719
- Brave adblock-rust（MPL-2.0）：https://github.com/brave/adblock-rust
- AdGuard SafariConverterLib（GPL-3.0，含支持/不支持规则的完整清单）：https://github.com/AdguardTeam/SafariConverterLib
- AdGuard 过滤器分类说明：https://adguard.com/kb/general/ad-filtering/adguard-filters/
- AdGuard Chinese Filter（antiadblock 分区）：https://github.com/AdguardTeam/AdguardFilters
- iOS 18 `allowsInlineMediaPlayback` 已知问题讨论：https://developer.apple.com/forums/thread/764194
