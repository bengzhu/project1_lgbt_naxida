import Foundation

enum TranslationTextKind: String, Codable, Sendable, Hashable {
    case dialogue
    case narration
    case sfx
    case title
    case other

    var promptLabel: String {
        switch self {
        case .dialogue: "对白"
        case .narration: "旁白"
        case .sfx: "拟声词"
        case .title: "标题"
        case .other: "其他"
        }
    }

    func defaultMaximumOutputCharacters(for sourceCount: Int) -> Int {
        let count = max(sourceCount, 1)
        switch self {
        case .dialogue:
            return max(96, count * 4 + 48)
        case .narration:
            return max(140, count * 5 + 64)
        case .sfx:
            return max(48, count * 4 + 24)
        case .title:
            return max(72, count * 3 + 24)
        case .other:
            return max(120, count * 4 + 48)
        }
    }
}

enum TranslationTermKind: String, Codable, Sendable {
    case terminology
    case personName
    case addressing
    case sfx
    case narration
}

enum TranslationTermStatus: String, Codable, Sendable {
    case confirmed
    case candidate
    case revoked
}

struct TranslationTermMemoryEntry: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var source: String
    var target: String
    var kind: TranslationTermKind
    var status: TranslationTermStatus
    var note: String?

    init(
        id: String = UUID().uuidString,
        source: String,
        target: String,
        kind: TranslationTermKind,
        status: TranslationTermStatus = .confirmed,
        note: String? = nil
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.kind = kind
        self.status = status
        self.note = note
    }
}

struct TranslationReadOnlyBatchItem: Equatable, Codable, Sendable {
    var ordinal: Int
    var sourceExcerpt: String
    var targetExcerpt: String
    var kind: TranslationTextKind
}

struct TranslationReadOnlyBatchSummary: Equatable, Codable, Sendable {
    var batchID: String
    var sourceLanguage: SupportedLanguage
    var targetLanguage: SupportedLanguage
    var items: [TranslationReadOnlyBatchItem]
    var generatedFromCompletedBlocks: Bool

    var isReadOnly: Bool { true }
    var containsPendingInputBlocks: Bool { false }

    init(
        batchID: String,
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage,
        items: [TranslationReadOnlyBatchItem],
        generatedFromCompletedBlocks: Bool = true
    ) {
        self.batchID = batchID
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.items = items
        self.generatedFromCompletedBlocks = generatedFromCompletedBlocks
    }
}

struct TranslationPromptContext: Equatable, Codable, Sendable {
    var confirmedTerms: [TranslationTermMemoryEntry]
    var previousBatchSummary: TranslationReadOnlyBatchSummary?
    var textKind: TranslationTextKind
    var maxOutputCharacters: Int?
    /// Optional per-block style hints for a mixed image translation batch.
    /// These are prompt metadata only; they never become pending input or
    /// persisted block content.
    var batchTextKinds: [TranslationTextKind]
    /// Zero-based start offset for the tagged image batch. When present, the
    /// mixed-kind prompt can use the same global block ordinals as `[N]` input
    /// tags without making those metadata lines part of the input.
    var batchStartIndex: Int?

    static let empty = TranslationPromptContext(
        confirmedTerms: [],
        previousBatchSummary: nil,
        textKind: .dialogue,
        maxOutputCharacters: nil,
        batchTextKinds: [],
        batchStartIndex: nil
    )

    init(
        confirmedTerms: [TranslationTermMemoryEntry] = [],
        previousBatchSummary: TranslationReadOnlyBatchSummary? = nil,
        textKind: TranslationTextKind = .dialogue,
        maxOutputCharacters: Int? = nil,
        batchTextKinds: [TranslationTextKind] = [],
        batchStartIndex: Int? = nil
    ) {
        self.confirmedTerms = confirmedTerms
        self.previousBatchSummary = previousBatchSummary
        self.textKind = textKind
        self.maxOutputCharacters = maxOutputCharacters
        self.batchTextKinds = batchTextKinds
        self.batchStartIndex = batchStartIndex
    }

