import Foundation

enum ImageOCRLayoutDirection: String, Sendable { case horizontal, vertical, unknown }

struct ImageOCRLayoutRect: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }

    /// Returns a finite, positive-area rectangle clipped to normalized image space.
    ///
    /// Vision normally provides valid normalized boxes, but keeping this boundary in
    /// the layout engine also protects callers that restore or synthesize OCR
    /// observations. Invalid geometry is rejected instead of leaking NaN/∞ values
    /// into sorting, union, focus crops, or overlay placement.
    func normalizedToUnit() -> Self? {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0 else {
            return nil
        }

        let right = x + width
        let bottom = y + height
        guard right.isFinite, bottom.isFinite else { return nil }

        let left = min(max(x, 0), 1)
        let clippedRight = min(max(right, 0), 1)
        let top = min(max(y, 0), 1)
        let clippedBottom = min(max(bottom, 0), 1)
        guard clippedRight > left, clippedBottom > top else { return nil }

        return Self(
            x: left,
            y: top,
            width: clippedRight - left,
            height: clippedBottom - top
        )
    }

    func union(_ other: Self) -> Self {
        let left = min(x, other.x)
        let top = min(y, other.y)
        let right = max(maxX, other.maxX)
        let bottom = max(maxY, other.maxY)
        return Self(x: left, y: top, width: right - left, height: bottom - top)
    }
}

struct ImageOCRLayoutObservation: Equatable, Sendable {
    var text: String
    var confidence: Float
    var rect: ImageOCRLayoutRect
}

struct ImageOCRLayoutBlock: Equatable, Sendable {
    var text: String
    var confidence: Float
    var rect: ImageOCRLayoutRect
    var direction: ImageOCRLayoutDirection
    var directionConfidence: Double
    var directionReason: String
}

enum ImageOCRLayoutEngine {
    static func layout(
        _ observations: [ImageOCRLayoutObservation],
        allowsVerticalText: Bool,
        prefersMangaReadingOrder: Bool = false
    ) -> [ImageOCRLayoutBlock] {
        let safeObservations = observations.compactMap { observation -> ImageOCRLayoutObservation? in
            guard let rect = observation.rect.normalizedToUnit() else { return nil }
            var safeObservation = observation
            safeObservation.rect = rect
            safeObservation.confidence = normalizedConfidence(observation.confidence)
            return safeObservation
        }
        let resolved = safeObservations.map {
            resolveDirection(for: $0, among: safeObservations, allowsVerticalText: allowsVerticalText)
        }
        let horizontal = orderedHorizontalBands(
            resolved.filter { $0.direction != .vertical },
            prefersRightToLeft: prefersMangaReadingOrder
        )
        let vertical = orderedVerticalBands(resolved.filter { $0.direction == .vertical })
        return mergeReadingOrder(
            horizontal: cluster(horizontal, direction: .horizontal),
            vertical: cluster(vertical, direction: .vertical)
        )
    }

    private static func resolveDirection(
        for observation: ImageOCRLayoutObservation,
        among all: [ImageOCRLayoutObservation],
        allowsVerticalText: Bool
    ) -> ResolvedObservation {
        let width = max(observation.rect.width, 0.001)
        let height = max(observation.rect.height, 0.001)
        let horizontalRatio = width / height
        let verticalRatio = height / width
        if horizontalRatio >= 1.35 {
            return ResolvedObservation(
                observation: observation,
                direction: .horizontal,
                confidence: min((horizontalRatio - 1) / 2, 1),
                reason: "wideBox"
            )
        }
        guard allowsVerticalText, verticalRatio >= 1.6, height >= 0.035 else {
            return ResolvedObservation(
                observation: observation,
                direction: .unknown,
                confidence: 0,
                reason: allowsVerticalText ? "ambiguousCJKBox" : "horizontalFallback"
            )
        }

        let peers = all.filter { $0 != observation }
        let hasColumnNeighbor = peers.contains { isColumnNeighbor(observation.rect, $0.rect) }
        let hasRowNeighbor = peers.contains { isCloseRowNeighbor(observation.rect, $0.rect) }
        let containsTextRun = cjkCharacterCount(in: observation.text) >= 2
        guard containsTextRun || (hasColumnNeighbor && !hasRowNeighbor) else {
            return ResolvedObservation(
                observation: observation,
                direction: .unknown,
                confidence: 0,
                reason: hasRowNeighbor ? "horizontalCJKFragment" : "isolatedTallCJKBox"
            )
        }
        return ResolvedObservation(
            observation: observation,
            direction: .vertical,
            confidence: min((verticalRatio - 1) / 2, 1),
            reason: containsTextRun ? "cjkTallTextRun" : "cjkColumnNeighbors"
        )
    }

