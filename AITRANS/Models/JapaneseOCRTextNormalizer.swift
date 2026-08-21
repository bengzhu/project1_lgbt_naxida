import Foundation

/// Keeps mixed Japanese/Latin OCR readable without changing the established
/// pure-Japanese normalization path. Vision and bundled Manga OCR both feed
/// their Japanese candidates through this boundary before fusion/layout.
enum JapaneseOCRTextNormalizer {
    /// Returns a normalized mixed-script candidate when the text contains an
    /// ASCII letter or digit; otherwise returns nil so callers can retain the
    /// historical pure-Japanese post-processing implementation.
    static func mixedScriptCandidate(_ text: String) -> String? {
        let tokens = text
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty,
              tokens.contains(where: containsASCIIWord) else {
            return nil
        }

        var output = ""
        for (index, token) in tokens.enumerated() {
            if index > 0 {
                let previousHasASCIIWord = containsASCIIWord(tokens[index - 1])
                if previousHasASCIIWord || containsASCIIWord(token) {
                    // Keep boundaries around Latin/number tokens so model
                    // names, URLs, dates, and English dialogue do not merge
                    // into adjacent Japanese text.
                    output.append(" ")
                }
            }
            output.append(
                normalizeToken(
                    token,
                    preservesASCII: containsASCIIWord(token)
                )
            )
        }
        return output
    }

    private static func containsASCIIWord(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x30...0x39).contains(scalar.value)
                || (0x41...0x5A).contains(scalar.value)
                || (0x61...0x7A).contains(scalar.value)
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
            if scalar.value == 0x2E || scalar.value == 0x30FB {
                dotCount += 1
                continue
            }
            flushDots()
            collapsed.unicodeScalars.append(scalar)
        }
        flushDots()

        var output = ""
        for scalar in collapsed.unicodeScalars {
            if preservesASCII,
               (0x21...0x7E).contains(scalar.value) {
                // Preserve ASCII letters, numbers, URL punctuation and model
                // separators inside a technical/Latin token.
                output.unicodeScalars.append(scalar)
            } else if (0x21...0x7E).contains(scalar.value),
                      let fullwidth = UnicodeScalar(scalar.value + 0xFEE0) {
                output.unicodeScalars.append(fullwidth)
            } else {
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }
}
