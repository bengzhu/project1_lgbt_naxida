import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision

struct ImageOCRRecognitionOutput: Sendable {
    var blocks: [ImageTranslationBlock]
    var shadowLedger: ImageOCRShadowLedger
}

enum VisionOCRServiceError: LocalizedError {
    case imageDecodeFailed
    case imageRenderFailed
    case blockRecognitionFailed

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:
            "无法解码图片，请选择 PNG、JPEG 或系统支持的图片格式"
        case .imageRenderFailed:
            "无法准备日语竖排 OCR 方向图片，请重试或选择其他图片"
        case .blockRecognitionFailed:
            "无法重新识别此图片文字块，请保留原结果或手动修正"
        }
    }
}

struct JapanesePixelFirstRegionDiagnostic: Sendable {
    var rect: ImageOCRLayoutRect
    var detectorRotation: Int
    var characterCount: Int
    var isCompactCandidate: Bool
}

struct JapaneseCompactCropReadDiagnostic: Sendable {
    var rect: ImageOCRLayoutRect
    var angle: Int
    var text: String
    var confidence: Float
}

struct VisionOCRService: Sendable {
    /// Koharu's line-region OCR is a bounded supplement to the existing
    /// detector TextRegion budget. It runs only on tight Japanese vertical
    /// candidates; detector bbox OCR remains the owner path and Vision remains
    /// the fallback when the bundled model is unavailable.
    private static let maximumJapaneseMangaLineOCRRequests = 8

    /// A weak page/layout block may still have usable geometry while its first
    /// text read is too short or too non-Japanese to translate safely. Reuse
    /// the existing scoped crop reread for only a small, deterministic number
    /// of such blocks; strong blocks and non-Japanese paths are not reissued.
    private static let maximumJapaneseWeakBlockRecoveryRequests = 4

    /// Read-only runtime evidence for the bounded Japanese pixel-first
    /// supplement. This is intentionally separate from the production OCR
    /// request path so a fixture can show which geometry gates admitted or
    /// rejected a compact candidate before any fusion decision is made.
    static func diagnosticJapanesePixelFirstRegions(
        in image: CGImage
    ) -> [JapanesePixelFirstRegionDiagnostic] {
        detectJapanesePixelFirstVerticalRegions(
            in: image,
            observations: [],
            verticalBlocks: [],
            lineObservations: []
        ).map { region in
            JapanesePixelFirstRegionDiagnostic(
                rect: region.rect,
                detectorRotation: region.detectorRotation,
                characterCount: region.characterCount,
                isCompactCandidate: isJapanesePixelFirstCompactCandidate(
                    region.rect,
                    characterCount: region.characterCount
                )
            )
        }
    }

    /// Run both bounded Vision crop orientations for compact candidates without
    /// entering page fusion. This keeps the orientation/content decision
    /// inspectable before a production gate is tightened further.
    static func diagnosticJapaneseCompactCropReads(
        in image: CGImage
    ) -> [JapaneseCompactCropReadDiagnostic] {
        let regions = detectJapanesePixelFirstVerticalRegions(
            in: image,
            observations: [],
            verticalBlocks: [],
            lineObservations: []
        ).filter {
            isJapanesePixelFirstCompactCandidate(
                $0.rect,
                characterCount: $0.characterCount
            )
        }.prefix(4)
        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        var reads: [JapaneseCompactCropReadDiagnostic] = []
        for candidate in regions {
            let cropRect = expandedVerticalLineCropRect(
                candidate.rect,
                imageSize: imageSize
            )
            guard let crop = cropImage(image, normalizedRect: cropRect) else { continue }
            let prepared = prepareJapaneseCropForVision(crop.image)
            for angle in [270, 90] {
                let observations = recognizeJapaneseCropPass(
                    crop: prepared.image,
                    cropRect: crop.rect,
                    originalImage: image,
                    angle: angle,
                    recognitionLanguages: ["ja-JP", "ja"],
                    minimumTextHeight: 0.002,
                    cropScale: prepared.scale,
                    observationRole: .verticalLine,
                    usesLanguageCorrection: true
                )
                guard let best = bestJapaneseObservation(in: observations) else {
                    continue
                }
                reads.append(
                    JapaneseCompactCropReadDiagnostic(
                        rect: candidate.rect,
                        angle: angle,
                        text: best.text,
                        confidence: best.confidence
                    )
                )
            }
        }
        return reads
    }

    func recognizeTextBlocks(in imageData: Data, sourceLanguage: SupportedLanguage) async throws -> [ImageTranslationBlock] {
        try await recognizeTextBlocksWithShadowLedger(
            in: imageData,
            sourceLanguage: sourceLanguage
        ).blocks
    }

    /// Cloud-only and diagnostic callers can inspect the same candidate
    /// stream without changing the production block API. The existing Store
    /// continues to call `recognizeTextBlocks`, which discards this ledger.
    func recognizeTextBlocksWithShadowLedger(
        in imageData: Data,
        sourceLanguage: SupportedLanguage
    ) async throws -> ImageOCRRecognitionOutput {
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

            var detectorMangaOCRObservations: [VisionOCRObservation] = []
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

                // Koharu recognizes each detector TextRegion with its dedicated
                // Manga OCR model. Run the bundled Core ML port on the same
                // pixel-first regions before Vision crop rereads; if the model
                // cannot load or infer, an empty result leaves every historical
                // Vision fallback available.
                detectorMangaOCRObservations = try await Self.recognizeJapaneseMangaOCR(
                    image: ocrImage
                )
                observations.append(contentsOf: detectorMangaOCRObservations)

                // Koharu crops each detected text node before handing it to the OCR
                // engine. Keep the bounded Vision crop reread after bundled Manga OCR
                // as a recovery path for regions the pixel detector or model misses:
                // crop existing vertical layout nodes, map boxes back, then dedupe.
                let cropRefinedObservations = try await Self.recognizeJapaneseVerticalCrops(
                    in: ocrImage,
                    observations: observations,
                    recognitionLanguages: japaneseVerticalRecognitionLanguages
                )
                observations.append(contentsOf: cropRefinedObservations)
                observations = Self.preferCompactJapaneseCropRecovery(
                    observations,
                    detectorObservations: detectorMangaOCRObservations
                )
                observations = Self.promoteCompactJapaneseHorizontalObservations(
                    observations
                )
            }

