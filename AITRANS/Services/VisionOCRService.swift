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
                for angle in [90, 270] {
                    let rotatedOCRImage = try Self.rotatedImage(ocrImage, angle: angle)
                    let rotatedObservations = try Self.recognizeObservations(
                        in: rotatedOCRImage,
                        recognitionLanguages: japaneseOrientationLanguages,
                        minimumTextHeight: 0.006,
                        automaticallyDetectsLanguage: false,
                        rotationApplied: angle,
                        postProcessJapaneseText: true
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

            let finalObservations = sourceLanguage == .japanese
                ? Self.deduplicateJapaneseObservations(observations)
                : Self.deduplicateObservations(observations)
            let layoutObservations = finalObservations.map {
                ImageOCRLayoutObservation(
                    text: $0.text,
                    confidence: $0.confidence,
                    rect: $0.rect
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
        postProcessJapaneseText: Bool = false
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
                rotationApplied: rotationApplied
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
                rect: $0.rect
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
                && (isStandardVerticalCandidate || isCompactVerticalCandidate)
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
        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        var orientationFallbacksRemaining = 8
        for block in verticalBlocks {
            let angle = safeObservations
                .filter { overlapRatio($0.rect, block.rect) >= 0.25 }
                .sorted { isBetterJapaneseObservation($0, $1) }
                .first
                .map { $0.rotationApplied == 270 ? 270 : 90 }
                ?? 90
            guard let crop = cropImage(
                image,
                normalizedRect: expandedVerticalCropRect(block.rect, imageSize: imageSize)
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
        let safeObservations = deduplicateJapaneseObservations(observations)
        var candidates: [VisionOCRObservation] = []
        for block in blocks {
            candidates.append(contentsOf: safeObservations.filter { observation in
                overlapRatio(observation.rect, block.rect) >= 0.25
                    && isVerticalLineCandidate(observation.rect)
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
            let angle = candidate.rotationApplied == 270 ? 270 : 90
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
            let angle = candidate.rotationApplied == 270 ? 270 : 90
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
                cropScale: preparedCrop.scale
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
                    cropScale: preparedCrop.scale
                ))
            }
        }
        return refined
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
                        rotationApplied: best.rotationApplied
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
        cropScale: CGFloat = 1
    ) -> [VisionOCRObservation] {
        guard let rotatedCrop = try? rotatedImage(crop, angle: angle),
              let cropObservations = try? recognizeObservations(
                  in: rotatedCrop,
                  recognitionLanguages: recognitionLanguages,
                  minimumTextHeight: minimumTextHeight,
                  automaticallyDetectsLanguage: false,
                  rotationApplied: angle,
                  postProcessJapaneseText: true
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
                  postProcessJapaneseText: true
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
            rotationApplied: angle
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
            return lhs.rotationApplied == 90
        }
        return lhs.text < rhs.text
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
        let baseScore = Double(observation.text.unicodeScalars.count)
            + Double(observation.confidence) * 8
            + Double(cjkCount) * 0.25
            + (observation.rotationApplied == 90 ? 0.15 : 0)
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
}

private struct JapaneseVerticalCropFragment: Sendable {
    var observation: VisionOCRObservation
    var rect: ImageOCRLayoutRect
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
