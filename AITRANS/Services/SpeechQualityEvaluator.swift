import Foundation

enum SpeechQualityEvaluator {
    static func evaluate(
        reference: String,
        recognition: String,
        localeIdentifier: String
    ) -> SpeechQualityMetrics {
        let normalizedReference = normalize(reference, localeIdentifier: localeIdentifier)
        let normalizedRecognition = normalize(recognition, localeIdentifier: localeIdentifier)
        let referenceCharacters = characterTokens(normalizedReference)
        let recognitionCharacters = characterTokens(normalizedRecognition)
        let characterErrors = editDistance(referenceCharacters, recognitionCharacters)
        let characterRate = rate(errors: characterErrors, referenceCount: referenceCharacters.count)

        let wordMetrics: (errors: Int, count: Int, rate: Double?)?
        if supportsWhitespaceWordErrorRate(localeIdentifier: localeIdentifier) {
            let referenceWords = wordTokens(normalizedReference)
            let recognitionWords = wordTokens(normalizedRecognition)
            let errors = editDistance(referenceWords, recognitionWords)
            wordMetrics = (errors, referenceWords.count, rate(errors: errors, referenceCount: referenceWords.count))
        } else {
            wordMetrics = nil
        }

        return SpeechQualityMetrics(
            normalizedReference: normalizedReference,
            normalizedRecognition: normalizedRecognition,
            wordErrorCount: wordMetrics?.errors,
            referenceWordCount: wordMetrics?.count,
            wordErrorRate: wordMetrics?.rate,
            characterErrorCount: characterErrors,
            referenceCharacterCount: referenceCharacters.count,
            characterErrorRate: characterRate
        )
    }

    static func aggregate(_ cases: [SpeechQualityCaseReport]) -> SpeechQualityAggregate {
        let successful = cases.filter { $0.failureCategory == nil && $0.metrics != nil }
        let wordErrors = successful.compactMap(\.metrics?.wordErrorCount).reduce(0, +)
        let referenceWords = successful.compactMap(\.metrics?.referenceWordCount).reduce(0, +)
        let characterErrors = successful.compactMap(\.metrics?.characterErrorCount).reduce(0, +)
        let referenceCharacters = successful.compactMap(\.metrics?.referenceCharacterCount).reduce(0, +)
        let latencies = successful.compactMap(\.latencySeconds)
        let failureBreakdown = Dictionary(grouping: cases.compactMap(\.failureCategory), by: \.rawValue)
            .mapValues(\.count)

        return SpeechQualityAggregate(
            totalCaseCount: cases.count,
            recognizedCaseCount: successful.count,
            failedCaseCount: cases.count - successful.count,
            totalWordErrors: wordErrors,
            totalReferenceWords: referenceWords,
            weightedWordErrorRate: rate(errors: wordErrors, referenceCount: referenceWords),
            totalCharacterErrors: characterErrors,
            totalReferenceCharacters: referenceCharacters,
            weightedCharacterErrorRate: rate(errors: characterErrors, referenceCount: referenceCharacters),
            totalLatencySeconds: latencies.reduce(0, +),
            averageLatencySeconds: latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count),
            failureBreakdown: failureBreakdown
        )
    }

    static func normalize(_ text: String, localeIdentifier: String = "en_US_POSIX") -> String {
        let folded = text
            .precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: localeIdentifier))

        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(folded.unicodeScalars.count)
        var previousWasSpace = true
        for scalar in folded.unicodeScalars {
            if ["'", "’", "ʼ"].contains(scalar) {
                continue
            }
            let isSeparator = CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
            if isSeparator {
                if !previousWasSpace {
                    scalars.append(" ")
                    previousWasSpace = true
                }
            } else {
                scalars.append(scalar)
                previousWasSpace = false
            }
        }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
    }

    static func editDistance<T: Equatable>(_ source: [T], _ target: [T]) -> Int {
        guard !source.isEmpty else { return target.count }
        guard !target.isEmpty else { return source.count }

        var previous = Array(0...target.count)
        for (sourceIndex, sourceValue) in source.enumerated() {
            var current = Array(repeating: 0, count: target.count + 1)
            current[0] = sourceIndex + 1
            for (targetIndex, targetValue) in target.enumerated() {
                let substitutionCost = sourceValue == targetValue ? 0 : 1
                current[targetIndex + 1] = min(
                    previous[targetIndex + 1] + 1,
                    current[targetIndex] + 1,
                    previous[targetIndex] + substitutionCost
                )
            }
            previous = current
        }
        return previous[target.count]
    }

    private static func wordTokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func characterTokens(_ text: String) -> [Character] {
        text.filter { !$0.isWhitespace }.map { $0 }
    }

    private static func supportsWhitespaceWordErrorRate(localeIdentifier: String) -> Bool {
        let language = Locale(identifier: localeIdentifier).language.languageCode?.identifier.lowercased()
            ?? localeIdentifier.split(separator: "-").first.map(String.init)?.lowercased()
            ?? ""
        return !["zh", "ja"].contains(language)
    }

    private static func rate(errors: Int, referenceCount: Int) -> Double? {
        guard referenceCount > 0 else { return nil }
        return Double(errors) / Double(referenceCount)
    }
}
