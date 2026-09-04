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
        case setEnabled(Bool)
        case setNetworkFiltering(Bool)
        case setScriptProtection(Bool)
        case setCosmeticFiltering(Bool)
        case setPopupBlocking(Bool)
        case setRedirectBlocking(Bool)
        case setElementPicker(Bool)
        case clearError
    }

    private(set) var state: AdBlockState

    @ObservationIgnored private let repository: AdBlockRuleRepository
    @ObservationIgnored private let compilationService: AdBlockRuleCompilationService
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var operationID = UUID()
    @ObservationIgnored private(set) var compiledRuleLists: AdBlockCompiledRuleLists?

    init(
        repository: AdBlockRuleRepository = AdBlockRuleRepository(),
        compilationService: AdBlockRuleCompilationService = AdBlockRuleCompilationService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.compilationService = compilationService
        self.userDefaults = userDefaults
        state = .initial(preferences: Self.loadPreferences(from: userDefaults))
    }

    func send(_ intent: Intent) {
        switch intent {
        case .bootstrap:
            startBootstrap()
        case let .refreshRules(force):
            startRefresh(force: force)
        case .clearCachedRules:
            startCacheClear()
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
        case .clearError:
            state.lastError = nil
        }
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
        state.message = preferences.isEnabled ? "广告防护设置已更新" : "广告防护已关闭"
    }

    private func persist(_ preferences: AdBlockPreferences) {
        userDefaults.set(preferences.isEnabled, forKey: AdBlockPreferenceKey.master.rawValue)
        userDefaults.set(preferences.networkFilteringEnabled, forKey: AdBlockPreferenceKey.network.rawValue)
        userDefaults.set(preferences.scriptProtectionEnabled, forKey: AdBlockPreferenceKey.script.rawValue)
        userDefaults.set(preferences.cosmeticFilteringEnabled, forKey: AdBlockPreferenceKey.cosmetic.rawValue)
        userDefaults.set(preferences.popupBlockingEnabled, forKey: AdBlockPreferenceKey.popups.rawValue)
        userDefaults.set(preferences.redirectBlockingEnabled, forKey: AdBlockPreferenceKey.redirects.rawValue)
        userDefaults.set(preferences.elementPickerEnabled, forKey: AdBlockPreferenceKey.elementPicker.rawValue)

        // Maintain compatibility with the previous browser-only keys until
        // every view has moved to intents in M2.
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
}
