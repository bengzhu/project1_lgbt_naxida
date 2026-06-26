import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit
import Vision

enum MangaOverlayProbeServiceError: LocalizedError {
    case imageDecodeFailed
    case imageRenderFailed
    case pngEncodeFailed

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:
            "无法解码 test/1.png。"
        case .imageRenderFailed:
            "无法创建漫画探针输出画布。"
        case .pngEncodeFailed:
            "无法编码漫画探针 PNG 输出。"
        }
    }
}

struct MangaOverlayOCRBlock: Identifiable, Equatable, Sendable {
    var id = UUID()
    var text: String
    var confidence: Float?
    var boundingBox: CGRect
    var rotationAngle: Int
}

struct MangaOverlayProbeCropping: Equatable, Sendable {
    var topRatio: CGFloat
    var bottomRatio: CGFloat
    var sideInsetRatio: CGFloat

    static let defaultValue = MangaOverlayProbeCropping(
        topRatio: 0.235,
        bottomRatio: 0.14,
        sideInsetRatio: 0
    )
}

private struct MangaOverlayOCRCandidate: Equatable, Sendable {
    var text: String
    var confidence: Float?
    var boundingBox: CGRect
    var rotationAngle: Int
}

private struct MangaOverlayOCRCluster {
    var candidates: [MangaOverlayOCRCandidate]

    var boundingBox: CGRect {
        candidates.map(\.boundingBox).reduce(.null) { partial, rect in
            partial.union(rect)
        }
    }
}

struct MangaOverlayProbeService: Sendable {
    private static let ocrScale: CGFloat = 2

    func recognizeTextBlocks(
        in imageData: Data,
        cropping: MangaOverlayProbeCropping = .defaultValue
    ) async throws -> (image: CGImage, blocks: [MangaOverlayOCRBlock]) {
        try await Task.detached(priority: .userInitiated) {
            let image = try Self.makeImage(from: imageData)
            let contentRect = Self.contentCropRect(for: image, cropping: cropping)
            let croppedImage = try Self.croppedImage(image, rect: contentRect)
            let scaledImage = try Self.scaledImage(croppedImage, scale: Self.ocrScale)

            let candidates = try [0, 90, 180, 270].flatMap { angle in
                let rotatedImage = try Self.rotatedImage(scaledImage, angle: angle)
                return try Self.recognizeTextCandidates(
                    in: rotatedImage,
                    angle: angle,
                    scaledContentSize: CGSize(width: CGFloat(scaledImage.width), height: CGFloat(scaledImage.height)),
                    contentOrigin: contentRect.origin,
                    scale: Self.ocrScale
                )
            }
            return (image, Self.mergeCandidatesIntoBlocks(candidates, imageSize: CGSize(width: image.width, height: image.height)))
        }.value
    }

    func renderOutputs(
        image: CGImage,
        blocks: [MangaOverlayProbeBlock],
        outputDirectory: URL
    ) async throws -> MangaOverlayProbeOutputFiles {
        try await Task.detached(priority: .userInitiated) {
            try Self.recreateDirectory(outputDirectory)

            let debugURL = outputDirectory.appendingPathComponent("1_debug_boxes.png")
            let overlayURL = outputDirectory.appendingPathComponent("1_translated_overlay.png")
            let debugImage = try Self.drawDebugBoxes(on: image, blocks: blocks)
            let overlayImage = try Self.drawTranslatedOverlay(on: image, blocks: blocks)
            try Self.writePNG(debugImage, to: debugURL)
            try Self.writePNG(overlayImage, to: overlayURL)
            return MangaOverlayProbeOutputFiles(
                debugBoxesImage: debugURL.path,
                overlayImage: overlayURL.path
            )
        }.value
    }

