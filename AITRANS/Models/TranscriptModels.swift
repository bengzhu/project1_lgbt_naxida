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
    var decodingMode: String
    var decodingSeed: UInt32?

    init(
        prompt: String,
        output: String,
        errorCode: String?,
        decodingMode: String = ModelDecodingProfile.sampled.mode,
        decodingSeed: UInt32? = nil
    ) {
        self.prompt = prompt
        self.output = output
        self.errorCode = errorCode
        self.decodingMode = decodingMode
        self.decodingSeed = decodingSeed
    }
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

struct MangaGroundTruthEntry: Equatable, Codable, Sendable {
    var text: String
    var type: String

    static let dialogueType = "dialogue"
    static let decorativeType = "decorative"
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
    var probeRunMode: String
    var probeFastPathEnabled: Bool
    var skippedDiagnostics: [String]
    var preprocessing: MangaOverlayPreprocessingOptions
    var correction: MangaOverlayCorrectionOptions
    var diagnosticDecodingMode: String
    var diagnosticDecodingSeed: UInt32?
    var productionDecodingMode: String
    var productionDecodingSeed: UInt32?
    var visionNewAPIStatus: String
    var customLexiconEnabled: Bool
    var customLexicon: [String]

    static let defaultValue = MangaOverlayProbeConfiguration(
        status: "current pipeline uses bubble geometry as primary merge boundary for whole-page Vision OCR observations",
        currentBlockSource: "bubble-constrained whole-page OCR observations merged only within assigned bubble ID",
        probeRunMode: "full",
        probeFastPathEnabled: false,
        skippedDiagnostics: [],
        preprocessing: .defaultValue,
        correction: .defaultValue,
        diagnosticDecodingMode: ModelDecodingProfile.deterministic.mode,
        diagnosticDecodingSeed: ModelDecodingProfile.deterministic.seed,
        productionDecodingMode: ModelDecodingProfile.sampled.mode,
        productionDecodingSeed: nil,
        visionNewAPIStatus: "deployment target is iOS 17.0; RecognizeTextRequest needs @available guard and is not part of the main path",
        customLexiconEnabled: true,
        customLexicon: ["Senpai", "City Battler", "Tournament", "Ren", "Battler"]
    )
}

