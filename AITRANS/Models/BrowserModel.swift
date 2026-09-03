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

    private(set) var phase: Phase = .start
    private(set) var currentURL: URL?
    private(set) var loadingProgress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isChromeVisible = true
    private(set) var notice: String?
    private(set) var noticeRevision = 0
    private(set) var addressError: String?

    @ObservationIgnored private weak var webView: WKWebView?
    @ObservationIgnored private var lastRequestedURL: URL?
    @ObservationIgnored private var chromeAutoHideSuspended = false

    func attach(webView: WKWebView) {
        self.webView = webView
        refreshNavigationState(from: webView)
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
        guard let webView else {
            phase = .failed("浏览器尚未准备好，请稍后重试。")
            return
        }

        lastRequestedURL = url
        currentURL = url
        loadingProgress = 0
        phase = .loading
        isChromeVisible = true
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
        } else if let lastRequestedURL {
            load(url: lastRequestedURL)
        }
    }

    func retry() {
        guard let retryURL = currentURL ?? lastRequestedURL else { return }
        load(url: retryURL)
    }

    func clearAddressError() {
        addressError = nil
    }

    func setChromeAutoHideSuspended(_ suspended: Bool) {
        chromeAutoHideSuspended = suspended
        if suspended {
            isChromeVisible = true
        }
    }

    func updateChromeVisibility(isScrollingDown: Bool?, isAtTop: Bool) {
        if isAtTop || chromeAutoHideSuspended {
            isChromeVisible = true
        } else if let isScrollingDown {
            isChromeVisible = !isScrollingDown
        }
    }

    func navigationDidStart(url: URL?, webView: WKWebView) {
        if let url {
            currentURL = url
            lastRequestedURL = url
        }
        phase = .loading
        isChromeVisible = true
        refreshNavigationState(from: webView)
    }

    func navigationDidFinish(url: URL?, webView: WKWebView) {
        if let url {
            currentURL = url
            lastRequestedURL = url
        }
        loadingProgress = 1
        phase = .loaded
        refreshNavigationState(from: webView)
    }

    func navigationDidFail(_ error: Error, webView: WKWebView) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else {
            refreshNavigationState(from: webView)
            return
        }

        phase = .failed(Self.failureMessage(for: nsError, url: currentURL ?? lastRequestedURL))
        isChromeVisible = true
        refreshNavigationState(from: webView)
    }

    func webContentProcessDidTerminate(webView: WKWebView) {
        phase = .webContentProcessTerminated
        isChromeVisible = true
        refreshNavigationState(from: webView)
    }

    func updateProgress(_ progress: Double) {
        loadingProgress = min(max(progress, 0), 1)
    }

    func updateCurrentURL(_ url: URL?) {
        guard let url else { return }
        currentURL = url
        lastRequestedURL = url
    }

    func refreshNavigationState(from webView: WKWebView) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
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

    func reportUnsupportedDownload(webView: WKWebView) {
        showNotice("暂不支持下载此内容")
        if webView.url != nil {
            phase = .loaded
        }
        refreshNavigationState(from: webView)
    }

    func clearNotice(revision: Int) {
        guard revision == noticeRevision else { return }
        notice = nil
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
            Task { @MainActor in
                self?.showNotice("暂不支持此链接")
            }
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
