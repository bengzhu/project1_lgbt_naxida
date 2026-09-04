import CryptoKit
import Foundation

actor AdBlockRuleCompilationService {
    func compile(_ remoteSnapshots: [AdBlockRuleSnapshot]) throws -> AdBlockRuleCompilation {
        try AdBlockRuleCompiler.compile([AdBlockRuleCompiler.builtInSnapshot] + remoteSnapshots)
    }
}

enum AdBlockRuleCompiler {
    private struct ContentRule: Encodable {
        struct Trigger: Encodable {
            let urlFilter: String
            let resourceType: [String]?
            let loadType: [String]?
            let ifDomain: [String]?
            let unlessDomain: [String]?

            enum CodingKeys: String, CodingKey {
                case urlFilter = "url-filter"
                case resourceType = "resource-type"
                case loadType = "load-type"
                case ifDomain = "if-domain"
                case unlessDomain = "unless-domain"
            }
        }

        struct Action: Encodable {
            let type: String
            let selector: String?
        }

        let trigger: Trigger
        let action: Action
    }

    private struct ParsedRule {
        let rule: ContentRule
        let key: String
    }

    private struct SourceAccumulator {
        let source: AdBlockRuleSource
        var totalLines = 0
        var acceptedNetwork = 0
        var acceptedCosmetic = 0
        var skipped = 0
    }

    static let builtInSnapshot: AdBlockRuleSnapshot = {
        let source = AdBlockRuleSource(
            id: "aitrans-built-in",
            name: "AITRANS Built-in Fallback",
            urlString: "aitrans://adblock/fallback",
            format: .adGuard,
            license: "AITRANS project code",
            isRequired: true,
            maximumResponseBytes: 64_000,
            maximumNetworkRules: 1_000,
            maximumCosmeticRules: 0
        )
        let text = """
        ||doubleclick.net^$third-party
        ||googlesyndication.com^$third-party
        ||googleadservices.com^$third-party
        ||adservice.google.com^$third-party
        ||adnxs.com^$third-party
        ||adsystem.com^$third-party
        ||popads.net^$third-party
        ||popcash.net^$third-party
        ||propellerads.com^$third-party
        ||exoclick.com^$third-party
        ||trafficjunky.net^$third-party
        ||juicyads.com^$third-party
        """
        let data = Data(text.utf8)
        return AdBlockRuleSnapshot(
            source: source,
            text: text,
            etag: nil,
            lastModified: nil,
            fetchedAt: .distantPast,
            contentSHA256: sha256Hex(data),
            cameFromCache: false
        )
    }()

