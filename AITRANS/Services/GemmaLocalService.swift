import Foundation

enum GemmaLocalServiceError: LocalizedError, Sendable {
    case modelNotInstalled(URL)

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled(let directory):
            "Gemma 1.5B model is not installed. Expected model files under \(directory.path)."
        }
    }
}

struct GemmaLocalService: LocalLanguageModeling {
    let modelDirectory: URL
    let metadata = ModelAdapterMetadata(
        engine: .local,
        displayName: "Gemma 1.5B Local",
        modelName: "gemma-1.5b-it",
        quantization: "GGUF Q4_K_M",
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
        try ensureModelInstalled()
    }

    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResult {
        let start = Date()
        try ensureModelInstalled()

        switch request.task {
        case .translation:
            let output = "[Gemma 1.5B local placeholder] \(request.targetLanguage.rawValue): \(request.inputText)"
            return ModelGenerationResult(
                text: output,
                summary: nil,
                engineName: metadata.displayName,
                tokenCount: max(8, output.count / 2),
                durationMilliseconds: elapsedMilliseconds(from: start)
            )

        case .summary:
            let summary = AISummary(
                bullets: request.transcriptContext.prefix(3).map { "\($0.speaker): \($0.translation)" },
                actions: ["真实 Gemma 1.5B 推理层接入后，在这里返回本地生成的行动项。"],
                title: "Gemma 本地总结"
            )
            return ModelGenerationResult(
                text: summary.bullets.joined(separator: "\n"),
                summary: summary,
                engineName: metadata.displayName,
                tokenCount: max(8, summary.bullets.joined().count / 2),
                durationMilliseconds: elapsedMilliseconds(from: start)
            )
        }
    }

    private func ensureModelInstalled() throws {
        let marker = modelDirectory.appendingPathComponent("model.gguf")
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw GemmaLocalServiceError.modelNotInstalled(modelDirectory)
        }
    }

    private func elapsedMilliseconds(from start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1_000)
    }
}