    private enum CodingKeys: String, CodingKey {
        case confirmedTerms
        case previousBatchSummary
        case textKind
        case maxOutputCharacters
        case batchTextKinds
        case batchStartIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        confirmedTerms = try container.decode(
            [TranslationTermMemoryEntry].self,
            forKey: .confirmedTerms
        )
        previousBatchSummary = try container.decodeIfPresent(
            TranslationReadOnlyBatchSummary.self,
            forKey: .previousBatchSummary
        )
        textKind = try container.decode(
            TranslationTextKind.self,
            forKey: .textKind
        )
        maxOutputCharacters = try container.decodeIfPresent(
            Int.self,
            forKey: .maxOutputCharacters
        )
        // Older transient context payloads predate v3.299.
        batchTextKinds = try container.decodeIfPresent(
            [TranslationTextKind].self,
            forKey: .batchTextKinds
        ) ?? []
        batchStartIndex = try container.decodeIfPresent(
            Int.self,
            forKey: .batchStartIndex
        )
    }

    var isEmpty: Bool {
        confirmedTerms.filter { $0.status == .confirmed }.isEmpty
            && previousBatchSummary == nil
            && maxOutputCharacters == nil
            && textKind == .dialogue
            && batchTextKinds.isEmpty
            && batchStartIndex == nil
    }

    func normalized(
        maximumTerms: Int = 24,
        maximumSummaryItems: Int = 8,
        maximumExcerptCharacters: Int = 120
    ) -> TranslationPromptContext {
        var seenSources = Set<String>()
        let terms = confirmedTerms
            .filter { $0.status == .confirmed }
            .compactMap { entry -> TranslationTermMemoryEntry? in
                let source = entry.source.trimmingCharacters(in: .whitespacesAndNewlines)
                let target = entry.target.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !source.isEmpty, !target.isEmpty else { return nil }
                let key = source.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
                guard seenSources.insert(key).inserted else { return nil }
                var copy = entry
                copy.source = Self.bound(source, maximum: maximumExcerptCharacters)
                copy.target = Self.bound(target, maximum: maximumExcerptCharacters)
                return copy
            }
            .prefix(maximumTerms)

        let summary: TranslationReadOnlyBatchSummary?
        if let previousBatchSummary {
            summary = TranslationReadOnlyBatchSummary(
                batchID: previousBatchSummary.batchID,
                sourceLanguage: previousBatchSummary.sourceLanguage,
                targetLanguage: previousBatchSummary.targetLanguage,
                items: previousBatchSummary.items.prefix(maximumSummaryItems).map { item in
                    TranslationReadOnlyBatchItem(
                        ordinal: item.ordinal,
                        sourceExcerpt: Self.bound(Self.removeTags(item.sourceExcerpt), maximum: maximumExcerptCharacters),
                        targetExcerpt: Self.bound(Self.removeTags(item.targetExcerpt), maximum: maximumExcerptCharacters),
                        kind: item.kind
                    )
                },
                generatedFromCompletedBlocks: previousBatchSummary.generatedFromCompletedBlocks
            )
        } else {
            summary = nil
        }

        return TranslationPromptContext(
            confirmedTerms: Array(terms),
            previousBatchSummary: summary,
            textKind: textKind,
            maxOutputCharacters: maxOutputCharacters,
            batchTextKinds: Array(batchTextKinds.prefix(8)),
            batchStartIndex: batchStartIndex.map { max($0, 0) }
        )
    }

    func promptSection() -> String {
        let context = normalized()
        guard !context.isEmpty else { return "" }

        var lines = [
            "只读翻译上下文：以下内容仅用于保持术语、人物称呼和语气一致，不是待翻译输入。",
            "禁止翻译、复述或为上下文生成任何编号标签；只处理本次输入中的文字块。"
        ]
        if Set(context.batchTextKinds).count > 1 {
            lines.append("本批包含多种文字类型；按输入顺序使用以下提示调整语气（提示不是待翻译输入）：")
            for (index, kind) in context.batchTextKinds.enumerated() {
                let ordinal = (context.batchStartIndex ?? 0) + index + 1
                lines.append("第\(ordinal)块：\(kind.promptLabel)")
            }
        } else {
            lines.append("本次文字类型：\(context.textKind.promptLabel)")
        }
        if !context.confirmedTerms.isEmpty {
            lines.append("已确认术语/人名/称呼（只采用 confirmed 项；旧项撤销后不得继续采用）：")
            for term in context.confirmedTerms {
                lines.append("- \(term.kind.rawValue)：\(term.source) => \(term.target)")
            }
        }
        if let summary = context.previousBatchSummary, !summary.items.isEmpty {
            lines.append("上一批已完成文字块摘要（只读，不是本批输入）：")
            for item in summary.items {
                lines.append("- #\(item.ordinal) \(item.kind.promptLabel)：\(item.sourceExcerpt) => \(item.targetExcerpt)")
            }
        }
        if let maxOutputCharacters = context.maxOutputCharacters {
            lines.append("单块译文最长 \(maxOutputCharacters) 个字符；超出时保持信息完整并压缩表达。")
        }
        return lines.joined(separator: "\n")
    }

