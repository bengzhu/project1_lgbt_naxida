import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

private func snapshot(
    id: String,
    format: AdBlockRuleSourceFormat,
    text: String
) -> AdBlockRuleSnapshot {
    let source = AdBlockRuleSource(
        id: id,
        name: id,
        urlString: "https://example.invalid/\(id)",
        format: format,
        license: "test fixture",
        isRequired: false,
        maximumResponseBytes: 64_000,
        maximumNetworkRules: 100,
        maximumCosmeticRules: 100
    )
    return AdBlockRuleSnapshot(
        source: source,
        text: text,
        etag: nil,
        lastModified: nil,
        fetchedAt: .distantPast,
        contentSHA256: id,
        cameFromCache: false
    )
}

@main
private struct AdBlockRuleCompilerSmoke {
    static func main() throws {
        let adGuard = snapshot(
            id: "adguard",
            format: .adGuard,
            text: """
            ||ads.example^$script,third-party
            @@||ads.example^$domain=reader.example
            ||redirect.example^$redirect=noopjs
            ||wide.example^path
            reader.example##.ad-slot
            reader.example##[class*="ad"]
            ##.generic-ad
            reader.example##body
            reader.example##html.adblock-wall
            """
        )
        let domains = snapshot(
            id: "domains",
            format: .domains,
            text: "0.0.0.0 tracker.example"
        )
        let result = try AdBlockRuleCompiler.compile([adGuard, domains])

        require(result.networkRuleCount == 3, "expected block, exception, and domain rules")
        require(result.cosmeticRuleCount == 1, "only the domain-scoped safe selector may compile")
        require(result.skippedRuleCount == 6, "unsafe or unsupported syntax must be counted")

        let networkData = Data(result.networkJSON.utf8)
        let cosmeticData = Data(result.cosmeticJSON.utf8)
        let network = try JSONSerialization.jsonObject(with: networkData) as? [[String: Any]]
        let cosmetic = try JSONSerialization.jsonObject(with: cosmeticData) as? [[String: Any]]
        require(network?.count == 3, "network JSON must be a valid WebKit rule array")
        require(cosmetic?.count == 1, "cosmetic JSON must be a valid WebKit rule array")

        let actions = network?.compactMap { ($0["action"] as? [String: Any])?["type"] as? String } ?? []
        require(actions == ["block", "block", "ignore-previous-rules"], "exceptions must follow block rules")
        let triggers = network?.compactMap { $0["trigger"] as? [String: Any] } ?? []
        require(triggers.contains { ($0["load-type"] as? [String]) == ["third-party"] }, "third-party modifier lost")
        require(triggers.contains { ($0["if-domain"] as? [String]) == ["*reader.example"] }, "domain condition lost")

        let cosmeticAction = cosmetic?.first?["action"] as? [String: Any]
        let selector = cosmeticAction?["selector"] as? String
        require(selector == ".ad-slot", "safe domain-scoped selector was not preserved")
        require(!result.cosmeticJSON.contains("class*="), "broad class selector must never reach WebKit")
        require(!result.cosmeticJSON.contains("adblock-wall"), "root selector must never reach WebKit")
        require(!result.networkJSON.contains("wide.example"), "path syntax must not broaden into a domain block")

        let fallback = try AdBlockRuleCompiler.compile([AdBlockRuleCompiler.builtInSnapshot])
        require(fallback.networkRuleCount == 12, "built-in fallback rules must remain independently usable")

        print("AdBlock rule compiler smoke passed: network=\(result.networkRuleCount), cosmetic=\(result.cosmeticRuleCount), skipped=\(result.skippedRuleCount)")
    }
}
