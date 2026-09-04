import Foundation

enum AdBlockRuleSourceFormat: String, Codable, Sendable {
    case adGuard
    case domains
}

struct AdBlockRuleSource: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let urlString: String
    let format: AdBlockRuleSourceFormat
    let license: String
    let isRequired: Bool
    let maximumResponseBytes: Int
    let maximumNetworkRules: Int
    let maximumCosmeticRules: Int

    var url: URL? { URL(string: urlString) }

    static let recommended: [Self] = [
        Self(
            id: "adguard-chinese",
            name: "AdGuard Chinese Filter",
            urlString: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_224_Chinese/filter.txt",
            format: .adGuard,
            license: "GPL-3.0 rules data",
            isRequired: false,
            maximumResponseBytes: 2_000_000,
            maximumNetworkRules: 10_000,
            maximumCosmeticRules: 5_000
        ),
        Self(
            id: "adguard-mobile",
            name: "AdGuard Mobile Ads Filter",
            urlString: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_11_Mobile/filter.txt",
            format: .adGuard,
            license: "GPL-3.0 rules data",
            isRequired: false,
            maximumResponseBytes: 1_500_000,
            maximumNetworkRules: 8_000,
            maximumCosmeticRules: 3_000
        ),
        Self(
            id: "adguard-popups",
            name: "AdGuard Popups Filter",
            urlString: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_19_Annoyances_Popups/filter.txt",
            format: .adGuard,
            license: "GPL-3.0 rules data",
            isRequired: false,
            maximumResponseBytes: 3_000_000,
            maximumNetworkRules: 6_000,
            maximumCosmeticRules: 5_000
        ),
        Self(
            id: "adguard-base",
            name: "AdGuard Base Filter",
            urlString: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_2_Base/filter.txt",
            format: .adGuard,
            license: "GPL-3.0 rules data",
            isRequired: false,
            maximumResponseBytes: 9_000_000,
            maximumNetworkRules: 24_000,
            maximumCosmeticRules: 5_000
        ),
        Self(
            id: "oisd-small",
            name: "OISD Small",
            urlString: "https://small.oisd.nl",
            format: .domains,
            license: "GPL-3.0 rules data",
            isRequired: false,
            maximumResponseBytes: 5_000_000,
            maximumNetworkRules: 8_000,
            maximumCosmeticRules: 0
        )
    ]
}

struct AdBlockRuleSnapshot: Equatable, Sendable {
    let source: AdBlockRuleSource
    let text: String
    let etag: String?
    let lastModified: String?
    let fetchedAt: Date
    let contentSHA256: String
    let cameFromCache: Bool
}

struct AdBlockSourceStatus: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var name: String
    var etag: String?
    var contentSHA256: String?
    var fetchedAt: Date?
    var lastCheckedAt: Date?
    var ruleCount: Int
    var cameFromCache: Bool
    var message: String
}

struct AdBlockSourceCompilationSummary: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let totalLines: Int
    let acceptedNetworkRules: Int
    let acceptedCosmeticRules: Int
    let skippedRules: Int
}

struct AdBlockRuleCompilation: Equatable, Sendable {
    let version: String
    let networkJSON: String
    let cosmeticJSON: String
    let networkRuleCount: Int
    let cosmeticRuleCount: Int
    let skippedRuleCount: Int
    let sourceSummaries: [AdBlockSourceCompilationSummary]
}

struct AdBlockRuleSummary: Equatable, Sendable {
    let version: String
    let networkRuleCount: Int
    let cosmeticRuleCount: Int
    let skippedRuleCount: Int
    let sourceStatuses: [AdBlockSourceStatus]
    let sourceCompilations: [AdBlockSourceCompilationSummary]
    let updatedAt: Date
}

struct AdBlockPreferences: Equatable, Sendable {
    var isEnabled: Bool
    var networkFilteringEnabled: Bool
    var scriptProtectionEnabled: Bool
    var cosmeticFilteringEnabled: Bool
    var popupBlockingEnabled: Bool
    var redirectBlockingEnabled: Bool
    var elementPickerEnabled: Bool

    static let `default` = Self(
        isEnabled: true,
        networkFilteringEnabled: true,
        scriptProtectionEnabled: true,
        cosmeticFilteringEnabled: true,
        popupBlockingEnabled: true,
        redirectBlockingEnabled: true,
        elementPickerEnabled: false
    )

    var effectiveNetworkFiltering: Bool { isEnabled && networkFilteringEnabled }
    var effectiveScriptProtection: Bool { isEnabled && scriptProtectionEnabled }
    var effectiveCosmeticFiltering: Bool { isEnabled && cosmeticFilteringEnabled }
    var effectivePopupBlocking: Bool { isEnabled && popupBlockingEnabled }
    var effectiveRedirectBlocking: Bool { isEnabled && redirectBlockingEnabled }
    var effectiveElementPicker: Bool { isEnabled && elementPickerEnabled }
}

enum AdBlockPhase: String, Equatable, Sendable {
    case idle
    case loadingCache
    case refreshing
    case ready
    case failed
}

struct AdBlockState: Equatable, Sendable {
    var phase: AdBlockPhase
    var preferences: AdBlockPreferences
    var ruleSummary: AdBlockRuleSummary?
    var isWebViewAttached: Bool
    var rememberedElementRuleCount: Int
    var blockedNavigationCount: Int
    var lastBlockedURL: String?
    var message: String
    var lastError: String?

    static func initial(
        preferences: AdBlockPreferences,
        rememberedElementRuleCount: Int
    ) -> Self {
        Self(
            phase: .idle,
            preferences: preferences,
            ruleSummary: nil,
            isWebViewAttached: false,
            rememberedElementRuleCount: rememberedElementRuleCount,
            blockedNavigationCount: 0,
            lastBlockedURL: nil,
            message: "广告防护尚未初始化",
            lastError: nil
        )
    }
}

enum AdBlockPreferenceKey: String, CaseIterable, Sendable {
    case master = "aitrans.adblock.enabled"
    case network = "aitrans.adblock.network"
    case script = "aitrans.adblock.script"
    case cosmetic = "aitrans.adblock.cosmetic"
    case popups = "aitrans.browser.blockPopups"
    case redirects = "aitrans.browser.blockRedirects"
    case elementPicker = "aitrans.browser.elementRemoval"
}

enum AdBlockError: LocalizedError, Equatable {
    case invalidSource(String)
    case responseTooLarge(String)
    case invalidResponse(String)
    case noUsableRules
    case cacheFailure(String)
    case compilationFailure(String)

    var errorDescription: String? {
        switch self {
        case let .invalidSource(name): "规则源地址无效：\(name)"
        case let .responseTooLarge(name): "规则源超过安全大小限制：\(name)"
        case let .invalidResponse(name): "规则源响应无效：\(name)"
        case .noUsableRules: "没有可用规则，已保留内置基础防护"
        case let .cacheFailure(message): "规则缓存失败：\(message)"
        case let .compilationFailure(message): "规则编译失败：\(message)"
        }
    }
}
