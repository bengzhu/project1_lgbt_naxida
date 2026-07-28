import Foundation

enum KoharuMaskPayloadError: Error, Equatable, CustomStringConvertible {
    case incompletePayload
    case invalidDimensions
    case dimensionOverflow
    case pixelLimitExceeded(expected: Int, limit: Int)
    case unsupportedEncoding(String)
    case invalidRun(index: Int)
    case invalidRunLength(index: Int)
    case invalidLabel(index: Int, label: Int)
    case decodedLengthExceeded(index: Int)
    case decodedLengthMismatch(expected: Int, actual: Int)
    case invalidBubbleInstance(id: String)
    case duplicateBubbleMaskValue(Int)
    case bubblePixelCountMismatch(id: String, expected: Int, actual: Int)
    case bubbleBoundingBoxMismatch(id: String, expected: [Double], actual: [Double]?)
    case segmentGlyphPixelCountMismatch(expected: Int, actual: Int)
    case segmentComponentCountMismatch(expected: Int, actual: Int)

    var description: String {
        switch self {
        case .incompletePayload:
            return "mask payload fields are incomplete"
        case .invalidDimensions:
            return "mask dimensions and pixel limit must be positive"
        case .dimensionOverflow:
            return "mask dimensions overflow Int"
        case let .pixelLimitExceeded(expected, limit):
            return "mask pixel count \(expected) exceeds limit \(limit)"
        case let .unsupportedEncoding(encoding):
            return "unsupported mask encoding: \(encoding)"
        case let .invalidRun(index):
            return "RLE run \(index) must contain exactly [label, count]"
        case let .invalidRunLength(index):
            return "RLE run \(index) has a non-positive count"
        case let .invalidLabel(index, label):
            return "RLE run \(index) has invalid label \(label)"
        case let .decodedLengthExceeded(index):
            return "RLE run \(index) exceeds the declared dimensions"
        case let .decodedLengthMismatch(expected, actual):
            return "decoded \(actual) pixels; expected \(expected)"
        case let .invalidBubbleInstance(id):
            return "bubble instance \(id) lacks a valid positive mask value and exact summary"
        case let .duplicateBubbleMaskValue(value):
            return "bubble mask value \(value) is assigned more than once"
        case let .bubblePixelCountMismatch(id, expected, actual):
            return "bubble \(id) reports \(expected) pixels; payload contains \(actual)"
        case let .bubbleBoundingBoxMismatch(id, expected, actual):
            return "bubble \(id) reports bbox \(expected); payload contains \(String(describing: actual))"
        case let .segmentGlyphPixelCountMismatch(expected, actual):
            return "segment mask reports \(expected) glyph pixels; payload contains \(actual)"
        case let .segmentComponentCountMismatch(expected, actual):
            return "segment mask reports \(expected) components; payload contains \(actual)"
        }
    }
}

struct KoharuMaskPixelRect: Equatable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}

struct KoharuMaskRegionStatistics: Equatable, Sendable {
    var sampledPixelCount: Int
    var nonzeroPixelCount: Int
    var nonzeroCoverageRatio: Double
    var majorityNonzeroLabel: Int?
    var majorityNonzeroPixelCount: Int
    var majorityNonzeroCoverageRatio: Double
    var labelPixelCounts: [Int: Int]
}

struct KoharuDecodedMask: Equatable, Sendable {
    let width: Int
    let height: Int
    let pixels: [Int]

    func statistics(in rect: KoharuMaskPixelRect) -> KoharuMaskRegionStatistics {
        let minX = min(max(0, rect.x), width)
        let minY = min(max(0, rect.y), height)
        let maxX = boundedEnd(origin: rect.x, length: rect.width, limit: width)
        let maxY = boundedEnd(origin: rect.y, length: rect.height, limit: height)
        guard minX < maxX, minY < maxY else {
            return KoharuMaskRegionStatistics(
                sampledPixelCount: 0,
                nonzeroPixelCount: 0,
                nonzeroCoverageRatio: 0,
                majorityNonzeroLabel: nil,
                majorityNonzeroPixelCount: 0,
                majorityNonzeroCoverageRatio: 0,
                labelPixelCounts: [:]
            )
        }

        var counts: [Int: Int] = [:]
        for y in minY..<maxY {
            let rowStart = y * width
            for x in minX..<maxX {
                counts[pixels[rowStart + x], default: 0] += 1
            }
        }
        let sampled = (maxX - minX) * (maxY - minY)
        let nonzero = counts.reduce(into: 0) { total, entry in
            if entry.key != 0 { total += entry.value }
        }
        let majority = counts
            .filter { $0.key != 0 }
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .first
        return KoharuMaskRegionStatistics(
            sampledPixelCount: sampled,
            nonzeroPixelCount: nonzero,
            nonzeroCoverageRatio: Double(nonzero) / Double(sampled),
            majorityNonzeroLabel: majority?.key,
            majorityNonzeroPixelCount: majority?.value ?? 0,
            majorityNonzeroCoverageRatio: Double(majority?.value ?? 0) / Double(sampled),
            labelPixelCounts: counts
        )
    }

