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
        displayPrice: "$0.99/月",
        detail: "约 1 美元/月，解锁同声传译、多语言目标和图片翻译入口"
    )
}

struct RawModelProbeResult: Equatable, Sendable {
    var prompt: String
    var output: String
    var errorCode: String?
}

struct DeveloperRawProbeCase: Identifiable, Equatable, Sendable {
    var id: UUID
    var sourceLanguage: SupportedLanguage
    var targetLanguage: SupportedLanguage
    var input: String
    var prompt: String
    var output: String
    var errorCode: String?
    var verdict: String
    var isRealLocalModelOutput: Bool

    init(
        id: UUID = UUID(),
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage,
        input: String,
        prompt: String = "",
        output: String = "",
        errorCode: String? = nil,
        verdict: String = "等待运行",
        isRealLocalModelOutput: Bool = false
    ) {
        self.id = id
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.input = input
        self.prompt = prompt
        self.output = output
        self.errorCode = errorCode
        self.verdict = verdict
        self.isRealLocalModelOutput = isRealLocalModelOutput
    }
}

enum MangaOverlayProbeState: String, Equatable, Codable, Sendable {
    case idle
    case loading
    case recognizing
    case translating
    case rendering
    case completed
    case failed
}

struct MangaOverlayProbeChecks: Equatable, Codable, Sendable {
    var ocrNotEmpty: Bool
    var translationNotEmpty: Bool
    var translationNotEqualOriginal: Bool
    var translationNotContainOriginal: Bool
    var translationNotPlaceholder: Bool
    var translationHasEnoughChinese: Bool
    var looksLikeChinese: Bool
}

struct MangaOverlayPreprocessingOptions: Equatable, Codable, Sendable {
    var enabled: Bool
    var grayscaleEnabled: Bool
    var contrastBrightnessEnabled: Bool
    var adaptiveThresholdEnabled: Bool
    var cropUpscaleEnabled: Bool
    var sharpenEnabled: Bool
    var cropScale: Double

    static let disabled = MangaOverlayPreprocessingOptions(
        enabled: false,
        grayscaleEnabled: false,
        contrastBrightnessEnabled: false,
        adaptiveThresholdEnabled: false,
        cropUpscaleEnabled: false,
        sharpenEnabled: false,
        cropScale: 1
    )

    static let defaultValue = MangaOverlayPreprocessingOptions(
        enabled: true,
        grayscaleEnabled: true,
        contrastBrightnessEnabled: true,
        adaptiveThresholdEnabled: true,
        cropUpscaleEnabled: true,
        sharpenEnabled: true,
        cropScale: 3
    )
}

struct MangaOverlayCorrectionOptions: Equatable, Codable, Sendable {
    var enabled: Bool
    var maxLengthDeltaRatio: Double
    var maxWordCountDeltaRatio: Double

    static let disabled = MangaOverlayCorrectionOptions(
        enabled: false,
        maxLengthDeltaRatio: 0.3,
        maxWordCountDeltaRatio: 0.35
    )

    static let defaultValue = MangaOverlayCorrectionOptions(
        enabled: true,
        maxLengthDeltaRatio: 0.3,
        maxWordCountDeltaRatio: 0.35
    )
}

struct MangaOverlayProbeConfiguration: Equatable, Codable, Sendable {
    var status: String
    var currentBlockSource: String
    var preprocessing: MangaOverlayPreprocessingOptions
    var correction: MangaOverlayCorrectionOptions
    var visionNewAPIStatus: String
    var customLexiconEnabled: Bool
    var customLexicon: [String]

    static let defaultValue = MangaOverlayProbeConfiguration(
        status: "current pipeline uses whole-page Vision OCR observations plus spatial clustering; no image-level bubble detection yet",
        currentBlockSource: "a: whole-page OCR observations merged by spatial clustering/deduplication",
        preprocessing: .defaultValue,
        correction: .defaultValue,
        visionNewAPIStatus: "deployment target is iOS 17.0; RecognizeTextRequest needs @available guard and is not part of the main path",
        customLexiconEnabled: true,
        customLexicon: ["Senpai", "City Battler", "Tournament", "Ren", "Battler"]
    )
}

