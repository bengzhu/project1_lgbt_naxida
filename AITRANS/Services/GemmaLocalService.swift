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

        // The direct completion path is deliberately last. The real test2
        // trace showed that an untemplated completion can emit language labels
        // and a long explanation that the ordinary cleaner cannot distinguish
        // from a translation. Give the instruction-tuned candidates every
        // chance first, then keep this as a narrowly guarded final fallback.
        if let rawPrompt = japaneseRawCompletionPrompt(for: request) {
            do {
                Self.writeTranslationProbeLog(
                    "local-raw-attempt-start " +
                    "source=\(request.sourceLanguage.rawValue) target=\(request.targetLanguage.rawValue) " +
                    "input=\(Self.probeField(request.inputText)) prompt=\(Self.probeField(rawPrompt))"
                )
                let output = try Self.runtime.generateRaw(
                    prompt: rawPrompt,
                    maxTokens: max(1, min(request.sampling.maxTokens, 160)),
                    decodingProfile: .sampled
                )
                Self.writeTranslationProbeLog(
                    "local-raw-attempt-raw output=\(Self.probeField(output))"
                )
                let cleanedOutput = try cleanJapaneseRawCompletionOutput(
                    output,
                    input: request.inputText,
                    sourceLanguage: request.sourceLanguage,
                    targetLanguage: request.targetLanguage
                )
                Self.writeTranslationProbeLog(
                    "local-raw-attempt-clean output=\(Self.probeField(cleanedOutput))"
                )
                return cleanedOutput
            } catch {
                Self.writeTranslationProbeLog(
                    "local-raw-attempt-error error=\(Self.probeField(error.localizedDescription))"
                )
                lastError = error
            }
        }

        throw lastError ?? GemmaLocalServiceError.emptyOutput
    }

    private func cleanJapaneseRawCompletionOutput(
        _ output: String,
        input: String,
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage
    ) throws -> String {
        let raw = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.contains("\n"), !raw.contains("\r") else {
            throw GemmaLocalServiceError.emptyOutput
        }
        let metadataMarkers = [
            "日本語：",
            "日语：",
            "Japanese:",
            "简体中文：",
            "繁体中文：",
            "Simplified Chinese:",
            "Traditional Chinese:",
            "English:",
            "韩语：",
            "Korean:"
        ]
        guard !metadataMarkers.contains(where: { marker in
            raw.localizedCaseInsensitiveContains(marker)
        }) else {
            throw GemmaLocalServiceError.emptyOutput
        }
        return try cleanTranslationOutput(
            raw,
            input: input,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
    }

    private func japaneseRawCompletionPrompt(for request: ModelGenerationRequest) -> String? {
        switch (request.sourceLanguage, request.targetLanguage) {
        case (.japanese, .simplifiedChinese):
            return "日语：\(request.inputText)\n简体中文："
        case (.japanese, .englishUS):
            return "Japanese: \(request.inputText)\nEnglish:"
        default:
            return nil
        }
    }

    private func generateMangaBlockTranslation(for request: ModelGenerationRequest) throws -> String {
        var lastError: Error?
        // LlamaRuntime uses a 1,024-token context. The manga prompt carries
        // up to eight tagged blocks, so keep generation bounded after the
        // compact context rendering leaves room for the actual translations.
        let generationMaxTokens = min(max(request.sampling.maxTokens, 192), 256)
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
                    maxTokens: generationMaxTokens,
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
        let defaultTranslationInstruction = PromptLanguageDirection
            .englishToChinese
            .fallbackInstruction
        let userInstructionSection = instruction == defaultTranslationInstruction
            ? ""
            : "\n用户指定要求：\(instruction)"
        let fullContextSection = request.translationContext.promptSection()
        let compactContextSection = request.translationContext.compactPromptSection()
        let contextSection: String
        if request.translationProfile == .mangaBlocks {
            contextSection = compactContextSection.isEmpty
                ? fullContextSection
                : compactContextSection
        } else if request.sourceLanguage == .japanese,
                  !compactContextSection.isEmpty {
            contextSection = compactContextSection
        } else {
            contextSection = fullContextSection
        }
        let contextualInstruction = contextSection.isEmpty ? "" : "\n\n\(contextSection)"

        if request.translationProfile == .mangaBlocks {
            let mangaMinimalInstruction: String
            if request.sourceLanguage == .japanese,
               request.targetLanguage == .simplifiedChinese {
                mangaMinimalInstruction = "Translate Japanese to Simplified Chinese."
            } else {
                mangaMinimalInstruction = "Translate \(request.sourceLanguage.rawValue) to \(request.targetLanguage.rawValue)."
            }
            let mangaChineseFallbackInstruction: String
            if request.sourceLanguage == .japanese,
               request.targetLanguage == .simplifiedChinese {
                mangaChineseFallbackInstruction = "把以下日语翻译成简体中文。"
            } else {
                mangaChineseFallbackInstruction = "Translate \(request.sourceLanguage.rawValue) to \(request.targetLanguage.rawValue)."
            }
            let mangaBareFallbackInstruction: String
            if request.sourceLanguage == .japanese,
               request.targetLanguage == .simplifiedChinese {
                mangaBareFallbackInstruction = "把以下翻译成中文："
            } else {
                mangaBareFallbackInstruction = "Translate the following into \(request.targetLanguage.rawValue):"
            }
            let mangaInstruction = """
            Translate each \(request.sourceLanguage.rawValue) text block into \(request.targetLanguage.rawValue).
            请逐个翻译下面的\(request.sourceLanguage.rawValue)文字块。
            Keep every [N] tag and the input order. Output only one line per tag: [N] translation.
            保留每个[N]标签和顺序，只输出标签及译文；不要解释、注释或罗马音。
            拟声词/状态字块用简短中文表达，不补写主语或解释动作。
            \(userInstructionSection)\(contextualInstruction)
            """
            return [
                """
                \(mangaInstruction)
                Text to translate:
                \(request.inputText)
                """,
                """
                漫画文字块：\(request.sourceLanguage.rawValue)→\(request.targetLanguage.rawValue)。
                只输出每个[N]标签对应的译文，保留标签和顺序，不解释：\(contextualInstruction)
                待翻译文字：
                \(request.inputText)
                """,
                """
                \(mangaMinimalInstruction) Keep each [N] tag and output only one [N] translation per line.
                \(request.inputText)
                """,
                """
                \(mangaChineseFallbackInstruction) 保留每个[N]标签和顺序，只输出每个标签一行译文：
                \(request.inputText)
                """,
                """
                \(mangaBareFallbackInstruction)
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
            Translate the following Japanese into Simplified Chinese.
            请把下面的日语翻译成简体中文，只输出简体中文译文，不要解释。
            保留语气、数字、专有名词和标点；拟声词或状态词使用简短自然的中文表达。
            """
        case (.japanese, .englishUS):
            japaneseLanguagePairInstruction = """
            The source language is Japanese and the target language is English. Translate the input into natural, concise, faithful English.
            日本語を英語に翻訳し、訳文だけを出力してください。
            Preserve names, honorifics, numbers, proper nouns, tone, emphasis, and punctuation; render sound effects or state words briefly and naturally.
            """
        default:
            japaneseLanguagePairInstruction = nil
        }

        let japaneseMinimalInstruction: String
        switch (request.sourceLanguage, request.targetLanguage) {
        case (.japanese, .simplifiedChinese):
            japaneseMinimalInstruction = "Translate Japanese to Simplified Chinese. Output only the translation."
        case (.japanese, .englishUS):
            japaneseMinimalInstruction = "Translate Japanese to English. Output only the translation."
        default:
            japaneseMinimalInstruction = "Translate the input into \(request.targetLanguage.rawValue). Output only the translation."
        }

        if let japaneseLanguagePairInstruction {
            let japaneseFewShotFallbackInstruction: String
            switch (request.sourceLanguage, request.targetLanguage) {
            case (.japanese, .simplifiedChinese):
                japaneseFewShotFallbackInstruction = """
                Translate Japanese to Simplified Chinese. Use the examples only as translation hints.
                Output only the final Chinese translation; do not output labels, explanations, or the examples.
                Example Japanese: ありがとう
                Example Simplified Chinese: 谢谢
                Example Japanese: つかれた
                Example Simplified Chinese: 累了
                Final Japanese:
                """
            case (.japanese, .englishUS):
                japaneseFewShotFallbackInstruction = """
                Translate Japanese to English. Use the examples only as translation hints.
                Output only the final English translation; do not output labels, explanations, or the examples.
                Example Japanese: ありがとう
                Example English: Thank you.
                Example Japanese: つかれた
                Example English: Tired.
                Final Japanese:
                """
            default:
                japaneseFewShotFallbackInstruction = ""
            }
            let japaneseChineseFallbackInstruction: String
            switch (request.sourceLanguage, request.targetLanguage) {
            case (.japanese, .simplifiedChinese):
                japaneseChineseFallbackInstruction = "把以下日语翻译成简体中文："
            case (.japanese, .englishUS):
                japaneseChineseFallbackInstruction = "把以下日语翻译成英文："
            default:
                japaneseChineseFallbackInstruction = "把以下内容翻译成\(request.targetLanguage.rawValue)："
            }
            let japaneseBareFallbackInstruction: String
            switch (request.sourceLanguage, request.targetLanguage) {
            case (.japanese, .simplifiedChinese):
                japaneseBareFallbackInstruction = "把以下翻译成中文："
            case (.japanese, .englishUS):
                japaneseBareFallbackInstruction = "Translate the following into English:"
            default:
                japaneseBareFallbackInstruction = "Translate the following into \(request.targetLanguage.rawValue):"
            }

            return [
                """
                \(japaneseFewShotFallbackInstruction)
                \(request.inputText)
                Answer:
                """,
                """
                \(japaneseLanguagePairInstruction)
                \(userInstructionSection)\(contextualInstruction)
                Text to translate:
                \(request.inputText)
                """,
                """
                \(japaneseLanguagePairInstruction)
                只输出译文，不输出原文或解释。\(userInstructionSection)\(contextualInstruction)
                待翻译文本：
                \(request.inputText)
                """,
                """
                \(japaneseMinimalInstruction)
                \(request.inputText)
                """,
                """
                \(japaneseChineseFallbackInstruction)
                \(request.inputText)
                """,
                """
                \(japaneseBareFallbackInstruction)
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
        // A small local model may prepend a known, standalone translation
        // label before the first numbered block. Recover that harmless
        // preamble without accepting arbitrary prose before [N] tags.
        text = stripLeadingMangaBatchPreamble(from: text)

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

    private func stripLeadingMangaBatchPreamble(from value: String) -> String {
        var lines = value.components(separatedBy: "\n")
        var cursor = 0
        var removedPreamble = false

        while cursor < lines.count {
            let trimmed = lines[cursor]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                cursor += 1
                continue
            }
            if trimmed.hasPrefix("[") {
                break
            }
            if let inlineTaggedLine = inlineMangaBatchTaggedLine(from: trimmed) {
                // Some small models put a harmless known label and the first
                // tag on one line. Remove only that exact prefix and keep the
                // tag plus its payload addressable by the existing parser.
                lines[cursor] = inlineTaggedLine
                removedPreamble = true
                break
            }
            guard isKnownMangaBatchPreambleLine(trimmed) else {
                // Do not partially sanitize an unknown prefix. The existing
                // first-tag guard must still reject arbitrary model prose.
                return value
            }
            removedPreamble = true
            cursor += 1
        }

        guard removedPreamble else { return value }
        return lines.dropFirst(cursor)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inlineMangaBatchTaggedLine(from line: String) -> String? {
        guard let bracket = line.firstIndex(of: "[") else { return nil }
        let prefix = String(line[..<bracket])
        guard isKnownMangaBatchPreambleLine(prefix) else { return nil }

        let taggedPayload = String(line[bracket...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^\[\d+\]"#),
              regex.firstMatch(
                  in: taggedPayload,
                  range: NSRange(
                      location: 0,
                      length: (taggedPayload as NSString).length
                  )
              ) != nil else {
            return nil
        }
        return taggedPayload
    }

    private func isKnownMangaBatchPreambleLine(_ line: String) -> Bool {
        let edgeTrimmed = line.trimmingCharacters(
            in: .whitespacesAndNewlines.union(.punctuationCharacters)
        )
        let knownPreambles = [
            "以下是翻译",
            "以下为翻译",
            "翻译如下",
            "译文如下",
            "翻译结果如下",
            "Translation",
            "Translations",
            "Here is the translation",
            "Here are the translations",
            "You are a translation engine",
            "Hard rules",
            "Translate the following text",
            "Translate from",
            "User instruction",
            "Output only"
        ]
        return knownPreambles.contains { known in
            edgeTrimmed.compare(
                known,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            ) == .orderedSame
        }
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

        // A plain-text translation may start with a short label and its
        // payload on the same line (for example `译文：你好` or
        // `Translation: hello`). Recover only a finite label followed by an
        // actual delimiter and payload. Embedded prose, label-like words
        // without a delimiter, and the existing tagged-batch path remain
        // untouched so a legitimate sentence cannot be silently shortened.
        text = stripLeadingTranslationLabel(from: text)

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
        let contentSensitiveLineLeakMarkers = [
            "translation engine",
            "输出风格"
        ]
        let translationLabelMarkers = [
            "以下是翻译",
            "翻译如下",
            "翻译是：",
            "这是翻译",
            "翻译结果如下",
            "译文如下",
            "翻译结果",
            "译文",
            "Here are the translations",
            "Here is the translation",
            "Translations",
            "Translation"
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

        // These two phrases can also be the opening words of legitimate
        // translated prose. Treat them as metadata only when they stand
        // alone or are followed by punctuation; explicit instruction markers
        // remain removable even when their line carries an instruction.
        func isPromptMetadataLine(_ line: String, marker: String) -> Bool {
            guard isPromptMarkerAtLineStart(line, marker: marker) else {
                return false
            }
            guard contentSensitiveLineLeakMarkers.contains(where: { candidate in
                candidate.compare(
                    marker,
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
                ) == .orderedSame
            }) else {
                return true
            }
            guard let range = line.range(
                of: marker,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            ) else {
                return false
            }
            let suffix = String(line[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let firstScalar = suffix.unicodeScalars.first else {
                return true
            }
            return CharacterSet.punctuationCharacters.contains(firstScalar)
        }

        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let bulletBody = trimmed.hasPrefix("- ")
                ? String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                : trimmed
            let isMetadataBullet = trimmed.hasPrefix("- ")
                && (bulletBody.isEmpty
                    || lineLeakMarkers.contains { marker in
                        isPromptMetadataLine(bulletBody, marker: marker)
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
                    isPromptMetadataLine(trimmed, marker: marker)
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

    private func stripLeadingTranslationLabel(from value: String) -> String {
        let labels = [
            "翻译结果如下",
            "译文如下",
            "Here are the translations",
            "Here is the translation",
            "Translations",
            "Translation",
            "翻译结果",
            "译文"
        ]
        let whitespace = CharacterSet.whitespacesAndNewlines
        let punctuation = CharacterSet.punctuationCharacters

        func isOnly(_ character: Character, in set: CharacterSet) -> Bool {
            character.unicodeScalars.allSatisfy { set.contains($0) }
        }

        for label in labels.sorted(by: { $0.count > $1.count }) {
            guard let range = value.range(
                of: label,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            ) else {
                continue
            }
            let before = String(value[..<range.lowerBound])
                .trimmingCharacters(in: whitespace.union(punctuation))
            guard before.isEmpty else { continue }

            let suffix = String(value[range.upperBound...])
            var cursor = suffix.startIndex
            while cursor < suffix.endIndex, isOnly(suffix[cursor], in: whitespace) {
                cursor = suffix.index(after: cursor)
            }
            let delimiterStart = cursor
            while cursor < suffix.endIndex, isOnly(suffix[cursor], in: punctuation) {
                cursor = suffix.index(after: cursor)
            }
            guard cursor != delimiterStart else { continue }
            while cursor < suffix.endIndex, isOnly(suffix[cursor], in: whitespace) {
                cursor = suffix.index(after: cursor)
            }
            guard cursor < suffix.endIndex else { continue }

            let payload = String(suffix[cursor...])
                .trimmingCharacters(in: whitespace)
            guard !payload.isEmpty else { continue }
            return payload
        }
        return value
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
