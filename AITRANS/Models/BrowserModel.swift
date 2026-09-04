import Observation
import CryptoKit
import Foundation
import UIKit
import WebKit

enum BrowserTranslationPhase: String, Equatable, Sendable {
    case idle
    case capturing
    case recognizing
    case translating
    case completed
    case partial
    case failed

    var isRunning: Bool {
        switch self {
        case .capturing, .recognizing, .translating: true
        case .idle, .completed, .partial, .failed: false
        }
    }
}

struct BrowserTranslationStatus: Equatable, Sendable {
    var phase: BrowserTranslationPhase
    var completedRegions: Int
    var totalRegions: Int
    var failedRegions: Int = 0
    var message: String
    var estimatedDurationMilliseconds: Int?
    var startedAt: Date?

    static let idle = Self(
        phase: .idle,
        completedRegions: 0,
        totalRegions: 0,
        message: "等待翻译",
        estimatedDurationMilliseconds: nil,
        startedAt: nil
    )

    var fractionCompleted: Double {
        guard totalRegions > 0 else {
            return phase == .completed ? 1 : 0
        }
        let processed = completedRegions + failedRegions
        return min(max(Double(processed) / Double(totalRegions), 0), 1)
    }
}

struct BrowserPerformanceSample: Equatable, Sendable {
    var stage: String
    var timestamp: Date
    var captureBytes: Int
    var physicalMemoryBytes: UInt64
    var processorCount: Int
    var activeProcessorCount: Int
    var residentMemoryBytes: UInt64
    var processCPUTimeMilliseconds: Int64
    var thermalState: String
}

/// Immutable page/viewport identity. URL alone is intentionally insufficient:
/// delayed DOM updates, scrolling and relayout each rotate a generation.
struct BrowserPageSnapshotIdentity: Hashable, Sendable {
    static let schemaVersion = 1

    var tabID: UUID
    var documentID: UUID
    var normalizedURL: String
    var navigationGeneration: Int
    var contentGeneration: Int
    var layoutGeneration: Int
    var scrollGeneration: Int
    var viewportWidth: Double
    var viewportHeight: Double
    var documentOffsetX: Double
    var documentOffsetY: Double
    var isStable: Bool

    var schemaKey: String { "browser-page-v\(Self.schemaVersion)" }
}

struct BrowserCaptureSelection: Equatable, Sendable {
    /// Coordinates are in the WKWebView bounds-local point space. MangaBrowserView
    /// reverse-maps its SwiftUI root selection before constructing this value.
    var rectInView: CGRect
}

struct BrowserPageCaptureMetadata: Equatable, Sendable {
    var identity: BrowserPageSnapshotIdentity
    var captureID: UUID
    /// WebView bounds-local point space; map through the WebView frame before
    /// drawing SwiftUI overlays.
    var captureRectInView: CGRect
    var contentRectInView: CGRect
    var visibleDocumentRectCSS: CGRect
    var capturePixelSize: CGSize
    var scale: CGFloat
    var captureSHA256: String
}

struct BrowserPageCapture: @unchecked Sendable {
    var identity: BrowserPageSnapshotIdentity
    var captureID: UUID
    var imageData: Data
    /// WebView bounds-local point space; never use as a SwiftUI root position
    /// without the frame-origin transform owned by MangaBrowserView.
    var captureRectInView: CGRect
    var contentRectInView: CGRect
    var visibleDocumentRectCSS: CGRect
    var capturePixelSize: CGSize
    var scale: CGFloat
    var captureSHA256: String

    var metadata: BrowserPageCaptureMetadata {
        BrowserPageCaptureMetadata(
            identity: identity,
            captureID: captureID,
            captureRectInView: captureRectInView,
            contentRectInView: contentRectInView,
            visibleDocumentRectCSS: visibleDocumentRectCSS,
            capturePixelSize: capturePixelSize,
            scale: scale,
            captureSHA256: captureSHA256
        )
    }
}

struct BrowserTranslationRegion: Identifiable, Equatable, Sendable {
    var id: UUID
    var original: String
    var translation: String
    var confidence: Float
    var boundingBox: NormalizedImageRect
    var documentRectCSS: CGRect
    var readingOrder: Int
    var sourceDirection: ImageTextDirection?
    var sourceFingerprint: String
    var translationError: String?
}

struct BrowserTranslationOverlaySnapshot: Equatable, Sendable {
    var identity: BrowserPageSnapshotIdentity
    var captureRectInView: CGRect
    var contentRectInView: CGRect
    var regions: [BrowserTranslationRegion]
    var renderRevision: Int
}

enum BrowserCaptureError: LocalizedError {
    case noWebView
    case unstableViewport
    case invalidContentRect
    case selectionTooSmall
    case snapshotFailed
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .noWebView: "网页尚未准备好，请稍后重试。"
        case .unstableViewport: "请先停下滚动，再开始翻译。"
        case .invalidContentRect: "当前可视内容区域不可用，请重试。"
        case .selectionTooSmall: "框选区域太小，请拖动选择包含文字的区域。"
        case .snapshotFailed: "无法截取当前网页内容，请重试。"
        case .imageEncodingFailed: "无法准备 OCR 图片，请重试。"
        }
    }
}

struct BrowserSecurityConfiguration: Equatable, Sendable {
    var blockAds: Bool
    var blockPopups: Bool
    var blockRedirects: Bool
    var elementRemovalEnabled: Bool
    var antiHijackingEnabled: Bool

    static let `default` = Self(
        blockAds: true,
        blockPopups: true,
        blockRedirects: true,
        elementRemovalEnabled: false,
        antiHijackingEnabled: true
    )