struct MangaOverlayProbeBlock: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var index: Int
    var bbox: [Double]
    var rotationAngleUsed: Int
    var rawOcrText: String
    var ocrText: String
    var ocrConfidence: Float?
    var preprocessingEnabled: Bool
    var afterPreprocessingOcrText: String?
    var correctionEnabled: Bool
    var afterCorrectionText: String?
    var correctionRejectedReason: String?
    var correctionPrompt: String?
    var correctionRawOutput: String?
    var correctionErrorCode: String?
    var deterministicCorrectionText: String?
    var deterministicCorrectionAppliedRules: [String]
    var deterministicCorrectionSimilarity: Double?
    var deterministicCorrectionTranslationCandidate: String?
    var deterministicCorrectionTranslationRawOutput: String?
    var deterministicCorrectionTranslationPassed: Bool?
    var deterministicCorrectionTranslationFailureDetail: String?
    var finalTextUsedForTranslation: String
    var bestGroundTruthIndex: Int?
    var bestGroundTruthText: String?
    var ocrGroundTruthSimilarity: Double?
    var ocrQualityLabel: String?
    var translatedText: String
    var translationCandidate: String
    var rawOutputClassification: String
    var candidateClassification: String
    var failureCategory: String
    var prompt: String
    var rawOutput: String
    var errorCode: String?
    var checks: MangaOverlayProbeChecks
    var failureReasons: [String]
    var qualityNotes: [String]
    var translationDecisionTrace: [String]
    var translationFailureDetail: String?
    var ocrProbeNotes: [String]
    var blockPassed: Bool

    init(
        id: UUID = UUID(),
        index: Int,
        bbox: [Double],
        rotationAngleUsed: Int,
        ocrText: String,
        ocrConfidence: Float?,
        rawOcrText: String? = nil,
        preprocessingEnabled: Bool = false,
        afterPreprocessingOcrText: String? = nil,
        correctionEnabled: Bool = false,
        afterCorrectionText: String? = nil,
        correctionRejectedReason: String? = nil,
        correctionPrompt: String? = nil,
        correctionRawOutput: String? = nil,
        correctionErrorCode: String? = nil,
        deterministicCorrectionText: String? = nil,
        deterministicCorrectionAppliedRules: [String] = [],
        deterministicCorrectionSimilarity: Double? = nil,
        deterministicCorrectionTranslationCandidate: String? = nil,
        deterministicCorrectionTranslationRawOutput: String? = nil,
        deterministicCorrectionTranslationPassed: Bool? = nil,
        deterministicCorrectionTranslationFailureDetail: String? = nil,
        finalTextUsedForTranslation: String? = nil,
        bestGroundTruthIndex: Int? = nil,
        bestGroundTruthText: String? = nil,
        ocrGroundTruthSimilarity: Double? = nil,
        ocrQualityLabel: String? = nil,
        translatedText: String = "",
        translationCandidate: String = "",
        rawOutputClassification: String = "notRun",
        candidateClassification: String = "notRun",
        failureCategory: String = "notRun",
        prompt: String = "",
        rawOutput: String = "",
        errorCode: String? = nil,
        checks: MangaOverlayProbeChecks = MangaOverlayProbeChecks(
            ocrNotEmpty: false,
            translationNotEmpty: false,
            translationNotEqualOriginal: false,
            translationNotContainOriginal: false,
            translationNotPlaceholder: false,
            translationHasEnoughChinese: false,
            looksLikeChinese: false
        ),
        failureReasons: [String] = [],
        qualityNotes: [String] = [],
        translationDecisionTrace: [String] = [],
        translationFailureDetail: String? = nil,
        ocrProbeNotes: [String] = [],
        blockPassed: Bool = false
    ) {
        self.id = id
        self.index = index
        self.bbox = bbox
        self.rotationAngleUsed = rotationAngleUsed
        self.rawOcrText = rawOcrText ?? ocrText
        self.ocrText = ocrText
        self.ocrConfidence = ocrConfidence
        self.preprocessingEnabled = preprocessingEnabled
        self.afterPreprocessingOcrText = afterPreprocessingOcrText
        self.correctionEnabled = correctionEnabled
        self.afterCorrectionText = afterCorrectionText
        self.correctionRejectedReason = correctionRejectedReason
        self.correctionPrompt = correctionPrompt
        self.correctionRawOutput = correctionRawOutput
        self.correctionErrorCode = correctionErrorCode
        self.deterministicCorrectionText = deterministicCorrectionText
        self.deterministicCorrectionAppliedRules = deterministicCorrectionAppliedRules
        self.deterministicCorrectionSimilarity = deterministicCorrectionSimilarity
        self.deterministicCorrectionTranslationCandidate = deterministicCorrectionTranslationCandidate
        self.deterministicCorrectionTranslationRawOutput = deterministicCorrectionTranslationRawOutput
        self.deterministicCorrectionTranslationPassed = deterministicCorrectionTranslationPassed
        self.deterministicCorrectionTranslationFailureDetail = deterministicCorrectionTranslationFailureDetail
        self.finalTextUsedForTranslation = finalTextUsedForTranslation ?? ocrText
        self.bestGroundTruthIndex = bestGroundTruthIndex
        self.bestGroundTruthText = bestGroundTruthText
        self.ocrGroundTruthSimilarity = ocrGroundTruthSimilarity
        self.ocrQualityLabel = ocrQualityLabel
        self.translatedText = translatedText
        self.translationCandidate = translationCandidate
        self.rawOutputClassification = rawOutputClassification
        self.candidateClassification = candidateClassification
        self.failureCategory = failureCategory
        self.prompt = prompt
        self.rawOutput = rawOutput
        self.errorCode = errorCode
        self.checks = checks
        self.failureReasons = failureReasons
        self.qualityNotes = qualityNotes
        self.translationDecisionTrace = translationDecisionTrace
        self.translationFailureDetail = translationFailureDetail
        self.ocrProbeNotes = ocrProbeNotes
        self.blockPassed = blockPassed
    }
}