    private static func orderedHorizontalBands(
        _ observations: [ResolvedObservation],
        prefersRightToLeft: Bool
    ) -> [ResolvedObservation] {
        let ordered = observations.sorted {
            stableKey(
                $0,
                $0.rect.y,
                prefersRightToLeft ? -$0.rect.x : $0.rect.x
            ) < stableKey(
                $1,
                $1.rect.y,
                prefersRightToLeft ? -$1.rect.x : $1.rect.x
            )
        }
        var bands: [[ResolvedObservation]] = []
        var anchor: Double?
        for observation in ordered {
            if let anchor, observation.rect.y - anchor <= 0.02 {
                bands[bands.count - 1].append(observation)
            } else {
                bands.append([observation])
                anchor = observation.rect.y
            }
        }
        return bands.flatMap { band in
            band.sorted {
                stableKey(
                    $0,
                    prefersRightToLeft ? -$0.rect.x : $0.rect.x,
                    $0.rect.y
                ) < stableKey(
                    $1,
                    prefersRightToLeft ? -$1.rect.x : $1.rect.x,
                    $1.rect.y
                )
            }
        }
    }

    private static func orderedVerticalBands(_ observations: [ResolvedObservation]) -> [ResolvedObservation] {
        guard observations.count > 1 else { return observations }

        // Koharu recursively cuts the page at the largest whitespace gap before
        // applying right-to-left reading order. Vision gives normalized geometry,
        // so scale the same median-size thresholds into unit coordinates rather
        // than using one global x-band anchor that can interleave panels.
        let medianWidth = median(observations.map(\.rect.width))
        let medianHeight = median(observations.map(\.rect.height))
        let minimumGapX = max(medianWidth * 0.15, 0.01)
        let minimumGapY = max(medianHeight * 0.10, 0.008)
        return recursiveMangaReadingOrder(
            observations,
            minimumGapX: minimumGapX,
            minimumGapY: minimumGapY
        )
    }

    private static func recursiveMangaReadingOrder(
        _ observations: [ResolvedObservation],
        minimumGapX: Double,
        minimumGapY: Double
    ) -> [ResolvedObservation] {
        guard observations.count > 1,
              let cut = bestMangaReadingCut(
                  observations,
                  minimumGapX: minimumGapX,
                  minimumGapY: minimumGapY
              ) else {
            return observations.sorted {
                stableKey($0, -$0.rect.midX, $0.rect.y)
                    < stableKey($1, -$1.rect.midX, $1.rect.y)
            }
        }

        let first: [ResolvedObservation]
        let second: [ResolvedObservation]
        switch cut.axis {
        case .x:
            // Manga pages read right-to-left across separated vertical columns.
            first = observations.filter { $0.rect.midX >= cut.coordinate }
            second = observations.filter { $0.rect.midX < cut.coordinate }
        case .y:
            // A horizontal whitespace cut separates panels/rows; read the upper
            // region before the lower one, then recurse within each region.
            first = observations.filter { $0.rect.midY <= cut.coordinate }
            second = observations.filter { $0.rect.midY > cut.coordinate }
        }

        guard !first.isEmpty, !second.isEmpty else {
            return observations.sorted {
                stableKey($0, -$0.rect.midX, $0.rect.y)
                    < stableKey($1, -$1.rect.midX, $1.rect.y)
            }
        }
        return recursiveMangaReadingOrder(
            first,
            minimumGapX: minimumGapX,
            minimumGapY: minimumGapY
        ) + recursiveMangaReadingOrder(
            second,
            minimumGapX: minimumGapX,
            minimumGapY: minimumGapY
        )
    }

    private static func bestMangaReadingCut(
        _ observations: [ResolvedObservation],
        minimumGapX: Double,
        minimumGapY: Double
    ) -> MangaReadingCut? {
        let xIntervals = observations
            .map { ($0.rect.x, $0.rect.maxX) }
        let yIntervals = observations
            .map { ($0.rect.y, $0.rect.maxY) }
        let gapX = largestMangaGap(xIntervals, minimum: minimumGapX)
        let gapY = largestMangaGap(yIntervals, minimum: minimumGapY)

        switch (gapX, gapY) {
        case let (x?, y?):
            let widthX = x.1 - x.0
            let widthY = y.1 - y.0
            // Koharu favors a meaningful row cut; normalized coordinates use a
            // small unit-space equivalent of its absolute pixel threshold.
            if widthY > max(0.01, widthX * 0.4) {
                return MangaReadingCut(axis: .y, coordinate: (y.0 + y.1) / 2)
            }
            return MangaReadingCut(axis: .x, coordinate: (x.0 + x.1) / 2)
        case let (x?, nil):
            return MangaReadingCut(axis: .x, coordinate: (x.0 + x.1) / 2)
        case let (nil, y?):
            return MangaReadingCut(axis: .y, coordinate: (y.0 + y.1) / 2)
        case (nil, nil):
            return nil
        }
    }

