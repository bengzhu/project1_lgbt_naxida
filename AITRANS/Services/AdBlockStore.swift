import Observation
import WebKit

@MainActor
struct AdBlockCompiledRuleLists {
    let version: String
    let network: WKContentRuleList
    let cosmetic: WKContentRuleList
}

@MainActor
@Observable
final class AdBlockStore {
    enum Intent {
        case bootstrap
        case refreshRules(force: Bool)
        case clearCachedRules
        case prepareWebViewConfiguration(
            WKWebViewConfiguration,
            messageHandler: any WKScriptMessageHandler
        )
        case attachWebView(WKWebView, attachmentID: UUID)
        case detachWebView(WKWebView, attachmentID: UUID)
        case setEnabled(Bool)
        case setNetworkFiltering(Bool)
        case setScriptProtection(Bool)
        case setCosmeticFiltering(Bool)
        case setPopupBlocking(Bool)
        case setRedirectBlocking(Bool)
        case setElementPicker(Bool)
        case rememberElementSelector(String)
        case clearRememberedElementSelectors
        case recordBlockedNavigation(URL)
        case clearError
    }

    private(set) var state: AdBlockState

    @ObservationIgnored private let repository: AdBlockRuleRepository
    @ObservationIgnored private let compilationService: AdBlockRuleCompilationService
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var operationID = UUID()
    @ObservationIgnored private(set) var compiledRuleLists: AdBlockCompiledRuleLists?
    @ObservationIgnored private weak var attachedWebView: WKWebView?
    @ObservationIgnored private var attachmentID: UUID?
    @ObservationIgnored private var installedNetworkRuleList: WKContentRuleList?
    @ObservationIgnored private var installedCosmeticRuleList: WKContentRuleList?
    @ObservationIgnored private var installedNetworkToken: String?
    @ObservationIgnored private var installedCosmeticToken: String?
    @ObservationIgnored private var rememberedElementSelectors: [String]

    private static let elementSelectorsKey = "aitrans.browser.elementSelectors"

    init(
        repository: AdBlockRuleRepository = AdBlockRuleRepository(),
        compilationService: AdBlockRuleCompilationService = AdBlockRuleCompilationService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.compilationService = compilationService
        self.userDefaults = userDefaults
        let selectors = Self.loadElementSelectors(from: userDefaults)
        rememberedElementSelectors = selectors
        state = .initial(
            preferences: Self.loadPreferences(from: userDefaults),
            rememberedElementRuleCount: selectors.count
        )
    }

    func send(_ intent: Intent) {
        switch intent {
        case .bootstrap:
            startBootstrap()
        case let .refreshRules(force):
            startRefresh(force: force)
        case .clearCachedRules:
            startCacheClear()
        case let .prepareWebViewConfiguration(configuration, messageHandler):
            prepare(configuration: configuration, messageHandler: messageHandler)
        case let .attachWebView(webView, attachmentID):
            attach(webView: webView, attachmentID: attachmentID)
        case let .detachWebView(webView, attachmentID):
            detach(webView: webView, attachmentID: attachmentID)
        case let .setEnabled(enabled):
            updatePreferences { $0.isEnabled = enabled }
        case let .setNetworkFiltering(enabled):
            updatePreferences { $0.networkFilteringEnabled = enabled }
        case let .setScriptProtection(enabled):
            updatePreferences { $0.scriptProtectionEnabled = enabled }
        case let .setCosmeticFiltering(enabled):
            updatePreferences { $0.cosmeticFilteringEnabled = enabled }
        case let .setPopupBlocking(enabled):
            updatePreferences { $0.popupBlockingEnabled = enabled }
        case let .setRedirectBlocking(enabled):
            updatePreferences { $0.redirectBlockingEnabled = enabled }
        case let .setElementPicker(enabled):
            updatePreferences { $0.elementPickerEnabled = enabled }
        case let .rememberElementSelector(selector):
            rememberElementSelector(selector)
        case .clearRememberedElementSelectors:
            clearRememberedElementSelectors()
        case let .recordBlockedNavigation(url):
            recordBlockedNavigation(url)
        case .clearError:
            state.lastError = nil
        }
    }

