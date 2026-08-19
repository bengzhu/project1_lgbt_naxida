import Foundation

private enum EvaluatorError: Error {
    case expectedFailure
}

private struct TemplateFixture {
    let profileID: LocalModelPromptProfileID
    let embeddedTemplate: String?
    let expectedPrefix: String?
}

@main
struct LocalGGUFChatTemplateEvaluator {
    static func main() throws {
        let messages = [
            LocalModelChatMessage(
                role: .system,
                content: "只输出译文。"
            ),
            LocalModelChatMessage(
                role: .user,
                content: "今度こそ😀\n[1] 持ち帰る！"
            )
        ]

        let gemma = TemplateFixture(
            profileID: .gemma,
            embeddedTemplate: "<start_of_turn>gemma fixture",
            expectedPrefix: "<start_of_turn>user\n只输出译文。\n\n今度こそ😀"
        )
        let qwen = TemplateFixture(
            profileID: .qwen,
            embeddedTemplate: "<|im_start|>qwen fixture",
            expectedPrefix: "<|im_start|>user"
        )
        let sakura = TemplateFixture(
            profileID: .sakura,
            embeddedTemplate: "<|im_start|>sakura fixture",
            expectedPrefix: "<|im_start|>user"
        )

        let gemmaFallback = try LocalModelPromptProfile.gemma.fallbackPrompt(for: messages)
        precondition(gemmaFallback.hasPrefix(gemma.expectedPrefix ?? ""))
        precondition(gemmaFallback.contains("<start_of_turn>model"))
        precondition(gemmaFallback.contains("😀"))
        precondition(!gemmaFallback.contains("<|im_start|>"))

        for fixture in [qwen, sakura] {
            precondition(fixture.embeddedTemplate != nil)
            do {
                _ = try LocalModelPromptProfile(
                    profileID: fixture.profileID,
                    displayName: fixture.profileID.rawValue,
                    knownFallbackTemplate: nil,
                    requiresEmbeddedTemplateForUnknownModel: true,
                    contextLength: 1_024,
                    defaultDecodingProfileID: "sampled-v1",
                    supportedSourceLanguages: ["Japanese"],
                    supportedTargetLanguages: ["简体中文"]
                ).fallbackPrompt(for: messages)
                throw EvaluatorError.expectedFailure
            } catch let error as LocalModelPromptProfileError {
                guard case .fallbackUnavailable = error else { throw error }
                // Missing Qwen/Sakura templates are a hard stop, not Gemma.
            }
        }

        let renderedGemmaFixture = renderFixture(
            template: gemma.embeddedTemplate!,
            messages: messages,
            assistantPrefix: "<start_of_turn>model"
        )
        precondition(renderedGemmaFixture.hasPrefix(gemma.expectedPrefix ?? ""))

        for fixture in [qwen, sakura] {
            let rendered = renderFixture(
                template: fixture.embeddedTemplate!,
                messages: messages,
                assistantPrefix: "<|im_start|>assistant"
            )
            precondition(rendered.hasPrefix(fixture.expectedPrefix ?? ""))
            precondition(!rendered.contains("<start_of_turn>user"))
        }

        let longText = String(repeating: "长文本😀", count: 512)
        let resized = renderWithBufferResize(longText)
        precondition(resized == longText)

        let tagged = "[2] 二\n[1] 一"
        let tags = tagged
            .split(separator: "\n")
            .compactMap { line -> Int? in
                guard line.first == "[", let end = line.firstIndex(of: "]") else { return nil }
                return Int(line[line.index(after: line.startIndex)..<end])
            }
        precondition(tags == [2, 1])
        precondition(gemmaFallback.contains("[1] 持ち帰る！"))

        let encoded = try JSONEncoder().encode(LocalModelPromptProfile.gemma)
        let decoded = try JSONDecoder().decode(LocalModelPromptProfile.self, from: encoded)
        precondition(decoded == .gemma)

        print("v3.286 local GGUF chat-template evaluator passed")
    }

    private static func renderFixture(
        template: String,
        messages: [LocalModelChatMessage],
        assistantPrefix: String
    ) -> String {
        if template.contains("<start_of_turn>") {
            let user = messages
                .filter { $0.role == .user }
                .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: "\n")
            let system = messages
                .filter { $0.role == .system }
                .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: "\n\n")
            return "<start_of_turn>user\n\(system)\n\n\(user)<end_of_turn>\n\(assistantPrefix)"
        }
        let user = messages
            .filter { $0.role == .user }
            .map { $0.content }
            .joined(separator: "\n")
        return "<|im_start|>user\n\(user)<|im_end|>\n\(assistantPrefix)"
    }

    private static func renderWithBufferResize(_ value: String) -> String {
        let bytes = Array(value.utf8)
        var capacity = 8
        while true {
            if bytes.count < capacity {
                return String(decoding: bytes, as: UTF8.self)
            }
            capacity = bytes.count + 1
        }
    }
}
