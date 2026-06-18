import Foundation

struct MockGemmaService: LocalLanguageModeling {
    let metadata = ModelAdapterMetadata(
        engine: .mock,
        displayName: "Gemma 1.5B Mock",
        modelName: "translation-mock",
        quantization: "Simulated Q4",
        supportsStreaming: true
    )

    func prepare() async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResult {
        let start = Date()
        try await Task.sleep(for: .milliseconds(request.task == .summary ? 520 : 360))

        switch request.task {
        case .translation:
            let text = translatedText(for: request)
            return ModelGenerationResult(
                text: text,
                summary: nil,
                engineName: metadata.displayName,
                tokenCount: estimateTokenCount(text),
                durationMilliseconds: elapsedMilliseconds(from: start)
            )

        case .summary:
            let summary = summary(for: request)
            return ModelGenerationResult(
                text: summary.bullets.joined(separator: "\n"),
                summary: summary,
                engineName: metadata.displayName,
                tokenCount: estimateTokenCount(summary.bullets.joined() + summary.actions.joined()),
                durationMilliseconds: elapsedMilliseconds(from: start)
            )
        }
    }

    private func translatedText(for request: ModelGenerationRequest) -> String {
        let normalized = request.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptHint = request.prompt.title

        switch request.targetLanguage {
        case .simplifiedChinese:
            let text = normalized.isEmpty ? "当前输入已翻译为中文。" : "这是 Mock 生成的中文译文。"
            return "【\(promptHint)】\(text)"
        case .englishUS:
            let text = normalized.isEmpty ? "The current input has been translated into English." : "This is a mock English translation."
            return "[\(promptHint)] \(text)"
        case .japanese:
            return "【\(promptHint)】これは Mock 生成の日本語訳です。"
        case .french:
            return "[\(promptHint)] Ceci est une traduction française simulée."
        case .german:
            return "[\(promptHint)] Dies ist eine simulierte deutsche Übersetzung."
        }
    }

    private func summary(for request: ModelGenerationRequest) -> AISummary {
        let count = max(request.transcriptContext.count, 1)
        let latest = request.transcriptContext.first?.translation ?? "当前还没有完整转录。"

        return AISummary(
            bullets: [
                "已使用 \(metadata.displayName) 模拟处理 \(count) 条本地转录片段。",
                "当前提示词为「\(request.prompt.title)」，语气要求：\(request.prompt.tone)。",
                "最近内容：\(latest)"
            ],
            actions: [
                "继续完善录音转写入口，并把真实音频文本送入同一个生成接口。",
                "在模型页下载内置 Gemma 270M 或导入 GGUF 后切换 Local 引擎。",
                "用 LLM 接口自测确认真实模型输入输出。"
            ],
            title: request.mode == .summary ? "AI 总结" : "实时摘要"
        )
    }

    private func estimateTokenCount(_ text: String) -> Int {
        max(8, text.count / 2)
    }

    private func elapsedMilliseconds(from start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1_000)
    }
}
