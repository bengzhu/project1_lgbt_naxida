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

    var promptStyleGuidance: String {
        switch self {
        case .dialogue:
            "保留说话人的口语语气、关系和情绪；不要补写旁白或解释性句子。"
        case .narration:
            "保持简洁的叙述语气；不要改写成角色对白或添加说话人。"
        case .sfx:
            "仅使用简短的中文拟声或动作表达，保留节奏；不要补写主语、解释动作或扩写成完整句子。"
        case .title:
            "保持紧凑的标题式表达；不要添加解释句、标点说明或正文语气。"
        case .other:
            "忠实、自然地翻译并保留信息；不要套用对白、旁白或声效的专属风格。"
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

/// Infers only a high-signal sound-effect hint from a newly recognized
/// Japanese image block. Narration, title, and dialogue remain caller-provided
/// because geometry alone cannot distinguish them safely. Returning `nil` is
/// intentional: an ambiguous block keeps the historical dialogue default.
enum TranslationTextKindClassifier {
    static func inferJapaneseKind(
        text: String,
        boundingBox: NormalizedImageRect
    ) -> TranslationTextKind? {
        guard boundingBox.normalizedToUnit() != nil else { return nil }

        let compact = text.filter { !$0.isWhitespace }
        guard (2...12).contains(compact.count) else { return nil }

        let scalars = Array(compact.unicodeScalars)
        let hasSoundEffectMarker = scalars.contains { scalar in
            switch scalar.value {
            case 0x2025, 0x2026, 0x30FC, 0x301C,
                 0xFF5E, 0x2605, 0x2606, 0x266A:
                true
            default:
                false
            }
        }
        let japaneseLetters = scalars.filter { scalar in
            switch scalar.value {
            case 0x3040...0x30FA, 0x3400...0x4DBF,
                 0x4E00...0x9FFF, 0xF900...0xFAFF,
                 0xFF66...0xFF9D:
                true
            default:
                false
            }
        }
        let hasSmallTsuEnding = japaneseLetters.last.map { scalar in
            switch scalar.value {
            case 0x3063, 0x30C3, 0xFF6F:
                true
            default:
                false
            }
        } ?? false
        guard japaneseLetters.count >= 2
            || (japaneseLetters.count >= 1
                && japaneseLetters.count <= 4
                && (hasSoundEffectMarker || hasSmallTsuEnding)) else {
            return nil
        }

        let katakanaLetters = japaneseLetters.filter { scalar in
            switch scalar.value {
            case 0x30A1...0x30FA, 0xFF66...0xFF9D:
                true
            default:
                false
            }
        }
        let kanaLetters = japaneseLetters.filter { scalar in
            switch scalar.value {
            case 0x3041...0x309F, 0x30A1...0x30FA, 0xFF66...0xFF9D:
                true
            default:
                false
            }
        }
        let katakanaRatio = Double(katakanaLetters.count)
            / Double(japaneseLetters.count)
        let kanaRatio = Double(kanaLetters.count)
            / Double(japaneseLetters.count)
        guard katakanaRatio >= 0.65 || kanaRatio >= 0.65 else { return nil }

        let hasDialogueQuote = scalars.contains { scalar in
            switch scalar.value {
            case 0x300C, 0x300D, 0x300E, 0x300F:
                true
            default:
                false
            }
        }
        guard !hasDialogueQuote else { return nil }

        var katakanaCounts: [UInt32: Int] = [:]
        for scalar in katakanaLetters {
            katakanaCounts[scalar.value, default: 0] += 1
        }
        let hasRepeatedKatakana = katakanaLetters.count >= 3
            && katakanaCounts.values.contains { $0 >= 2 }
        let kanaValues = kanaLetters.map(\.value)
        let hasRepeatedKanaUnit: Bool
        if kanaValues.count >= 4, kanaValues.count.isMultiple(of: 2) {
            let half = kanaValues.count / 2
            hasRepeatedKanaUnit = Array(kanaValues.prefix(half))
                == Array(kanaValues.suffix(half))
        } else {
            hasRepeatedKanaUnit = false
        }
        var longestRepeatedKanaRun = kanaValues.isEmpty ? 0 : 1
        var currentRepeatedKanaRun = longestRepeatedKanaRun
        if kanaValues.count > 1 {
            for index in 1..<kanaValues.count {
                if kanaValues[index] == kanaValues[index - 1] {
                    currentRepeatedKanaRun += 1
                    longestRepeatedKanaRun = max(
                        longestRepeatedKanaRun,
                        currentRepeatedKanaRun
                    )
                } else {
                    currentRepeatedKanaRun = 1
                }
            }
        }
        let hasRepeatedKana = hasRepeatedKanaUnit
            || longestRepeatedKanaRun >= 3
        let hasKatakanaMarkerShape = hasSoundEffectMarker
            && katakanaRatio >= 0.65
        let hasShortMarkerShape = hasSoundEffectMarker
            && japaneseLetters.count <= 2
        guard hasKatakanaMarkerShape
            || hasShortMarkerShape
            || hasRepeatedKatakana
            || hasRepeatedKana
            || hasSmallTsuEnding else {
            return nil
        }
        return .sfx
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

    /// Only a complete, non-empty summary may cross the prompt boundary.
    /// This keeps decoded/transient context fail-closed when a caller hands
    /// us a summary that was not produced from completed blocks.
    var isEligibleForPrompt: Bool {
        guard isReadOnly,
              !containsPendingInputBlocks,
              generatedFromCompletedBlocks,
              !batchID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !items.isEmpty else {
            return false
        }

        let ordinals = items.map(\.ordinal)
        guard Set(ordinals).count == ordinals.count else {
            return false
        }
        for (index, item) in items.enumerated() {
            guard item.ordinal > 0,
                  !item.sourceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !item.targetExcerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            if index > 0, item.ordinal != items[index - 1].ordinal + 1 {
                return false
            }
        }
        return true
    }

    /// A structurally valid summary is still unsafe when it came from a
    /// different translation pair. The request boundary must provide the
    /// current source and target languages before the summary can cross.
    func isEligibleForPrompt(
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage
    ) -> Bool {
        isEligibleForPrompt
            && self.sourceLanguage == sourceLanguage
            && self.targetLanguage == targetLanguage
    }

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

    /// Request-bound language identity. These fields are deliberately
    /// transient and omitted from CodingKeys: context is prompt metadata, not
    /// persisted session state. An unbound context fails closed for summaries.
    private var requestSourceLanguage: SupportedLanguage?
    private var requestTargetLanguage: SupportedLanguage?

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
        self.requestSourceLanguage = nil
        self.requestTargetLanguage = nil
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
        requestSourceLanguage = nil
        requestTargetLanguage = nil
    }

    /// Binds transient context to the exact request that will consume it.
    /// This does not alter any persisted or user-visible state.
    func bound(
        to sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage
    ) -> TranslationPromptContext {
        var copy = self
        copy.requestSourceLanguage = sourceLanguage
        copy.requestTargetLanguage = targetLanguage
        return copy
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
        if let previousBatchSummary,
           previousBatchSummary.isEligibleForPrompt {
            if let requestSourceLanguage,
               let requestTargetLanguage,
               previousBatchSummary.isEligibleForPrompt(
                   sourceLanguage: requestSourceLanguage,
                   targetLanguage: requestTargetLanguage
               ) {
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
        } else {
            summary = nil
        }

        var normalizedContext = TranslationPromptContext(
            confirmedTerms: Array(terms),
            previousBatchSummary: summary,
            textKind: textKind,
            maxOutputCharacters: maxOutputCharacters,
            batchTextKinds: Array(batchTextKinds.prefix(8)),
            batchStartIndex: batchStartIndex.map { max($0, 0) }
        )
        normalizedContext.requestSourceLanguage = requestSourceLanguage
        normalizedContext.requestTargetLanguage = requestTargetLanguage
        return normalizedContext
    }

    /// Returns the style metadata aligned with one item of a tagged batch.
    /// A missing entry deliberately falls back to dialogue so a legacy block
    /// cannot inherit the first block's type merely because the batch contains
    /// mixed text kinds.
    func batchTextKind(
        at offset: Int,
        fallback: TranslationTextKind = .dialogue
    ) -> TranslationTextKind {
        guard batchTextKinds.indices.contains(offset) else { return fallback }
        return batchTextKinds[offset]
    }

    /// Narrows a mixed-batch context before it is consumed by a plain-text
    /// single-block request. Confirmed terms and an eligible previous-batch
    /// summary remain read-only context, while per-item batch style metadata
    /// and the batch ordinal are removed. The existing kind-specific output
    /// limit is surfaced to the model and remains the same QA limit.
    func scopedToSingleBlock(
        textKind: TranslationTextKind,
        sourceCharacterCount: Int
    ) -> TranslationPromptContext {
        var copy = TranslationPromptContext(
            confirmedTerms: confirmedTerms,
            previousBatchSummary: previousBatchSummary,
            textKind: textKind,
            maxOutputCharacters: maxOutputCharacters
                ?? textKind.defaultMaximumOutputCharacters(for: sourceCharacterCount)
        )
        copy.requestSourceLanguage = requestSourceLanguage
        copy.requestTargetLanguage = requestTargetLanguage
        return copy
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
                lines.append("仅对第\(ordinal)块生效的文字类型提示（\(kind.promptLabel)）：\(kind.promptStyleGuidance)")
            }
        } else {
            lines.append("本次文字类型：\(context.textKind.promptLabel)")
            lines.append("本次文字类型提示：\(context.textKind.promptStyleGuidance)")
        }
        let hasSFXBatchKind = context.batchTextKinds.contains(.sfx)
        let sfxOrdinals = context.batchTextKinds.enumerated().compactMap { index, kind -> Int? in
            guard kind == .sfx else { return nil }
            return (context.batchStartIndex ?? 0) + index + 1
        }
        if hasSFXBatchKind {
            let sfxScope = sfxOrdinals
                .map { "第\($0)块" }
                .joined(separator: "、")
            if !sfxScope.isEmpty {
                lines.append("仅对\(sfxScope)生效的拟声词/状态字规则：仅使用简短的中文拟声或动作表达，保留节奏；不要补写主语、解释动作；不要扩写成完整句子。其它编号块仍按各自文字类型翻译。")
            }
        } else if context.batchTextKinds.isEmpty && context.textKind == .sfx {
            lines.append("本次文字块是拟声词/状态字：仅使用简短的中文拟声或动作表达，保留节奏；不要补写主语、解释动作；不要扩写成完整句子。")
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
    var sourceLanguage: SupportedLanguage
    var targetLanguage: SupportedLanguage
    var confirmedTerms: [TranslationTermMemoryEntry]
    var previousBatchSummary: TranslationReadOnlyBatchSummary?
    var minimumTargetLanguageDensity: Double
    var maximumOutputCharacters: Int?

    init(
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage,
        confirmedTerms: [TranslationTermMemoryEntry] = [],
        previousBatchSummary: TranslationReadOnlyBatchSummary? = nil,
        minimumTargetLanguageDensity: Double = 0.35,
        maximumOutputCharacters: Int? = nil
    ) {
        self.sourceLanguage = sourceLanguage
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
            "待翻译内容",
            "需要翻译内容",
            "要翻译的句子",
            "翻译以下文本",
            "翻译以上文本",
            "翻译上述文本",
            "待翻译文字",
            "text to translate",
            "source text to translate",
            "text for translation",
            "the text you want translated",
            "translation input",
            "input text"
        ]
        let startsWithRequestMarker = requestMarkers.contains { marker in
            compact.hasPrefix(marker.filter { !$0.isWhitespace && !$0.isPunctuation })
        }
        let hasExplicitTranslationInput = translationInputMarkers.contains { marker in
            compact.contains(marker.filter { !$0.isWhitespace && !$0.isPunctuation })
        }
        guard compact.count <= 96,
              startsWithRequestMarker,
              hasExplicitTranslationInput else {
            return false
        }
        return true
    }

    /// Japanese and Simplified Chinese can intentionally share an unchanged
    /// Han-only token (for example, a place name such as `東京`). Model-output
    /// cleaners must use the same narrow exception as product QA; otherwise a
    /// valid translation is rejected before the shared QA boundary sees it.
    /// This does not allow kana, Latin text, digits, mixed-language output, or
    /// a source substring with extra content to pass through unchanged.
    static func allowsUnchangedJapaneseHanTranslation(
        source: String,
        output: String,
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage
    ) -> Bool {
        guard sourceLanguage == .japanese,
              targetLanguage == .simplifiedChinese else {
            return false
        }

        let normalizedSource = comparableText(source)
        let normalizedOutput = comparableText(output)
        guard normalizedSource.count > 1,
              normalizedSource == normalizedOutput,
              isSharedHanOnlyJapaneseSource(source) else {
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

    private static func comparableText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .joined()
    }

    private static func isSharedHanOnlyJapaneseSource(_ text: String) -> Bool {
        let visible = text.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
        }
        guard !visible.isEmpty else { return false }
        return visible.allSatisfy { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                true
            default:
                false
            }
        }
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
        if isSourceLeakage(
            source: sourceText,
            output: translatedText,
            normalizedSource: normalizedSource,
            normalizedOutput: normalizedOutput,
            sourceLanguage: configuration.sourceLanguage,
            targetLanguage: configuration.targetLanguage
        ) {
            failures.append("sourceLeakage")
        }

        if numericTokens(in: sourceText) != numericTokens(in: translatedText) {
            failures.append("numberMismatch")
        }

        if let previousBatchSummary = configuration.previousBatchSummary,
           previousBatchSummary.isEligibleForPrompt,
           previousBatchSummary.isEligibleForPrompt(
               sourceLanguage: configuration.sourceLanguage,
               targetLanguage: configuration.targetLanguage
           ) {
            let copiedPreviousBatch = previousBatchSummary.items.contains { item in
                let previousTarget = comparableText(item.targetExcerpt)
                guard previousTarget.count >= 4,
                      normalizedOutput == previousTarget else {
                    return false
                }
                // Repeating the same source block can legitimately produce the
                // same translation. Only treat an exact output echo as context
                // leakage when the current source is different from the prior
                // source excerpt; a longer current translation may also contain
                // a previously translated phrase without being an echo.
                let previousSource = comparableText(item.sourceExcerpt)
                return previousSource != normalizedSource
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

    /// Japanese and Simplified Chinese share a meaningful Han vocabulary.
    /// A pure-kanji Japanese name or place can therefore be a correct Chinese
    /// translation even when its normalized spelling is unchanged. Keep the
    /// leakage gate strict for kana/Latin/digit-bearing Japanese text and for
    /// every other language pair, while avoiding false rejection of shared Han
    /// output.
    private static func isSourceLeakage(
        source: String,
        output: String,
        normalizedSource: String,
        normalizedOutput: String,
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage
    ) -> Bool {
        guard !normalizedSource.isEmpty,
              !isOnlyDigits(normalizedSource),
              normalizedOutput.contains(normalizedSource) else {
            return false
        }

        if sourceLanguage == .japanese,
           targetLanguage == .simplifiedChinese,
           isSharedHanOnlyJapaneseSource(source) {
            // The shared-Han exception is exact-only. A tagged block such as
            // `日本人` must not pass merely because it contains the source
            // `日本`; the model cleaner and QA must make the same decision.
            return !TranslationOutputPolicy.allowsUnchangedJapaneseHanTranslation(
                source: source,
                output: output,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
        }
        guard normalizedSource.count > 1 else {
            return false
        }
        return true
    }

    private static func isSharedHanOnlyJapaneseSource(_ text: String) -> Bool {
        let visible = text.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
        }
        guard !visible.isEmpty else { return false }
        return visible.allSatisfy { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                true
            default:
                false
            }
        }
    }

    private static func numericTokens(in text: String) -> [String] {
        // OCR and a translation model may use fullwidth Japanese digits and
        // separators even when the other side uses ASCII. Canonicalize only
        // the numeric width variants before matching so number preservation
        // stays exact for token order, punctuation, and leading zeroes.
        let canonicalText = canonicalNumericTokenText(text)
        guard let regex = try? NSRegularExpression(pattern: #"[0-9]+(?:[.,:/-][0-9]+)*"#) else { return [] }
        let nsText = canonicalText as NSString
        return regex.matches(in: canonicalText, range: NSRange(location: 0, length: nsText.length))
            .map { nsText.substring(with: $0.range).lowercased() }
    }

    private static func canonicalNumericTokenText(_ text: String) -> String {
        var canonical = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFF10...0xFF19:
                if let mapped = UnicodeScalar(scalar.value - 0xFEE0) {
                    canonical.unicodeScalars.append(mapped)
                } else {
                    canonical.unicodeScalars.append(scalar)
                }
            case 0xFF0C:
                canonical.append(",")
            case 0xFF0E:
                canonical.append(".")
            case 0xFF0F:
                canonical.append("/")
            case 0xFF1A:
                canonical.append(":")
            case 0xFF0D:
                canonical.append("-")
            default:
                canonical.unicodeScalars.append(scalar)
            }
        }
        return canonical
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