    private static func bound(_ text: String, maximum: Int) -> String {
        guard text.count > maximum else { return text }
        return String(text.prefix(maximum)) + "…"
    }

    private static func removeTags(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\[\d+\]"#,
            with: "",
            options: .regularExpression
        )
    }
}

struct TranslationBatchQAInputItem: Equatable, Sendable {
    var id: Int
    var sourceText: String
    var kind: TranslationTextKind
}

struct TranslationBatchQAConfiguration: Equatable, Sendable {
    var targetLanguage: SupportedLanguage
    var confirmedTerms: [TranslationTermMemoryEntry]
    var previousBatchSummary: TranslationReadOnlyBatchSummary?
    var minimumTargetLanguageDensity: Double
    var maximumOutputCharacters: Int?

    init(
        targetLanguage: SupportedLanguage,
        confirmedTerms: [TranslationTermMemoryEntry] = [],
        previousBatchSummary: TranslationReadOnlyBatchSummary? = nil,
        minimumTargetLanguageDensity: Double = 0.35,
        maximumOutputCharacters: Int? = nil
    ) {
        self.targetLanguage = targetLanguage
        self.confirmedTerms = confirmedTerms
        self.previousBatchSummary = previousBatchSummary
        self.minimumTargetLanguageDensity = minimumTargetLanguageDensity
        self.maximumOutputCharacters = maximumOutputCharacters
    }
}

/// Shared, conservative classifier for model meta-responses.
///
/// A translated sentence may legitimately contain words such as “谢谢” or
/// “请提供证件”.  Treating those words as placeholders rejects real dialogue
/// before it reaches the user.  Only an explicit refusal, an input-request
/// tied to translation, or a meta-only label is classified as a placeholder.
enum TranslationOutputPolicy {
    static func isPlaceholderResponse(_ text: String) -> Bool {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return false }
        let compact = normalized.filter { !$0.isWhitespace && !$0.isPunctuation }

        let exactMetaResponses = [
            "na",
            "待翻译",
            "以下是翻译",
            "这是翻译",
            "翻译如下",
            "翻译成中文",
            "translationunavailable",
            "notranslationavailable",
            "cannottranslate",
            "unabletotranslate",
            "pleaseprovide",
            "providethetext",
            "translate the following".replacingOccurrences(of: " ", with: ""),
            "翻译是",
            "意思是",
            "这句话的意思",
            "最合适的翻译",
            "最通用的翻译",
            "最常用的翻译"
        ]
        if exactMetaResponses.contains(compact) {
            return true
        }

        let refusalMarkers = [
            "无法翻译",
            "无法完成翻译",
            "无法提供译文",
            "翻译失败",
            "需要更多上下文",
            "需要更多信息",
            "请提供更多上下文",
            "请提供更多信息",
            "cannottranslate",
            "unabletotranslate",
            "translationunavailable",
            "notranslationavailable",
            "pleaseprovidemorecontext",
            "pleaseprovidemoreinformation",
            "needmorecontext",
            "needmoreinformation",
            "pleaseprovidethetext",
            "providethetexttotranslate",
            "请将以下翻译成中文",
            "请将以上翻译成中文",
            "请将以下翻译转换成中文",
            "请将以上翻译转换成中文",
            "把以下翻译成中文",
            "翻译转换成中文"
        ]
        if compact.count <= 96,
           refusalMarkers.contains(where: { compact.contains($0.filter { !$0.isWhitespace && !$0.isPunctuation }) }) {
            return true
        }

