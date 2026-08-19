import Foundation

/// Report-only preflight for the current rectangular image overlay renderer.
///
/// This is deliberately independent from BubbleMask/SegmentMask artifacts. It
/// can identify geometry and collision risks before a future inpainting path is
/// introduced, while the existing overlay renderer remains the source of
/// truth for exported pixels.
struct ImageTranslationRenderSafety {
    enum Verdict: String, Codable, Sendable {
        case clear
        case needsReview
    }

    enum Severity: String, Codable, Sendable {
        case warning
        case unsafe
    }

    enum IssueCode: String, Codable, Sendable {
        case invalidGeometry
        case emptyText
        case adjacentOverlayClipped
        case adjacentOverlayOverlapsSource
        case sourceBlocksOverlap
        case adjacentOverlayCollidesWithOtherBlock
    }

    struct Issue: Equatable, Codable, Sendable {
        var blockID: UUID?
        var relatedBlockID: UUID?
        var code: IssueCode
        var severity: Severity
        var detail: String
    }

    struct Report: Equatable, Codable, Sendable {
        var overlayMode: ImageTranslationOverlayMode
        var evaluatedBlockCount: Int
        var issues: [Issue]
        var verdict: Verdict
        /// This report is diagnostic-only. It does not gate or rewrite export.
        var reportOnly: Bool
        var groundTruthUsedForDecision: Bool
        var changesOCR: Bool
        var changesTranslation: Bool
        var changesOverlayRendering: Bool

        var requiresAttention: Bool {
            verdict == .needsReview
        }

        var title: String {
            overlayMode == .adjacent ? "旁贴渲染预检" : "覆盖渲染预检"
        }

        var detail: String {
            let unsafeCount = issues.count(where: { $0.severity == .unsafe })
            let warningCount = issues.count(where: { $0.severity == .warning })
            var parts = ["发现 \(issues.count) 项几何风险"]
            if unsafeCount > 0 {
                parts.append("\(unsafeCount) 项可能遮挡或裁切")
            }
            if warningCount > 0 {
                parts.append("\(warningCount) 项提示")
            }
            parts.append("当前仍保留现有矩形 overlay；不会重跑 OCR、翻译或自动清字")
            return parts.joined(separator: "；")
        }
    }

    private struct Entry {
        let block: ImageTranslationBlock
        let sourceRect: NormalizedImageRect
        let overlayRect: NormalizedImageRect
    }

    static func analyze(
        blocks: [ImageTranslationBlock],
        overlayMode: ImageTranslationOverlayMode
    ) -> Report {
        var issues: [Issue] = []
        var entries: [Entry] = []

        for block in blocks {
            guard let sourceRect = block.boundingBox.normalizedToUnit() else {
                issues.append(Issue(
                    blockID: block.id,
                    relatedBlockID: nil,
                    code: .invalidGeometry,
                    severity: .unsafe,
                    detail: "文字块几何无效，导出预检无法确认安全范围"
                ))
                continue
            }

            let text = (block.translation.isEmpty ? block.original : block.translation)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                issues.append(Issue(
                    blockID: block.id,
                    relatedBlockID: nil,
                    code: .emptyText,
                    severity: .warning,
                    detail: "文字块没有可绘制的原文或译文"
                ))
            }

            let adjacent = adjacentOverlay(for: sourceRect)
            let overlayRect = overlayMode == .adjacent ? adjacent.rect : sourceRect
            entries.append(Entry(
                block: block,
                sourceRect: sourceRect,
                overlayRect: overlayRect
            ))

            if overlayMode == .adjacent && adjacent.wasClipped {
                issues.append(Issue(
                    blockID: block.id,
                    relatedBlockID: nil,
                    code: .adjacentOverlayClipped,
                    severity: .unsafe,
                    detail: "旁贴译文区域触及图片边界，当前 overlay 可能被裁切"
                ))
            }

            if overlayMode == .adjacent && overlapRatio(sourceRect, adjacent.rect) > 0.02 {
                issues.append(Issue(
                    blockID: block.id,
                    relatedBlockID: nil,
                    code: .adjacentOverlayOverlapsSource,
                    severity: .unsafe,
                    detail: "旁贴译文区域与原文字块重叠"
                ))
            }
        }

        for leftIndex in entries.indices {
            for rightIndex in (leftIndex + 1)..<entries.count {
                let left = entries[leftIndex]
                let right = entries[rightIndex]
                if overlapRatio(left.sourceRect, right.sourceRect) > 0.25 {
                    issues.append(Issue(
                        blockID: left.block.id,
                        relatedBlockID: right.block.id,
                        code: .sourceBlocksOverlap,
                        severity: .warning,
                        detail: "两个文字块的矩形重叠，可能造成覆盖顺序风险"
                    ))
                }

                guard overlayMode == .adjacent else { continue }
                if overlapRatio(left.overlayRect, right.sourceRect) > 0.08 {
                    issues.append(Issue(
                        blockID: left.block.id,
                        relatedBlockID: right.block.id,
                        code: .adjacentOverlayCollidesWithOtherBlock,
                        severity: .unsafe,
                        detail: "旁贴译文区域覆盖了另一个文字块"
                    ))
                }
                if overlapRatio(right.overlayRect, left.sourceRect) > 0.08 {
                    issues.append(Issue(
                        blockID: right.block.id,
                        relatedBlockID: left.block.id,
                        code: .adjacentOverlayCollidesWithOtherBlock,
                        severity: .unsafe,
                        detail: "旁贴译文区域覆盖了另一个文字块"
                    ))
                }
            }
        }

        return Report(
            overlayMode: overlayMode,
            evaluatedBlockCount: entries.count,
            issues: issues,
            verdict: issues.isEmpty ? .clear : .needsReview,
            reportOnly: true,
            groundTruthUsedForDecision: false,
            changesOCR: false,
            changesTranslation: false,
            changesOverlayRendering: false
        )
    }

    private static func adjacentOverlay(
        for source: NormalizedImageRect
    ) -> (rect: NormalizedImageRect, wasClipped: Bool) {
        let gap = 0.008
        let width = min(max(source.width * 1.45, 0.16), 0.46)
        let height = min(max(source.height * 1.65, 0.075), 0.32)
        let proposedX = source.x + source.width + gap + width <= 1
            ? source.x + source.width + gap
            : source.x - gap - width
        let proposedY = source.y + source.height / 2 - height / 2
        let x = min(max(proposedX, 0), max(1 - width, 0))
        let y = min(max(proposedY, 0), max(1 - height, 0))
        return (
            NormalizedImageRect(x: x, y: y, width: width, height: height),
            proposedX < 0 || proposedY < 0 || proposedX + width > 1 || proposedY + height > 1
        )
    }

    private static func overlapRatio(
        _ lhs: NormalizedImageRect,
        _ rhs: NormalizedImageRect
    ) -> Double {
        let intersectionWidth = max(
            0,
            min(lhs.x + lhs.width, rhs.x + rhs.width) - max(lhs.x, rhs.x)
        )
        let intersectionHeight = max(
            0,
            min(lhs.y + lhs.height, rhs.y + rhs.height) - max(lhs.y, rhs.y)
        )
        let intersection = intersectionWidth * intersectionHeight
        let smallerArea = min(lhs.width * lhs.height, rhs.width * rhs.height)
        guard smallerArea > 0 else { return 0 }
        return intersection / smallerArea
    }
}