    static func compile(_ snapshots: [AdBlockRuleSnapshot]) throws -> AdBlockRuleCompilation {
        var networkBlocks: [ContentRule] = []
        var networkExceptions: [ContentRule] = []
        var cosmetics: [ContentRule] = []
        var networkKeys: Set<String> = []
        var cosmeticKeys: Set<String> = []
        var summaries: [AdBlockSourceCompilationSummary] = []

        for snapshot in snapshots {
            var accumulator = SourceAccumulator(source: snapshot.source)
            snapshot.text.enumerateLines { rawLine, _ in
                accumulator.totalLines += 1
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty,
                      !line.hasPrefix("!"),
                      !line.hasPrefix("[") else {
                    return
                }

                if line.contains("##") || line.contains("#@#") || line.contains("#?#")
                    || line.contains("#$#") || line.contains("#%#") {
                    guard accumulator.acceptedCosmetic < snapshot.source.maximumCosmeticRules,
                          let parsed = parseCosmeticRule(line),
                          cosmeticKeys.insert(parsed.key).inserted else {
                        accumulator.skipped += 1
                        return
                    }
                    cosmetics.append(parsed.rule)
                    accumulator.acceptedCosmetic += 1
                    return
                }

                guard accumulator.acceptedNetwork < snapshot.source.maximumNetworkRules,
                      let parsed = parseNetworkRule(line, format: snapshot.source.format),
                      networkKeys.insert(parsed.key).inserted else {
                    accumulator.skipped += 1
                    return
                }
                if parsed.rule.action.type == "ignore-previous-rules" {
                    networkExceptions.append(parsed.rule)
                } else {
                    networkBlocks.append(parsed.rule)
                }
                accumulator.acceptedNetwork += 1
            }
            summaries.append(
                AdBlockSourceCompilationSummary(
                    id: snapshot.source.id,
                    name: snapshot.source.name,
                    totalLines: accumulator.totalLines,
                    acceptedNetworkRules: accumulator.acceptedNetwork,
                    acceptedCosmeticRules: accumulator.acceptedCosmetic,
                    skippedRules: accumulator.skipped
                )
            )
        }

        let networkRules = networkBlocks + networkExceptions
        guard !networkRules.isEmpty else { throw AdBlockError.noUsableRules }
        let cosmeticRules = cosmetics.isEmpty ? [cosmeticNoOpRule] : cosmetics
        let networkJSON = try encodedJSON(networkRules)
        let cosmeticJSON = try encodedJSON(cosmeticRules)
        let versionSeed = snapshots
            .map { "\($0.source.id):\($0.contentSHA256)" }
            .joined(separator: "|")
            + "|compiler=v1|network=\(networkRules.count)|cosmetic=\(cosmetics.count)"
        let version = String(sha256Hex(Data(versionSeed.utf8)).prefix(20))
        return AdBlockRuleCompilation(
            version: version,
            networkJSON: networkJSON,
            cosmeticJSON: cosmeticJSON,
            networkRuleCount: networkRules.count,
            cosmeticRuleCount: cosmetics.count,
            skippedRuleCount: summaries.reduce(0) { $0 + $1.skippedRules },
            sourceSummaries: summaries
        )
    }

    private static func parseNetworkRule(
        _ rawLine: String,
        format: AdBlockRuleSourceFormat
    ) -> ParsedRule? {
        if format == .domains {
            return parseDomainListRule(rawLine)
        }

        let isException = rawLine.hasPrefix("@@")
        let line = isException ? String(rawLine.dropFirst(2)) : rawLine
        let components = line.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
        let pattern = String(components[0])
        let modifierText = components.count == 2 ? String(components[1]) : ""
        guard pattern.hasPrefix("||"),
              let host = anchoredHost(from: pattern) else {
            return nil
        }

        let modifiers = modifierText.isEmpty
            ? []
            : modifierText.split(separator: ",").map(String.init)
        var resourceTypes: Set<String> = []
        var loadTypes: Set<String> = []
        var ifDomains: [String] = []
        var unlessDomains: [String] = []
        let typeMap = [
            "document": "document",
            "subdocument": "document",
            "image": "image",
            "stylesheet": "style-sheet",
            "script": "script",
            "font": "font",
            "media": "media",
            "xmlhttprequest": "raw",
            "other": "raw",
            "object": "raw",
            "websocket": "raw",
            "popup": "popup"
        ]
        for modifier in modifiers {
            if modifier == "third-party" {
                loadTypes.insert("third-party")
            } else if modifier == "first-party" {
                loadTypes.insert("first-party")
            } else if modifier == "important" {
                continue
            } else if modifier.hasPrefix("domain=") {
                let value = String(modifier.dropFirst("domain=".count))
                guard parseDomainConditions(
                    value,
                    ifDomains: &ifDomains,
                    unlessDomains: &unlessDomains
                ) else { return nil }
            } else if modifier.hasPrefix("~") {
                return nil
            } else if let resourceType = typeMap[modifier] {
                resourceTypes.insert(resourceType)
            } else if !modifier.isEmpty {
                // Skipping unknown semantic modifiers avoids broadening a
                // redirect/removeparam/scriptlet rule into a plain block.
                return nil
            }
        }

        let escapedHost = NSRegularExpression.escapedPattern(for: host)
        let urlFilter = "^https?://([^/]+\\.)?\(escapedHost)([:/?#]|$)"
        let actionType = isException ? "ignore-previous-rules" : "block"
        let sortedResources = resourceTypes.isEmpty ? nil : resourceTypes.sorted()
        let sortedLoads = loadTypes.isEmpty ? nil : loadTypes.sorted()
        let normalizedIfDomains = ifDomains.isEmpty ? nil : Array(Set(ifDomains)).sorted()
        let normalizedUnlessDomains = unlessDomains.isEmpty ? nil : Array(Set(unlessDomains)).sorted()
        let key = [
            actionType,
            urlFilter,
            sortedResources?.joined(separator: ",") ?? "",
            sortedLoads?.joined(separator: ",") ?? "",
            normalizedIfDomains?.joined(separator: ",") ?? "",
            normalizedUnlessDomains?.joined(separator: ",") ?? ""
        ].joined(separator: "|")
        return ParsedRule(
            rule: ContentRule(
                trigger: ContentRule.Trigger(
                    urlFilter: urlFilter,
                    resourceType: sortedResources,
                    loadType: sortedLoads,
                    ifDomain: normalizedIfDomains,
                    unlessDomain: normalizedUnlessDomains
                ),
                action: ContentRule.Action(type: actionType, selector: nil)
            ),
            key: key
        )
    }

