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

    let modelDirectory: URL
    let metadata = ModelAdapterMetadata(
        engine: .local,
        displayName: "Local GGUF",
        modelName: "imported model.gguf",
        quantization: "GGUF",
        supportsStreaming: false
    )

    init(
        modelDirectory: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models/Gemma-1.5B", isDirectory: true)
    ) {
        self.modelDirectory = modelDirectory
    }

    func prepare() async throws {
        let modelURL = try modelURL()
        try Self.runtime.loadModelIfNeeded(at: modelURL.path)
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
                prompt: summaryPrompt(for: request),
                maxTokens: min(request.sampling.maxTokens, 220)
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
        var lastError: Error?
        for (index, prompt) in translationPrompts(for: request).enumerated() {
            do {
                Self.writeTranslationProbeLog(
                    "local-attempt-start index=\(index + 1) " +
                    "source=\(request.sourceLanguage.rawValue) target=\(request.targetLanguage.rawValue) " +
                    "input=\(Self.probeField(request.inputText)) prompt=\(Self.probeField(prompt))"
                )
                let output = try Self.runtime.generate(
                    prompt: prompt,
                    maxTokens: min(request.sampling.maxTokens, 160)
                )
                Self.writeTranslationProbeLog(
                    "local-attempt-raw index=\(index + 1) output=\(Self.probeField(output))"
                )
                let cleanedOutput = try cleanTranslationOutput(
                    output,
                    input: request.inputText,
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

    private func modelURL() throws -> URL {
        let marker = modelDirectory.appendingPathComponent("model.gguf")
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw GemmaLocalServiceError.modelNotInstalled(modelDirectory)
        }
        return marker
    }

    private func translationPrompts(for request: ModelGenerationRequest) -> [String] {
        if request.sourceLanguage == .englishUS, request.targetLanguage == .simplifiedChinese {
            return [
                """
                <start_of_turn>user
                翻译成中文，不要输出英文原文，不要解释：
                \(request.inputText)
                <end_of_turn>
                <start_of_turn>model
                """,
                """
                <start_of_turn>user
                English -> 简体中文。只输出中文译文：
                \(request.inputText)
                <end_of_turn>
                <start_of_turn>model
                """,
                """
                <start_of_turn>user
                请把下面英文翻译成简体中文，只输出中文译文：
                \(request.inputText)
                <end_of_turn>
                <start_of_turn>model
                """
            ]
        }

        return [
            """
            <start_of_turn>user
            请把下面内容从\(request.sourceLanguage.rawValue)翻译成\(request.targetLanguage.rawValue)，只输出译文：
            \(request.inputText)
            <end_of_turn>
            <start_of_turn>model
            """,
            """
            <start_of_turn>user
            翻译成\(request.targetLanguage.rawValue)，不要输出原文，不要解释：
            \(request.inputText)
            <end_of_turn>
            <start_of_turn>model
            """
        ]
    }

    private func summaryPrompt(for request: ModelGenerationRequest) -> String {
        let context = request.transcriptContext
            .prefix(8)
            .map { "\($0.speaker): \($0.translation)" }
            .joined(separator: "\n")

        return """
        <start_of_turn>user
        Summarize the following transcript in \(request.targetLanguage.rawValue).
        Return three short bullet points only.

        \(context.isEmpty ? request.inputText : context)
        <end_of_turn>
        <start_of_turn>model
        """
    }

    private func estimateTokenCount(_ text: String) -> Int {
        max(1, text.count / 2)
    }

    private func cleanTranslationOutput(
        _ output: String,
        input: String,
        targetLanguage: SupportedLanguage
    ) throws -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let cutMarkers = [
            "<end_of_turn>",
            "<start_of_turn>",
            "You are a translation engine.",
            "Hard rules:",
            "Translate the following text",
            "Translate from",
            "User instruction:",
            "Output only"
        ]

        for marker in cutMarkers {
            if let range = text.range(of: marker) {
                text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
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
            "简体中文翻译"
        ]
        lines.removeAll { line in
            line.hasPrefix("- ")
                || (line.hasPrefix("|") && line.hasSuffix("|"))
                || lineLeakMarkers.contains { line.localizedCaseInsensitiveContains($0) }
        }

        if let last = lines.last, !last.isEmpty {
            return try validateTranslationOutput(last, input: input, targetLanguage: targetLanguage)
        }

        guard !text.isEmpty else {
            throw GemmaLocalServiceError.emptyOutput
        }
        return try validateTranslationOutput(stripFormatting(from: text), input: input, targetLanguage: targetLanguage)
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
        targetLanguage: SupportedLanguage
    ) throws -> String {
        let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let normalizedOutput = output.trimmingCharacters(in: trimSet)
        let normalizedInput = input.trimmingCharacters(in: trimSet)
        guard !normalizedOutput.isEmpty else {
            throw GemmaLocalServiceError.emptyOutput
        }
        guard normalizedOutput.localizedCaseInsensitiveCompare(normalizedInput) != ComparisonResult.orderedSame else {
            throw GemmaLocalServiceError.repeatedInput
        }
        guard !normalizedOutput.localizedCaseInsensitiveContains(normalizedInput), !normalizedInput.localizedCaseInsensitiveContains(normalizedOutput) else {
            throw GemmaLocalServiceError.repeatedInput
        }
        guard !isPlaceholderResponse(output) else {
            throw GemmaLocalServiceError.emptyOutput
        }
        guard looksLikeTargetLanguage(output, targetLanguage: targetLanguage) else {
            throw GemmaLocalServiceError.outputNotInTargetLanguage(targetLanguage)
        }
        return output
    }

    private func isPlaceholderResponse(_ output: String) -> Bool {
        let markers = [
            "请您提供",
            "请提供",
            "想要翻译的文本",
            "需要翻译的文本",
            "无法翻译",
            "cannot translate",
            "please provide",
            "provide the text"
        ]
        return markers.contains { output.localizedCaseInsensitiveContains($0) }
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