        let requestMarkers = [
            "请提供",
            "请您提供",
            "请你提供",
            "请输入",
            "请给出",
            "pleaseprovide",
            "pleaseenter",
            "pleasesend",
            "kindlyprovide"
        ]
        let translationInputMarkers = [
            "需要翻译的文本",
            "想要翻译的文本",
            "待翻译文本",
            "翻译文本",
            "原文",
            "译文",
            "文本",
            "内容",
            "句子",
            "文字",
            "text",
            "sourcetext",
            "translation",
            "sentence",
            "content"
        ]
        guard compact.count <= 96,
              requestMarkers.contains(where: { compact.contains($0.filter { !$0.isWhitespace && !$0.isPunctuation }) }),
              translationInputMarkers.contains(where: { compact.contains($0.filter { !$0.isWhitespace && !$0.isPunctuation }) }) else {
            return false
        }
        return true
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

struct TranslationBatchQualityReport: Equatable, Sendable {
    var values: [String?]
    var failedOffsets: [Int]
    var failureReasonsByOffset: [Int: [String]]
    var batchFailureReasons: [String]
    var tagComplete: Bool
    var accepted: Bool
}

enum TranslationBatchQualityEvaluator {
    static func evaluate(
        output: String,
        items: [TranslationBatchQAInputItem],
        configuration: TranslationBatchQAConfiguration
    ) -> TranslationBatchQualityReport {
        guard !items.isEmpty else {
            return TranslationBatchQualityReport(
                values: [],
                failedOffsets: [],
                failureReasonsByOffset: [:],
                batchFailureReasons: ["emptyInput"],
                tagComplete: false,
                accepted: false
            )
        }

        let expectedIDs = items.map(\.id)
        var values = Array<String?>(repeating: nil, count: items.count)
        var failureReasonsByOffset: [Int: [String]] = [:]
        var batchFailureReasons: [String] = []
        var failedOffsets = Set<Int>()

        func addFailure(offset: Int, reason: String) {
            failedOffsets.insert(offset)
            var reasons = failureReasonsByOffset[offset, default: []]
            if !reasons.contains(reason) { reasons.append(reason) }
            failureReasonsByOffset[offset] = reasons
        }

        let normalizedOutput = normalizeModelOutput(output)
        let records = taggedRecords(in: normalizedOutput)
        var offsetsByID: [Int: [Int]] = [:]
        var recognizedOrder: [Int] = []
        var hasUnexpectedTag = false
        for record in records {
            guard let offset = items.firstIndex(where: { $0.id == record.id }) else {
                hasUnexpectedTag = true
                continue
            }
            offsetsByID[record.id, default: []].append(offset)
            recognizedOrder.append(record.id)
            if values[offset] == nil {
                values[offset] = record.value
            }
        }

        guard !records.isEmpty else {
            for offset in items.indices { addFailure(offset: offset, reason: "missingTags") }
            return report(
                values: values,
                failedOffsets: failedOffsets,
                failureReasonsByOffset: failureReasonsByOffset,
                batchFailureReasons: ["missingTags"],
                tagComplete: false
            )
        }

        if hasUnexpectedTag {
            batchFailureReasons.append("extraTag")
            for offset in items.indices { addFailure(offset: offset, reason: "extraTag") }
        }

        for (offset, item) in items.enumerated() {
            let occurrences = offsetsByID[item.id, default: []]
            if occurrences.isEmpty {
                addFailure(offset: offset, reason: "missingTags")
            } else if occurrences.count > 1 {
                addFailure(offset: offset, reason: "duplicateTags")
                values[offset] = nil
            }
        }

        let expectedRecognized = expectedIDs.filter { offsetsByID[$0]?.isEmpty == false }
        if expectedRecognized != recognizedOrder {
            batchFailureReasons.append("outOfOrderTags")
            for (index, id) in recognizedOrder.enumerated() {
                guard index < expectedRecognized.count,
                      expectedRecognized[index] == id else {
                    if let offset = items.firstIndex(where: { $0.id == id }) {
                        addFailure(offset: offset, reason: "outOfOrderTags")
                    }
                    if index < expectedRecognized.count,
                       let expectedOffset = items.firstIndex(where: { $0.id == expectedRecognized[index] }) {
                        addFailure(offset: expectedOffset, reason: "outOfOrderTags")
                    }
                    continue
                }
            }
        }

        for (offset, item) in items.enumerated() {
            guard !failedOffsets.contains(offset), let value = values[offset] else { continue }
            let reasons = textFailures(
                source: item.sourceText,
                output: value,
                kind: item.kind,
                configuration: configuration
            )
            for reason in reasons { addFailure(offset: offset, reason: reason) }
            if !reasons.isEmpty { values[offset] = nil }
        }

        let tagComplete = batchFailureReasons.isEmpty
            && items.indices.allSatisfy { !failedOffsets.contains($0) || !(failureReasonsByOffset[$0] ?? []).contains("missingTags") }
            && records.count == expectedIDs.count
            && recognizedOrder == expectedIDs
        return report(
            values: values,
            failedOffsets: failedOffsets,
            failureReasonsByOffset: failureReasonsByOffset,
            batchFailureReasons: batchFailureReasons,
            tagComplete: tagComplete,
            sort: true
        )
    }

