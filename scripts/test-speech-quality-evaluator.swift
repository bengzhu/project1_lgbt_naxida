import Foundation

@main
struct SpeechQualityEvaluatorContract {
    static func main() {
        precondition(SpeechQualityEvaluator.editDistance(Array("kitten"), Array("sitting")) == 3)

        let english = SpeechQualityEvaluator.evaluate(
            reference: "Hello, brave world!",
            recognition: "hello world",
            localeIdentifier: "en-US"
        )
        precondition(english.normalizedReference == "hello brave world")
        precondition(english.wordErrorCount == 1)
        precondition(english.referenceWordCount == 3)
        precondition(abs((english.wordErrorRate ?? -1) - (1.0 / 3.0)) < 0.000_001)
        precondition(SpeechQualityEvaluator.normalize("Don't stop") == "dont stop")

        let french = SpeechQualityEvaluator.evaluate(
            reference: "café",
            recognition: "cafe",
            localeIdentifier: "fr-FR"
        )
        precondition(french.wordErrorCount == 1)
        precondition(french.characterErrorCount == 1)

        let chinese = SpeechQualityEvaluator.evaluate(
            reference: "明天九点开会",
            recognition: "明天八点开会",
            localeIdentifier: "zh-CN"
        )
        precondition(chinese.wordErrorRate == nil)
        precondition(chinese.wordErrorCount == nil)
        precondition(chinese.characterErrorCount == 1)
        precondition(chinese.referenceCharacterCount == 6)

        let englishCase = SpeechQualityCaseReport(
            id: "en-1",
            audioFile: "en-1.wav",
            audioSHA256: String(repeating: "a", count: 64),
            audioByteCount: 1,
            localeIdentifier: "en-US",
            sourceDescription: "contract",
            referenceTranscript: "Hello, brave world!",
            recognizedTranscript: "hello world",
            metrics: english,
            latencySeconds: 1.5,
            segmentCount: 2,
            averageConfidence: 0.9,
            requiresOnDeviceRecognition: true,
            supportsOnDeviceRecognition: true,
            failureCategory: nil,
            failureMessage: nil,
            referenceUsedForEvaluationOnly: true,
            referenceUsedForRecognitionDecision: false
        )
        let failedCase = SpeechQualityCaseReport(
            id: "failed",
            audioFile: "failed.wav",
            audioSHA256: String(repeating: "b", count: 64),
            audioByteCount: 1,
            localeIdentifier: "en-US",
            sourceDescription: "contract",
            referenceTranscript: "test",
            recognizedTranscript: "",
            metrics: nil,
            latencySeconds: nil,
            segmentCount: 0,
            averageConfidence: nil,
            requiresOnDeviceRecognition: true,
            supportsOnDeviceRecognition: false,
            failureCategory: .onDeviceRecognitionUnavailable,
            failureMessage: "unsupported",
            referenceUsedForEvaluationOnly: true,
            referenceUsedForRecognitionDecision: false
        )
        let aggregate = SpeechQualityEvaluator.aggregate([englishCase, failedCase])
        precondition(aggregate.totalCaseCount == 2)
        precondition(aggregate.recognizedCaseCount == 1)
        precondition(aggregate.failedCaseCount == 1)
        precondition(aggregate.totalWordErrors == 1)
        precondition(aggregate.totalReferenceWords == 3)
        precondition(aggregate.failureBreakdown["onDeviceRecognitionUnavailable"] == 1)
        print("Speech quality evaluator contract passed")
    }
}