    var fingerprint: String {
        [blockAds, blockPopups, blockRedirects, elementRemovalEnabled, antiHijackingEnabled]
            .map { $0 ? "1" : "0" }
            .joined()
    }
}

struct BrowserBookmark: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var urlString: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, urlString: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
    }

    var url: URL? { URL(string: urlString) }
}

enum BrowserSecurityScript {
    static func make(configuration: BrowserSecurityConfiguration, rememberedSelectors: [String]) -> String {
        let selectorValues = Array(rememberedSelectors.prefix(32))
        let selectors: String
        if let data = try? JSONSerialization.data(withJSONObject: selectorValues),
           let json = String(data: data, encoding: .utf8) {
            selectors = json
        } else {
            selectors = "[]"
        }
        return """
        (() => {
          const config = {
            ads: \(configuration.blockAds ? "true" : "false"),
            popups: \(configuration.blockPopups ? "true" : "false"),
            redirects: \(configuration.blockRedirects ? "true" : "false"),
            remove: \(configuration.elementRemovalEnabled ? "true" : "false"),
            hijack: \(configuration.antiHijackingEnabled ? "true" : "false")
          };
          window.__aitransSecurity = config;
          window.__aitransApplySecurity = (next) => {
            if (!next) return;
            Object.keys(config).forEach(key => {
              if (typeof next[key] === 'boolean') config[key] = next[key];
            });
            window.__aitransSecurity = config;
            removeRemembered(); hideAds();
          };
          const separatorCharacter = String.fromCharCode(10);
          const currentRuleHost = location.hostname.toLowerCase();
          const localRuleKey = '__aitransElementRulesV1';
          const remembered = \(selectors);
          try {
            const localRules = JSON.parse(localStorage.getItem(localRuleKey) || '[]');
            if (Array.isArray(localRules)) {
              localRules.slice(0, 32).forEach(selector => {
                if (typeof selector !== 'string' || !selector) return;
                const scopedRule = currentRuleHost + separatorCharacter + selector;
                if (!remembered.includes(scopedRule)) remembered.push(scopedRule);
              });
            }
          } catch (_) {}
          const removeRemembered = () => {
            if (!config.remove) return;
            remembered.forEach(entry => {
              const separator = entry.indexOf(separatorCharacter);
              if (separator <= 0) return;
              const host = entry.slice(0, separator).toLowerCase();
              if (host !== location.hostname.toLowerCase()) return;
              const selector = entry.slice(separator + 1);
              try { document.querySelectorAll(selector).forEach(e => e.remove()); } catch (_) {}
            });
          };
          const adSelector = '[class="ad" i],[class~="ad" i],[class*="ad-" i],[class*="-ad" i],[class*="_ad" i],[id="ad" i],[id^="ad-" i],[id*="advert" i],[class*="banner" i],[class*="sponsor" i],[class*="popup" i],iframe[src*="doubleclick" i]';
          const hideAds = () => {
            if (!config.ads) return;
            try { document.querySelectorAll(adSelector).forEach(e => { e.dataset.aitransHidden = '1'; e.style.setProperty('display','none','important'); }); } catch (_) {}
          };
          const selectorPath = (el) => {
            if (!el || !el.tagName) return '';
            const parts = [];
            while (el && el.nodeType === 1 && parts.length < 6) {
              let part = el.tagName.toLowerCase();
              if (el.id) part += '#' + CSS.escape(el.id);
              else if (el.parentElement) {
                const siblings = Array.from(el.parentElement.children).filter(x => x.tagName === el.tagName);
                if (siblings.length > 1) part += ':nth-of-type(' + (siblings.indexOf(el) + 1) + ')';
              }
              parts.unshift(part); el = el.parentElement;
            }
            return parts.join('>');
          };
          document.addEventListener('click', (event) => {
            if (!config.remove) return;
            const target = event.target && event.target.closest ? event.target.closest('*') : null;
            if (!target) return;
            if (target === document.body || target === document.documentElement) return;
            event.preventDefault(); event.stopPropagation();
            const selector = selectorPath(target);
            target.remove();
            if (selector) {
              const scopedRule = currentRuleHost + separatorCharacter + selector;
              if (!remembered.includes(scopedRule)) remembered.unshift(scopedRule);
              try {
                const siteSelectors = remembered
                  .filter(entry => entry.startsWith(currentRuleHost + separatorCharacter))
                  .map(entry => entry.slice(entry.indexOf(separatorCharacter) + 1))
                  .slice(0, 32);
                localStorage.setItem(localRuleKey, JSON.stringify(siteSelectors));
              } catch (_) {}
            }
            if (selector && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.aitransElementRule) {
              window.webkit.messageHandlers.aitransElementRule.postMessage(selector);
            }
          }, true);
          const originalWindowOpen = window.open;
          window.open = (...args) => config.popups ? null : originalWindowOpen.apply(window, args);
          const originalWriteText = navigator.clipboard && navigator.clipboard.writeText;
          if (navigator.clipboard && originalWriteText) {
            navigator.clipboard.writeText = (...args) => {
              const userInitiated = !!(navigator.userActivation && navigator.userActivation.isActive);
              return config.hijack && !userInitiated
                ? Promise.reject(new Error('AITRANS clipboard write blocked'))
                : originalWriteText.apply(navigator.clipboard, args);
            };
          }
          document.addEventListener('touchstart', (event) => {
            if (!config.hijack) return;
            const target = event.target && event.target.closest ? event.target.closest('*') : null;
            if (!target || target.closest('a[href],button,input,textarea,select,video,canvas,[role="button"],[data-aitrans-allow-touch]')) return;
            const style = getComputedStyle(target);
            const rect = target.getBoundingClientRect();
            const viewportArea = Math.max(1, innerWidth * innerHeight);
            const coversViewport = Math.max(0, rect.width) * Math.max(0, rect.height) >= viewportArea * 0.65;
            const elevated = style.position === 'fixed' && Number.parseInt(style.zIndex || '0', 10) >= 1000;
            const visuallyEmpty = target.children.length === 0 && (target.textContent || '').trim() === '';
            if (!(coversViewport && elevated && visuallyEmpty)) return;
            event.preventDefault(); event.stopImmediatePropagation();
            target.style.setProperty('pointer-events', 'none', 'important');
          }, true);
          removeRemembered(); hideAds();
          const securityRoot = document.documentElement;
          if (securityRoot) {
            new MutationObserver(() => { removeRemembered(); hideAds(); }).observe(
              securityRoot,
              {childList:true, subtree:true}
            );
          }
        })();
        """
    }