    static func recreateDirectory(_ url: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func writeReport(_ report: MangaOverlayProbeReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
    }

    private static func recognizeTextCandidates(
        in image: CGImage,
        angle: Int,
        scaledContentSize: CGSize,
        contentOrigin: CGPoint,
        scale: CGFloat
    ) throws -> [MangaOverlayOCRCandidate] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        let supportedLanguages = (try? request.supportedRecognitionLanguages()) ?? []
        let englishLanguages = ["en-US", "en"].filter { supportedLanguages.contains($0) }
        if !englishLanguages.isEmpty {
            request.recognitionLanguages = englishLanguages
        }
        request.minimumTextHeight = 0.006

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !Self.isNoise(text) else { return nil }

            let pixelBox = Self.pixelRect(
                from: observation.boundingBox,
                imageSize: CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
            )
            let scaledContentBox = Self.mapRectToOriginal(
                pixelBox,
                angle: angle,
                rotatedSize: CGSize(width: CGFloat(image.width), height: CGFloat(image.height)),
                originalSize: scaledContentSize
            )
            let originalBox = CGRect(
                x: contentOrigin.x + scaledContentBox.minX / scale,
                y: contentOrigin.y + scaledContentBox.minY / scale,
                width: scaledContentBox.width / scale,
                height: scaledContentBox.height / scale
            ).standardized

            return MangaOverlayOCRCandidate(
                text: text,
                confidence: candidate.confidence,
                boundingBox: originalBox,
                rotationAngle: angle
            )
        }
    }

    private static func makeImage(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else {
            throw MangaOverlayProbeServiceError.imageDecodeFailed
        }
        return image
    }

    private static func contentCropRect(for image: CGImage, cropping: MangaOverlayProbeCropping) -> CGRect {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let x = width * cropping.sideInsetRatio
        let y = height * cropping.topRatio
        let bottom = height * cropping.bottomRatio
        return CGRect(
            x: x,
            y: y,
            width: width - x * 2,
            height: max(1, height - y - bottom)
        ).integral
    }

    private static func croppedImage(_ image: CGImage, rect: CGRect) throws -> CGImage {
        guard let cropped = image.cropping(to: rect) else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        return cropped
    }

    private static func scaledImage(_ image: CGImage, scale: CGFloat) throws -> CGImage {
        guard scale != 1 else { return image }
        let width = Int(CGFloat(image.width) * scale)
        let height = Int(CGFloat(image.height) * scale)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard let scaled = context.makeImage() else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        return scaled
    }

    private static func rotatedImage(_ image: CGImage, angle: Int) throws -> CGImage {
        guard angle != 0 else { return image }

        let width = image.width
        let height = image.height
        let outputSize = angle == 180
            ? CGSize(width: CGFloat(width), height: CGFloat(height))
            : CGSize(width: CGFloat(height), height: CGFloat(width))

        guard let context = CGContext(
            data: nil,
            width: Int(outputSize.width),
            height: Int(outputSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }

        switch angle {
        case 90:
            context.translateBy(x: outputSize.width, y: 0)
            context.rotate(by: .pi / 2)
        case 180:
            context.translateBy(x: outputSize.width, y: outputSize.height)
            context.rotate(by: .pi)
        case 270:
            context.translateBy(x: 0, y: outputSize.height)
            context.rotate(by: -.pi / 2)
        default:
            break
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard let rotated = context.makeImage() else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        return rotated
    }

    private static func pixelRect(from normalizedBox: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: normalizedBox.minX * imageSize.width,
            y: (1 - normalizedBox.maxY) * imageSize.height,
            width: normalizedBox.width * imageSize.width,
            height: normalizedBox.height * imageSize.height
        ).standardized
    }

    private static func mapRectToOriginal(
        _ rect: CGRect,
        angle: Int,
        rotatedSize: CGSize,
        originalSize: CGSize
    ) -> CGRect {
        let points = [
            rect.origin,
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ].map { point in
            mapPointToOriginal(point, angle: angle, rotatedSize: rotatedSize, originalSize: originalSize)
        }

        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return clamp(
            CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
            to: CGRect(origin: .zero, size: originalSize)
        )
    }

    private static func mapPointToOriginal(
        _ point: CGPoint,
        angle: Int,
        rotatedSize: CGSize,
        originalSize: CGSize
    ) -> CGPoint {
        switch angle {
        case 90:
            CGPoint(x: originalSize.width - point.y, y: point.x)
        case 180:
            CGPoint(x: originalSize.width - point.x, y: originalSize.height - point.y)
        case 270:
            CGPoint(x: point.y, y: originalSize.height - point.x)
        default:
            point
        }
    }

    private static func mergeCandidatesIntoBlocks(
        _ candidates: [MangaOverlayOCRCandidate],
        imageSize: CGSize
    ) -> [MangaOverlayOCRBlock] {
        let cleanCandidates = deduplicateCandidates(candidates)
            .filter { $0.boundingBox.width >= 14 && $0.boundingBox.height >= 7 }
            .sorted { lhs, rhs in
                if abs(lhs.boundingBox.minY - rhs.boundingBox.minY) > 18 {
                    return lhs.boundingBox.minY < rhs.boundingBox.minY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }

        var clusters: [MangaOverlayOCRCluster] = []
        for candidate in cleanCandidates {
            if let index = clusters.firstIndex(where: { shouldCluster(candidate, with: $0) }) {
                clusters[index].candidates.append(candidate)
            } else {
                clusters.append(MangaOverlayOCRCluster(candidates: [candidate]))
            }
        }

        return mergeOverlappingClusters(clusters)
            .map { cluster in
                let ordered = orderedCandidates(cluster.candidates)
                let text = mergeText(from: ordered)
                let confidenceValues = ordered.compactMap(\.confidence)
                let confidence = confidenceValues.isEmpty
                    ? nil
                    : confidenceValues.reduce(0, +) / Float(confidenceValues.count)
                let angle = dominantAngle(in: ordered)
                return MangaOverlayOCRBlock(
                    text: text,
                    confidence: confidence,
                    boundingBox: clamp(cluster.boundingBox.insetBy(dx: -6, dy: -6), to: CGRect(origin: .zero, size: imageSize)),
                    rotationAngle: angle
                )
            }
            .filter { !$0.text.isEmpty }
            .sorted {
                if abs($0.boundingBox.minY - $1.boundingBox.minY) > 20 {
                    return $0.boundingBox.minY < $1.boundingBox.minY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
    }

    private static func shouldCluster(_ candidate: MangaOverlayOCRCandidate, with cluster: MangaOverlayOCRCluster) -> Bool {
        let candidateBox = candidate.boundingBox
        let clusterBox = cluster.boundingBox
        if overlapRatio(candidateBox, clusterBox) > 0.18 {
            return true
        }

        let verticalGap = max(0, max(candidateBox.minY - clusterBox.maxY, clusterBox.minY - candidateBox.maxY))
        let horizontalIntersection = max(0, min(candidateBox.maxX, clusterBox.maxX) - max(candidateBox.minX, clusterBox.minX))
        let horizontalOverlap = horizontalIntersection / max(1, min(candidateBox.width, clusterBox.width))
        let centerDeltaX = abs(candidateBox.midX - clusterBox.midX)

        let sameColumn = horizontalOverlap > 0.18 || centerDeltaX < max(24, clusterBox.width * 0.28)
        let nearbyLine = verticalGap < max(18, min(candidateBox.height, clusterBox.height) * 1.4)
        return sameColumn && nearbyLine
    }

    private static func mergeOverlappingClusters(_ input: [MangaOverlayOCRCluster]) -> [MangaOverlayOCRCluster] {
        var clusters = input
        var didMerge = true

        while didMerge {
            didMerge = false
            outer: for leftIndex in clusters.indices {
                for rightIndex in clusters.indices where rightIndex > leftIndex {
                    guard shouldMergeClusters(clusters[leftIndex], clusters[rightIndex]) else { continue }
                    clusters[leftIndex].candidates.append(contentsOf: clusters[rightIndex].candidates)
                    clusters.remove(at: rightIndex)
                    didMerge = true
                    break outer
                }
            }
        }

        return clusters
    }

    private static func shouldMergeClusters(_ lhs: MangaOverlayOCRCluster, _ rhs: MangaOverlayOCRCluster) -> Bool {
        let lhsBox = lhs.boundingBox
        let rhsBox = rhs.boundingBox
        if overlapRatio(lhsBox, rhsBox) > 0.12 {
            return true
        }

        let verticalGap = max(0, max(lhsBox.minY - rhsBox.maxY, rhsBox.minY - lhsBox.maxY))
        let horizontalIntersection = max(0, min(lhsBox.maxX, rhsBox.maxX) - max(lhsBox.minX, rhsBox.minX))
        let horizontalOverlap = horizontalIntersection / max(1, min(lhsBox.width, rhsBox.width))
        let centerDeltaX = abs(lhsBox.midX - rhsBox.midX)
        return verticalGap < 12
            && (horizontalOverlap > 0.45 || centerDeltaX < min(lhsBox.width, rhsBox.width) * 0.35)
    }

    private static func deduplicateCandidates(_ candidates: [MangaOverlayOCRCandidate]) -> [MangaOverlayOCRCandidate] {
        var result: [MangaOverlayOCRCandidate] = []
        for candidate in candidates.sorted(by: isBetterCandidate) {
            guard !result.contains(where: { isDuplicateCandidate(candidate, of: $0) }) else { continue }
            result.append(candidate)
        }
        return result
    }

    private static func isBetterCandidate(_ lhs: MangaOverlayOCRCandidate, _ rhs: MangaOverlayOCRCandidate) -> Bool {
        let lhsScore = Double(lhs.text.count) + Double(lhs.confidence ?? 0) * 8 - Double(lhs.rotationAngle == 0 ? 0 : 1)
        let rhsScore = Double(rhs.text.count) + Double(rhs.confidence ?? 0) * 8 - Double(rhs.rotationAngle == 0 ? 0 : 1)
        return lhsScore > rhsScore
    }

    private static func isDuplicateCandidate(_ candidate: MangaOverlayOCRCandidate, of existing: MangaOverlayOCRCandidate) -> Bool {
        guard overlapRatio(candidate.boundingBox, existing.boundingBox) > 0.48 else { return false }
        let lhs = normalizedOCRText(candidate.text)
        let rhs = normalizedOCRText(existing.text)
        return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs) || textSimilarity(lhs, rhs) > 0.76
    }

    private static func normalizedOCRText(_ text: String) -> String {
        text
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func textSimilarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let lhsBigrams = bigrams(lhs)
        let rhsBigrams = bigrams(rhs)
        guard !lhsBigrams.isEmpty, !rhsBigrams.isEmpty else {
            return lhs == rhs ? 1 : 0
        }
        let commonCount = lhsBigrams.intersection(rhsBigrams).count
        return Double(commonCount * 2) / Double(lhsBigrams.count + rhsBigrams.count)
    }

    private static func bigrams(_ text: String) -> Set<String> {
        let characters = Array(text)
        guard characters.count > 1 else { return Set(characters.map(String.init)) }
        return Set(characters.indices.dropLast().map { index in
            String(characters[index]) + String(characters[characters.index(after: index)])
        })
    }

    private static func orderedCandidates(_ candidates: [MangaOverlayOCRCandidate]) -> [MangaOverlayOCRCandidate] {
        candidates.sorted {
            if abs($0.boundingBox.minY - $1.boundingBox.minY) > max(8, min($0.boundingBox.height, $1.boundingBox.height) * 0.7) {
                return $0.boundingBox.minY < $1.boundingBox.minY
            }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
    }

    private static func mergeText(from candidates: [MangaOverlayOCRCandidate]) -> String {
        var lines: [String] = []
        var currentLine: [MangaOverlayOCRCandidate] = []

        for candidate in deduplicateLineText(candidates) {
            if let last = currentLine.last,
               abs(candidate.boundingBox.midY - last.boundingBox.midY) > max(10, last.boundingBox.height * 0.75) {
                lines.append(currentLine.map(\.text).joined(separator: " "))
                currentLine = [candidate]
            } else {
                currentLine.append(candidate)
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine.map(\.text).joined(separator: " "))
        }

        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func deduplicateLineText(_ candidates: [MangaOverlayOCRCandidate]) -> [MangaOverlayOCRCandidate] {
        var seen = Set<String>()
        var output: [MangaOverlayOCRCandidate] = []
        for candidate in candidates {
            let key = normalizedOCRText(candidate.text)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(candidate)
        }
        return output
    }

    private static func dominantAngle(in candidates: [MangaOverlayOCRCandidate]) -> Int {
        let grouped = Dictionary(grouping: candidates, by: \.rotationAngle)
        return grouped.max { lhs, rhs in
            let lhsScore = lhs.value.reduce(0) { $0 + $1.text.count }
            let rhsScore = rhs.value.reduce(0) { $0 + $1.text.count }
            return lhsScore < rhsScore
        }?.key ?? 0
    }

    private static func overlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let minArea = max(1, min(lhs.width * lhs.height, rhs.width * rhs.height))
        return intersectionArea / minArea
    }

    private static func drawDebugBoxes(on image: CGImage, blocks: [MangaOverlayProbeBlock]) throws -> CGImage {
        try draw(on: image) { context, _ in
            context.setStrokeColor(CGColor(red: 1, green: 0.08, blue: 0.18, alpha: 1))
            context.setLineWidth(max(3, CGFloat(image.width) * 0.006))

            for block in blocks {
                let rect = rect(from: block.bbox)
                context.stroke(rect)
                drawText(
                    "#\(block.index)",
                    in: CGRect(x: rect.minX, y: max(0, rect.minY - 30), width: 80, height: 28),
                    fontSize: 22,
                    textColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                    backgroundColor: CGColor(red: 1, green: 0.08, blue: 0.18, alpha: 0.88),
                    context: context
                )
            }
        }
    }

    private static func drawTranslatedOverlay(on image: CGImage, blocks: [MangaOverlayProbeBlock]) throws -> CGImage {
        try draw(on: image) { context, _ in
            for block in blocks where !block.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let expanded = expand(rect(from: block.bbox), by: 0.14, bounds: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
                let background = sampleBackgroundColor(image: image, near: expanded)
                context.setFillColor(background)
                context.fill(expanded)
                context.setStrokeColor(CGColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 0.25))
                context.setLineWidth(1.5)
                context.stroke(expanded)

                let inset = max(4, min(expanded.width, expanded.height) * 0.08)
                let textRect = expanded.insetBy(dx: inset, dy: inset)
                drawFittingText(
                    block.translatedText,
                    in: textRect,
                    context: context
                )
            }
        }
    }

    private static func draw(
        on image: CGImage,
        actions: (CGContext, CGSize) throws -> Void
    ) throws -> CGImage {
        let size = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        var renderError: Error?
        let rendered = renderer.image { rendererContext in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
            do {
                try actions(rendererContext.cgContext, size)
            } catch {
                renderError = error
            }
        }
        if let renderError {
            throw renderError
        }
        guard let output = rendered.cgImage else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        return output
    }

    private static func drawFittingText(_ text: String, in rect: CGRect, context: CGContext) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        var fontSize = min(max(10, rect.height * 0.46), 32)
        while fontSize > 9 {
            let lines = wrappedLines(cleanText, fontSize: fontSize, maxWidth: rect.width)
            let lineHeight = fontSize * 1.18
            if CGFloat(lines.count) * lineHeight <= rect.height {
                drawLines(lines, in: rect, fontSize: fontSize, lineHeight: lineHeight, context: context)
                return
            }
            fontSize -= 1
        }

        let lines = wrappedLines(cleanText, fontSize: fontSize, maxWidth: rect.width)
        drawLines(Array(lines.prefix(max(1, Int(rect.height / (fontSize * 1.18))))), in: rect, fontSize: fontSize, lineHeight: fontSize * 1.18, context: context)
    }

    private static func drawLines(
        _ lines: [String],
        in rect: CGRect,
        fontSize: CGFloat,
        lineHeight: CGFloat,
        context: CGContext
    ) {
        let totalHeight = CGFloat(lines.count) * lineHeight
        var y = rect.minY + max(0, (rect.height - totalHeight) / 2)
        for line in lines {
            drawText(
                line,
                in: CGRect(x: rect.minX, y: y, width: rect.width, height: lineHeight),
                fontSize: fontSize,
                textColor: CGColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1),
                backgroundColor: nil,
                context: context
            )
            y += lineHeight
        }
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        fontSize: CGFloat,
        textColor: CGColor,
        backgroundColor: CGColor?,
        context: CGContext
    ) {
        if let backgroundColor {
            context.setFillColor(backgroundColor)
            context.fill(rect)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: UIColor(cgColor: textColor)
        ]
        (text as NSString).draw(in: rect.insetBy(dx: 3, dy: 0), withAttributes: attributes)
    }

    private static func wrappedLines(_ text: String, fontSize: CGFloat, maxWidth: CGFloat) -> [String] {
        var lines: [String] = []
        var current = ""
        for character in text {
            let candidate = current.isEmpty ? String(character) : current + String(character)
            if estimatedTextWidth(candidate, fontSize: fontSize) <= maxWidth || current.isEmpty {
                current = candidate
            } else {
                lines.append(current)
                current = String(character)
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }

    private static func estimatedTextWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        text.reduce(0) { width, character in
            let scalar = String(character).unicodeScalars.first?.value ?? 0
            let isASCII = scalar < 128
            return width + fontSize * (isASCII ? 0.58 : 1.02)
        }
    }

    private static func sampleBackgroundColor(image: CGImage, near rect: CGRect) -> CGColor {
        guard let providerData = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(providerData),
              image.bitsPerPixel == 32 else {
            return CGColor(red: 1, green: 1, blue: 1, alpha: 0.94)
        }

        let bytesPerRow = image.bytesPerRow
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        let ring = expand(rect, by: 0.24, bounds: bounds)
        var samples: [(Int, Int, Int)] = []
        let step = max(1, Int(min(ring.width, ring.height) / 12))
        for y in stride(from: Int(ring.minY), through: Int(ring.maxY), by: step) {
            for x in stride(from: Int(ring.minX), through: Int(ring.maxX), by: step) {
                guard !rect.contains(CGPoint(x: CGFloat(x), y: CGFloat(y))), x >= 0, y >= 0, x < image.width, y < image.height else { continue }
                let offset = y * bytesPerRow + x * 4
                samples.append((Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2])))
            }
        }

        guard !samples.isEmpty else {
            return CGColor(red: 1, green: 1, blue: 1, alpha: 0.94)
        }
        let sorted = samples.sorted { lhs, rhs in
            lhs.0 + lhs.1 + lhs.2 > rhs.0 + rhs.1 + rhs.2
        }
        let picked = sorted[min(sorted.count - 1, max(0, sorted.count / 6))]
        return CGColor(
            red: Double(picked.0) / 255,
            green: Double(picked.1) / 255,
            blue: Double(picked.2) / 255,
            alpha: 0.96
        )
    }

    private static func rect(from bbox: [Double]) -> CGRect {
        guard bbox.count == 4 else { return .zero }
        return CGRect(x: bbox[0], y: bbox[1], width: bbox[2], height: bbox[3]).standardized
    }

    private static func expand(_ rect: CGRect, by fraction: Double, bounds: CGRect) -> CGRect {
        let dx = max(5, rect.width * fraction)
        let dy = max(5, rect.height * fraction)
        return clamp(rect.insetBy(dx: -dx, dy: -dy), to: bounds)
    }

    private static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let minX = max(bounds.minX, rect.minX)
        let minY = max(bounds.minY, rect.minY)
        let maxX = min(bounds.maxX, rect.maxX)
        let maxY = min(bounds.maxY, rect.maxY)
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw MangaOverlayProbeServiceError.pngEncodeFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw MangaOverlayProbeServiceError.pngEncodeFailed
        }
    }

    private static func isNoise(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lettersOrNumbers = trimmed.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        let letters = trimmed.unicodeScalars.filter {
            CharacterSet.letters.contains($0)
        }
        return trimmed.count <= 1 && lettersOrNumbers.isEmpty
            || lettersOrNumbers.isEmpty
            || letters.count < 2
            || trimmed.localizedCaseInsensitiveContains("nhentai.net")
            || trimmed.localizedCaseInsensitiveContains("of 36")
            || trimmed.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
    }

    private static func isBrowserChrome(_ rect: CGRect, imageHeight: CGFloat) -> Bool {
        rect.minY < 160 || rect.maxY > imageHeight - 95
    }
}