struct MangaOverlayProbeBlock: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var index: Int
    var bbox: [Double]
    var bubbleID: Int?
    var bubbleAssignmentMethod: String
    var crossBubbleMergeRejected: Bool
    var sliceIndex: Int?
    var sliceOverlapDeduped: Bool
    var rotationAngleUsed: Int
    var rawOcrText: String
    var ocrText: String
    var ocrConfidence: Float?
    var preprocessingEnabled: Bool
    var afterPreprocessingOcrText: String?
    var adaptivePreprocessingOcrText: String?
    var fixedPreprocessingOcrText: String?
    var cropPaddingX: Double?
    var cropPaddingY: Double?
    var cropClampedByBubble: Bool
    var cropCandidatePreservesRawWords: Bool
    var cropFallbackTriggered: Bool
    var cropFallbackReason: String?
    var cropStrategyUsed: String?
    var safeLayoutRect: [Double]?
    var safeLayoutSource: String?
    var safeLayoutSourceBeforeMask: String?
    var maskSafeRect: [Double]?
    var renderCollisionChecked: Bool
    var renderCollisionInitialOverflow: Bool
    var renderCollisionResolved: Bool
    var renderMaskCollisionChecked: Bool
    var renderMaskCollisionResolved: Bool
    var renderMaskOverflowPixelCount: Int
    var renderFontSize: Double?
    var renderMinFontSizeReached: Bool
    var renderTextTruncated: Bool
    var renderNonTransparentBounds: [Double]?
    var glyphMaskRect: [Double]?
    var glyphMaskPixelCount: Int
    var glyphMaskFillRects: [[Double]]
    var backgroundFillApplied: Bool
    var backgroundFillColor: [Double]?
    var backgroundColorStdDev: Double?
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
    var bestGroundTruthType: String?
    var groundTruthMatch: String
    var groundTruthMatchThreshold: Double
    var ocrGroundTruthSimilarity: Double?
    var ocrLegacySimilarity: Double?
    var wordOrderPreserved: Bool?
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

    enum CodingKeys: String, CodingKey {
        case id
        case index
        case bbox
        case bubbleID
        case bubbleAssignmentMethod
        case crossBubbleMergeRejected
        case sliceIndex
        case sliceOverlapDeduped
        case rotationAngleUsed
        case rawOcrText
        case ocrText
        case ocrConfidence
        case preprocessingEnabled
        case afterPreprocessingOcrText
        case adaptivePreprocessingOcrText
        case fixedPreprocessingOcrText
        case cropPaddingX
        case cropPaddingY
        case cropClampedByBubble
        case cropCandidatePreservesRawWords
        case cropFallbackTriggered
        case cropFallbackReason
        case cropStrategyUsed
        case safeLayoutRect
        case safeLayoutSource
        case safeLayoutSourceBeforeMask
        case maskSafeRect
        case renderCollisionChecked
        case renderCollisionInitialOverflow
        case renderCollisionResolved
        case renderMaskCollisionChecked
        case renderMaskCollisionResolved
        case renderMaskOverflowPixelCount
        case renderFontSize
        case renderMinFontSizeReached
        case renderTextTruncated
        case renderNonTransparentBounds
        case glyphMaskRect
        case glyphMaskPixelCount
        case glyphMaskFillRects
        case backgroundFillApplied
        case backgroundFillColor
        case backgroundColorStdDev
        case correctionEnabled
        case afterCorrectionText
        case correctionRejectedReason
        case correctionPrompt
        case correctionRawOutput
        case correctionErrorCode
        case deterministicCorrectionText
        case deterministicCorrectionAppliedRules
        case deterministicCorrectionSimilarity
        case deterministicCorrectionTranslationCandidate
        case deterministicCorrectionTranslationRawOutput
        case deterministicCorrectionTranslationPassed
        case deterministicCorrectionTranslationFailureDetail
        case finalTextUsedForTranslation
        case bestGroundTruthIndex
        case bestGroundTruthText
        case bestGroundTruthType
        case groundTruthMatch
        case groundTruthMatchThreshold
        case ocrGroundTruthSimilarity
        case ocrLegacySimilarity
        case wordOrderPreserved
        case ocrQualityLabel
        case translatedText
        case translationCandidate
        case rawOutputClassification
        case candidateClassification
        case failureCategory
        case prompt
        case rawOutput
        case errorCode
        case checks
        case failureReasons
        case qualityNotes
        case translationDecisionTrace
        case translationFailureDetail
        case ocrProbeNotes
        case blockPassed
    }

    init(
        id: UUID = UUID(),
        index: Int,
        bbox: [Double],
        bubbleID: Int? = nil,
        bubbleAssignmentMethod: String = "unassigned",
        crossBubbleMergeRejected: Bool = false,
        sliceIndex: Int? = nil,
        sliceOverlapDeduped: Bool = false,
        rotationAngleUsed: Int,
        ocrText: String,
        ocrConfidence: Float?,
        rawOcrText: String? = nil,
        preprocessingEnabled: Bool = false,
        afterPreprocessingOcrText: String? = nil,
        adaptivePreprocessingOcrText: String? = nil,
        fixedPreprocessingOcrText: String? = nil,
        cropPaddingX: Double? = nil,
        cropPaddingY: Double? = nil,
        cropClampedByBubble: Bool = false,
        cropCandidatePreservesRawWords: Bool = false,
        cropFallbackTriggered: Bool = false,
        cropFallbackReason: String? = nil,
        cropStrategyUsed: String? = nil,
        safeLayoutRect: [Double]? = nil,
        safeLayoutSource: String? = nil,
        safeLayoutSourceBeforeMask: String? = nil,
        maskSafeRect: [Double]? = nil,
        renderCollisionChecked: Bool = false,
        renderCollisionInitialOverflow: Bool = false,
        renderCollisionResolved: Bool = false,
        renderMaskCollisionChecked: Bool = false,
        renderMaskCollisionResolved: Bool = false,
        renderMaskOverflowPixelCount: Int = 0,
        renderFontSize: Double? = nil,
        renderMinFontSizeReached: Bool = false,
        renderTextTruncated: Bool = false,
        renderNonTransparentBounds: [Double]? = nil,
        glyphMaskRect: [Double]? = nil,
        glyphMaskPixelCount: Int = 0,
        glyphMaskFillRects: [[Double]] = [],
        backgroundFillApplied: Bool = false,
        backgroundFillColor: [Double]? = nil,
        backgroundColorStdDev: Double? = nil,
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
        bestGroundTruthType: String? = nil,
        groundTruthMatch: String = "unmatched",
        groundTruthMatchThreshold: Double = 0.42,
        ocrGroundTruthSimilarity: Double? = nil,
        ocrLegacySimilarity: Double? = nil,
        wordOrderPreserved: Bool? = nil,
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
        self.bubbleID = bubbleID
        self.bubbleAssignmentMethod = bubbleAssignmentMethod
        self.crossBubbleMergeRejected = crossBubbleMergeRejected
        self.sliceIndex = sliceIndex
        self.sliceOverlapDeduped = sliceOverlapDeduped
        self.rotationAngleUsed = rotationAngleUsed
        self.rawOcrText = rawOcrText ?? ocrText
        self.ocrText = ocrText
        self.ocrConfidence = ocrConfidence
        self.preprocessingEnabled = preprocessingEnabled
        self.afterPreprocessingOcrText = afterPreprocessingOcrText
        self.adaptivePreprocessingOcrText = adaptivePreprocessingOcrText
        self.fixedPreprocessingOcrText = fixedPreprocessingOcrText
        self.cropPaddingX = cropPaddingX
        self.cropPaddingY = cropPaddingY
        self.cropClampedByBubble = cropClampedByBubble
        self.cropCandidatePreservesRawWords = cropCandidatePreservesRawWords
        self.cropFallbackTriggered = cropFallbackTriggered
        self.cropFallbackReason = cropFallbackReason
        self.cropStrategyUsed = cropStrategyUsed
        self.safeLayoutRect = safeLayoutRect
        self.safeLayoutSource = safeLayoutSource
        self.safeLayoutSourceBeforeMask = safeLayoutSourceBeforeMask
        self.maskSafeRect = maskSafeRect
        self.renderCollisionChecked = renderCollisionChecked
        self.renderCollisionInitialOverflow = renderCollisionInitialOverflow
        self.renderCollisionResolved = renderCollisionResolved
        self.renderMaskCollisionChecked = renderMaskCollisionChecked
        self.renderMaskCollisionResolved = renderMaskCollisionResolved
        self.renderMaskOverflowPixelCount = renderMaskOverflowPixelCount
        self.renderFontSize = renderFontSize
        self.renderMinFontSizeReached = renderMinFontSizeReached
        self.renderTextTruncated = renderTextTruncated
        self.renderNonTransparentBounds = renderNonTransparentBounds
        self.glyphMaskRect = glyphMaskRect
        self.glyphMaskPixelCount = glyphMaskPixelCount
        self.glyphMaskFillRects = glyphMaskFillRects
        self.backgroundFillApplied = backgroundFillApplied
        self.backgroundFillColor = backgroundFillColor
        self.backgroundColorStdDev = backgroundColorStdDev
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
        self.bestGroundTruthType = bestGroundTruthType
        self.groundTruthMatch = groundTruthMatch
        self.groundTruthMatchThreshold = groundTruthMatchThreshold
        self.ocrGroundTruthSimilarity = ocrGroundTruthSimilarity
        self.ocrLegacySimilarity = ocrLegacySimilarity
        self.wordOrderPreserved = wordOrderPreserved
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(index, forKey: .index)
        try container.encode(bbox, forKey: .bbox)
        try container.encode(bubbleID, forKey: .bubbleID)
        try container.encode(bubbleAssignmentMethod, forKey: .bubbleAssignmentMethod)
        try container.encode(crossBubbleMergeRejected, forKey: .crossBubbleMergeRejected)
        try container.encode(sliceIndex, forKey: .sliceIndex)
        try container.encode(sliceOverlapDeduped, forKey: .sliceOverlapDeduped)
        try container.encode(rotationAngleUsed, forKey: .rotationAngleUsed)
        try container.encode(rawOcrText, forKey: .rawOcrText)
        try container.encode(ocrText, forKey: .ocrText)
        try container.encodeIfPresent(ocrConfidence, forKey: .ocrConfidence)
        try container.encode(preprocessingEnabled, forKey: .preprocessingEnabled)
        try container.encodeIfPresent(afterPreprocessingOcrText, forKey: .afterPreprocessingOcrText)
        try container.encodeIfPresent(adaptivePreprocessingOcrText, forKey: .adaptivePreprocessingOcrText)
        try container.encodeIfPresent(fixedPreprocessingOcrText, forKey: .fixedPreprocessingOcrText)
        try container.encodeIfPresent(cropPaddingX, forKey: .cropPaddingX)
        try container.encodeIfPresent(cropPaddingY, forKey: .cropPaddingY)
        try container.encode(cropClampedByBubble, forKey: .cropClampedByBubble)
        try container.encode(cropCandidatePreservesRawWords, forKey: .cropCandidatePreservesRawWords)
        try container.encode(cropFallbackTriggered, forKey: .cropFallbackTriggered)
        try container.encodeIfPresent(cropFallbackReason, forKey: .cropFallbackReason)
        try container.encodeIfPresent(cropStrategyUsed, forKey: .cropStrategyUsed)
        try container.encodeIfPresent(safeLayoutRect, forKey: .safeLayoutRect)
        try container.encodeIfPresent(safeLayoutSource, forKey: .safeLayoutSource)
        try container.encodeIfPresent(safeLayoutSourceBeforeMask, forKey: .safeLayoutSourceBeforeMask)
        try container.encodeIfPresent(maskSafeRect, forKey: .maskSafeRect)
        try container.encode(renderCollisionChecked, forKey: .renderCollisionChecked)
        try container.encode(renderCollisionInitialOverflow, forKey: .renderCollisionInitialOverflow)
        try container.encode(renderCollisionResolved, forKey: .renderCollisionResolved)
        try container.encode(renderMaskCollisionChecked, forKey: .renderMaskCollisionChecked)
        try container.encode(renderMaskCollisionResolved, forKey: .renderMaskCollisionResolved)
        try container.encode(renderMaskOverflowPixelCount, forKey: .renderMaskOverflowPixelCount)
        try container.encodeIfPresent(renderFontSize, forKey: .renderFontSize)
        try container.encode(renderMinFontSizeReached, forKey: .renderMinFontSizeReached)
        try container.encode(renderTextTruncated, forKey: .renderTextTruncated)
        try container.encodeIfPresent(renderNonTransparentBounds, forKey: .renderNonTransparentBounds)
        try container.encodeIfPresent(glyphMaskRect, forKey: .glyphMaskRect)
        try container.encode(glyphMaskPixelCount, forKey: .glyphMaskPixelCount)
        try container.encode(glyphMaskFillRects, forKey: .glyphMaskFillRects)
        try container.encode(backgroundFillApplied, forKey: .backgroundFillApplied)
        try container.encodeIfPresent(backgroundFillColor, forKey: .backgroundFillColor)
        try container.encodeIfPresent(backgroundColorStdDev, forKey: .backgroundColorStdDev)
        try container.encode(correctionEnabled, forKey: .correctionEnabled)
        try container.encodeIfPresent(afterCorrectionText, forKey: .afterCorrectionText)
        try container.encodeIfPresent(correctionRejectedReason, forKey: .correctionRejectedReason)
        try container.encodeIfPresent(correctionPrompt, forKey: .correctionPrompt)
        try container.encodeIfPresent(correctionRawOutput, forKey: .correctionRawOutput)
        try container.encodeIfPresent(correctionErrorCode, forKey: .correctionErrorCode)
        try container.encodeIfPresent(deterministicCorrectionText, forKey: .deterministicCorrectionText)
        try container.encode(deterministicCorrectionAppliedRules, forKey: .deterministicCorrectionAppliedRules)
        try container.encodeIfPresent(deterministicCorrectionSimilarity, forKey: .deterministicCorrectionSimilarity)
        try container.encodeIfPresent(deterministicCorrectionTranslationCandidate, forKey: .deterministicCorrectionTranslationCandidate)
        try container.encodeIfPresent(deterministicCorrectionTranslationRawOutput, forKey: .deterministicCorrectionTranslationRawOutput)
        try container.encodeIfPresent(deterministicCorrectionTranslationPassed, forKey: .deterministicCorrectionTranslationPassed)
        try container.encodeIfPresent(deterministicCorrectionTranslationFailureDetail, forKey: .deterministicCorrectionTranslationFailureDetail)
        try container.encode(finalTextUsedForTranslation, forKey: .finalTextUsedForTranslation)
        try container.encodeIfPresent(bestGroundTruthIndex, forKey: .bestGroundTruthIndex)
        try container.encodeIfPresent(bestGroundTruthText, forKey: .bestGroundTruthText)
        try container.encodeIfPresent(bestGroundTruthType, forKey: .bestGroundTruthType)
        try container.encode(groundTruthMatch, forKey: .groundTruthMatch)
        try container.encode(groundTruthMatchThreshold, forKey: .groundTruthMatchThreshold)
        try container.encodeIfPresent(ocrGroundTruthSimilarity, forKey: .ocrGroundTruthSimilarity)
        try container.encodeIfPresent(ocrLegacySimilarity, forKey: .ocrLegacySimilarity)
        try container.encodeIfPresent(wordOrderPreserved, forKey: .wordOrderPreserved)
        try container.encodeIfPresent(ocrQualityLabel, forKey: .ocrQualityLabel)
        try container.encode(translatedText, forKey: .translatedText)
        try container.encode(translationCandidate, forKey: .translationCandidate)
        try container.encode(rawOutputClassification, forKey: .rawOutputClassification)
        try container.encode(candidateClassification, forKey: .candidateClassification)
        try container.encode(failureCategory, forKey: .failureCategory)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(rawOutput, forKey: .rawOutput)
        try container.encodeIfPresent(errorCode, forKey: .errorCode)
        try container.encode(checks, forKey: .checks)
        try container.encode(failureReasons, forKey: .failureReasons)
        try container.encode(qualityNotes, forKey: .qualityNotes)
        try container.encode(translationDecisionTrace, forKey: .translationDecisionTrace)
        try container.encodeIfPresent(translationFailureDetail, forKey: .translationFailureDetail)
        try container.encode(ocrProbeNotes, forKey: .ocrProbeNotes)
        try container.encode(blockPassed, forKey: .blockPassed)
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
    var probeContactSheetImage: String?
    var cleanTextDiagnosticFile: String?

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
        bubbleTextOverlayImage: String? = nil,
        probeContactSheetImage: String? = nil,
        cleanTextDiagnosticFile: String? = nil
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
        self.probeContactSheetImage = probeContactSheetImage
        self.cleanTextDiagnosticFile = cleanTextDiagnosticFile
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
    var averageCoreDialogueOCRSimilarity: Double
    var averageDecorativeOCRSimilarity: Double
    var groundTruthMatchedBlocks: Int
    var groundTruthUnmatchedBlocks: Int
    var wordOrderFailedBlocks: [Int]
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
    var repeatedKeywordFailures: [String: Int]
    var crossBubbleMergeRejectedBlocks: [Int]
    var bubbleAssignedBlocks: Int
    var bubbleUnassignedBlocks: Int
    var safeLayoutRectBlocks: Int
    var renderCollisionCheckedBlocks: Int
    var renderCollisionInitialOverflowBlocks: [Int]
    var renderCollisionResolvedBlocks: [Int]
    var renderCollisionUnresolvedBlocks: [Int]
    var renderMinFontSizeReachedBlocks: [Int]
    var renderTextTruncatedBlocks: [Int]
    var glyphMaskBlocks: Int
    var backgroundFillAppliedBlocks: [Int]
    var backgroundFillSkippedBlocks: [Int]

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
        averageCoreDialogueOCRSimilarity: 0,
        averageDecorativeOCRSimilarity: 0,
        groundTruthMatchedBlocks: 0,
        groundTruthUnmatchedBlocks: 0,
        wordOrderFailedBlocks: [],
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
        deterministicCorrectionTranslationFailedBlocks: [],
        repeatedKeywordFailures: [:],
        crossBubbleMergeRejectedBlocks: [],
        bubbleAssignedBlocks: 0,
        bubbleUnassignedBlocks: 0,
        safeLayoutRectBlocks: 0,
        renderCollisionCheckedBlocks: 0,
        renderCollisionInitialOverflowBlocks: [],
        renderCollisionResolvedBlocks: [],
        renderCollisionUnresolvedBlocks: [],
        renderMinFontSizeReachedBlocks: [],
        renderTextTruncatedBlocks: [],
        glyphMaskBlocks: 0,
        backgroundFillAppliedBlocks: [],
        backgroundFillSkippedBlocks: []
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
    var matchedGroundTruthCount: Int
    var unmatchedBlockCount: Int
}