    private static func largestMangaGap(
        _ intervals: [(Double, Double)],
        minimum: Double
    ) -> (Double, Double)? {
        guard let first = intervals.min(by: { $0.0 < $1.0 }) else { return nil }
        let sorted = intervals.sorted { $0.0 < $1.0 }
        var currentMaxEnd = first.1
        var largest: (Double, Double)?
        for interval in sorted.dropFirst() {
            let gap = interval.0 - currentMaxEnd
            if gap >= minimum,
               largest.map({ gap > $0.1 - $0.0 }) ?? true {
                largest = (currentMaxEnd, interval.0)
            }
            currentMaxEnd = max(currentMaxEnd, interval.1)
        }
        return largest
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private static func stableKey(_ value: ResolvedObservation, _ primary: Double, _ secondary: Double) -> StableKey {
        StableKey(
            primary: primary,
            secondary: secondary,
            width: value.rect.width,
            height: value.rect.height,
            text: value.text,
            confidence: value.observation.confidence
        )
    }

    private static func cluster(
        _ observations: [ResolvedObservation],
        direction: ImageOCRLayoutDirection
    ) -> [ImageOCRLayoutBlock] {
        var clusters: [Cluster] = []
        for observation in observations {
            let compatibleIndices = clusters.indices.filter { index in
                direction == .vertical
                    ? shouldMergeVertically(observation, into: clusters[index])
                    : shouldMergeHorizontally(observation, into: clusters[index])
            }
            let bestIndex = compatibleIndices.min { lhs, rhs in
                let lhsScore = mergeScore(observation, cluster: clusters[lhs], direction: direction)
                let rhsScore = mergeScore(observation, cluster: clusters[rhs], direction: direction)
                return lhsScore == rhsScore ? lhs < rhs : lhsScore < rhsScore
            }
            if let bestIndex {
                clusters[bestIndex].append(observation)
            } else {
                clusters.append(Cluster(observation))
            }
        }
        return clusters.map(\.block)
    }

    private static func mergeScore(
        _ observation: ResolvedObservation,
        cluster: Cluster,
        direction: ImageOCRLayoutDirection
    ) -> Double {
        let crossAxisDistance = abs(observation.rect.midX - cluster.rect.midX)
        let readingAxisGap = max(0, observation.rect.y - cluster.rect.maxY)
        return direction == .vertical
            ? crossAxisDistance * 2 + readingAxisGap
            : crossAxisDistance + readingAxisGap * 0.5
    }

    private static func shouldMergeHorizontally(_ line: ResolvedObservation, into cluster: Cluster?) -> Bool {
        guard let cluster else { return false }
        let rect = cluster.rect
        let verticalGap = line.rect.y - rect.maxY
        let averageHeight = max((line.rect.height + rect.height) / 2, 0.012)
        let sameBand = abs(line.rect.y - rect.y) <= averageHeight * 0.55
        let closeVertically = verticalGap <= max(0.018, averageHeight * 0.90)
        guard sameBand || closeVertically else { return false }
        let overlap = horizontalOverlap(line.rect, rect) / max(min(line.rect.width, rect.width), 0.001)
        let centerDistance = abs(line.rect.midX - rect.midX)
        let touches = line.rect.maxY >= rect.y - 0.01 && line.rect.y <= rect.maxY + 0.035
        return touches && (overlap > 0.18 || centerDistance < 0.26)
    }

    private static func shouldMergeVertically(_ line: ResolvedObservation, into cluster: Cluster?) -> Bool {
        guard let cluster else { return false }
        let rect = cluster.rect
        let sameColumn = horizontalOverlap(line.rect, rect) / max(min(line.rect.width, rect.width), 0.001) >= 0.45
            || abs(line.rect.midX - rect.midX) <= max(line.rect.width, rect.width) * 0.55
        let gap = line.rect.y - rect.maxY
        return sameColumn && gap >= -0.015 && gap <= max(0.025, max(line.rect.width, rect.width) * 1.2)
    }

    private static func mergeReadingOrder(
        horizontal: [ImageOCRLayoutBlock],
        vertical: [ImageOCRLayoutBlock]
    ) -> [ImageOCRLayoutBlock] {
        var horizontalIndex = 0
        var verticalIndex = 0
        var output: [ImageOCRLayoutBlock] = []
        while horizontalIndex < horizontal.count || verticalIndex < vertical.count {
            if horizontalIndex == horizontal.count {
                output.append(contentsOf: vertical[verticalIndex...])
                break
            }
            if verticalIndex == vertical.count {
                output.append(contentsOf: horizontal[horizontalIndex...])
                break
            }
            if horizontal[horizontalIndex].rect.y + 0.02 < vertical[verticalIndex].rect.y {
                output.append(horizontal[horizontalIndex])
                horizontalIndex += 1
            } else {
                output.append(vertical[verticalIndex])
                verticalIndex += 1
            }
        }
        return output
    }

    private static func isColumnNeighbor(_ lhs: ImageOCRLayoutRect, _ rhs: ImageOCRLayoutRect) -> Bool {
        let sameColumn = horizontalOverlap(lhs, rhs) / max(min(lhs.width, rhs.width), 0.001) >= 0.45
            || abs(lhs.midX - rhs.midX) <= max(lhs.width, rhs.width) * 0.55
        let gap = max(lhs.y, rhs.y) - min(lhs.maxY, rhs.maxY)
        return sameColumn && gap >= -0.015 && gap <= max(0.06, max(lhs.height, rhs.height) * 1.5)
    }

    private static func isCloseRowNeighbor(_ lhs: ImageOCRLayoutRect, _ rhs: ImageOCRLayoutRect) -> Bool {
        let overlap = max(0, min(lhs.maxY, rhs.maxY) - max(lhs.y, rhs.y))
        let sameRow = overlap / max(min(lhs.height, rhs.height), 0.001) >= 0.45
        let gap = max(lhs.x, rhs.x) - min(lhs.maxX, rhs.maxX)
        return sameRow && gap >= -0.01 && gap <= max(0.025, max(lhs.width, rhs.width) * 1.5)
    }

    private static func horizontalOverlap(_ lhs: ImageOCRLayoutRect, _ rhs: ImageOCRLayoutRect) -> Double {
        max(0, min(lhs.maxX, rhs.maxX) - max(lhs.x, rhs.x))
    }

    private static func cjkCharacterCount(in text: String) -> Int {
        text.unicodeScalars.count { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: true
            default: false
            }
        }
    }

