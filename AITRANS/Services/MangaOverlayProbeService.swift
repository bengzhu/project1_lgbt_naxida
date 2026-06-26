import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
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

struct MangaOverlayProbeService: Sendable {
    func recognizeTextBlocks(in imageData: Data) async throws -> (image: CGImage, blocks: [MangaOverlayOCRBlock]) {
        try await Task.detached(priority: .userInitiated) {
            let image = try Self.makeImage(from: imageData)
            let blocksByAngle = try [0, 90, 180, 270].flatMap { angle in
                let rotatedImage = try Self.rotatedImage(image, angle: angle)
                return try Self.recognizeTextBlocks(in: rotatedImage, angle: angle, originalImage: image)
            }
            return (image, Self.mergeDuplicateBlocks(blocksByAngle))
        }.value
    }

    func renderOutputs(
        image: CGImage,
        blocks: [MangaOverlayProbeBlock],
        outputDirectory: URL
    ) async throws -> MangaOverlayProbeOutputFiles {
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

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

    static func writeReport(_ report: MangaOverlayProbeReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
    }

    private static func recognizeTextBlocks(
        in image: CGImage,
        angle: Int,
        originalImage: CGImage
    ) throws -> [MangaOverlayOCRBlock] {
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
            let originalBox = Self.mapRectToOriginal(
                pixelBox,
                angle: angle,
                rotatedSize: CGSize(width: CGFloat(image.width), height: CGFloat(image.height)),
                originalSize: CGSize(width: CGFloat(originalImage.width), height: CGFloat(originalImage.height))
            )
            guard !Self.isBrowserChrome(originalBox, imageHeight: CGFloat(originalImage.height)) else { return nil }

            return MangaOverlayOCRBlock(
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

    private static func mergeDuplicateBlocks(_ blocks: [MangaOverlayOCRBlock]) -> [MangaOverlayOCRBlock] {
        var merged: [MangaOverlayOCRBlock] = []
        for block in blocks.sorted(by: isBetterBlock) {
            guard !merged.contains(where: { shouldMerge($0, block) }) else { continue }
            merged.append(block)
        }

        return merged.sorted {
            let yDelta = abs($0.boundingBox.minY - $1.boundingBox.minY)
            if yDelta > 14 {
                return $0.boundingBox.minY < $1.boundingBox.minY
            }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
    }

    private static func isBetterBlock(_ lhs: MangaOverlayOCRBlock, _ rhs: MangaOverlayOCRBlock) -> Bool {
        let lhsScore = Double(lhs.text.count) + Double(lhs.confidence ?? 0) * 8
        let rhsScore = Double(rhs.text.count) + Double(rhs.confidence ?? 0) * 8
        return lhsScore > rhsScore
    }

    private static func shouldMerge(_ lhs: MangaOverlayOCRBlock, _ rhs: MangaOverlayOCRBlock) -> Bool {
        let intersection = lhs.boundingBox.intersection(rhs.boundingBox)
        guard !intersection.isNull else { return false }
        let minArea = max(1, min(lhs.boundingBox.width * lhs.boundingBox.height, rhs.boundingBox.width * rhs.boundingBox.height))
        let overlap = (intersection.width * intersection.height) / minArea
        return overlap > 0.35 || lhs.text.localizedCaseInsensitiveCompare(rhs.text) == .orderedSame
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
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }

        context.draw(image, in: CGRect(origin: .zero, size: size))
        try actions(context, size)
        guard let output = context.makeImage() else {
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
            .font: CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil),
            .foregroundColor: textColor
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: rect.minX + 3, y: CGFloat(context.height) - rect.maxY + (rect.height - fontSize) / 2)
        CTLineDraw(line, context)
        context.restoreGState()
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
        return trimmed.count <= 1 && lettersOrNumbers.isEmpty
            || lettersOrNumbers.isEmpty
            || trimmed.localizedCaseInsensitiveContains("nhentai.net")
            || trimmed.localizedCaseInsensitiveContains("of 36")
            || trimmed.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
    }

    private static func isBrowserChrome(_ rect: CGRect, imageHeight: CGFloat) -> Bool {
        rect.minY < 160 || rect.maxY > imageHeight - 95
    }
}
