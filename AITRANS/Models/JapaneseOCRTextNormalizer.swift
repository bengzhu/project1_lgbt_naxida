import Foundation

/// Keeps mixed Japanese/Latin OCR readable without changing the established
/// pure-Japanese normalization path. Vision and bundled Manga OCR both feed
/// their Japanese candidates through this boundary before fusion/layout.
enum JapaneseOCRTextNormalizer {
    /// Identifies a Japanese candidate whose Latin/number tokens are part of
    /// the OCR signal, rather than incidental punctuation. Fullwidth Latin
    /// letters and digits are included because Vision may emit `ＡＢＣ１２３`
    /// for a technical token even when the source glyphs are Latin. Vision
    /// candidate selection uses this as a bounded fidelity hint before the
    /// shared post-processing boundary runs.
    static func hasMixedJapaneseAndASCII(_ text: String) -> Bool {
        (containsASCIIWord(text) || containsFullwidthWord(text))
            && text.unicodeScalars.contains(where: containsJapaneseScript)
    }

    /// Returns a normalized mixed-script candidate when the text contains an
    /// ASCII letter or digit; otherwise returns nil so callers can retain the
    /// historical pure-Japanese post-processing implementation.
    static func mixedScriptCandidate(_ text: String) -> String? {
        let tokens = text
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty,
              tokens.contains(where: containsLatinOrDigitWord) else {
            return nil
        }

        var output = ""
        for (index, token) in tokens.enumerated() {
            if index > 0 {
                let previousHasTechnicalWord = containsLatinOrDigitWord(tokens[index - 1])
                if previousHasTechnicalWord || containsLatinOrDigitWord(token) {
                    // Keep boundaries around Latin/number tokens so model
                    // names, URLs, dates, and English dialogue do not merge
                    // into adjacent Japanese text.
                    output.append(" ")
                }
            }
            output.append(
                normalizeToken(
                    token,
                    preservesASCII: containsLatinOrDigitWord(token)
                )
            )
        }
        return output
    }

    private static func containsASCIIWord(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            containsASCIIWordScalar(scalar)
        }
    }

    private static func containsFullwidthWord(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            containsFullwidthWordScalar(scalar)
        }
    }

    private static func containsLatinOrDigitWord(_ text: String) -> Bool {
        containsASCIIWord(text) || containsFullwidthWord(text)
    }

    private static func containsASCIIWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value)
            || (0x41...0x5A).contains(scalar.value)
            || (0x61...0x7A).contains(scalar.value)
    }

    private static func containsFullwidthWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0xFF10...0xFF19).contains(scalar.value)
            || (0xFF21...0xFF3A).contains(scalar.value)
            || (0xFF41...0xFF5A).contains(scalar.value)
    }

    private static func containsJapaneseScript(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF,
             0x4E00...0x9FFF, 0xF900...0xFAFF,
             0xFF66...0xFF9D:
            return true
        default:
            return false
        }
    }

    private static func normalizeToken(
        _ token: String,
        preservesASCII: Bool
    ) -> String {
        let expanded = token.replacingOccurrences(of: "…", with: "...")
        var collapsed = ""
        var dotCount = 0

        func flushDots() {
            guard dotCount > 0 else { return }
            collapsed.append(contentsOf: String(repeating: ".", count: dotCount))
            dotCount = 0
        }

        for scalar in expanded.unicodeScalars {
            if scalar.value == 0x2E || scalar.value == 0xFF0E {
                dotCount += 1
                continue
            }
            // Japanese middle dot separates names and loanwords; it is not
            // an ASCII period and must survive OCR normalization as `・`.
            flushDots()
            collapsed.unicodeScalars.append(scalar)
        }
        flushDots()

        var output = ""
        for scalar in collapsed.unicodeScalars {
            if preservesASCII,
               let technicalScalar = normalizedTechnicalScalar(scalar) {
                // Preserve ASCII letters, numbers, URL punctuation and model
                // separators inside a technical/Latin token. Convert their
                // fullwidth forms to ASCII so the translation model receives
                // one stable representation for dates, versions and URLs.
                output.unicodeScalars.append(technicalScalar)
            } else if (0x21...0x7E).contains(scalar.value),
                      let fullwidth = UnicodeScalar(scalar.value + 0xFEE0) {
                output.unicodeScalars.append(fullwidth)
            } else {
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }

    private static func normalizedTechnicalScalar(
        _ scalar: Unicode.Scalar
    ) -> Unicode.Scalar? {
        if (0x21...0x7E).contains(scalar.value) {
            return scalar
        }
        guard (0xFF01...0xFF5E).contains(scalar.value) else {
            return nil
        }
        return UnicodeScalar(scalar.value - 0xFEE0)
    }
}