            let finalObservations = sourceLanguage == .japanese
                ? Self.deduplicateJapaneseObservations(
                    Self.suppressJapaneseDetectorOwnedPageSupplements(
                        observations,
                        detectorObservations: detectorMangaOCRObservations
                    )
                )
                : Self.deduplicateObservations(observations)
            let layoutObservations = finalObservations.map {
                ImageOCRLayoutObservation(
                    text: $0.text,
                    confidence: $0.confidence,
                    rect: $0.rect,
                    sourceDirectionHint: $0.sourceDirectionHint,
                    preservesDetectorTextRegionBoundary: $0.preservesDetectorTextRegionBoundary,
                    verticalTextRegionOwner: $0.verticalTextRegionOwner,
                    provenance: $0.candidateProvenance
                )
            }
            let allowsVerticalText = sourceLanguage == .japanese || sourceLanguage == .simplifiedChinese
            let laidOutBlocks = { () -> [ImageTranslationBlock] in
                return ImageOCRLayoutEngine.layout(
                    layoutObservations,
                    allowsVerticalText: allowsVerticalText,
                    prefersMangaReadingOrder: sourceLanguage == .japanese
                ).map { block in
                    var imageBlock = ImageTranslationBlock(
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
                        directionReason: block.directionReason,
                        ocrProvenance: block.provenance
                    )
                    if sourceLanguage == .japanese {
                        // Apply the conservative hint after layout; it is
                        // metadata only and never changes OCR geometry/order.
                        imageBlock.textKind = TranslationTextKindClassifier.inferJapaneseKind(
                            text: imageBlock.original,
                            boundingBox: imageBlock.boundingBox
                        )
                    }
                    return imageBlock
                }
            }()
            let blocks = sourceLanguage == .japanese
                ? try await Self.recoverWeakJapaneseBlocks(
                    in: ocrImage,
                    blocks: laidOutBlocks
                )
                : laidOutBlocks
            return ImageOCRRecognitionOutput(
                blocks: blocks,
                shadowLedger: Self.makeShadowLedger(
                    observations: observations,
                    selectedObservations: finalObservations
                )
            )
        }

        return try await task.value
    }

    /// Re-read one existing text node without rerunning page detection, layout,
    /// or the rest of the translation session. Japanese keeps the bundled
    /// Manga OCR crop as the baseline and compares it with the same bounded
    /// Vision crop; other languages use one bounded Vision crop.
    func recognizeTextBlock(
        in imageData: Data,
        sourceLanguage: SupportedLanguage,
        block: ImageTranslationBlock
    ) async throws -> ImageTranslationBlock? {
        let task = Task.detached(priority: .userInitiated) {
            try await Self.recognizeTextBlockDetached(
                imageData: imageData,
                sourceLanguage: sourceLanguage,
                block: block
            )
        }

        return try await task.value
    }

    private static func recognizeTextBlockDetached(
        imageData: Data,
        sourceLanguage: SupportedLanguage,
        block: ImageTranslationBlock
    ) async throws -> ImageTranslationBlock? {
        let image = try Self.makeOCRImage(from: imageData)
        return try await Self.recognizeTextBlockDetached(
            image: image,
            sourceLanguage: sourceLanguage,
            block: block
        )
    }

    private static func recognizeTextBlockDetached(
        image: CGImage,
        sourceLanguage: SupportedLanguage,
        block: ImageTranslationBlock,
        selectionReason: ImageOCRSelectionReason = .scopedRerecognition
    ) async throws -> ImageTranslationBlock? {
        guard let rect = ImageOCRLayoutRect(
            x: block.boundingBox.x,
            y: block.boundingBox.y,
            width: block.boundingBox.width,
            height: block.boundingBox.height
        ).normalizedToUnit() else {
            throw VisionOCRServiceError.blockRecognitionFailed
        }

        // Reuse the same Koharu font-relative envelope as the page-level
        // detector crop. The block's layout rect remains the ownership
        // geometry; padding only makes this scoped reread see the glyphs at
        // the edge of a detector bbox.
        let blockCropRect = sourceLanguage == .japanese
            ? Self.expandedVerticalCropRect(
                rect,
                imageSize: CGSize(width: image.width, height: image.height),
                direction: block.effectiveSourceDirection ?? .vertical
            )
            : rect

        let japanese = sourceLanguage == .japanese
        var mangaCandidate: ImageTranslationBlock?

        if sourceLanguage == .japanese {
            do {
                let cropOrientation: MangaOCRCropOrientation =
                    block.effectiveSourceDirection == .vertical
                        ? .koharuVertical270
                        : .natural
                let request = MangaOCRRequest(
                    textRect: rect,
                    cropRect: blockCropRect,
                    cropOrientation: cropOrientation,
                    regionID: block.ocrProvenance?.candidates.compactMap(\.regionID).first,
                    lineID: block.ocrProvenance?.candidates.compactMap(\.lineID).first
                )
                if let result = try await MangaOCRService.shared
                    .recognize(image: image, requests: [request])
                    .first,
                   let text = Self.cleanRecognizedBlockText(result.text),
                   !text.isEmpty,
                   let confidence = Self.validOCRConfidence(result.confidence),
                   confidence >= 0.55,
                   JapaneseOCRTextNormalizer.containsJapaneseLetter(text),
                   JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5,
                   Self.japaneseScriptDensity(in: text) >= 0.5 {
                    mangaCandidate = Self.recognizedBlock(
                        block,
                        text: text,
                        confidence: confidence,
                        candidateProvenance: ImageOCRCandidateProvenance(
                            engine: .bundledMangaOCR,
                            role: result.lineID == nil ? .detectorTextRegion : .verticalLine,
                            cropVariant: result.cropVariant,
                            geometrySource: result.geometrySource,
                            regionID: result.regionID,
                            lineID: result.lineID,
                            rawConfidence: result.confidence,
                            detectorConfidence: result.detectorConfidence,
                            rotationApplied: koharuPreferredJapaneseVerticalLineOrientation(),
                            verticalTextRegionOwner: result.verticalTextRegionOwner
                        ),
                        selectionReason: selectionReason,
                        reconcileJapaneseTextKind: true
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A missing or incompatible bundled model must not remove
                // the existing block; the crop-level Vision fallback below
                // remains available.
            }
        }

        guard let crop = Self.cropImageForBlock(image, normalizedRect: blockCropRect) else {
            if japanese {
                return mangaCandidate
            }
            throw VisionOCRServiceError.blockRecognitionFailed
        }

        let angles: [Int]
        if japanese {
            // Keep this comparison compatible with the lightweight runtime
            // harness, whose block direction predates the app's optional field.
            if block.effectiveSourceDirection == .vertical {
                angles = [270, 90]
            } else if block.effectiveSourceDirection == .horizontal {
                angles = [0]
            } else {
                angles = [270, 90, 0]
            }
        } else {
            angles = [0]
        }

        var observations: [VisionOCRObservation] = []
        for angle in angles {
            try Task.checkCancellation()
            let orientedCrop: CGImage
            if angle == 0 {
                orientedCrop = crop
            } else {
                guard let rotated = try? Self.rotatedImage(crop, angle: angle) else {
                    continue
                }
                orientedCrop = rotated
            }
            do {
                observations.append(contentsOf: try Self.recognizeObservations(
                    in: orientedCrop,
                    recognitionLanguages: japanese
                        ? ["ja-JP", "ja"]
                        : sourceLanguage.visionRecognitionLanguageIdentifiers,
                    minimumTextHeight: japanese ? 0.006 : 0.01,
                    automaticallyDetectsLanguage: !japanese,
                    rotationApplied: angle,
                    postProcessJapaneseText: japanese,
                    usesLanguageCorrection: !japanese,
                    observationRole: .crop,
                    requiresUsableJapaneseScopedText: japanese
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch let error {
                // A Vision orientation failure must not discard an accepted
                // Manga OCR candidate. Other angles remain bounded and may
                // still provide a comparable candidate.
                if japanese {
                    continue
                }
                throw error
            }
        }

        try Task.checkCancellation()
        let eligibleObservations = japanese
            ? observations.filter {
                Self.isUsableJapaneseScopedText(
                    $0.text,
                    confidence: $0.confidence
                )
            }
            : observations
        guard let best = Self.bestObservation(
            in: eligibleObservations,
            prefersJapanese: japanese
        ),
        let text = Self.cleanRecognizedBlockText(best.text),
        !text.isEmpty else {
            return japanese ? mangaCandidate : nil
        }
        let visionCandidate = Self.recognizedBlock(
            block,
            text: text,
            confidence: best.confidence,
            candidateProvenance: best.candidateProvenance,
            selectionReason: selectionReason,
            reconcileJapaneseTextKind: japanese
        )
        if japanese {
            return Self.selectJapaneseScopedBlockCandidate(
                mangaCandidate: mangaCandidate,
                visionCandidate: visionCandidate
            )
        }
        return visionCandidate
    }

    private static func recognizeObservations(
        in image: CGImage,
        recognitionLanguages: [String],
        minimumTextHeight: Float,
        automaticallyDetectsLanguage: Bool,
        rotationApplied: Int,
        postProcessJapaneseText: Bool = false,
        usesLanguageCorrection: Bool = true,
        observationRole: VisionOCRObservationRole = .page,
        requiresUsableJapaneseScopedText: Bool = false,
        requiresMeaningfulJapaneseRecoveryText: Bool = false
    ) throws -> [VisionOCRObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Keep the historical page-reconnaissance default explicit. Koharu's
        // Manga OCR crop inference decodes directly, so crop callers can opt
        // out of Vision's language rewrite without changing the page path.
        request.usesLanguageCorrection = true
        if !usesLanguageCorrection {
            request.usesLanguageCorrection = false
        }
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
            let candidates = observation.topCandidates(postProcessJapaneseText ? 5 : 1)
            let candidate: VNRecognizedText?
            if requiresUsableJapaneseScopedText {
                candidate = Self.selectJapaneseScopedVisionCandidate(
                    from: candidates
                )
            } else if requiresMeaningfulJapaneseRecoveryText {
                candidate = Self.selectJapaneseRecoveryVisionCandidate(
                    from: candidates
                )
            } else {
                candidate = Self.selectOCRCandidate(
                    from: candidates,
                    japanese: postProcessJapaneseText
                )
            }
            guard let candidate else { return nil }
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

    private static func makeShadowLedger(
        observations: [VisionOCRObservation],
        selectedObservations: [VisionOCRObservation]
    ) -> ImageOCRShadowLedger {
        var selectedKeyCounts: [String: Int] = [:]
        for observation in selectedObservations {
            let key = shadowObservationKey(observation)
            selectedKeyCounts[key, default: 0] += 1
        }
        let ordered = observations.sorted {
            shadowObservationKey($0) < shadowObservationKey($1)
        }
        var candidates: [ImageOCRCandidate] = []
        var selectedIDs: [String] = []
        candidates.reserveCapacity(ordered.count)
        for (index, observation) in ordered.enumerated() {
            let key = shadowObservationKey(observation)
            let isSelected = (selectedKeyCounts[key] ?? 0) > 0
            if isSelected {
                selectedKeyCounts[key, default: 0] -= 1
            }
            let candidateID = "candidate-\(index)"
            candidates.append(
                ImageOCRCandidate(
                    candidateID: candidateID,
                    text: observation.text,
                    confidence: observation.confidence,
                    rect: observation.rect,
                    provenance: observation.candidateProvenance,
                    selectionReason: isSelected
                        ? .selectedByExistingFusion
                        : .shadowOnly
                )
            )
            if isSelected {
                selectedIDs.append(candidateID)
            }
        }
        return ImageOCRShadowLedger(
            candidates: candidates,
            selectedCandidateIDs: selectedIDs
        )
    }

    private static func shadowObservationKey(_ observation: VisionOCRObservation) -> String {
        let rect = observation.rect
        let geometry = [rect.x, rect.y, rect.width, rect.height]
            .map { String(Int(($0 * 100_000).rounded())) }
            .joined(separator: ",")
        let provenance = observation.candidateProvenance
        return [
            observation.text,
            geometry,
            provenance.engine.rawValue,
            provenance.role.rawValue,
            provenance.cropVariant.rawValue,
            provenance.regionID?.rawValue ?? "",
            provenance.lineID?.rawValue ?? "",
            String(provenance.verticalTextRegionOwner ?? -1),
            String(observation.confidence)
        ].joined(separator: "|")
    }

    private static func recognizedBlock(
        _ block: ImageTranslationBlock,
        text: String,
        confidence: Float,
        candidateProvenance: ImageOCRCandidateProvenance,
        selectionReason: ImageOCRSelectionReason = .scopedRerecognition,
        reconcileJapaneseTextKind: Bool = false
    ) -> ImageTranslationBlock {
        var recognized = block
        var retainedProvenance = candidateProvenance
        if retainedProvenance.regionID == nil {
            retainedProvenance.regionID = block.ocrProvenance?.candidates.compactMap(\.regionID).first
        }
        if retainedProvenance.lineID == nil {
            retainedProvenance.lineID = block.ocrProvenance?.candidates.compactMap(\.lineID).first
        }
        recognized.original = text
        recognized.confidence = validOCRConfidence(confidence)
            ?? validOCRConfidence(block.confidence)
            ?? 0
        recognized.ocrProvenance = ImageOCRBlockProvenance.make(
            from: [retainedProvenance],
            selectionReason: selectionReason
        )
        if reconcileJapaneseTextKind {
            // The automatic crop/recovery result may change the text shape
            // after the page-level hint was inferred. Reconcile only the
            // conservative Japanese SFX hint; narration/title/dialogue stay
            // caller-provided and ambiguous text remains nil.
            recognized.textKind = TranslationTextKindClassifier.inferJapaneseKind(
                text: recognized.original,
                boundingBox: recognized.boundingBox
            )
        }
        return recognized
    }

    /// Re-read only weak Japanese blocks after the normal page/layout pass.
    /// This is a product-path recovery for ordinary image OCR: it does not
    /// change detector geometry, block order, translation batching, or any
    /// external/reference artifact policy. A candidate must pass the same
    /// scoped reread quality gates and demonstrate a measurable improvement
    /// before it can replace the existing block text.
    private static func recoverWeakJapaneseBlocks(
        in image: CGImage,
        blocks: [ImageTranslationBlock]
    ) async throws -> [ImageTranslationBlock] {
        let prioritizedCandidates = blocks.enumerated()
            .filter { needsJapaneseWeakBlockRecovery($0.element) }
            .sorted { lhs, rhs in
                let lhsConfidence = validOCRConfidence(lhs.element.confidence)
                    ?? -.infinity
                let rhsConfidence = validOCRConfidence(rhs.element.confidence)
                    ?? -.infinity
                if lhsConfidence != rhsConfidence {
                    return lhsConfidence < rhsConfidence
                }
                return lhs.offset < rhs.offset
            }
            .map { (offset: $0.offset, block: $0.element) }
        let candidates = Self.boundedJapaneseWeakBlockRecoveryCandidates(
            prioritizedCandidates,
            limit: Self.maximumJapaneseWeakBlockRecoveryRequests
        )
        guard !candidates.isEmpty else { return blocks }

        var recovered = blocks
        for candidate in candidates {
            try Task.checkCancellation()
            do {
                guard let reread = try await Self.recognizeTextBlockDetached(
                    image: image,
                    sourceLanguage: .japanese,
                    block: candidate.block,
                    selectionReason: .existingLayoutFusion
                ),
                      Self.isBetterJapaneseWeakBlockRecovery(
                          reread,
                          than: candidate.block
                      ) else {
                    continue
                }
                recovered[candidate.offset] = reread
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A bounded recovery failure must leave the original page
                // block intact; the ordinary OCR result remains usable.
                continue
            }
        }
        return recovered
    }

    /// Keep the existing weak-first ordering, but prevent a long page or a
    /// multi-panel image from spending all four scoped rereads in one vertical
    /// band. Only an over-budget candidate set with more than one populated
    /// band is reselected; the returned candidates retain the original weak
    /// ordering so request sequencing and all under-budget pages remain stable.
    private static func boundedJapaneseWeakBlockRecoveryCandidates(
        _ candidates: [(offset: Int, block: ImageTranslationBlock)],
        limit: Int
    ) -> [(offset: Int, block: ImageTranslationBlock)] {
        guard limit > 0, candidates.count > limit else {
            return candidates
        }

        let bandCount = min(limit, candidates.count)
        var bands = Array(
            repeating: [(offset: Int, block: ImageTranslationBlock)](),
            count: bandCount
        )
        for candidate in candidates {
            let centerY = candidate.block.boundingBox.y
                + candidate.block.boundingBox.height / 2
            let boundedCenterY = centerY.isFinite
                ? min(max(centerY, 0), 1)
                : 0
            let bandIndex = min(
                Int(boundedCenterY * Double(bandCount)),
                bandCount - 1
            )
            bands[bandIndex].append(candidate)
        }

        let populatedBands = bands.indices.filter { !bands[$0].isEmpty }
        guard populatedBands.count > 1 else {
            return Array(candidates.prefix(limit))
        }

        var selectedOffsets = Set<Int>()
        var cursors = Array(repeating: 0, count: bandCount)
        while selectedOffsets.count < limit {
            var addedCandidate = false
            for bandIndex in populatedBands {
                guard selectedOffsets.count < limit,
                      cursors[bandIndex] < bands[bandIndex].count else {
                    continue
                }
                let candidate = bands[bandIndex][cursors[bandIndex]]
                cursors[bandIndex] += 1
                selectedOffsets.insert(candidate.offset)
                addedCandidate = true
            }
            guard addedCandidate else { break }
        }

        return candidates.filter { selectedOffsets.contains($0.offset) }
    }

    private static func needsJapaneseWeakBlockRecovery(
        _ block: ImageTranslationBlock
    ) -> Bool {
        let text = postProcessJapaneseOCRText(block.original)
        guard !text.isEmpty else { return false }
        let direction = block.effectiveSourceDirection
        let directionIsWeak = direction == nil
            || direction == .unknown
            || (block.directionConfidence ?? 1) < 0.45
        let letters = japaneseLetterCountForRecovery(text)
        return validOCRConfidence(block.confidence) == nil
            || block.confidence < 0.60
            || JapaneseOCRTextNormalizer.japaneseLetterDensity(text) < 0.5
            || japaneseScriptDensity(in: text) < 0.5
            || (directionIsWeak && letters <= 3)
            || (direction == .vertical && letters <= 2)
    }

    private static func isJapaneseVerticalBlockAtRisk(
        _ block: ImageOCRLayoutBlock
    ) -> Bool {
        let text = postProcessJapaneseOCRText(block.text)
        let directionIsWeak = block.direction != .vertical
            || !block.directionConfidence.isFinite
            || block.directionConfidence < 0.45
        let letters = japaneseLetterCountForRecovery(text)
        return validOCRConfidence(block.confidence) == nil
            || block.confidence < 0.60
            || text.isEmpty
            || JapaneseOCRTextNormalizer.japaneseLetterDensity(text) < 0.5
            || japaneseScriptDensity(in: text) < 0.5
            || directionIsWeak
            || letters <= 2
    }

    private static func isBetterJapaneseWeakBlockRecovery(
        _ candidate: ImageTranslationBlock,
        than original: ImageTranslationBlock
    ) -> Bool {
        let candidateText = postProcessJapaneseOCRText(candidate.original)
        guard !candidateText.isEmpty,
              validOCRConfidence(candidate.confidence) != nil,
              candidate.confidence >= 0.55,
              JapaneseOCRTextNormalizer.containsJapaneseLetter(candidateText),
              JapaneseOCRTextNormalizer.japaneseLetterDensity(candidateText) >= 0.5,
              japaneseScriptDensity(in: candidateText) >= 0.5 else {
            return false
        }

        let originalText = postProcessJapaneseOCRText(original.original)
        let candidateLetters = japaneseLetterCountForRecovery(candidateText)
        let originalLetters = japaneseLetterCountForRecovery(originalText)
        let originalDensity = japaneseScriptDensity(in: originalText)
        let originalConfidence = validOCRConfidence(original.confidence) ?? 0

        if originalDensity < 0.5,
           candidateLetters >= max(originalLetters, 1) {
            return true
        }
        if candidateLetters > originalLetters,
           candidate.confidence >= max(originalConfidence - 0.02, 0.55) {
            return true
        }
        return candidate.confidence >= max(originalConfidence + 0.04, 0.55)
            && candidateLetters >= max(originalLetters, 1)
    }

    /// Select between the accepted bundled Manga OCR read and the bounded
    /// Vision reread for one existing Japanese block. The bundled model stays
    /// the deterministic baseline: Vision may replace it only when its
    /// accepted Japanese evidence is measurably better. Confidence is a
    /// bounded tie-break within this local comparison, not a cross-engine
    /// calibration claim; equal evidence keeps the Manga OCR result.
    private static func selectJapaneseScopedBlockCandidate(
        mangaCandidate: ImageTranslationBlock?,
        visionCandidate: ImageTranslationBlock?
    ) -> ImageTranslationBlock? {
        guard let mangaCandidate else {
            guard let visionCandidate,
                  isUsableJapaneseScopedBlockCandidate(visionCandidate) else {
                return nil
            }
            return visionCandidate
        }
        guard let visionCandidate else {
            return isUsableJapaneseScopedBlockCandidate(mangaCandidate)
                ? mangaCandidate
                : nil
        }
        guard isUsableJapaneseScopedBlockCandidate(visionCandidate) else {
            return isUsableJapaneseScopedBlockCandidate(mangaCandidate)
                ? mangaCandidate
                : nil
        }
        guard isUsableJapaneseScopedBlockCandidate(mangaCandidate) else {
            return visionCandidate
        }
        return isBetterJapaneseScopedBlockCandidate(
            visionCandidate,
            than: mangaCandidate
        ) ? visionCandidate : mangaCandidate
    }

    private static func isUsableJapaneseScopedBlockCandidate(
        _ candidate: ImageTranslationBlock
    ) -> Bool {
        isUsableJapaneseScopedText(
            candidate.original,
            confidence: candidate.confidence
        )
    }

    private static func isUsableJapaneseScopedText(
        _ sourceText: String,
        confidence: Float
    ) -> Bool {
        let text = postProcessJapaneseOCRText(sourceText)
        return !text.isEmpty
            && validOCRConfidence(confidence) != nil
            && confidence >= 0.55
            && JapaneseOCRTextNormalizer.containsJapaneseLetter(text)
            && JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5
            && japaneseScriptDensity(in: text) >= 0.5
    }

    private static func isBetterJapaneseScopedBlockCandidate(
        _ candidate: ImageTranslationBlock,
        than incumbent: ImageTranslationBlock
    ) -> Bool {
        guard isUsableJapaneseScopedBlockCandidate(candidate),
              isUsableJapaneseScopedBlockCandidate(incumbent) else {
            return false
        }

        let candidateText = postProcessJapaneseOCRText(candidate.original)
        let incumbentText = postProcessJapaneseOCRText(incumbent.original)
        let candidateLetters = japaneseLetterCountForRecovery(candidateText)
        let incumbentLetters = japaneseLetterCountForRecovery(incumbentText)
        let candidateDensity = japaneseScriptDensity(in: candidateText)
        let incumbentDensity = japaneseScriptDensity(in: incumbentText)

        if candidateLetters > incumbentLetters,
           candidate.confidence >= max(incumbent.confidence - 0.04, 0.55) {
            return true
        }
        if candidateDensity > incumbentDensity + 0.05,
           candidate.confidence >= max(incumbent.confidence - 0.02, 0.55) {
            return true
        }
        return candidateLetters == incumbentLetters
            && candidate.confidence >= incumbent.confidence + 0.04
    }

    private static func cleanRecognizedBlockText(_ text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func cropImageForBlock(
        _ image: CGImage,
        normalizedRect: ImageOCRLayoutRect
    ) -> CGImage? {
        guard let rect = normalizedRect.normalizedToUnit() else { return nil }
        let bounds = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
        let pixels = CGRect(
            x: rect.x * bounds.width,
            y: rect.y * bounds.height,
            width: rect.width * bounds.width,
            height: rect.height * bounds.height
        )
        .integral
        .intersection(bounds)
        guard pixels.width >= 2, pixels.height >= 2 else { return nil }
        return image.cropping(to: pixels)
    }

    /// Mirrors Koharu Manga OCR's post-processing boundary for Japanese text.
    /// Vision's candidate string is still the source of geometry; this only
    /// removes recognition formatting noise before layout, dedupe, and translation.
    private static func postProcessJapaneseOCRText(_ text: String) -> String {
        let canonicalText = JapaneseOCRTextNormalizer.canonicalized(text)
        if let mixedScriptCandidate = JapaneseOCRTextNormalizer.mixedScriptCandidate(text) {
            return mixedScriptCandidate
        }
        let withoutWhitespace = canonicalText.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "…", with: "...")

        // Keep the two-stage boundary explicit: collapse true dot runs first,
        // then apply halfwidth-to-fullwidth conversion to the collapsed
        // result. Japanese middle dots are separators, not periods, so they
        // remain U+30FB in the final OCR text.
        var collapsed = ""
        var dotCount = 0
        func flushDots() {
            guard dotCount > 0 else { return }
            collapsed.append(contentsOf: String(repeating: ".", count: dotCount))
            dotCount = 0
        }

        for scalar in withoutWhitespace.unicodeScalars {
            switch scalar.value {
            case 0x2E, 0xFF0E:
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

    private static func validOCRConfidence(_ confidence: Float) -> Float? {
        guard confidence.isFinite, (0...1).contains(confidence) else {
            return nil
        }
        return confidence
    }

    private static func selectOCRCandidate(
        from candidates: [VNRecognizedText],
        japanese: Bool
    ) -> VNRecognizedText? {
        guard japanese else { return candidates.first }
        let validCandidates = candidates.filter {
            validOCRConfidence($0.confidence) != nil
        }
        guard let bestConfidence = validCandidates.map(\.confidence).max() else {
            return nil
        }

        // Keep alternatives close to Vision's best score, then prefer the
        // Japanese-script candidate. This avoids replacing a strong result with
        // a speculative alternative while recovering common vertical glyph
        // substitutions that Vision reports just below top-1.
        let confidenceWindow = validCandidates.filter {
            $0.confidence >= bestConfidence - 0.14
        }
        // Vision can return a high-confidence punctuation or symbol-only
        // alternative for a glyph row whose nearby candidate contains actual
        // Japanese letters. Prefer letter-bearing content within the same
        // bounded confidence window so punctuation cannot replace a usable
        // OCR word; retain the old window when no letter-bearing candidate
        // exists because punctuation-only Japanese text is still valid input.
        let letterBearingCandidates = confidenceWindow.filter {
            japaneseLetterCountForRecovery(postProcessJapaneseOCRText($0.string)) > 0
        }
        let candidatesToScore = letterBearingCandidates.isEmpty
            ? confidenceWindow
            : letterBearingCandidates
        return candidatesToScore
            .max { lhs, rhs in
                japaneseCandidateScore(lhs) < japaneseCandidateScore(rhs)
            }
    }

    /// A scoped reread replaces an existing block, so punctuation-only,
    /// low-confidence, out-of-domain, or low-density alternatives cannot mask a
    /// usable nearby Vision candidate. Page OCR keeps its historical fallback
    /// because punctuation-only Japanese is still valid page content.
    private static func selectJapaneseScopedVisionCandidate(
        from candidates: [VNRecognizedText]
    ) -> VNRecognizedText? {
        let usableCandidates = candidates.filter { candidate in
            isUsableJapaneseScopedText(
                candidate.string,
                confidence: candidate.confidence
            )
        }
        return selectOCRCandidate(from: usableCandidates, japanese: true)
    }

    /// Ordinary Japanese crop recovery keeps each caller's existing confidence
    /// policy, but punctuation-only or low-density alternatives cannot mask a
    /// lower-scored candidate that contains meaningful Japanese writing. Page
    /// OCR does not opt into this filter, so punctuation-only page content keeps
    /// the historical fallback in `selectOCRCandidate`.
    private static func selectJapaneseRecoveryVisionCandidate(
        from candidates: [VNRecognizedText]
    ) -> VNRecognizedText? {
        let meaningfulCandidates = candidates.filter { candidate in
            isMeaningfulJapaneseRecoveryText(candidate.string)
        }
        return selectOCRCandidate(from: meaningfulCandidates, japanese: true)
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
        let hasMixedJapaneseAndASCII = JapaneseOCRTextNormalizer.hasMixedJapaneseAndASCII(candidate.string)
        // Keep confidence as the dominant signal, but do not let the old
        // pure-Japanese density preference discard a high-confidence English
        // token/model-name candidate. The bonus is deliberately bounded and
        // only applies when both Japanese script and ASCII word characters
        // are present.
        let mixedScriptFidelityBonus = hasMixedJapaneseAndASCII ? 0.12 : 0
        return confidence * 0.82
            + scriptDensity * 0.14
            + punctuationDensity * 0.04
            + mixedScriptFidelityBonus
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
    ) async throws -> [VisionOCRObservation] {
        let safeObservations = deduplicateJapaneseObservations(observations)
        let layoutObservations = safeObservations.map {
            ImageOCRLayoutObservation(
                text: $0.text,
                confidence: $0.confidence,
                rect: $0.rect,
                sourceDirectionHint: $0.sourceDirectionHint,
                preservesDetectorTextRegionBoundary: $0.preservesDetectorTextRegionBoundary,
                verticalTextRegionOwner: $0.verticalTextRegionOwner,
                provenance: $0.candidateProvenance
            )
        }
        let prioritizedVerticalBlocks = ImageOCRLayoutEngine.layout(
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
            let lhsAtRisk = isJapaneseVerticalBlockAtRisk(lhs)
            let rhsAtRisk = isJapaneseVerticalBlockAtRisk(rhs)
            if lhsAtRisk != rhsAtRisk {
                // The following prefix is the bounded block-crop budget. Give
                // blocks whose first read is weak or directionally uncertain a
                // chance to use that budget before spending it on strong
                // blocks that are less likely to need a wider reread.
                return lhsAtRisk && !rhsAtRisk
            }
            let lhsConfidence = validOCRConfidence(lhs.confidence) ?? -.infinity
            let rhsConfidence = validOCRConfidence(rhs.confidence) ?? -.infinity
            if lhsConfidence != rhsConfidence {
                // Within the same risk class, recover the weakest finite read
                // first. This keeps the selection deterministic and makes the
                // bounded crop queue agree with weak-block recovery priority.
                return lhsConfidence < rhsConfidence
            }
            let lhsDirectionConfidence = lhs.directionConfidence.isFinite
                ? lhs.directionConfidence
                : -.infinity
            let rhsDirectionConfidence = rhs.directionConfidence.isFinite
                ? rhs.directionConfidence
                : -.infinity
            if lhsDirectionConfidence != rhsDirectionConfidence {
                return lhsDirectionConfidence < rhsDirectionConfidence
            }
            if lhs.rect.height != rhs.rect.height {
                return lhs.rect.height > rhs.rect.height
            }
            return lhs.text < rhs.text
        }
        let verticalBlocks = Self.boundedJapaneseVerticalCropBlocks(
            prioritizedVerticalBlocks,
            limit: 16
        )
        .prefix(16)
        .enumerated()
        .map { index, block in
            var owned = block
            owned.verticalTextRegionOwner = index
            return owned
        }

        let verticalBlockArray = Array(verticalBlocks)
        let ownerAnnotatedObservations = annotateJapaneseVerticalTextRegionOwners(
            safeObservations,
            blocks: verticalBlockArray
        )
        var refined: [VisionOCRObservation] = []
        refined.reserveCapacity(verticalBlockArray.count * 2 + 12)

        // Koharu's extract_text_block_regions is line-first: once a TextRegion
        // has usable line polygons, it sends those regions to OCR before any
        // wider detector or block crop fallback. Vision does not expose those polygons,
        // so the mapped line observations are our bounded equivalent.
        // Run this path first and let later reconnaissance consume only gaps
        // that were not reliably covered by a line reread.
        let lineRefined = try await Self.recognizeJapaneseVerticalLineCrops(
            in: image,
            observations: ownerAnnotatedObservations,
            blocks: verticalBlockArray,
            recognitionLanguages: recognitionLanguages
        )
        refined.append(contentsOf: lineRefined)

        let pixelFirstRefined = Self.recognizeJapanesePixelFirstVerticalCrops(
            in: image,
            observations: ownerAnnotatedObservations,
            verticalBlocks: verticalBlockArray,
            lineObservations: lineRefined,
            recognitionLanguages: recognitionLanguages
        )
        refined.append(contentsOf: pixelFirstRefined)

        // A successful pixel-first crop is already a reliable vertical-line
        // observation after the shared recovery gate. Feed it into the same
        // read-only frontier used by the tile fallback so a broad tile does
        // not spend one of the existing 18 windows rereading an area that the
        // narrower detector crop has just covered. Weak/empty pixel-first
        // output is absent from this array and therefore cannot suppress the
        // broader recovery path.
        let recoveryFrontierObservations = lineRefined + pixelFirstRefined
        refined.append(contentsOf: Self.recognizeJapaneseVerticalTileFallback(
            in: image,
            verticalBlocks: verticalBlockArray,
            lineObservations: recoveryFrontierObservations,
            recognitionLanguages: recognitionLanguages
        ))

        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        var orientationFallbacksRemaining = 8
        for block in verticalBlocks {
            let hasCompleteLineCoverage = Self.hasCompleteJapaneseLineCoverage(
                for: block,
                sourceObservations: ownerAnnotatedObservations,
                lineRefined: lineRefined
            )
            let hasLineOCRResult = lineRefined.contains { observation in
                japaneseObservation(observation, belongsTo: block)
                    && overlapRatio(observation.rect, block.rect) >= 0.25
                    && japaneseLineRegionOverlapsBlock(observation, block: block)
            } && hasCompleteLineCoverage
            guard !hasLineOCRResult else { continue }

            let angle = ownerAnnotatedObservations
                .filter {
                    japaneseObservation($0, belongsTo: block)
                        && overlapRatio($0.rect, block.rect) >= 0.25
                }
                .sorted { isBetterJapaneseObservation($0, $1) }
                .first
                .map { $0.rotationApplied == 270 ? 270 : 90 }
                ?? 90
            guard let crop = cropImage(
                image,
                normalizedRect: koharuVerticalBlockCropRect(
                    block,
                    observations: ownerAnnotatedObservations,
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
                cropScale: preparedCrop.scale,
                verticalTextRegionOwner: block.verticalTextRegionOwner
            )
            let meaningfulPrimary = meaningfulJapaneseRecoveryObservations(
                primary
            )
            var blockFallback = meaningfulPrimary

            // A block can be laid out correctly while its first crop orientation
            // is still reversed. Retry only weak/empty crops and keep a strict
            // page-level budget so dense manga pages do not double their OCR cost.
            if orientationFallbacksRemaining > 0,
               needsJapaneseOrientationFallback(meaningfulPrimary) {
                orientationFallbacksRemaining -= 1
                let opposite = recognizeJapaneseCropPass(
                    crop: preparedCrop.image,
                    cropRect: crop.rect,
                    originalImage: image,
                    angle: oppositeJapaneseOrientation(angle),
                    recognitionLanguages: recognitionLanguages,
                    minimumTextHeight: 0.004,
                    cropScale: preparedCrop.scale,
                    verticalTextRegionOwner: block.verticalTextRegionOwner
                )
                blockFallback.append(
                    contentsOf: meaningfulJapaneseRecoveryObservations(opposite)
                )
            }
            blockFallback = deduplicateJapaneseObservations(blockFallback)

            // Koharu emits one prediction per TextRegion. If incomplete line
            // coverage required this wider crop, replace the owner's partial
            // line fragments only when the fallback set itself proves complete,
            // one-to-one source-line coverage for that exact owner. Otherwise
            // owner-first layout would concatenate partial text with a complete
            // fallback, while a merely strong fragment must not erase good lines.
            let fallbackHasCompleteLineCoverage = Self.hasCompleteJapaneseLineCoverage(
                for: block,
                sourceObservations: ownerAnnotatedObservations,
                lineRefined: blockFallback,
                allowsBlockCropResults: true
            )
            if ImageOCRLayoutEngine.blockFallbackCanReplacePartialLines(
                fallbackOwners: blockFallback.map(\.verticalTextRegionOwner),
                blockOwner: block.verticalTextRegionOwner,
                hasCompleteLineCoverage: fallbackHasCompleteLineCoverage
            ),
               let blockOwner = block.verticalTextRegionOwner {
                refined.removeAll {
                    $0.observationRole == .verticalLine
                        && $0.verticalTextRegionOwner == blockOwner
                }
            }
            refined.append(contentsOf: blockFallback)
        }

        return refined
    }

    /// Preserve the v3.336 risk-first block queue while preventing a long
    /// page's first 16 risky blocks from all occupying one vertical band.
    /// Only an over-budget, multi-band queue is reselected; the result returns
    /// to the original risk order so block ownership and downstream fusion do
    /// not observe the scheduling pass.
    private static func boundedJapaneseVerticalCropBlocks(
        _ blocks: [ImageOCRLayoutBlock],
        limit: Int
    ) -> [ImageOCRLayoutBlock] {
        guard limit > 0, blocks.count > limit else { return blocks }

        let bandCount = min(limit, blocks.count)
        var bands = Array(repeating: [Int](), count: bandCount)
        for (offset, block) in blocks.enumerated() {
            let centerY = block.rect.y + block.rect.height / 2
            let boundedCenterY = centerY.isFinite
                ? min(max(centerY, 0), 1)
                : 0
            let bandIndex = min(
                Int(boundedCenterY * Double(bandCount)),
                bandCount - 1
            )
            bands[bandIndex].append(offset)
        }

        let populatedBands = bands.indices.filter { !bands[$0].isEmpty }
        guard populatedBands.count > 1 else {
            return Array(blocks.prefix(limit))
        }

        var selectedOffsets = Set<Int>()
        var cursors = Array(repeating: 0, count: bandCount)
        while selectedOffsets.count < limit {
            var addedCandidate = false
            for bandIndex in populatedBands {
                guard selectedOffsets.count < limit,
                      cursors[bandIndex] < bands[bandIndex].count else {
                    continue
                }
                let offset = bands[bandIndex][cursors[bandIndex]]
                cursors[bandIndex] += 1
                selectedOffsets.insert(offset)
                addedCandidate = true
            }
            guard addedCandidate else { break }
        }

        return blocks.enumerated()
            .filter { selectedOffsets.contains($0.offset) }
            .map(\.element)
    }

    private static func recognizeJapaneseMangaOCR(
        image: CGImage
    ) async throws -> [VisionOCRObservation] {
        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        let detectorSliceCount = ComicTextBubbleDetectorService.inferenceWindowCount(
            for: image
        )
        let detectorRegions: [ComicTextDetectorRegion]
        do {
            detectorRegions = try await ComicTextBubbleDetectorService.shared.detectTextRegions(
                in: image
            )
        } catch is CancellationError {
            // A cancelled detector pass must cancel the whole bounded OCR run;
            // it is not equivalent to a model load or inference failure.
            throw CancellationError()
        } catch {
            // Preserve the historical Vision fallback for ordinary detector
            // failures, but do not let a concurrent cancellation be hidden by
            // an underlying Core ML error.
            try Task.checkCancellation()
            detectorRegions = []
        }
        let visionRegions = alignPartialJapaneseMangaOCRColumns(
            detectJapanesePixelFirstVerticalRegions(
                in: image,
                observations: [],
                verticalBlocks: [],
                lineObservations: []
            )
        )
        let regions = japaneseMangaOCRRegions(
            detectorRegions: detectorRegions,
            visionRegions: visionRegions
        )
        let selectedRegions = detectorSliceCount > 1
            ? japaneseLongPageMangaOCRRegions(
                regions,
                detectorSliceCount: detectorSliceCount
            )
            : Array(regions.prefix(12))
        let cropRegions = detectorSliceCount > 1 ? regions : selectedRegions
        let requests = selectedRegions.map { region in
            MangaOCRRequest(
                textRect: region.rect,
                cropRect: japaneseMangaOCRCropRect(
                    region,
                    among: cropRegions,
                    imageSize: imageSize
                ),
                detectorConfidence: Self.detectorConfidenceForMangaOCR(
                    region
                ),
                cropQuad: region.cropQuadHint,
                cropQuadIsVertical: region.cropQuadHint != nil,
                regionID: region.regionID
            )
        }
        guard !requests.isEmpty else {
            return []
        }
        let results: [MangaOCRResult]
        do {
            results = try await MangaOCRService.shared.recognize(
                image: image,
                requests: requests
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Model loading remains an all-or-nothing fallback to Vision OCR.
            return []
        }
        return results.map { result in
            return VisionOCRObservation(
                text: result.text,
                confidence: result.confidence,
                rect: result.textRect,
                lineRegionRect: result.textRect,
                lineRegionQuad: nil,
                rotationApplied: koharuPreferredJapaneseVerticalLineOrientation(),
                // The bundled RT-DETR output has no Koharu `source_direction`
                // field. Keep the proven Japanese vertical hint for this
                // dedicated path; the separate detector role below prevents
                // ownership from being confused with Vision line provenance.
                sourceDirectionHint: .vertical,
                observationRole: .detectorTextRegion,
                preservesDetectorTextRegionBoundary:
                    Self.isReliableJapaneseMangaOCRResult(result),
                provenance: ImageOCRCandidateProvenance(
                    engine: .bundledMangaOCR,
                    role: result.lineID == nil ? .detectorTextRegion : .verticalLine,
                    cropVariant: result.cropVariant,
                    geometrySource: result.geometrySource,
                    regionID: result.regionID,
                    lineID: result.lineID,
                    rawConfidence: result.confidence,
                    detectorConfidence: result.detectorConfidence,
                    rotationApplied: koharuPreferredJapaneseVerticalLineOrientation(),
                    verticalTextRegionOwner: result.verticalTextRegionOwner
                )
            )
        }
    }

    /// A detector TextRegion becomes a protected Koharu owner only when the
    /// bundled OCR result has enough Japanese evidence to be trusted over a
    /// page-level Vision fallback. Keep weaker text as a normal candidate so
    /// it can still help when no fallback exists, but do not let it suppress
    /// or permanently merge a stronger observation.
    private static func isReliableJapaneseMangaOCRResult(
        _ result: MangaOCRResult
    ) -> Bool {
        guard let confidence = validOCRConfidence(result.confidence),
              confidence >= 0.55,
              JapaneseOCRTextNormalizer.containsJapaneseLetter(result.text),
              JapaneseOCRTextNormalizer.japaneseLetterDensity(result.text) >= 0.5,
              japaneseScriptDensity(in: result.text) >= 0.5 else {
            return false
        }
        if let detectorConfidence = result.detectorConfidence {
            guard let detectorScore = validOCRConfidence(detectorConfidence),
                  detectorScore >= 0.55 else {
                return false
            }
        }
        return true
    }

    /// Only RT-DETR-owned requests carry a detector score. Vision supplemental
    /// regions remain eligible for the existing model/content gate, but can
    /// never accidentally claim a detector-owner boundary from a synthetic
    /// zero default.
    private static func detectorConfidenceForMangaOCR(
        _ region: JapanesePixelFirstRegion
    ) -> Float? {
        guard case .comicTextBubble = region.detector else { return nil }
        return region.detectorConfidence
    }

    /// Koharu's RT-DETR TextRegions are the primary Manga OCR geometry. Vision's
    /// rotated text rectangles remain a bounded supplement only when a candidate
    /// is not already covered by a dedicated detector region. If the bundled
    /// detector cannot load or infer, an empty primary list preserves the full
    /// historical Vision request budget and behavior.
    private static func japaneseMangaOCRRegions(
        detectorRegions: [ComicTextDetectorRegion],
        visionRegions: [JapanesePixelFirstRegion]
    ) -> [JapanesePixelFirstRegion] {
        let primary = detectorRegions.compactMap {
            detectorRegion -> JapanesePixelFirstRegion? in
            guard let detectorConfidence = validOCRConfidence(
                detectorRegion.confidence
            ) else {
                return nil
            }
            return JapanesePixelFirstRegion(
                rect: detectorRegion.rect,
                detectorRotation: 0,
                characterCount: 0,
                detector: .comicTextBubble,
                detectorConfidence: detectorConfidence,
                regionID: detectorRegion.regionID,
                cropRectHint: japaneseDetectorCropHint(
                    detectorRegion.rect,
                    from: visionRegions
                ),
                cropQuadHint: japaneseDetectorCropQuadHint(
                    detectorRegion.rect,
                    from: visionRegions
                )
            )
        }
        let supplemental = visionRegions.filter { candidate in
            !primary.contains {
                overlapRatio($0.rect, candidate.rect) >= 0.60
                    || intersectionOverUnion($0.rect, candidate.rect) >= 0.50
            }
        }
        return primary + supplemental
    }

    /// A detector TextRegion is the stable layout owner, but its bbox can be
    /// wider than the actual Japanese column. Vision character envelopes are
    /// useful as a Koharu `line_polygon` proxy only when they cover nearly all
    /// of the detector region and retain enough vertical context. The hint is
    /// crop-only; the detector rect remains the text/layout geometry.
    private static func japaneseDetectorCropHint(
        _ detectorRect: ImageOCRLayoutRect,
        from visionRegions: [JapanesePixelFirstRegion]
    ) -> ImageOCRLayoutRect? {
        let candidates = visionRegions.filter { candidate in
            guard case .vision = candidate.detector,
                  candidate.characterCount >= 2,
                  let rect = candidate.rect.normalizedToUnit(),
                  isJapanesePixelFirstVerticalCandidate(rect) else {
                return false
            }
            let detectorArea = max(detectorRect.width * detectorRect.height, 0.0001)
            let candidateArea = rect.width * rect.height
            let overlap = overlapRatio(detectorRect, rect)
            let intersection = intersectionArea(detectorRect, rect)
            let detectorCoverage = intersection / detectorArea
            let candidateCoverage = intersection / max(candidateArea, 0.0001)
            let areaRatio = candidateArea / detectorArea
            let horizontalCoverage = min(
                detectorRect.maxX,
                rect.maxX
            ) - max(detectorRect.x, rect.x)
            let verticalCoverage = min(
                detectorRect.maxY,
                rect.maxY
            ) - max(detectorRect.y, rect.y)
            return overlap >= 0.80
                && detectorCoverage >= 0.55
                && candidateCoverage >= 0.80
                && areaRatio >= 0.35
                && areaRatio <= 1.05
                && horizontalCoverage / max(detectorRect.width, 0.001) >= 0.45
                && verticalCoverage / max(detectorRect.height, 0.001) >= 0.85
                && rect.width < detectorRect.width * 0.90
        }
        return candidates.min { lhs, rhs in
            let lhsWidth = lhs.rect.width
            let rhsWidth = rhs.rect.width
            if lhsWidth != rhsWidth { return lhsWidth < rhsWidth }
            if lhs.characterCount != rhs.characterCount {
                return lhs.characterCount > rhs.characterCount
            }
            return lhs.rect.x > rhs.rect.x
        }?.rect
    }

    /// Carry the same strictly gated Vision candidate into the optional
    /// Koharu line-polygon path. The existing crop-rectangle helper remains the
    /// single authority for coverage/ownership gates; this only retrieves the
    /// quad attached to that already-approved candidate.
    private static func japaneseDetectorCropQuadHint(
        _ detectorRect: ImageOCRLayoutRect,
        from visionRegions: [JapanesePixelFirstRegion]
    ) -> ImageOCRLayoutQuad? {
        guard let rectHint = japaneseDetectorCropHint(
            detectorRect,
            from: visionRegions
        ) else {
            return nil
        }
        return visionRegions
            .filter { candidate in
                guard candidate.cropQuadHint != nil else { return false }
                let rect = candidate.rect
                return overlapRatio(rect, rectHint) >= 0.98
                    && abs(rect.width - rectHint.width) <= 0.002
                    && abs(rect.height - rectHint.height) <= 0.002
            }
            .min { lhs, rhs in
                if lhs.characterCount != rhs.characterCount {
                    return lhs.characterCount > rhs.characterCount
                }
                return lhs.rect.x > rhs.rect.x
            }?.cropQuadHint?.normalized()
    }

    /// Koharu sends every detector TextRegion to Manga OCR. The iOS port keeps
    /// CPU work bounded, but scales the historical 12-request budget with the
    /// detector's actual long-page windows and distributes capped work across
    /// the full page so confidence-heavy upper slices cannot starve the tail.
    private static func japaneseLongPageMangaOCRRegions(
        _ regions: [JapanesePixelFirstRegion],
        detectorSliceCount: Int
    ) -> [JapanesePixelFirstRegion] {
        let requestsPerSlice = 12
        let maximumRequests = 48
        let requestLimit = min(
            maximumRequests,
            max(detectorSliceCount, 1) * requestsPerSlice
        )
        let bandCount = min(max(detectorSliceCount, 1), requestLimit)
        let primary = regions.filter {
            guard case .comicTextBubble = $0.detector else { return false }
            return validOCRConfidence($0.detectorConfidence) != nil
        }
        var selected = verticallyBalancedJapaneseMangaOCRRegions(
            primary,
            bandCount: bandCount,
            limit: requestLimit
        )
        let remaining = requestLimit - selected.count
        if remaining > 0 {
            let supplemental = regions.filter {
                if case .vision = $0.detector { return true }
                return false
            }
            selected.append(contentsOf: verticallyBalancedJapaneseMangaOCRRegions(
                supplemental,
                bandCount: bandCount,
                limit: remaining
            ))
        }
        return selected
    }

    private static func verticallyBalancedJapaneseMangaOCRRegions(
        _ regions: [JapanesePixelFirstRegion],
        bandCount: Int,
        limit: Int
    ) -> [JapanesePixelFirstRegion] {
        guard limit > 0, !regions.isEmpty else { return [] }
        guard regions.count > limit else { return regions }

        let boundedBandCount = min(max(bandCount, 1), limit)
        var bands = Array(
            repeating: [JapanesePixelFirstRegion](),
            count: boundedBandCount
        )
        for region in regions {
            let normalizedCenter = min(max(region.rect.midY, 0), 1)
            let bandIndex = min(
                Int(normalizedCenter * Double(boundedBandCount)),
                boundedBandCount - 1
            )
            bands[bandIndex].append(region)
        }

        let baseQuota = limit / boundedBandCount
        let extraQuota = limit % boundedBandCount
        var selected: [JapanesePixelFirstRegion] = []
        var overflow: [JapanesePixelFirstRegion] = []
        selected.reserveCapacity(limit)
        for (index, band) in bands.enumerated() {
            let quota = baseQuota + (index < extraQuota ? 1 : 0)
            selected.append(contentsOf: band.prefix(quota))
            overflow.append(contentsOf: band.dropFirst(quota))
        }
        if selected.count < limit {
            overflow.sort(by: isBetterJapaneseMangaOCRRegion)
            selected.append(contentsOf: overflow.prefix(limit - selected.count))
        }
        return selected
    }

    private static func isBetterJapaneseMangaOCRRegion(
        _ lhs: JapanesePixelFirstRegion,
        _ rhs: JapanesePixelFirstRegion
    ) -> Bool {
        let lhsDetectorConfidence = validOCRConfidence(lhs.detectorConfidence)
        let rhsDetectorConfidence = validOCRConfidence(rhs.detectorConfidence)
        if (lhsDetectorConfidence != nil) != (rhsDetectorConfidence != nil) {
            return lhsDetectorConfidence != nil
        }
        if let lhsDetectorConfidence,
           let rhsDetectorConfidence,
           lhsDetectorConfidence != rhsDetectorConfidence {
            return lhsDetectorConfidence > rhsDetectorConfidence
        }
        if lhs.rect.y != rhs.rect.y { return lhs.rect.y < rhs.rect.y }
        if lhs.rect.x != rhs.rect.x { return lhs.rect.x > rhs.rect.x }
        if lhs.rect.height != rhs.rect.height { return lhs.rect.height > rhs.rect.height }
        return lhs.rect.width < rhs.rect.width
    }

    /// Recovery observations may enter final fusion/layout only when their
    /// cleaned text contains meaningful Japanese writing.  Keep this shared by
    /// pixel-first and tile reconnaissance so punctuation-heavy crop output is
    /// treated as a miss and the existing opposite/block fallback can continue.
    private static func meaningfulJapaneseRecoveryObservations(
        _ observations: [VisionOCRObservation]
    ) -> [VisionOCRObservation] {
        observations.filter { observation in
            isMeaningfulJapaneseRecoveryText(observation.text)
        }
    }

    private static func isMeaningfulJapaneseRecoveryText(
        _ sourceText: String
    ) -> Bool {
        let text = postProcessJapaneseOCRText(sourceText)
        return !text.isEmpty
            && JapaneseOCRTextNormalizer.containsJapaneseLetter(text)
            && JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5
            && japaneseScriptDensity(in: text) >= 0.5
    }

    /// Use Vision's pixel-first text rectangle detector as a bounded recovery
    /// path for dedicated TextRegions that fail or miss a region. The detector
    /// contributes geometry only; recognition still runs through the existing
    /// Japanese crop helper.
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
            let isCompactCandidate = isJapanesePixelFirstCompactCandidate(
                candidate.rect,
                characterCount: candidate.characterCount
            )
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
                observationRole: .verticalLine,
                preservesDetectorTextRegionBoundary: isCompactCandidate,
                isCompactJapaneseRecovery: isCompactCandidate,
                usesLanguageCorrection: isCompactCandidate
            )
            let meaningfulPrimary = meaningfulJapaneseRecoveryObservations(
                primary
            )
            refined.append(contentsOf: meaningfulPrimary)

            if orientationFallbacksRemaining > 0,
               (isCompactCandidate
                    || needsJapaneseOrientationFallback(meaningfulPrimary)) {
                orientationFallbacksRemaining -= 1
                let opposite = recognizeJapaneseCropPass(
                    crop: preparedCrop.image,
                    cropRect: crop.rect,
                    originalImage: image,
                    angle: oppositeJapaneseOrientation(
                        koharuPreferredJapaneseVerticalLineOrientation()
                    ),
                    recognitionLanguages: recognitionLanguages,
                    minimumTextHeight: 0.002,
                    cropScale: preparedCrop.scale,
                    observationRole: .verticalLine,
                    preservesDetectorTextRegionBoundary: isCompactCandidate,
                    isCompactJapaneseRecovery: isCompactCandidate,
                    usesLanguageCorrection: isCompactCandidate
                )
                refined.append(
                    contentsOf: meaningfulJapaneseRecoveryObservations(opposite)
                )
            }
        }

        return deduplicateJapaneseCompactRecoveryObservations(
            deduplicateJapaneseObservations(refined)
        )
    }

    private static func deduplicateJapaneseCompactRecoveryObservations(
        _ observations: [VisionOCRObservation]
    ) -> [VisionOCRObservation] {
        var output: [VisionOCRObservation] = []
        for observation in observations {
            guard observation.isCompactJapaneseRecovery else {
                output.append(observation)
                continue
            }
            let duplicateIndex = output.firstIndex { existing in
                existing.isCompactJapaneseRecovery
                    && verticalTextRegionOwnersCompatible(existing, observation)
                    && overlapRatio(
                        existing.lineRegionRect ?? existing.rect,
                        observation.lineRegionRect ?? observation.rect
                    ) >= 0.45
            }
            guard let duplicateIndex else {
                output.append(observation)
                continue
            }
            let inheritedOwner = observation.verticalTextRegionOwner
                ?? output[duplicateIndex].verticalTextRegionOwner
            if isBetterCompactJapaneseRecovery(
                observation,
                than: output[duplicateIndex]
            ) {
                var winner = observation
                winner.verticalTextRegionOwner = inheritedOwner
                output[duplicateIndex] = winner
            } else {
                output[duplicateIndex].verticalTextRegionOwner = inheritedOwner
            }
        }
        return output
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
            // A detector-owned compact result below the reliability ceiling is
            // exactly the case where the bounded Vision reread must be allowed
            // to compete. Do not let that weak owner hide its own crop
            // candidate before the v3.252 content-quality fusion gate runs.
            if isWeakCompactJapaneseOwner(observation) {
                return nil
            }
            // Direction provenance alone is not recognition coverage. A weak
            // page-level vertical read must leave its geometry eligible for
            // pixel-first reread; only usable Japanese text may suppress a
            // duplicate recovery candidate.
            let text = postProcessJapaneseOCRText(observation.text)
            guard !text.isEmpty,
                  validOCRConfidence(observation.confidence) != nil,
                  observation.confidence >= 0.48,
                  JapaneseOCRTextNormalizer.containsJapaneseLetter(text),
                  JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5,
                  japaneseScriptDensity(in: text) >= 0.5 else {
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
            request.reportCharacterBoxes = true
            let handler = VNImageRequestHandler(cgImage: rotated, options: [:])
            guard (try? handler.perform([request])) != nil else { continue }

            for detection in request.results ?? [] {
                guard let rotatedRect = normalizedRect(from: detection.boundingBox) else {
                    continue
                }
                let mappedRequestRect = mapRotatedRegionRect(
                    rotatedRect,
                    rotatedImage: rotated,
                    originalImage: image,
                    angle: angle
                )
                let mappedRect = japanesePixelDetectorCharacterEnvelope(
                    detection,
                    fallback: mappedRequestRect,
                    rotatedImage: rotated,
                    originalImage: image,
                    angle: angle
                )
                let mappedQuad = japanesePixelDetectorCharacterQuad(
                    detection,
                    fallback: mappedRequestRect,
                    candidateRect: mappedRect,
                    rotatedImage: rotated,
                    originalImage: image,
                    angle: angle
                )
                let characterCount = detection.characterBoxes?.count ?? 0
                let isCompactCandidate = isJapanesePixelFirstCompactCandidate(
                    mappedRect,
                    characterCount: characterCount
                )
                let overlapsLayoutBlock = verticalBlocks.contains {
                    japanesePixelDetectorRegionIsCovered(
                        $0.rect,
                        by: mappedRect
                    )
                }
                guard (
                    isJapanesePixelFirstVerticalCandidate(mappedRect)
                        || isCompactCandidate
                ),
                      !overlapsLayoutBlock,
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
                        detectorRotation: angle,
                        characterCount: characterCount,
                        cropQuadHint: mappedQuad
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
            // Collect a bounded overflow before applying the 12-request cap so
            // compact candidates in a long-page band cannot be hidden behind
            // taller Vision boxes. The final selection below reserves at most
            // four compact candidates and still returns no more than 12.
            if unique.count == 128 { break }
        }
        let compactCandidates = unique
            .filter {
                isJapanesePixelFirstCompactCandidate(
                    $0.rect,
                    characterCount: $0.characterCount
                )
            }
            .sorted { lhs, rhs in
                if lhs.rect.y != rhs.rect.y { return lhs.rect.y < rhs.rect.y }
                return lhs.rect.x > rhs.rect.x
            }
        let reservedCompact = Array(compactCandidates.prefix(4))
        let regularCandidates = unique.filter { candidate in
            !reservedCompact.contains(where: {
                $0.rect == candidate.rect
                    && $0.detectorRotation == candidate.detectorRotation
                    && $0.characterCount == candidate.characterCount
            })
        }
        let remaining = max(0, 12 - reservedCompact.count)
        let selectedRegular = Self.boundedJapanesePixelFirstRegularCandidates(
            regularCandidates,
            limit: remaining
        )
        return reservedCompact + selectedRegular
    }

    /// Keep the existing compact-candidate reservation, but prevent the
    /// remaining pixel-first recovery slots from clustering in one vertical
    /// band on a long page. The input is already ordered by the historical
    /// height/geometry priority; only an over-budget, multi-band queue is
    /// reselected and the returned candidates retain that original order.
    private static func boundedJapanesePixelFirstRegularCandidates(
        _ candidates: [JapanesePixelFirstRegion],
        limit: Int
    ) -> [JapanesePixelFirstRegion] {
        guard limit > 0, candidates.count > limit else { return candidates }

        let bandCount = min(limit, candidates.count)
        var bands = Array(repeating: [Int](), count: bandCount)
        for (offset, candidate) in candidates.enumerated() {
            let centerY = candidate.rect.y + candidate.rect.height / 2
            let boundedCenterY = centerY.isFinite
                ? min(max(centerY, 0), 1)
                : 0
            let bandIndex = min(
                Int(boundedCenterY * Double(bandCount)),
                bandCount - 1
            )
            bands[bandIndex].append(offset)
        }

        let populatedBands = bands.indices.filter { !bands[$0].isEmpty }
        guard populatedBands.count > 1 else {
            return Array(candidates.prefix(limit))
        }

        var selectedOffsets = Set<Int>()
        var cursors = Array(repeating: 0, count: bandCount)
        while selectedOffsets.count < limit {
            var addedCandidate = false
            for bandIndex in populatedBands {
                guard selectedOffsets.count < limit,
                      cursors[bandIndex] < bands[bandIndex].count else {
                    continue
                }
                let offset = bands[bandIndex][cursors[bandIndex]]
                cursors[bandIndex] += 1
                selectedOffsets.insert(offset)
                addedCandidate = true
            }
            guard addedCandidate else { break }
        }

        return candidates.enumerated()
            .filter { selectedOffsets.contains($0.offset) }
            .map(\.element)
    }

    /// Prefer the detector's character-level envelope as the closest Vision
    /// equivalent to Koharu's tight line polygon. A broad request rectangle
    /// remains the fallback when Vision omits character boxes or returns an
    /// isolated/invalid set, so detector recall never depends on this hint.
    private static func japanesePixelDetectorCharacterEnvelope(
        _ detection: VNTextObservation,
        fallback: ImageOCRLayoutRect,
        rotatedImage: CGImage,
        originalImage: CGImage,
        angle: Int
    ) -> ImageOCRLayoutRect {
        let characterRects = (detection.characterBoxes ?? []).compactMap {
            character -> ImageOCRLayoutRect? in
            guard let rotatedRect = normalizedRect(from: character.boundingBox) else {
                return nil
            }
            return mapRotatedRegionRect(
                rotatedRect,
                rotatedImage: rotatedImage,
                originalImage: originalImage,
                angle: angle
            ).normalizedToUnit()
        }
        guard characterRects.count >= 2,
              let broadEnvelope = characterRects
                .dropFirst()
                .reduce(characterRects[0], { $0.union($1) })
                .normalizedToUnit() else {
            return fallback
        }
        let envelope = japanesePixelDetectorRobustColumnEnvelope(
            characterRects,
            broadEnvelope: broadEnvelope
        ) ?? broadEnvelope

        let envelopeArea = envelope.width * envelope.height
        let fallbackArea = max(fallback.width * fallback.height, 0.0001)
        let areaRatio = envelopeArea / fallbackArea
        let horizontalCoverage = envelope.width / max(fallback.width, 0.001)
        let verticalCoverage = envelope.height / max(fallback.height, 0.001)
        guard isJapanesePixelFirstVerticalCandidate(envelope),
              overlapRatio(envelope, fallback) >= 0.80,
              areaRatio >= 0.25,
              areaRatio <= 1.05,
              horizontalCoverage >= 0.35,
              verticalCoverage >= 0.60 else {
            return fallback
        }
        return envelope
    }

    /// Approximate Koharu's `line_polygon` from Vision character rectangles.
    /// Character boxes arrive in the rotated image, where a vertical Japanese
    /// line runs along the horizontal axis. Aggregate the outer glyph edges in
    /// that coordinate space so the quad covers the whole line instead of the
    /// middle glyph; the strict detector-coverage gate still rejects unsafe
    /// geometry and callers retain the bbox crop as a fallback.
    private static func japanesePixelDetectorCharacterQuad(
        _ detection: VNTextObservation,
        fallback: ImageOCRLayoutRect,
        candidateRect: ImageOCRLayoutRect,
        rotatedImage: CGImage,
        originalImage: CGImage,
        angle: Int
    ) -> ImageOCRLayoutQuad? {
        let rotatedCharacterQuads = (detection.characterBoxes ?? []).compactMap {
            character -> ImageOCRLayoutQuad? in
            normalizedQuad(from: character)
        }
        guard rotatedCharacterQuads.count >= 2 else { return nil }

        let allPoints = rotatedCharacterQuads.flatMap(\.points)
        guard let minX = allPoints.map(\.x).min(),
              let maxX = allPoints.map(\.x).max(),
              let minY = allPoints.map(\.y).min(),
              let maxY = allPoints.map(\.y).max() else {
            return nil
        }
        let rotatedLineQuad = ImageOCRLayoutQuad(points: [
            ImageOCRLayoutPoint(x: minX, y: minY),
            ImageOCRLayoutPoint(x: maxX, y: minY),
            ImageOCRLayoutPoint(x: maxX, y: maxY),
            ImageOCRLayoutPoint(x: minX, y: maxY),
        ])
        guard let normalizedRotatedLineQuad = rotatedLineQuad.normalized() else {
            return nil
        }
        let quad = mapRotatedRegionQuad(
            normalizedRotatedLineQuad,
            rotatedImage: rotatedImage,
            originalImage: originalImage,
            angle: angle
        )
        guard let quadRect = quad.boundingRect.normalizedToUnit() else {
            return nil
        }

        let detectorArea = max(fallback.width * fallback.height, 0.0001)
        let quadArea = quadRect.width * quadRect.height
        let intersection = intersectionArea(fallback, quadRect)
        let detectorCoverage = intersection / detectorArea
        let quadCoverage = intersection / max(quadArea, 0.0001)
        let areaRatio = quadArea / detectorArea
        let horizontalCoverage = min(fallback.maxX, quadRect.maxX)
            - max(fallback.x, quadRect.x)
        let verticalCoverage = min(fallback.maxY, quadRect.maxY)
            - max(fallback.y, quadRect.y)

        guard overlapRatio(fallback, quadRect) >= 0.80,
              overlapRatio(candidateRect, quadRect) >= 0.80,
              detectorCoverage >= 0.55,
              quadCoverage >= 0.80,
              areaRatio >= 0.35,
              areaRatio <= 1.05,
              horizontalCoverage / max(fallback.width, 0.001) >= 0.45,
              verticalCoverage / max(fallback.height, 0.001) >= 0.85,
              quadRect.width < fallback.width * 0.90 else {
            return nil
        }
        return quad
    }

    /// Vision occasionally reports one character rectangle spanning two
    /// neighboring manga columns. Koharu's detector line polygons stay tied to
    /// one TextRegion, so use the median center and width of glyph-sized boxes
    /// when that produces a materially tighter column. The broad envelope is
    /// retained for vertical extent and remains the safe fallback.
    private static func japanesePixelDetectorRobustColumnEnvelope(
        _ characterRects: [ImageOCRLayoutRect],
        broadEnvelope: ImageOCRLayoutRect
    ) -> ImageOCRLayoutRect? {
        guard characterRects.count >= 3,
              let maximumWidth = characterRects.map(\.width).max(),
              let maximumHeight = characterRects.map(\.height).max() else {
            return nil
        }
        let glyphRects = characterRects.filter {
            $0.width >= maximumWidth * 0.35
                && $0.height >= maximumHeight * 0.35
        }
        guard glyphRects.count >= 3 else { return nil }

        let medianCenter = median(glyphRects.map(\.midX))
        let medianWidth = median(glyphRects.map(\.width))
        guard medianWidth >= broadEnvelope.width * 0.35,
              medianWidth <= broadEnvelope.width * 0.82 else {
            return nil
        }
        return ImageOCRLayoutRect(
            x: medianCenter - medianWidth / 2,
            y: broadEnvelope.y,
            width: medianWidth,
            height: broadEnvelope.height
        ).normalizedToUnit()
    }

    /// A rotated Vision detector can start a short column several glyphs below
    /// its siblings even though their vertical ranges clearly belong to one
    /// manga text group. Extend only small candidates toward the top of a
    /// nearby, better-supported column; never alter the bottom or synthesize a
    /// new column without detector geometry.
    private static func alignPartialJapaneseMangaOCRColumns(
        _ regions: [JapanesePixelFirstRegion]
    ) -> [JapanesePixelFirstRegion] {
        regions.map { candidate in
            guard candidate.characterCount >= 2,
                  candidate.characterCount <= 4 else {
                return candidate
            }
            let neighbors = regions.filter { neighbor in
                guard neighbor.characterCount > candidate.characterCount else {
                    return false
                }
                let centerDistance = abs(neighbor.rect.midX - candidate.rect.midX)
                let minimumSeparation = min(neighbor.rect.width, candidate.rect.width) * 0.55
                let maximumSeparation = max(neighbor.rect.width, candidate.rect.width) * 2.0
                let topGap = candidate.rect.y - neighbor.rect.y
                let verticalIntersection = max(
                    0,
                    min(candidate.rect.maxY, neighbor.rect.maxY)
                        - max(candidate.rect.y, neighbor.rect.y)
                )
                let verticalOverlap = verticalIntersection
                    / max(min(candidate.rect.height, neighbor.rect.height), 0.001)
                return centerDistance >= minimumSeparation
                    && centerDistance <= maximumSeparation
                    && topGap >= 0.012
                    && topGap <= min(candidate.rect.height * 0.65, 0.06)
                    && neighbor.rect.height >= candidate.rect.height * 0.75
                    && verticalOverlap >= 0.60
            }
            guard let neighbor = neighbors.min(by: {
                abs($0.rect.midX - candidate.rect.midX)
                    < abs($1.rect.midX - candidate.rect.midX)
            }) else {
                return candidate
            }
            let alignedRect = ImageOCRLayoutRect(
                x: candidate.rect.x,
                y: neighbor.rect.y,
                width: candidate.rect.width,
                height: candidate.rect.maxY - neighbor.rect.y
            ).normalizedToUnit()
            guard let alignedRect,
                  isJapanesePixelFirstVerticalCandidate(alignedRect) else {
                return candidate
            }
            var aligned = candidate
            aligned.rect = alignedRect
            return aligned
        }
    }

    /// Match Koharu's role boundary for Manga OCR crops. Its RT-DETR
    /// `comic-text-bubble-detector` TextRegion has neither `ctd` line polygons
    /// nor a detected font size, so `crop_text_block_bbox` returns the detector
    /// bbox unchanged. Vision-only supplements are the bounded compatibility
    /// path where our line envelope and direction-aware padding still apply.
    private static func japaneseMangaOCRCropRect(
        _ region: JapanesePixelFirstRegion,
        among regions: [JapanesePixelFirstRegion],
        imageSize: CGSize
    ) -> ImageOCRLayoutRect {
        let rect = region.rect
        guard case .vision = region.detector else {
            // Do not expand an RT-DETR owner. A padded detector crop can pull a
            // neighboring vertical column into the model input even though the
            // ownership/layout rect itself remains correct.
            return rect
        }
        let cropBase = region.cropRectHint ?? rect
        let expanded = expandedVerticalCropRect(
            cropBase,
            imageSize: imageSize,
            direction: .vertical
        )
        // Do not let a Vision supplement bisect its own expanded crop at an
        // adjacent detector/column boundary.
        var left = expanded.x
        var right = expanded.maxX
        for neighbor in regions where neighbor.rect != rect {
            let verticalIntersection = max(
                0,
                min(rect.maxY, neighbor.rect.maxY) - max(rect.y, neighbor.rect.y)
            )
            let verticalOverlap = verticalIntersection
                / max(min(rect.height, neighbor.rect.height), 0.001)
            let centerDistance = abs(neighbor.rect.midX - rect.midX)
            guard verticalOverlap >= 0.50,
                  centerDistance >= min(rect.width, neighbor.rect.width) * 0.55,
                  centerDistance <= max(rect.width, neighbor.rect.width) * 2.25 else {
                continue
            }
            let boundary = (rect.midX + neighbor.rect.midX) / 2
            if neighbor.rect.midX < rect.midX {
                left = max(left, min(boundary, rect.x))
            } else {
                right = min(right, max(boundary, rect.maxX))
            }
        }
        return ImageOCRLayoutRect(
            x: left,
            y: expanded.y,
            width: right - left,
            height: expanded.height
        ).normalizedToUnit() ?? expanded
    }

    private static func isJapanesePixelFirstVerticalCandidate(
        _ rect: ImageOCRLayoutRect
    ) -> Bool {
        let aspectRatio = rect.height / max(rect.width, 0.001)
        return rect.width <= 0.30
            && rect.height >= 0.025
            && aspectRatio >= 1.15
    }

    /// Vision can expose a short Japanese sound effect from a rotated page as
    /// a compact, near-square envelope after mapping it back to the source.
    /// Keep this recovery gate separate from the normal vertical geometry so a
    /// genuinely horizontal short line cannot globally become a vertical
    /// candidate. The four-character cap mirrors Koharu's bounded small-node
    /// ownership and lets long-page bands reserve one compact candidate each.
    private static func isJapanesePixelFirstCompactCandidate(
        _ rect: ImageOCRLayoutRect,
        characterCount: Int
    ) -> Bool {
        guard (2...4).contains(characterCount),
              rect.width >= 0.012,
              rect.height >= 0.006,
              rect.width <= 0.08,
              rect.height <= 0.08 else {
            return false
        }
        let shortest = max(min(rect.width, rect.height), 0.001)
        let longest = max(rect.width, rect.height)
        let aspectRatio = longest / shortest
        return aspectRatio <= 4.5
    }

    private static func isWeakCompactJapaneseOwner(
        _ observation: VisionOCRObservation
    ) -> Bool {
        observation.observationRole == .detectorTextRegion
            && validOCRConfidence(observation.confidence) != nil
            && observation.confidence < 0.80
            && observation.rect.width <= 0.08
            && observation.rect.height <= 0.08
            && observation.text.unicodeScalars.count <= 4
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
        // A layout block is geometry context, not recognition coverage by
        // itself. Keep weak, empty, non-Japanese, low-density, and
        // directionally uncertain vertical blocks eligible for the existing
        // tile fallback; only a usable Japanese block with a confident
        // vertical classification may suppress a broad reconnaissance
        // window. The direction score is the layout engine's geometry
        // confidence, not the OCR confidence above, so keep both gates
        // explicit.
        let reliableVerticalBlocks = verticalBlocks.filter { block in
            let text = postProcessJapaneseOCRText(block.text)
            return block.direction == .vertical
                && block.directionConfidence.isFinite
                && (0...1).contains(block.directionConfidence)
                && block.directionConfidence >= 0.45
                && !text.isEmpty
                && validOCRConfidence(block.confidence) != nil
                && block.confidence >= 0.48
                && JapaneseOCRTextNormalizer.containsJapaneseLetter(text)
                && JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5
                && japaneseScriptDensity(in: text) >= 0.5
        }
        // Manga reading order is right-to-left across columns, then
        // top-to-bottom inside each column. For a very tall page, a strict
        // column-first loop can spend the whole finite budget in the first
        // rightmost strip and leave every other column unseen. Only when the
        // complete strip/window schedule exceeds the existing budget do we
        // round-robin same-height windows from right to left before descending
        // to the next height band. Keeping the legacy order when the schedule
        // fits preserves the existing orientation-fallback assignment for
        // ordinary pages; layout still restores final reading order after
        // recognition.
        let mangaOrderedStarts = starts.sorted { $0 > $1 }
        let shouldUseBandRoundRobin =
            verticalWindows.count * mangaOrderedStarts.count > maximumWindows
        let reliableLineRegions = lineObservations.compactMap { observation in
            japaneseLinePathRegion(observation)
        }

        var refined: [VisionOCRObservation] = []
        refined.reserveCapacity(maximumWindows * 2)
        var orientationFallbacksRemaining = 4
        var processedWindowCount = 0

        func processJapaneseVerticalTile(
            start: Int,
            window: (start: Int, height: Int)
        ) {
            guard processedWindowCount < maximumWindows else { return }
            let pixelWidth = min(tileWidth, imageWidth - start)
            guard pixelWidth >= 2 else { return }
            let pixelHeight = window.height
            guard pixelHeight >= 2 else { return }
            let tileRect = ImageOCRLayoutRect(
                x: Double(start) / Double(imageWidth),
                y: Double(window.start) / Double(imageHeight),
                width: Double(pixelWidth) / Double(imageWidth),
                height: Double(pixelHeight) / Double(imageHeight)
            )
            guard !reliableVerticalBlocks.contains(where: {
                verticalTileIsCovered($0.rect, by: tileRect)
            }),
                  !reliableLineRegions.contains(where: {
                      overlapRatio($0, tileRect) >= 0.60
                  }),
                  let crop = cropImage(image, normalizedRect: tileRect),
                  crop.image.width >= 2,
                  crop.image.height >= 2 else {
                return
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

        if shouldUseBandRoundRobin {
            for window in verticalWindows {
                for start in mangaOrderedStarts {
                    processJapaneseVerticalTile(start: start, window: window)
                }
            }
        } else {
            for start in mangaOrderedStarts {
                for window in verticalWindows {
                    processJapaneseVerticalTile(start: start, window: window)
                }
            }
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
        meaningfulJapaneseRecoveryObservations(observations).filter { observation in
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
    ) async throws -> [VisionOCRObservation] {
        let safeObservations = deduplicateJapaneseObservations(observations)
        var candidates: [VisionOCRObservation] = []
        for block in blocks {
            candidates.append(contentsOf: safeObservations.compactMap { observation in
                let lineRegion = observation.lineRegionRect ?? observation.rect
                guard japaneseObservation(observation, belongsTo: block),
                      overlapRatio(observation.rect, block.rect) >= 0.25,
                      japaneseLineRegionOverlapsBlock(observation, block: block),
                      isVerticalLineCandidate(lineRegion) else {
                    return nil
                }
                return observation
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

        let perspectiveCandidates = Array(
            boundedJapaneseVisionLineCandidates(
                uniqueCandidates,
                limit: 24
            ).prefix(24)
        )
        // Vision may split a narrow vertical Japanese column into near-square
        // one- or two-glyph observations. Koharu's detector emits one line
        // region before OCR, so replace those fragmented axis-aligned rereads
        // with bounded synthetic column crops while keeping the original
        // quadrilateral candidates available for perspective correction.
        let synthesizedCandidates = synthesizeJapaneseVerticalLineCandidates(
            observations: safeObservations,
            blocks: blocks
        )
        let geometryOnlyCandidates = japaneseGeometryOnlyVerticalLineCandidates(
            in: image,
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
            boundedJapaneseVisionLineCandidates(
                deduplicateJapaneseObservations(axisSeeds),
                limit: 24
            ).prefix(24)
        )

        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        let mangaLineCandidates = japaneseMangaLineOCRCandidates(
            uniqueCandidates: uniqueCandidates,
            synthesizedCandidates: synthesizedCandidates,
            geometryOnlyCandidates: geometryOnlyCandidates
        )
        let mangaLineRefined = try await recognizeJapaneseMangaLineOCR(
            in: image,
            candidates: mangaLineCandidates,
            imageSize: imageSize
        )
        var refined: [VisionOCRObservation] = []
        refined.append(contentsOf: mangaLineRefined)
        refined.reserveCapacity(
            mangaLineRefined.count + (perspectiveCandidates.count + axisCandidates.count) * 2
        )
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
                let meaningfulPerspective = meaningfulJapaneseRecoveryObservations(
                    [perspective]
                )
                refined.append(contentsOf: meaningfulPerspective)
                // Koharu's extract_text_block_regions uses a successful line
                // polygon region instead of rereading the same line bbox. Keep
                // the axis-aligned path as a quality fallback, but suppress it
                // for a geometrically matching perspective result that is
                // already strong enough to avoid a duplicate Vision request.
                if !needsJapaneseOrientationFallback(meaningfulPerspective) {
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
                observationRole: .verticalLine,
                verticalTextRegionOwner: candidate.verticalTextRegionOwner
            )
            let meaningfulPrimary = meaningfulJapaneseRecoveryObservations(
                primary
            )
            refined.append(contentsOf: meaningfulPrimary)
            if orientationFallbacksRemaining > 0,
               needsJapaneseOrientationFallback(meaningfulPrimary) {
                orientationFallbacksRemaining -= 1
                let opposite = recognizeJapaneseCropPass(
                    crop: preparedCrop.image,
                    cropRect: crop.rect,
                    originalImage: image,
                    angle: oppositeJapaneseOrientation(angle),
                    recognitionLanguages: recognitionLanguages,
                    minimumTextHeight: 0.002,
                    cropScale: preparedCrop.scale,
                    observationRole: .verticalLine,
                    verticalTextRegionOwner: candidate.verticalTextRegionOwner
                )
                refined.append(
                    contentsOf: meaningfulJapaneseRecoveryObservations(opposite)
                )
            }
        }
        return refined
    }

    private static func annotateJapaneseVerticalTextRegionOwners(
        _ observations: [VisionOCRObservation],
        blocks: [ImageOCRLayoutBlock]
    ) -> [VisionOCRObservation] {
        observations.map { observation in
            var annotated = observation
            let ownerMatches = verticalTextRegionMatchIndices(
                observation,
                blocks: blocks
            )
            if ownerMatches.count == 1 {
                annotated.verticalTextRegionOwner = blocks[ownerMatches[0]]
                    .verticalTextRegionOwner
            } else {
                annotated.verticalTextRegionOwner = nil
            }
            return annotated
        }
    }

    /// Return the vertical layout blocks whose geometry owns this line
    /// candidate. Exactly one match is the Koharu `block_index` equivalent;
    /// zero or multiple matches intentionally remain ownerless.
    private static func verticalTextRegionMatchIndices(
        _ observation: VisionOCRObservation,
        blocks: [ImageOCRLayoutBlock]
    ) -> [Int] {
        blocks.enumerated().compactMap { index, block in
            let lineRegion = observation.lineRegionRect ?? observation.rect
            guard block.direction == .vertical,
                  block.directionConfidence >= 0.25,
                  JapaneseOCRTextNormalizer.japaneseLetterDensity(block.text) >= 0.5,
                  japaneseScriptDensity(in: block.text) >= 0.5,
                  overlapRatio(observation.rect, block.rect) >= 0.25,
                  japaneseLineRegionOverlapsBlock(observation, block: block),
                  isVerticalLineCandidate(lineRegion) else {
                return nil
            }
            return index
        }
    }

    /// Mark a text-backed line as a bounded recovery risk before the Manga OCR
    /// line budget is allocated. Long, already-strong lines are useful context
    /// but are less likely to benefit from a second read than a short or
    /// mixed-script line whose first read may have lost Japanese glyphs.
    private static func isJapaneseMangaLineCandidateAtRisk(
        _ candidate: VisionOCRObservation
    ) -> Bool {
        let text = postProcessJapaneseOCRText(candidate.text)
        let letters = japaneseLetterCountForRecovery(text)
        return validOCRConfidence(candidate.confidence) == nil
            || candidate.confidence < 0.60
            || letters <= 2
            || JapaneseOCRTextNormalizer.japaneseLetterDensity(text) < 0.65
            || japaneseScriptDensity(in: text) < 0.65
    }

    /// Select tight Vision line geometry as a bounded equivalent of Koharu's
    /// `TextRegion.line_polygons`. Detector-owned Manga OCR results are excluded
    /// so the same TextRegion is never submitted twice; synthesized columns are
    /// admitted because they are the closest local proxy for fragmented lines.
    private static func japaneseMangaLineOCRCandidates(
        uniqueCandidates: [VisionOCRObservation],
        synthesizedCandidates: [VisionOCRObservation],
        geometryOnlyCandidates: [VisionOCRObservation]
    ) -> [VisionOCRObservation] {
        let textBackedCandidates = deduplicateJapaneseObservations(
            synthesizedCandidates + uniqueCandidates
        ).filter { candidate in
            guard candidate.observationRole != .detectorTextRegion else {
                return false
            }
            let region = candidate.lineRegionRect ?? candidate.rect
            let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return isVerticalLineCandidate(region)
                && !text.isEmpty
                && validOCRConfidence(candidate.confidence) != nil
                && JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5
                && japaneseScriptDensity(in: text) >= 0.5
        }
        let textBacked = textBackedCandidates.sorted { lhs, rhs in
            let lhsAtRisk = isJapaneseMangaLineCandidateAtRisk(lhs)
            let rhsAtRisk = isJapaneseMangaLineCandidateAtRisk(rhs)
            if lhsAtRisk != rhsAtRisk {
                // The text-backed share of the bounded line budget should
                // reach weak/short/mixed-script lines before strong long lines
                // that are less likely to need a second recognition pass.
                return lhsAtRisk && !rhsAtRisk
            }
            let lhsConfidence = validOCRConfidence(lhs.confidence) ?? -.infinity
            let rhsConfidence = validOCRConfidence(rhs.confidence) ?? -.infinity
            if lhsAtRisk {
                if lhsConfidence != rhsConfidence {
                    // Within the risk class, preserve the existing weak-first
                    // recovery policy using the finite confidence key.
                    return lhsConfidence < rhsConfidence
                }
                let lhsText = postProcessJapaneseOCRText(lhs.text)
                let rhsText = postProcessJapaneseOCRText(rhs.text)
                let lhsLetters = japaneseLetterCountForRecovery(lhsText)
                let rhsLetters = japaneseLetterCountForRecovery(rhsText)
                if lhsLetters != rhsLetters {
                    return lhsLetters < rhsLetters
                }
                let lhsDensity = japaneseScriptDensity(in: lhsText)
                let rhsDensity = japaneseScriptDensity(in: rhsText)
                if lhsDensity != rhsDensity {
                    return lhsDensity < rhsDensity
                }
            }
            let lhsLength = lhs.text.unicodeScalars.count
            let rhsLength = rhs.text.unicodeScalars.count
            if lhsLength != rhsLength {
                return lhsLength > rhsLength
            }
            if lhsConfidence != rhsConfidence {
                // Non-risk candidates keep the historical longest-line-first
                // order; confidence remains the tie-break for equal lengths.
                return lhsConfidence < rhsConfidence
            }
            if lhs.rect.y != rhs.rect.y {
                return lhs.rect.y < rhs.rect.y
            }
            if lhs.rect.x != rhs.rect.x {
                return lhs.rect.x < rhs.rect.x
            }
            return lhs.text < rhs.text
        }

        // Geometry-only candidates are the closest local equivalent to
        // Koharu's detector-supplied `line_polygons`: they have no OCR text or
        // detector confidence, so reserve a small part of the same request
        // budget for them instead of letting a page full of fragmented
        // text-backed observations starve a missed line. A geometry candidate
        // that is already covered by a text-backed line is not a recovery
        // opportunity and must not consume that reserved capacity.
        let uncoveredGeometry = geometryOnlyCandidates
            .filter { geometry in
                !textBacked.contains { textCandidate in
                    isSameJapaneseLineRegion(geometry, as: textCandidate)
                }
            }
            .sorted { lhs, rhs in
                let lhsHeight = lhs.lineRegionRect?.height ?? lhs.rect.height
                let rhsHeight = rhs.lineRegionRect?.height ?? rhs.rect.height
                if lhsHeight != rhsHeight { return lhsHeight > rhsHeight }
                if lhs.rect.y != rhs.rect.y { return lhs.rect.y < rhs.rect.y }
                return lhs.rect.x > rhs.rect.x
            }

        let geometryReserve = min(
            uncoveredGeometry.count,
            min(2, maximumJapaneseMangaLineOCRRequests)
        )
        let textLimit = max(
            0,
            maximumJapaneseMangaLineOCRRequests - geometryReserve
        )
        let selectedTextBacked = boundedJapaneseMangaLineTextCandidates(
            textBacked,
            limit: textLimit
        )
        return Array(
            selectedTextBacked
                + Array(uncoveredGeometry.prefix(geometryReserve))
        ).prefix(maximumJapaneseMangaLineOCRRequests).map { $0 }
    }

    /// Preserve the existing risk-first line queue, but prevent one known
    /// vertical TextRegion from consuming every text-backed slot when the
    /// bounded line budget is exceeded. Only a missing owner is promoted into
    /// the selected prefix; the final array is restored to the original queue
    /// order so request/result matching and all ordinary under-budget pages are
    /// unchanged. ownerless candidates are not counted as owners and are only
    /// displaced when no duplicate known-owner candidate can be removed.
    private static func boundedJapaneseMangaLineTextCandidates(
        _ candidates: [VisionOCRObservation],
        limit: Int
    ) -> [VisionOCRObservation] {
        guard limit > 0 else { return [] }
        guard candidates.count > limit else { return candidates }

        var knownOwners: [Int] = []
        for candidate in candidates {
            guard let owner = candidate.verticalTextRegionOwner,
                  !knownOwners.contains(owner) else {
                continue
            }
            knownOwners.append(owner)
        }
        guard knownOwners.count > 1 else {
            return Array(candidates.prefix(limit))
        }

        var selectedIndices = Array(candidates.indices.prefix(limit))
        var selectedOwnerCounts: [Int: Int] = [:]
        for index in selectedIndices {
            if let owner = candidates[index].verticalTextRegionOwner {
                selectedOwnerCounts[owner, default: 0] += 1
            }
        }
        let selectedOwners = Set(selectedOwnerCounts.keys)
        guard selectedOwners.count < knownOwners.count else {
            return selectedIndices.map { candidates[$0] }
        }

        for owner in knownOwners where !selectedOwnerCounts.keys.contains(owner) {
            guard let candidateIndex = candidates.indices.first(where: { index in
                candidates[index].verticalTextRegionOwner == owner
                    && !selectedIndices.contains(index)
            }) else {
                continue
            }

            let duplicateOwnerDropIndex = selectedIndices.reversed().first { index in
                guard let selectedOwner = candidates[index].verticalTextRegionOwner else {
                    return false
                }
                return (selectedOwnerCounts[selectedOwner] ?? 0) > 1
            }
            let dropIndex = duplicateOwnerDropIndex
                ?? selectedIndices.reversed().first { index in
                    candidates[index].verticalTextRegionOwner == nil
                }
                ?? selectedIndices.last
            guard let dropIndex else { continue }

            if let droppedOwner = candidates[dropIndex].verticalTextRegionOwner {
                selectedOwnerCounts[droppedOwner, default: 1] -= 1
                if selectedOwnerCounts[droppedOwner] == 0 {
                    selectedOwnerCounts.removeValue(forKey: droppedOwner)
                }
            }
            selectedIndices.removeAll { $0 == dropIndex }
            selectedIndices.append(candidateIndex)
            selectedOwnerCounts[owner, default: 0] += 1
        }

        return selectedIndices.sorted().map { candidates[$0] }
    }

    /// Reuse the deterministic owner-balanced prefix policy for Vision's
    /// perspective and axis line rereads. These queues may contain geometry
    /// or synthesized candidates in addition to text-backed observations, so
    /// the public boundary is kept separate from the Manga-only helper while
    /// preserving the same explicit-owner, no-new-budget semantics.
    private static func boundedJapaneseVisionLineCandidates(
        _ candidates: [VisionOCRObservation],
        limit: Int
    ) -> [VisionOCRObservation] {
        boundedJapaneseMangaLineTextCandidates(candidates, limit: limit)
    }

    /// Derive recognition-only line geometry from Vision's rotated
    /// `VNTextObservation.characterBoxes`. This is deliberately a separate
    /// source from text-backed observations: the candidate is admitted without
    /// using recognized text, but only inside one already-established Japanese
    /// vertical layout block. That is the safe boundary available on iOS when
    /// the upstream RT-DETR exposes a bbox but no Koharu `line_polygons`.
    private static func japaneseLineID(
        for rect: ImageOCRLayoutRect,
        owner: Int?
    ) -> ImageOCRLineID {
        let ownerKey = owner.map(String.init) ?? "ownerless"
        let values = [rect.x, rect.y, rect.width, rect.height].map {
            Int(($0 * 100_000).rounded())
        }
        return ImageOCRLineID(
            "line-\(ownerKey)-\(values.map { String($0) }.joined(separator: "-"))"
        )
    }

    private static func japaneseGeometryOnlyVerticalLineCandidates(
        in image: CGImage,
        observations: [VisionOCRObservation],
        blocks: [ImageOCRLayoutBlock]
    ) -> [VisionOCRObservation] {
        guard !blocks.isEmpty else { return [] }

        // Reuse the existing character-envelope/quad mapper, but do not pass
        // broad page or detector observations as `existingVerticalRegions`.
        // They are ownership context, not evidence that this line geometry was
        // already recognized. Existing tight vertical-line observations and
        // their reliable line results still suppress duplicate geometry.
        let lineSeedObservations = observations.filter {
            $0.observationRole == .verticalLine
        }
        let regions = detectJapanesePixelFirstVerticalRegions(
            in: image,
            observations: lineSeedObservations,
            verticalBlocks: [],
            lineObservations: []
        )

        var candidates: [VisionOCRObservation] = []
        for region in regions {
            guard region.characterCount >= 2,
                  region.cropQuadHint != nil,
                  isVerticalLineCandidate(region.rect) else {
                continue
            }

            let matchingBlocks = blocks.filter { block in
                guard block.direction == .vertical,
                      block.directionConfidence >= 0.25,
                      JapaneseOCRTextNormalizer.japaneseLetterDensity(block.text) >= 0.5,
                      japaneseScriptDensity(in: block.text) >= 0.5 else {
                    return false
                }
                return japanesePixelDetectorRegionIsCovered(
                    block.rect,
                    by: region.rect
                )
            }
            // A line polygon belongs to exactly one TextRegion in Koharu. If
            // Vision geometry crosses two layout owners, it is not safe to
            // assign it to either owner, so leave the historical paths intact.
            guard matchingBlocks.count == 1,
                  let block = matchingBlocks.first else {
                continue
            }
            let owner = block.verticalTextRegionOwner
            let regionID = block.provenance?.candidates.compactMap(\.regionID).first

            let blockArea = max(block.rect.width * block.rect.height, 0.0001)
            let candidateArea = region.rect.width * region.rect.height
            let candidateCoverage = intersectionArea(block.rect, region.rect)
                / blockArea
            let areaRatio = candidateArea / blockArea
            guard candidateCoverage >= 0.10,
                  areaRatio <= 1.25,
                  region.rect.width <= max(block.rect.width * 1.25, 0.05),
                  region.rect.height <= max(block.rect.height * 1.25, 0.05) else {
                continue
            }

            let duplicatesTextBackedGeometry = observations.contains { observation in
                guard let tightRegion = observation.lineRegionRect?.normalizedToUnit(),
                      observation.observationRole != .detectorTextRegion else {
                    return false
                }
                return overlapRatio(tightRegion, region.rect) >= 0.72
            }
            guard !duplicatesTextBackedGeometry else { continue }

            let lineID = japaneseLineID(
                for: region.rect,
                owner: owner
            )

            candidates.append(
                VisionOCRObservation(
                    text: "",
                    confidence: 0,
                    rect: region.rect,
                    lineRegionRect: region.rect,
                    lineRegionQuad: region.cropQuadHint,
                    rotationApplied: koharuPreferredJapaneseVerticalLineOrientation(),
                    sourceDirectionHint: .vertical,
                    observationRole: .verticalLine,
                    verticalTextRegionOwner: owner,
                    provenance: ImageOCRCandidateProvenance(
                        engine: .vision,
                        role: .geometryOnly,
                        cropVariant: .lineQuad,
                        geometrySource: .lineQuad,
                        regionID: regionID,
                        lineID: lineID,
                        rawConfidence: 0,
                        rotationApplied: koharuPreferredJapaneseVerticalLineOrientation(),
                        verticalTextRegionOwner: owner
                    )
                )
            )
        }

        var unique: [VisionOCRObservation] = []
        for candidate in candidates {
            guard !unique.contains(where: {
                isSameJapaneseLineRegion(candidate, as: $0)
            }) else {
                continue
            }
            unique.append(candidate)
        }
        return unique
    }

    /// Feed a tight vertical line crop through the bundled Koharu Manga OCR
    /// model. The request keeps the candidate's line quad as recognition-only
    /// geometry, uses the line-specific rotate270 boundary, and maps output back
    /// to the original line ownership rect. A missing/incompatible model is an
    /// ordinary fallback; cancellation still propagates to the image task.
    private static func recognizeJapaneseMangaLineOCR(
        in image: CGImage,
        candidates: [VisionOCRObservation],
        imageSize: CGSize
    ) async throws -> [VisionOCRObservation] {
        guard !candidates.isEmpty else { return [] }
        let requests = candidates.map { candidate in
            let lineRect = candidate.lineRegionRect ?? candidate.rect
            return MangaOCRRequest(
                textRect: lineRect,
                cropRect: expandedVerticalLineCropRect(
                    lineRect,
                    imageSize: imageSize
                ),
                cropOrientation: .koharuVerticalLine270,
                cropQuad: candidate.lineRegionQuad,
                cropQuadIsVertical: candidate.lineRegionQuad != nil,
                verticalTextRegionOwner: candidate.verticalTextRegionOwner,
                regionID: candidate.candidateProvenance.regionID,
                lineID: candidate.candidateProvenance.lineID
                    ?? japaneseLineID(
                        for: lineRect,
                        owner: candidate.verticalTextRegionOwner
                    )
            )
        }

        let results: [MangaOCRResult]
        do {
            results = try await MangaOCRService.shared.recognize(
                image: image,
                requests: requests
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return []
        }

        var unmatchedCandidates = candidates
        var observations: [VisionOCRObservation] = []
        observations.reserveCapacity(results.count)
        for result in results {
            guard let text = Self.cleanRecognizedBlockText(result.text),
                  let confidence = Self.validOCRConfidence(result.confidence),
                  confidence >= 0.55,
                  JapaneseOCRTextNormalizer.containsJapaneseLetter(text),
                  JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5,
                  japaneseScriptDensity(in: text) >= 0.5 else {
                continue
            }
            guard let candidateIndex = unmatchedCandidates.firstIndex(where: {
                let lineRect = $0.lineRegionRect ?? $0.rect
                return lineRect == result.textRect
                    && $0.verticalTextRegionOwner == result.verticalTextRegionOwner
            }) else {
                continue
            }
            let candidate = unmatchedCandidates.remove(at: candidateIndex)
            observations.append(
                VisionOCRObservation(
                    text: text,
                    confidence: confidence,
                    rect: candidate.rect,
                    lineRegionRect: candidate.lineRegionRect ?? candidate.rect,
                    lineRegionQuad: candidate.lineRegionQuad,
                    rotationApplied: koharuPreferredJapaneseVerticalLineOrientation(),
                    sourceDirectionHint: .vertical,
                    observationRole: .verticalLine,
                    verticalTextRegionOwner: result.verticalTextRegionOwner,
                    provenance: ImageOCRCandidateProvenance(
                        engine: .bundledMangaOCR,
                        role: .verticalLine,
                        cropVariant: result.cropVariant,
                        geometrySource: result.geometrySource,
                        lineID: result.lineID,
                        rawConfidence: result.confidence,
                        detectorConfidence: result.detectorConfidence,
                        rotationApplied: koharuPreferredJapaneseVerticalLineOrientation(),
                        verticalTextRegionOwner: result.verticalTextRegionOwner
                    )
                )
            )
        }
        return observations
    }

    /// Decide whether a Japanese block is safe to omit after line rereads.
    ///
    /// A single successful line can sit inside a multi-line Vision block.  The
    /// old any-overlap check therefore dropped the remaining text before the
    /// block crop had a chance to recover it. Reconstruct the source line set
    /// from page/line observations, excluding block-level detector TextRegions,
    /// require a valid source candidate, and match
    /// each candidate to a distinct, tight `.verticalLine` result.  The
    /// one-to-one rule also prevents a synthesized column envelope from being
    /// treated as proof that several independent source lines were read.
    private static func hasCompleteJapaneseLineCoverage(
        for block: ImageOCRLayoutBlock,
        sourceObservations: [VisionOCRObservation],
        lineRefined: [VisionOCRObservation],
        allowsBlockCropResults: Bool = false
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
                let hasEligibleRole = observation.observationRole == .verticalLine
                    || (allowsBlockCropResults && observation.observationRole == .crop)
                guard hasEligibleRole,
                      !observation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let lineRegion = observation.lineRegionRect?.normalizedToUnit() else {
                    return false
                }
                return japaneseObservation(observation, belongsTo: block)
                    && overlapRatio(observation.rect, block.rect) >= 0.25
                    && japaneseLineRegionOverlapsBlock(observation, block: block)
                    && isVerticalLineCandidate(lineRegion)
            }
            .sorted { isBetterJapaneseObservation($0, $1) }

        guard availableLineResults.count >= sourceLineCandidates.count else {
            return false
        }

        for candidate in sourceLineCandidates {
            guard let resultIndex = availableLineResults.firstIndex(where: {
                ImageOCRLayoutEngine.lineCoverageOwnersProveBlock(
                    lineResultOwner: $0.verticalTextRegionOwner,
                    candidateOwner: candidate.verticalTextRegionOwner,
                    blockOwner: block.verticalTextRegionOwner
                )
                    && isReliableJapaneseLineCoverageResult($0, candidate: candidate)
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
            // A bundled detector observation is a block-level TextRegion bbox,
            // not evidence that each source line inside that bbox was read.
            // Keeping it out of the source set prevents one narrow line result
            // from falsely suppressing the wider block-crop recovery.
            guard observation.observationRole != .detectorTextRegion else {
                return false
            }
            let lineRegion = observation.lineRegionRect ?? observation.rect
            return japaneseObservation(observation, belongsTo: block)
                && overlapRatio(observation.rect, block.rect) >= 0.25
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
              validOCRConfidence(result.confidence) != nil,
              result.confidence >= 0.48,
              JapaneseOCRTextNormalizer.containsJapaneseLetter(text),
              JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5,
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
        guard verticalTextRegionOwnersCompatible(lineResult, candidate) else {
            return false
        }
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
                    japaneseObservation(observation, belongsTo: block)
                        && overlapRatio(observation.rect, block.rect) >= 0.25
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

                let best = bestJapaneseObservation(
                    in: ordered.map(\.observation)
                ) ?? ordered[0].observation
                let ownerCandidates = Set(
                    ordered.compactMap { $0.observation.verticalTextRegionOwner }
                )
                let owner = ownerCandidates.count == 1
                    && ordered.allSatisfy({ $0.observation.verticalTextRegionOwner != nil })
                    ? ownerCandidates.first
                    : nil
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
                        observationRole: best.observationRole,
                        verticalTextRegionOwner: owner
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
            && JapaneseOCRTextNormalizer.japaneseLetterDensity(observation.text) >= 0.5
            && japaneseScriptDensity(in: observation.text) >= 0.5
            && region.height >= 0.012
            && ratio >= 0.75
    }

    private static func isSameJapaneseLineRegion(
        _ candidate: VisionOCRObservation,
        as covered: VisionOCRObservation
    ) -> Bool {
        guard verticalTextRegionOwnersCompatible(candidate, covered) else {
            return false
        }
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
        observationRole: VisionOCRObservationRole = .crop,
        preservesDetectorTextRegionBoundary: Bool = false,
        isCompactJapaneseRecovery: Bool = false,
        usesLanguageCorrection: Bool = false,
        verticalTextRegionOwner: Int? = nil
    ) -> [VisionOCRObservation] {
        guard let rotatedCrop = try? rotatedImage(crop, angle: angle),
              let cropObservations = try? recognizeObservations(
                  in: rotatedCrop,
                  recognitionLanguages: recognitionLanguages,
                  minimumTextHeight: minimumTextHeight,
                  automaticallyDetectsLanguage: false,
                  rotationApplied: angle,
                  postProcessJapaneseText: true,
                  usesLanguageCorrection: usesLanguageCorrection,
                  observationRole: observationRole,
                  requiresMeaningfulJapaneseRecoveryText: true
              ) else {
            return []
        }
        return cropObservations.map {
            var mapped = mapRotatedCropObservation(
                $0,
                rotatedImage: rotatedCrop,
                cropRect: cropRect,
                originalImage: originalImage,
                angle: angle,
                cropScale: cropScale
            )
            mapped.preservesDetectorTextRegionBoundary =
                preservesDetectorTextRegionBoundary
            mapped.isCompactJapaneseRecovery = isCompactJapaneseRecovery
            mapped.verticalTextRegionOwner = verticalTextRegionOwner
            return mapped
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
        guard let best = bestJapaneseObservation(in: observations) else {
            return true
        }
        let textLength = best.text.unicodeScalars.count
        return validOCRConfidence(best.confidence) == nil
            || best.confidence < 0.48
            || JapaneseOCRTextNormalizer.japaneseLetterDensity(best.text) < 0.5
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
                  observationRole: .verticalLine,
                  requiresMeaningfulJapaneseRecoveryText: true
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
            observationRole: .verticalLine,
            verticalTextRegionOwner: candidate.verticalTextRegionOwner
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

        // Koharu's `warp_line_region` samples the cropped source directly into
        // a bounded target canvas with bilinear interpolation, then rotates a
        // vertical line by 270 degrees. Reuse MangaOCRService's shared
        // image-rs-compatible sampler here so Vision line rereads do not add
        // a second Core Image projection followed by a `.high` resize. If the
        // direct path cannot represent malformed or unsupported geometry, the
        // natural Core Image projection below remains the compatibility
        // fallback for this isolated line request.
        if let targetSize = MangaOCRService.koharuVerticalQuadWarpTargetSize(
            localPoints,
            maximumDimension: 4_096,
            maximumPixels: 4_000_000
        ) {
            let targetWidth = Int(targetSize.width.rounded())
            let targetHeight = Int(targetSize.height.rounded())
            if targetWidth >= 2,
               targetHeight >= 2,
               let bounded = MangaOCRService.koharuVerticalQuadWarp(
                   croppedImage,
                   sourcePoints: localPoints,
                   targetWidth: targetWidth,
                   targetHeight: targetHeight
               ),
               let rotated = try? rotatedImage(bounded, angle: 270) {
                return rotated
            }
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
              validOCRConfidence(observation.confidence) != nil,
              observation.confidence >= 0.48,
              JapaneseOCRTextNormalizer.containsJapaneseLetter(text),
              JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5,
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

    /// Known Koharu-style owners are hard TextRegion partitions. Ownerless
    /// Vision observations retain the historical geometry fallback because
    /// they could not be assigned to exactly one vertical block.
    private static func japaneseObservation(
        _ observation: VisionOCRObservation,
        belongsTo block: ImageOCRLayoutBlock
    ) -> Bool {
        guard let observationOwner = observation.verticalTextRegionOwner,
              let blockOwner = block.verticalTextRegionOwner else {
            return true
        }
        return observationOwner == blockOwner
    }

    private static func koharuVerticalCropPadding(
        _ rect: ImageOCRLayoutRect,
        imageSize: CGSize,
        direction: ImageTextDirection = .vertical
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
        let horizontalPaddingFraction = direction == .horizontal ? 0.12 : 0.18
        let verticalPaddingFraction = direction == .horizontal ? 0.18 : 0.12
        let horizontalPaddingPixels = max(
            fontSizePixels * horizontalPaddingFraction,
            basePaddingPixels
        )
        let verticalPaddingPixels = max(
            fontSizePixels * verticalPaddingFraction,
            basePaddingPixels
        )
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
                japaneseObservation(observation, belongsTo: block)
                    && overlapRatio(observation.rect, block.rect) >= 0.25
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
        imageSize: CGSize? = nil,
        direction: ImageTextDirection = .vertical
    ) -> ImageOCRLayoutRect {
        let padding = imageSize.flatMap {
            koharuVerticalCropPadding(rect, imageSize: $0, direction: direction)
        }
        let horizontalFraction = direction == .horizontal ? 0.12 : 0.18
        let verticalFraction = direction == .horizontal ? 0.18 : 0.12
        let horizontalPadding = padding?.horizontal
            ?? min(max(rect.width * horizontalFraction, 0.01), 0.08)
        let verticalPadding = padding?.vertical
            ?? min(max(rect.height * verticalFraction, 0.01), 0.08)
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
            observationRole: observation.observationRole,
            verticalTextRegionOwner: observation.verticalTextRegionOwner
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

    /// Keep successful detector TextRegions authoritative at the final layout
    /// boundary. Koharu does not retain a second page-level OCR stream after a
    /// text node has been handed to Manga OCR; Vision's rotated reconnaissance
    /// can otherwise add a wide, lower-quality duplicate for the same region.
    /// Only page observations are removed, and only when a detector-owned
    /// vertical result covers most of their smaller geometry. An empty detector
    /// result leaves every historical Vision fallback untouched.
    private static func suppressJapaneseDetectorOwnedPageSupplements(
        _ observations: [VisionOCRObservation],
        detectorObservations: [VisionOCRObservation]
    ) -> [VisionOCRObservation] {
        let detectorOwners = detectorObservations.filter { observation in
            observation.preservesDetectorTextRegionBoundary
                && !observation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !detectorOwners.isEmpty else { return observations }

        return observations.filter { observation in
            guard observation.observationRole == .page,
                  japaneseScriptDensity(in: observation.text) >= 0.5 else {
                return true
            }
            return !detectorOwners.contains { owner in
                verticalTextRegionOwnersCompatible(observation, owner)
                    && overlapRatio(observation.rect, owner.rect) >= 0.60
            }
        }
    }

    /// A detector TextRegion can be geometrically correct while its bundled
    /// Manga OCR result is a short, punctuation-heavy fragment.  The existing
    /// bbox-primary rule must remain the default, but a tightly overlapping
    /// Vision crop can be a better content read for this compact case (the
    /// fixed sample's `こっ、` versus `ニコッ`).  Replace only when all of the
    /// following hold: the owner is small and weak, the crop is a bounded
    /// Japanese vertical reread, it contains at least one more Japanese letter
    /// than the owner, and its geometry stays inside the owner neighborhood.
    /// This is a fusion preference, not a new detector or request path.
    private static func preferCompactJapaneseCropRecovery(
        _ observations: [VisionOCRObservation],
        detectorObservations: [VisionOCRObservation]
    ) -> [VisionOCRObservation] {
        var output = observations
        for owner in detectorObservations {
            let ownerText = owner.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let ownerLetters = japaneseLetterCountForRecovery(ownerText)
            guard owner.preservesDetectorTextRegionBoundary,
                  validOCRConfidence(owner.confidence) != nil,
                  owner.confidence < 0.80,
                  owner.rect.width <= 0.08,
                  owner.rect.height <= 0.08,
                  ownerText.unicodeScalars.count <= 4,
                  ownerLetters > 0 else {
                continue
            }

            let candidate = observations
                .filter { candidate in
                    guard candidate != owner,
                          candidate.observationRole == .crop
                              || candidate.observationRole == .verticalLine,
                          verticalTextRegionOwnersCompatible(candidate, owner),
                          candidate.sourceDirectionHint == .vertical,
                          validOCRConfidence(candidate.confidence) != nil,
                          candidate.confidence >= 0.40,
                          JapaneseOCRTextNormalizer.japaneseLetterDensity(candidate.text) >= 0.5,
                          japaneseScriptDensity(in: candidate.text) >= 0.5,
                          japaneseLetterCountForRecovery(candidate.text)
                              > ownerLetters,
                          overlapRatio(candidate.rect, owner.rect) >= 0.70,
                          candidate.rect.width <= max(owner.rect.width * 3.0, 0.08),
                          candidate.rect.height <= max(owner.rect.height * 2.5, 0.08) else {
                        return false
                    }
                    return true
                }
                .max { lhs, rhs in
                    let lhsLetters = japaneseLetterCountForRecovery(lhs.text)
                    let rhsLetters = japaneseLetterCountForRecovery(rhs.text)
                    if lhsLetters != rhsLetters { return lhsLetters < rhsLetters }
                    if lhs.confidence != rhs.confidence {
                        return lhs.confidence < rhs.confidence
                    }
                    return lhs.text < rhs.text
                }
            guard candidate != nil,
                  let ownerIndex = output.firstIndex(of: owner) else {
                continue
            }
            output.remove(at: ownerIndex)
        }
        return output
    }

    private static func japaneseLetterCountForRecovery(_ text: String) -> Int {
        text.unicodeScalars.reduce(into: 0) { count, scalar in
            switch scalar.value {
            case 0x3041...0x3096, 0x30A1...0x30FA, 0x30FD...0x30FF,
                 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                 0xFF66...0xFF9D:
                count += 1
            default:
                break
            }
        }
    }

    /// A short page-level Vision observation can be mapped as horizontal even
    /// when it sits in the same narrow column as the surrounding vertical
    /// Japanese text. Promote only a bounded 2–4-character Japanese candidate
    /// with a strong same-column vertical neighbor; unrelated horizontal UI
    /// labels and ordinary prose remain untouched.
    private static func promoteCompactJapaneseHorizontalObservations(
        _ observations: [VisionOCRObservation]
    ) -> [VisionOCRObservation] {
        var output = observations
        for index in output.indices {
            let candidate = output[index]
            guard candidate.observationRole == .page,
                  candidate.sourceDirectionHint != .vertical,
                  validOCRConfidence(candidate.confidence) != nil,
                  candidate.confidence >= 0.40,
                  candidate.rect.width <= 0.05,
                  candidate.rect.height <= 0.02,
                  JapaneseOCRTextNormalizer.japaneseLetterDensity(candidate.text) >= 0.5,
                  japaneseScriptDensity(in: candidate.text) >= 0.5,
                  (2...4).contains(japaneseLetterCountForRecovery(candidate.text)) else {
                continue
            }
            let hasVerticalColumnNeighbor = output.enumerated().contains { neighborIndex, neighbor in
                guard neighborIndex != index,
                      neighbor.observationRole == .verticalLine
                          || neighbor.sourceDirectionHint == .vertical,
                      validOCRConfidence(neighbor.confidence) != nil,
                      JapaneseOCRTextNormalizer.japaneseLetterDensity(neighbor.text) >= 0.5,
                      japaneseScriptDensity(in: neighbor.text) >= 0.5 else {
                    return false
                }
                let centerDistance = abs(neighbor.rect.midX - candidate.rect.midX)
                let gap = candidate.rect.y - neighbor.rect.maxY
                return centerDistance <= max(0.08, neighbor.rect.width * 0.65)
                    && gap >= -0.015
                    && gap <= 0.12
                    && neighbor.rect.width >= candidate.rect.width * 1.8
            }
            guard hasVerticalColumnNeighbor else { continue }
            output[index].sourceDirectionHint = .vertical
            output[index].observationRole = .verticalLine
            let ownerMatches = output.indices.filter { neighborIndex in
                guard neighborIndex != index,
                      output[neighborIndex].observationRole == .verticalLine,
                      output[neighborIndex].verticalTextRegionOwner != nil else {
                    return false
                }
                return overlapRatio(
                    output[neighborIndex].rect,
                    candidate.rect
                ) >= 0.45
            }
            let owners = Set(ownerMatches.compactMap {
                output[$0].verticalTextRegionOwner
            })
            if owners.count == 1 {
                output[index].verticalTextRegionOwner = owners.first
            }
            // This compact recovery was already a protected layout node before
            // owner tagging. Keep that fallback when geometry cannot identify
            // exactly one TextRegion; the owner is an additional partition,
            // not a prerequisite for retaining the compact block boundary.
            output[index].preservesDetectorTextRegionBoundary = true
            output[index].isCompactJapaneseRecovery = true
        }
        return output
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
            let inheritedOwner = observation.verticalTextRegionOwner
                ?? output[duplicateIndex].verticalTextRegionOwner
            if observation.isCompactJapaneseRecovery {
                if output[duplicateIndex].isCompactJapaneseRecovery {
                    if isBetterCompactJapaneseRecovery(
                        observation,
                        than: output[duplicateIndex]
                    ) {
                        var winner = observation
                        winner.verticalTextRegionOwner = inheritedOwner
                        output[duplicateIndex] = winner
                    } else if output[duplicateIndex].verticalTextRegionOwner == nil {
                        output[duplicateIndex].verticalTextRegionOwner = inheritedOwner
                    }
                } else if isUsableCompactJapaneseRecovery(observation) {
                    var winner = observation
                    winner.verticalTextRegionOwner = inheritedOwner
                    output.remove(at: duplicateIndex)
                    output.append(winner)
                }
                continue
            }
            if output[duplicateIndex].isCompactJapaneseRecovery {
                if isUsableCompactJapaneseRecovery(output[duplicateIndex]) {
                    continue
                }
                var winner = observation
                winner.verticalTextRegionOwner = inheritedOwner
                output[duplicateIndex] = winner
                continue
            }
            let preservesDetectorTextRegionBoundary =
                observation.preservesDetectorTextRegionBoundary
                || output[duplicateIndex].preservesDetectorTextRegionBoundary
            if prefersJapanese,
               shouldPreferMeaningfulJapaneseDuplicate(
                   observation,
                   over: output[duplicateIndex]
               ) {
                var winner = observation
                winner.verticalTextRegionOwner = inheritedOwner
                output[duplicateIndex] = winner
            } else if isBetterObservation(
                observation,
                than: output[duplicateIndex],
                prefersJapanese: prefersJapanese
            ) {
                var winner = observation
                winner.verticalTextRegionOwner = inheritedOwner
                output[duplicateIndex] = winner
            }
            output[duplicateIndex].preservesDetectorTextRegionBoundary =
                preservesDetectorTextRegionBoundary
            if output[duplicateIndex].verticalTextRegionOwner == nil {
                output[duplicateIndex].verticalTextRegionOwner = inheritedOwner
            }
        }
        return output
    }

    /// Geometry can prove that two ordinary Vision observations describe the
    /// same Japanese text, while the generic length/confidence score can still
    /// favor a long mixed-Latin read or punctuation-only noise. Within Vision's
    /// existing 0.14 confidence window, prefer the duplicate that contains
    /// meaningful Japanese writing. A lower-confidence hallucination cannot
    /// displace a strong punctuation result, and punctuation remains available
    /// when there is no qualified duplicate. Detector and compact candidates
    /// retain their dedicated replacement policies above this generic branch.
    private static func shouldPreferMeaningfulJapaneseDuplicate(
        _ candidate: VisionOCRObservation,
        over incumbent: VisionOCRObservation
    ) -> Bool {
        guard candidate.observationRole != .detectorTextRegion,
              incumbent.observationRole != .detectorTextRegion,
              !candidate.isCompactJapaneseRecovery,
              !incumbent.isCompactJapaneseRecovery,
              isMeaningfulJapaneseRecoveryText(candidate.text),
              !isMeaningfulJapaneseRecoveryText(incumbent.text),
              validOCRConfidence(candidate.confidence) != nil,
              candidate.confidence >= 0.40 else {
            return false
        }
        let incumbentConfidence = validOCRConfidence(incumbent.confidence) ?? 0
        return candidate.confidence >= incumbentConfidence - 0.14
    }

    private static func isUsableCompactJapaneseRecovery(
        _ observation: VisionOCRObservation
    ) -> Bool {
        validOCRConfidence(observation.confidence) != nil
            && observation.confidence >= 0.40
            && JapaneseOCRTextNormalizer.japaneseLetterDensity(observation.text) >= 0.5
            && japaneseScriptDensity(in: observation.text) >= 0.5
            && japaneseLetterCountForRecovery(observation.text) >= 3
    }

    private static func isBetterCompactJapaneseRecovery(
        _ lhs: VisionOCRObservation,
        than rhs: VisionOCRObservation
    ) -> Bool {
        let lhsLetters = japaneseLetterCountForRecovery(lhs.text)
        let rhsLetters = japaneseLetterCountForRecovery(rhs.text)
        if lhsLetters != rhsLetters { return lhsLetters > rhsLetters }
        let lhsDensity = japaneseScriptDensity(in: lhs.text)
        let rhsDensity = japaneseScriptDensity(in: rhs.text)
        if lhsDensity != rhsDensity { return lhsDensity > rhsDensity }
        return isBetterObservation(lhs, than: rhs, prefersJapanese: true)
    }

    private static func isBetterJapaneseObservation(
        _ lhs: VisionOCRObservation,
        _ rhs: VisionOCRObservation
    ) -> Bool {
        isBetterObservation(lhs, rhs, prefersJapanese: true)
    }

    /// The observation comparators are descending, while `Sequence.max(by:)`
    /// expects an ascending-order predicate. Keep reduction explicit so scoped
    /// selection, orientation fallback, synthesized provenance, and diagnostic
    /// evidence all use the strongest observation rather than the weakest one.
    private static func bestJapaneseObservation(
        in observations: [VisionOCRObservation]
    ) -> VisionOCRObservation? {
        bestObservation(in: observations, prefersJapanese: true)
    }

    private static func bestObservation(
        in observations: [VisionOCRObservation],
        prefersJapanese: Bool = false
    ) -> VisionOCRObservation? {
        guard var best = observations.first else { return nil }
        for candidate in observations.dropFirst() {
            if isBetterObservation(
                candidate,
                best,
                prefersJapanese: prefersJapanese
            ) {
                best = candidate
            }
        }
        return best
    }

    private static func isBetterObservation(
        _ lhs: VisionOCRObservation,
        _ rhs: VisionOCRObservation,
        prefersJapanese: Bool = false
    ) -> Bool {
        let lhsHasValidConfidence = validOCRConfidence(lhs.confidence) != nil
        let rhsHasValidConfidence = validOCRConfidence(rhs.confidence) != nil
        if lhsHasValidConfidence != rhsHasValidConfidence {
            return lhsHasValidConfidence
        }
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
        let confidence = validOCRConfidence(observation.confidence)
            .map { Double($0) }
            ?? 0
        let baseScore = Double(observation.text.unicodeScalars.count)
            + confidence * 8
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
        guard verticalTextRegionOwnersCompatible(lhs, rhs) else {
            return false
        }
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
        if prefersJapanese {
            let widthInsensitiveLeftText = normalizedOCRText(
                lhs.text,
                widthInsensitive: true
            )
            let widthInsensitiveRightText = normalizedOCRText(
                rhs.text,
                widthInsensitive: true
            )
            if widthInsensitiveLeftText == widthInsensitiveRightText {
                return true
            }
        }
        if leftText == rightText || leftText.contains(rightText) || rightText.contains(leftText) {
            return true
        }
        return overlap >= 0.72 && textSimilarity(leftText, rightText) >= 0.62
    }

    /// A non-empty owner is a hard Koharu TextRegion partition. Ownerless
    /// observations retain historical compatibility, while two distinct
    /// known owners can never collapse into one OCR line.
    private static func verticalTextRegionOwnersCompatible(
        _ lhs: VisionOCRObservation,
        _ rhs: VisionOCRObservation
    ) -> Bool {
        guard let lhsOwner = lhs.verticalTextRegionOwner,
              let rhsOwner = rhs.verticalTextRegionOwner else {
            return true
        }
        return lhsOwner == rhsOwner
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

    /// Japanese width folding intentionally preserves dakuten/handakuten;
    /// `.diacriticInsensitive` would collapse distinct kana during dedupe.
    private static func normalizedOCRText(
        _ text: String,
        widthInsensitive: Bool = false
    ) -> String {
        let canonicalText = JapaneseOCRTextNormalizer.canonicalized(text)
        let comparedText = widthInsensitive
            ? canonicalText.folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: .current
            )
            : canonicalText.lowercased()
        return comparedText.filter { $0.isLetter || $0.isNumber }
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
        // The rotated page pass is Koharu's bounded orientation
        // reconnaissance. Carry a vertical source hint only when the mapped
        // Japanese geometry is actually column-like; horizontal Japanese
        // captions observed in the same pass must keep the normal layout
        // heuristics instead of inheriting rotation provenance blindly.
        let directionRect = originalLineRegionRect ?? originalRect
        let verticalSourceHint: ImageOCRLayoutDirection? =
            JapaneseOCRTextNormalizer.japaneseLetterDensity(observation.text) >= 0.5
                && japaneseScriptDensity(in: observation.text) >= 0.5
                && directionRect.height / max(directionRect.width, 0.001) >= 1.05
                ? .vertical
                : nil
        return VisionOCRObservation(
            text: observation.text,
            confidence: observation.confidence,
            rect: originalRect,
            lineRegionRect: originalLineRegionRect,
            lineRegionQuad: originalLineRegionQuad,
            rotationApplied: observation.rotationApplied,
            sourceDirectionHint: verticalSourceHint,
            observationRole: observation.observationRole,
            verticalTextRegionOwner: observation.verticalTextRegionOwner
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

        let thumbnailMaxPixelSize = longPageThumbnailMaxPixelSize(for: source)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw VisionOCRServiceError.imageDecodeFailed
        }

        return image
    }

    /// Koharu slices a tall page before running detector/OCR. A single global
    /// 1,800-pixel thumbnail would shrink a 1,136px-wide long page to a few
    /// hundred pixels wide before slicing, making vertical glyphs ambiguous.
    /// Preserve display width for tall pages when memory allows, while keeping
    /// an explicit width and total-pixel bound for very large inputs.
    private static func longPageThumbnailMaxPixelSize(
        for source: CGImageSource
    ) -> Int {
        let fallback = 1_800
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              rawWidth.isFinite,
              rawHeight.isFinite,
              rawWidth >= 2,
              rawHeight >= 2 else {
            return fallback
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsAxes = [5, 6, 7, 8].contains(orientation)
        let displayWidth = swapsAxes ? rawHeight : rawWidth
        let displayHeight = swapsAxes ? rawWidth : rawHeight
        let aspectRatio = displayHeight / max(displayWidth, 1)
        guard aspectRatio > 3.5 else { return fallback }

        let maximumWidth = 1_800.0
        let maximumPixels = 16_000_000.0
        let widthScale = min(1, maximumWidth / displayWidth)
        let pixelScale = min(1, sqrt(maximumPixels / (displayWidth * displayHeight)))
        let scale = min(widthScale, pixelScale)
        let sourceMaxDimension = max(rawWidth, rawHeight)
        return max(Int(ceil(sourceMaxDimension * scale)), 2)
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
    case detectorTextRegion
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
    /// Set by bundled Manga OCR because its geometry originates from one
    /// dedicated detector TextRegion. Japanese dedupe carries this provenance
    /// onto the selected text so layout cannot join two detector nodes later.
    var preservesDetectorTextRegionBoundary = false
    /// Marks the bounded compact sound-effect recovery candidate. It wins over
    /// a duplicate page-level short line so long-page output keeps the compact
    /// candidate's vertical provenance instead of retaining a horizontal echo.
    var isCompactJapaneseRecovery = false
    /// Ephemeral Koharu `block_index` equivalent for a uniquely matched
    /// Japanese vertical TextRegion. This never enters the persisted block.
    var verticalTextRegionOwner: Int? = nil
    /// Explicit provenance is supplied by bundled Manga OCR and stable
    /// detector/line identities. Ordinary Vision observations derive the
    /// equivalent v3.281 record from their existing role and geometry.
    var provenance: ImageOCRCandidateProvenance? = nil

    var candidateProvenance: ImageOCRCandidateProvenance {
        if let provenance { return provenance }
        let role: ImageOCRCandidateRole
        let cropVariant: ImageOCRCropVariant
        let geometrySource: ImageOCRGeometrySource
        switch observationRole {
        case .page:
            role = .page
            cropVariant = .page
            geometrySource = .bbox
        case .crop:
            role = .crop
            cropVariant = .blockBBox
            geometrySource = .bbox
        case .verticalLine:
            role = .verticalLine
            cropVariant = lineRegionQuad == nil ? .lineBBox : .lineQuad
            geometrySource = lineRegionQuad == nil ? .bbox : .lineQuad
        case .detectorTextRegion:
            role = .detectorTextRegion
            cropVariant = .detectorBBox
            geometrySource = .bbox
        }
        return ImageOCRCandidateProvenance(
            engine: observationRole == .detectorTextRegion ? .bundledMangaOCR : .vision,
            role: role,
            cropVariant: cropVariant,
            geometrySource: geometrySource,
            rawConfidence: confidence,
            rotationApplied: rotationApplied,
            verticalTextRegionOwner: verticalTextRegionOwner
        )
    }
}

private struct JapaneseVerticalCropFragment: Sendable {
    var observation: VisionOCRObservation
    var rect: ImageOCRLayoutRect
}

private struct JapanesePixelFirstRegion: Sendable {
    var rect: ImageOCRLayoutRect
    var detectorRotation: Int
    var characterCount: Int
    var detector: JapanesePixelFirstDetector = .vision
    var detectorConfidence: Float = 0
    var regionID: ImageOCRRegionID? = nil
    /// Optional tight character-envelope crop. This never replaces `rect` in
    /// layout or ownership decisions and is only populated after strict
    /// detector-coverage gates pass.
    var cropRectHint: ImageOCRLayoutRect? = nil
    /// Optional perspective crop equivalent to Koharu's `line_polygon`. Like
    /// `cropRectHint`, this is recognition-only geometry with bbox fallback.
    var cropQuadHint: ImageOCRLayoutQuad? = nil
}

private enum JapanesePixelFirstDetector: Sendable {
    case vision
    case comicTextBubble
}

struct ImageOCRLayoutPoint: Equatable, Codable, Sendable {
    var x: Double
    var y: Double
}

struct ImageOCRLayoutQuad: Equatable, Codable, Sendable {
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
