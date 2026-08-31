import Foundation

enum GemmaLocalServiceError: LocalizedError, Sendable {
    case modelNotInstalled(URL)
    case emptyOutput
    case repeatedInput
    case outputNotInTargetLanguage(SupportedLanguage)

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled(let directory):
            "Local GGUF model is not installed. Expected model file under \(directory.path)."
        case .emptyOutput:
            "本地模型没有返回有效译文。"
        case .repeatedInput:
            "本地模型返回了原文，已判定为生成失败。"
        case .outputNotInTargetLanguage(let language):
            "本地模型输出不像\(language.rawValue)，已判定为生成失败。"
        }
    }
}

struct GemmaLocalService: LocalLanguageModeling {
    private static let runtime = LlamaRuntime()

    private static var defaultModelDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models/Gemma-1.5B", isDirectory: true)
    }

    let modelDirectory: URL
    let promptProfile: LocalModelPromptProfile
    let metadata = ModelAdapterMetadata(
        engine: .local,
        displayName: "Local GGUF",
        modelName: "imported model.gguf",
        quantization: "GGUF",
        supportsStreaming: false
    )

    init(
        modelDirectory: URL = GemmaLocalService.defaultModelDirectory,
        promptProfile: LocalModelPromptProfile? = nil
    ) {
        self.modelDirectory = modelDirectory
        let isBundledGemmaDirectory = modelDirectory.standardizedFileURL.path
            == Self.defaultModelDirectory.standardizedFileURL.path
        self.promptProfile = promptProfile
            ?? (isBundledGemmaDirectory ? .gemma : .experimental)
    }

    func prepare() async throws {
        let modelURL = try modelURL()
        try Self.runtime.loadModelIfNeeded(at: modelURL.path)
    }

    func rawTranslationProbe(for request: ModelGenerationRequest) -> RawModelProbeResult {
        let messages = translationMessages(for: request).first ?? []
        let fallbackPrompt = fallbackPrompt(for: messages)
        let limitedMaxTokens = max(1, min(request.sampling.maxTokens, 220))

        do {
            let modelURL = try modelURL()
            try Self.runtime.loadModelIfNeeded(at: modelURL.path)
            let rendered = try Self.runtime.renderPrompt(
                messages: messages,
                fallbackProfile: promptProfile
            )
            let output = try Self.runtime.generateRaw(
                prompt: rendered.prompt,
                maxTokens: limitedMaxTokens,
                decodingProfile: .deterministic
            )
            return RawModelProbeResult(
                prompt: rendered.prompt,
                output: output,
                errorCode: nil,
                decodingMode: ModelDecodingProfile.deterministic.mode,
                decodingSeed: ModelDecodingProfile.deterministic.seed
            )
        } catch {
            return RawModelProbeResult(
                prompt: fallbackPrompt,
                output: "",
                errorCode: "\(type(of: error)): \(error.localizedDescription)",
                decodingMode: ModelDecodingProfile.deterministic.mode,
                decodingSeed: ModelDecodingProfile.deterministic.seed
            )
        }
    }

    func rawProbe(
        prompt: String,
        maxTokens: Int = 160,
        decodingProfile: ModelDecodingProfile = .deterministic
    ) -> RawModelProbeResult {
        let limitedMaxTokens = max(1, min(maxTokens, 220))

        do {
            let modelURL = try modelURL()
            try Self.runtime.loadModelIfNeeded(at: modelURL.path)
            let output = try Self.runtime.generateRaw(
                prompt: prompt,
                maxTokens: limitedMaxTokens,
                decodingProfile: decodingProfile
            )
            return RawModelProbeResult(
                prompt: prompt,
                output: output,
                errorCode: nil,
                decodingMode: decodingProfile.mode,
                decodingSeed: decodingProfile.seed
            )
        } catch {
            return RawModelProbeResult(
                prompt: prompt,
                output: "",
                errorCode: "\(type(of: error)): \(error.localizedDescription)",
                decodingMode: decodingProfile.mode,
                decodingSeed: decodingProfile.seed
            )
        }
    }

    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResult {
        let start = Date.now
        let modelURL = try modelURL()
        try Self.runtime.loadModelIfNeeded(at: modelURL.path)

        switch request.task {
        case .translation:
            let cleanedOutput = try generateTranslation(for: request)
            return ModelGenerationResult(
                text: cleanedOutput,
                summary: nil,
                engineName: metadata.displayName,
                tokenCount: estimateTokenCount(cleanedOutput),
                durationMilliseconds: elapsedMilliseconds(from: start)
            )

        case .summary:
            let output = try Self.runtime.generate(
                messages: summaryMessages(for: request),
                fallbackProfile: promptProfile,
                maxTokens: min(request.sampling.maxTokens, 220),
                decodingProfile: .sampled
            )
            let summary = AISummary(
                bullets: output
                    .split(separator: "\n")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .prefix(3)
                    .map { $0 },
                actions: ["继续用更强的 GGUF 模型验证翻译质量。"],
                title: "Gemma 本地总结"
            )
            return ModelGenerationResult(
                text: output,
                summary: summary,
                engineName: metadata.displayName,
                tokenCount: estimateTokenCount(output),
                durationMilliseconds: elapsedMilliseconds(from: start)
            )
        }
    }

    private func generateTranslation(for request: ModelGenerationRequest) throws -> String {
        if request.translationProfile == .mangaBlocks {
            return try generateMangaBlockTranslation(for: request)
        }

        var lastError: Error?
        for (index, messages) in translationMessages(for: request).enumerated() {
            let promptForLog = promptForLogging(for: messages)
            do {
                Self.writeTranslationProbeLog(
                    "local-attempt-start index=\(index + 1) " +
                    "source=\(request.sourceLanguage.rawValue) target=\(request.targetLanguage.rawValue) " +
                    "input=\(Self.probeField(request.inputText)) prompt=\(Self.probeField(promptForLog))"
                )
                let output = try Self.runtime.generate(
                    messages: messages,
                    fallbackProfile: promptProfile,
                    maxTokens: min(request.sampling.maxTokens, 160),
                    decodingProfile: .sampled
                )
                Self.writeTranslationProbeLog(
                    "local-attempt-raw index=\(index + 1) output=\(Self.probeField(output))"
                )
                let cleanedOutput = try cleanTranslationOutput(
                    output,
                    input: request.inputText,
                    sourceLanguage: request.sourceLanguage,
                    targetLanguage: request.targetLanguage
                )
                Self.writeTranslationProbeLog(
                    "local-attempt-clean index=\(index + 1) output=\(Self.probeField(cleanedOutput))"
                )
                return cleanedOutput
            } catch {
                Self.writeTranslationProbeLog(
                    "local-attempt-error index=\(index + 1) error=\(Self.probeField(error.localizedDescription))"
                )
                lastError = error
            }
        }

        throw lastError ?? GemmaLocalServiceError.emptyOutput
    }

    private func generateMangaBlockTranslation(for request: ModelGenerationRequest) throws -> String {
        var lastError: Error?
        for (index, messages) in translationMessages(for: request).enumerated() {
            let promptForLog = promptForLogging(for: messages)
            do {
                Self.writeTranslationProbeLog(
                    "manga-batch-attempt-start index=\(index + 1) " +
                    "source=\(request.sourceLanguage.rawValue) target=\(request.targetLanguage.rawValue) " +
                    "input=\(Self.probeField(request.inputText)) prompt=\(Self.probeField(promptForLog))"
                )
                let output = try Self.runtime.generate(
                    messages: messages,
                    fallbackProfile: promptProfile,
                    maxTokens: min(max(request.sampling.maxTokens, 192), 768),
                    decodingProfile: .sampled
                )
                Self.writeTranslationProbeLog(
                    "manga-batch-attempt-raw index=\(index + 1) output=\(Self.probeField(output))"
                )
                let cleanedOutput = try cleanMangaBlockOutput(
                    output,
                    input: request.inputText,
                    sourceLanguage: request.sourceLanguage,
                    targetLanguage: request.targetLanguage
                )
                Self.writeTranslationProbeLog(
                    "manga-batch-attempt-clean index=\(index + 1) output=\(Self.probeField(cleanedOutput))"
                )
                return cleanedOutput
            } catch {
                Self.writeTranslationProbeLog(
                    "manga-batch-attempt-error index=\(index + 1) error=\(Self.probeField(error.localizedDescription))"
                )
                lastError = error
            }
        }

        throw lastError ?? GemmaLocalServiceError.emptyOutput
    }

    private func modelURL() throws -> URL {
        let marker = modelDirectory.appendingPathComponent("model.gguf")
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw GemmaLocalServiceError.modelNotInstalled(modelDirectory)
        }
        return marker
    }

    private func translationPrompts(for request: ModelGenerationRequest) -> [String] {
        translationMessages(for: request).map { messages in
            let body = messages.first?.content ?? ""
            return """
            <start_of_turn>user
            \(body)
            <end_of_turn>
            <start_of_turn>model
            """
        }
    }

    private func translationMessages(for request: ModelGenerationRequest) -> [[LocalModelChatMessage]] {
        translationPromptBodies(for: request).map { body in
            [LocalModelChatMessage(role: .user, content: body)]
        }
    }

    private func fallbackPrompt(for messages: [LocalModelChatMessage]) -> String {
        (try? promptProfile.fallbackPrompt(for: messages)) ?? ""
    }

    private func promptForLogging(for messages: [LocalModelChatMessage]) -> String {
        if let rendered = try? Self.runtime.renderPrompt(
            messages: messages,
            fallbackProfile: promptProfile
        ) {
            return rendered.prompt
        }
        return fallbackPrompt(for: messages)
    }

    private func translationPromptBodies(for request: ModelGenerationRequest) -> [String] {
        let instruction = request.prompt.instruction(
            source: request.sourceLanguage,
            target: request.targetLanguage
        )
        let contextSection = request.translationContext.promptSection()
        let contextualInstruction = contextSection.isEmpty ? "" : "\n\n\(contextSection)"

        if request.translationProfile == .mangaBlocks {
            let mangaInstruction = """
            你是专业的漫画翻译器。源语言是\(request.sourceLanguage.rawValue)，目标语言是\(request.targetLanguage.rawValue)。
            输入由带编号的文字块组成，例如 [1]、[2]。只翻译每个编号后面的文字。
            必须原样保留每个 [N] 标签，并按输入顺序逐个输出；不要合并、拆分、遗漏或重排文字块。
            保留角色语气、情绪、关系、强调和拟声词；对拟声词/状态字块使用简短的中文拟声或动作表达，不补写主语或解释动作；译文自然、简洁、适合漫画气泡。
            不要输出解释、注释、罗马音或额外标题。每个标签单独一行，格式为 [N] 译文。
            用户补充要求：\(instruction)\(contextualInstruction)
            """
            return [
                """
                \(mangaInstruction)
                \(request.inputText)
                """,
                """
                漫画编号块翻译。保留所有 [N] 标签及顺序，只输出每个标签对应的\(request.targetLanguage.rawValue)译文，不合并、不拆分、不解释。上下文仅供术语和语气参考，不得生成额外标签：\(contextualInstruction)
                \(request.inputText)
                """
            ]
        }

        if request.sourceLanguage == .englishUS, request.targetLanguage == .simplifiedChinese {
            return [
                """
                \(instruction)\(contextualInstruction)
                \(request.inputText)
                """,
                """
                English -> 简体中文。只输出中文译文。上下文仅供一致性参考：\(contextualInstruction)
                \(request.inputText)
                """,
                """
                请把下面英文翻译成简体中文，只输出中文译文。上下文仅供一致性参考：\(contextualInstruction)
                \(request.inputText)
                """
            ]
        }

        // Japanese image fallback and re-recognition translations use the
        // plain-text standard profile so their block-scoped QA remains
        // addressable. Make that path explicit about the language pair for a
        // small local model instead of relying on a generic prompt template.
        let japaneseLanguagePairInstruction: String?
        switch (request.sourceLanguage, request.targetLanguage) {
        case (.japanese, .simplifiedChinese):
            japaneseLanguagePairInstruction = """
            源语言是日语，目标语言是简体中文。将输入的日语翻译成自然、简洁、忠实的简体中文。
            保留人名、称呼、数字、专有名词、语气、强调和标点；拟声词或状态词使用简短自然的中文表达。
            只输出译文，不输出日语原文、解释、注释、罗马音或提示词。
            """
        case (.japanese, .englishUS):
            japaneseLanguagePairInstruction = """
            The source language is Japanese and the target language is English. Translate the input into natural, concise, faithful English.
            Preserve names, honorifics, numbers, proper nouns, tone, emphasis, and punctuation; render sound effects or state words briefly and naturally.
            Output only the translation, without the Japanese source, explanations, notes, romanization, or prompt text.
            """
        default:
            japaneseLanguagePairInstruction = nil
        }

        if let japaneseLanguagePairInstruction {
            return [
                """
                \(japaneseLanguagePairInstruction)
                用户补充要求：\(instruction)\(contextualInstruction)
                \(request.inputText)
                """,
                """
                \(japaneseLanguagePairInstruction)
                上下文仅供术语和语气一致性参考，不得输出原文、解释或额外内容：\(contextualInstruction)
                \(request.inputText)
                """
            ]
        }

        return [
            """
            \(instruction)\(contextualInstruction)
            \(request.inputText)
            """,
            """
            翻译成\(request.targetLanguage.rawValue)，不要输出原文，不要解释。上下文仅供一致性参考：\(contextualInstruction)
            \(request.inputText)
            """
        ]
    }

    private func cleanMangaBlockOutput(
        _ output: String,
        input: String,
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage
    ) throws -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["<end_of_turn>", "<start_of_turn>"] {
            if let range = text.range(of: marker) {
                text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        text = text
            .replacingOccurrences(of: "```text", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let expectedIDs = Self.mangaBlockIDs(in: input)
        let inputParts = Self.mangaBlockParts(in: input)
        let outputParts = Self.mangaBlockParts(in: text)
        let expectedPartsByID = Dictionary(
            uniqueKeysWithValues: inputParts.map { ($0.id, $0.value) }
        )
        let recognizedOutputParts = outputParts.filter {
            expectedPartsByID[$0.id] != nil
        }
        guard !expectedIDs.isEmpty,
              matchesFirstTagAtStart(in: text),
              !recognizedOutputParts.isEmpty,
              !text.isEmpty else {
            throw GemmaLocalServiceError.emptyOutput
        }

        // Match Koharu's tagged-block parser: ordering and completeness are
        // recovered by the caller, so a small local model can return a subset
        // or reorder blocks without discarding the valid translations.
        guard recognizedOutputParts.allSatisfy({ translated in
            let sourceText = expectedPartsByID[translated.id]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let translatedText = translated.value
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let allowsUnchangedSharedHan = TranslationOutputPolicy
                .allowsUnchangedJapaneseHanTranslation(
                    source: sourceText,
                    output: translatedText,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage
                )
            return !translatedText.isEmpty
                && (allowsUnchangedSharedHan
                    || sourceText.localizedCaseInsensitiveCompare(translatedText) != .orderedSame)
        }) else {
            throw GemmaLocalServiceError.repeatedInput
        }
        return text
    }

    private func matchesFirstTagAtStart(in text: String) -> Bool {
        text.first == "["
    }

    private struct MangaBlockPart {
        let id: Int
        let value: String
    }

    private static func mangaBlockIDs(in text: String) -> [Int] {
        mangaBlockParts(in: text).map(\.id)
    }

    private static func mangaBlockParts(in text: String) -> [MangaBlockPart] {
        let pattern = #"(?m)^\s*\[(\d+)\]\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: fullRange)
        return matches.enumerated().compactMap { index, match in
            guard let idRange = Range(match.range(at: 1), in: text),
                  let id = Int(text[idRange]) else { return nil }
            let valueStart = match.range.location + match.range.length
            let valueEnd = index + 1 < matches.count
                ? matches[index + 1].range.location
                : nsText.length
            guard valueEnd >= valueStart else { return nil }
            let value = nsText.substring(with: NSRange(
                location: valueStart,
                length: valueEnd - valueStart
            ))
            return MangaBlockPart(id: id, value: value)
        }
    }

    private func summaryPrompt(for request: ModelGenerationRequest) -> String {
        let body = summaryMessageContent(for: request)
        return """
        <start_of_turn>user
        \(body)
        <end_of_turn>
        <start_of_turn>model
        """
    }

    private func summaryMessages(for request: ModelGenerationRequest) -> [LocalModelChatMessage] {
        [LocalModelChatMessage(role: .user, content: summaryMessageContent(for: request))]
    }

    private func summaryMessageContent(for request: ModelGenerationRequest) -> String {
        let context = request.transcriptContext
            .prefix(8)
            .map { "\($0.speaker): \($0.translation)" }
            .joined(separator: "\n")

        return """
        Summarize the following transcript in \(request.targetLanguage.rawValue).
        Return three short bullet points only.

        \(context.isEmpty ? request.inputText : context)
        """
    }

    private func estimateTokenCount(_ text: String) -> Int {
        max(1, text.count / 2)
    }

    private func cleanTranslationOutput(
        _ output: String,
        input: String,
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage
    ) throws -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        // Runtime turn markers are unambiguous control tokens and may appear
        // after a valid translation. Natural-language prompt markers are only
        // safe to act on at an independent line start; otherwise a legitimate
        // English phrase inside translated prose can be mistaken for an
        // echoed instruction. A leading prompt line is removable metadata,
        // while a prompt after real content remains a hard suffix boundary.
        let terminalControlMarkers = [
            "<end_of_turn>",
            "<start_of_turn>"
        ]
        let lineStartPromptMarkers = [
            "You are a translation engine.",
            "Hard rules:",
            "Translate the following text",
            "Translate from",
            "User instruction:",
            "Output only"
        ]

        for marker in terminalControlMarkers {
            if let range = text.range(of: marker) {
                text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        func lineStartPromptMarkerMatch(
            in value: String,
            marker: String
        ) -> (
            lineStart: String.Index,
            markerRange: Range<String.Index>,
            lineEnd: String.Index,
            marker: String
        )? {
            var searchStart = value.startIndex
            while searchStart < value.endIndex,
                  let range = value.range(
                      of: marker,
                      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      range: searchStart..<value.endIndex
                  ) {
                let lineStart = value[..<range.lowerBound]
                    .lastIndex(of: "\n")
                    .map { value.index(after: $0) }
                    ?? value.startIndex
                let beforeMarker = String(value[lineStart..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if beforeMarker.isEmpty {
                    let lineEnd = value[range.upperBound...].firstIndex(of: "\n")
                        ?? value.endIndex
                    return (
                        lineStart: lineStart,
                        markerRange: range,
                        lineEnd: lineEnd,
                        marker: marker
                    )
                }
                searchStart = range.upperBound
            }
            return nil
        }

        func firstLineStartPromptMarker(
            in value: String
        ) -> (
            lineStart: String.Index,
            markerRange: Range<String.Index>,
            lineEnd: String.Index,
            marker: String
        )? {
            var firstMatch: (
                lineStart: String.Index,
                markerRange: Range<String.Index>,
                lineEnd: String.Index,
                marker: String
            )?
            for marker in lineStartPromptMarkers {
                guard let match = lineStartPromptMarkerMatch(
                    in: value,
                    marker: marker
                ) else {
                    continue
                }
                guard let current = firstMatch else {
                    firstMatch = match
                    continue
                }
                if match.lineStart < current.lineStart
                    || (match.lineStart == current.lineStart
                        && match.markerRange.lowerBound < current.markerRange.lowerBound) {
                    firstMatch = match
                }
            }
            return firstMatch
        }

        func leadingPromptPayload(
            in value: String,
            match: (
                lineStart: String.Index,
                markerRange: Range<String.Index>,
                lineEnd: String.Index,
                marker: String
            )
        ) -> String? {
            // Only "Output only:" has an unambiguous inline translation
            // payload. Other prompt markers may be followed by source text or
            // instruction details, so their whole leading line is removed.
            guard match.marker == "Output only" else { return nil }
            let suffix = String(value[match.markerRange.upperBound..<match.lineEnd])
            let whitespace = CharacterSet.whitespacesAndNewlines
            let punctuation = CharacterSet.punctuationCharacters
            var cursor = suffix.startIndex
            var sawPunctuation = false
            while cursor < suffix.endIndex {
                let character = suffix[cursor]
                let scalars = character.unicodeScalars
                guard scalars.allSatisfy({
                    whitespace.contains($0) || punctuation.contains($0)
                }) else {
                    break
                }
                sawPunctuation = sawPunctuation
                    || scalars.contains { punctuation.contains($0) }
                cursor = suffix.index(after: cursor)
            }
            guard sawPunctuation, cursor < suffix.endIndex else { return nil }
            let payload = String(suffix[cursor...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return payload.isEmpty ? nil : payload
        }

        func removeLeadingPromptLine(
            from value: String,
            match: (
                lineStart: String.Index,
                markerRange: Range<String.Index>,
                lineEnd: String.Index,
                marker: String
            )
        ) -> String {
            let suffixStart = match.lineEnd < value.endIndex
                ? value.index(after: match.lineEnd)
                : value.endIndex
            let suffix = String(value[suffixStart..<value.endIndex])
            let payload = leadingPromptPayload(in: value, match: match)
            guard let payload else { return suffix }
            return suffix.isEmpty ? payload : "\(payload)\n\(suffix)"
        }

        // Prompt echo before the first real translation line is recoverable:
        // remove only the leading metadata line and keep following output.
        // Once real content precedes a prompt line, retain the v3.370 cut
        // boundary so echoed instructions cannot leak into the translation.
        while let match = firstLineStartPromptMarker(in: text) {
            let prefix = String(text[..<match.lineStart])
            let hasPriorContent = !prefix
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                .isEmpty
            if hasPriorContent {
                text = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
            text = removeLeadingPromptLine(from: text, match: match)
        }

        var lines = text
            .split(separator: "\n")
            .map { stripFormatting(from: String($0)) }
            .filter { !$0.isEmpty }

        let lineLeakMarkers = [
            "translation engine",
            "do not summarize",
            "do not add explanations",
            "English ->",
            "只输出中文译文",
            "只输出译文",
            "不要输出英文原文",
            "简体中文翻译",
            "预设提示词",
            "输出风格"
        ]
        let translationLabelMarkers = [
            "以下是翻译",
            "翻译如下",
            "翻译是：",
            "这是翻译"
        ]

        // A prompt marker embedded in translated prose is content; only a
        // marker at the line start is unambiguous metadata.
        func isPromptMarkerAtLineStart(_ line: String, marker: String) -> Bool {
            guard let range = line.range(
                of: marker,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            ) else {
                return false
            }
            let before = String(line[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return before.isEmpty
        }

        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let bulletBody = trimmed.hasPrefix("- ")
                ? String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                : trimmed
            let isMetadataBullet = trimmed.hasPrefix("- ")
                && (bulletBody.isEmpty
                    || lineLeakMarkers.contains { marker in
                        isPromptMarkerAtLineStart(bulletBody, marker: marker)
                    })
            let isTranslationLabelOnly = translationLabelMarkers.contains { marker in
                guard let range = trimmed.range(
                    of: marker,
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
                ) else {
                    return false
                }
                let before = String(trimmed[..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                let after = String(trimmed[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                return before.isEmpty && after.isEmpty
            }
            return isMetadataBullet
                || (trimmed.hasPrefix("|") && trimmed.hasSuffix("|"))
                || lineLeakMarkers.contains { marker in
                    isPromptMarkerAtLineStart(trimmed, marker: marker)
                }
                || isTranslationLabelOnly
        }

        guard !lines.isEmpty else {
            throw GemmaLocalServiceError.emptyOutput
        }
        let candidate = lines.joined(separator: "\n")
        return try validateTranslationOutput(
            candidate,
            input: input,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
    }

    private func stripFormatting(from output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrappers = ["**", "__", "`", "\"", "'", "“", "”", "‘", "’"]

        var didStripWrapper = true
        while didStripWrapper {
            didStripWrapper = false
            for wrapper in wrappers where text.hasPrefix(wrapper) && text.hasSuffix(wrapper) && text.count > wrapper.count * 2 {
                text = String(text.dropFirst(wrapper.count).dropLast(wrapper.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                didStripWrapper = true
            }
        }

        return text
    }

    private func validateTranslationOutput(
        _ output: String,
        input: String,
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage
    ) throws -> String {
        let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let normalizedOutput = output.trimmingCharacters(in: trimSet)
        let normalizedInput = input.trimmingCharacters(in: trimSet)
        guard !normalizedOutput.isEmpty else {
            throw GemmaLocalServiceError.emptyOutput
        }
        let allowsUnchangedSharedHan = TranslationOutputPolicy
            .allowsUnchangedJapaneseHanTranslation(
                source: input,
                output: output,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
        guard allowsUnchangedSharedHan
            || normalizedOutput.localizedCaseInsensitiveCompare(normalizedInput) != ComparisonResult.orderedSame else {
            throw GemmaLocalServiceError.repeatedInput
        }
        guard allowsUnchangedSharedHan
            || (!normalizedOutput.localizedCaseInsensitiveContains(normalizedInput)
                && !normalizedInput.localizedCaseInsensitiveContains(normalizedOutput)) else {
            throw GemmaLocalServiceError.repeatedInput
        }
        guard !TranslationOutputPolicy.isPlaceholderResponse(output) else {
            throw GemmaLocalServiceError.emptyOutput
        }
        guard looksLikeTargetLanguage(output, targetLanguage: targetLanguage) else {
            throw GemmaLocalServiceError.outputNotInTargetLanguage(targetLanguage)
        }
        return output
    }

    private func looksLikeTargetLanguage(_ output: String, targetLanguage: SupportedLanguage) -> Bool {
        switch targetLanguage {
        case .simplifiedChinese:
            output.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(Int(scalar.value))
            }
        case .englishUS:
            output.unicodeScalars.contains { scalar in
                (0x41...0x5A).contains(Int(scalar.value)) || (0x61...0x7A).contains(Int(scalar.value))
            }
        default:
            true
        }
    }

    private func elapsedMilliseconds(from start: Date) -> Int {
        Int(Date.now.timeIntervalSince(start) * 1_000)
    }

#if DEBUG
    private static func writeTranslationProbeLog(_ message: String) {
        guard ProcessInfo.processInfo.environment["AITRANS_RUN_LLM_SMOKE"] == "1" else { return }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("AITRANS", isDirectory: true)
        let url = directory.appendingPathComponent("llm-smoke-result.log")
        let line = "\(Date.now.ISO8601Format()) \(message)\n"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url, options: .atomic)
        }
    }

    private static func probeField(_ text: String) -> String {
        text
            .replacing("\n", with: "\\n")
            .replacing("\t", with: "\\t")
            .replacing("|", with: "\\|")
    }
#else
    private static func writeTranslationProbeLog(_ message: String) {}
    private static func probeField(_ text: String) -> String { text }
#endif
}
