import CoreGraphics
import Foundation
import ImageIO
import Vision

enum VisionOCRServiceError: LocalizedError {
    case imageDecodeFailed
    case imageRenderFailed

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:
            "无法解码图片，请选择 PNG、JPEG 或系统支持的图片格式"
        case .imageRenderFailed:
            "无法准备日语竖排 OCR 方向图片，请重试或选择其他图片"
        }
    }
}

struct VisionOCRService: Sendable {
    func recognizeTextBlocks(in imageData: Data, sourceLanguage: SupportedLanguage) async throws -> [ImageTranslationBlock] {
        let task = Task.detached(priority: .userInitiated) {
            let ocrImage = try Self.makeOCRImage(from: imageData)
            let preferredLanguages = sourceLanguage.visionRecognitionLanguageIdentifiers
            var observations = try Self.recognizeObservations(
                in: ocrImage,
                recognitionLanguages: preferredLanguages,
                minimumTextHeight: 0.012,
                automaticallyDetectsLanguage: true,
                rotationApplied: 0
            )

            if sourceLanguage == .japanese {
                // Koharu keeps detection/layout separate from recognition and gives Japanese
                // candidates a bounded orientation comparison before its cropped OCR engines.
                // Vision is the on-device engine here, so use the same first migration step:
                // re-read the page in both rotated orientations, map boxes back, then let the
                // existing layout engine restore manga right-to-left vertical order. Running
                // both directions matters because a photographed page can be mirrored or
                // presented with either vertical writing direction.
                let japaneseOrientationLanguages = ["ja-JP", "ja", "en-US", "en"]
                for angle in [90, 270] {
                    let rotatedOCRImage = try Self.rotatedImage(ocrImage, angle: angle)
                    let rotatedObservations = try Self.recognizeObservations(
                        in: rotatedOCRImage,
                        recognitionLanguages: japaneseOrientationLanguages,
                        minimumTextHeight: 0.006,
                        automaticallyDetectsLanguage: false,
                        rotationApplied: angle
                    ).map {
                        Self.mapRotatedObservation(
                            $0,
                            rotatedImage: rotatedOCRImage,
                            originalImage: ocrImage,
                            angle: angle
                        )
                    }
                    observations.append(contentsOf: rotatedObservations)
                }

                // Koharu crops each detected text node before handing it to the OCR
                // engine. The iOS path has no bundled Manga OCR/PaddleOCR model yet,
                // so mirror that boundary with a bounded Vision crop reread: use the
                // existing vertical layout candidates, crop only those nodes, reread
                // the chosen orientation, map the boxes back, then dedupe again.
                let cropRefinedObservations = Self.recognizeJapaneseVerticalCrops(
                    in: ocrImage,
                    observations: observations,
                    recognitionLanguages: japaneseOrientationLanguages
                )
                observations.append(contentsOf: cropRefinedObservations)
            }

            let layoutObservations = Self.deduplicateObservations(observations).map {
                ImageOCRLayoutObservation(
                    text: $0.text,
                    confidence: $0.confidence,
                    rect: $0.rect
                )
            }
            let allowsVerticalText = sourceLanguage == .japanese || sourceLanguage == .simplifiedChinese
            return ImageOCRLayoutEngine.layout(
                layoutObservations,
                allowsVerticalText: allowsVerticalText
            ).map { block in
                ImageTranslationBlock(
                    original: block.text,
                    confidence: block.confidence,
                    boundingBox: NormalizedImageRect(
                        x: block.rect.x,
                        y: block.rect.y,
                        width: block.rect.width,
                        height: block.rect.height
                    ),
                    sourceDirection: ImageTextDirection(rawValue: block.direction.rawValue) ?? .unknown,
                    directionConfidence: block.directionConfidence,
                    directionReason: block.directionReason
                )
            }
        }

        return try await task.value
    }

    private static func recognizeObservations(
        in image: CGImage,
        recognitionLanguages: [String],
        minimumTextHeight: Float,
        automaticallyDetectsLanguage: Bool,
        rotationApplied: Int
    ) throws -> [VisionOCRObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = automaticallyDetectsLanguage
        request.minimumTextHeight = minimumTextHeight

        let supportedLanguages = (try? request.supportedRecognitionLanguages()) ?? []
        let availableLanguages = recognitionLanguages.filter { supportedLanguages.contains($0) }
        if !availableLanguages.isEmpty {
            request.recognitionLanguages = availableLanguages
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            guard let rect = Self.normalizedRect(from: observation.boundingBox) else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return VisionOCRObservation(
                text: text,
                confidence: candidate.confidence,
                rect: rect,
                lineRegionRect: Self.recognizedTextRegionRect(
                    for: candidate,
                    fallback: rect
                ),
                rotationApplied: rotationApplied
            )
        }
    }