    private static func normalizedConfidence(_ rawConfidence: Float) -> Float {
        guard rawConfidence.isFinite else { return 0 }
        return min(max(rawConfidence, 0), 1)
    }
}

private struct ResolvedObservation {
    var observation: ImageOCRLayoutObservation
    var direction: ImageOCRLayoutDirection
    var confidence: Double
    var reason: String
    var text: String { observation.text }
    var rect: ImageOCRLayoutRect { observation.rect }
}

private struct StableKey: Comparable {
    var primary: Double
    var secondary: Double
    var width: Double
    var height: Double
    var text: String
    var confidence: Float

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.primary != rhs.primary { return lhs.primary < rhs.primary }
        if lhs.secondary != rhs.secondary { return lhs.secondary < rhs.secondary }
        if lhs.width != rhs.width { return lhs.width < rhs.width }
        if lhs.height != rhs.height { return lhs.height < rhs.height }
        if lhs.text != rhs.text { return lhs.text < rhs.text }
        return lhs.confidence < rhs.confidence
    }
}

private enum MangaReadingCutAxis {
    case x
    case y
}

private struct MangaReadingCut {
    var axis: MangaReadingCutAxis
    var coordinate: Double
}

private struct Cluster {
    private(set) var observations: [ResolvedObservation]
    private(set) var rect: ImageOCRLayoutRect

    init(_ observation: ResolvedObservation) {
        observations = [observation]
        rect = observation.rect
    }

    mutating func append(_ observation: ResolvedObservation) {
        observations.append(observation)
        rect = rect.union(observation.rect)
    }

    var block: ImageOCRLayoutBlock {
        let direction: ImageOCRLayoutDirection
        if observations.contains(where: { $0.direction == .vertical }) {
            direction = .vertical
        } else if observations.contains(where: { $0.direction == .horizontal }) {
            direction = .horizontal
        } else {
            direction = .unknown
        }
        let text: String
        if direction == .vertical {
            text = observations.map(\.text).joined()
        } else {
            text = observations.enumerated().reduce(into: "") { output, entry in
                let (index, observation) = entry
                if index > 0 {
                    let previous = observations[index - 1]
                    let sameLine = abs(previous.rect.y - observation.rect.y)
                        <= max(previous.rect.height, observation.rect.height) * 0.50
                    output += sameLine ? " " : "\n"
                }
                output += observation.text
            }
        }
        return ImageOCRLayoutBlock(
            text: text,
            confidence: observations.reduce(Float(0)) { $0 + $1.observation.confidence } / Float(observations.count),
            rect: rect,
            direction: direction,
            directionConfidence: observations.reduce(0) { $0 + $1.confidence } / Double(observations.count),
            directionReason: Array(Set(observations.map(\.reason))).sorted().joined(separator: ",")
        )
    }
}