struct MangaOverlayProbeOutputFiles: Equatable, Codable, Sendable {
    var debugBoxesImage: String
    var overlayImage: String
    var ocrTextOverlayImage: String?
    var deterministicCorrectionOverlayImage: String?
    var deterministicTranslationOverlayImage: String?
    var ocrProbeTextFile: String?
    var blockCropsImage: String?
    var preprocessedContentImage: String?
    var bubbleDebugImage: String?
    var bubbleCropsImage: String?
    var bubbleSeedDebugImage: String?
    var bubbleTextOverlayImage: String?

    init(
        debugBoxesImage: String,
        overlayImage: String,
        ocrTextOverlayImage: String? = nil,
        deterministicCorrectionOverlayImage: String? = nil,
        deterministicTranslationOverlayImage: String? = nil,
        ocrProbeTextFile: String? = nil,
        blockCropsImage: String? = nil,
        preprocessedContentImage: String? = nil,
        bubbleDebugImage: String? = nil,
        bubbleCropsImage: String? = nil,
        bubbleSeedDebugImage: String? = nil,
        bubbleTextOverlayImage: String? = nil
    ) {
        self.debugBoxesImage = debugBoxesImage
        self.overlayImage = overlayImage
        self.ocrTextOverlayImage = ocrTextOverlayImage
        self.deterministicCorrectionOverlayImage = deterministicCorrectionOverlayImage
        self.deterministicTranslationOverlayImage = deterministicTranslationOverlayImage
        self.ocrProbeTextFile = ocrProbeTextFile
        self.blockCropsImage = blockCropsImage
        self.preprocessedContentImage = preprocessedContentImage
        self.bubbleDebugImage = bubbleDebugImage
        self.bubbleCropsImage = bubbleCropsImage
        self.bubbleSeedDebugImage = bubbleSeedDebugImage
        self.bubbleTextOverlayImage = bubbleTextOverlayImage
    }
}

