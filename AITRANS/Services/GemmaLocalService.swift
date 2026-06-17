import Foundation

enum GemmaLocalServiceError: LocalizedError, Sendable {
    case modelNotInstalled(URL)

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled(let directory):
            "Local GGUF model is not installed. Expected model file under \(directory.path)."
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
            let output = try Self.runtime.generate(
                prompt: translationPrompt(for: request),
                maxTokens: min(request.sampling.maxTokens, 160)
            )
            let cleanedOutput = cleanTranslationOutput(output, fallbackInput: request.inputText)
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

    private func modelURL() throws -> URL {
        let marker = modelDirectory.appendingPathComponent("model.gguf")
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw GemmaLocalServiceError.modelNotInstalled(modelDirectory)
        }
        return marker
    }

    private func translationPrompt(for request: ModelGenerationRequest) -> String {
        """
        <start_of_turn>user
        You are a translation engine.
        Translate from \(request.sourceLanguage.rawValue) to \(request.targetLanguage.rawValue).
        User instruction: \(request.prompt.instruction)
        Tone: \(request.prompt.tone)
        Hard rules:
        - Output only the translated text.
        - Do not summarize.
        - Do not add explanations.
        - Keep names, product names, numbers, dates, and technical terms faithful.

        \(request.inputText)
        <end_of_turn>
        <start_of_turn>model
        """
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

    private func cleanTranslationOutput(_ output: String, fallbackInput: String) -> String {
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

        let lines = text
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("- ") }
            .filter { !$0.localizedCaseInsensitiveContains("translation engine") }
            .filter { !$0.localizedCaseInsensitiveContains("do not summarize") }
            .filter { !$0.localizedCaseInsensitiveContains("do not add explanations") }

        if let last = lines.last {
            return last
        }

        return text.isEmpty ? fallbackInput : text
    }

    private func elapsedMilliseconds(from start: Date) -> Int {
        Int(Date.now.timeIntervalSince(start) * 1_000)
    }
}