struct MangaOverlayBubbleResult: Equatable, Codable, Sendable {
    var index: Int
    var bbox: [Double]
    var bubbleID: Int?
    var source: String
    var text: String
    var bestGroundTruthIndex: Int?
    var bestGroundTruthType: String?
    var groundTruthMatch: String
    var bestSimilarity: Double
    var legacySimilarity: Double?
    var wordOrderPreserved: Bool?
}

struct MangaOverlayFrameworkComparison: Equatable, Codable, Sendable {
    var groundTruth: [MangaGroundTruthEntry]
    var comparisonUnit: String
    var wholePage: MangaOverlayFrameworkMetrics
    var bubbleFirst: MangaOverlayFrameworkMetrics
    var blocksOnlyInWholePage: [String]
    var blocksOnlyInBubbleFirst: [String]
    var blocksFoundByBoth: Int
    var matchedGroundTruthUnionCount: Int
    var consistencyPassed: Bool
    var consistencyWarnings: [String]
    var bubbleResults: [MangaOverlayBubbleResult]
    var notes: [String]
}

struct MangaOverlayFusionCandidate: Equatable, Codable, Sendable {
    var source: String
    var sourceIndex: Int
    var text: String
    var bbox: [Double]
    var bubbleID: Int?
    var confidence: Float?
    var qualityScore: Double
    var selected: Bool
    var rejectionReason: String?
}

struct MangaOverlayFusionResult: Equatable, Codable, Sendable {
    var fusedBlockIndex: Int
    var selectedSource: String
    var selectedText: String
    var selectedBBox: [Double]
    var selectedBubbleID: Int?
    var sourceBlockIndex: Int?
    var bubbleResultIndex: Int?
    var competingCandidates: [MangaOverlayFusionCandidate]
    var dedupeReason: String
    var replacementReason: String?
    var rejectedCandidates: [MangaOverlayFusionCandidate]
}

struct MangaOverlayPostFusionRejectedBlock: Equatable, Codable, Sendable {
    var originalFusedBlockIndex: Int
    var source: String
    var sourceBlockIndex: Int?
    var bubbleResultIndex: Int?
    var bubbleID: Int?
    var text: String
    var bbox: [Double]
    var reason: String
    var relatedFusedBlockIndex: Int?
    var relatedKeptBlockIndex: Int?
    var relatedText: String?
    var relatedBBox: [Double]?
    var qualityScore: Double?
    var protectedTextMatched: Bool?
    var evidence: [String]?
}

struct MangaOverlayPostFusionCleanupReport: Equatable, Codable, Sendable {
    var applied: Bool
    var blockCountBeforeCleanup: Int
    var blockCountAfterCleanup: Int
    var rejectedBlockCount: Int
    var rejectedBlocks: [MangaOverlayPostFusionRejectedBlock]
    var preservedKeyTexts: [String]
    var missingKeyTexts: [String]
    var warnings: [String]
    var notes: [String]
}

struct MangaOverlayInternalStructureBottleneckBlock: Equatable, Codable, Sendable {
    var blockIndex: Int
    var groundTruthMatch: String
    var groundTruthType: String?
    var ocrGroundTruthSimilarity: Double?
    var wordOrderPreserved: Bool?
    var bubbleID: Int?
    var bbox: [Double]
    var finalTextUsedForTranslation: String
    var failureCategory: String
    var blockPassed: Bool
    var primaryBottleneck: String
    var secondaryBottlenecks: [String]
    var recommendedNextAction: String
    var evidence: [String]
    var mustNotPromoteReasons: [String]
}

struct MangaOverlayInternalStructureBottleneckReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var evaluatedBlockCount: Int
    var primaryBottleneckBreakdown: [String: Int]
    var recommendedActionBreakdown: [String: Int]
    var dialogueBottleneckBreakdown: [String: Int]
    var decorativeBottleneckBreakdown: [String: Int]
    var ocrInputSuspectBlocks: [Int]
    var duplicateOrFragmentBlocks: [Int]
    var modelTranslationQualityBlocks: [Int]
    var cropCandidateBlockedBlocks: [Int]
    var bubbleSplitOrAssignmentBlocks: [Int]
    var renderOnlyBlocks: [Int]
    var passedBlocks: [Int]
    var postFusionRejectedDuplicateOrFragmentBlocks: [Int]
    var blockSummaries: [MangaOverlayInternalStructureBottleneckBlock]
    var notes: [String]
}

struct MangaRoutingDrivenTranslationComparisonCase: Equatable, Codable, Sendable {
    var blockIndex: Int
    var routingPrimaryBottleneck: String
    var routingRecommendedAction: String
    var sourceText: String
    var controlCandidate: String
    var controlPassed: Bool
    var controlFailureCategory: String
    var controlFailureReasons: [String]
    var variantID: String
    var variantPrompt: String
    var variantRawOutput: String
    var variantCandidate: String
    var variantRawOutputClassification: String
    var variantCandidateClassification: String
    var variantPassed: Bool
    var variantFailureReasons: [String]
    var improvementCategory: String
    var latinLeakReduced: Bool
    var emptyOutputFixed: Bool
    var placeholderFixed: Bool
    var shortChineseFixed: Bool
    var diagnosticOnly: Bool
    var mustNotPromoteReasons: [String]
}

struct MangaRoutingDrivenTranslationComparisonReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var decodingMode: String
    var decodingSeed: UInt32?
    var variantID: String
    var candidateSelectionRule: String
    var evaluatedCaseCount: Int
    var targetBlockIndexes: [Int]
    var controlPassedCount: Int
    var variantPassedCount: Int
    var passedButControlFailedBlocks: [Int]
    var worseThanControlBlocks: [Int]
    var emptyOutputFixedBlocks: [Int]
    var placeholderFixedBlocks: [Int]
    var latinLeakReducedBlocks: [Int]
    var improvementBreakdown: [String: Int]
    var cases: [MangaRoutingDrivenTranslationComparisonCase]
    var notes: [String]
}

struct MangaOCRCharacterDamageAuditCase: Equatable, Codable, Sendable {
    var blockIndex: Int
    var groundTruthMatch: String
    var groundTruthType: String?
    var ocrGroundTruthSimilarity: Double?
    var wordOrderPreserved: Bool?
    var finalTextUsedForTranslation: String
    var bestGroundTruthText: String?
    var damagedTokens: [String]
    var missingGroundTruthTokens: [String]
    var extraOcrTokens: [String]
    var suspectedSubstitutions: [String]
    var repeatedKeywordDamage: [String]
    var lineBreakRisk: Bool
    var bubbleID: Int?
    var textBoxEvidenceSummary: String?
    var segmentMaskEvidenceSummary: String?
    var cropBlockers: [String]
    var recommendedNextAction: String
    var diagnosticOnly: Bool
    var mustNotPromoteReasons: [String]
}

struct MangaOCRCharacterDamageAuditReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var evaluatedBlockCount: Int
    var targetBlockIndexes: [Int]
    var damageTokenFrequency: [String: Int]
    var missingTokenFrequency: [String: Int]
    var substitutionFrequency: [String: Int]
    var repeatedKeywordDamage: [String: Int]
    var lineBreakRiskBlocks: [Int]
    var cropBlockedBlocks: [Int]
    var textBoxOrSegmentEvidenceBlocks: [Int]
    var recommendedActionBreakdown: [String: Int]
    var cases: [MangaOCRCharacterDamageAuditCase]
    var notes: [String]
}

struct MangaReadingOrderStructureAuditCase: Equatable, Codable, Sendable {
    var blockIndex: Int
    var currentOrderIndex: Int
    var proposedReadingOrderIndex: Int
    var orderChanged: Bool
    var orderConfidence: Double
    var orderRiskFlags: [String]
    var bubbleID: Int?
    var maskDominantBubbleID: Int?
    var bubbleIDConsistent: Bool
    var bubbleGroupID: String
    var sameBubbleSiblingBlockIndexes: [Int]
    var bbox: [Double]
    var safeLayoutRect: [Double]?
    var groundTruthMatch: String
    var groundTruthType: String?
    var ocrGroundTruthSimilarity: Double?
    var finalTextUsedForTranslation: String
    var primaryBottleneck: String?
    var translationFailureCategory: String
    var textBoxEvidenceLevel: String
    var segmentMaskEvidenceLevel: String
    var bubbleAssignmentRisk: String
    var splitOrMergeRisk: String
    var duplicateOrFragmentRisk: String
    var decorativeProtectionApplied: Bool
    var recommendedStructureAction: String
    var diagnosticOnly: Bool
    var mustNotPromoteReasons: [String]
}

struct MangaReadingOrderStructureAuditReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var evaluatedBlockCount: Int
    var currentOrderRule: String
    var proposedOrderRule: String
    var orderChangedBlocks: [Int]
    var lowConfidenceOrderBlocks: [Int]
    var bubbleGroupCount: Int
    var multiBlockBubbleGroups: [String: [Int]]
    var unassignedBlocks: [Int]
    var maskConflictBlocks: [Int]
    var correctionRecommendedBlocks: [Int]
    var splitRiskBlocks: [Int]
    var duplicateOrFragmentRiskBlocks: [Int]
    var decorativeProtectedBlocks: [Int]
    var keyDialogueProtectedBlocks: [Int]
    var textBoxEvidenceBreakdown: [String: Int]
    var segmentMaskEvidenceBreakdown: [String: Int]
    var bubbleAssignmentRiskBreakdown: [String: Int]
    var splitOrMergeRiskBreakdown: [String: Int]
    var duplicateOrFragmentRiskBreakdown: [String: Int]
    var recommendedStructureActionBreakdown: [String: Int]
    var cases: [MangaReadingOrderStructureAuditCase]
    var notes: [String]
}