struct MangaOverlayProbeDiagnostics: Equatable, Codable, Sendable {
    var passedBlocks: Int
    var failedBlocks: Int
    var emptyTranslationCandidates: Int
    var placeholderTranslationCandidates: Int
    var repeatedOriginalCandidates: Int
    var nonChineseCandidates: Int
    var cjkButFailedCandidates: Int
    var likelyModelOutputFailures: Int
    var candidateExtractorDroppedRawOutputs: Int
    var rawOutputEmptyBlocks: Int
    var rawOutputPlaceholderBlocks: Int
    var rawOutputRepeatedOriginalBlocks: Int
    var rawOutputNonChineseBlocks: Int
    var averageOCRGroundTruthSimilarity: Double
    var lowOCRSimilarityBlocks: [Int]
    var likelyOCRIssueBlocks: [Int]
    var likelyRuleFalseFailureBlocks: [Int]
    var passedButSuspiciousTranslationBlocks: [Int]
    var translationFailureBreakdown: [String: Int]
    var cjkFailureBreakdown: [String: Int]
    var translationLanguageQualityPassedBlocks: [Int]
    var translationLanguageQualityFailedBlocks: [Int]
    var translationUsableButOCRSuspectBlocks: [Int]
    var ocrQualityProbe: [String]
    var deterministicCorrectionImprovedBlocks: [Int]
    var deterministicCorrectionAverageSimilarity: Double
    var deterministicCorrectionTranslationTestedBlocks: [Int]
    var deterministicCorrectionTranslationPassedBlocks: [Int]
    var deterministicCorrectionTranslationFailedBlocks: [Int]

    static let empty = MangaOverlayProbeDiagnostics(
        passedBlocks: 0,
        failedBlocks: 0,
        emptyTranslationCandidates: 0,
        placeholderTranslationCandidates: 0,
        repeatedOriginalCandidates: 0,
        nonChineseCandidates: 0,
        cjkButFailedCandidates: 0,
        likelyModelOutputFailures: 0,
        candidateExtractorDroppedRawOutputs: 0,
        rawOutputEmptyBlocks: 0,
        rawOutputPlaceholderBlocks: 0,
        rawOutputRepeatedOriginalBlocks: 0,
        rawOutputNonChineseBlocks: 0,
        averageOCRGroundTruthSimilarity: 0,
        lowOCRSimilarityBlocks: [],
        likelyOCRIssueBlocks: [],
        likelyRuleFalseFailureBlocks: [],
        passedButSuspiciousTranslationBlocks: [],
        translationFailureBreakdown: [:],
        cjkFailureBreakdown: [:],
        translationLanguageQualityPassedBlocks: [],
        translationLanguageQualityFailedBlocks: [],
        translationUsableButOCRSuspectBlocks: [],
        ocrQualityProbe: [],
        deterministicCorrectionImprovedBlocks: [],
        deterministicCorrectionAverageSimilarity: 0,
        deterministicCorrectionTranslationTestedBlocks: [],
        deterministicCorrectionTranslationPassedBlocks: [],
        deterministicCorrectionTranslationFailedBlocks: []
    )
}

struct MangaOverlayCorrectionGuardrailTest: Equatable, Codable, Sendable {
    var original: String
    var proposed: String
    var accepted: Bool
    var reason: String?
}

struct MangaOverlayLexiconComparison: Equatable, Codable, Sendable {
    var enabled: Bool
    var customWords: [String]
    var withoutLexiconTotalBlocks: Int
    var withLexiconTotalBlocks: Int
    var changedBlockIndexes: [Int]
    var notes: [String]
}

struct MangaOverlayVisionAPIComparison: Equatable, Codable, Sendable {
    var oldAPITotalObservations: Int
    var newAPISupported: Bool
    var newAPITotalObservations: Int?
    var changed: Bool?
    var oldAPISample: [String]
    var newAPISample: [String]
    var error: String?
}

struct MangaOverlayFrameworkMetrics: Equatable, Codable, Sendable {
    var totalBlocksDetected: Int
    var processingTimeMs: Int
    var accuracyVsGroundTruth: Double
}