    static let contentRuleListJSON = """
    [
      {"trigger":{"url-filter":".*(doubleclick\\.net|googlesyndication\\.com|adservice\\.google\\.com|adnxs\\.com|advertising\\.com|adsystem\\.com|popads\\.net|propellerads\\.com).*","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*(doubleclick\\.net|googlesyndication\\.com|adservice\\.google\\.com|adnxs\\.com|popads\\.net).*","resource-type":["script","image","style-sheet","font","raw","svg-document","media"]},"action":{"type":"block"}}
    ]
    """

    /// Reports meaningful DOM/layout changes to the BrowserModel so a running
    /// capture loses its viewport lease. The debounce keeps animated pages
    /// from flooding the main actor while still allowing a later stable capture.
    static let pageMutationObserverSource = """
    (() => {
      let timer = null;
      const report = () => {
        if (timer !== null) return;
        timer = setTimeout(() => {
          timer = null;
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.aitransPageMutation) {
            window.webkit.messageHandlers.aitransPageMutation.postMessage('layout');
          }
        }, 180);
      };
      const root = document.documentElement;
      if (!root) return;
      new MutationObserver(report).observe(root, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['src', 'style', 'class', 'hidden']
      });
      if (window.ResizeObserver) new ResizeObserver(report).observe(root);
    })();
    """
}

@MainActor
@Observable
final class BrowserModel {
    static let recommendedBookmarks: [BrowserBookmark] = [
        BrowserBookmark(title: "MangaDex", urlString: "https://mangadex.org"),
        BrowserBookmark(title: "Comick", urlString: "https://comick.io"),
        BrowserBookmark(title: "漫画之家", urlString: "https://www.manhuagui.com")
    ]
    enum Phase: Equatable {
        case start
        case loading
        case loaded
        case failed(String)
        case webContentProcessTerminated
    }

    enum ChromeMode: Equatable {
        case expanded
        case compact
    }

    struct BrowserTab: Identifiable {
        let id: UUID
        var phase: Phase
        var currentURL: URL?
        var loadingProgress: Double
        var canGoBack: Bool
        var canGoForward: Bool
        var scrollOffsetX: CGFloat
        var scrollOffsetY: CGFloat
        var thumbnail: UIImage?
        var documentID: UUID
        var navigationGeneration: Int
        var contentGeneration: Int
        var layoutGeneration: Int
        var scrollGeneration: Int
        fileprivate var lastRequestedURL: URL?

        init(id: UUID = UUID()) {
            self.id = id
            phase = .start
            currentURL = nil
            loadingProgress = 0
            canGoBack = false
            canGoForward = false
            scrollOffsetX = 0
            scrollOffsetY = 0
            thumbnail = nil
            documentID = UUID()
            navigationGeneration = 0
            contentGeneration = 0
            layoutGeneration = 0
            scrollGeneration = 0
            lastRequestedURL = nil
        }

        var displayHost: String {
            currentURL?.host(percentEncoded: false) ?? currentURL?.host ?? "新标签"
        }
    }

    private(set) var tabs: [BrowserTab]
    private(set) var activeTabID: UUID
    private(set) var chromeMode: ChromeMode = .expanded
    private(set) var notice: String?
    private(set) var noticeRevision = 0
    private(set) var addressError: String?
    private(set) var isSwitchingTabs = false
    private(set) var isViewportStable = true
    private(set) var pageIdentityRevision = 0
    private(set) var bookmarks: [BrowserBookmark]
    private(set) var rememberedElementSelectors: [String]

    var activeTab: BrowserTab {
        tabs.first(where: { $0.id == activeTabID }) ?? tabs[0]
    }

    var phase: Phase { activeTab.phase }
    var currentURL: URL? { activeTab.currentURL }
    var loadingProgress: Double { activeTab.loadingProgress }
    var canGoBack: Bool { activeTab.canGoBack }
    var canGoForward: Bool { activeTab.canGoForward }
    var displayHost: String { activeTab.displayHost }
    var tabCount: Int { tabs.count }
    var showsExpandedChrome: Bool { chromeMode == .expanded }
    var pageIdentity: BrowserPageSnapshotIdentity {
        let tab = activeTab
        return BrowserPageSnapshotIdentity(
            tabID: tab.id,
            documentID: tab.documentID,
            normalizedURL: normalizedPageURL(tab.currentURL),
            navigationGeneration: tab.navigationGeneration,
            contentGeneration: tab.contentGeneration,
            layoutGeneration: tab.layoutGeneration,
            scrollGeneration: tab.scrollGeneration,
            viewportWidth: Double(viewportSize.width),
            viewportHeight: Double(viewportSize.height),
            documentOffsetX: Double(max(0, tab.scrollOffsetX)),
            documentOffsetY: Double(max(0, tab.scrollOffsetY)),
            isStable: isViewportStable
        )
    }