    func containmentRatio(of label: Int, in rect: KoharuMaskPixelRect) -> Double {
        let total = pixels.reduce(into: 0) { count, pixel in
            if pixel == label { count += 1 }
        }
        guard total > 0 else { return 0 }
        return Double(statistics(in: rect).labelPixelCounts[label, default: 0]) / Double(total)
    }

    private func boundedEnd(origin: Int, length: Int, limit: Int) -> Int {
        guard length > 0 else { return min(max(0, origin), limit) }
        let (end, overflow) = origin.addingReportingOverflow(length)
        return overflow ? limit : min(max(0, end), limit)
    }
}

struct KoharuBubbleMaskInstanceSummary: Equatable, Sendable {
    var id: String
    var bbox: [Double]
    var pixelCount: Int?
    var maskValue: Int?
}

struct KoharuBubbleMaskInstanceEvaluation: Equatable, Sendable {
    var id: String
    var maskValue: Int
    var pixelCount: Int
    var bbox: [Double]
}

struct KoharuValidatedBubbleMask: Equatable, Sendable {
    var mask: KoharuDecodedMask
    var instances: [KoharuBubbleMaskInstanceEvaluation]
}

enum KoharuBubbleMaskPayloadEvaluation: Equatable, Sendable {
    case summaryOnly
    case validated(KoharuValidatedBubbleMask)
}

struct KoharuValidatedSegmentMask: Equatable, Sendable {
    var mask: KoharuDecodedMask
    var glyphPixelCount: Int
    var connectedComponentCount: Int
}

enum KoharuSegmentMaskPayloadEvaluation: Equatable, Sendable {
    case summaryOnly
    case validated(KoharuValidatedSegmentMask)
}

enum KoharuMaskPayloadEvaluator {
    static let rowMajorRLEEncoding = "rowMajorRLE"

    static func evaluateBubble(
        width: Int?,
        height: Int?,
        encoding: String?,
        runs: [[Int]]?,
        instances: [KoharuBubbleMaskInstanceSummary],
        maxPixelCount: Int
    ) throws -> KoharuBubbleMaskPayloadEvaluation {
        guard encoding != nil || runs != nil else { return .summaryOnly }
        guard let width, let height, let encoding, let runs else {
            throw KoharuMaskPayloadError.incompletePayload
        }

        var maskValues = Set<Int>()
        var validatedInstances: [(summary: KoharuBubbleMaskInstanceSummary, maskValue: Int, pixelCount: Int)] = []
        validatedInstances.reserveCapacity(instances.count)
        for instance in instances {
            guard !instance.id.isEmpty,
                  let maskValue = instance.maskValue,
                  maskValue > 0,
                  let pixelCount = instance.pixelCount,
                  pixelCount > 0,
                  instance.bbox.count == 4 else {
                throw KoharuMaskPayloadError.invalidBubbleInstance(id: instance.id)
            }
            guard maskValues.insert(maskValue).inserted else {
                throw KoharuMaskPayloadError.duplicateBubbleMaskValue(maskValue)
            }
            validatedInstances.append((instance, maskValue, pixelCount))
        }

        let mask = try decode(
            width: width,
            height: height,
            encoding: encoding,
            runs: runs,
            allowedLabels: maskValues.union([0]),
            maxPixelCount: maxPixelCount
        )
        var evaluations: [KoharuBubbleMaskInstanceEvaluation] = []
        evaluations.reserveCapacity(instances.count)
        for validated in validatedInstances {
            let instance = validated.summary
            let maskValue = validated.maskValue
            let actualCount = mask.pixels.reduce(into: 0) { count, pixel in
                if pixel == maskValue { count += 1 }
            }
            if validated.pixelCount != actualCount {
                throw KoharuMaskPayloadError.bubblePixelCountMismatch(
                    id: instance.id,
                    expected: validated.pixelCount,
                    actual: actualCount
                )
            }
            let actualBBox = boundingBox(of: maskValue, in: mask)
            guard actualBBox == instance.bbox else {
                throw KoharuMaskPayloadError.bubbleBoundingBoxMismatch(
                    id: instance.id,
                    expected: instance.bbox,
                    actual: actualBBox
                )
            }
            evaluations.append(KoharuBubbleMaskInstanceEvaluation(
                id: instance.id,
                maskValue: maskValue,
                pixelCount: actualCount,
                bbox: instance.bbox
            ))
        }
        return .validated(KoharuValidatedBubbleMask(mask: mask, instances: evaluations))
    }