    private static func parseDomainListRule(_ rawLine: String) -> ParsedRule? {
        var fields = rawLine.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if fields.count == 2, fields[0] == "0.0.0.0" || fields[0] == "127.0.0.1" {
            fields.removeFirst()
        }
        guard fields.count == 1,
              let host = fields[0].hasPrefix("||")
                ? anchoredHost(from: fields[0])
                : normalizedHost(fields[0]) else { return nil }
        let escapedHost = NSRegularExpression.escapedPattern(for: host)
        let urlFilter = "^https?://([^/]+\\.)?\(escapedHost)([:/?#]|$)"
        return ParsedRule(
            rule: ContentRule(
                trigger: ContentRule.Trigger(
                    urlFilter: urlFilter,
                    resourceType: nil,
                    loadType: nil,
                    ifDomain: nil,
                    unlessDomain: nil
                ),
                action: ContentRule.Action(type: "block", selector: nil)
            ),
            key: "block|\(urlFilter)"
        )
    }

    private static func parseCosmeticRule(_ line: String) -> ParsedRule? {
        guard !line.contains("#@#"),
              !line.contains("#?#"),
              !line.contains("#$#"),
              !line.contains("#%#"),
              let marker = line.range(of: "##") else { return nil }
        let domainText = String(line[..<marker.lowerBound])
        let selector = String(line[marker.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !domainText.isEmpty,
              !domainText.contains("["),
              isSafeCosmeticSelector(selector) else { return nil }

        var ifDomains: [String] = []
        var unlessDomains: [String] = []
        guard parseDomainConditions(
            domainText.replacing(",", with: "|"),
            ifDomains: &ifDomains,
            unlessDomains: &unlessDomains
        ), !ifDomains.isEmpty else { return nil }
        let normalizedIfDomains = Array(Set(ifDomains)).sorted()
        let normalizedUnlessDomains = Array(Set(unlessDomains)).sorted()
        let key = [
            selector,
            normalizedIfDomains.joined(separator: ","),
            normalizedUnlessDomains.joined(separator: ",")
        ].joined(separator: "|")
        return ParsedRule(
            rule: ContentRule(
                trigger: ContentRule.Trigger(
                    urlFilter: ".*",
                    resourceType: nil,
                    loadType: nil,
                    ifDomain: normalizedIfDomains,
                    unlessDomain: normalizedUnlessDomains.isEmpty ? nil : normalizedUnlessDomains
                ),
                action: ContentRule.Action(type: "css-display-none", selector: selector)
            ),
            key: key
        )
    }

    private static func anchoredHost(from pattern: String) -> String? {
        let candidate = String(pattern.dropFirst(2))
        let boundary = candidate.firstIndex(where: { $0 == "^" || $0 == "/" })
        let rawHost = boundary.map { String(candidate[..<$0]) } ?? candidate
        if let boundary {
            guard candidate[boundary] == "^",
                  candidate.index(after: boundary) == candidate.endIndex else { return nil }
        }
        return normalizedHost(rawHost)
    }

    private static func normalizedHost(_ rawValue: String) -> String? {
        var host = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("*.") { host.removeFirst(2) }
        while host.hasSuffix(".") { host.removeLast() }
        guard host.count >= 3,
              host.contains("."),
              !host.contains(".."),
              host.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_")
                      .contains($0)
              }),
              host.split(separator: ".").allSatisfy({ !$0.isEmpty }) else {
            return nil
        }
        return host
    }