    @ObservationIgnored private weak var webView: WKWebView?
    @ObservationIgnored private var attachedTabID: UUID?
    @ObservationIgnored private var chromeAutoHideSuspended = false
    @ObservationIgnored private var pendingRestorationOffsets: [UUID: CGFloat] = [:]
    @ObservationIgnored private var captureExclusionInsets = UIEdgeInsets.zero
    @ObservationIgnored private var viewportSize = CGSize.zero
    @ObservationIgnored private var securityConfiguration = BrowserSecurityConfiguration.default
    @ObservationIgnored private var contentStabilityTask: Task<Void, Never>?
    @ObservationIgnored private var isScrollInteractionActive = false

    init() {
        let initialTab = BrowserTab()
        tabs = [initialTab]
        activeTabID = initialTab.id
        bookmarks = Self.loadBookmarks()
        rememberedElementSelectors = Self.loadRememberedElementSelectors()
    }

    func attach(webView: WKWebView, to tabID: UUID) {
        guard tabID == activeTabID else { return }
        self.webView = webView
        attachedTabID = tabID
        isScrollInteractionActive = false
        viewportSize = webView.bounds.size
        isViewportStable = true
        refreshNavigationState(from: webView, tabID: tabID)

        let tab = activeTab
        guard let url = tab.currentURL,
              tab.phase == .loaded || tab.phase == .loading else { return }

        // Rebuilding a WKWebView is a new document observation even when the
        // URL is unchanged; old overlays must not flash before a new capture.
        invalidatePageIdentity(tabID: tabID)
        pendingRestorationOffsets[tabID] = tab.scrollOffsetY
        mutateTab(tabID) {
            $0.phase = .loading
            $0.loadingProgress = 0
            $0.canGoBack = false
            $0.canGoForward = false
        }
        webView.load(URLRequest(url: url))
    }

    func detach(webView: WKWebView, from tabID: UUID) {
        guard attachedTabID == tabID, self.webView === webView else { return }
        captureSessionState(from: webView, tabID: tabID)
        invalidatePageIdentity(tabID: tabID)
        isScrollInteractionActive = false
        self.webView = nil
        attachedTabID = nil
    }

    @discardableResult
    func load(address rawAddress: String) -> Bool {
        let trimmed = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            addressError = "请输入网址"
            return false
        }

        let candidate = normalizedCandidate(from: trimmed)
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              let url = components.url else {
            addressError = "网址格式无效，请检查后重试"
            return false
        }

        guard scheme == "http" || scheme == "https" else {
            addressError = nil
            handleExternalNavigation(url)
            return false
        }

        guard let host = components.host, !host.isEmpty, !host.contains(" ") else {
            addressError = "网址缺少有效的站点地址"
            return false
        }