    private static func recognizedTextRegionRect(
        for candidate: VNRecognizedText,
        fallback: ImageOCRLayoutRect
    ) -> ImageOCRLayoutRect {
        let range = candidate.string.startIndex..<candidate.string.endIndex
        do {
            if let rangeObservation = try candidate.boundingBox(for: range),
               let rangeRect = normalizedRect(from: rangeObservation.boundingBox),
               isUsableTextRegion(rangeRect, relativeTo: fallback) {
                return rangeRect
            }
        } catch {
            // Vision may not provide character-range geometry for every revision;
            // the request-level observation remains the safe Koharu line proxy.
        }
        return fallback
    }

    private static func isUsableTextRegion(
        _ candidate: ImageOCRLayoutRect,
        relativeTo fallback: ImageOCRLayoutRect
    ) -> Bool {
        let candidateArea = candidate.width * candidate.height
        let fallbackArea = max(fallback.width * fallback.height, 0.0001)
        let areaRatio = candidateArea / fallbackArea
        return overlapRatio(candidate, fallback) >= 0.45
            && areaRatio >= 0.25
            && areaRatio <= 1.25
    }

    private static func recognizeJapaneseVerticalCrops(
        in image: CGImage,
        observations: [VisionOCRObservation],
        recognitionLanguages: [String]
    ) -> [VisionOCRObservation] {
        let safeObservations = deduplicateObservations(observations)
        let layoutObservations = safeObservations.map {
            ImageOCRLayoutObservation(
                text: $0.text,
                confidence: $0.confidence,
                rect: $0.rect
            )
        }
        let verticalBlocks = ImageOCRLayoutEngine.layout(
            layoutObservations,
            allowsVerticalText: true
        )
        .filter { block in
            let aspectRatio = block.rect.height / max(block.rect.width, 0.001)
            return block.direction == .vertical
                && aspectRatio >= 1.45
                && block.rect.height >= 0.04
        }
        .sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            if lhs.rect.height != rhs.rect.height {
                return lhs.rect.height > rhs.rect.height
            }
            return lhs.text < rhs.text
        }
        .prefix(16)

        var refined: [VisionOCRObservation] = []
        refined.reserveCapacity(verticalBlocks.count * 2)
        for block in verticalBlocks {
            let angle = safeObservations
                .filter { overlapRatio($0.rect, block.rect) >= 0.25 }
                .sorted { isBetterObservation($0, $1) }
                .first
                .map { $0.rotationApplied == 270 ? 270 : 90 }
                ?? 90
            guard let crop = cropImage(image, normalizedRect: expandedVerticalCropRect(block.rect)),
                  let rotatedCrop = try? rotatedImage(crop.image, angle: angle),
                  let cropObservations = try? recognizeObservations(
                      in: rotatedCrop,
                      recognitionLanguages: recognitionLanguages,
                      minimumTextHeight: 0.004,
                      automaticallyDetectsLanguage: false,
                      rotationApplied: angle
                  ) else {
                continue
            }

            refined.append(contentsOf: cropObservations.map {
                mapRotatedCropObservation(
                    $0,
                    rotatedImage: rotatedCrop,
                    cropRect: crop.rect,
                    originalImage: image,
                    angle: angle
                )
            })
        }