    static func singleOutputFailures(
        output: String,
        sourceText: String,
        kind: TranslationTextKind = .dialogue,
        configuration: TranslationBatchQAConfiguration
    ) -> [String] {
        textFailures(
            source: sourceText,
            output: normalizeModelOutput(output),
            kind: kind,
            configuration: configuration
        )
    }

    private static func report(
        values: [String?],
        failedOffsets: Set<Int>,
        failureReasonsByOffset: [Int: [String]],
        batchFailureReasons: [String],
        tagComplete: Bool,
        sort: Bool = false
    ) -> TranslationBatchQualityReport {
        let offsets = sort ? failedOffsets.sorted() : Array(failedOffsets)
        return TranslationBatchQualityReport(
            values: values,
            failedOffsets: offsets,
            failureReasonsByOffset: failureReasonsByOffset,
            batchFailureReasons: batchFailureReasons,
            tagComplete: tagComplete,
            accepted: offsets.isEmpty && batchFailureReasons.isEmpty
        )
    }

    private static func textFailures(
        source: String,
        output: String,
        kind: TranslationTextKind,
        configuration: TranslationBatchQAConfiguration
    ) -> [String] {
        let sourceText = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let translatedText = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translatedText.isEmpty else { return ["emptyOutput"] }

        var failures: [String] = []
        let normalizedSource = comparableText(sourceText)
        let normalizedOutput = comparableText(translatedText)
        if TranslationOutputPolicy.isPlaceholderResponse(translatedText) {
            failures.append("placeholderOutput")
        }
        if normalizedSource.count > 1,
           !isOnlyDigits(normalizedSource),
           normalizedOutput.contains(normalizedSource) {
            failures.append("sourceLeakage")
        }

        if numericTokens(in: sourceText) != numericTokens(in: translatedText) {
            failures.append("numberMismatch")
        }

        if let previousBatchSummary = configuration.previousBatchSummary {
            let normalizedOutput = comparableText(translatedText)
            let copiedPreviousBatch = previousBatchSummary.items.contains { item in
                let previousTarget = comparableText(item.targetExcerpt)
                return previousTarget.count >= 4 && normalizedOutput.contains(previousTarget)
            }
            if copiedPreviousBatch {
                failures.append("previousContextLeakage")
            }
        }

        for term in configuration.confirmedTerms where term.status == .confirmed {
            let termSource = term.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let termTarget = term.target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !termSource.isEmpty, !termTarget.isEmpty,
                  sourceText.localizedCaseInsensitiveContains(termSource) else { continue }
            if !translatedText.localizedCaseInsensitiveContains(termTarget) {
                failures.append("confirmedTermMismatch")
            }
        }

        let maximum = configuration.maximumOutputCharacters
            ?? kind.defaultMaximumOutputCharacters(for: sourceText.count)
        if translatedText.count > maximum {
            failures.append("outputTooLong")
        }

        let density = targetLanguageDensity(translatedText, language: configuration.targetLanguage)
        if density < configuration.minimumTargetLanguageDensity {
            failures.append("targetLanguageDensity")
        }
        return failures
    }

    private static func taggedRecords(in text: String) -> [(id: Int, value: String)] {
        let pattern = #"(?m)^\s*\[(\d+)\]\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.enumerated().compactMap { index, match in
            guard let idRange = Range(match.range(at: 1), in: text),
                  let id = Int(text[idRange]) else { return nil }
            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count ? matches[index + 1].range.location : nsText.length
            guard end >= start else { return nil }
            let value = nsText.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (id: id, value: value)
        }
    }

    private static func normalizeModelOutput(_ output: String) -> String {
        var text = output
            .replacingOccurrences(of: "```text", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["<end_of_turn>", "<start_of_turn>"] {
            if let range = text.range(of: marker) {
                text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    private static func comparableText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .joined()
    }

    private static func isOnlyDigits(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private static func numericTokens(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:[.,:/-]\d+)*"#) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            .map { nsText.substring(with: $0.range).lowercased() }
    }

    private static func targetLanguageDensity(_ text: String, language: SupportedLanguage) -> Double {
        let relevant = text.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
        }
        guard !relevant.isEmpty else { return 0 }
        let signal = relevant.filter { scalar in
            let value = Int(scalar.value)
            switch language {
            case .simplifiedChinese:
                return (0x4E00...0x9FFF).contains(value)
            case .japanese:
                return (0x3040...0x30FF).contains(value) || (0x4E00...0x9FFF).contains(value)
            case .englishUS, .french, .german:
                return (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value)
            }
        }
        return Double(signal.count) / Double(relevant.count)
    }
}