struct MangaOverlayBubbleResult: Equatable, Codable, Sendable {
    var index: Int
    var bbox: [Double]
    var source: String
    var text: String
    var bestGroundTruthIndex: Int?
    var bestSimilarity: Double
}

struct MangaOverlayFrameworkComparison: Equatable, Codable, Sendable {
    var groundTruth: [String]
    var wholePage: MangaOverlayFrameworkMetrics
    var bubbleFirst: MangaOverlayFrameworkMetrics
    var blocksOnlyInWholePage: [String]
    var blocksOnlyInBubbleFirst: [String]
    var blocksFoundByBoth: Int
    var bubbleResults: [MangaOverlayBubbleResult]
    var notes: [String]
}

struct MangaOverlayProbeReport: Equatable, Codable, Sendable {
    var sourceImage: String
    var engineUsed: String
    var configuration: MangaOverlayProbeConfiguration
    var totalBlocksDetected: Int
    var blocks: [MangaOverlayProbeBlock]
    var diagnostics: MangaOverlayProbeDiagnostics
    var correctionGuardrailTest: MangaOverlayCorrectionGuardrailTest?
    var lexiconComparison: MangaOverlayLexiconComparison?
    var visionAPIComparison: MangaOverlayVisionAPIComparison?
    var frameworkComparison: MangaOverlayFrameworkComparison?
    var overallPassed: Bool
    var outputFiles: MangaOverlayProbeOutputFiles
    var outputDirectoryCleaned: Bool
    var retainedOutputFiles: [String]
    var outputCleanupPolicy: String
    var warnings: [String]
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

enum PromptLanguageDirection: String, CaseIterable, Identifiable, Codable, Sendable {
    case englishToChinese = "英译中"
    case chineseToEnglish = "中译英"

    var id: String { rawValue }

    var sourceLanguage: SupportedLanguage {
        switch self {
        case .englishToChinese: .englishUS
        case .chineseToEnglish: .simplifiedChinese
        }
    }

    var targetLanguage: SupportedLanguage {
        switch self {
        case .englishToChinese: .simplifiedChinese
        case .chineseToEnglish: .englishUS
        }
    }

    var fallbackInstruction: String {
        switch self {
        case .englishToChinese:
            "把以下翻译成中文："
        case .chineseToEnglish:
            "Translate the following into English:"
        }
    }

