import Foundation

/// The message-level input passed to a local GGUF model. Keeping this apart
/// from the rendered string prevents one model's control tokens from being
/// accidentally embedded inside another model's chat template.
struct LocalModelChatMessage: Equatable, Codable, Sendable {
    enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }

    var role: Role
    var content: String

    init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

enum LocalModelPromptProfileID: String, Codable, Sendable {
    case gemma
    case qwen
    case sakura
    case llama
    case hunyuan
    case experimental
}

enum LocalModelKnownFallbackTemplate: String, Codable, Sendable {
    case gemma
}

enum LocalModelChatTemplateSource: String, Codable, Sendable {
    case embedded
    case explicitKnownFallback
}

enum LocalModelPromptProfileError: LocalizedError, Sendable {
    case fallbackUnavailable(LocalModelPromptProfileID)
    case emptyMessage

    var errorDescription: String? {
        switch self {
        case .fallbackUnavailable(let profileID):
            "模型 \(profileID.rawValue) 没有获批准的 chat-template fallback。"
        case .emptyMessage:
            "chat message 不能为空。"
        }
    }
}

/// Model metadata that is safe to keep next to a prompt profile. It is not a
/// license or quality approval; those remain separate benchmark artifacts.
struct LocalModelPromptProfile: Equatable, Codable, Sendable {
    var profileID: LocalModelPromptProfileID
    var displayName: String
    var knownFallbackTemplate: LocalModelKnownFallbackTemplate?
    var requiresEmbeddedTemplateForUnknownModel: Bool
    var contextLength: Int
    var defaultDecodingProfileID: String
    var supportedSourceLanguages: [String]
    var supportedTargetLanguages: [String]

    static let gemma = LocalModelPromptProfile(
        profileID: .gemma,
        displayName: "Gemma-compatible local chat",
        knownFallbackTemplate: .gemma,
        requiresEmbeddedTemplateForUnknownModel: true,
        contextLength: 1_024,
        defaultDecodingProfileID: "sampled-v1",
        supportedSourceLanguages: ["Japanese", "English (US)"],
        supportedTargetLanguages: ["简体中文", "English (US)"]
    )

    static let qwen = LocalModelPromptProfile(
        profileID: .qwen,
        displayName: "Qwen-compatible local chat",
        knownFallbackTemplate: nil,
        requiresEmbeddedTemplateForUnknownModel: true,
        contextLength: 1_024,
        defaultDecodingProfileID: "sampled-v1",
        supportedSourceLanguages: ["Japanese", "English (US)"],
        supportedTargetLanguages: ["简体中文", "English (US)"]
    )

    static let sakura = LocalModelPromptProfile(
        profileID: .sakura,
        displayName: "Sakura-compatible local chat",
        knownFallbackTemplate: nil,
        requiresEmbeddedTemplateForUnknownModel: true,
        contextLength: 1_024,
        defaultDecodingProfileID: "sampled-v1",
        supportedSourceLanguages: ["Japanese"],
        supportedTargetLanguages: ["简体中文", "English (US)"]
    )

    static let llama = LocalModelPromptProfile(
        profileID: .llama,
        displayName: "Llama-compatible local chat",
        knownFallbackTemplate: nil,
        requiresEmbeddedTemplateForUnknownModel: true,
        contextLength: 1_024,
        defaultDecodingProfileID: "sampled-v1",
        supportedSourceLanguages: ["Japanese", "English (US)"],
        supportedTargetLanguages: ["简体中文", "English (US)"]
    )

    static let hunyuan = LocalModelPromptProfile(
        profileID: .hunyuan,
        displayName: "Hunyuan-compatible local chat",
        knownFallbackTemplate: nil,
        requiresEmbeddedTemplateForUnknownModel: true,
        contextLength: 1_024,
        defaultDecodingProfileID: "sampled-v1",
        supportedSourceLanguages: ["Japanese", "English (US)"],
        supportedTargetLanguages: ["简体中文", "English (US)"]
    )

    static let experimental = LocalModelPromptProfile(
        profileID: .experimental,
        displayName: "Experimental local chat",
        knownFallbackTemplate: nil,
        requiresEmbeddedTemplateForUnknownModel: true,
        contextLength: 1_024,
        defaultDecodingProfileID: "deterministic-v1",
        supportedSourceLanguages: [],
        supportedTargetLanguages: []
    )

    /// Render only an explicitly approved fallback. In particular, this
    /// method never turns a missing template into ChatML or another guessed
    /// wrapper.
    func fallbackPrompt(
        for messages: [LocalModelChatMessage],
        addAssistant: Bool = true
    ) throws -> String {
        guard !messages.isEmpty else {
            throw LocalModelPromptProfileError.emptyMessage
        }
        guard knownFallbackTemplate == .some(.gemma) else {
            throw LocalModelPromptProfileError.fallbackUnavailable(profileID)
        }

        var output = ""
        var pendingSystem = ""
        for message in messages {
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                throw LocalModelPromptProfileError.emptyMessage
            }
            if message.role == .system {
                if !pendingSystem.isEmpty {
                    pendingSystem += "\n\n"
                }
                pendingSystem += content
                continue
            }

            if message.role == .assistant && !pendingSystem.isEmpty {
                output += "<start_of_turn>user\n\(pendingSystem)<end_of_turn>\n"
                pendingSystem = ""
            }
            let role = message.role == .assistant ? "model" : message.role.rawValue
            output += "<start_of_turn>\(role)\n"
            if !pendingSystem.isEmpty && message.role != .assistant {
                output += "\(pendingSystem)\n\n"
                pendingSystem = ""
            }
            output += "\(content)<end_of_turn>\n"
        }

        if !pendingSystem.isEmpty {
            output += "<start_of_turn>user\n\(pendingSystem)<end_of_turn>\n"
        }
        if addAssistant {
            output += "<start_of_turn>model"
        }
        return output
    }
}

struct LocalModelRenderedPrompt: Equatable, Sendable {
    var prompt: String
    var source: LocalModelChatTemplateSource
    var embeddedTemplate: String?
}
