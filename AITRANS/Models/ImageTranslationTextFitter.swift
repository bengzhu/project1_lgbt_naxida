import CoreText
import Foundation

/// Computes one bounded text layout for both the live image preview and PNG export.
///
/// The caller owns drawing. This type only searches for the largest system-font size
/// whose measured lines or vertical cells fit inside the OCR rectangle.
struct ImageTranslationTextFitter {
    struct Plan: Equatable {
        let fontSize: CGFloat
        let edgeInset: CGFloat
        let lineLimit: Int
        let rowCapacity: Int
        let columnCount: Int
        let cellWidth: CGFloat
        let cellHeight: CGFloat
        let maximumCharacterCount: Int

        var contentSize: CGSize
    }

    static func fit(
        text: String,
        in containerSize: CGSize,
        vertical: Bool
    ) -> Plan {
        guard containerSize.width.isFinite,
              containerSize.height.isFinite,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return emptyPlan
        }

        let minimumDimension = min(containerSize.width, containerSize.height)
        let edgeInset = max(minimumDimension * 0.055, 0.5)
        let contentSize = CGSize(
            width: max(containerSize.width - edgeInset * 2, 0.5),
            height: max(containerSize.height - edgeInset * 2, 0.5)
        )
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return makePlan(
                fontSize: 1,
                edgeInset: edgeInset,
                contentSize: contentSize,
                characterCount: 0,
                vertical: vertical
            )
        }

        let characterCount = vertical
            ? ImageTranslationVerticalTextLayout.normalizedCharacters(in: normalizedText).count
            : normalizedText.count
        let minimumFontSize: CGFloat = 0.5
        var lowerBound = minimumFontSize
        var upperBound = max(contentSize.width, contentSize.height)
        var bestFontSize = minimumFontSize

        for _ in 0..<12 {
            let candidate = (lowerBound + upperBound) / 2
            if fits(
                normalizedText,
                characterCount: characterCount,
                fontSize: candidate,
                contentSize: contentSize,
                vertical: vertical
            ) {
                bestFontSize = candidate
                lowerBound = candidate
            } else {
                upperBound = candidate
            }
        }

        // Leave a tiny shaping allowance because SwiftUI and Core Text can round
        // glyph advances differently at display scale boundaries.
        bestFontSize = max(bestFontSize * 0.98, minimumFontSize)
        return makePlan(
            fontSize: bestFontSize,
            edgeInset: edgeInset,
            contentSize: contentSize,
            characterCount: characterCount,
            vertical: vertical
        )
    }

    private static var emptyPlan: Plan {
        Plan(
            fontSize: 1,
            edgeInset: 0,
            lineLimit: 1,
            rowCapacity: 1,
            columnCount: 1,
            cellWidth: 1,
            cellHeight: 1,
            maximumCharacterCount: 1,
            contentSize: CGSize(width: 1, height: 1)
        )
    }

    private static func fits(
        _ text: String,
        characterCount: Int,
        fontSize: CGFloat,
        contentSize: CGSize,
        vertical: Bool
    ) -> Bool {
        let font = systemFont(size: fontSize)
        let lineHeight = max(
            CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font),
            fontSize
        )

        if vertical {
            let cellHeight = lineHeight
            let cellWidth = max(fontSize, lineHeight * 0.9)
            let rows = max(Int(floor(contentSize.height / cellHeight)), 1)
            let columns = max(Int(ceil(Double(characterCount) / Double(rows))), 1)
            return CGFloat(columns) * cellWidth <= contentSize.width + 0.25
                && cellHeight <= contentSize.height + 0.25
        }

        let attributes = [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        var fittedRange = CFRange()
        let measuredSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            nil,
            CGSize(width: contentSize.width, height: .greatestFiniteMagnitude),
            &fittedRange
        )
        return fittedRange.length == attributedText.length
            && measuredSize.width <= contentSize.width + 0.25
            && measuredSize.height <= contentSize.height + 0.25
    }

    private static func makePlan(
        fontSize: CGFloat,
        edgeInset: CGFloat,
        contentSize: CGSize,
        characterCount: Int,
        vertical: Bool
    ) -> Plan {
        let font = systemFont(size: fontSize)
        let lineHeight = max(
            CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font),
            fontSize
        )
        let cellHeight = lineHeight
        let cellWidth = max(fontSize, lineHeight * 0.9)
        let rowCapacity = max(Int(floor(contentSize.height / cellHeight)), 1)
        let availableColumns = max(Int(floor(contentSize.width / cellWidth)), 1)
        let requiredColumns = max(
            Int(ceil(Double(max(characterCount, 1)) / Double(rowCapacity))),
            1
        )

        return Plan(
            fontSize: fontSize,
            edgeInset: edgeInset,
            lineLimit: max(Int(floor(contentSize.height / lineHeight)), 1),
            rowCapacity: rowCapacity,
            columnCount: vertical ? min(requiredColumns, availableColumns) : 1,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            maximumCharacterCount: max(rowCapacity * availableColumns, 1),
            contentSize: contentSize
        )
    }

    private static func systemFont(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }
}