    private static func parseDomainConditions(
        _ value: String,
        ifDomains: inout [String],
        unlessDomains: inout [String]
    ) -> Bool {
        for rawDomain in value.split(separator: "|") {
            let isExcluded = rawDomain.hasPrefix("~")
            let value = isExcluded ? String(rawDomain.dropFirst()) : String(rawDomain)
            guard let domain = normalizedHost(value), !domain.contains("*") else { return false }
            let webKitDomain = "*\(domain)"
            if isExcluded {
                unlessDomains.append(webKitDomain)
            } else {
                ifDomains.append(webKitDomain)
            }
        }
        return !ifDomains.isEmpty || !unlessDomains.isEmpty
    }

    private static func isSafeCosmeticSelector(_ selector: String) -> Bool {
        guard !selector.isEmpty,
              selector.count <= 300,
              selector.contains(where: { $0 == "." || $0 == "#" || $0 == "[" }),
              !selector.contains(","),
              !selector.contains("{"),
              !selector.contains("}"),
              !selector.contains(";"),
              !selector.contains("url("),
              !selector.contains(":has("),
              !selector.contains(":contains("),
              !selector.contains(":xpath("),
              !selector.contains(":matches-css("),
              !selector.contains(":style("),
              !selector.contains(":remove(") else { return false }
        let normalized = selector
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized.contains(".") || normalized.contains("#") || normalized.contains("=") else {
            return false
        }
        let broadAttributeMatchers = [
            "[class*=", "[class^=", "[class$=",
            "[id*=", "[id^=", "[id$="
        ]
        guard !broadAttributeMatchers.contains(where: normalized.contains) else {
            return false
        }

        let finalCompound = normalized
            .split(whereSeparator: { $0.isWhitespace || $0 == ">" || $0 == "+" || $0 == "~" })
            .last
            .map(String.init) ?? normalized
        let forbiddenRoots: Set<String> = [
            "*", ":root", "html", "body", "main", "article", "[role=main]",
            "[role=\"main\"]", "[role='main']"
        ]
        guard !forbiddenRoots.contains(finalCompound) else { return false }
        return !["html", "body", "main", "article", ":root"].contains { root in
            finalCompound.hasPrefix("\(root).")
                || finalCompound.hasPrefix("\(root)#")
                || finalCompound.hasPrefix("\(root)[")
                || finalCompound.hasPrefix("\(root):")
        }
    }

    private static let cosmeticNoOpRule = ContentRule(
        trigger: ContentRule.Trigger(
            urlFilter: ".*",
            resourceType: nil,
            loadType: nil,
            ifDomain: nil,
            unlessDomain: nil
        ),
        action: ContentRule.Action(
            type: "css-display-none",
            selector: "[data-aitrans-adblock-never-match]"
        )
    )

    private static func encodedJSON(_ rules: [ContentRule]) throws -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(rules)
            guard let json = String(data: data, encoding: .utf8) else {
                throw AdBlockError.compilationFailure("无法编码 WebKit JSON")
            }
            return json
        } catch let error as AdBlockError {
            throw error
        } catch {
            throw AdBlockError.compilationFailure(error.localizedDescription)
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
