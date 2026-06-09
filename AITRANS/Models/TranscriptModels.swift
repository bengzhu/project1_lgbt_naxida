import Foundation

enum SessionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case live = "实时"
    case translate = "翻译"
    case summary = "总结"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .live: "waveform"
        case .translate: "character.bubble"
        case .summary: "sparkles"
        }
    }

    var detail: String {
        switch self {
        case .live: "适合同声传译和会议记录"
        case .translate: "适合逐句翻译和润色"
        case .summary: "适合整理要点和行动项"
        }
    }
}

enum SupportedLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case englishUS = "英语(美国)"
    case simplifiedChinese = "简体中文"
    case japanese = "日语"
    case french = "法语"
    case german = "德语"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .englishUS: "EN"
        case .simplifiedChinese: "ZH"
        case .japanese: "JA"
        case .french: "FR"
        case .german: "DE"
        }
    }
}

struct TranscriptLine: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var speaker: String
    var original: String
    var translation: String
    var time: String
    var isFinal: Bool

    init(
        id: UUID = UUID(),
        speaker: String,
        original: String,
        translation: String,
        time: String,
        isFinal: Bool
    ) {
        self.id = id
        self.speaker = speaker
        self.original = original
        self.translation = translation
        self.time = time
        self.isFinal = isFinal
    }
}

struct AISummary: Equatable, Codable, Sendable {
    var bullets: [String]
    var actions: [String]
    var title: String

    static let empty = AISummary(
        bullets: ["新会话已准备好，等待实时转录输入。"],
        actions: ["开始录音或输入一段文本进行模拟。"],
        title: "空白会话"
    )
}

struct ModelStatus: Equatable, Sendable {
    var title: String
    var detail: String
    var isReady: Bool
}

enum ModelEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case mock = "Mock"
    case local = "Local"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mock: "Gemma 1.5B Mock"
        case .local: "Gemma 1.5B Local"
        }
    }

    var systemImage: String {
        switch self {
        case .mock: "cpu.fill"
        case .local: "externaldrive.fill"
        }
    }
}

struct PromptTemplate: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var title: String
    var instruction: String
    var tone: String
    var createdAt: Date
    var updatedAt: Date
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        title: String,
        instruction: String,
        tone: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.tone = tone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isBuiltIn = isBuiltIn
    }

    static let interpreterID = UUID(uuidString: "4B7087C2-0CF1-4A9B-92B5-27152270A101")!
    static let meetingID = UUID(uuidString: "64B62B0D-3661-4772-9F8C-8473709700B2")!
    static let conciseID = UUID(uuidString: "C2D38258-65EE-4B0A-BAC1-358111BC4FAE")!

    static var defaultPrompts: [PromptTemplate] {
        [
            PromptTemplate(
                id: interpreterID,
                title: "同声传译",
                instruction: "保持原意，优先给出自然、简洁、可直接展示给听众的译文。遇到不确定专有名词时保留原文。",
                tone: "专业、流畅、低延迟",
                isBuiltIn: true
            ),
            PromptTemplate(
                id: meetingID,
                title: "会议纪要",
                instruction: "识别决策、风险、待办和负责人。总结时不要扩写没有出现的信息。",
                tone: "结构化、准确、偏商务",
                isBuiltIn: true
            ),
            PromptTemplate(
                id: conciseID,
                title: "极简翻译",
                instruction: "只输出译文，删除寒暄和重复表达，保留数字、日期和实体名称。",
                tone: "短句、清晰、克制",
                isBuiltIn: true
            )
        ]
    }
}

struct GenerationSampling: Equatable, Codable, Sendable {
    var temperature: Double
    var maxTokens: Int

    static let defaultValue = GenerationSampling(temperature: 0.55, maxTokens: 512)
}

enum ModelTask: String, Codable, Sendable {
    case translation
    case summary
}

struct ModelAdapterMetadata: Equatable, Sendable {
    var engine: ModelEngine
    var displayName: String
    var modelName: String
    var quantization: String
    var supportsStreaming: Bool
}

struct ModelGenerationRequest: Sendable {
    var task: ModelTask
    var mode: SessionMode
    var inputText: String
    var transcriptContext: [TranscriptLine]
    var sourceLanguage: SupportedLanguage
    var targetLanguage: SupportedLanguage
    var prompt: PromptTemplate
    var sampling: GenerationSampling
}

struct ModelGenerationResult: Sendable {
    var text: String
    var summary: AISummary?
    var engineName: String
    var tokenCount: Int?
    var durationMilliseconds: Int?
}

enum DiagnosticState: String, Codable, Sendable {
    case idle
    case running
    case passed
    case failed
}

struct DiagnosticCheck: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var title: String
    var detail: String
    var state: DiagnosticState
}

protocol LocalLanguageModeling: Sendable {
    var metadata: ModelAdapterMetadata { get }

    func prepare() async throws
    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResult
}

struct TranslationSessionRecord: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var mode: SessionMode
    var sourceLanguage: SupportedLanguage
    var targetLanguage: SupportedLanguage
    var selectedPromptID: UUID
    var selectedEngine: ModelEngine
    var durationSeconds: Int
    var transcript: [TranscriptLine]
    var summary: AISummary
}

struct AppSettings: Equatable, Codable, Sendable {
    var mode: SessionMode
    var sourceLanguage: SupportedLanguage
    var targetLanguage: SupportedLanguage
    var selectedPromptID: UUID
    var selectedEngine: ModelEngine
    var sampling: GenerationSampling

    static let defaultValue = AppSettings(
        mode: .live,
        sourceLanguage: .englishUS,
        targetLanguage: .simplifiedChinese,
        selectedPromptID: PromptTemplate.interpreterID,
        selectedEngine: .mock,
        sampling: .defaultValue
    )
}

struct AppPersistenceSnapshot: Equatable, Codable, Sendable {
    var activeSession: TranslationSessionRecord?
    var history: [TranslationSessionRecord]
    var prompts: [PromptTemplate]
    var settings: AppSettings
}
