import Foundation

enum SpeechQualityProbeState: String, Codable, Sendable {
    case idle
    case loadingManifest
    case requestingAuthorization
    case validatingAudio
    case recognizing
    case completed
    case failed
    case cancelled
}

struct SpeechQualityCorpusManifest: Codable, Equatable, Sendable {
    static let supportedSchemaVersion = "aitrans.speech_corpus.v1"

    var schemaVersion: String
    var corpusID: String
    var corpusVersion: String
    var cases: [SpeechQualityCorpusCase]
}

struct SpeechQualityCorpusCase: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var audioFile: String
    var audioSHA256: String
    var audioByteCount: Int64
    var localeIdentifier: String
    var referenceTranscript: String
    var sourceDescription: String
}

enum SpeechQualityFailureCategory: String, Codable, Sendable {
    case manifestMissing
    case invalidManifest
    case audioMissing
    case audioIdentityMismatch
    case authorizationDenied
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable
    case recognitionFailed
    case emptyTranscript
    case timedOut
    case cancelled
}

struct SpeechQualityMetrics: Codable, Equatable, Sendable {
    var normalizedReference: String
    var normalizedRecognition: String
    var wordErrorCount: Int?
    var referenceWordCount: Int?
    var wordErrorRate: Double?
    var characterErrorCount: Int
    var referenceCharacterCount: Int
    var characterErrorRate: Double?
}

struct SpeechQualityCaseReport: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var audioFile: String
    var audioSHA256: String
    var audioByteCount: Int64
    var localeIdentifier: String
    var sourceDescription: String
    var referenceTranscript: String
    var recognizedTranscript: String
    var metrics: SpeechQualityMetrics?
    var latencySeconds: Double?
    var segmentCount: Int
    var averageConfidence: Double?
    var requiresOnDeviceRecognition: Bool
    var supportsOnDeviceRecognition: Bool?
    var failureCategory: SpeechQualityFailureCategory?
    var failureMessage: String?
    var referenceUsedForEvaluationOnly: Bool
    var referenceUsedForRecognitionDecision: Bool
}

struct SpeechQualityAggregate: Codable, Equatable, Sendable {
    var totalCaseCount: Int
    var recognizedCaseCount: Int
    var failedCaseCount: Int
    var totalWordErrors: Int
    var totalReferenceWords: Int
    var weightedWordErrorRate: Double?
    var totalCharacterErrors: Int
    var totalReferenceCharacters: Int
    var weightedCharacterErrorRate: Double?
    var totalLatencySeconds: Double
    var averageLatencySeconds: Double?
    var failureBreakdown: [String: Int]
}

struct SpeechQualityRuntimeIdentity: Codable, Equatable, Sendable {
    var appVersion: String
    var appBuild: String
    var deviceModel: String
    var systemName: String
    var systemVersion: String
}

enum SpeechQualityProbeVerdict: String, Codable, Sendable {
    case manifestMissing
    case invalidManifest
    case qualityMeasured
    case completedWithFailures
    case cancelled
}

struct SpeechQualityProbeReport: Codable, Equatable, Sendable {
    static let schemaVersion = "aitrans.speech_quality_report.v1"

    var schemaVersion: String
    var appAlgorithmVersion: String
    var generatedAt: Date
    var verdict: SpeechQualityProbeVerdict
    var corpusManifestFile: String
    var corpusManifestSHA256: String?
    var corpusID: String?
    var corpusVersion: String?
    var runtime: SpeechQualityRuntimeIdentity
    var requiresOnDeviceRecognition: Bool
    var referenceUsedForEvaluationOnly: Bool
    var referenceUsedForRecognitionDecision: Bool
    var cases: [SpeechQualityCaseReport]
    var aggregate: SpeechQualityAggregate
    var warnings: [String]
}