        addressError = nil
        load(url: url)
        return true
    }

    func load(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            handleExternalNavigation(url)
            return
        }
        guard let webView, attachedTabID == activeTabID else {
            mutateActiveTab { $0.phase = .failed("浏览器尚未准备好，请稍后重试。") }
            return
        }

        pendingRestorationOffsets[activeTabID] = nil
        invalidatePageIdentity()
        mutateActiveTab {
            $0.lastRequestedURL = url
            $0.currentURL = url
            $0.loadingProgress = 0
            $0.scrollOffsetX = 0
            $0.scrollOffsetY = 0
            $0.phase = .loading
        }
        chromeMode = .expanded
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        guard canGoBack else { return }
        webView?.goBack()
    }

    func goForward() {
        guard canGoForward else { return }
        webView?.goForward()
    }

    func reload() {
        if webView?.url != nil {
            webView?.reload()
        } else if let retryURL = activeTab.lastRequestedURL ?? currentURL {
            load(url: retryURL)
        }
    }

    func retry() {
        guard let retryURL = currentURL ?? activeTab.lastRequestedURL else { return }
        load(url: retryURL)
    }

    func clearAddressError() {
        addressError = nil
    }

    func setChromeAutoHideSuspended(_ suspended: Bool) {
        chromeAutoHideSuspended = suspended
        if suspended { chromeMode = .expanded }
    }

    func updateChromePresentation(isScrollingDown: Bool?, isAtTop: Bool) {
        if isAtTop || chromeAutoHideSuspended {
            chromeMode = .expanded
        } else if let isScrollingDown {
            chromeMode = isScrollingDown ? .compact : .expanded
        }
    }

    func navigationDidStart(url: URL?, webView: WKWebView, tabID: UUID) {
        guard isActiveAttachment(webView, tabID: tabID) else { return }
        invalidatePageIdentity(tabID: tabID)
        mutateTab(tabID) {
            if let url {
                $0.currentURL = url
                $0.lastRequestedURL = url
            }
            $0.phase = .loading
        }
        chromeMode = .expanded
        refreshNavigationState(from: webView, tabID: tabID)
    }

    func navigationDidFinish(url: URL?, webView: WKWebView, tabID: UUID) {
        guard isActiveAttachment(webView, tabID: tabID) else { return }
        // A provisional navigation must never lend its loading-time document
        // identity to a capture. Commit a fresh document UUID only after the
        // top-level navigation has finished; redirects keep their generation
        // but cannot reuse the old page's render lease.
        invalidatePageIdentity(tabID: tabID)
        contentStabilityTask?.cancel()
        contentStabilityTask = nil
        isViewportStable = true
        mutateTab(tabID) {
            if let url {
                $0.currentURL = url
                $0.lastRequestedURL = url
            }
            $0.loadingProgress = 1
            $0.phase = .loaded
        }
        refreshNavigationState(from: webView, tabID: tabID)
    }

    func navigationDidFail(_ error: Error, webView: WKWebView, tabID: UUID) {
        guard isActiveAttachment(webView, tabID: tabID) else { return }
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else {
            refreshNavigationState(from: webView, tabID: tabID)
            return
        }

        let failedURL = activeTab.currentURL ?? activeTab.lastRequestedURL
        mutateTab(tabID) { $0.phase = .failed(Self.failureMessage(for: nsError, url: failedURL)) }
        chromeMode = .expanded
        refreshNavigationState(from: webView, tabID: tabID)
    }

    func webContentProcessDidTerminate(webView: WKWebView, tabID: UUID) {
        guard isActiveAttachment(webView, tabID: tabID) else { return }
        invalidatePageIdentity(tabID: tabID)
        mutateTab(tabID) { $0.phase = .webContentProcessTerminated }
        chromeMode = .expanded
        refreshNavigationState(from: webView, tabID: tabID)
    }

    func updateProgress(_ progress: Double, webView: WKWebView, tabID: UUID) {
        guard isActiveAttachment(webView, tabID: tabID) else { return }
        mutateTab(tabID) { $0.loadingProgress = min(max(progress, 0), 1) }
    }

    func updateCurrentURL(_ url: URL?, webView: WKWebView, tabID: UUID) {
        guard isActiveAttachment(webView, tabID: tabID), let url else { return }
        mutateTab(tabID) {
            $0.currentURL = url
            $0.lastRequestedURL = url
        }
    }

    func updateScrollOffset(_ offsetY: CGFloat, webView: WKWebView, tabID: UUID) {
        guard isActiveAttachment(webView, tabID: tabID) else { return }
        let previousX = activeTab.scrollOffsetX
        let previousY = activeTab.scrollOffsetY
        let nextX = webView.scrollView.contentOffset.x
        mutateTab(tabID) {
            $0.scrollOffsetX = nextX
            $0.scrollOffsetY = offsetY
        }
        let moved = abs(previousX - nextX) > 0.5 || abs(previousY - offsetY) > 0.5
        guard moved, !isScrollInteractionActive else { return }

        // JavaScript and restoration can scroll without UIScrollView's drag
        // callbacks. Rotate the viewport lease on the first movement and only
        // mark it stable after scrolling has actually gone quiet.
        if isViewportStable {
            invalidatePageIdentity(
                tabID: tabID,
                documentChanged: false,
                contentChanged: false
            )
        }
        contentStabilityTask?.cancel()
        contentStabilityTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled, let self,
                  self.activeTabID == tabID,
                  !self.isScrollInteractionActive else { return }
            self.isViewportStable = true
            self.pageIdentityRevision &+= 1
            self.contentStabilityTask = nil
        }
    }

    func updateViewport(size: CGSize, webView: WKWebView, tabID: UUID) {
        guard isActiveAttachment(webView, tabID: tabID), size.width > 0, size.height > 0 else { return }
        guard abs(viewportSize.width - size.width) > 0.5 || abs(viewportSize.height - size.height) > 0.5 else {
            return
        }
        viewportSize = size
        invalidatePageIdentity(
            tabID: tabID,
            documentChanged: false,
            contentChanged: false,
            layoutChanged: true
        )
    }

    func updateCaptureExclusionInsets(_ insets: UIEdgeInsets) {
        let bounded = UIEdgeInsets(
            top: max(0, insets.top),
            left: max(0, insets.left),
            bottom: max(0, insets.bottom),
            right: max(0, insets.right)
        )
        guard bounded != captureExclusionInsets else { return }
        captureExclusionInsets = bounded
    }

    func applySecurityConfiguration(_ configuration: BrowserSecurityConfiguration) {
        securityConfiguration = configuration
    }

    var isActivePageBookmarked: Bool {
        let url = normalizedPageURL(currentURL)
        guard url != "about:blank" else { return false }
        return bookmarks.contains { $0.urlString == url }
    }

    func toggleActiveBookmark() {
        guard let url = currentURL else { return }
        let urlString = normalizedPageURL(url)
        if let index = bookmarks.firstIndex(where: { $0.urlString == urlString }) {
            bookmarks.remove(at: index)
        } else {
            let title = activeTab.displayHost == "新标签" ? "漫画页面" : activeTab.displayHost
            bookmarks.insert(BrowserBookmark(title: title, urlString: urlString), at: 0)
        }
        saveBookmarks()
        showNotice(isActivePageBookmarked ? "已收藏此漫画页面" : "已取消收藏")
    }

    func removeBookmark(_ bookmark: BrowserBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }

    func openBookmark(_ bookmark: BrowserBookmark) {
        guard let url = bookmark.url else { return }
        load(url: url)
    }

    func rememberElementSelector(_ selector: String) {
        let clean = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              let host = currentURL?.host(percentEncoded: false)?.lowercased(),
              !host.isEmpty else { return }
        let scopedRule = "\(host)\n\(clean)"
        rememberedElementSelectors.removeAll { $0 == scopedRule }
        rememberedElementSelectors.insert(scopedRule, at: 0)
        rememberedElementSelectors = Array(rememberedElementSelectors.prefix(32))
        UserDefaults.standard.set(rememberedElementSelectors, forKey: "aitrans.browser.elementSelectors")
        showNotice("已移除元素，并记住此规则")
    }

    func clearRememberedElementSelectors() {
        rememberedElementSelectors = []
        UserDefaults.standard.removeObject(forKey: "aitrans.browser.elementSelectors")
        webView?.evaluateJavaScript(
            "try { localStorage.removeItem('__aitransElementRulesV1'); } catch (_) {}",
            completionHandler: nil
        )
    }

    /// Releases tab thumbnails under memory pressure. A thumbnail is only a
    /// convenience for the tab switcher; it is never part of page identity or
    /// the browser translation cache and can be recreated on demand.
    func handleMemoryWarning() {
        for index in tabs.indices {
            tabs[index].thumbnail = nil
        }
        invalidatePageIdentity(documentChanged: false, contentChanged: false)
    }

    func scrollViewWillBeginInteraction() {
        isScrollInteractionActive = true
        contentStabilityTask?.cancel()
        contentStabilityTask = nil
        guard isViewportStable else { return }
        isViewportStable = false
        invalidatePageIdentity(documentChanged: false, contentChanged: false)
    }

    func scrollViewDidEndInteraction() {
        isScrollInteractionActive = false
        guard contentStabilityTask == nil else { return }
        isViewportStable = true
        pageIdentityRevision &+= 1
    }

    func pageContentDidChange(layoutChanged: Bool) {
        let observedTabID = activeTabID
        invalidatePageIdentity(
            documentChanged: false,
            contentChanged: true,
            layoutChanged: layoutChanged
        )
        contentStabilityTask?.cancel()
        contentStabilityTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled, let self,
                  self.activeTabID == observedTabID else { return }
            guard !self.isScrollInteractionActive else {
                self.contentStabilityTask = nil
                return
            }
            self.isViewportStable = true
            self.pageIdentityRevision &+= 1
            self.contentStabilityTask = nil
        }
    }

    /// Captures only the visible webpage rectangle. The SwiftUI toolbar is
    /// outside the WKWebView, while `captureExclusionInsets` removes its
    /// obscured area from the snapshot and OCR coordinate space.
    func captureVisibleContent(selection: BrowserCaptureSelection? = nil) async throws -> BrowserPageCapture {
        guard let webView, attachedTabID == activeTabID else { throw BrowserCaptureError.noWebView }
        guard activeTab.phase == .loaded else { throw BrowserCaptureError.noWebView }
        guard isViewportStable, pageIdentity.isStable else { throw BrowserCaptureError.unstableViewport }

        let bounds = webView.bounds
        let contentRect = CGRect(
            x: bounds.minX + captureExclusionInsets.left,
            y: bounds.minY + captureExclusionInsets.top,
            width: bounds.width - captureExclusionInsets.left - captureExclusionInsets.right,
            height: bounds.height - captureExclusionInsets.top - captureExclusionInsets.bottom
        )
        guard contentRect.width >= 24, contentRect.height >= 24 else {
            throw BrowserCaptureError.invalidContentRect
        }
        let requestedRect = selection?.rectInView ?? contentRect
        let captureRect = requestedRect.intersection(contentRect)
        guard !captureRect.isNull, captureRect.width >= 24, captureRect.height >= 24 else {
            throw BrowserCaptureError.selectionTooSmall
        }

        let captureIdentity = pageIdentity
        let pageMetrics = await evaluatePageMetrics(in: webView)
        let image: UIImage = try await withCheckedThrowingContinuation { continuation in
            let configuration = WKSnapshotConfiguration()
            configuration.rect = captureRect
            configuration.afterScreenUpdates = true
            webView.takeSnapshot(with: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? BrowserCaptureError.snapshotFailed)
                }
            }
        }

        let encoded = try boundedJPEGData(for: image)
        guard isViewportStable, pageIdentity == captureIdentity else {
            throw BrowserCaptureError.unstableViewport
        }
        let scaleX = pageMetrics.viewportWidth / max(bounds.width, 1)
        let scaleY = pageMetrics.viewportHeight / max(bounds.height, 1)
        let visibleDocumentRect = CGRect(
            x: pageMetrics.offsetX + Double(contentRect.minX) * scaleX,
            y: pageMetrics.offsetY + Double(contentRect.minY) * scaleY,
            width: Double(contentRect.width) * scaleX,
            height: Double(contentRect.height) * scaleY
        )
        let captureDocumentRect = CGRect(
            x: visibleDocumentRect.minX + Double(captureRect.minX - contentRect.minX) * scaleX,
            y: visibleDocumentRect.minY + Double(captureRect.minY - contentRect.minY) * scaleY,
            width: Double(captureRect.width) * scaleX,
            height: Double(captureRect.height) * scaleY
        )
        let captureID = UUID()
        return BrowserPageCapture(
            identity: captureIdentity,
            captureID: captureID,
            imageData: encoded.data,
            captureRectInView: captureRect,
            contentRectInView: contentRect,
            visibleDocumentRectCSS: captureDocumentRect,
            capturePixelSize: encoded.pixelSize,
            scale: encoded.scale,
            captureSHA256: Self.sha256Hex(encoded.data)
        )
    }

    func restorationScrollOffset(for tabID: UUID) -> CGFloat? {
        pendingRestorationOffsets.removeValue(forKey: tabID)
    }

    func refreshNavigationState(from webView: WKWebView, tabID: UUID) {
        guard isActiveAttachment(webView, tabID: tabID) else { return }
        mutateTab(tabID) {
            $0.canGoBack = webView.canGoBack
            $0.canGoForward = webView.canGoForward
        }
    }

    func captureActiveThumbnail() {
        guard let webView, attachedTabID == activeTabID else { return }
        captureSessionState(from: webView, tabID: activeTabID)
        takeSnapshot(of: webView, tabID: activeTabID) {}
    }

    func activateTab(_ tabID: UUID) {
        guard tabID != activeTabID, tabs.contains(where: { $0.id == tabID }) else { return }
        transitionAfterCapturingActiveTab {
            self.activeTabID = tabID
            self.chromeMode = .expanded
            self.addressError = nil
        }
    }

    func newTab() {
        transitionAfterCapturingActiveTab {
            let tab = BrowserTab()
            self.tabs.append(tab)
            self.activeTabID = tab.id
            self.chromeMode = .expanded
            self.addressError = nil
        }
    }

    func closeTab(_ tabID: UUID) {
        guard let closingIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if tabID != activeTabID {
            tabs.remove(at: closingIndex)
            return
        }

        if tabs.count == 1 {
            transitionAfterCapturingActiveTab {
                let replacement = BrowserTab()
                self.tabs = [replacement]
                self.activeTabID = replacement.id
                self.chromeMode = .expanded
                self.addressError = nil
            }
            return
        }

        let nextIndex = closingIndex == tabs.count - 1 ? closingIndex - 1 : closingIndex + 1
        let nextID = tabs[nextIndex].id
        transitionAfterCapturingActiveTab {
            self.tabs.removeAll(where: { $0.id == tabID })
            self.activeTabID = nextID
            self.chromeMode = .expanded
            self.addressError = nil
        }
    }

    @discardableResult
    func handleExternalNavigationIfNeeded(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        let isWebURL = scheme == "http" || scheme == "https"
        let isAppStoreURL = isWebURL && url.host?.lowercased() == "apps.apple.com"
        guard !isWebURL || isAppStoreURL else { return false }
        handleExternalNavigation(url)
        return true
    }

    func reportUnsupportedDownload(webView: WKWebView, tabID: UUID) {
        guard isActiveAttachment(webView, tabID: tabID) else { return }
        showNotice("暂不支持下载此内容")
        mutateTab(tabID) {
            $0.phase = webView.url == nil
                ? .failed("暂不支持下载此内容，请使用系统浏览器打开。")
                : .loaded
        }
        refreshNavigationState(from: webView, tabID: tabID)
    }

    func reportBrowserSecurityBlock(url: URL) {
        let host = url.host(percentEncoded: false) ?? url.host ?? "此地址"
        showNotice("已拦截可疑跳转：\(host)")
    }

    func clearNotice(revision: Int) {
        guard revision == noticeRevision else { return }
        notice = nil
    }

    private func transitionAfterCapturingActiveTab(_ transition: @escaping @MainActor () -> Void) {
        guard !isSwitchingTabs else { return }
        let outgoingID = activeTabID
        invalidatePageIdentity(tabID: outgoingID)
        isScrollInteractionActive = false
        guard let webView, attachedTabID == activeTabID else {
            transition()
            return
        }

        isSwitchingTabs = true
        captureSessionState(from: webView, tabID: outgoingID)
        takeSnapshot(of: webView, tabID: outgoingID) {
            self.webView = nil
            self.attachedTabID = nil
            transition()
            self.isSwitchingTabs = false
        }
    }

    private func takeSnapshot(of webView: WKWebView, tabID: UUID, completion: @escaping @MainActor () -> Void) {
        guard webView.bounds.width > 0, webView.bounds.height > 0 else {
            completion()
            return
        }

        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.afterScreenUpdates = false
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            Task { @MainActor in
                if let image {
                    let thumbnail = Self.boundedThumbnail(for: image)
                    self?.mutateTab(tabID) { $0.thumbnail = thumbnail }
                }
                completion()
            }
        }
    }

    /// WKWebView snapshots are device-scale screen images. Keep only a small
    /// tab-switcher preview so several background tabs cannot retain multiple
    /// full-resolution pages; translation never consumes this thumbnail.
    private static func boundedThumbnail(for image: UIImage) -> UIImage {
        let maximumDimension: CGFloat = 480
        let sourceDimension = max(image.size.width, image.size.height)
        let scale = min(1, maximumDimension / max(sourceDimension, 1))
        guard scale < 1 else { return image }
        let targetSize = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func captureSessionState(from webView: WKWebView, tabID: UUID) {
        mutateTab(tabID) {
            if let url = webView.url {
                $0.currentURL = url
                $0.lastRequestedURL = url
            }
            $0.canGoBack = webView.canGoBack
            $0.canGoForward = webView.canGoForward
            $0.scrollOffsetY = webView.scrollView.contentOffset.y
            $0.scrollOffsetX = webView.scrollView.contentOffset.x
        }
    }

    private func isActiveAttachment(_ webView: WKWebView, tabID: UUID) -> Bool {
        tabID == activeTabID && attachedTabID == tabID && self.webView === webView
    }

    private func invalidatePageIdentity(
        tabID: UUID? = nil,
        documentChanged: Bool = true,
        contentChanged: Bool = true,
        layoutChanged: Bool = false
    ) {
        let targetID = tabID ?? activeTabID
        guard tabs.contains(where: { $0.id == targetID }) else { return }
        if documentChanged || contentChanged || layoutChanged {
            contentStabilityTask?.cancel()
            contentStabilityTask = nil
        }
        mutateTab(targetID) {
            if documentChanged {
                $0.documentID = UUID()
                $0.navigationGeneration &+= 1
            }
            if contentChanged { $0.contentGeneration &+= 1 }
            if layoutChanged { $0.layoutGeneration &+= 1 }
            $0.scrollGeneration &+= 1
        }
        isViewportStable = false
        pageIdentityRevision &+= 1
    }

    private struct PageMetrics {
        var offsetX: Double
        var offsetY: Double
        var viewportWidth: Double
        var viewportHeight: Double
    }

    private func evaluatePageMetrics(in webView: WKWebView) async -> PageMetrics {
        let script = """
        (() => {
          const v = window.visualViewport;
          return {
            x: Number(window.scrollX || 0),
            y: Number(window.scrollY || 0),
            width: Number((v && v.width) || window.innerWidth || 1),
            height: Number((v && v.height) || window.innerHeight || 1)
          };
        })();
        """
        let value = try? await webView.evaluateJavaScript(script)
        guard let dictionary = value as? [String: Any] else {
            return PageMetrics(
                offsetX: Double(max(0, webView.scrollView.contentOffset.x)),
                offsetY: Double(max(0, webView.scrollView.contentOffset.y)),
                viewportWidth: Double(max(1, webView.bounds.width)),
                viewportHeight: Double(max(1, webView.bounds.height))
            )
        }
        func number(_ key: String, fallback: Double) -> Double {
            if let value = dictionary[key] as? NSNumber, value.doubleValue.isFinite {
                return max(0, value.doubleValue)
            }
            return fallback
        }
        return PageMetrics(
            offsetX: number("x", fallback: Double(max(0, webView.scrollView.contentOffset.x))),
            offsetY: number("y", fallback: Double(max(0, webView.scrollView.contentOffset.y))),
            viewportWidth: max(1, number("width", fallback: Double(max(1, webView.bounds.width)))),
            viewportHeight: max(1, number("height", fallback: Double(max(1, webView.bounds.height))))
        )
    }

    private func boundedJPEGData(for image: UIImage) throws -> (data: Data, pixelSize: CGSize, scale: CGFloat) {
        let sourcePixelWidth = max(1, image.size.width * image.scale)
        let sourcePixelHeight = max(1, image.size.height * image.scale)
        let maximumDimension: CGFloat = 4_096
        let maximumPixels: CGFloat = 6_000_000
        let dimensionScale = min(
            1,
            maximumDimension / max(sourcePixelWidth, sourcePixelHeight),
            sqrt(maximumPixels / max(1, sourcePixelWidth * sourcePixelHeight))
        )
        let pixelWidth = max(1, floor(sourcePixelWidth * dimensionScale))
        let pixelHeight = max(1, floor(sourcePixelHeight * dimensionScale))
        let targetSize = CGSize(width: pixelWidth, height: pixelHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let rendered = renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = rendered.jpegData(compressionQuality: 0.9), !data.isEmpty else {
            throw BrowserCaptureError.imageEncodingFailed
        }
        return (data, targetSize, 1)
    }

    private func normalizedPageURL(_ url: URL?) -> String {
        guard let url else { return "about:blank" }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        let scheme = components.scheme?.lowercased()
        let host = components.host?.lowercased()
        components.scheme = scheme
        components.host = host
        if scheme == "http", components.port == 80 {
            components.port = nil
        } else if scheme == "https", components.port == 443 {
            components.port = nil
        }
        if components.path.isEmpty {
            components.path = "/"
        }
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    private static func loadBookmarks() -> [BrowserBookmark] {
        guard let data = UserDefaults.standard.data(forKey: "aitrans.browser.bookmarks"),
              let bookmarks = try? JSONDecoder().decode([BrowserBookmark].self, from: data) else {
            return []
        }
        return bookmarks.filter { $0.url?.scheme?.lowercased() == "http" || $0.url?.scheme?.lowercased() == "https" }
    }

    private func saveBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: "aitrans.browser.bookmarks")
    }

    private static func loadRememberedElementSelectors() -> [String] {
        let stored = (UserDefaults.standard.array(
            forKey: "aitrans.browser.elementSelectors"
        ) as? [String]) ?? []
        // Rules created before host scoping are intentionally ignored: a
        // selector learned on one site must never remove content on another.
        return stored.filter { rule in
            guard let separator = rule.firstIndex(of: "\n") else { return false }
            return separator != rule.startIndex && separator != rule.index(before: rule.endIndex)
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func mutateActiveTab(_ mutation: (inout BrowserTab) -> Void) {
        mutateTab(activeTabID, mutation)
    }

    private func mutateTab(_ tabID: UUID, _ mutation: (inout BrowserTab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        mutation(&tabs[index])
    }

    private func normalizedCandidate(from address: String) -> String {
        if address.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#, options: .regularExpression) != nil {
            return address
        }
        if address.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil,
           let colon = address.firstIndex(of: ":"),
           !address[..<colon].contains(".") {
            return address
        }
        return "https://\(address)"
    }

    private func handleExternalNavigation(_ url: URL) {
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in self?.showNotice("暂不支持此链接") }
        }
    }

    private func showNotice(_ message: String) {
        notice = message
        noticeRevision += 1
    }

    private static func failureMessage(for error: NSError, url: URL?) -> String {
        if error.domain == NSURLErrorDomain {
            switch error.code {
            case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                return "该站点使用不安全的 HTTP 连接，已被系统安全策略阻止。请改用 HTTPS。"
            case NSURLErrorNotConnectedToInternet:
                return "网络未连接，请检查网络后重试。"
            case NSURLErrorTimedOut:
                return "页面加载超时，请稍后重试。"
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return "找不到该站点，请检查网址是否正确。"
            case NSURLErrorCannotConnectToHost:
                return "无法连接到该站点，请稍后重试。"
            case NSURLErrorSecureConnectionFailed,
                 NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid:
                return "无法建立安全连接，请检查站点证书后重试。"
            default:
                break
            }
        }

        if url?.scheme?.lowercased() == "http" {
            return "HTTP 页面加载失败。系统保持默认网络安全策略，建议改用 HTTPS。"
        }
        return error.localizedDescription.isEmpty ? "页面加载失败，请稍后重试。" : error.localizedDescription
    }
}