    private var contentWorld: WKContentWorld {
        .world(name: AdBlockWebScript.contentWorldName)
    }

    private func prepare(
        configuration: WKWebViewConfiguration,
        messageHandler: any WKScriptMessageHandler
    ) {
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: AdBlockWebScript.bootstrap(
                    preferences: state.preferences,
                    rememberedSelectors: rememberedElementSelectors
                ),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: contentWorld
            )
        )
        configuration.userContentController.add(
            messageHandler,
            contentWorld: contentWorld,
            name: AdBlockWebScript.elementRuleMessageName
        )
    }

    private func attach(webView: WKWebView, attachmentID: UUID) {
        if let previousWebView = attachedWebView, previousWebView !== webView {
            removeInstalledRuleLists(from: previousWebView)
        }
        attachedWebView = webView
        self.attachmentID = attachmentID
        installedNetworkRuleList = nil
        installedCosmeticRuleList = nil
        installedNetworkToken = nil
        installedCosmeticToken = nil
        state.isWebViewAttached = true
        applyProtection(to: webView, reloadIfRuleListsChange: false)
    }

    private func detach(webView: WKWebView, attachmentID: UUID) {
        guard self.attachmentID == attachmentID, attachedWebView === webView else { return }
        removeInstalledRuleLists(from: webView)
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: AdBlockWebScript.elementRuleMessageName,
            contentWorld: contentWorld
        )
        attachedWebView = nil
        self.attachmentID = nil
        state.isWebViewAttached = false
    }

    private func startBootstrap() {
        guard state.phase == .idle || state.phase == .failed else { return }
        refreshTask?.cancel()
        let currentOperation = UUID()
        operationID = currentOperation
        state.phase = .loadingCache
        state.message = "正在载入广告规则缓存"
        state.lastError = nil
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let cached = try await self.repository.loadCached()
                try Task.checkCancellation()
                let installed = try await self.compileAndInstall(
                    snapshots: cached.snapshots,
                    statuses: cached.statuses,
                    operationID: currentOperation
                )
                guard installed else { return }
                await self.performRefresh(force: false, operationID: currentOperation)
            } catch is CancellationError {
                return
            } catch {
                guard self.operationID == currentOperation else { return }
                self.publishFailure(error)
            }
        }
    }

    private func startRefresh(force: Bool) {
        refreshTask?.cancel()
        let currentOperation = UUID()
        operationID = currentOperation
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(force: force, operationID: currentOperation)
        }
    }

    private func performRefresh(force: Bool, operationID: UUID) async {
        guard self.operationID == operationID else { return }
        state.phase = .refreshing
        state.message = force ? "正在强制检查规则更新" : "正在检查规则更新"
        state.lastError = nil
        do {
            let refreshed = try await repository.refresh(force: force)
            try Task.checkCancellation()
            _ = try await compileAndInstall(
                snapshots: refreshed.snapshots,
                statuses: refreshed.statuses,
                operationID: operationID
            )
        } catch is CancellationError {
            return
        } catch {
            guard self.operationID == operationID else { return }
            if compiledRuleLists != nil {
                state.phase = .ready
                state.message = "规则更新失败，继续使用上次可用版本"
                state.lastError = error.localizedDescription
            } else {
                publishFailure(error)
            }
        }
    }

    private func startCacheClear() {
        refreshTask?.cancel()
        let currentOperation = UUID()
        operationID = currentOperation
        state.phase = .loadingCache
        state.message = "正在清理规则缓存"
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.clearCache()
                try Task.checkCancellation()
                let installed = try await self.compileAndInstall(
                    snapshots: [],
                    statuses: [],
                    operationID: currentOperation
                )
                guard installed else { return }
                self.state.message = "已清理远端缓存，保留内置基础防护"
            } catch is CancellationError {
                return
            } catch {
                guard self.operationID == currentOperation else { return }
                self.publishFailure(error)
            }
        }
    }

    @discardableResult
    private func compileAndInstall(
        snapshots: [AdBlockRuleSnapshot],
        statuses: [AdBlockSourceStatus],
        operationID: UUID
    ) async throws -> Bool {
        let compilation = try await compilationService.compile(snapshots)
        try Task.checkCancellation()
        guard self.operationID == operationID else { return false }

        let networkID = "aitrans-adblock-network-\(compilation.version)"
        let cosmeticID = "aitrans-adblock-cosmetic-\(compilation.version)"
        let network = try await contentRuleList(
            identifier: networkID,
            encodedJSON: compilation.networkJSON
        )
        let cosmetic = try await contentRuleList(
            identifier: cosmeticID,
            encodedJSON: compilation.cosmeticJSON
        )
        let installed = AdBlockCompiledRuleLists(
            version: compilation.version,
            network: network,
            cosmetic: cosmetic
        )
        try Task.checkCancellation()
        guard self.operationID == operationID else { return false }

        compiledRuleLists = installed
        let sourceStatuses = statuses.map { status in
            var status = status
            if let summary = compilation.sourceSummaries.first(where: { $0.id == status.id }) {
                status.ruleCount = summary.acceptedNetworkRules + summary.acceptedCosmeticRules
            }
            return status
        }
        state.ruleSummary = AdBlockRuleSummary(
            version: compilation.version,
            networkRuleCount: compilation.networkRuleCount,
            cosmeticRuleCount: compilation.cosmeticRuleCount,
            skippedRuleCount: compilation.skippedRuleCount,
            sourceStatuses: sourceStatuses,
            sourceCompilations: compilation.sourceSummaries,
            updatedAt: .now
        )
        state.phase = .ready
        let availableSourceCount = sourceStatuses.count(where: { $0.contentSHA256 != nil })
        state.message = snapshots.isEmpty
            ? "内置基础防护已就绪"
            : "广告规则已就绪（\(availableSourceCount)/\(AdBlockRuleSource.recommended.count) 个远端源）"
        state.lastError = nil
        if let attachedWebView {
            applyProtection(to: attachedWebView, reloadIfRuleListsChange: true)
        }
        await removeObsoleteCompiledLists(keeping: Set([networkID, cosmeticID]))
        return true
    }

    private func contentRuleList(
        identifier: String,
        encodedJSON: String
    ) async throws -> WKContentRuleList {
        if let cached = await lookupContentRuleList(identifier: identifier) {
            return cached
        }
        return try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: encodedJSON
            ) { ruleList, error in
                if let ruleList {
                    continuation.resume(returning: ruleList)
                } else {
                    continuation.resume(
                        throwing: AdBlockError.compilationFailure(
                            error?.localizedDescription ?? "WebKit 未返回编译结果"
                        )
                    )
                }
            }
        }
    }

    private func lookupContentRuleList(identifier: String) async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().lookUpContentRuleList(
                forIdentifier: identifier
            ) { ruleList, _ in
                continuation.resume(returning: ruleList)
            }
        }
    }

    private func removeObsoleteCompiledLists(keeping identifiers: Set<String>) async {
        let available = await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().getAvailableContentRuleListIdentifiers { identifiers in
                continuation.resume(returning: identifiers ?? [])
            }
        }
        for identifier in available where
            identifier.hasPrefix("aitrans-adblock-") && !identifiers.contains(identifier) {
            await withCheckedContinuation { continuation in
                WKContentRuleListStore.default().removeContentRuleList(
                    forIdentifier: identifier
                ) { _ in
                    continuation.resume()
                }
            }
        }
    }

    private func updatePreferences(_ mutation: (inout AdBlockPreferences) -> Void) {
        var preferences = state.preferences
        mutation(&preferences)
        guard preferences != state.preferences else { return }
        state.preferences = preferences
        persist(preferences)
        if let attachedWebView {
            applyProtection(to: attachedWebView, reloadIfRuleListsChange: true)
        }
        state.message = preferences.isEnabled ? "广告防护设置已更新" : "广告防护已关闭"
    }

    private func applyProtection(
        to webView: WKWebView,
        reloadIfRuleListsChange: Bool
    ) {
        let compiledVersion = compiledRuleLists?.version
        let desiredNetworkToken = state.preferences.effectiveNetworkFiltering
            ? compiledVersion.map { "network:\($0)" }
            : nil
        let desiredCosmeticToken = state.preferences.effectiveCosmeticFiltering
            ? compiledVersion.map { "cosmetic:\($0)" }
            : nil
        let controller = webView.configuration.userContentController
        var ruleListsChanged = false

        if installedNetworkToken != desiredNetworkToken {
            if let installedNetworkRuleList {
                controller.remove(installedNetworkRuleList)
            }
            installedNetworkRuleList = nil
            installedNetworkToken = nil
            if let desiredNetworkToken, let network = compiledRuleLists?.network {
                controller.add(network)
                installedNetworkRuleList = network
                installedNetworkToken = desiredNetworkToken
            }
            ruleListsChanged = true
        }

        if installedCosmeticToken != desiredCosmeticToken {
            if let installedCosmeticRuleList {
                controller.remove(installedCosmeticRuleList)
            }
            installedCosmeticRuleList = nil
            installedCosmeticToken = nil
            if let desiredCosmeticToken, let cosmetic = compiledRuleLists?.cosmetic {
                controller.add(cosmetic)
                installedCosmeticRuleList = cosmetic
                installedCosmeticToken = desiredCosmeticToken
            }
            ruleListsChanged = true
        }

        if webView.url != nil {
            let update = AdBlockWebScript.runtimeUpdate(
                preferences: state.preferences,
                rememberedSelectors: rememberedElementSelectors
            )
            let currentAttachmentID = attachmentID
            webView.evaluateJavaScript(
                update,
                in: nil,
                in: contentWorld
            ) { [weak self, weak webView] result in
                guard case let .failure(error) = result else { return }
                Task { @MainActor in
                    guard let self, let webView,
                          self.attachmentID == currentAttachmentID,
                          self.attachedWebView === webView else { return }
                    self.state.lastError = "页面防护脚本更新失败：\(error.localizedDescription)"
                }
            }
        }

        if reloadIfRuleListsChange, ruleListsChanged, webView.url != nil {
            webView.reload()
        }
    }

    private func removeInstalledRuleLists(from webView: WKWebView) {
        let controller = webView.configuration.userContentController
        if let installedNetworkRuleList {
            controller.remove(installedNetworkRuleList)
        }
        if let installedCosmeticRuleList {
            controller.remove(installedCosmeticRuleList)
        }
        installedNetworkRuleList = nil
        installedCosmeticRuleList = nil
        installedNetworkToken = nil
        installedCosmeticToken = nil
    }

    private func rememberElementSelector(_ selector: String) {
        let clean = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = clean.lowercased()
        guard !clean.isEmpty,
              clean.count <= 300,
              !clean.contains("\n"),
              !["html", "body", "main", "article", ":root", "*"].contains(normalized),
              let host = attachedWebView?.url?.host(percentEncoded: false)?.lowercased(),
              !host.isEmpty else { return }
        let scopedRule = "\(host)\n\(clean)"
        rememberedElementSelectors.removeAll { $0 == scopedRule }
        rememberedElementSelectors.insert(scopedRule, at: 0)
        rememberedElementSelectors = Array(rememberedElementSelectors.prefix(32))
        userDefaults.set(rememberedElementSelectors, forKey: Self.elementSelectorsKey)
        state.rememberedElementRuleCount = rememberedElementSelectors.count
        if let attachedWebView {
            applyProtection(to: attachedWebView, reloadIfRuleListsChange: false)
        }
        state.message = "已隐藏所选元素并记住此站点规则"
    }

    private func clearRememberedElementSelectors() {
        guard !rememberedElementSelectors.isEmpty else { return }
        rememberedElementSelectors = []
        userDefaults.removeObject(forKey: Self.elementSelectorsKey)
        state.rememberedElementRuleCount = 0
        if let attachedWebView {
            applyProtection(to: attachedWebView, reloadIfRuleListsChange: false)
        }
        state.message = "已清除点选元素规则"
    }

    private func recordBlockedNavigation(_ url: URL) {
        state.blockedNavigationCount &+= 1
        state.lastBlockedURL = url.host(percentEncoded: false) ?? url.scheme ?? "未知地址"
        state.message = "已阻止网页跳转：\(state.lastBlockedURL ?? "未知地址")"
    }

    private func persist(_ preferences: AdBlockPreferences) {
        userDefaults.set(preferences.isEnabled, forKey: AdBlockPreferenceKey.master.rawValue)
        userDefaults.set(preferences.networkFilteringEnabled, forKey: AdBlockPreferenceKey.network.rawValue)
        userDefaults.set(preferences.scriptProtectionEnabled, forKey: AdBlockPreferenceKey.script.rawValue)
        userDefaults.set(preferences.cosmeticFilteringEnabled, forKey: AdBlockPreferenceKey.cosmetic.rawValue)
        userDefaults.set(preferences.popupBlockingEnabled, forKey: AdBlockPreferenceKey.popups.rawValue)
        userDefaults.set(preferences.redirectBlockingEnabled, forKey: AdBlockPreferenceKey.redirects.rawValue)
        userDefaults.set(preferences.elementPickerEnabled, forKey: AdBlockPreferenceKey.elementPicker.rawValue)

        // Preserve existing installations while Store-backed views use the
        // new preference namespace as their only write path.
        userDefaults.set(preferences.networkFilteringEnabled, forKey: "aitrans.browser.blockAds")
        userDefaults.set(preferences.scriptProtectionEnabled, forKey: "aitrans.browser.antiHijacking")
    }

    private func publishFailure(_ error: Error) {
        state.phase = .failed
        state.message = "广告规则不可用"
        state.lastError = error.localizedDescription
    }

    private static func loadPreferences(from defaults: UserDefaults) -> AdBlockPreferences {
        func value(for key: AdBlockPreferenceKey, fallback: Bool) -> Bool {
            defaults.object(forKey: key.rawValue) == nil
                ? fallback
                : defaults.bool(forKey: key.rawValue)
        }
        let legacyBlockAds = defaults.object(forKey: "aitrans.browser.blockAds") == nil
            ? true
            : defaults.bool(forKey: "aitrans.browser.blockAds")
        let legacyAntiHijacking = defaults.object(forKey: "aitrans.browser.antiHijacking") == nil
            ? true
            : defaults.bool(forKey: "aitrans.browser.antiHijacking")
        return AdBlockPreferences(
            isEnabled: value(for: .master, fallback: true),
            networkFilteringEnabled: value(for: .network, fallback: legacyBlockAds),
            scriptProtectionEnabled: value(for: .script, fallback: legacyAntiHijacking),
            cosmeticFilteringEnabled: value(for: .cosmetic, fallback: true),
            popupBlockingEnabled: value(for: .popups, fallback: true),
            redirectBlockingEnabled: value(for: .redirects, fallback: true),
            elementPickerEnabled: value(for: .elementPicker, fallback: false)
        )
    }

    private static func loadElementSelectors(from defaults: UserDefaults) -> [String] {
        let values = defaults.stringArray(forKey: elementSelectorsKey) ?? []
        return Array(
            values
                .filter { value in
                    value.count <= 500
                        && value.contains("\n")
                        && !value.hasPrefix("\n")
                }
                .prefix(32)
        )
    }
}
