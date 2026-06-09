import Foundation

struct MockGemmaService: LocalLanguageModeling {
    let metadata = ModelAdapterMetadata(
        engine: .mock,
        displayName: "Gemma 1.5B Mock",
        modelName: "gemma-1.5b-it-simulated",
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
        let sourcePreview = normalized.isEmpty ? "当前输入" : String(normalized.prefix(42))
        let promptHint = request.prompt.title

        switch request.targetLanguage {
        case .simplifiedChinese:
            return "【\(promptHint)】根据「\(sourcePreview)」，我们会先确认目标，再把技术方案、时间线和风险整理成可以执行的清单。"
        case .englishUS:
            return "[\(promptHint)] Based on \"\(sourcePreview)\", let's align on the goal, then turn the technical plan, timeline, and risks into actionable notes."
        case .japanese:
            return "【\(promptHint)】「\(sourcePreview)」に基づき、目標を確認し、技術案、日程、リスクを実行可能なメモに整理します。"
        case .french:
            return "[\(promptHint)] À partir de \"\(sourcePreview)\", nous confirmons l'objectif, puis transformons le plan, le calendrier et les risques en actions."
        case .german:
            return "[\(promptHint)] Ausgehend von „\(sourcePreview)” klären wir das Ziel und fassen Technikplan, Zeitplan und Risiken als Aufgaben zusammen."
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
                "将 Gemma 1.5B 量化模型放入本地模型目录后切换 Local 引擎。",
                "为长会议保留分段摘要，避免上下文过长。"
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