struct MangaStructureActionCandidateMetrics: Equatable, Codable, Sendable {
    var orderIndexDelta: Int?
    var bubbleIDBefore: Int?
    var bubbleIDAfter: Int?
    var bubbleConsistencyBefore: Bool?
    var bubbleConsistencyAfter: Bool?
    var maskCoverageBefore: Double?
    var maskCoverageAfter: Double?
    var safeLayoutAreaBefore: Double?
    var safeLayoutAreaAfter: Double?
    var renderOverflowBefore: Int?
    var renderOverflowAfter: Int?
    var siblingOverlapBefore: Double?
    var siblingOverlapAfter: Double?
    var ocrSimilarityBefore: Double?
    var ocrSimilarityAfter: Double?
    var translationFailureCategoryBefore: String?
    var translationFailureCategoryAfter: String?
}

struct MangaStructureActionCandidateDelta: Equatable, Codable, Sendable {
    var orderIndexDelta: Int?
    var bubbleConsistencyChanged: Bool?
    var maskCoverageDelta: Double?
    var safeLayoutAreaDelta: Double?
    var renderOverflowDelta: Int?
    var siblingOverlapDelta: Double?
    var ocrSimilarityDelta: Double?
    var translationFailureCategoryChanged: Bool?
    var summary: [String]
}

struct MangaStructureActionCandidate: Equatable, Codable, Sendable {
    var candidateID: String
    var blockIndex: Int
    var candidateType: String
    var sourceRecommendedAction: String
    var sourceRisks: [String]
    var inputSignals: [String]
    var plannedOperation: String
    var expectedBenefit: String
    var executionMode: String
    var diagnosticOnly: Bool
    var groundTruthUsedForPlanning: Bool
    var wouldChangeMainFlow: Bool
    var mustNotPromoteReasons: [String]
    var executed: Bool
    var executionSkippedReason: String?
    var controlMetrics: MangaStructureActionCandidateMetrics
    var shadowMetrics: MangaStructureActionCandidateMetrics
    var delta: MangaStructureActionCandidateDelta
    var promotionVerdict: String
    var promotionBlockers: [String]
    var recommendedNextStep: String
}

struct MangaStructureActionCandidateCase: Equatable, Codable, Sendable {
    var blockIndex: Int
    var sourceRecommendedAction: String
    var candidateCount: Int
    var executedCandidateCount: Int
    var skippedCandidateCount: Int
    var candidateTypes: [String]
    var promotionVerdicts: [String]
    var recommendedNextSteps: [String]
    var candidates: [MangaStructureActionCandidate]
}

struct MangaStructureActionCandidateReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var evaluatedBlockCount: Int
    var candidateCount: Int
    var executedCandidateCount: Int
    var skippedCandidateCount: Int
    var candidateTypeBreakdown: [String: Int]
    var promotionVerdictBreakdown: [String: Int]
    var recommendedNextStepBreakdown: [String: Int]
    var reportOnlyWouldImproveBlocks: [Int]
    var blockedBlocks: [Int]
    var needsRealArtifactBlocks: [Int]
    var renderReflowCandidateBlocks: [Int]
    var bubbleSplitCandidateBlocks: [Int]
    var bubbleAssignmentReviewBlocks: [Int]
    var duplicateProtectionBlocks: [Int]
    var manualReviewBlocks: [Int]
    var cases: [MangaStructureActionCandidateCase]
    var notes: [String]
}

struct MangaKoharuArtifactGateCheck: Equatable, Codable, Sendable {
    var checkName: String
    var passed: Bool
    var severity: String
    var evidence: [String]
    var affectedBlocks: [Int]
    var recommendedNextAction: String
    var groundTruthUsedForDecision: Bool
}

struct MangaKoharuArtifactDependencyEdge: Equatable, Codable, Sendable {
    var fromStage: String
    var toStage: String
    var required: Bool
    var artifactKind: String
    var available: Bool
    var consumer: String
    var missingReason: String?
    var diagnosticOnly: Bool
    var wouldChangeMainFlow: Bool
}

struct MangaKoharuArtifactStageSummary: Equatable, Codable, Sendable {
    var stageName: String
    var artifactKind: String
    var status: String
    var producedBy: [String]
    var consumedBy: [String]
    var blockCount: Int
    var readyBlockCount: Int
    var blockedBlockCount: Int
    var proxyOnlyBlockCount: Int
    var missingBlockCount: Int
    var primaryGateChecks: [MangaKoharuArtifactGateCheck]
    var notes: [String]
}

struct MangaKoharuArtifactStageTrace: Equatable, Codable, Sendable {
    var stageName: String
    var status: String
    var artifactKind: String
    var sourceReport: String
    var sourceIDs: [String]
    var confidence: Double?
    var gateChecks: [MangaKoharuArtifactGateCheck]
    var blockers: [String]
    var downstreamImpact: [String]
    var diagnosticOnly: Bool
    var wouldChangeMainFlow: Bool
}

struct MangaKoharuArtifactBlockTrace: Equatable, Codable, Sendable {
    var blockIndex: Int
    var groundTruthMatch: String
    var bestGroundTruthType: String?
    var ocrSimilarityForEvaluation: Double?
    var failureCategory: String
    var blockPassed: Bool
    var bubbleID: Int?
    var firstBlockingStage: String
    var firstBlockingReason: String
    var downstreamImpacts: [String]
    var stageTraces: [MangaKoharuArtifactStageTrace]
    var structureActionCandidateVerdicts: [String]
    var recommendedNextAction: String
}

struct MangaKoharuArtifactDAGReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var pipelineName: String
    var evaluatedBlockCount: Int
    var stageCount: Int
    var edgeCount: Int
    var stageStatusBreakdown: [String: Int]
    var artifactKindBreakdown: [String: Int]
    var firstBlockingStageBreakdown: [String: Int]
    var downstreamImpactBreakdown: [String: Int]
    var readyStages: [String]
    var proxyOnlyStages: [String]
    var missingRequiredStages: [String]
    var blockedStages: [String]
    var realArtifactGateVerdict: String
    var realArtifactGateNextAction: String
    var blocksNeedingRealTextBoxes: [Int]
    var blocksNeedingRealBubbleMask: [Int]
    var blocksNeedingRealSegmentMask: [Int]
    var blocksStoppedByOCRCropEvidence: [Int]
    var blocksStoppedByTranslationModelQuality: [Int]
    var blocksWithRenderOnlyIssues: [Int]
    var dependencyEdges: [MangaKoharuArtifactDependencyEdge]
    var stageSummaries: [MangaKoharuArtifactStageSummary]
    var blockTraces: [MangaKoharuArtifactBlockTrace]
    var notes: [String]
}

struct MangaKoharuPromotionGate: Equatable, Codable, Sendable {
    var gateName: String
    var scope: String
    var requiredForPromotion: Bool
    var currentStatus: String
    var evidence: [String]
    var threshold: String
    var affectedBlocks: [Int]
    var failureMeans: String
    var groundTruthUsedForDecision: Bool
}

struct MangaKoharuStageConformanceCheck: Equatable, Codable, Sendable {
    var checkName: String
    var passed: Bool
    var evidence: [String]
    var requiredForPromotion: Bool
    var groundTruthUsedForDecision: Bool
}

struct MangaKoharuStageGapSummary: Equatable, Codable, Sendable {
    var canonicalStage: String
    var currentAITRANSStage: String
    var currentCapability: String
    var artifactKind: String
    var sourceReports: [String]
    var gapCategory: String
    var replicationReadiness: String
    var minimumRequiredInputs: [String]
    var availableEvidence: [String]
    var missingEvidence: [String]
    var affectedBlocks: [Int]
    var primaryDownstreamImpact: String
    var promotionGates: [MangaKoharuPromotionGate]
    var conformanceChecks: [MangaKoharuStageConformanceCheck]
    var stopConditions: [String]
    var recommendedWorkPackageID: String
    var groundTruthUsedForPlanning: Bool
    var diagnosticOnly: Bool
    var wouldChangeMainFlow: Bool
}

struct MangaKoharuReplicationWorkPackage: Equatable, Codable, Sendable {
    var workPackageID: String
    var title: String
    var priority: String
    var targetStages: [String]
    var targetBlocks: [Int]
    var inputArtifactsRequired: [String]
    var canRunInCIFast: Bool
    var requiresFullProbe: Bool
    var requiresRealExternalArtifact: Bool
    var expectedMetricMovement: [String]
    var promotionGates: [MangaKoharuPromotionGate]
    var rollbackOrStopConditions: [String]
    var nonGoals: [String]
    var recommendedBranchName: String
}

struct MangaKoharuBlockReplicationPlan: Equatable, Codable, Sendable {
    var blockIndex: Int
    var groundTruthMatch: String
    var bestGroundTruthType: String?
    var ocrSimilarityForEvaluation: Double?
    var blockPassed: Bool
    var failureCategory: String
    var bubbleID: Int?
    var firstBlockingStageFromDAG: String
    var primaryGapCategory: String
    var targetCanonicalStage: String
    var recommendedWorkPackageID: String
    var minimumEvidenceToCollect: [String]
    var mustNotPromoteReasons: [String]
    var canBeEvaluatedInCIFast: Bool
    var requiresFullProbe: Bool
    var requiresRealExternalArtifact: Bool
    var nextAction: String
}

struct MangaKoharuStageGapReplicationReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var referencePipeline: String
    var evaluatedBlockCount: Int
    var canonicalStageCount: Int
    var gapCount: Int
    var workPackageCount: Int
    var stageCapabilityBreakdown: [String: Int]
    var gapCategoryBreakdown: [String: Int]
    var replicationReadinessBreakdown: [String: Int]
    var promotionGateBreakdown: [String: Int]
    var blockedByRealArtifactStages: [String]
    var blockedByOCRStages: [String]
    var blockedByBubbleSegmentationStages: [String]
    var blockedBySegmentMaskStages: [String]
    var blockedByTranslationModelStages: [String]
    var renderReadyStages: [String]
    var stopTuningStages: [String]
    var readyForShadowOnlyStages: [String]
    var mustWaitForExternalArtifactStages: [String]
    var stageGaps: [MangaKoharuStageGapSummary]
    var workPackages: [MangaKoharuReplicationWorkPackage]
    var blockPlans: [MangaKoharuBlockReplicationPlan]
    var notes: [String]
}

