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

    var isFreeTranslationTarget: Bool {
        switch self {
        case .englishUS, .simplifiedChinese:
            true
        case .japanese, .french, .german:
            false
        }
    }

    var speechLocaleIdentifier: String {
        switch self {
        case .englishUS: "en-US"
        case .simplifiedChinese: "zh-CN"
        case .japanese: "ja-JP"
        case .french: "fr-FR"
        case .german: "de-DE"
        }
    }

    var visionRecognitionLanguageIdentifiers: [String] {
        switch self {
        case .englishUS:
            ["en-US", "en"]
        case .simplifiedChinese:
            ["zh-Hans", "zh-CN", "zh"]
        case .japanese:
            ["ja-JP", "ja"]
        case .french:
            ["fr-FR", "fr"]
        case .german:
            ["de-DE", "de"]
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

struct BuiltInLocalModel: Equatable, Sendable {
    var displayName: String
    var filename: String
    var sourceURL: URL
    var expectedSizeBytes: Int64
    var sha256: String

    static let gemma270M = BuiltInLocalModel(
        displayName: "Gemma 3 270M IT QAT Q4_0",
        filename: "gemma-3-270m-it-qat-Q4_0.gguf",
        sourceURL: URL(string: "https://huggingface.co/ggml-org/gemma-3-270m-it-qat-GGUF/resolve/main/gemma-3-270m-it-qat-Q4_0.gguf")!,
        expectedSizeBytes: 241_410_624,
        sha256: "3626e245220ca4a1c5911eb4010b3ecb7bdbf5bc53c79403c21355354d1e2dc6"
    )
}

enum ModelDownloadPhase: String, Equatable, Sendable {
    case idle
    case downloading
    case installed
    case failed
}

struct ModelDownloadProgress: Equatable, Sendable {
    var phase: ModelDownloadPhase
    var bytesReceived: Int64
    var totalBytes: Int64
    var speedBytesPerSecond: Int64
    var message: String

    static let idle = ModelDownloadProgress(
        phase: .idle,
        bytesReceived: 0,
        totalBytes: BuiltInLocalModel.gemma270M.expectedSizeBytes,
        speedBytesPerSecond: 0,
        message: "未下载"
    )

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(bytesReceived) / Double(totalBytes), 0), 1)
    }

    var isDownloading: Bool {
        phase == .downloading
    }
}

struct SpeechRecognitionCapability: Identifiable, Equatable, Sendable {
    var id: String { language.id }
    var language: SupportedLanguage
    var localeIdentifier: String
    var supportsOnDeviceRecognition: Bool
}

struct ProSubscriptionPlan: Equatable, Sendable {
    var productID: String
    var title: String
    var displayPrice: String
    var detail: String

    static let development = ProSubscriptionPlan(
        productID: "com.local.aitrans.pro.monthly",
        title: "秒译 Pro",
        displayPrice: "内购开发中",
        detail: "解锁同声传译、多语言目标和图片翻译入口"
    )
}

enum AudioRecognitionState: String, Equatable, Codable, Sendable {
    case idle
    case checking
    case recognizing
    case translated
    case failed
}

enum ImageTranslationState: String, Equatable, Codable, Sendable {
    case idle
    case loading
    case recognizing
    case translating
    case translated
    case failed
}

enum ImageTranslationOverlayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case adjacent = "旁贴"
    case replace = "覆盖"

    var id: String { rawValue }
}