    static func direction(source: SupportedLanguage, target: SupportedLanguage) -> PromptLanguageDirection? {
        switch (source, target) {
        case (.englishUS, .simplifiedChinese):
            .englishToChinese
        case (.simplifiedChinese, .englishUS):
            .chineseToEnglish
        default:
            nil
        }
    }
}

struct PromptTemplate: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var title: String
    var instruction: String
    var englishToChineseInstruction: String
    var chineseToEnglishInstruction: String
    var tone: String
    var createdAt: Date
    var updatedAt: Date
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        title: String,
        instruction: String,
        englishToChineseInstruction: String? = nil,
        chineseToEnglishInstruction: String? = nil,
        tone: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.englishToChineseInstruction = englishToChineseInstruction ?? instruction
        self.chineseToEnglishInstruction = chineseToEnglishInstruction ?? instruction
        self.tone = tone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isBuiltIn = isBuiltIn
    }

    func instruction(for direction: PromptLanguageDirection) -> String {
        let candidate: String
        switch direction {
        case .englishToChinese:
            candidate = englishToChineseInstruction
        case .chineseToEnglish:
            candidate = chineseToEnglishInstruction
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? direction.fallbackInstruction : trimmed
    }

    func instruction(source: SupportedLanguage, target: SupportedLanguage) -> String {
        guard let direction = PromptLanguageDirection.direction(source: source, target: target) else {
            let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "只输出译文：" : trimmed
        }

        return instruction(for: direction)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case instruction
        case englishToChineseInstruction
        case chineseToEnglishInstruction
        case tone
        case createdAt
        case updatedAt
        case isBuiltIn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        instruction = try container.decode(String.self, forKey: .instruction)
        englishToChineseInstruction = try container.decodeIfPresent(
            String.self,
            forKey: .englishToChineseInstruction
        ) ?? instruction
        chineseToEnglishInstruction = try container.decodeIfPresent(
            String.self,
            forKey: .chineseToEnglishInstruction
        ) ?? instruction
        tone = try container.decode(String.self, forKey: .tone)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
    }

    static let interpreterID = UUID(uuidString: "4B7087C2-0CF1-4A9B-92B5-27152270A101")!
    static let translatorID = UUID(uuidString: "F5E1EDB9-A29B-4E57-8E3B-5D0D6C62B4D5")!
    static let literalTranslationID = UUID(uuidString: "64B62B0D-3661-4772-9F8C-8473709700B2")!
    static let conciseID = UUID(uuidString: "C2D38258-65EE-4B0A-BAC1-358111BC4FAE")!

    static var defaultPrompts: [PromptTemplate] {
        [
            PromptTemplate(
                id: translatorID,
                title: "极简翻译",
                instruction: PromptLanguageDirection.englishToChinese.fallbackInstruction,
                englishToChineseInstruction: PromptLanguageDirection.englishToChinese.fallbackInstruction,
                chineseToEnglishInstruction: PromptLanguageDirection.chineseToEnglish.fallbackInstruction,
                tone: "只输出译文",
                isBuiltIn: true
            ),
            PromptTemplate(
                id: interpreterID,
                title: "同声传译",
                instruction: "保持原意，优先给出自然、简洁、可直接展示给听众的译文。遇到不确定专有名词时保留原文。",
                englishToChineseInstruction: "把以下英文同声传译成自然中文，只输出译文：",
                chineseToEnglishInstruction: "Interpret the following Chinese into natural English. Output only the translation:",
                tone: "专业、流畅、低延迟",
                isBuiltIn: true
            ),
            PromptTemplate(
                id: literalTranslationID,
                title: "直译优先",
                instruction: "逐句翻译为目标语言，尽量保持原句结构和术语。不要补充上下文，不输出项目计划、待办或总结。",
                englishToChineseInstruction: "把以下英文直译成中文，保留原句结构和术语，只输出译文：",
                chineseToEnglishInstruction: "Translate the following Chinese literally into English, preserving structure and terms. Output only the translation:",
                tone: "忠实、克制、术语一致",
                isBuiltIn: true
            ),
            PromptTemplate(
                id: conciseID,
                title: "简洁翻译",
                instruction: "只输出译文，删除寒暄和重复表达，保留数字、日期和实体名称。",
                englishToChineseInstruction: "把以下英文翻译成简洁中文，只输出译文，保留数字、日期和实体名称：",
                chineseToEnglishInstruction: "Translate the following Chinese into concise English. Output only the translation and preserve numbers, dates, and entity names:",
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
    var isDeveloperModeEnabled: Bool

    static let defaultValue = AppSettings(
        mode: .translate,
        sourceLanguage: .englishUS,
        targetLanguage: .simplifiedChinese,
        selectedPromptID: PromptTemplate.translatorID,
        selectedEngine: .mock,
        sampling: .defaultValue,
        isProUnlocked: false,
        isDeveloperModeEnabled: false
    )

    init(
        mode: SessionMode,
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage,
        selectedPromptID: UUID,
        selectedEngine: ModelEngine,
        sampling: GenerationSampling,
        isProUnlocked: Bool,
        isDeveloperModeEnabled: Bool = false
    ) {
        self.mode = mode
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.selectedPromptID = selectedPromptID
        self.selectedEngine = selectedEngine
        self.sampling = sampling
        self.isProUnlocked = isProUnlocked
        self.isDeveloperModeEnabled = isDeveloperModeEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case sourceLanguage
        case targetLanguage
        case selectedPromptID
        case selectedEngine
        case sampling
        case isProUnlocked
        case isDeveloperModeEnabled
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
        isDeveloperModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isDeveloperModeEnabled) ?? false
    }
}

struct AppPersistenceSnapshot: Equatable, Codable, Sendable {
    var activeSession: TranslationSessionRecord?
    var history: [TranslationSessionRecord]
    var prompts: [PromptTemplate]
    var settings: AppSettings
}