struct MangaKoharuNativeMetricSignal: Equatable, Codable, Sendable {
    var name: String
    var value: String
    var sourceReport: String
    var groundTruthFreeDecisionSignal: Bool
    var groundTruthUsedForEvaluationOnly: Bool
}

struct MangaKoharuNativeStageScorecard: Equatable, Codable, Sendable {
    var stageName: String
    var referenceKoharuArtifact: String
    var nativeStatus: String
    var decisionSignals: [MangaKoharuNativeMetricSignal]
    var evaluationSignals: [MangaKoharuNativeMetricSignal]
    var primaryGateStatus: String
    var primaryBottleneck: String
    var affectedBlocks: [Int]
    var stopLocalTuning: Bool
    var nextWorkItemID: String
    var groundTruthUsedForEvaluationOnly: Bool
    var groundTruthUsedForDecision: Bool
    var diagnosticOnly: Bool
    var wouldChangeMainFlow: Bool
}

struct MangaKoharuNativeGateLedgerEntry: Equatable, Codable, Sendable {
    var gateID: String
    var gateName: String
    var scope: String
    var status: String
    var requiredForMainFlowPromotion: Bool
    var decisionSignals: [MangaKoharuNativeMetricSignal]
    var evaluationSignals: [MangaKoharuNativeMetricSignal]
    var threshold: String
    var affectedBlocks: [Int]
    var failureMeans: String
    var recommendedAction: String
    var groundTruthUsedForDecision: Bool
}

struct MangaKoharuNativeBlockScorecard: Equatable, Codable, Sendable {
    var blockIndex: Int
    var groundTruthMatch: String
    var bestGroundTruthType: String?
    var ocrSimilarityForEvaluation: Double?
    var blockPassed: Bool
    var failureCategory: String
    var bubbleID: Int?
    var primaryNativeStage: String
    var primaryBottleneck: String
    var recommendedPriority: String
    var prioritySignals: [String]
    var priorityUsedGroundTruth: Bool
    var ocrGateStatus: String
    var bubbleGateStatus: String
    var segmentGateStatus: String
    var translationGateStatus: String
    var renderGateStatus: String
    var stopLocalCropOrLineTuning: Bool
    var stopEvidence: [String]
    var mustNotPromoteReasons: [String]
    var recommendedWorkItemID: String
    var nextAction: String
}

struct MangaKoharuNativeWorkItem: Equatable, Codable, Sendable {
    var workItemID: String
    var title: String
    var priority: String
    var targetStages: [String]
    var targetBlocks: [Int]
    var whyNow: String
    var decisionSignals: [MangaKoharuNativeMetricSignal]
    var evaluationSignals: [MangaKoharuNativeMetricSignal]
    var canRunInCIFast: Bool
    var requiresFullProbe: Bool
    var requiresExternalArtifact: Bool
    var expectedMetricMovement: [String]
    var blockedByGates: [String]
    var stopConditions: [String]
    var nonGoals: [String]
    var suggestedBranchName: String
}

struct MangaKoharuNativeReplicationScoreboardReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var source: String
    var referencePipeline: String
    var evaluatedBlockCount: Int
    var stageScorecardCount: Int
    var gateCount: Int
    var workItemCount: Int
    var externalArtifactsRequiredForThisReport: Bool
    var groundTruthUsedForEvaluationOnly: Bool
    var groundTruthUsedForDecision: Bool
    var stageStatusBreakdown: [String: Int]
    var gateStatusBreakdown: [String: Int]
    var blockPrimaryBottleneckBreakdown: [String: Int]
    var recommendedPriorityBreakdown: [String: Int]
    var stopLocalTuningBlocks: [Int]
    var nativeReadyStages: [String]
    var nativeProxyReadyStages: [String]
    var shadowBlockedStages: [String]
    var modelLimitedStages: [String]
    var renderStableStages: [String]
    var stageScorecards: [MangaKoharuNativeStageScorecard]
    var gateLedger: [MangaKoharuNativeGateLedgerEntry]
    var blockScorecards: [MangaKoharuNativeBlockScorecard]
    var recommendedNextWorkItems: [MangaKoharuNativeWorkItem]
    var notes: [String]
}

struct MangaNativeTextBoxProxySignal: Equatable, Codable, Sendable {
    var name: String
    var value: String
    var sourceReport: String
    var groundTruthFreeDecisionSignal: Bool
    var groundTruthUsedForEvaluationOnly: Bool
}

struct MangaNativeTextBoxProxyCandidateLedger: Equatable, Codable, Sendable {
    var candidateID: String
    var blockIndex: Int
    var source: String
    var bbox: [Double]
    var clampSource: String?
    var bubbleID: Int?
    var textPreview: String?
    var rawWordsPreserved: Bool?
    var protectedKeywordsPreserved: Bool?
    var wordCountDelta: Int?
    var bubbleContained: Bool?
    var segmentMaskSupported: Bool?
    var introducedLikelyOCRError: Bool
    var promotionVerdict: String
    var promotionBlockers: [String]
    var reportOnlyRank: Int
    var groundTruthUsedForDecision: Bool
    var wouldChangeMainFlow: Bool
}

struct MangaNativeTextBoxProxyBlockLedger: Equatable, Codable, Sendable {
    var blockIndex: Int
    var bubbleID: Int?
    var failureCategory: String
    var blockPassed: Bool
    var qualityStatus: String
    var primaryFreezeReason: String?
    var candidateSources: [String]
    var candidateCount: Int
    var bestReportOnlyCandidateID: String?
    var rawWordPreservationStatus: String
    var protectedKeywordStatus: String
    var wordOrderStatus: String
    var bubbleConstraintStatus: String
    var segmentMaskConstraintStatus: String
    var ocrDamageStatus: String
    var translationModelFloorStatus: String
    var renderStatus: String
    var stoplistHit: Bool
    var stoplistReasons: [String]
    var decisionSignals: [MangaNativeTextBoxProxySignal]
    var evaluationSignals: [MangaNativeTextBoxProxySignal]
    var mustNotPromoteReasons: [String]
    var nextAction: String
    var groundTruthUsedForDecision: Bool
    var diagnosticOnly: Bool
    var wouldChangeMainFlow: Bool
}

struct MangaNativeTextBoxProxyGate: Equatable, Codable, Sendable {
    var gateID: String
    var gateName: String
    var scope: String
    var status: String
    var threshold: String
    var affectedBlocks: [Int]
    var decisionSignals: [MangaNativeTextBoxProxySignal]
    var failureMeans: String
    var recommendedAction: String
    var groundTruthUsedForDecision: Bool
}

struct MangaNativeTextBoxProxyStoplistEntry: Equatable, Codable, Sendable {
    var blockIndex: Int
    var scope: String
    var reason: String
    var sourceReports: [String]
    var evidence: [String]
    var expiresWhen: String
    var nextAllowedAction: String
}

struct MangaNativeTextBoxProxyLedgerReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var source: String
    var referenceWorkItemID: String
    var evaluatedBlockCount: Int
    var candidateLedgerCount: Int
    var gateCount: Int
    var stoplistCount: Int
    var groundTruthUsedForDecision: Bool
    var groundTruthUsedForEvaluationOnly: Bool
    var wouldChangeMainFlow: Bool
    var diagnosticOnly: Bool
    var qualityStatusBreakdown: [String: Int]
    var candidateSourceBreakdown: [String: Int]
    var freezeReasonBreakdown: [String: Int]
    var nextActionBreakdown: [String: Int]
    var stoplistBlocks: [Int]
    var shadowOnlyEligibleBlocks: [Int]
    var manualReviewBlocks: [Int]
    var blockedByWordPreservationBlocks: [Int]
    var blockedByBubbleMaskBlocks: [Int]
    var blockedBySegmentMaskBlocks: [Int]
    var blockedByTranslationModelBlocks: [Int]
    var blockLedgers: [MangaNativeTextBoxProxyBlockLedger]
    var candidateLedgers: [MangaNativeTextBoxProxyCandidateLedger]
    var gateLedger: [MangaNativeTextBoxProxyGate]
    var stoplist: [MangaNativeTextBoxProxyStoplistEntry]
    var notes: [String]
}

struct MangaOverlayFusionComparison: Equatable, Codable, Sendable {
    var comparisonUnit: String
    var wholePage: MangaOverlayFrameworkMetrics
    var bubbleFirst: MangaOverlayFrameworkMetrics
    var fused: MangaOverlayFrameworkMetrics
    var blocksFoundByAll: Int
    var blocksOnlyInWholePage: [String]
    var blocksOnlyInBubbleFirst: [String]
    var blocksOnlyInFused: [String]
    var fusedFromWholePageCount: Int
    var fusedFromBubbleFirstCount: Int
    var fusedAddedBubbleOnlyCount: Int
    var fusedRetainedWholePageOnlyCount: Int
    var fusedRejectedCandidateCount: Int
    var postFusionCleanup: MangaOverlayPostFusionCleanupReport?
    var consistencyPassed: Bool
    var consistencyWarnings: [String]
    var notes: [String]
}

struct MangaOverlayTextRegionCropDiagnostic: Equatable, Codable, Sendable {
    var blockIndex: Int
    var bubbleID: Int?
    var source: String
    var seedBBox: [Double]
    var regionBBox: [Double]
    var cropBBox: [Double]
    var clampSource: String
    var correctedBubbleID: Int?
    var splitCandidateID: Int?
    var textBoxCandidateID: Int?
    var segmentMaskUsableForCropEvidence: Bool?
    var failureAttribution: [String]
    var cropBBoxBeforeAssignmentCorrection: [Double]?
    var cropBBoxAfterAssignmentCorrection: [Double]?
    var cropMaskCoverageBefore: Double?
    var cropMaskCoverageAfter: Double?
    var assignmentCorrectionRejectedReason: String?
    var splitCandidateRejectedReason: String?
    var subRegionID: Int?
    var subRegionBBox: [Double]?
    var subRegionCoverageRatio: Double?
    var subRegionRejectedReason: String?
    var cropBBoxBeforeSubRegionClamp: [Double]
    var cropBBoxAfterSubRegionClamp: [Double]
    var cropMaskCoverageRatio: Double?
    var cropMaskRejectedReason: String?
    var cropClampedByBubble: Bool
    var paddingX: Double
    var paddingY: Double
    var orientationHint: String
    var wholePageText: String
    var fusedTextBeforeCrop: String
    var adaptiveCropText: String?
    var textRegionCropText: String?
    var selectedText: String
    var adopted: Bool
    var selectionReason: String
    var rejectionReasons: [String]
    var rawWordPreservationRatio: Double
    var candidateQualityScore: Double
    var originalQualityScore: Double
}

