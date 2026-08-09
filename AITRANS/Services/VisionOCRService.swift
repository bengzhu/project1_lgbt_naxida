import CoreGraphics
import CoreImage
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
                rotationApplied: 0,
                postProcessJapaneseText: sourceLanguage == .japanese
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
                // Koharu's manga OCR crop is language-specific. Keep the page
                // reconnaissance bilingual for mixed Japanese/Latin panels, but
                // constrain vertical line/block/tile rereads to Japanese so a
                // nearby Latin candidate cannot win a narrow column.
                let japaneseVerticalRecognitionLanguages = ["ja-JP", "ja"]
                for angle in [90, 270] {
                    guard let rotatedOCRImage = try? Self.rotatedImage(ocrImage, angle: angle),
                          let rotatedObservations = try? Self.recognizeObservations(
                              in: rotatedOCRImage,
                              recognitionLanguages: japaneseOrientationLanguages,
                              minimumTextHeight: 0.006,
                              automaticallyDetectsLanguage: false,
                              rotationApplied: angle,
                              postProcessJapaneseText: true
                          ).map({
                              Self.mapRotatedObservation(
                                  $0,
                                  rotatedImage: rotatedOCRImage,
                                  originalImage: ocrImage,
                                  angle: angle
                              )
                          }) else {
                        // Keep the original page pass usable when one rotated
                        // reconnaissance render or Vision request fails.
                        continue
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
                    recognitionLanguages: japaneseVerticalRecognitionLanguages
                )
                observations.append(contentsOf: cropRefinedObservations)
            }

            let finalObservations = sourceLanguage == .japanese
                ? Self.deduplicateJapaneseObservations(observations)
                : Self.deduplicateObservations(observations)
            let layoutObservations = finalObservations.map {
                ImageOCRLayoutObservation(
                    text: $0.text,
                    confidence: $0.confidence,
                    rect: $0.rect,
                    sourceDirectionHint: $0.sourceDirectionHint
                )
            }
            let allowsVerticalText = sourceLanguage == .japanese || sourceLanguage == .simplifiedChinese
            return ImageOCRLayoutEngine.layout(
                layoutObservations,
                allowsVerticalText: allowsVerticalText,
                prefersMangaReadingOrder: sourceLanguage == .japanese
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
        rotationApplied: Int,
        postProcessJapaneseText: Bool = false,
        usesLanguageCorrection: Bool = true,
        observationRole: VisionOCRObservationRole = .page
    ) throws -> [VisionOCRObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Koharu's Manga OCR crop inference decodes directly; crop callers can
        // disable Vision's language rewrite while page reconnaissance keeps it.
        request.usesLanguageCorrection = usesLanguageCorrection
        request.automaticallyDetectsLanguage = automaticallyDetectsLanguage
        request.minimumTextHeight = minimumTextHeight

        let supportedLanguages = (try? request.supportedRecognitionLanguages()) ?? []
        let availableLanguages = recognitionLanguages.filter { supportedLanguages.contains($0) }
        if !availableLanguages.isEmpty {
            request.recognitionLanguages = availableLanguages
        } else if !automaticallyDetectsLanguage {
            // Do not silently fall back to the device locale for a
            // language-specific reread. The page-level pass remains available.
            return []
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = Self.selectOCRCandidate(
                from: observation.topCandidates(postProcessJapaneseText ? 5 : 1),
                japanese: postProcessJapaneseText
            ) else { return nil }
            guard let rect = Self.normalizedRect(from: observation.boundingBox) else { return nil }
            let text = postProcessJapaneseText
                ? Self.postProcessJapaneseOCRText(candidate.string)
                : candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let geometry = Self.recognizedTextGeometry(
                for: candidate,
                fallback: rect
            )
            return VisionOCRObservation(
                text: text,
                confidence: candidate.confidence,
                rect: rect,
                lineRegionRect: geometry.rect,
                lineRegionQuad: geometry.quad,
                rotationApplied: rotationApplied,
                observationRole: observationRole
            )
        }
    }

    /// Mirrors Koharu Manga OCR's post-processing boundary for Japanese text.
    /// Vision's candidate string is still the source of geometry; this only
    /// removes recognition formatting noise before layout, dedupe, and translation.
    private static func postProcessJapaneseOCRText(_ text: String) -> String {
        let withoutWhitespace = text.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "…", with: "...")

        // Keep Koharu's two-stage boundary explicit: collapse dot/middle-dot
        // runs first, then apply halfwidth-to-fullwidth conversion to the
        // collapsed result. Emitting the dots directly into the final output
        // would leave them halfwidth while all other ASCII punctuation becomes
        // fullwidth.
        var collapsed = ""
        var dotCount = 0
        func flushDots() {
            guard dotCount > 0 else { return }
            collapsed.append(contentsOf: String(repeating: ".", count: dotCount))
            dotCount = 0
        }

        for scalar in withoutWhitespace.unicodeScalars {
            switch scalar.value {
            case 0x2E, 0x30FB:
                dotCount += 1
            default:
                flushDots()
                collapsed.unicodeScalars.append(scalar)
            }
        }
        flushDots()

        var output = ""
        for scalar in collapsed.unicodeScalars {
            if scalar.value == 0x20 {
                output.unicodeScalars.append(UnicodeScalar(0x3000)!)
            } else if (0x21...0x7E).contains(scalar.value),
                      let fullwidth = UnicodeScalar(scalar.value + 0xFEE0) {
                output.unicodeScalars.append(fullwidth)
            } else {
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }

    private static func selectOCRCandidate(
        from candidates: [VNRecognizedText],
        japanese: Bool
    ) -> VNRecognizedText? {
        guard japanese else { return candidates.first }
        guard let bestConfidence = candidates.map(\.confidence).max() else { return nil }

        // Keep alternatives close to Vision's best score, then prefer the
        // Japanese-script candidate. This avoids replacing a strong result with
        // a speculative alternative while recovering common vertical glyph
        // substitutions that Vision reports just below top-1.
        return candidates
            .filter { $0.confidence >= bestConfidence - 0.14 }
            .max { lhs, rhs in
                japaneseCandidateScore(lhs) < japaneseCandidateScore(rhs)
            }
    }

    private static func japaneseCandidateScore(_ candidate: VNRecognizedText) -> Double {
        let text = postProcessJapaneseOCRText(candidate.string)
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { return Double(candidate.confidence) * 0.82 }
        let japaneseCount = scalars.count { scalar in
            switch scalar.value {
            case 0x3000...0x303F, 0x3040...0x30FF, 0x3400...0x4DBF,
                 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF61...0xFF9F:
                true
            default:
                false
            }
        }
        let punctuationCount = scalars.count { scalar in
            switch scalar.value {
            case 0x3000...0x303F, 0xFF61...0xFF65:
                true
            default:
                false
            }
        }
        let scriptDensity = Double(japaneseCount) / Double(scalars.count)
        let punctuationDensity = Double(punctuationCount) / Double(scalars.count)
        let confidence = min(max(Double(candidate.confidence), 0), 1)
        return confidence * 0.82 + scriptDensity * 0.14 + punctuationDensity * 0.04
    }

    private static func recognizedTextGeometry(
        for candidate: VNRecognizedText,
        fallback: ImageOCRLayoutRect
    ) -> (rect: ImageOCRLayoutRect, quad: ImageOCRLayoutQuad?) {
        let range = candidate.string.startIndex..<candidate.string.endIndex
        do {
            if let rangeObservation = try candidate.boundingBox(for: range),
               let rangeRect = normalizedRect(from: rangeObservation.boundingBox),
               isUsableTextRegion(rangeRect, relativeTo: fallback) {
                return (
                    rect: rangeRect,
                    quad: normalizedQuad(from: rangeObservation)
                )
            }
        } catch {
            // Vision may not provide character-range geometry for every revision;
            // the request-level observation remains the safe Koharu line proxy.
        }
        return (rect: fallback, quad: nil)
    }

    private static func normalizedQuad(
        from observation: VNRectangleObservation
    ) -> ImageOCRLayoutQuad? {
        let rawPoints = [
            observation.topLeft,
            observation.topRight,
            observation.bottomRight,
            observation.bottomLeft
        ]
        let points = rawPoints.map {
            ImageOCRLayoutPoint(
                x: Double($0.x),
                y: Double(1 - $0.y)
            )
        }
        guard points.allSatisfy({
            $0.x.isFinite && $0.y.isFinite
                && $0.x >= 0 && $0.x <= 1
                && $0.y >= 0 && $0.y <= 1
        }) else {
            return nil
        }
        let quad = ImageOCRLayoutQuad(points: points)
        guard quad.boundingRect.normalizedToUnit() != nil,
              quad.minimumEdgeLength >= 0.002,
              quad.isConvex else {
            return nil
        }
        return quad
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
        let safeObservations = deduplicateJapaneseObservations(observations)
        let layoutObservations = safeObservations.map {
            ImageOCRLayoutObservation(
                text: $0.text,
                confidence: $0.confidence,
                rect: $0.rect,
                sourceDirectionHint: $0.sourceDirectionHint
            )
        }
        let verticalBlocks = ImageOCRLayoutEngine.layout(
            layoutObservations,
            allowsVerticalText: true,
            prefersMangaReadingOrder: true
        )
        .filter { block in
            let aspectRatio = block.rect.height / max(block.rect.width, 0.001)
            let isStandardVerticalCandidate = aspectRatio >= 1.45
                && block.rect.height >= 0.04
            // Koharu's PP-DocLayout detector marks a text region as vertical
            // at `height / width >= 1.15` and keeps detector confidence >= 0.25.
            // Vision layout has already resolved this block as vertical, so
            // carry that bounded detector boundary into the crop stage instead
            // of dropping medium-height columns before OCR reread. Keep a
            // normalized height floor so small icons and incidental fragments
            // do not consume a block crop budget.
            let isKoharuDetectorVerticalCandidate = aspectRatio >= 1.15
                && block.rect.height >= 0.035
                && block.directionConfidence >= 0.25
            // Koharu sends every detector TextRegion through
            // crop_text_block_bbox. A v3.177 compact direction result is a
            // similarly explicit Japanese block, even when its normalized
            // dimensions are below the old tall-block crop threshold. Keep
            // the relaxed path tied to that reason and retain a bounded shape
            // and height gate so short noise does not trigger extra rereads.
            let hasCompactDirectionReason = block.directionReason
                .split(separator: ",")
                .contains { String($0) == "cjkCompactColumnTextRun" }
            let isCompactVerticalCandidate = hasCompactDirectionReason
                && aspectRatio >= 1.20
                && block.rect.height >= 0.022
            return block.direction == .vertical
                && (isStandardVerticalCandidate
                    || isKoharuDetectorVerticalCandidate
                    || isCompactVerticalCandidate)
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

        let verticalBlockArray = Array(verticalBlocks)
        var refined: [VisionOCRObservation] = []
        refined.reserveCapacity(verticalBlockArray.count * 2 + 12)

        // Koharu's extract_text_block_regions is line-first: once a TextRegion
        // has usable line polygons, it sends those regions to OCR before any
        // wider detector or block crop fallback. Vision does not expose those polygons,
        // so the mapped line observations are our bounded equivalent.
        // Run this path first and let later reconnaissance consume only gaps
        // that were not reliably covered by a line reread.
        let lineRefined = Self.recognizeJapaneseVerticalLineCrops(
            in: image,
            observations: safeObservations,
            blocks: Array(verticalBlocks),
            recognitionLanguages: recognitionLanguages
        )
        refined.append(contentsOf: lineRefined)

        refined.append(contentsOf: Self.recognizeJapanesePixelFirstVerticalCrops(
            in: image,
            observations: safeObservations,
            verticalBlocks: verticalBlockArray,
            lineObservations: lineRefined,
            recognitionLanguages: recognitionLanguages
        ))
        refined.append(contentsOf: Self.recognizeJapaneseVerticalTileFallback(
            in: image,
            verticalBlocks: verticalBlockArray,
            lineObservations: lineRefined,
            recognitionLanguages: recognitionLanguages
        ))

        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        var orientationFallbacksRemaining = 8
        for block in verticalBlocks {
            let hasCompleteLineCoverage = Self.hasCompleteJapaneseLineCoverage(
                for: block,
                sourceObservations: safeObservations,
                lineRefined: lineRefined
            )
            let hasLineOCRResult = lineRefined.contains { observation in
                overlapRatio(observation.rect, block.rect) >= 0.25
                    && japaneseLineRegionOverlapsBlock(observation, block: block)
            } && hasCompleteLineCoverage
            guard !hasLineOCRResult else { continue }

            let angle = safeObservations
                .filter { overlapRatio($0.rect, block.rect) >= 0.25 }
                .sorted { isBetterJapaneseObservation($0, $1) }
                .first
                .map { $0.rotationApplied == 270 ? 270 : 90 }
                ?? 90
            guard let crop = cropImage(
                image,
                normalizedRect: koharuVerticalBlockCropRect(
                    block,
                    observations: safeObservations,
                    imageSize: imageSize
                )
            ),
                  crop.image.width >= 2,
                  crop.image.height >= 2 else {
                continue
            }

            // Koharu's Manga OCR preprocessor turns every text-node crop into a
            // grayscale, bounded model input before inference. Vision owns its own
            // tensor normalization, so mirror the model-independent part here:
            // remove page color noise and give small vertical glyphs a bounded
            // resolution boost. The returned scale is carried through the existing
            // crop mapper so geometry remains in source-image coordinates.
            let preparedCrop = prepareJapaneseCropForVision(crop.image)

            let primary = recognizeJapaneseCropPass(
                crop: preparedCrop.image,
                cropRect: crop.rect,
                originalImage: image,
                angle: angle,
                recognitionLanguages: recognitionLanguages,
                minimumTextHeight: 0.004,
                cropScale: preparedCrop.scale
            )
            refined.append(contentsOf: primary)

            // A block can be laid out correctly while its first crop orientation
            // is still reversed. Retry only weak/empty crops and keep a strict
            // page-level budget so dense manga pages do not double their OCR cost.
            if orientationFallbacksRemaining > 0,
               needsJapaneseOrientationFallback(primary) {
                orientationFallbacksRemaining -= 1
                refined.append(contentsOf: recognizeJapaneseCropPass(
                    crop: preparedCrop.image,
                    cropRect: crop.rect,
                    originalImage: image,
                    angle: oppositeJapaneseOrientation(angle),
                    recognitionLanguages: recognitionLanguages,
                    minimumTextHeight: 0.004,
                    cropScale: preparedCrop.scale
                ))
            }
        }

        return refined
    }

    /// Use Vision's pixel-first text rectangle detector as a bounded proxy for
    /// Koharu's detector -> TextRegion -> crop/OCR boundary. The detector only
    /// contributes geometry; recognition still runs through the existing
    /// Japanese crop helper and remains isolated from model/artifact paths.
    private static func recognizeJapanesePixelFirstVerticalCrops(
        in image: CGImage,
        observations: [VisionOCRObservation],
        verticalBlocks: [ImageOCRLayoutBlock],
        lineObservations: [VisionOCRObservation],
        recognitionLanguages: [String]
    ) -> [VisionOCRObservation] {
        let candidates = detectJapanesePixelFirstVerticalRegions(
            in: image,
            observations: observations,
            verticalBlocks: verticalBlocks,
            lineObservations: lineObservations
        )
        guard !candidates.isEmpty else { return [] }

        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        var refined: [VisionOCRObservation] = []
        refined.reserveCapacity(candidates.count * 2)
        var orientationFallbacksRemaining = 4

        for candidate in candidates.prefix(12) {
            let cropRect = expandedVerticalLineCropRect(
                candidate.rect,
                imageSize: imageSize
            )
            guard let crop = cropImage(image, normalizedRect: cropRect),
                  crop.image.width >= 2,
                  crop.image.height >= 2 else {
                continue
            }

            let preparedCrop = prepareJapaneseCropForVision(crop.image)
            let primary = recognizeJapaneseCropPass(
                crop: preparedCrop.image,
                cropRect: crop.rect,
                originalImage: image,
                angle: koharuPreferredJapaneseVerticalLineOrientation(),
                recognitionLanguages: recognitionLanguages,
                minimumTextHeight: 0.002,
                cropScale: preparedCrop.scale,
                observationRole: .verticalLine
            )
            refined.append(contentsOf: primary)

            if orientationFallbacksRemaining > 0,
               needsJapaneseOrientationFallback(primary) {
                orientationFallbacksRemaining -= 1
                refined.append(contentsOf: recognizeJapaneseCropPass(
                    crop: preparedCrop.image,
                    cropRect: crop.rect,
                    originalImage: image,
                    angle: oppositeJapaneseOrientation(
                        koharuPreferredJapaneseVerticalLineOrientation()
                    ),
                    recognitionLanguages: recognitionLanguages,
                    minimumTextHeight: 0.002,
                    cropScale: preparedCrop.scale,
                    observationRole: .verticalLine
                ))
            }
        }

        return deduplicateJapaneseObservations(refined)
    }

    /// Detect text rectangles on both rotated page views, map them back to the
    /// source image, and retain only uncovered vertical candidates. This is a
    /// geometry-only fallback: it does not claim detector confidence or OCR
    /// quality until the normal crop pass produces a usable observation.
    private static func detectJapanesePixelFirstVerticalRegions(
        in image: CGImage,
        observations: [VisionOCRObservation],
        verticalBlocks: [ImageOCRLayoutBlock],
        lineObservations: [VisionOCRObservation]
    ) -> [JapanesePixelFirstRegion] {
        guard image.width >= 8, image.height >= 8 else { return [] }

        let existingVerticalRegions = observations.compactMap { observation -> ImageOCRLayoutRect? in
            guard observation.sourceDirectionHint == .vertical
                || observation.observationRole == .verticalLine else {
                return nil
            }
            return observation.lineRegionRect ?? observation.rect
        }
        let reliableLineRegions = lineObservations.compactMap { observation in
            japaneseLinePathRegion(observation)
        }
        var candidates: [JapanesePixelFirstRegion] = []
        for angle in [90, 270] {
            guard let rotated = try? rotatedImage(image, angle: angle) else {
                continue
            }

            let request = VNDetectTextRectanglesRequest()
            request.reportCharacterBoxes = false
            let handler = VNImageRequestHandler(cgImage: rotated, options: [:])
            guard (try? handler.perform([request])) != nil else { continue }

            for detection in request.results ?? [] {
                guard let rotatedRect = normalizedRect(from: detection.boundingBox) else {
                    continue
                }
                let mappedRect = mapRotatedRegionRect(
                    rotatedRect,
                    rotatedImage: rotated,
                    originalImage: image,
                    angle: angle
                )
                guard isJapanesePixelFirstVerticalCandidate(mappedRect),
                      !verticalBlocks.contains(where: {
                          japanesePixelDetectorRegionIsCovered($0.rect, by: mappedRect)
                      }),
                      !existingVerticalRegions.contains(where: {
                          japanesePixelDetectorRegionIsCovered($0, by: mappedRect)
                      }),
                      !reliableLineRegions.contains(where: {
                          overlapRatio($0, mappedRect) >= 0.60
                      }) else {
                    continue
                }
                candidates.append(
                    JapanesePixelFirstRegion(
                        rect: mappedRect,
                        detectorRotation: angle
                    )
                )
            }
        }

        var unique: [JapanesePixelFirstRegion] = []
        for candidate in candidates.sorted(by: { lhs, rhs in
            if lhs.rect.height != rhs.rect.height {
                return lhs.rect.height > rhs.rect.height
            }
            if lhs.rect.width != rhs.rect.width {
                return lhs.rect.width < rhs.rect.width
            }
            if lhs.rect.y != rhs.rect.y {
                return lhs.rect.y < rhs.rect.y
            }
            if lhs.rect.x != rhs.rect.x {
                return lhs.rect.x > rhs.rect.x
            }
            return lhs.detectorRotation == 270 && rhs.detectorRotation != 270
        }) {
            guard !unique.contains(where: {
                isSameJapanesePixelFirstRegion(candidate, as: $0)
            }) else {
                continue
            }
            unique.append(candidate)
            if unique.count == 12 { break }
        }
        return unique
    }

    private static func isJapanesePixelFirstVerticalCandidate(
        _ rect: ImageOCRLayoutRect
    ) -> Bool {
        let aspectRatio = rect.height / max(rect.width, 0.001)
        return rect.width <= 0.30
            && rect.height >= 0.025
            && aspectRatio >= 1.15
    }

    private static func japanesePixelDetectorRegionIsCovered(
        _ block: ImageOCRLayoutRect,
        by candidate: ImageOCRLayoutRect
    ) -> Bool {
        let horizontalIntersection = max(
            0,
            min(block.maxX, candidate.maxX) - max(block.x, candidate.x)
        )
        let horizontalCoverage = horizontalIntersection
            / max(min(block.width, candidate.width), 0.001)
        let verticalIntersection = max(
            0,
            min(block.maxY, candidate.maxY) - max(block.y, candidate.y)
        )
        let verticalCoverage = verticalIntersection / max(candidate.height, 0.001)
        return horizontalCoverage >= 0.45 && verticalCoverage >= 0.60
    }

    private static func isSameJapanesePixelFirstRegion(
        _ candidate: JapanesePixelFirstRegion,
        as other: JapanesePixelFirstRegion
    ) -> Bool {
        intersectionOverUnion(candidate.rect, other.rect) >= 0.45
            || overlapRatio(candidate.rect, other.rect) >= 0.65
    }

    /// Recover Japanese vertical columns that the page-level Vision passes did
    /// not expose as observations. Koharu's detector creates TextBoxes before
    /// crop/OCR; when Vision misses an entire column there is no candidate to
    /// crop, so use a bounded, overlapping reconnaissance pass as a detector
    /// fallback. Split each narrow strip into overlapping local windows so text
    /// on a long manga page occupies materially more of Vision's input, closer
    /// to Koharu's TextBox -> crop/OCR boundary than a full-height strip. Existing
    /// vertical blocks suppress covered windows, while the hard horizontal,
    /// total-window, and opposite-orientation budgets keep dense pages bounded.
    private static func recognizeJapaneseVerticalTileFallback(
        in image: CGImage,
        verticalBlocks: [ImageOCRLayoutBlock],
        lineObservations: [VisionOCRObservation],
        recognitionLanguages: [String]
    ) -> [VisionOCRObservation] {
        let imageWidth = image.width
        let imageHeight = image.height
        guard imageWidth >= 8, imageHeight >= 8 else { return [] }

        let maximumTiles = 6
        let maximumWindows = 18
        let tileWidth = max(Int((Double(imageWidth) / 4).rounded()), 2)
        let overlapPixels = max(Int((Double(tileWidth) * 0.18).rounded()), 1)
        let step = max(tileWidth - overlapPixels, 1)
        var starts: [Int] = []
        var nextStart = 0
        while nextStart < imageWidth,
              starts.count < maximumTiles {
            starts.append(nextStart)
            guard nextStart + tileWidth < imageWidth else { break }
            nextStart += step
        }

        let lastStart = max(imageWidth - tileWidth, 0)
        if !starts.contains(lastStart) {
            if starts.count == maximumTiles {
                starts[starts.count - 1] = lastStart
            } else {
                starts.append(lastStart)
            }
        }

        // Mirror Koharu's comic_text_bubble_detector::ImageSlicer instead of
        // sizing windows as a percentage of the page: target a 3:1 slice,
        // advance by 80%, and fold a final sliver into the preceding slice when
        // it would be no more than 70% of the target height. Applying the same
        // geometry to each narrow reconnaissance strip keeps glyphs large on
        // test/jap.jpg while guaranteeing bottom-edge coverage.
        let verticalWindows = japaneseVerticalSliceWindows(
            imageHeight: imageHeight,
            stripWidth: tileWidth
        )
        // Manga reading order is right-to-left across columns, then
        // top-to-bottom inside each column. Spend a finite reconnaissance
        // budget on the rightmost columns first so a very tall page does not
        // truncate the Japanese reading frontier on the left.
        let mangaOrderedStarts = starts.sorted { $0 > $1 }
        let reliableLineRegions = lineObservations.compactMap { observation in
            japaneseLinePathRegion(observation)
        }

        var refined: [VisionOCRObservation] = []
        refined.reserveCapacity(maximumWindows * 2)
        var orientationFallbacksRemaining = 4
        var processedWindowCount = 0

        for start in mangaOrderedStarts {
            let pixelWidth = min(tileWidth, imageWidth - start)
            guard pixelWidth >= 2 else { continue }
            for window in verticalWindows {
                guard processedWindowCount < maximumWindows else { break }
                let pixelHeight = window.height
                guard pixelHeight >= 2 else { continue }
                let tileRect = ImageOCRLayoutRect(
                    x: Double(start) / Double(imageWidth),
                    y: Double(window.start) / Double(imageHeight),
                    width: Double(pixelWidth) / Double(imageWidth),
                    height: Double(pixelHeight) / Double(imageHeight)
                )
                guard !verticalBlocks.contains(where: {
                    verticalTileIsCovered($0.rect, by: tileRect)
                }),
                      !reliableLineRegions.contains(where: {
                          overlapRatio($0, tileRect) >= 0.60
                      }),
                      let crop = cropImage(image, normalizedRect: tileRect),
                      crop.image.width >= 2,
                      crop.image.height >= 2 else {
                    continue
                }

                processedWindowCount += 1
                let preparedCrop = prepareJapaneseCropForVision(crop.image)
                let primary = recognizeJapaneseCropPass(
                    crop: preparedCrop.image,
                    cropRect: crop.rect,
                    originalImage: image,
                    angle: 90,
                    recognitionLanguages: recognitionLanguages,
                    minimumTextHeight: 0.003,
                    cropScale: preparedCrop.scale
                )
                let verticalPrimary = filterJapaneseVerticalTileObservations(primary)
                refined.append(contentsOf: verticalPrimary)

                if orientationFallbacksRemaining > 0,
                   needsJapaneseOrientationFallback(verticalPrimary) {
                    orientationFallbacksRemaining -= 1
                    let opposite = recognizeJapaneseCropPass(
                        crop: preparedCrop.image,
                        cropRect: crop.rect,
                        originalImage: image,
                        angle: 270,
                        recognitionLanguages: recognitionLanguages,
                        minimumTextHeight: 0.003,
                        cropScale: preparedCrop.scale
                    )
                    refined.append(contentsOf: filterJapaneseVerticalTileObservations(opposite))
                }
            }
            guard processedWindowCount < maximumWindows else { break }
        }
        return deduplicateJapaneseObservations(refined)
    }

    /// Port of Koharu's `ImageSlicer::calculate_slice_params` for a single
    /// vertical reconnaissance strip. The final returned window always reaches
    /// the image bottom; an undersized tail is folded into that final window.
    private static func japaneseVerticalSliceWindows(
        imageHeight: Int,
        stripWidth: Int
    ) -> [(start: Int, height: Int)] {
        guard imageHeight >= 2, stripWidth >= 1 else { return [] }

        let sliceTargetAspectRatio = 3.0
        let sliceOverlapRatio = 0.20
        let minimumLastSliceRatio = 0.70
        let targetHeight = min(
            max(Int((Double(stripWidth) * sliceTargetAspectRatio).rounded()), 2),
            imageHeight
        )
        guard targetHeight < imageHeight else {
            return [(start: 0, height: imageHeight)]
        }

        let effectiveHeight = max(
            Int((Double(targetHeight) * (1 - sliceOverlapRatio)).rounded()),
            1
        )
        var sliceCount = max(
            Int(ceil(Double(imageHeight) / Double(effectiveHeight))),
            1
        )
        if sliceCount > 1 {
            let lastStart = (sliceCount - 1) * effectiveHeight
            let lastHeight = max(imageHeight - lastStart, 0)
            if Double(lastHeight) / Double(targetHeight) <= minimumLastSliceRatio {
                sliceCount -= 1
            }
        }

        return (0..<sliceCount).compactMap { index in
            let start = index * effectiveHeight
            guard start < imageHeight else { return nil }
            let height = index + 1 == sliceCount
                ? imageHeight - start
                : min(targetHeight, imageHeight - start)
            guard height >= 2 else { return nil }
            return (start: start, height: height)
        }
    }

    /// A localized reconnaissance window is still broader than a Koharu TextBox.
    /// Keep its reread output on the vertical-column boundary so horizontal
    /// Japanese lines discovered incidentally in the same window do not become
    /// duplicate fallback observations. Compact one- or two-glyph CJK fragments
    /// remain eligible through the same bounded geometry gate used by line
    /// synthesis.
    private static func filterJapaneseVerticalTileObservations(
        _ observations: [VisionOCRObservation]
    ) -> [VisionOCRObservation] {
        observations.filter { observation in
            let region = observation.lineRegionRect ?? observation.rect
            let ratio = region.height / max(region.width, 0.001)
            let scriptDensity = japaneseScriptDensity(in: observation.text)
            guard scriptDensity >= 0.5 else { return false }

            let isTallColumn = region.height >= 0.022 && ratio >= 1.18
            let isCompactFragment = region.height >= 0.018
                && ratio >= 0.90
                && observation.text.unicodeScalars.count <= 2
            return isTallColumn || isCompactFragment
        }
    }

    private static func verticalTileIsCovered(
        _ block: ImageOCRLayoutRect,
        by tile: ImageOCRLayoutRect
    ) -> Bool {
        let horizontalIntersection = max(
            0,
            min(block.maxX, tile.maxX) - max(block.x, tile.x)
        )
        let horizontalCoverage = horizontalIntersection
            / max(min(block.width, tile.width), 0.001)
        let verticalIntersection = max(
            0,
            min(block.maxY, tile.maxY) - max(block.y, tile.y)
        )
        let verticalCoverage = verticalIntersection / max(tile.height, 0.001)
        return horizontalCoverage >= 0.45 && verticalCoverage >= 0.30
    }

    private static func recognizeJapaneseVerticalLineCrops(
        in image: CGImage,
        observations: [VisionOCRObservation],
        blocks: [ImageOCRLayoutBlock],
        recognitionLanguages: [String]
    ) -> [VisionOCRObservation] {
        let safeObservations = deduplicateJapaneseObservations(observations)
        var candidates: [VisionOCRObservation] = []
        for block in blocks {
            candidates.append(contentsOf: safeObservations.filter { observation in
                let lineRegion = observation.lineRegionRect ?? observation.rect
                return overlapRatio(observation.rect, block.rect) >= 0.25
                    && japaneseLineRegionOverlapsBlock(observation, block: block)
                    && isVerticalLineCandidate(lineRegion)
            })
        }

        var uniqueCandidates: [VisionOCRObservation] = []
        for candidate in candidates.sorted(by: { isBetterJapaneseObservation($0, $1) }) {
            guard !uniqueCandidates.contains(where: {
                isDuplicateObservation(candidate, of: $0, prefersJapanese: true)
            }) else {
                continue
            }
            uniqueCandidates.append(candidate)
        }

        let perspectiveCandidates = Array(uniqueCandidates.prefix(24))
        // Vision may split a narrow vertical Japanese column into near-square
        // one- or two-glyph observations. Koharu's detector emits one line
        // region before OCR, so replace those fragmented axis-aligned rereads
        // with bounded synthetic column crops while keeping the original
        // quadrilateral candidates available for perspective correction.
        let synthesizedCandidates = synthesizeJapaneseVerticalLineCandidates(
            observations: safeObservations,
            blocks: blocks
        )
        // A synthesized line is the bounded TextRegion proxy for the column,
        // so do not reread an original axis candidate that it geometrically
        // covers. Keep the original candidate in `perspectiveCandidates` so
        // its quad can still receive the Koharu-style warp path; this filter
        // only removes the duplicate axis-aligned bbox request.
        let axisSeeds = synthesizedCandidates + uniqueCandidates.filter { candidate in
            !synthesizedCandidates.contains(where: {
                isSameJapaneseLineRegion(candidate, as: $0)
            })
        }
        let axisCandidates = Array(
            deduplicateJapaneseObservations(axisSeeds)
                .prefix(24)
        )

        var refined: [VisionOCRObservation] = []
        refined.reserveCapacity((perspectiveCandidates.count + axisCandidates.count) * 2)
        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        var perspectiveWarpPixels: CGFloat = 0
        var perspectiveCoveredCandidates: [VisionOCRObservation] = []
        for candidate in perspectiveCandidates {
            // Koharu's `warp_line_region` rotates every vertical line region
            // with `rotate270` before line-level OCR. Keep that as the
            // primary direction for this line-only path; the bounded opposite
            // orientation below remains available for weak/empty results.
            let angle = koharuPreferredJapaneseVerticalLineOrientation()
            if let perspective = recognizeJapanesePerspectiveLineCrop(
                candidate: candidate,
                in: image,
                angle: angle,
                recognitionLanguages: recognitionLanguages,
                consumedPixels: &perspectiveWarpPixels
            ) {
                refined.append(perspective)
                // Koharu's extract_text_block_regions uses a successful line
                // polygon region instead of rereading the same line bbox. Keep
                // the axis-aligned path as a quality fallback, but suppress it
                // for a geometrically matching perspective result that is
                // already strong enough to avoid a duplicate Vision request.
                if !needsJapaneseOrientationFallback([perspective]) {
                    perspectiveCoveredCandidates.append(candidate)
                }
            }
        }

        var orientationFallbacksRemaining = 12
        for candidate in axisCandidates {
            guard !perspectiveCoveredCandidates.contains(where: {
                isSameJapaneseLineRegion(candidate, as: $0)
            }) else {
                continue
            }
            // Keep axis-aligned line rereads on the same Koharu-preferred
            // vertical direction as perspective line regions. Block and tile
            // crops intentionally retain their own candidate-derived angle.
            let angle = koharuPreferredJapaneseVerticalLineOrientation()
            let cropRect = expandedVerticalLineCropRect(for: candidate, imageSize: imageSize)
            guard let crop = cropImage(image, normalizedRect: cropRect) else {
                continue
            }

            // Keep line-region rereads on the same model-independent Koharu
            // crop boundary as block rereads: grayscale first, then apply a
            // bounded resolution boost. The returned scale is preserved for
            // the existing source-image geometry mapping.
            let preparedCrop = prepareJapaneseCropForVision(crop.image)

            let primary = recognizeJapaneseCropPass(
                crop: preparedCrop.image,
                cropRect: crop.rect,
                originalImage: image,
                angle: angle,
                recognitionLanguages: recognitionLanguages,
                minimumTextHeight: 0.002,
                cropScale: preparedCrop.scale,
                observationRole: .verticalLine
            )
            refined.append(contentsOf: primary)
            if orientationFallbacksRemaining > 0,
               needsJapaneseOrientationFallback(primary) {
                orientationFallbacksRemaining -= 1
                refined.append(contentsOf: recognizeJapaneseCropPass(
                    crop: preparedCrop.image,
                    cropRect: crop.rect,
                    originalImage: image,
                    angle: oppositeJapaneseOrientation(angle),
                    recognitionLanguages: recognitionLanguages,
                    minimumTextHeight: 0.002,
                    cropScale: preparedCrop.scale,
                    observationRole: .verticalLine
                ))
            }
        }
        return refined
    }

    /// Decide whether a Japanese block is safe to omit after line rereads.
    ///
    /// A single successful line can sit inside a multi-line Vision block.  The
    /// old any-overlap check therefore dropped the remaining text before the
    /// block crop had a chance to recover it.  Reconstruct the source line set
    /// from the page observations, require a valid source candidate, and match
    /// each candidate to a distinct, tight `.verticalLine` result.  The
    /// one-to-one rule also prevents a synthesized column envelope from being
    /// treated as proof that several independent source lines were read.
    private static func hasCompleteJapaneseLineCoverage(
        for block: ImageOCRLayoutBlock,
        sourceObservations: [VisionOCRObservation],
        lineRefined: [VisionOCRObservation]
    ) -> Bool {
        let sourceLineCandidates = japaneseLineCoverageSourceCandidates(
            for: block,
            sourceObservations: sourceObservations
        )
        guard !sourceLineCandidates.isEmpty else {
            return false
        }

        var availableLineResults = lineRefined
            .filter { observation in
                guard observation.observationRole == .verticalLine,
                      !observation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let lineRegion = observation.lineRegionRect?.normalizedToUnit() else {
                    return false
                }
                return overlapRatio(observation.rect, block.rect) >= 0.25
                    && japaneseLineRegionOverlapsBlock(observation, block: block)
                    && isVerticalLineCandidate(lineRegion)
            }
            .sorted { isBetterJapaneseObservation($0, $1) }

        guard availableLineResults.count >= sourceLineCandidates.count else {
            return false
        }

        for candidate in sourceLineCandidates {
            guard let resultIndex = availableLineResults.firstIndex(where: {
                isReliableJapaneseLineCoverageResult($0, candidate: candidate)
                    && japaneseLineCoverageMatches($0, candidate: candidate)
            }) else {
                return false
            }
            // A result can prove coverage for only one source line.  Removing
            // it keeps a broad/synthesized result from satisfying every line.
            availableLineResults.remove(at: resultIndex)
        }
        return true
    }

    private static func japaneseLineCoverageSourceCandidates(
        for block: ImageOCRLayoutBlock,
        sourceObservations: [VisionOCRObservation]
    ) -> [VisionOCRObservation] {
        let candidates = sourceObservations.filter { observation in
            let lineRegion = observation.lineRegionRect ?? observation.rect
            return overlapRatio(observation.rect, block.rect) >= 0.25
                && japaneseLineRegionOverlapsBlock(observation, block: block)
                && isVerticalLineCandidate(lineRegion)
        }

        var uniqueCandidates: [VisionOCRObservation] = []
        for candidate in candidates.sorted(by: { isBetterJapaneseObservation($0, $1) }) {
            guard !uniqueCandidates.contains(where: {
                isDuplicateObservation(candidate, of: $0, prefersJapanese: true)
            }) else {
                continue
            }
            uniqueCandidates.append(candidate)
        }
        return uniqueCandidates
    }

    /// A line-region geometry match alone is not proof that OCR recovered the
    /// line. Keep weak Vision output on the block-crop fallback path, where the
    /// surrounding glyph context gives the recognizer another chance. A single
    /// glyph may still cover a genuinely single-glyph source line, but it must
    /// not make a multi-glyph source line look complete.
    private static func isReliableJapaneseLineCoverageResult(
        _ result: VisionOCRObservation,
        candidate: VisionOCRObservation
    ) -> Bool {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              result.confidence.isFinite,
              result.confidence >= 0.48,
              japaneseScriptDensity(in: text) >= 0.5 else {
            return false
        }

        let candidateLength = candidate.text.unicodeScalars.count
        let resultLength = text.unicodeScalars.count
        return candidateLength < 2 || resultLength >= 2
    }

    private static func japaneseLineCoverageMatches(
        _ lineResult: VisionOCRObservation,
        candidate: VisionOCRObservation
    ) -> Bool {
        guard let resultRegion = lineResult.lineRegionRect?.normalizedToUnit(),
              let candidateRegion = (candidate.lineRegionRect ?? candidate.rect).normalizedToUnit() else {
            return false
        }
        let overlap = overlapRatio(resultRegion, candidateRegion)
        guard overlap >= 0.72 else {
            return false
        }

        // A line result may be slightly wider after crop mapping, but a result
        // whose tight region is materially larger than the source line is a
        // synthesized/noisy envelope rather than proof of per-line OCR.
        let candidateArea = max(candidateRegion.width * candidateRegion.height, 0.0001)
        let resultArea = resultRegion.width * resultRegion.height
        return resultArea <= candidateArea * 1.75
    }

    /// Build a conservative Koharu-style line-region proxy for fragmented
    /// Japanese vertical glyph observations. This is intentionally narrower
    /// than the regular line candidate gate: only short Japanese fragments
    /// that share a column and have bounded vertical gaps are eligible.
    private static func synthesizeJapaneseVerticalLineCandidates(
        observations: [VisionOCRObservation],
        blocks: [ImageOCRLayoutBlock]
    ) -> [VisionOCRObservation] {
        var synthesized: [VisionOCRObservation] = []

        for block in blocks {
            let fragments = observations
                .filter { observation in
                    overlapRatio(observation.rect, block.rect) >= 0.25
                        && japaneseLineRegionOverlapsBlock(observation, block: block)
                        && isJapaneseVerticalFragment(observation)
                }
                .map {
                    JapaneseVerticalCropFragment(
                        observation: $0,
                        rect: $0.lineRegionRect ?? $0.rect
                    )
                }
            guard fragments.count >= 2 else { continue }

            let medianWidth = median(fragments.map { $0.rect.width })
            let columnTolerance = min(max(medianWidth * 2.0, 0.018), 0.08)
            var columns: [[JapaneseVerticalCropFragment]] = []
            for fragment in fragments.sorted(by: { $0.rect.midX < $1.rect.midX }) {
                guard let lastIndex = columns.indices.last else {
                    columns.append([fragment])
                    continue
                }
                let anchor = columns[lastIndex]
                    .map { $0.rect.midX }
                    .reduce(0, +) / Double(columns[lastIndex].count)
                if abs(fragment.rect.midX - anchor) <= columnTolerance {
                    columns[lastIndex].append(fragment)
                } else {
                    columns.append([fragment])
                }
            }

            for column in columns where column.count >= 2 {
                let ordered = column.sorted { $0.rect.y < $1.rect.y }
                let medianHeight = median(ordered.map { $0.rect.height })
                let maximumGap = min(max(medianHeight * 3.0, 0.04), 0.16)
                guard zip(ordered, ordered.dropFirst()).allSatisfy({ pair in
                    let gap = pair.1.rect.y - pair.0.rect.maxY
                    return gap <= maximumGap
                }) else {
                    continue
                }

                let rect = ordered
                    .map(\.rect)
                    .dropFirst()
                    .reduce(ordered[0].rect) { $0.union($1) }
                let aspectRatio = rect.height / max(rect.width, 0.001)
                guard rect.height >= max(block.rect.height * 0.18, 0.035),
                      aspectRatio >= 1.25 else {
                    continue
                }

                let best = ordered
                    .map(\.observation)
                    .max(by: { isBetterJapaneseObservation($0, $1) }) ?? ordered[0].observation
                let confidence = ordered
                    .map { $0.observation.confidence }
                    .reduce(Float(0), +) / Float(ordered.count)
                synthesized.append(
                    VisionOCRObservation(
                        text: ordered.map { $0.observation.text }.joined(),
                        confidence: confidence,
                        rect: rect,
                        lineRegionRect: rect,
                        lineRegionQuad: nil,
                        rotationApplied: best.rotationApplied,
                        sourceDirectionHint: .vertical,
                        observationRole: best.observationRole
                    )
                )
            }
        }

        return deduplicateJapaneseObservations(synthesized)
    }

    private static func isJapaneseVerticalFragment(_ observation: VisionOCRObservation) -> Bool {
        let region = observation.lineRegionRect ?? observation.rect
        let scalarCount = observation.text.unicodeScalars.count
        let ratio = region.height / max(region.width, 0.001)
        return scalarCount > 0
            && scalarCount <= 2
            && japaneseScriptDensity(in: observation.text) >= 0.5
            && region.height >= 0.012
            && ratio >= 0.75
    }

    private static func isSameJapaneseLineRegion(
        _ candidate: VisionOCRObservation,
        as covered: VisionOCRObservation
    ) -> Bool {
        let candidateRegion = candidate.lineRegionRect ?? candidate.rect
        let coveredRegion = covered.lineRegionRect ?? covered.rect
        return overlapRatio(candidateRegion, coveredRegion) >= 0.72
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// Run one bounded crop reread and map its geometry back to the source page.
    /// Keeping this as one helper makes the primary and opposite orientation pass
    /// use identical language, scaling, post-processing, and coordinate rules.
    private static func recognizeJapaneseCropPass(
        crop: CGImage,
        cropRect: CGRect,
        originalImage: CGImage,
        angle: Int,
        recognitionLanguages: [String],
        minimumTextHeight: Float,
        cropScale: CGFloat = 1,
        observationRole: VisionOCRObservationRole = .crop
    ) -> [VisionOCRObservation] {
        guard let rotatedCrop = try? rotatedImage(crop, angle: angle),
              let cropObservations = try? recognizeObservations(
                  in: rotatedCrop,
                  recognitionLanguages: recognitionLanguages,
                  minimumTextHeight: minimumTextHeight,
                  automaticallyDetectsLanguage: false,
                  rotationApplied: angle,
                  postProcessJapaneseText: true,
                  usesLanguageCorrection: false,
                  observationRole: observationRole
              ) else {
            return []
        }
        return cropObservations.map {
            mapRotatedCropObservation(
                $0,
                rotatedImage: rotatedCrop,
                cropRect: cropRect,
                originalImage: originalImage,
                angle: angle,
                cropScale: cropScale
            )
        }
    }

    private static func oppositeJapaneseOrientation(_ angle: Int) -> Int {
        angle == 270 ? 90 : 270
    }

    /// Koharu's vertical `warp_line_region` normalizes a vertical line region
    /// and then applies `rotate270` before OCR. Keep this preference scoped to
    /// ordinary-image Japanese line rereads; block/tile paths still use their
    /// own orientation evidence and retain the opposite-direction fallback.
    private static func koharuPreferredJapaneseVerticalLineOrientation() -> Int {
        270
    }

    private static func needsJapaneseOrientationFallback(
        _ observations: [VisionOCRObservation]
    ) -> Bool {
        guard let best = observations.max(by: { isBetterJapaneseObservation($0, $1) }) else {
            return true
        }
        let textLength = best.text.unicodeScalars.count
        return best.confidence < 0.48
            || japaneseScriptDensity(in: best.text) < 0.5
            || textLength <= 1
    }

    private static func japaneseScriptDensity(in text: String) -> Double {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { return 0 }
        let japaneseCount = scalars.count { scalar in
            switch scalar.value {
            case 0x3000...0x303F, 0x3040...0x30FF, 0x3400...0x4DBF,
                 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF61...0xFF9F:
                true
            default:
                false
            }
        }
        return Double(japaneseCount) / Double(scalars.count)
    }

    private static func japanesePunctuationDensity(in text: String) -> Double {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { return 0 }
        let punctuationCount = scalars.count { scalar in
            switch scalar.value {
            case 0x3000...0x303F, 0xFF61...0xFF65:
                true
            default:
                false
            }
        }
        return Double(punctuationCount) / Double(scalars.count)
    }

    private static func japaneseObservationEvidence(in text: String) -> Double {
        let scriptDensity = japaneseScriptDensity(in: text)
        guard scriptDensity > 0 else {
            // Keep the preference a tie-breaker rather than rejecting a crop:
            // Vision can legitimately return a Latin symbol or a mixed label.
            return -0.65
        }
        let punctuationDensity = japanesePunctuationDensity(in: text)
        let boundedEvidence = min(
            scriptDensity * 0.9 + punctuationDensity * 0.2,
            1.1
        )
        return boundedEvidence
    }

    private static func recognizeJapanesePerspectiveLineCrop(
        candidate: VisionOCRObservation,
        in image: CGImage,
        angle: Int,
        recognitionLanguages: [String],
        consumedPixels: inout CGFloat
    ) -> VisionOCRObservation? {
        guard let quad = candidate.lineRegionQuad,
              let warped = perspectiveCorrectedLineImage(in: image, quad: quad) else {
            return nil
        }

        let warpedPixels = CGFloat(warped.width) * CGFloat(warped.height)
        guard warpedPixels.isFinite,
              warpedPixels >= 4,
              warpedPixels <= 4_000_000 else {
            return nil
        }

        // Perspective line regions are also Koharu text-node crops. Reuse the
        // same grayscale + bounded upscale boundary as block/axis-aligned
        // rereads, and charge the bounded result against the page budget so a
        // collection of tiny lines cannot expand into an unbounded workload.
        let preparedCrop = prepareJapaneseCropForVision(warped)
        let preparedPixels = CGFloat(preparedCrop.image.width) * CGFloat(preparedCrop.image.height)
        guard preparedPixels.isFinite,
              preparedPixels >= 4,
              preparedPixels <= 4_000_000,
              consumedPixels + preparedPixels <= 16_000_000 else {
            return nil
        }
        consumedPixels += preparedPixels

        guard let rotated = try? rotatedImage(preparedCrop.image, angle: angle),
              let observations = try? recognizeObservations(
                  in: rotated,
                  recognitionLanguages: recognitionLanguages,
                  minimumTextHeight: 0.002,
                  automaticallyDetectsLanguage: false,
                  rotationApplied: angle,
                  postProcessJapaneseText: true,
                  usesLanguageCorrection: false,
                  observationRole: .verticalLine
              ) else {
            return nil
        }

        let ordered = orderedJapanesePerspectiveLineObservations(
            observations,
            angle: angle
        )
        let text = ordered
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let confidence = ordered.reduce(Float(0)) { $0 + $1.confidence }
            / Float(ordered.count)
        return VisionOCRObservation(
            text: text,
            confidence: confidence,
            rect: candidate.rect,
            lineRegionRect: candidate.lineRegionRect,
            lineRegionQuad: candidate.lineRegionQuad,
            rotationApplied: angle,
            sourceDirectionHint: .vertical,
            observationRole: .verticalLine
        )
    }

    /// Assemble observations from one warped vertical line in the same reading
    /// direction as Koharu's `rotate270` vertical line crop. After the source
    /// column is rotated, its original top-to-bottom order lies on the x axis:
    /// the 90-degree pass reads left-to-right, while the 270-degree pass reads
    /// right-to-left. Keep y as a bounded tie-breaker for a Vision result that
    /// contains more than one row, rather than letting that noise reverse the
    /// primary line order.
    private static func orderedJapanesePerspectiveLineObservations(
        _ observations: [VisionOCRObservation],
        angle: Int
    ) -> [VisionOCRObservation] {
        guard observations.count > 1 else { return observations }
        let xTolerance = 0.02
        let readsRightToLeft = angle == 270
        return observations.sorted { lhs, rhs in
            let xDelta = abs(lhs.rect.midX - rhs.rect.midX)
            if xDelta > xTolerance {
                return readsRightToLeft
                    ? lhs.rect.midX > rhs.rect.midX
                    : lhs.rect.midX < rhs.rect.midX
            }

            let yDelta = abs(lhs.rect.midY - rhs.rect.midY)
            if yDelta > xTolerance {
                return lhs.rect.midY < rhs.rect.midY
            }
            return isBetterJapaneseObservation(lhs, rhs)
        }
    }

    private static func perspectiveCorrectedLineImage(
        in image: CGImage,
        quad: ImageOCRLayoutQuad
    ) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let points = quad.points.map {
            CGPoint(x: $0.x * width, y: $0.y * height)
        }
        guard points.count == 4,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              quad.isConvex else {
            return nil
        }

        let bounds = points.reduce(CGRect.null) { partial, point in
            partial.union(CGRect(origin: point, size: .zero))
        }.integral
        let imageBounds = CGRect(x: 0, y: 0, width: width, height: height)
        let cropBounds = bounds.intersection(imageBounds)
        guard cropBounds.width >= 2,
              cropBounds.height >= 2,
              cropBounds.width <= 4096,
              cropBounds.height <= 4096,
              let croppedImage = image.cropping(to: cropBounds) else {
            return nil
        }

        // Koharu's warp_line_region first crops the line polygon's bbox and
        // only then projects that local image. Keeping the same boundary avoids
        // feeding unrelated page pixels into a tiny Japanese line crop and
        // keeps the perspective budget proportional to the actual TextRegion.
        let localPoints = points.map {
            CGPoint(x: $0.x - cropBounds.minX, y: $0.y - cropBounds.minY)
        }
        let croppedHeight = CGFloat(croppedImage.height)
        let ciImage = CIImage(cgImage: croppedImage)
        let filter = CIFilter(name: "CIPerspectiveCorrection")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(
            CIVector(cgPoint: CGPoint(x: localPoints[0].x, y: croppedHeight - localPoints[0].y)),
            forKey: "inputTopLeft"
        )
        filter?.setValue(
            CIVector(cgPoint: CGPoint(x: localPoints[1].x, y: croppedHeight - localPoints[1].y)),
            forKey: "inputTopRight"
        )
        filter?.setValue(
            CIVector(cgPoint: CGPoint(x: localPoints[2].x, y: croppedHeight - localPoints[2].y)),
            forKey: "inputBottomRight"
        )
        filter?.setValue(
            CIVector(cgPoint: CGPoint(x: localPoints[3].x, y: croppedHeight - localPoints[3].y)),
            forKey: "inputBottomLeft"
        )
        guard let output = filter?.outputImage else { return nil }
        let outputExtent = output.extent.integral
        guard outputExtent.width >= 2,
              outputExtent.height >= 2,
              outputExtent.width <= 4096,
              outputExtent.height <= 4096 else {
            return nil
        }
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let rendered = context.createCGImage(output, from: outputExtent) else {
            return nil
        }

        // Koharu's `warp_line_region` does not rely on the projection library's
        // natural output extent. It derives a target canvas from the quad's
        // vertical/horizontal axis lengths first, then projects into that
        // canvas. Core Image owns the projection here, so apply the same
        // geometry contract as a bounded post-projection resize. This keeps a
        // skewed/narrow Japanese line at a stable glyph aspect ratio before the
        // shared grayscale/upscale preprocessor runs.
        guard let targetSize = koharuVerticalLineWarpTargetSize(
            localPoints,
            maximumDimension: 4_096,
            maximumPixels: 4_000_000
        ) else {
            // Character-range geometry can be unavailable or degenerate on a
            // particular Vision revision. Preserve the existing natural warp
            // as the safe fallback instead of dropping the line reread.
            return rendered
        }
        let targetWidth = Int(targetSize.width.rounded())
        let targetHeight = Int(targetSize.height.rounded())
        guard targetWidth >= 2, targetHeight >= 2 else {
            return rendered
        }
        guard rendered.width != targetWidth || rendered.height != targetHeight else {
            return rendered
        }
        return resizedImage(
            rendered,
            pixelWidth: targetWidth,
            pixelHeight: targetHeight
        ) ?? rendered
    }

    /// Mirror Koharu's vertical `warp_line_region` target geometry. Its
    /// `quad_axis_lengths` returns the line's long (vertical) and short
    /// (horizontal/text-height) axes; vertical crops are projected to
    /// `(textHeight, textHeight * ratio)` before the later 90°/270° reread.
    /// Keep the target finite and bounded so malformed Vision geometry cannot
    /// create an oversized intermediate image.
    private static func koharuVerticalLineWarpTargetSize(
        _ points: [CGPoint],
        maximumDimension: CGFloat,
        maximumPixels: CGFloat
    ) -> CGSize? {
        guard points.count == 4,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              maximumDimension.isFinite,
              maximumDimension >= 2,
              maximumPixels.isFinite,
              maximumPixels >= 4 else {
            return nil
        }

        func midpoint(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
            CGPoint(
                x: (lhs.x + rhs.x) * 0.5,
                y: (lhs.y + rhs.y) * 0.5
            )
        }
        func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
            hypot(lhs.x - rhs.x, lhs.y - rhs.y)
        }

        let top = midpoint(points[0], points[1])
        let right = midpoint(points[1], points[2])
        let bottom = midpoint(points[2], points[3])
        let left = midpoint(points[3], points[0])
        let verticalLength = distance(top, bottom)
        let horizontalLength = distance(left, right)
        guard verticalLength.isFinite,
              horizontalLength.isFinite,
              verticalLength > 0,
              horizontalLength > 0 else {
            return nil
        }

        let textHeight = max(horizontalLength.rounded(), 1)
        let ratio = verticalLength / horizontalLength
        let rawWidth = textHeight
        let rawHeight = max((textHeight * ratio).rounded(), 1)
        guard rawWidth.isFinite,
              rawHeight.isFinite,
              rawWidth >= 1,
              rawHeight >= 1 else {
            return nil
        }

        let areaScale = sqrt(maximumPixels / (rawWidth * rawHeight))
        let scale = min(
            1,
            maximumDimension / rawWidth,
            maximumDimension / rawHeight,
            areaScale
        )
        guard scale.isFinite, scale > 0 else { return nil }
        let width = max((rawWidth * scale).rounded(), 1)
        let height = max((rawHeight * scale).rounded(), 1)
        guard width.isFinite,
              height.isFinite,
              width * height <= maximumPixels + 1 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private static func isVerticalLineCandidate(_ rect: ImageOCRLayoutRect) -> Bool {
        rect.height / max(rect.width, 0.001) >= 1.25
            && rect.height >= 0.018
    }

    /// Return only reliable line rereads that may suppress a broader fallback.
    /// Missing or invalid tight geometry falls back to the request-level box,
    /// matching the existing safe geometry boundary. Weak or non-Japanese text
    /// remains uncovered so detector/tile and block recovery can try again.
    private static func japaneseLinePathRegion(
        _ observation: VisionOCRObservation
    ) -> ImageOCRLayoutRect? {
        let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard observation.observationRole == .verticalLine,
              !text.isEmpty,
              observation.confidence.isFinite,
              observation.confidence >= 0.48,
              japaneseScriptDensity(in: text) >= 0.5 else {
            return nil
        }
        let region = observation.lineRegionRect?.normalizedToUnit()
            ?? observation.rect.normalizedToUnit()
        guard let region, isVerticalLineCandidate(region) else {
            return nil
        }
        return region
    }

    /// Koharu associates each detector line polygon with its owning TextRegion.
    /// Vision's request-level box can be wider after rotation, so require the
    /// tighter character-range geometry to overlap the current Japanese block
    /// whenever that geometry is available. Missing/invalid tight geometry
    /// keeps the request-level overlap as the safe compatibility fallback.
    private static func japaneseLineRegionOverlapsBlock(
        _ observation: VisionOCRObservation,
        block: ImageOCRLayoutBlock
    ) -> Bool {
        guard let lineRegion = observation.lineRegionRect?.normalizedToUnit() else {
            return true
        }
        return overlapRatio(lineRegion, block.rect) >= 0.25
    }

    private static func koharuVerticalCropPadding(
        _ rect: ImageOCRLayoutRect,
        imageSize: CGSize
    ) -> (horizontal: Double, vertical: Double)? {
        let imageWidth = Double(imageSize.width)
        let imageHeight = Double(imageSize.height)
        guard imageWidth.isFinite, imageWidth > 0,
              imageHeight.isFinite, imageHeight > 0 else {
            return nil
        }

        // Koharu estimates font size from the smaller text-node dimension and
        // applies direction-aware pixel padding before cropping. Keep that
        // calculation in pixel space, then map the padding back to normalized
        // Vision coordinates so a 576px-wide fixture and a retina image use
        // the same model-independent crop boundary.
        let widthPixels = max(rect.width * imageWidth, 1)
        let heightPixels = max(rect.height * imageHeight, 1)
        let fontSizePixels = max(min(widthPixels, heightPixels), 1)
        let basePaddingPixels = max(fontSizePixels * 0.08, 2)
        let horizontalPaddingPixels = max(fontSizePixels * 0.18, basePaddingPixels)
        let verticalPaddingPixels = max(fontSizePixels * 0.12, basePaddingPixels)
        return (
            min(horizontalPaddingPixels / imageWidth, 0.08),
            min(verticalPaddingPixels / imageHeight, 0.08)
        )
    }

    private static func expandedVerticalLineCropRect(
        _ rect: ImageOCRLayoutRect,
        imageSize: CGSize? = nil
    ) -> ImageOCRLayoutRect {
        // Keep the old normalized fallback for callers without source pixels;
        // the OCR path always supplies imageSize and uses Koharu's font estimate.
        let padding = imageSize.flatMap { koharuVerticalCropPadding(rect, imageSize: $0) }
        let horizontalPadding = padding?.horizontal
            ?? min(max(rect.width * 0.18, 0.008), 0.06)
        let verticalPadding = padding?.vertical
            ?? min(max(rect.height * 0.12, 0.006), 0.06)
        return ImageOCRLayoutRect(
            x: rect.x - horizontalPadding,
            y: rect.y - verticalPadding,
            width: rect.width + horizontalPadding * 2,
            height: rect.height + verticalPadding * 2
        ).normalizedToUnit() ?? rect
    }

    private static func expandedVerticalLineCropRect(
        for observation: VisionOCRObservation,
        imageSize: CGSize? = nil
    ) -> ImageOCRLayoutRect {
        let region = observation.lineRegionRect ?? observation.rect
        return expandedVerticalLineCropRect(region, imageSize: imageSize)
    }

    /// Mirror Koharu's `crop_text_block_bbox` envelope rule for a vertical
    /// Japanese block. Koharu starts with the detector TextRegion bbox and
    /// expands it to include every line polygon before applying direction-aware
    /// font padding. Vision exposes that tighter geometry as `lineRegionRect`;
    /// union only related observations and never shrink the layout block, so a
    /// missing or invalid line hint safely returns the original block crop.
    private static func koharuVerticalBlockCropRect(
        _ block: ImageOCRLayoutBlock,
        observations: [VisionOCRObservation],
        imageSize: CGSize
    ) -> ImageOCRLayoutRect {
        let lineRegions = observations
            .filter { observation in
                overlapRatio(observation.rect, block.rect) >= 0.25
                    && japaneseLineRegionOverlapsBlock(observation, block: block)
            }
            .compactMap(\.lineRegionRect)
            .compactMap { $0.normalizedToUnit() }

        guard !lineRegions.isEmpty else {
            return expandedVerticalCropRect(block.rect, imageSize: imageSize)
        }

        let envelope = lineRegions.reduce(block.rect) { partial, region in
            partial.union(region)
        }
        // Koharu keeps `detected_font_size_px` from the original TextRegion
        // while expanding the union envelope. The Vision layout block has no
        // detector font field, so retain its original min-dimension proxy as
        // the padding anchor instead of letting a multi-line envelope inflate
        // the inferred glyph size.
        return expandedKoharuVerticalBlockEnvelopeCropRect(
            envelope,
            fontSizeReference: block.rect,
            imageSize: imageSize
        )
    }

    /// Apply Koharu's direction-aware font padding to a line-expanded block
    /// while preserving the original block's font-size proxy. This mirrors
    /// `expanded_text_block_crop_bounds`: line geometry changes the envelope,
    /// not the detected glyph-size estimate used for padding.
    private static func expandedKoharuVerticalBlockEnvelopeCropRect(
        _ envelope: ImageOCRLayoutRect,
        fontSizeReference: ImageOCRLayoutRect,
        imageSize: CGSize
    ) -> ImageOCRLayoutRect {
        guard let padding = koharuVerticalCropPadding(
            fontSizeReference,
            imageSize: imageSize
        ) else {
            return expandedVerticalCropRect(envelope, imageSize: imageSize)
        }
        return ImageOCRLayoutRect(
            x: envelope.x - padding.horizontal,
            y: envelope.y - padding.vertical,
            width: envelope.width + padding.horizontal * 2,
            height: envelope.height + padding.vertical * 2
        ).normalizedToUnit() ?? envelope
    }

    private static func expandedVerticalCropRect(
        _ rect: ImageOCRLayoutRect,
        imageSize: CGSize? = nil
    ) -> ImageOCRLayoutRect {
        let padding = imageSize.flatMap { koharuVerticalCropPadding(rect, imageSize: $0) }
        let horizontalPadding = padding?.horizontal
            ?? min(max(rect.width * 0.18, 0.01), 0.08)
        let verticalPadding = padding?.vertical
            ?? min(max(rect.height * 0.12, 0.01), 0.08)
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
        return resizedImage(
            image,
            pixelWidth: width,
            pixelHeight: height
        )
    }

    private static func resizedImage(
        _ image: CGImage,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> CGImage? {
        guard pixelWidth >= 1, pixelHeight >= 1 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
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
            in: CGRect(
                x: 0,
                y: 0,
                width: CGFloat(pixelWidth),
                height: CGFloat(pixelHeight)
            )
        )
        return context.makeImage()
    }

    /// Apply the useful, model-independent portion of Koharu's Manga OCR crop
    /// preprocessor before a Vision reread. Keep the operation bounded because
    /// this is called for many vertical blocks on a manga page. A failed Core
    /// Image conversion or resize is deliberately a safe no-op.
    private static func prepareJapaneseCropForVision(
        _ image: CGImage,
        maximumPixels: CGFloat = 4_000_000,
        preferredScale: CGFloat = 2
    ) -> (image: CGImage, scale: CGFloat) {
        let grayscale = grayscaleJapaneseCrop(image) ?? image
        let pixels = CGFloat(grayscale.width) * CGFloat(grayscale.height)
        guard pixels.isFinite, pixels > 0,
              maximumPixels.isFinite, maximumPixels > 0,
              preferredScale.isFinite, preferredScale > 1 else {
            return (grayscale, 1)
        }

        let boundedScale = min(preferredScale, sqrt(maximumPixels / pixels))
        guard boundedScale.isFinite,
              boundedScale > 1.01,
              let resized = resizedImage(grayscale, scale: boundedScale) else {
            return (grayscale, 1)
        }
        return (resized, boundedScale)
    }

    /// Koharu Manga OCR receives a grayscale crop; applying that boundary to
    /// Japanese Vision rereads suppresses colored screentones without touching
    /// the normal-language full-page OCR path.
    private static func grayscaleJapaneseCrop(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage else { return nil }
        let extent = output.extent.integral
        guard extent.width >= 2, extent.height >= 2 else { return nil }
        let context = CIContext(options: [.cacheIntermediates: false])
        return context.createCGImage(output, from: extent)
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
        let originalLineRegionQuad = observation.lineRegionQuad.map {
            mapRotatedCropRegionQuad(
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
            lineRegionQuad: originalLineRegionQuad,
            rotationApplied: observation.rotationApplied,
            sourceDirectionHint: .vertical,
            observationRole: observation.observationRole
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

    private static func mapRotatedCropRegionQuad(
        _ quad: ImageOCRLayoutQuad,
        rotatedImage: CGImage,
        cropRect: CGRect,
        originalImage: CGImage,
        angle: Int,
        cropScale: CGFloat
    ) -> ImageOCRLayoutQuad {
        let rotatedSize = CGSize(width: CGFloat(rotatedImage.width), height: CGFloat(rotatedImage.height))
        let cropSize = CGSize(width: cropRect.width, height: cropRect.height)
        let originalSize = CGSize(width: CGFloat(originalImage.width), height: CGFloat(originalImage.height))
        let unscaledRotatedSize = angle == 90 || angle == 270
            ? CGSize(width: cropSize.height, height: cropSize.width)
            : cropSize
        let scaleX = rotatedSize.width / max(unscaledRotatedSize.width, 1)
        let scaleY = rotatedSize.height / max(unscaledRotatedSize.height, 1)
        let safeScale = cropScale.isFinite && cropScale > 0 ? cropScale : 1
        let points = quad.points.map { point in
            let scaledPoint = CGPoint(
                x: point.x * rotatedSize.width,
                y: point.y * rotatedSize.height
            )
            let unscaledPoint = CGPoint(
                x: scaledPoint.x / max(scaleX, safeScale),
                y: scaledPoint.y / max(scaleY, safeScale)
            )
            let local = Self.mapPointToOriginal(
                unscaledPoint,
                angle: angle,
                originalSize: cropSize
            )
            return ImageOCRLayoutPoint(
                x: (cropRect.minX + local.x) / originalSize.width,
                y: (cropRect.minY + local.y) / originalSize.height
            )
        }
        return ImageOCRLayoutQuad(points: points).normalized() ?? quad
    }

    private static func deduplicateJapaneseObservations(
        _ observations: [VisionOCRObservation]
    ) -> [VisionOCRObservation] {
        deduplicateObservations(observations, prefersJapanese: true)
    }

    private static func deduplicateObservations(
        _ observations: [VisionOCRObservation],
        prefersJapanese: Bool = false
    ) -> [VisionOCRObservation] {
        var output: [VisionOCRObservation] = []
        for observation in observations.sorted(by: {
            isBetterObservation($0, $1, prefersJapanese: prefersJapanese)
        }) {
            guard let duplicateIndex = output.firstIndex(where: {
                isDuplicateObservation(
                    observation,
                    of: $0,
                    prefersJapanese: prefersJapanese
                )
            }) else {
                output.append(observation)
                continue
            }
            if isBetterObservation(
                observation,
                than: output[duplicateIndex],
                prefersJapanese: prefersJapanese
            ) {
                output[duplicateIndex] = observation
            }
        }
        return output
    }

    private static func isBetterJapaneseObservation(
        _ lhs: VisionOCRObservation,
        _ rhs: VisionOCRObservation
    ) -> Bool {
        isBetterObservation(lhs, rhs, prefersJapanese: true)
    }

    private static func isBetterObservation(
        _ lhs: VisionOCRObservation,
        _ rhs: VisionOCRObservation,
        prefersJapanese: Bool = false
    ) -> Bool {
        let lhsScore = observationScore(lhs, prefersJapanese: prefersJapanese)
        let rhsScore = observationScore(rhs, prefersJapanese: prefersJapanese)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        if lhs.rotationApplied != rhs.rotationApplied {
            let lhsUsesPreferredRotation = lhs.rotationApplied
                == preferredJapaneseRotation(for: lhs)
            let rhsUsesPreferredRotation = rhs.rotationApplied
                == preferredJapaneseRotation(for: rhs)
            if lhsUsesPreferredRotation != rhsUsesPreferredRotation {
                return lhsUsesPreferredRotation
            }
            return lhs.rotationApplied == 90
        }
        return lhs.text < rhs.text
    }

    private static func preferredJapaneseRotation(
        for observation: VisionOCRObservation
    ) -> Int {
        observation.observationRole == .verticalLine ? 270 : 90
    }

    private static func isBetterObservation(
        _ lhs: VisionOCRObservation,
        than rhs: VisionOCRObservation,
        prefersJapanese: Bool = false
    ) -> Bool {
        isBetterObservation(lhs, rhs, prefersJapanese: prefersJapanese)
    }

    private static func observationScore(
        _ observation: VisionOCRObservation,
        prefersJapanese: Bool = false
    ) -> Double {
        let cjkCount = observation.text.unicodeScalars.count { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: true
            default: false
            }
        }
        let rotationBonus: Double
        if prefersJapanese, observation.observationRole == .verticalLine {
            // Koharu's vertical line region always enters OCR through rotate270.
            // Keep this bounded so a genuinely stronger opposite-direction
            // result can still win on confidence or text evidence.
            rotationBonus = observation.rotationApplied == 270 ? 0.15 : 0
        } else {
            rotationBonus = observation.rotationApplied == 90 ? 0.15 : 0
        }
        let baseScore = Double(observation.text.unicodeScalars.count)
            + Double(observation.confidence) * 8
            + Double(cjkCount) * 0.25
            + rotationBonus
        guard prefersJapanese else { return baseScore }

        // A crop can produce a long, high-confidence Latin-looking fallback
        // even when the source page is Japanese. Keep the normal score intact
        // for every other language, but give Japanese-script candidates a
        // bounded tie-breaker during Japanese fusion and penalize a candidate
        // with no Japanese evidence slightly. This mirrors Koharu's language-
        // specific recognition boundary without making Japanese a hard gate.
        return baseScore + japaneseObservationEvidence(in: observation.text)
    }

    private static func isDuplicateObservation(
        _ lhs: VisionOCRObservation,
        of rhs: VisionOCRObservation,
        prefersJapanese: Bool = false
    ) -> Bool {
        // Koharu's OCR is handed one detector line region at a time. Vision's
        // request-level boxes can be wider than that region, especially after
        // a rotated crop is mapped back to the page; using those boxes for all
        // Japanese fusion can therefore merge neighboring vertical lines. Use
        // the tighter character-range geometry only when both candidates have
        // it, and retain the request box as a safe fallback for incomplete
        // observations and every non-Japanese path.
        let lhsGeometry: ImageOCRLayoutRect
        let rhsGeometry: ImageOCRLayoutRect
        if prefersJapanese,
           let lhsLineRegion = lhs.lineRegionRect,
           let rhsLineRegion = rhs.lineRegionRect {
            lhsGeometry = lhsLineRegion
            rhsGeometry = rhsLineRegion
        } else {
            lhsGeometry = lhs.rect
            rhsGeometry = rhs.rect
        }

        let intersection = intersectionArea(lhsGeometry, rhsGeometry)
        let minimumArea = max(
            min(
                lhsGeometry.width * lhsGeometry.height,
                rhsGeometry.width * rhsGeometry.height
            ),
            0.0001
        )
        let overlap = intersection / minimumArea
        guard overlap >= 0.45 else { return false }

        // Koharu's merge_slice_regions collapses a detector region that is
        // almost completely contained in another slice, or whose same-label
        // regions have IoU >= 0.50, before OCR text is compared. At this stage
        // the closest safe equivalent is a pair of tight character-range
        // regions: when both Japanese candidates carry those regions and they
        // satisfy either Koharu geometry threshold, the geometry itself is
        // strong enough to treat them as one observation.
        // Request-level boxes remain text-dependent so neighboring vertical
        // lines cannot be merged merely because their broad crops overlap.
        let hasTightJapaneseGeometry = prefersJapanese
            && lhs.lineRegionRect != nil
            && rhs.lineRegionRect != nil
        if hasTightJapaneseGeometry {
            let tightRegionIoU = intersectionOverUnion(lhsGeometry, rhsGeometry)
            if overlap >= 0.85 || tightRegionIoU >= 0.50 {
                return true
            }
        }

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

    private static func intersectionOverUnion(
        _ lhs: ImageOCRLayoutRect,
        _ rhs: ImageOCRLayoutRect
    ) -> Double {
        let intersection = intersectionArea(lhs, rhs)
        let lhsArea = max(lhs.width * lhs.height, 0)
        let rhsArea = max(rhs.width * rhs.height, 0)
        let union = lhsArea + rhsArea - intersection
        guard union > 0 else { return 0 }
        return intersection / union
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
        let originalLineRegionQuad = observation.lineRegionQuad.map {
            mapRotatedRegionQuad(
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
            lineRegionQuad: originalLineRegionQuad,
            rotationApplied: observation.rotationApplied,
            observationRole: observation.observationRole
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

    private static func mapRotatedRegionQuad(
        _ quad: ImageOCRLayoutQuad,
        rotatedImage: CGImage,
        originalImage: CGImage,
        angle: Int
    ) -> ImageOCRLayoutQuad {
        let rotatedSize = CGSize(width: CGFloat(rotatedImage.width), height: CGFloat(rotatedImage.height))
        let originalSize = CGSize(width: CGFloat(originalImage.width), height: CGFloat(originalImage.height))
        let points = quad.points.map { point in
            let mapped = Self.mapPointToOriginal(
                CGPoint(
                    x: point.x * rotatedSize.width,
                    y: point.y * rotatedSize.height
                ),
                angle: angle,
                originalSize: originalSize
            )
            return ImageOCRLayoutPoint(
                x: mapped.x / originalSize.width,
                y: mapped.y / originalSize.height
            )
        }
        return ImageOCRLayoutQuad(points: points).normalized() ?? quad
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

private enum VisionOCRObservationRole: Equatable, Sendable {
    case page
    case crop
    case verticalLine
}

private struct VisionOCRObservation: Equatable, Sendable {
    var text: String
    var confidence: Float
    var rect: ImageOCRLayoutRect
    /// Character-range geometry is a tighter, Vision-provided line-region hint;
    /// `rect` remains the stable request-level box used by layout and fallback
    /// dedupe. Japanese fusion prefers this hint when both candidates provide it.
    var lineRegionRect: ImageOCRLayoutRect?
    /// The corresponding Vision quadrilateral enables a bounded Koharu-style
    /// perspective correction for Japanese vertical line crops. It is only a
    /// recognition hint; request-level `rect` remains the stable layout geometry.
    var lineRegionQuad: ImageOCRLayoutQuad?
    var rotationApplied: Int
    /// Set only by Japanese block/line/tile rereads that originate from a
    /// vertical layout candidate. This mirrors Koharu's TextBox source
    /// direction and prevents mapped crop geometry from overriding it.
    var sourceDirectionHint: ImageOCRLayoutDirection? = nil
    /// Keeps Koharu's vertical-line orientation preference alive through crop
    /// mapping and final Japanese observation fusion. Page/block/tile rereads
    /// retain their historical rotation tie-breaker.
    var observationRole: VisionOCRObservationRole = .page
}

private struct JapaneseVerticalCropFragment: Sendable {
    var observation: VisionOCRObservation
    var rect: ImageOCRLayoutRect
}

private struct JapanesePixelFirstRegion: Sendable {
    var rect: ImageOCRLayoutRect
    var detectorRotation: Int
}

private struct ImageOCRLayoutPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

private struct ImageOCRLayoutQuad: Equatable, Sendable {
    var points: [ImageOCRLayoutPoint]

    var boundingRect: ImageOCRLayoutRect {
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        return ImageOCRLayoutRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    var minimumEdgeLength: Double {
        guard points.count == 4 else { return 0 }
        return points.indices.map { index in
            let next = points[(index + 1) % points.count]
            let point = points[index]
            return hypot(next.x - point.x, next.y - point.y)
        }.min() ?? 0
    }

    var isConvex: Bool {
        guard points.count == 4 else { return false }
        let crosses = points.indices.map { index -> Double in
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let following = points[(index + 2) % points.count]
            return (next.x - current.x) * (following.y - next.y)
                - (next.y - current.y) * (following.x - next.x)
        }
        return crosses.allSatisfy { $0 > 0.000001 }
            || crosses.allSatisfy { $0 < -0.000001 }
    }

    func normalized() -> Self? {
        guard points.count == 4,
              points.allSatisfy({
                  $0.x.isFinite && $0.y.isFinite
                      && $0.x >= 0 && $0.x <= 1
                      && $0.y >= 0 && $0.y <= 1
              }),
              boundingRect.normalizedToUnit() != nil,
              minimumEdgeLength >= 0.002,
              isConvex else {
            return nil
        }
        return self
    }
}