        // Koharu's extract_text_block_regions prefers detector line polygons when
        // available. Vision does not expose those polygons, so use the mapped,
        // deduplicated vertical observations as conservative line-region proxies.
        // Each proxy gets its own direction-aware crop and a small upscale before
        // OCR, keeping narrow Japanese glyph columns out of a larger block crop.
        refined.append(contentsOf: Self.recognizeJapaneseVerticalLineCrops(
            in: image,
            observations: safeObservations,
            blocks: Array(verticalBlocks),
            recognitionLanguages: recognitionLanguages
        ))
        return refined
    }

    private static func recognizeJapaneseVerticalLineCrops(
        in image: CGImage,
        observations: [VisionOCRObservation],
        blocks: [ImageOCRLayoutBlock],
        recognitionLanguages: [String]
    ) -> [VisionOCRObservation] {
        let safeObservations = deduplicateObservations(observations)
        var candidates: [VisionOCRObservation] = []
        for block in blocks {
            candidates.append(contentsOf: safeObservations.filter { observation in
                overlapRatio(observation.rect, block.rect) >= 0.25
                    && isVerticalLineCandidate(observation.rect)
            })
        }

        var uniqueCandidates: [VisionOCRObservation] = []
        for candidate in candidates.sorted(by: { isBetterObservation($0, $1) }) {
            guard !uniqueCandidates.contains(where: {
                isDuplicateObservation(candidate, of: $0)
            }) else {
                continue
            }
            uniqueCandidates.append(candidate)
        }

        var refined: [VisionOCRObservation] = []
        refined.reserveCapacity(min(uniqueCandidates.count, 24) * 2)
        for candidate in uniqueCandidates.prefix(24) {
            let cropRect = expandedVerticalLineCropRect(for: candidate)
            guard let crop = cropImage(image, normalizedRect: cropRect) else {
                continue
            }

            let cropScale: CGFloat
            let scaledCrop: CGImage
            if let resized = resizedImage(crop.image, scale: 2) {
                scaledCrop = resized
                cropScale = 2
            } else {
                scaledCrop = crop.image
                cropScale = 1
            }

            let angle = candidate.rotationApplied == 270 ? 270 : 90
            guard let rotatedCrop = try? rotatedImage(scaledCrop, angle: angle),
                  let cropObservations = try? recognizeObservations(
                      in: rotatedCrop,
                      recognitionLanguages: recognitionLanguages,
                      minimumTextHeight: 0.002,
                      automaticallyDetectsLanguage: false,
                      rotationApplied: angle
                  ) else {
                continue
            }

            refined.append(contentsOf: cropObservations.map {
                mapRotatedCropObservation(
                    $0,
                    rotatedImage: rotatedCrop,
                    cropRect: crop.rect,
                    originalImage: image,
                    angle: angle,
                    cropScale: cropScale
                )
            })
        }
        return refined
    }

    private static func isVerticalLineCandidate(_ rect: ImageOCRLayoutRect) -> Bool {
        rect.height / max(rect.width, 0.001) >= 1.25
            && rect.height >= 0.018
    }

    private static func expandedVerticalLineCropRect(_ rect: ImageOCRLayoutRect) -> ImageOCRLayoutRect {
        // Mirrors Koharu's vertical TextRegion padding: give the reading axis
        // enough context without swallowing a neighboring Japanese column.
        let horizontalPadding = min(max(rect.width * 0.18, 0.008), 0.06)
        let verticalPadding = min(max(rect.height * 0.12, 0.006), 0.06)
        return ImageOCRLayoutRect(
            x: rect.x - horizontalPadding,
            y: rect.y - verticalPadding,
            width: rect.width + horizontalPadding * 2,
            height: rect.height + verticalPadding * 2
        ).normalizedToUnit() ?? rect
    }

    private static func expandedVerticalLineCropRect(
        for observation: VisionOCRObservation
    ) -> ImageOCRLayoutRect {
        let region = observation.lineRegionRect ?? observation.rect
        return expandedVerticalLineCropRect(region)
    }

    private static func expandedVerticalCropRect(_ rect: ImageOCRLayoutRect) -> ImageOCRLayoutRect {
        let horizontalPadding = min(max(rect.width * 0.18, 0.01), 0.08)
        let verticalPadding = min(max(rect.height * 0.12, 0.01), 0.08)
        return ImageOCRLayoutRect(
            x: rect.x - horizontalPadding,
            y: rect.y - verticalPadding,
            width: rect.width + horizontalPadding * 2,
            height: rect.height + verticalPadding * 2
        ).normalizedToUnit() ?? rect
    }

    private static func cropImage(
        _ image: CGImage,
        normalizedRect: ImageOCRLayoutRect
    ) -> (image: CGImage, rect: CGRect)? {
        let bounds = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
        let pixelRect = CGRect(
            x: normalizedRect.x * bounds.width,
            y: normalizedRect.y * bounds.height,
            width: normalizedRect.width * bounds.width,
            height: normalizedRect.height * bounds.height
        )
        .integral
        .intersection(bounds)
        guard pixelRect.width >= 2, pixelRect.height >= 2,
              let cropped = image.cropping(to: pixelRect) else {
            return nil
        }
        return (cropped, pixelRect)
    }

    private static func resizedImage(_ image: CGImage, scale: CGFloat) -> CGImage? {
        guard scale.isFinite, scale > 0 else { return nil }
        let width = max(Int((CGFloat(image.width) * scale).rounded()), 1)
        let height = max(Int((CGFloat(image.height) * scale).rounded()), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        )
        return context.makeImage()
    }

    private static func mapRotatedCropObservation(
        _ observation: VisionOCRObservation,
        rotatedImage: CGImage,
        cropRect: CGRect,
        originalImage: CGImage,
        angle: Int,
        cropScale: CGFloat = 1
    ) -> VisionOCRObservation {
        let rotatedSize = CGSize(width: CGFloat(rotatedImage.width), height: CGFloat(rotatedImage.height))
        let cropSize = CGSize(width: cropRect.width, height: cropRect.height)
        let originalSize = CGSize(width: CGFloat(originalImage.width), height: CGFloat(originalImage.height))
        let unscaledRotatedSize = angle == 90 || angle == 270
            ? CGSize(width: cropSize.height, height: cropSize.width)
            : cropSize
        let scaleX = rotatedSize.width / max(unscaledRotatedSize.width, 1)
        let scaleY = rotatedSize.height / max(unscaledRotatedSize.height, 1)
        let safeScale = cropScale.isFinite && cropScale > 0 ? cropScale : 1
        let pixelRect = CGRect(
            x: observation.rect.x * rotatedSize.width,
            y: observation.rect.y * rotatedSize.height,
            width: observation.rect.width * rotatedSize.width,
            height: observation.rect.height * rotatedSize.height
        )
        let points = [
            pixelRect.origin,
            CGPoint(x: pixelRect.maxX, y: pixelRect.minY),
            CGPoint(x: pixelRect.minX, y: pixelRect.maxY),
            CGPoint(x: pixelRect.maxX, y: pixelRect.maxY)
        ].map {
            let unscaledPoint = CGPoint(
                x: $0.x / max(scaleX, safeScale),
                y: $0.y / max(scaleY, safeScale)
            )
            let local = Self.mapPointToOriginal(unscaledPoint, angle: angle, originalSize: cropSize)
            return CGPoint(x: cropRect.minX + local.x, y: cropRect.minY + local.y)
        }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? cropRect.minX
        let maxX = xs.max() ?? cropRect.maxX
        let minY = ys.min() ?? cropRect.minY
        let maxY = ys.max() ?? cropRect.maxY
        let originalRect = ImageOCRLayoutRect(
            x: minX / originalSize.width,
            y: minY / originalSize.height,
            width: (maxX - minX) / originalSize.width,
            height: (maxY - minY) / originalSize.height
        ).normalizedToUnit() ?? observation.rect
        let originalLineRegionRect = observation.lineRegionRect.map {
            mapRotatedCropRegionRect(
                $0,
                rotatedImage: rotatedImage,
                cropRect: cropRect,
                originalImage: originalImage,
                angle: angle,
                cropScale: cropScale
            )
        }
        return VisionOCRObservation(
            text: observation.text,
            confidence: observation.confidence,
            rect: originalRect,
            lineRegionRect: originalLineRegionRect,
            rotationApplied: observation.rotationApplied
        )
    }

    private static func mapRotatedCropRegionRect(
        _ region: ImageOCRLayoutRect,
        rotatedImage: CGImage,
        cropRect: CGRect,
        originalImage: CGImage,
        angle: Int,
        cropScale: CGFloat
    ) -> ImageOCRLayoutRect {
        let rotatedSize = CGSize(width: CGFloat(rotatedImage.width), height: CGFloat(rotatedImage.height))
        let cropSize = CGSize(width: cropRect.width, height: cropRect.height)
        let originalSize = CGSize(width: CGFloat(originalImage.width), height: CGFloat(originalImage.height))
        let unscaledRotatedSize = angle == 90 || angle == 270
            ? CGSize(width: cropSize.height, height: cropSize.width)
            : cropSize
        let scaleX = rotatedSize.width / max(unscaledRotatedSize.width, 1)
        let scaleY = rotatedSize.height / max(unscaledRotatedSize.height, 1)
        let safeScale = cropScale.isFinite && cropScale > 0 ? cropScale : 1
        let pixelRect = CGRect(
            x: region.x * rotatedSize.width,
            y: region.y * rotatedSize.height,
            width: region.width * rotatedSize.width,
            height: region.height * rotatedSize.height
        )
        let points = [
            pixelRect.origin,
            CGPoint(x: pixelRect.maxX, y: pixelRect.minY),
            CGPoint(x: pixelRect.minX, y: pixelRect.maxY),
            CGPoint(x: pixelRect.maxX, y: pixelRect.maxY)
        ].map {
            let unscaledPoint = CGPoint(
                x: $0.x / max(scaleX, safeScale),
                y: $0.y / max(scaleY, safeScale)
            )
            let local = Self.mapPointToOriginal(unscaledPoint, angle: angle, originalSize: cropSize)
            return CGPoint(x: cropRect.minX + local.x, y: cropRect.minY + local.y)
        }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? cropRect.minX
        let maxX = xs.max() ?? cropRect.maxX
        let minY = ys.min() ?? cropRect.minY
        let maxY = ys.max() ?? cropRect.maxY
        return ImageOCRLayoutRect(
            x: minX / originalSize.width,
            y: minY / originalSize.height,
            width: (maxX - minX) / originalSize.width,
            height: (maxY - minY) / originalSize.height
        ).normalizedToUnit() ?? region
    }

    private static func deduplicateObservations(_ observations: [VisionOCRObservation]) -> [VisionOCRObservation] {
        var output: [VisionOCRObservation] = []
        for observation in observations.sorted(by: { isBetterObservation($0, $1) }) {
            guard let duplicateIndex = output.firstIndex(where: {
                isDuplicateObservation(observation, of: $0)
            }) else {
                output.append(observation)
                continue
            }
            if isBetterObservation(observation, than: output[duplicateIndex]) {
                output[duplicateIndex] = observation
            }
        }
        return output
    }

    private static func isBetterObservation(_ lhs: VisionOCRObservation, _ rhs: VisionOCRObservation) -> Bool {
        let lhsScore = observationScore(lhs)
        let rhsScore = observationScore(rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        if lhs.rotationApplied != rhs.rotationApplied {
            return lhs.rotationApplied == 90
        }
        return lhs.text < rhs.text
    }

    private static func isBetterObservation(_ lhs: VisionOCRObservation, than rhs: VisionOCRObservation) -> Bool {
        isBetterObservation(lhs, rhs)
    }

    private static func observationScore(_ observation: VisionOCRObservation) -> Double {
        let cjkCount = observation.text.unicodeScalars.count { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: true
            default: false
            }
        }
        return Double(observation.text.unicodeScalars.count)
            + Double(observation.confidence) * 8
            + Double(cjkCount) * 0.25
            + (observation.rotationApplied == 90 ? 0.15 : 0)
    }

    private static func isDuplicateObservation(
        _ lhs: VisionOCRObservation,
        of rhs: VisionOCRObservation
    ) -> Bool {
        let intersection = intersectionArea(lhs.rect, rhs.rect)
        let minimumArea = max(min(lhs.rect.width * lhs.rect.height, rhs.rect.width * rhs.rect.height), 0.0001)
        let overlap = intersection / minimumArea
        guard overlap >= 0.45 else { return false }

        let leftText = normalizedOCRText(lhs.text)
        let rightText = normalizedOCRText(rhs.text)
        guard !leftText.isEmpty, !rightText.isEmpty else { return overlap >= 0.72 }
        if leftText == rightText || leftText.contains(rightText) || rightText.contains(leftText) {
            return true
        }
        return overlap >= 0.72 && textSimilarity(leftText, rightText) >= 0.62
    }

    private static func overlapRatio(_ lhs: ImageOCRLayoutRect, _ rhs: ImageOCRLayoutRect) -> Double {
        let intersection = intersectionArea(lhs, rhs)
        let minimumArea = max(min(lhs.width * lhs.height, rhs.width * rhs.height), 0.0001)
        return intersection / minimumArea
    }

    private static func intersectionArea(_ lhs: ImageOCRLayoutRect, _ rhs: ImageOCRLayoutRect) -> Double {
        let width = max(0, min(lhs.maxX, rhs.maxX) - max(lhs.x, rhs.x))
        let height = max(0, min(lhs.maxY, rhs.maxY) - max(lhs.y, rhs.y))
        return width * height
    }

    private static func normalizedOCRText(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
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

    private static func mapRotatedObservation(
        _ observation: VisionOCRObservation,
        rotatedImage: CGImage,
        originalImage: CGImage,
        angle: Int
    ) -> VisionOCRObservation {
        let rotatedSize = CGSize(width: CGFloat(rotatedImage.width), height: CGFloat(rotatedImage.height))
        let originalSize = CGSize(width: CGFloat(originalImage.width), height: CGFloat(originalImage.height))
        let pixelRect = CGRect(
            x: observation.rect.x * rotatedSize.width,
            y: observation.rect.y * rotatedSize.height,
            width: observation.rect.width * rotatedSize.width,
            height: observation.rect.height * rotatedSize.height
        )
        let points = [
            pixelRect.origin,
            CGPoint(x: pixelRect.maxX, y: pixelRect.minY),
            CGPoint(x: pixelRect.minX, y: pixelRect.maxY),
            CGPoint(x: pixelRect.maxX, y: pixelRect.maxY)
        ].map {
            Self.mapPointToOriginal(
                $0,
                angle: angle,
                originalSize: originalSize
            )
        }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        let originalRect = ImageOCRLayoutRect(
            x: minX / originalSize.width,
            y: minY / originalSize.height,
            width: (maxX - minX) / originalSize.width,
            height: (maxY - minY) / originalSize.height
        ).normalizedToUnit() ?? observation.rect
        let originalLineRegionRect = observation.lineRegionRect.map {
            mapRotatedRegionRect(
                $0,
                rotatedImage: rotatedImage,
                originalImage: originalImage,
                angle: angle
            )
        }
        return VisionOCRObservation(
            text: observation.text,
            confidence: observation.confidence,
            rect: originalRect,
            lineRegionRect: originalLineRegionRect,
            rotationApplied: observation.rotationApplied
        )
    }

    private static func mapRotatedRegionRect(
        _ region: ImageOCRLayoutRect,
        rotatedImage: CGImage,
        originalImage: CGImage,
        angle: Int
    ) -> ImageOCRLayoutRect {
        let rotatedSize = CGSize(width: CGFloat(rotatedImage.width), height: CGFloat(rotatedImage.height))
        let originalSize = CGSize(width: CGFloat(originalImage.width), height: CGFloat(originalImage.height))
        let pixelRect = CGRect(
            x: region.x * rotatedSize.width,
            y: region.y * rotatedSize.height,
            width: region.width * rotatedSize.width,
            height: region.height * rotatedSize.height
        )
        let points = [
            pixelRect.origin,
            CGPoint(x: pixelRect.maxX, y: pixelRect.minY),
            CGPoint(x: pixelRect.minX, y: pixelRect.maxY),
            CGPoint(x: pixelRect.maxX, y: pixelRect.maxY)
        ].map {
            Self.mapPointToOriginal($0, angle: angle, originalSize: originalSize)
        }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return ImageOCRLayoutRect(
            x: minX / originalSize.width,
            y: minY / originalSize.height,
            width: (maxX - minX) / originalSize.width,
            height: (maxY - minY) / originalSize.height
        ).normalizedToUnit() ?? region
    }

    private static func mapPointToOriginal(
        _ point: CGPoint,
        angle: Int,
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
            throw VisionOCRServiceError.imageRenderFailed
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
            throw VisionOCRServiceError.imageRenderFailed
        }
        return rotated
    }

    private static func makeOCRImage(from imageData: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw VisionOCRServiceError.imageDecodeFailed
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_800
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw VisionOCRServiceError.imageDecodeFailed
        }

        return image
    }

    private static func normalizedRect(from rawBox: CGRect) -> ImageOCRLayoutRect? {
        guard rawBox.origin.x.isFinite,
              rawBox.origin.y.isFinite,
              rawBox.width.isFinite,
              rawBox.height.isFinite,
              rawBox.width > 0,
              rawBox.height > 0 else {
            return nil
        }

        let rect = ImageOCRLayoutRect(
            x: Double(rawBox.origin.x),
            y: Double(1 - rawBox.origin.y - rawBox.height),
            width: Double(rawBox.width),
            height: Double(rawBox.height)
        )
        return rect.normalizedToUnit()
    }
}

private struct VisionOCRObservation: Equatable, Sendable {
    var text: String
    var confidence: Float
    var rect: ImageOCRLayoutRect
    /// Character-range geometry is a tighter, Vision-provided line-region hint;
    /// `rect` remains the stable request-level box used by layout and dedupe.
    var lineRegionRect: ImageOCRLayoutRect?
    var rotationApplied: Int
}