struct NormalizedImageRect: Equatable, Codable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct ImageTranslationBlock: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var original: String
    var translation: String
    var confidence: Float
    var boundingBox: NormalizedImageRect

    init(
        id: UUID = UUID(),
        original: String,
        translation: String = "",
        confidence: Float,
        boundingBox: NormalizedImageRect
    ) {
        self.id = id
        self.original = original
        self.translation = translation
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

enum ModelEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case mock = "Mock"
    case local = "Local"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mock: "Gemma 1.5B Mock"
        case .local: "Local GGUF"
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
    static let translatorID = UUID(uuidString: "F5E1EDB9-A29B-4E57-8E3B-5D0D6C62B4D5")!
    static let literalTranslationID = UUID(uuidString: "64B62B0D-3661-4772-9F8C-8473709700B2")!
    static let conciseID = UUID(uuidString: "C2D38258-65EE-4B0A-BAC1-358111BC4FAE")!

    static var defaultPrompts: [PromptTemplate] {
        [
            PromptTemplate(
                id: translatorID,
                title: "通用翻译",
                instruction: "把输入内容从源语言翻译为目标语言。只输出译文，不解释、不总结、不改写成会议纪要。保留人名、产品名、数字、日期和专有名词。",
                tone: "自然、准确、直接",
                isBuiltIn: true
            ),
            PromptTemplate(
                id: interpreterID,
                title: "同声传译",
                instruction: "保持原意，优先给出自然、简洁、可直接展示给听众的译文。遇到不确定专有名词时保留原文。",
                tone: "专业、流畅、低延迟",
                isBuiltIn: true
            ),
            PromptTemplate(
                id: literalTranslationID,
                title: "直译优先",
                instruction: "逐句翻译为目标语言，尽量保持原句结构和术语。不要补充上下文，不输出项目计划、待办或总结。",
                tone: "忠实、克制、术语一致",
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

enum ModelStreamEvent: Sendable {
    case token(String)
    case completed(ModelGenerationResult)
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

struct LLMInterfaceSmokeTest: Equatable, Sendable {
    var input: String
    var output: String
    var state: DiagnosticState
    var message: String
    var engineName: String
    var tokenCount: Int?
    var durationMilliseconds: Int?

    static let defaultInput = "Keep the model on device."

    static let idle = LLMInterfaceSmokeTest(
        input: defaultInput,
        output: "",
        state: .idle,
        message: "等待发送模拟 LLM 请求。",
        engineName: "",
        tokenCount: nil,
        durationMilliseconds: nil
    )
}

protocol LocalLanguageModeling: Sendable {
    var metadata: ModelAdapterMetadata { get }

    func prepare() async throws
    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResult
    func stream(_ request: ModelGenerationRequest) -> AsyncThrowingStream<ModelStreamEvent, Error>
}

extension LocalLanguageModeling {
    func stream(_ request: ModelGenerationRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await generate(request)
                    if !result.text.isEmpty {
                        continuation.yield(.token(result.text))
                    }
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
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
    var isProUnlocked: Bool

    static let defaultValue = AppSettings(
        mode: .translate,
        sourceLanguage: .englishUS,
        targetLanguage: .simplifiedChinese,
        selectedPromptID: PromptTemplate.translatorID,
        selectedEngine: .mock,
        sampling: .defaultValue,
        isProUnlocked: false
    )

    init(
        mode: SessionMode,
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage,
        selectedPromptID: UUID,
        selectedEngine: ModelEngine,
        sampling: GenerationSampling,
        isProUnlocked: Bool
    ) {
        self.mode = mode
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.selectedPromptID = selectedPromptID
        self.selectedEngine = selectedEngine
        self.sampling = sampling
        self.isProUnlocked = isProUnlocked
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case sourceLanguage
        case targetLanguage
        case selectedPromptID
        case selectedEngine
        case sampling
        case isProUnlocked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(SessionMode.self, forKey: .mode)
        sourceLanguage = try container.decode(SupportedLanguage.self, forKey: .sourceLanguage)
        targetLanguage = try container.decode(SupportedLanguage.self, forKey: .targetLanguage)
        selectedPromptID = try container.decode(UUID.self, forKey: .selectedPromptID)
        selectedEngine = try container.decode(ModelEngine.self, forKey: .selectedEngine)
        sampling = try container.decode(GenerationSampling.self, forKey: .sampling)
        isProUnlocked = try container.decodeIfPresent(Bool.self, forKey: .isProUnlocked) ?? false
    }
}

struct AppPersistenceSnapshot: Equatable, Codable, Sendable {
    var activeSession: TranslationSessionRecord?
    var history: [TranslationSessionRecord]
    var prompts: [PromptTemplate]
    var settings: AppSettings
}