    static func evaluateSegment(
        width: Int?,
        height: Int?,
        encoding: String?,
        runs: [[Int]]?,
        glyphPixelCount: Int?,
        connectedComponentCount: Int?,
        maxPixelCount: Int
    ) throws -> KoharuSegmentMaskPayloadEvaluation {
        guard encoding != nil || runs != nil else { return .summaryOnly }
        guard let width, let height, let encoding, let runs,
              let glyphPixelCount, let connectedComponentCount,
              glyphPixelCount >= 0, connectedComponentCount >= 0 else {
            throw KoharuMaskPayloadError.incompletePayload
        }
        let mask = try decode(
            width: width,
            height: height,
            encoding: encoding,
            runs: runs,
            allowedLabels: [0, 1],
            maxPixelCount: maxPixelCount
        )
        let actualGlyphPixels = mask.pixels.reduce(into: 0) { count, pixel in
            if pixel == 1 { count += 1 }
        }
        guard actualGlyphPixels == glyphPixelCount else {
            throw KoharuMaskPayloadError.segmentGlyphPixelCountMismatch(
                expected: glyphPixelCount,
                actual: actualGlyphPixels
            )
        }
        let actualComponents = fourConnectedComponentCount(in: mask, foregroundLabel: 1)
        guard actualComponents == connectedComponentCount else {
            throw KoharuMaskPayloadError.segmentComponentCountMismatch(
                expected: connectedComponentCount,
                actual: actualComponents
            )
        }
        return .validated(KoharuValidatedSegmentMask(
            mask: mask,
            glyphPixelCount: actualGlyphPixels,
            connectedComponentCount: actualComponents
        ))
    }

    static func decode(
        width: Int,
        height: Int,
        encoding: String,
        runs: [[Int]],
        allowedLabels: Set<Int>,
        maxPixelCount: Int
    ) throws -> KoharuDecodedMask {
        guard width > 0, height > 0, maxPixelCount > 0 else {
            throw KoharuMaskPayloadError.invalidDimensions
        }
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else { throw KoharuMaskPayloadError.dimensionOverflow }
        guard pixelCount <= maxPixelCount else {
            throw KoharuMaskPayloadError.pixelLimitExceeded(expected: pixelCount, limit: maxPixelCount)
        }
        guard encoding == rowMajorRLEEncoding else {
            throw KoharuMaskPayloadError.unsupportedEncoding(encoding)
        }

        var pixels: [Int] = []
        pixels.reserveCapacity(pixelCount)
        for (index, run) in runs.enumerated() {
            guard run.count == 2 else { throw KoharuMaskPayloadError.invalidRun(index: index) }
            let label = run[0]
            let count = run[1]
            guard allowedLabels.contains(label) else {
                throw KoharuMaskPayloadError.invalidLabel(index: index, label: label)
            }
            guard count > 0 else { throw KoharuMaskPayloadError.invalidRunLength(index: index) }
            guard count <= pixelCount - pixels.count else {
                throw KoharuMaskPayloadError.decodedLengthExceeded(index: index)
            }
            pixels.append(contentsOf: repeatElement(label, count: count))
        }
        guard pixels.count == pixelCount else {
            throw KoharuMaskPayloadError.decodedLengthMismatch(expected: pixelCount, actual: pixels.count)
        }
        return KoharuDecodedMask(width: width, height: height, pixels: pixels)
    }

    static func fourConnectedComponentCount(in mask: KoharuDecodedMask, foregroundLabel: Int) -> Int {
        var visited = Array(repeating: false, count: mask.pixels.count)
        var componentCount = 0
        var stack: [Int] = []
        for start in mask.pixels.indices where mask.pixels[start] == foregroundLabel && !visited[start] {
            componentCount += 1
            visited[start] = true
            stack.append(start)
            while let index = stack.popLast() {
                let x = index % mask.width
                let y = index / mask.width
                if x > 0 { enqueue(index - 1, label: foregroundLabel, mask: mask, visited: &visited, stack: &stack) }
                if x + 1 < mask.width { enqueue(index + 1, label: foregroundLabel, mask: mask, visited: &visited, stack: &stack) }
                if y > 0 { enqueue(index - mask.width, label: foregroundLabel, mask: mask, visited: &visited, stack: &stack) }
                if y + 1 < mask.height { enqueue(index + mask.width, label: foregroundLabel, mask: mask, visited: &visited, stack: &stack) }
            }
        }
        return componentCount
    }

    private static func enqueue(
        _ index: Int,
        label: Int,
        mask: KoharuDecodedMask,
        visited: inout [Bool],
        stack: inout [Int]
    ) {
        guard !visited[index], mask.pixels[index] == label else { return }
        visited[index] = true
        stack.append(index)
    }

    private static func boundingBox(of label: Int, in mask: KoharuDecodedMask) -> [Double]? {
        var minX = mask.width
        var minY = mask.height
        var maxX = -1
        var maxY = -1
        for (index, pixel) in mask.pixels.enumerated() where pixel == label {
            let x = index % mask.width
            let y = index / mask.width
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return [Double(minX), Double(minY), Double(maxX - minX + 1), Double(maxY - minY + 1)]
    }
}
