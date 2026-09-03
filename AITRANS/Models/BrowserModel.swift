import Observation
import UIKit
import WebKit

@MainActor
@Observable
final class BrowserModel {
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
        var scrollOffsetY: CGFloat
        var thumbnail: UIImage?
        fileprivate var lastRequestedURL: URL?

        init(id: UUID = UUID()) {
            self.id = id
            phase = .start
            currentURL = nil
            loadingProgress = 0
            canGoBack = false
            canGoForward = false
            scrollOffsetY = 0
            thumbnail = nil
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

    @ObservationIgnored private weak var webView: WKWebView?
    @ObservationIgnored private var attachedTabID: UUID?
    @ObservationIgnored private var chromeAutoHideSuspended = false
    @ObservationIgnored private var pendingRestorationOffsets: [UUID: CGFloat] = [:]

    init() {
        let initialTab = BrowserTab()
        tabs = [initialTab]
        activeTabID = initialTab.id
    }

    func attach(webView: WKWebView, to tabID: UUID) {
        guard tabID == activeTabID else { return }
        self.webView = webView
        attachedTabID = tabID
        refreshNavigationState(from: webView, tabID: tabID)

        let tab = activeTab
        guard let url = tab.currentURL,
              tab.phase == .loaded || tab.phase == .loading else { return }

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
        mutateActiveTab {
            $0.lastRequestedURL = url
            $0.currentURL = url
            $0.loadingProgress = 0
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
        mutateTab(tabID) { $0.scrollOffsetY = offsetY }
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

    func clearNotice(revision: Int) {
        guard revision == noticeRevision else { return }
        notice = nil
    }

    private func transitionAfterCapturingActiveTab(_ transition: @escaping @MainActor () -> Void) {
        guard !isSwitchingTabs else { return }
        guard let webView, attachedTabID == activeTabID else {
            transition()
            return
        }

        isSwitchingTabs = true
        let outgoingID = activeTabID
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
                if let image { self?.mutateTab(tabID) { $0.thumbnail = image } }
                completion()
            }
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
        }
    }

    private func isActiveAttachment(_ webView: WKWebView, tabID: UUID) -> Bool {
        tabID == activeTabID && attachedTabID == tabID && self.webView === webView
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