struct MangaOverlayTextRegionCropReport: Equatable, Codable, Sendable {
    var totalRegions: Int
    var cropSucceededCount: Int
    var adoptedCount: Int
    var rejectedCount: Int
    var adoptedBlockIndexes: [Int]
    var rejectedBlockIndexes: [Int]
    var mainRejectionReasons: [String: Int]
    var failureAttributionBreakdown: [String: Int]
    var diagnostics: [MangaOverlayTextRegionCropDiagnostic]
    var notes: [String]
}

struct MangaOverlayTextBoxCandidateDiagnostic: Equatable, Codable, Sendable {
    var id: Int
    var blockIndex: Int
    var source: String
    var bbox: [Double]
    var seedBBox: [Double]
    var orientationHint: String
    var bubbleID: Int?
    var correctedBubbleID: Int?
    var splitCandidateID: Int?
    var clampSource: String
    var paddingX: Double
    var paddingY: Double
    var bubbleMaskCoverageRatio: Double?
    var glyphOverlapRatio: Double?
    var safeRectOverlapRatio: Double?
    var evidenceScore: Double
    var eligibleForCrop: Bool
    var derivedFromTextRegionCrop: Bool
    var usedForTextRegionCrop: Bool
    var rejectionReasons: [String]
    var riskFlags: [String]
    var notes: [String]
}

struct MangaOverlayTextBoxCandidateReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var evaluatedBlockCount: Int
    var candidateCount: Int
    var cropEligibleCount: Int
    var usedForCropBlocks: [Int]
    var rejectedBlocks: [Int]
    var diagnostics: [MangaOverlayTextBoxCandidateDiagnostic]
    var notes: [String]
}

struct MangaOverlaySegmentMaskDiagnostic: Equatable, Codable, Sendable {
    var blockIndex: Int
    var textBoxCandidateID: Int?
    var glyphMaskPixelCount: Int
    var glyphMaskRect: [Double]?
    var glyphMaskFillRectCount: Int
    var textBoxCoverageRatio: Double?
    var bubbleMaskCoverageRatio: Double?
    var safeRectCoverageRatio: Double?
    var glyphEscapesBubble: Bool
    var glyphEscapesTextBox: Bool
    var usableForCleanup: Bool
    var usableForCropEvidence: Bool
    var rejectionReasons: [String]
    var riskFlags: [String]
    var notes: [String]
}

struct MangaOverlaySegmentMaskReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var evaluatedBlockCount: Int
    var glyphMaskBlocks: Int
    var usableForCleanupBlocks: [Int]
    var usableForCropEvidenceBlocks: [Int]
    var weakSegmentBlocks: [Int]
    var diagnostics: [MangaOverlaySegmentMaskDiagnostic]
    var notes: [String]
}

struct MangaOverlayPreCropTextBoxPlan: Equatable, Codable, Sendable {
    var planID: Int
    var blockIndex: Int
    var variantName: String
    var sourceSignals: [String]
    var bbox: [Double]
    var seedBBox: [Double]
    var bubbleID: Int?
    var dominantBubbleID: Int?
    var bubbleCoverageRatio: Double?
    var glyphCoverageRatio: Double?
    var safeRectCoverageRatio: Double?
    var estimatedOrientation: String
    var evidenceScore: Double
    var eligibleForShadowOCR: Bool
    var riskFlags: [String]
    var rejectionReasons: [String]
    var notes: [String]
}

struct MangaOverlayPreCropTextBoxPlanBlockSummary: Equatable, Codable, Sendable {
    var blockIndex: Int
    var selectedPlanIDsForShadowOCR: [Int]
    var rejectedPlanIDs: [Int]
    var planningVerdict: String
    var stopReasons: [String]
    var notes: [String]
}

struct MangaOverlayPreCropTextBoxPlanReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var evaluatedBlockCount: Int
    var planCount: Int
    var shadowOCREligiblePlanCount: Int
    var selectedForShadowOCRBlocks: [Int]
    var stoppedBlocks: [Int]
    var blockSummaries: [MangaOverlayPreCropTextBoxPlanBlockSummary]
    var plans: [MangaOverlayPreCropTextBoxPlan]
    var notes: [String]
}

struct MangaOverlayCropExperimentCandidate: Equatable, Codable, Sendable {
    var candidateID: Int
    var blockIndex: Int
    var sourcePlanID: Int?
    var variantName: String
    var sourceStack: [String]
    var bboxBeforeClamp: [Double]
    var bboxAfterClamp: [Double]
    var clampSource: String
    var preprocessingProfile: String
    var ocrText: String?
    var ocrSucceeded: Bool
    var wordPreservationRatio: Double
    var lineCountDelta: Int
    var qualityScoreBefore: Double
    var qualityScoreAfter: Double
    var qualityDelta: Double
    var betterThanControl: Bool
    var riskFlags: [String]
    var rejectionReasons: [String]
    var notes: [String]
}

struct MangaOverlayCropExperimentBlockSummary: Equatable, Codable, Sendable {
    var blockIndex: Int
    var controlCandidateID: Int?
    var bestShadowCandidateID: Int?
    var bestVariantName: String?
    var promotionVerdict: String
    var stopReasons: [String]
    var candidateIDs: [Int]
    var notes: [String]
}

struct MangaOverlayCropExperimentVariantSummary: Equatable, Codable, Sendable {
    var variantName: String
    var attemptedCount: Int
    var ocrSucceededCount: Int
    var betterThanControlCount: Int
    var promotedBlockCount: Int
    var degradedCount: Int
    var emptyOutputCount: Int
    var rawWordsLostCount: Int
}

struct MangaOverlayCropExperimentReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var evaluatedBlockCount: Int
    var candidateCount: Int
    var controlCandidateCount: Int
    var ocrSucceededCount: Int
    var betterThanControlCount: Int
    var promotedShadowBlocks: [Int]
    var stoppedBlocks: [Int]
    var variantBreakdown: [String: MangaOverlayCropExperimentVariantSummary]
    var blockSummaries: [MangaOverlayCropExperimentBlockSummary]
    var candidates: [MangaOverlayCropExperimentCandidate]
    var notes: [String]
}

struct MangaOverlayTextBoxPlanFailureDiagnostic: Equatable, Codable, Sendable {
    var planID: Int?
    var blockIndex: Int
    var variantName: String
    var planFailureCategory: String
    var geometryReasons: [String]
    var bubbleMaskReasons: [String]
    var segmentMaskReasons: [String]
    var safetyReasons: [String]
    var protectionReasons: [String]
    var candidateID: Int?
    var ocrFailureCategory: String?
    var ocrReasons: [String]
    var passedPromotionChecks: [String]
    var failedPromotionChecks: [String]
    var promotionBlockers: [String]
    var recommendedNextAction: String
    var notes: [String]
}

struct MangaOverlayTextBoxPlanFailureBlockSummary: Equatable, Codable, Sendable {
    var blockIndex: Int
    var verdict: String
    var primaryFailureCategory: String
    var planIDs: [Int]
    var candidateIDs: [Int]
    var bestShadowCandidateID: Int?
    var bestShadowBetterThanControl: Bool
    var passedPromotionChecks: [String]
    var failedPromotionChecks: [String]
    var promotionBlockers: [String]
    var recommendedNextAction: String
    var notes: [String]
}

struct MangaOverlayTextBoxPlanFailureReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var evaluatedBlockCount: Int
    var evaluatedPlanCount: Int
    var evaluatedCandidateCount: Int
    var betterThanControlCandidateCount: Int
    var promotedShadowBlockCount: Int
    var planFailureBreakdown: [String: Int]
    var ocrFailureBreakdown: [String: Int]
    var promotionBlockerBreakdown: [String: Int]
    var stopRecommendedBlocks: [Int]
    var continueGeometryResearchBlocks: [Int]
    var candidatePromotionBlockedBlocks: [Int]
    var blockSummaries: [MangaOverlayTextBoxPlanFailureBlockSummary]
    var diagnostics: [MangaOverlayTextBoxPlanFailureDiagnostic]
    var notes: [String]
}

struct MangaOverlayLineTextBoxPlan: Equatable, Codable, Sendable {
    var planID: Int
    var blockIndex: Int
    var parentPlanID: Int?
    var variantName: String
    var lineIndex: Int?
    var bbox: [Double]
    var seedBBox: [Double]
    var bubbleID: Int?
    var orientationHint: String
    var deskewAngleDegrees: Double?
    var sourceSignals: [String]
    var bubbleCoverageRatio: Double?
    var glyphCoverageRatio: Double?
    var safeRectCoverageRatio: Double?
    var siblingOverlapRatio: Double?
    var evidenceScore: Double
    var eligibleForShadowOCR: Bool
    var ocrExecuted: Bool
    var riskFlags: [String]
    var rejectionReasons: [String]
    var notes: [String]
}

struct MangaOverlayLineTextBoxPlanBlockSummary: Equatable, Codable, Sendable {
    var blockIndex: Int
    var sourceFailureAction: String
    var selectedPlanIDsForShadowOCR: [Int]
    var rejectedPlanIDs: [Int]
    var planningVerdict: String
    var stopReasons: [String]
    var notes: [String]
}

struct MangaOverlayLineTextBoxPlanReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var targetBlocks: [Int]
    var evaluatedBlockCount: Int
    var planCount: Int
    var shadowOCREligiblePlanCount: Int
    var blockSummaries: [MangaOverlayLineTextBoxPlanBlockSummary]
    var plans: [MangaOverlayLineTextBoxPlan]
    var notes: [String]
}

struct MangaOverlayLineCropExperimentReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var targetBlocks: [Int]
    var candidateCount: Int
    var ocrSucceededCount: Int
    var betterThanControlCount: Int
    var promotedLineShadowBlocks: [Int]
    var stoppedAfterLineResearchBlocks: [Int]
    var blockSummaries: [MangaOverlayCropExperimentBlockSummary]
    var candidates: [MangaOverlayCropExperimentCandidate]
    var notes: [String]
}

struct MangaOverlayExternalArtifactManifest: Equatable, Codable, Sendable {
    var schemaVersion: String
    var sourceImage: String
    var coordinateSpace: String
    var contractExampleOnly: Bool
    var generatedBy: String?
    var generatedAt: String?
    var textBoxesPath: String?
    var bubbleMaskPath: String?
    var segmentMaskPath: String?
    var notes: [String]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sourceImage
        case coordinateSpace
        case contractExampleOnly
        case generatedBy
        case generatedAt
        case textBoxesPath
        case bubbleMaskPath
        case segmentMaskPath
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "unknown"
        sourceImage = try container.decodeIfPresent(String.self, forKey: .sourceImage) ?? ""
        coordinateSpace = try container.decodeIfPresent(String.self, forKey: .coordinateSpace) ?? ""
        contractExampleOnly = try container.decodeIfPresent(Bool.self, forKey: .contractExampleOnly) ?? false
        generatedBy = try container.decodeIfPresent(String.self, forKey: .generatedBy)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        textBoxesPath = try container.decodeIfPresent(String.self, forKey: .textBoxesPath)
        bubbleMaskPath = try container.decodeIfPresent(String.self, forKey: .bubbleMaskPath)
        segmentMaskPath = try container.decodeIfPresent(String.self, forKey: .segmentMaskPath)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
}

struct MangaOverlayExternalTextBox: Equatable, Codable, Sendable {
    var id: String
    var bbox: [Double]
    var confidence: Double?
    var detector: String?
    var linePolygons: [[[Double]]]?
    var sourceDirection: String?
    var rotationDegrees: Double?
    var detectedFontSizePx: Double?
    var notes: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case bbox
        case x
        case y
        case width
        case height
        case confidence
        case detector
        case linePolygons
        case sourceDirection
        case rotationDegrees
        case rotationDeg
        case detectedFontSizePx
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        if let bbox = try container.decodeIfPresent([Double].self, forKey: .bbox), bbox.count == 4 {
            self.bbox = bbox
        } else {
            let x = try container.decodeIfPresent(Double.self, forKey: .x) ?? 0
            let y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0
            let width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 0
            let height = try container.decodeIfPresent(Double.self, forKey: .height) ?? 0
            bbox = [x, y, width, height]
        }
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        detector = try container.decodeIfPresent(String.self, forKey: .detector)
        linePolygons = try container.decodeIfPresent([[[Double]]].self, forKey: .linePolygons)
        sourceDirection = try container.decodeIfPresent(String.self, forKey: .sourceDirection)
        rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees)
            ?? container.decodeIfPresent(Double.self, forKey: .rotationDeg)
        detectedFontSizePx = try container.decodeIfPresent(Double.self, forKey: .detectedFontSizePx)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(bbox, forKey: .bbox)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(detector, forKey: .detector)
        try container.encodeIfPresent(linePolygons, forKey: .linePolygons)
        try container.encodeIfPresent(sourceDirection, forKey: .sourceDirection)
        try container.encodeIfPresent(rotationDegrees, forKey: .rotationDegrees)
        try container.encodeIfPresent(detectedFontSizePx, forKey: .detectedFontSizePx)
        try container.encode(notes, forKey: .notes)
    }
}

struct MangaOverlayExternalBubbleInstance: Equatable, Codable, Sendable {
    var id: String
    var bbox: [Double]
    var confidence: Double?
    var pixelCount: Int?
    var maskValue: Int?
    var notes: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case bbox
        case x
        case y
        case width
        case height
        case confidence
        case pixelCount
        case maskValue
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        if let bbox = try container.decodeIfPresent([Double].self, forKey: .bbox), bbox.count == 4 {
            self.bbox = bbox
        } else {
            let x = try container.decodeIfPresent(Double.self, forKey: .x) ?? 0
            let y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0
            let width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 0
            let height = try container.decodeIfPresent(Double.self, forKey: .height) ?? 0
            bbox = [x, y, width, height]
        }
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        pixelCount = try container.decodeIfPresent(Int.self, forKey: .pixelCount)
        maskValue = try container.decodeIfPresent(Int.self, forKey: .maskValue)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(bbox, forKey: .bbox)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(pixelCount, forKey: .pixelCount)
        try container.encodeIfPresent(maskValue, forKey: .maskValue)
        try container.encode(notes, forKey: .notes)
    }
}

struct MangaOverlayExternalSegmentMaskSummary: Equatable, Codable, Sendable {
    var sourcePath: String?
    var width: Int?
    var height: Int?
    var glyphPixelCount: Int?
    var connectedComponentCount: Int?
    var notes: [String]

    private enum CodingKeys: String, CodingKey {
        case sourcePath
        case width
        case height
        case glyphPixelCount
        case connectedComponentCount
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        glyphPixelCount = try container.decodeIfPresent(Int.self, forKey: .glyphPixelCount)
        connectedComponentCount = try container.decodeIfPresent(Int.self, forKey: .connectedComponentCount)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
}

struct MangaOverlayExternalArtifactCoordinateValidation: Equatable, Codable, Sendable {
    var coordinateSpace: String?
    var expectedCoordinateSpace: String
    var sourceImageMatches: Bool
    var imageWidth: Int
    var imageHeight: Int
    var bboxValidationPassed: Bool
    var invalidTextBoxIDs: [String]
    var invalidBubbleInstanceIDs: [String]
    var segmentMaskSizeMatches: Bool?
    var errors: [String]
    var notes: [String]
}

struct MangaOverlayExternalArtifactBlockAlignment: Equatable, Codable, Sendable {
    var blockIndex: Int
    var blockBBox: [Double]
    var bestTextBoxID: String?
    var bestTextBoxIoU: Double?
    var textBoxCenterContained: Bool
    var bestBubbleInstanceID: String?
    var bestBubbleIoU: Double?
    var currentBubbleID: Int?
    var bestExternalBubbleMaskValue: Int?
    var segmentCoverageLevel: String
    var alignmentVerdict: String
    var notes: [String]
}

struct MangaOverlayExternalArtifactReadinessReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var sourceImage: String
    var activeArtifactsDirectory: Bool
    var contractExampleOnly: Bool
    var generatedBy: String?
    var manifestPath: String?
    var textBoxesPath: String?
    var bubbleMaskPath: String?
    var segmentMaskPath: String?
    var externalTextBoxesShadowOCRAllowed: Bool
    var manifestFound: Bool
    var textBoxesFound: Bool
    var bubbleMaskFound: Bool
    var segmentMaskFound: Bool
    var textBoxCount: Int
    var bubbleInstanceCount: Int
    var segmentGlyphPixelCount: Int?
    var parsedTextBoxCount: Int
    var parsedBubbleInstanceCount: Int
    var parseErrors: [String]
    var missingArtifacts: [String]
    var coordinateValidation: MangaOverlayExternalArtifactCoordinateValidation
    var blockAlignment: [MangaOverlayExternalArtifactBlockAlignment]
    var readinessVerdict: String
    var nextAction: String
    var notes: [String]
}

struct MangaOverlayExternalTextBoxShadowOCRCandidate: Equatable, Codable, Sendable {
    var candidateID: Int
    var blockIndex: Int
    var selectedTextBoxID: String?
    var variantName: String
    var textBoxBBox: [Double]?
    var cropBBox: [Double]?
    var textBoxConfidence: Double?
    var textBoxIoU: Double?
    var blockCenterContained: Bool
    var bubbleInstanceID: String?
    var bubbleAlignmentMatched: Bool
    var areaRatioToBlock: Double?
    var linePolygonsPresent: Bool
    var sourceDirection: String?
    var rotationDegrees: Double?
    var deskewExecuted: Bool
    var ocrExecuted: Bool
    var ocrSucceeded: Bool
    var controlText: String
    var ocrText: String?
    var wordPreservationRatio: Double
    var qualityScoreBefore: Double
    var qualityScoreAfter: Double
    var qualityDelta: Double
    var betterThanControl: Bool
    var promotionVerdict: String
    var blockers: [String]
    var riskFlags: [String]
    var notes: [String]
}

struct MangaOverlayExternalTextBoxShadowOCRBlockSummary: Equatable, Codable, Sendable {
    var blockIndex: Int
    var selectedCandidateID: Int?
    var selectedTextBoxID: String?
    var candidateBBox: [Double]?
    var ocrExecuted: Bool
    var ocrSucceeded: Bool
    var ocrText: String?
    var qualityDelta: Double?
    var wordPreservationRatio: Double?
    var promotionVerdict: String
    var blockers: [String]
    var notes: [String]
}

struct MangaOverlayExternalTextBoxShadowOCRReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var executed: Bool
    var gateVerdict: String
    var activeArtifactsDirectory: Bool
    var contractExampleOnly: Bool
    var externalTextBoxesShadowOCRAllowed: Bool
    var shadowOnly: Bool
    var groundTruthNotUsed: Bool
    var doesNotChangeFinalTextUsedForTranslation: Bool
    var doesNotChangeMainOverlay: Bool
    var candidateCount: Int
    var ocrExecutedCount: Int
    var ocrSucceededCount: Int
    var betterThanControlCount: Int
    var promotedExternalShadowBlocks: [Int]
    var wouldPromoteByExistingGateBlocks: [Int]
    var skippedBlocks: [Int]
    var blockSummaries: [MangaOverlayExternalTextBoxShadowOCRBlockSummary]
    var candidates: [MangaOverlayExternalTextBoxShadowOCRCandidate]
    var notes: [String]
}

struct MangaOverlayBubbleSubRegionDiagnostic: Equatable, Codable, Sendable {
    var id: Int
    var parentBubbleID: Int
    var bbox: [Double]
    var seedBlockIndexes: [Int]
    var seedTextRegionIndexes: [Int]
    var source: String
    var area: Double
    var parentCoverageRatio: Double
    var seedCoverageRatio: Double
    var confidence: Double
    var clampEligible: Bool
    var rejectionReasons: [String]
    var notes: [String]
}

struct MangaOverlayBubbleSubRegionReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var totalSubRegions: Int
    var clampEligibleCount: Int
    var oversizedBubbleIDs: [Int]
    var diagnostics: [MangaOverlayBubbleSubRegionDiagnostic]
    var notes: [String]
}

struct MangaOverlayBubbleMaskInstanceDiagnostic: Equatable, Codable, Sendable {
    var bubbleID: Int
    var bbox: [Double]
    var maskPixelCount: Int
    var bboxPixelCount: Int
    var maskCoverageRatio: Double
    var source: String
    var confidence: Double
    var safePixelCount: Int
    var safeBBox: [Double]?
    var safeRect: [Double]?
    var safeRectCoverageRatio: Double
    var riskFlags: [String]
    var notes: [String]
}

struct MangaOverlayBubbleMaskBlockDiagnostic: Equatable, Codable, Sendable {
    var blockIndex: Int
    var currentBubbleID: Int?
    var maskDominantBubbleID: Int?
    var maskDominantCoverageRatio: Double
    var maskIDsUnderSeed: [String: Int]
    var bubbleIDConsistent: Bool
    var safeLayoutSourceBeforeMask: String?
    var safeLayoutSourceAfterMask: String?
    var maskSafeRect: [Double]?
    var renderMaskCollisionChecked: Bool
    var renderMaskCollisionResolved: Bool
    var renderMaskOverflowPixelCount: Int
    var cropMaskCoverageRatio: Double?
    var cropMaskRejectedReason: String?
}

struct MangaOverlayBubbleMaskReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var imageWidth: Int
    var imageHeight: Int
    var instanceCount: Int
    var instances: [MangaOverlayBubbleMaskInstanceDiagnostic]
    var blockDiagnostics: [MangaOverlayBubbleMaskBlockDiagnostic]
    var maskSafeLayoutBlocks: Int
    var bboxFallbackBlocks: Int
    var inconsistentBubbleAssignmentBlocks: [Int]
    var renderMaskOverflowBlocks: [Int]
    var notes: [String]
}

struct MangaOverlayBubbleAssignmentCorrectionDiagnostic: Equatable, Codable, Sendable {
    var blockIndex: Int
    var currentBubbleID: Int?
    var maskDominantBubbleID: Int?
    var maskDominantCoverageRatio: Double
    var maskIDsUnderSeed: [String: Int]
    var correctionRecommended: Bool
    var correctedBubbleID: Int?
    var correctionAppliedToCropClamp: Bool
    var correctionAppliedToSafeLayout: Bool
    var decision: String
    var rejectionReasons: [String]
    var riskFlags: [String]
    var notes: [String]
}

struct MangaOverlayBubbleAssignmentCorrectionReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var evaluatedBlockCount: Int
    var inconsistentBlockIndexes: [Int]
    var recommendedCorrectionBlocks: [Int]
    var appliedToCropClampBlocks: [Int]
    var appliedToSafeLayoutBlocks: [Int]
    var rejectedCorrectionBlocks: [Int]
    var diagnostics: [MangaOverlayBubbleAssignmentCorrectionDiagnostic]
    var notes: [String]
}

struct MangaOverlayBubbleSplitCandidateDiagnostic: Equatable, Codable, Sendable {
    var id: Int
    var parentBubbleID: Int
    var seedBlockIndexes: [Int]
    var bbox: [Double]
    var safeRect: [Double]?
    var maskPixelCount: Int
    var parentMaskCoverageRatio: Double
    var seedCoverageRatio: Double
    var siblingOverlapRatio: Double
    var clampEligible: Bool
    var appliedToBlockIndexes: [Int]
    var rejectionReasons: [String]
    var riskFlags: [String]
    var notes: [String]
}

struct MangaOverlayBubbleSplitCandidateReport: Equatable, Codable, Sendable {
    var enabled: Bool
    var parentBubbleIDs: [Int]
    var candidateCount: Int
    var clampEligibleCount: Int
    var appliedToCropClampBlocks: [Int]
    var diagnostics: [MangaOverlayBubbleSplitCandidateDiagnostic]
    var notes: [String]
}

struct MangaCleanTextDiagnosticCase: Equatable, Codable, Sendable {
    var index: Int
    var groundTruthType: String
    var text: String
    var prompt: String
    var rawOutput: String
    var translationCandidate: String
    var passed: Bool
    var failureReasons: [String]
}

struct MangaCleanTextDiagnosticReport: Equatable, Codable, Sendable {
    var source: String
    var promptTemplate: String
    var decodingMode: String
    var decodingSeed: UInt32?
    var totalCases: Int
    var passedCases: Int
    var failedCases: Int
    var passRate: Double
    var cases: [MangaCleanTextDiagnosticCase]
}

struct MangaBatchTranslationCase: Equatable, Codable, Sendable {
    var index: Int
    var tag: String
    var sourceText: String
    var parsedText: String?
    var rawOutputClassification: String
    var candidateClassification: String
    var passed: Bool
    var sequentialBlockPassed: Bool
    var failureReasons: [String]
}

struct MangaBatchTranslationComparison: Equatable, Codable, Sendable {
    var enabled: Bool
    var decodingMode: String
    var decodingSeed: UInt32?
    var prompt: String
    var rawOutput: String
    var errorCode: String?
    var totalCases: Int
    var parsedCases: Int
    var missingTags: [String]
    var duplicateTags: [String]
    var outOfOrderTags: [String]
    var sequentialPassedCases: Int
    var batchPassedCases: Int
    var sequentialPassRate: Double
    var batchPassRate: Double
    var batchBetterBy: Double
    var parseFailureReasons: [String]
    var cases: [MangaBatchTranslationCase]
    var notes: [String]
}

struct MangaDeterministicDecodingCheck: Equatable, Codable, Sendable {
    var enabled: Bool
    var decodingMode: String
    var decodingSeed: UInt32?
    var input: String
    var firstOutput: String
    var secondOutput: String
    var firstErrorCode: String?
    var secondErrorCode: String?
    var outputsIdentical: Bool
}

struct MangaOverlayProbeReport: Equatable, Codable, Sendable {
    var sourceImage: String
    var engineUsed: String
    var decodingMode: String
    var decodingSeed: UInt32?
    var configuration: MangaOverlayProbeConfiguration
    var totalBlocksDetected: Int
    var blocks: [MangaOverlayProbeBlock]
    var diagnostics: MangaOverlayProbeDiagnostics
    var correctionGuardrailTest: MangaOverlayCorrectionGuardrailTest?
    var lexiconComparison: MangaOverlayLexiconComparison?
    var visionAPIComparison: MangaOverlayVisionAPIComparison?
    var frameworkComparison: MangaOverlayFrameworkComparison?
    var fusionComparison: MangaOverlayFusionComparison?
    var fusionResults: [MangaOverlayFusionResult]
    var textRegionCropReport: MangaOverlayTextRegionCropReport?
    var textBoxCandidateReport: MangaOverlayTextBoxCandidateReport?
    var segmentMaskReport: MangaOverlaySegmentMaskReport?
    var preCropTextBoxPlanReport: MangaOverlayPreCropTextBoxPlanReport?
    var cropExperimentReport: MangaOverlayCropExperimentReport?
    var textBoxPlanFailureReport: MangaOverlayTextBoxPlanFailureReport?
    var lineTextBoxPlanReport: MangaOverlayLineTextBoxPlanReport?
    var lineCropExperimentReport: MangaOverlayLineCropExperimentReport?
    var externalArtifactReadinessReport: MangaOverlayExternalArtifactReadinessReport?
    var externalTextBoxShadowOCRReport: MangaOverlayExternalTextBoxShadowOCRReport?
    var internalStructureBottleneckReport: MangaOverlayInternalStructureBottleneckReport?
    var routingDrivenTranslationComparisonReport: MangaRoutingDrivenTranslationComparisonReport?
    var ocrCharacterDamageAuditReport: MangaOCRCharacterDamageAuditReport?
    var readingOrderStructureAuditReport: MangaReadingOrderStructureAuditReport?
    var structureActionCandidateReport: MangaStructureActionCandidateReport?
    var koharuArtifactDAGReport: MangaKoharuArtifactDAGReport?
    var koharuStageGapReplicationReport: MangaKoharuStageGapReplicationReport?
    var koharuNativeReplicationScoreboardReport: MangaKoharuNativeReplicationScoreboardReport?
    var nativeTextBoxProxyLedgerReport: MangaNativeTextBoxProxyLedgerReport?
    var bubbleSubRegionReport: MangaOverlayBubbleSubRegionReport?
    var bubbleMaskReport: MangaOverlayBubbleMaskReport?
    var bubbleAssignmentCorrectionReport: MangaOverlayBubbleAssignmentCorrectionReport?
    var bubbleSplitCandidateReport: MangaOverlayBubbleSplitCandidateReport?
    var cleanTextDiagnostic: MangaCleanTextDiagnosticReport?
    var batchTranslationComparison: MangaBatchTranslationComparison?
    var deterministicDecodingCheck: MangaDeterministicDecodingCheck?
    var bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics?
    var sliceOCR: MangaOverlaySliceOCRDiagnostics?
    var syntheticSliceOCR: MangaOverlaySliceOCRDiagnostics?
    var cropFallbackSelfTest: MangaOverlayCropFallbackSelfTest?
    var overallPassed: Bool
    var outputFiles: MangaOverlayProbeOutputFiles
    var outputDirectoryCleaned: Bool
    var outputCleanupRemovedItemCount: Int
    var outputFileCountAfterCleanup: Int
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

struct ModelDecodingProfile: Equatable, Sendable {
    var mode: String
    var seed: UInt32?
    var temperature: Double
    var topK: Int32?
    var topP: Double?
    var minP: Double?

    static let deterministic = ModelDecodingProfile(
        mode: "deterministic",
        seed: 42,
        temperature: 0,
        topK: nil,
        topP: nil,
        minP: nil
    )

    static let sampled = ModelDecodingProfile(
        mode: "sampled",
        seed: nil,
        temperature: 0.2,
        topK: 40,
        topP: 0.90,
        minP: 0.05
    )
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
