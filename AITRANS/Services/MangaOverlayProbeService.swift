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

private struct MangaOverlayBubbleCandidate: Equatable, Sendable {
    var index: Int
    var boundingBox: CGRect
    var source: String
}

struct MangaOverlayProbeService: Sendable {
    private static let ocrScale: CGFloat = 2

    func recognizeTextBlocks(
        in imageData: Data,
        cropping: MangaOverlayProbeCropping = .defaultValue,
        customWords: [String] = []
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
                    scale: Self.ocrScale,
                    customWords: customWords
                )
            }
            return (image, Self.mergeCandidatesIntoBlocks(candidates, imageSize: CGSize(width: image.width, height: image.height)))
        }.value
    }

    func recognizePreprocessedText(
        in image: CGImage,
        block: MangaOverlayOCRBlock,
        options: MangaOverlayPreprocessingOptions = .defaultValue
    ) async throws -> String? {
        try await Task.detached(priority: .userInitiated) {
            guard options.enabled else { return nil }
            let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            let cropRect = Self.expand(block.boundingBox, by: 0.18, bounds: bounds).integral
            let cropped = try Self.croppedImage(image, rect: cropRect)
            let prepared = try Self.preprocessedImage(cropped, options: options)
            let candidates = try Self.recognizeTextCandidates(
                in: prepared,
                angle: 0,
                scaledContentSize: CGSize(width: CGFloat(prepared.width), height: CGFloat(prepared.height)),
                contentOrigin: .zero,
                scale: 1,
                customWords: []
            )
            let text = candidates
                .sorted {
                    if abs($0.boundingBox.minY - $1.boundingBox.minY) > 8 {
                        return $0.boundingBox.minY < $1.boundingBox.minY
                    }
                    return $0.boundingBox.minX < $1.boundingBox.minX
                }
                .map(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }.value
    }

    func renderOutputs(
        image: CGImage,
        blocks: [MangaOverlayProbeBlock],
        outputDirectory: URL,
        preprocessing: MangaOverlayPreprocessingOptions = .defaultValue,
        cropping: MangaOverlayProbeCropping = .defaultValue,
        bubbleDebugImagePath: String? = nil,
        bubbleCropsImagePath: String? = nil,
        bubbleTextOverlayImagePath: String? = nil
    ) async throws -> MangaOverlayProbeOutputFiles {
        try await Task.detached(priority: .userInitiated) {
            _ = try Self.recreateDirectory(outputDirectory)

            let debugURL = outputDirectory.appendingPathComponent("1_debug_boxes.png")
            let overlayURL = outputDirectory.appendingPathComponent("1_translated_overlay.png")
            let ocrTextURL = outputDirectory.appendingPathComponent("1_ocr_text_overlay.png")
            let deterministicCorrectionURL = outputDirectory.appendingPathComponent("1_deterministic_correction_overlay.png")
            let deterministicTranslationURL = outputDirectory.appendingPathComponent("1_deterministic_translation_overlay.png")
            let ocrProbeTextURL = outputDirectory.appendingPathComponent("1_ocr_probe_text.txt")
            let cropsURL = outputDirectory.appendingPathComponent("1_block_crops.png")
            let preprocessedURL = outputDirectory.appendingPathComponent("1_preprocessed_content.png")
            let debugImage = try Self.drawDebugBoxes(on: image, blocks: blocks)
            let overlayImage = try Self.drawTranslatedOverlay(on: image, blocks: blocks)
            let ocrTextImage = try Self.drawOCRTextOverlay(on: image, blocks: blocks)
            let deterministicCorrectionImage = try Self.drawDeterministicCorrectionOverlay(on: image, blocks: blocks)
            let deterministicTranslationImage = try Self.drawDeterministicTranslationOverlay(on: image, blocks: blocks)
            let cropsImage = try Self.drawBlockCrops(from: image, blocks: blocks, preprocessing: preprocessing)
            try Self.writePNG(debugImage, to: debugURL)
            try Self.writePNG(overlayImage, to: overlayURL)
            try Self.writePNG(ocrTextImage, to: ocrTextURL)
            try Self.writePNG(deterministicCorrectionImage, to: deterministicCorrectionURL)
            try Self.writePNG(deterministicTranslationImage, to: deterministicTranslationURL)
            try Self.writePNG(cropsImage, to: cropsURL)
            try Self.writeOCRProbeText(blocks: blocks, to: ocrProbeTextURL)

            var preprocessedPath: String?
            if preprocessing.enabled {
                let contentRect = Self.contentCropRect(for: image, cropping: cropping)
                let cropped = try Self.croppedImage(image, rect: contentRect)
                let prepared = try Self.preprocessedImage(cropped, options: preprocessing)
                try Self.writePNG(prepared, to: preprocessedURL)
                preprocessedPath = preprocessedURL.path
            }
            return MangaOverlayProbeOutputFiles(
                debugBoxesImage: debugURL.path,
                overlayImage: overlayURL.path,
                ocrTextOverlayImage: ocrTextURL.path,
                deterministicCorrectionOverlayImage: deterministicCorrectionURL.path,
                deterministicTranslationOverlayImage: deterministicTranslationURL.path,
                ocrProbeTextFile: ocrProbeTextURL.path,
                blockCropsImage: cropsURL.path,
                preprocessedContentImage: preprocessedPath,
                bubbleDebugImage: bubbleDebugImagePath,
                bubbleCropsImage: bubbleCropsImagePath,
                bubbleTextOverlayImage: bubbleTextOverlayImagePath
            )
        }.value
    }

    @discardableResult
    static func recreateDirectory(_ url: URL) throws -> Int {
        let fileManager = FileManager.default
        var removedItemCount = 0
        if fileManager.fileExists(atPath: url.path) {
            removedItemCount = (try? fileManager.contentsOfDirectory(atPath: url.path).count) ?? 0
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return removedItemCount
    }

    static func writeReport(_ report: MangaOverlayProbeReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
    }

    static func renderContactSheet(outputFiles: MangaOverlayProbeOutputFiles, outputDirectory: URL) throws -> String? {
        let entries: [(String, String?)] = [
            ("whole-page OCR", outputFiles.ocrTextOverlayImage),
            ("bubble-first OCR", outputFiles.bubbleTextOverlayImage),
            ("bubble crops", outputFiles.bubbleCropsImage),
            ("translated overlay", outputFiles.overlayImage),
            ("deterministic OCR", outputFiles.deterministicCorrectionOverlayImage),
            ("deterministic translation", outputFiles.deterministicTranslationOverlayImage)
        ]
        let images = entries.compactMap { title, path -> (String, CGImage)? in
            guard let path,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let image = try? makeImage(from: data) else {
                return nil
            }
            return (title, image)
        }
        guard !images.isEmpty else { return nil }

        let columns = 2
        let tileWidth: CGFloat = 520
        let tileHeight: CGFloat = 680
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        let canvasSize = CGSize(width: tileWidth * CGFloat(columns), height: tileHeight * CGFloat(rows))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let rendered = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.setFillColor(CGColor(red: 0.94, green: 0.95, blue: 0.96, alpha: 1))
            context.fill(CGRect(origin: .zero, size: canvasSize))
            for (index, entry) in images.enumerated() {
                let column = index % columns
                let row = index / columns
                let tile = CGRect(
                    x: CGFloat(column) * tileWidth + 10,
                    y: CGFloat(row) * tileHeight + 10,
                    width: tileWidth - 20,
                    height: tileHeight - 20
                )
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                context.fill(tile)
                drawText(
                    entry.0,
                    in: CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: 30),
                    fontSize: 17,
                    textColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                    backgroundColor: CGColor(red: 0.1, green: 0.16, blue: 0.24, alpha: 0.9),
                    context: context
                )
                let imageRect = aspectFitRect(
                    imageSize: CGSize(width: entry.1.width, height: entry.1.height),
                    bounds: CGRect(x: tile.minX + 6, y: tile.minY + 38, width: tile.width - 12, height: tile.height - 44)
                )
                UIImage(cgImage: entry.1).draw(in: imageRect)
            }
        }
        guard let image = rendered.cgImage else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        let url = outputDirectory.appendingPathComponent("1_probe_contact_sheet.png")
        try writePNG(image, to: url)
        return url.path
    }

    func compareCustomLexicon(
        in imageData: Data,
        customWords: [String],
        cropping: MangaOverlayProbeCropping = .defaultValue
    ) async throws -> MangaOverlayLexiconComparison {
        let withoutLexicon = try await recognizeTextBlocks(in: imageData, cropping: cropping, customWords: [])
        let withLexicon = try await recognizeTextBlocks(in: imageData, cropping: cropping, customWords: customWords)
        let pairedCount = min(withoutLexicon.blocks.count, withLexicon.blocks.count)
        var changedIndexes: [Int] = []
        for index in 0..<pairedCount where withoutLexicon.blocks[index].text != withLexicon.blocks[index].text {
            changedIndexes.append(index)
        }
        if withoutLexicon.blocks.count != withLexicon.blocks.count {
            changedIndexes.append(contentsOf: pairedCount..<max(withoutLexicon.blocks.count, withLexicon.blocks.count))
        }
        let notes: [String] = changedIndexes.isEmpty
            ? ["customWords did not change final merged block text in this run"]
            : ["customWords changed \(changedIndexes.count) merged block(s); effect is lexicon/language-correction hinting, not general OCR repair"]
        return MangaOverlayLexiconComparison(
            enabled: !customWords.isEmpty,
            customWords: customWords,
            withoutLexiconTotalBlocks: withoutLexicon.blocks.count,
            withLexiconTotalBlocks: withLexicon.blocks.count,
            changedBlockIndexes: changedIndexes,
            notes: notes
        )
    }

    func compareVisionAPIs(
        in imageData: Data,
        customWords: [String],
        cropping: MangaOverlayProbeCropping = .defaultValue
    ) async throws -> MangaOverlayVisionAPIComparison {
        try await Task.detached(priority: .userInitiated) {
            let image = try Self.makeImage(from: imageData)
            let contentRect = Self.contentCropRect(for: image, cropping: cropping)
            let croppedImage = try Self.croppedImage(image, rect: contentRect)
            let scaledImage = try Self.scaledImage(croppedImage, scale: Self.ocrScale)
            let oldTexts = try Self.recognizeTextCandidates(
                in: scaledImage,
                angle: 0,
                scaledContentSize: CGSize(width: CGFloat(scaledImage.width), height: CGFloat(scaledImage.height)),
                contentOrigin: contentRect.origin,
                scale: Self.ocrScale,
                customWords: customWords
            ).map(\.text)

            if #available(iOS 18.0, *) {
                do {
                    let newTexts = try await Self.recognizeTextWithSwiftAPI(in: scaledImage, customWords: customWords)
                    return MangaOverlayVisionAPIComparison(
                        oldAPITotalObservations: oldTexts.count,
                        newAPISupported: true,
                        newAPITotalObservations: newTexts.count,
                        changed: oldTexts != newTexts,
                        oldAPISample: Array(oldTexts.prefix(20)),
                        newAPISample: Array(newTexts.prefix(20)),
                        error: nil
                    )
                } catch {
                    return MangaOverlayVisionAPIComparison(
                        oldAPITotalObservations: oldTexts.count,
                        newAPISupported: true,
                        newAPITotalObservations: nil,
                        changed: nil,
                        oldAPISample: Array(oldTexts.prefix(20)),
                        newAPISample: [],
                        error: "\(type(of: error)): \(error.localizedDescription)"
                    )
                }
            } else {
                return MangaOverlayVisionAPIComparison(
                    oldAPITotalObservations: oldTexts.count,
                    newAPISupported: false,
                    newAPITotalObservations: nil,
                    changed: nil,
                    oldAPISample: Array(oldTexts.prefix(20)),
                    newAPISample: [],
                    error: "RecognizeTextRequest requires iOS 18+"
                )
            }
        }.value
    }

    func runBubbleFirstProbe(
        imageData: Data,
        groundTruth: [String],
        preprocessing: MangaOverlayPreprocessingOptions,
        customWords: [String],
        outputDirectory: URL,
        cropping: MangaOverlayProbeCropping = .defaultValue
    ) async throws -> (comparison: MangaOverlayFrameworkComparison, debugPath: String, cropsPath: String, seedDebugPath: String, textOverlayPath: String) {
        let start = Date.now
        return try await Task.detached(priority: .userInitiated) {
            let image = try Self.makeImage(from: imageData)
            let bubbles = try Self.detectBubbleCandidates(in: image, cropping: cropping, customWords: customWords)
            let seedDebugCandidates = try Self.rawBubbleSeedCandidates(in: image, cropping: cropping, customWords: customWords)
            let results = try bubbles.flatMap { bubble in
                try Self.bubbleResults(
                    for: bubble,
                    image: image,
                    preprocessing: preprocessing,
                    customWords: customWords,
                    groundTruth: groundTruth
                )
            }
            .filter(Self.shouldKeepBubbleResult)
            .enumerated()
            .map { offset, result in
                MangaOverlayBubbleResult(
                    index: offset,
                    bbox: result.bbox,
                    source: result.source,
                    text: result.text,
                    bestGroundTruthIndex: result.bestGroundTruthIndex,
                    bestSimilarity: result.bestSimilarity
                )
            }

            let bubbleTexts = results.map(\.text).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let bubbleAccuracy = Self.averageBestSimilarity(texts: bubbleTexts, groundTruth: groundTruth)
            let processingTime = Int(Date.now.timeIntervalSince(start) * 1000)
            let debugURL = outputDirectory.appendingPathComponent("1_bubble_debug.png")
            let cropsURL = outputDirectory.appendingPathComponent("1_bubble_crops.png")
            let seedDebugURL = outputDirectory.appendingPathComponent("1_bubble_seed_debug.png")
            let textOverlayURL = outputDirectory.appendingPathComponent("1_bubble_text_overlay.png")
            let debugImage = try Self.drawBubbleDebug(on: image, bubbles: bubbles)
            let cropsImage = try Self.drawBubbleCrops(from: image, bubbles: bubbles, results: results, preprocessing: preprocessing)
            let seedDebugImage = try Self.drawBubbleDebug(on: image, bubbles: seedDebugCandidates)
            let textOverlayImage = try Self.drawBubbleTextOverlay(on: image, results: results)
            try Self.writePNG(debugImage, to: debugURL)
            try Self.writePNG(cropsImage, to: cropsURL)
            try Self.writePNG(seedDebugImage, to: seedDebugURL)
            try Self.writePNG(textOverlayImage, to: textOverlayURL)
            let comparison = MangaOverlayFrameworkComparison(
                groundTruth: groundTruth,
                wholePage: MangaOverlayFrameworkMetrics(totalBlocksDetected: 0, processingTimeMs: 0, accuracyVsGroundTruth: 0),
                bubbleFirst: MangaOverlayFrameworkMetrics(
                    totalBlocksDetected: results.count,
                    processingTimeMs: processingTime,
                    accuracyVsGroundTruth: bubbleAccuracy
                ),
                blocksOnlyInWholePage: [],
                blocksOnlyInBubbleFirst: [],
                blocksFoundByBoth: 0,
                bubbleResults: results,
                notes: [
                    "bubble-first is independent probe path; it does not replace whole-page OCR",
                    "bubble detection uses near-white connected components, so non-white narration/effect text can be missed"
                ]
            )
            return (comparison, debugURL.path, cropsURL.path, seedDebugURL.path, textOverlayURL.path)
        }.value
    }

    @available(iOS 18.0, *)
    private static func recognizeTextWithSwiftAPI(in image: CGImage, customWords: [String]) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        let englishLanguages = request.supportedRecognitionLanguages.filter { language in
            let identifier = language.minimalIdentifier
            return identifier == "en" || identifier == "en-US"
        }
        if !englishLanguages.isEmpty {
            request.recognitionLanguages = englishLanguages
        }
        if !customWords.isEmpty {
            request.customWords = customWords
        }
        request.minimumTextHeightFraction = 0.006
        let observations = try await request.perform(on: image)
        return observations.compactMap { observation in
            let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty || Self.isNoise(text) ? nil : text
        }
    }

    private static func writeOCRProbeText(blocks: [MangaOverlayProbeBlock], to url: URL) throws {
        let content = blocks.map { block in
            let bbox = block.bbox.map { String(Int($0.rounded())) }.joined(separator: ",")
            let raw = block.rawOcrText.replacing("\n", with: " / ")
            let preprocessed = block.afterPreprocessingOcrText?.replacing("\n", with: " / ") ?? "nil"
            let final = block.finalTextUsedForTranslation.replacing("\n", with: " / ")
            let deterministic = block.deterministicCorrectionText?.replacing("\n", with: " / ") ?? "nil"
            let truth = block.bestGroundTruthText ?? "nil"
            let similarity = block.ocrGroundTruthSimilarity.map {
                $0.formatted(.number.precision(.fractionLength(3)))
            } ?? "nil"
            let translation = block.translationCandidate.replacing("\n", with: " / ")
            let rawOutput = block.rawOutput.replacing("\n", with: " / ")
            let deterministicTranslation = block.deterministicCorrectionTranslationCandidate?.replacing("\n", with: " / ") ?? "nil"
            let deterministicTranslationRaw = block.deterministicCorrectionTranslationRawOutput?.replacing("\n", with: " / ") ?? "nil"
            return """
            #\(block.index) bbox=[\(bbox)] angle=\(block.rotationAngleUsed) ocrSimilarity=\(similarity) blockPassed=\(block.blockPassed)
            rawOCR: \(raw)
            afterPreprocessing: \(preprocessed)
            finalForTranslation: \(final)
            deterministicCorrection: \(deterministic)
            bestGroundTruth: \(truth)
            translationCandidate: \(translation)
            rawOutput: \(rawOutput)
            deterministicCorrectionTranslationPassed: \(block.deterministicCorrectionTranslationPassed.map(String.init) ?? "nil")
            deterministicCorrectionTranslationCandidate: \(deterministicTranslation)
            deterministicCorrectionTranslationRawOutput: \(deterministicTranslationRaw)
            deterministicCorrectionTranslationFailureDetail: \(block.deterministicCorrectionTranslationFailureDetail ?? "nil")
            failureCategory: \(block.failureCategory)
            failureReasons: \(block.failureReasons.joined(separator: " | "))
            translationFailureDetail: \(block.translationFailureDetail ?? "nil")
            qualityNotes: \(block.qualityNotes.joined(separator: " | "))
            decisionTrace: \(block.translationDecisionTrace.joined(separator: " | "))
            """
        }
        .joined(separator: "\n\n")
        let cleanContent = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        try cleanContent.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func bubbleResults(
        for bubble: MangaOverlayBubbleCandidate,
        image: CGImage,
        preprocessing: MangaOverlayPreprocessingOptions,
        customWords: [String],
        groundTruth: [String]
    ) throws -> [MangaOverlayBubbleResult] {
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        let cropRect = expand(bubble.boundingBox, by: 0.08, bounds: bounds).integral
        let cropped = try croppedImage(image, rect: cropRect)
        let processed: CGImage
        let scale: CGFloat
        if preprocessing.enabled, bubble.source == "whiteComponent" {
            processed = try preprocessedImage(cropped, options: preprocessing)
            scale = 1
        } else if bubble.source == "ocrSeed" {
            processed = try scaledImage(cropped, scale: ocrScale)
            scale = ocrScale
        } else {
            processed = cropped
            scale = 1
        }
        let candidates = try recognizeTextCandidates(
            in: processed,
            angle: 0,
            scaledContentSize: CGSize(width: CGFloat(processed.width), height: CGFloat(processed.height)),
            contentOrigin: .zero,
            scale: 1,
            customWords: customWords
        )

        let localBlocks: [MangaOverlayOCRBlock]
        if bubble.source == "ocrSeed" {
            localBlocks = mergeCandidatesIntoBlocks(
                candidates,
                imageSize: CGSize(width: CGFloat(processed.width), height: CGFloat(processed.height))
            )
        } else {
            let text = mergeText(from: orderedCandidates(candidates))
            let rect = candidates.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
            localBlocks = text.isEmpty ? [] : [
                MangaOverlayOCRBlock(
                    text: text,
                    confidence: nil,
                    boundingBox: rect.isNull ? CGRect(origin: .zero, size: CGSize(width: processed.width, height: processed.height)) : rect,
                    rotationAngle: 0
                )
            ]
        }

        return localBlocks.map { block in
            let globalRect = clamp(
                CGRect(
                    x: cropRect.minX + block.boundingBox.minX / scale,
                    y: cropRect.minY + block.boundingBox.minY / scale,
                    width: block.boundingBox.width / scale,
                    height: block.boundingBox.height / scale
                ).standardized,
                to: bounds
            )
            let match = bestGroundTruthMatch(text: block.text, groundTruth: groundTruth)
            return MangaOverlayBubbleResult(
                index: bubble.index,
                bbox: [globalRect.minX, globalRect.minY, globalRect.width, globalRect.height].map(Double.init),
                source: "\(bubble.source):split",
                text: block.text,
                bestGroundTruthIndex: match.index,
                bestSimilarity: match.similarity
            )
        }
    }

    private static func shouldKeepBubbleResult(_ result: MangaOverlayBubbleResult) -> Bool {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let normalized = normalizedOCRText(text)
        guard normalized.count >= 8 || (normalized.count >= 5 && result.bestSimilarity >= 0.6) else { return false }
        let rect = CGRect(
            x: result.bbox.indices.contains(0) ? result.bbox[0] : 0,
            y: result.bbox.indices.contains(1) ? result.bbox[1] : 0,
            width: result.bbox.indices.contains(2) ? result.bbox[2] : 0,
            height: result.bbox.indices.contains(3) ? result.bbox[3] : 0
        )
        if result.bestSimilarity < 0.45, (normalized.count < 18 || rect.width * rect.height < 1500) {
            return false
        }
        return true
    }

    private static func recognizeTextCandidates(
        in image: CGImage,
        angle: Int,
        scaledContentSize: CGSize,
        contentOrigin: CGPoint,
        scale: CGFloat,
        customWords: [String]
    ) throws -> [MangaOverlayOCRCandidate] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        if !customWords.isEmpty {
            request.customWords = customWords
        }
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

    private static func preprocessedImage(_ image: CGImage, options: MangaOverlayPreprocessingOptions) throws -> CGImage {
        var current = image
        if options.cropUpscaleEnabled, options.cropScale > 1 {
            current = try scaledImage(current, scale: CGFloat(options.cropScale))
        }
        if options.grayscaleEnabled || options.contrastBrightnessEnabled || options.adaptiveThresholdEnabled {
            current = try rasterProcessedImage(current, options: options)
        }
        if options.sharpenEnabled {
            current = try sharpenedImage(current)
        }
        return current
    }

    private static func rasterProcessedImage(_ image: CGImage, options: MangaOverlayPreprocessingOptions) throws -> CGImage {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        var luminance = [UInt8](repeating: 0, count: width * height)
        var sum = 0
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                let gray = (red * 299 + green * 587 + blue * 114) / 1000
                luminance[y * width + x] = UInt8(max(0, min(255, gray)))
                sum += gray
            }
        }
        let mean = max(1, sum / max(1, width * height))

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                var gray = Int(luminance[index])
                if options.contrastBrightnessEnabled {
                    gray = max(0, min(255, Int((Double(gray - mean) * 1.35) + 188)))
                }
                if options.adaptiveThresholdEnabled {
                    let localMean = localAverage(luminance, x: x, y: y, width: width, height: height, radius: 8)
                    gray = gray < localMean - 10 ? 0 : 255
                }
                let offset = y * bytesPerRow + x * bytesPerPixel
                pixels[offset] = UInt8(gray)
                pixels[offset + 1] = UInt8(gray)
                pixels[offset + 2] = UInt8(gray)
                pixels[offset + 3] = 255
            }
        }

        guard let output = context.makeImage() else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        return output
    }

    private static func localAverage(_ luminance: [UInt8], x: Int, y: Int, width: Int, height: Int, radius: Int) -> Int {
        let minX = max(0, x - radius)
        let maxX = min(width - 1, x + radius)
        let minY = max(0, y - radius)
        let maxY = min(height - 1, y + radius)
        let step = max(1, radius / 4)
        var sum = 0
        var count = 0
        for sampleY in stride(from: minY, through: maxY, by: step) {
            for sampleX in stride(from: minX, through: maxX, by: step) {
                sum += Int(luminance[sampleY * width + sampleX])
                count += 1
            }
        }
        return count == 0 ? 255 : sum / count
    }

    private static func sharpenedImage(_ image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var input = [UInt8](repeating: 255, count: height * bytesPerRow)
        guard let inputContext = CGContext(
            data: &input,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        inputContext.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        var output = input
        guard width > 2, height > 2 else { return image }
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                for channel in 0..<3 {
                    let center = Int(input[(y * bytesPerRow) + (x * bytesPerPixel) + channel]) * 5
                    let top = Int(input[((y - 1) * bytesPerRow) + (x * bytesPerPixel) + channel])
                    let bottom = Int(input[((y + 1) * bytesPerRow) + (x * bytesPerPixel) + channel])
                    let left = Int(input[(y * bytesPerRow) + ((x - 1) * bytesPerPixel) + channel])
                    let right = Int(input[(y * bytesPerRow) + ((x + 1) * bytesPerPixel) + channel])
                    output[(y * bytesPerRow) + (x * bytesPerPixel) + channel] = UInt8(max(0, min(255, center - top - bottom - left - right)))
                }
            }
        }

        guard let outputContext = CGContext(
            data: &output,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let rendered = outputContext.makeImage() else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        return rendered
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

    private static func detectBubbleCandidates(
        in image: CGImage,
        cropping: MangaOverlayProbeCropping,
        customWords: [String]
    ) throws -> [MangaOverlayBubbleCandidate] {
        let contentRect = contentCropRect(for: image, cropping: cropping)
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        var mask = [Bool](repeating: false, count: width * height)
        let minX = max(0, Int(contentRect.minX))
        let maxX = min(width - 1, Int(contentRect.maxX))
        let minY = max(0, Int(contentRect.minY))
        let maxY = min(height - 1, Int(contentRect.maxY))
        for y in minY...maxY {
            for x in minX...maxX {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                let maxChannel = max(red, max(green, blue))
                let minChannel = min(red, min(green, blue))
                let luminance = (red * 299 + green * 587 + blue * 114) / 1000
                mask[y * width + x] = luminance > 218 && (maxChannel - minChannel) < 34
            }
        }

        var visited = [Bool](repeating: false, count: width * height)
        var rects: [CGRect] = []
        let minArea = max(280, Int(CGFloat(width * height) * 0.00035))
        let maxArea = Int(CGFloat(width * height) * 0.055)
        let imageArea = CGFloat(width * height)
        for y in minY...maxY {
            for x in minX...maxX {
                let startIndex = y * width + x
                guard mask[startIndex], !visited[startIndex] else { continue }
                var queue = [(x, y)]
                visited[startIndex] = true
                var cursor = 0
                var componentMinX = x
                var componentMaxX = x
                var componentMinY = y
                var componentMaxY = y
                var area = 0
                while cursor < queue.count {
                    let (currentX, currentY) = queue[cursor]
                    cursor += 1
                    area += 1
                    componentMinX = min(componentMinX, currentX)
                    componentMaxX = max(componentMaxX, currentX)
                    componentMinY = min(componentMinY, currentY)
                    componentMaxY = max(componentMaxY, currentY)
                    for (nextX, nextY) in [(currentX + 1, currentY), (currentX - 1, currentY), (currentX, currentY + 1), (currentX, currentY - 1)] {
                        guard nextX >= minX, nextX <= maxX, nextY >= minY, nextY <= maxY else { continue }
                        let nextIndex = nextY * width + nextX
                        guard mask[nextIndex], !visited[nextIndex] else { continue }
                        visited[nextIndex] = true
                        queue.append((nextX, nextY))
                    }
                }

                let rect = CGRect(
                    x: componentMinX,
                    y: componentMinY,
                    width: max(1, componentMaxX - componentMinX + 1),
                    height: max(1, componentMaxY - componentMinY + 1)
                )
                let fillRatio = CGFloat(area) / max(1, rect.width * rect.height)
                let aspectRatio = rect.width / max(1, rect.height)
                let rectArea = rect.width * rect.height
                let isPageSized = rect.width > CGFloat(width) * 0.72
                    || rect.height > contentRect.height * 0.45
                    || rectArea > imageArea * 0.08
                guard area >= minArea,
                      area <= maxArea,
                      !isPageSized,
                      rect.width >= 24,
                      rect.height >= 18,
                      aspectRatio >= 0.22,
                      aspectRatio <= 6.2,
                      fillRatio >= 0.28 else { continue }
                rects.append(expand(rect, by: 0.1, bounds: CGRect(x: 0, y: 0, width: width, height: height)))
            }
        }

        let seedRects = try ocrSeedBubbleRects(
            in: image,
            contentRect: contentRect,
            customWords: customWords
        )
        let seedOnlyRects = deduplicateSeedBubbleRects(seedRects)
        let whiteOnlyRects = mergeBubbleRects(rects).filter { white in
            !seedOnlyRects.contains { seed in
                overlapRatio(seed, white) > 0.62
            }
        }
        let candidates = seedOnlyRects.map { rect in
            (rect: rect, source: "ocrSeed")
        } + whiteOnlyRects.map { rect in
            (rect: rect, source: "whiteComponent")
        }
        return candidates
            .filter { item in
                item.rect.width >= 34
                    && item.rect.height >= 28
                    && item.rect.width <= CGFloat(width) * 0.58
                    && item.rect.height <= contentRect.height * 0.4
            }
            .sorted {
                if abs($0.rect.minY - $1.rect.minY) > 20 {
                    return $0.rect.minY < $1.rect.minY
                }
                return $0.rect.minX < $1.rect.minX
            }
            .enumerated()
            .map { index, item in
                MangaOverlayBubbleCandidate(index: index, boundingBox: item.rect, source: item.source)
        }
    }

    private static func ocrSeedBubbleRects(
        in image: CGImage,
        contentRect: CGRect,
        customWords: [String]
    ) throws -> [CGRect] {
        let croppedImage = try croppedImage(image, rect: contentRect)
        let scaledImage = try scaledImage(croppedImage, scale: ocrScale)
        let candidates = try [0, 90, 180, 270].flatMap { angle in
            let rotatedImage = try rotatedImage(scaledImage, angle: angle)
            return try recognizeTextCandidates(
                in: rotatedImage,
                angle: angle,
                scaledContentSize: CGSize(width: CGFloat(scaledImage.width), height: CGFloat(scaledImage.height)),
                contentOrigin: contentRect.origin,
                scale: ocrScale,
                customWords: customWords
            )
        }
        let blocks = mergeCandidatesIntoBlocks(
            candidates,
            imageSize: CGSize(width: image.width, height: image.height)
        )
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        return blocks
            .map { block -> CGRect in
                let rect = block.boundingBox
                let longText = block.text.count > 34
                let widthPad = max(18, rect.width * (longText ? 1.25 : 1.85))
                let heightPad = max(20, rect.height * 0.8)
                return clamp(rect.insetBy(dx: -widthPad, dy: -heightPad), to: bounds).integral
            }
            .filter { rect in
                rect.width >= 42
                    && rect.height >= 34
                    && rect.width <= CGFloat(image.width) * 0.62
                    && rect.height <= contentRect.height * 0.42
            }
    }

    private static func rawBubbleSeedCandidates(
        in image: CGImage,
        cropping: MangaOverlayProbeCropping,
        customWords: [String]
    ) throws -> [MangaOverlayBubbleCandidate] {
        let contentRect = contentCropRect(for: image, cropping: cropping)
        let seedRects = try ocrSeedBubbleRects(in: image, contentRect: contentRect, customWords: customWords)
        return seedRects.enumerated().map { index, rect in
            MangaOverlayBubbleCandidate(index: index, boundingBox: rect, source: "ocrSeedRaw")
        }
    }

    private static func mergeBubbleRects(_ rects: [CGRect]) -> [CGRect] {
        var output: [CGRect] = []
        for rect in rects.sorted(by: { $0.minY == $1.minY ? $0.minX < $1.minX : $0.minY < $1.minY }) {
            if let index = output.firstIndex(where: { overlapRatio($0, rect) > 0.2 || $0.insetBy(dx: -8, dy: -8).intersects(rect) }) {
                output[index] = output[index].union(rect)
            } else {
                output.append(rect)
            }
        }
        return output.sorted {
            if abs($0.minY - $1.minY) > 20 {
                return $0.minY < $1.minY
            }
            return $0.minX < $1.minX
        }
    }

    private static func deduplicateSeedBubbleRects(_ rects: [CGRect]) -> [CGRect] {
        var output: [CGRect] = []
        for rect in rects.sorted(by: { ($0.width * $0.height) > ($1.width * $1.height) }) {
            if let index = output.firstIndex(where: { overlapRatio($0, rect) > 0.78 }) {
                output[index] = output[index].union(rect)
            } else {
                output.append(rect)
            }
        }
        return output.sorted {
            if abs($0.minY - $1.minY) > 20 {
                return $0.minY < $1.minY
            }
            return $0.minX < $1.minX
        }
    }

    static func bestGroundTruthMatch(text: String, groundTruth: [String]) -> (index: Int?, similarity: Double) {
        let normalizedText = normalizedOCRText(text)
        guard !normalizedText.isEmpty else { return (nil, 0) }
        var bestIndex: Int?
        var bestScore = 0.0
        for (index, truth) in groundTruth.enumerated() {
            let score = textSimilarity(normalizedText, normalizedOCRText(truth))
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return (bestIndex, bestScore)
    }

    static func averageBestSimilarity(texts: [String], groundTruth: [String]) -> Double {
        guard !groundTruth.isEmpty else { return 0 }
        let scores = groundTruth.map { truth in
            texts.map { textSimilarity(normalizedOCRText($0), normalizedOCRText(truth)) }.max() ?? 0
        }
        return scores.reduce(0, +) / Double(scores.count)
    }

    static func matchedGroundTruthIndexes(texts: [String], groundTruth: [String], threshold: Double = 0.55) -> Set<Int> {
        var matched = Set<Int>()
        for text in texts {
            let match = bestGroundTruthMatch(text: text, groundTruth: groundTruth)
            if let index = match.index, match.similarity >= threshold {
                matched.insert(index)
            }
        }
        return matched
    }

    private static func drawBubbleDebug(on image: CGImage, bubbles: [MangaOverlayBubbleCandidate]) throws -> CGImage {
        try draw(on: image) { context, _ in
            context.setLineWidth(max(3, CGFloat(image.width) * 0.006))
            for bubble in bubbles {
                let isSeed = bubble.source.hasPrefix("ocrSeed")
                let strokeColor = isSeed
                    ? CGColor(red: 0.12, green: 0.45, blue: 1, alpha: 1)
                    : CGColor(red: 0.1, green: 0.72, blue: 0.25, alpha: 1)
                let labelColor = isSeed
                    ? CGColor(red: 0.1, green: 0.34, blue: 0.86, alpha: 0.9)
                    : CGColor(red: 0.1, green: 0.65, blue: 0.22, alpha: 0.9)
                context.setStrokeColor(strokeColor)
                context.stroke(bubble.boundingBox)
                drawText(
                    "B\(bubble.index) \(isSeed ? "seed" : "white")",
                    in: CGRect(x: bubble.boundingBox.minX, y: max(0, bubble.boundingBox.minY - 28), width: 128, height: 26),
                    fontSize: 18,
                    textColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                    backgroundColor: labelColor,
                    context: context
                )
            }
        }
    }

    private static func drawBubbleCrops(
        from image: CGImage,
        bubbles: [MangaOverlayBubbleCandidate],
        results: [MangaOverlayBubbleResult],
        preprocessing: MangaOverlayPreprocessingOptions
    ) throws -> CGImage {
        let tileWidth: CGFloat = 280
        let tileHeight: CGFloat = 210
        let columns = 2
        let rows = max(1, Int(ceil(Double(max(bubbles.count, 1)) / Double(columns))))
        let canvasSize = CGSize(width: tileWidth * CGFloat(columns), height: tileHeight * CGFloat(rows))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        var renderError: Error?
        let rendered = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.setFillColor(CGColor(red: 0.94, green: 0.95, blue: 0.94, alpha: 1))
            context.fill(CGRect(origin: .zero, size: canvasSize))
            for bubble in bubbles {
                let column = bubble.index % columns
                let row = bubble.index / columns
                let tileRect = CGRect(x: CGFloat(column) * tileWidth + 8, y: CGFloat(row) * tileHeight + 8, width: tileWidth - 16, height: tileHeight - 16)
                do {
                    let cropRect = expand(bubble.boundingBox, by: 0.08, bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
                    let cropped = try croppedImage(image, rect: cropRect)
                    let processed = preprocessing.enabled ? try preprocessedImage(cropped, options: preprocessing) : cropped
                    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                    context.fill(tileRect)
                    let result = results.first(where: { $0.index == bubble.index })
                    let header = "B\(bubble.index) \(bubble.source) sim \(Int(((result?.bestSimilarity ?? 0) * 100).rounded()))%"
                    drawText(header, in: CGRect(x: tileRect.minX, y: tileRect.minY, width: tileRect.width, height: 23), fontSize: 13, textColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1), backgroundColor: CGColor(red: 0.1, green: 0.36, blue: 0.74, alpha: 0.9), context: context)
                    UIImage(cgImage: processed).draw(in: aspectFitRect(imageSize: CGSize(width: processed.width, height: processed.height), bounds: CGRect(x: tileRect.minX, y: tileRect.minY + 26, width: tileRect.width, height: tileRect.height - 76)))
                    let text = result?.text ?? ""
                    drawText(text.isEmpty ? "<no OCR>" : text, in: CGRect(x: tileRect.minX, y: tileRect.maxY - 48, width: tileRect.width, height: 46), fontSize: 10, textColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1), backgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 0.84), context: context)
                } catch {
                    renderError = error
                }
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

    private static func drawBubbleTextOverlay(on image: CGImage, results: [MangaOverlayBubbleResult]) throws -> CGImage {
        try draw(on: image) { context, _ in
            let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            for result in results {
                let rect = rect(from: result.bbox)
                context.setStrokeColor(CGColor(red: 0.05, green: 0.38, blue: 0.95, alpha: 0.95))
                context.setLineWidth(2)
                context.stroke(rect)

                let similarity = result.bestSimilarity.formatted(.number.precision(.fractionLength(3)))
                let text = "#\(result.index) bubble-first\nsim=\(similarity)\n\(result.text)"
                let textRect = expand(rect, by: 0.22, bounds: bounds)
                context.setFillColor(CGColor(red: 0.9, green: 0.95, blue: 1, alpha: 0.9))
                context.fill(textRect)
                drawFittingText(text, in: textRect.insetBy(dx: 4, dy: 4), context: context)
            }
        }
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

    private static func drawOCRTextOverlay(on image: CGImage, blocks: [MangaOverlayProbeBlock]) throws -> CGImage {
        try draw(on: image) { context, _ in
            for block in blocks {
                let rect = rect(from: block.bbox)
                context.setStrokeColor(CGColor(red: 0.05, green: 0.35, blue: 1, alpha: 0.9))
                context.setLineWidth(2)
                context.stroke(rect)

                let text = "#\(block.index) raw:\n\(block.rawOcrText)\npre:\n\(block.afterPreprocessingOcrText ?? "<off/no change>")"
                let textRect = expand(rect, by: 0.2, bounds: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.86))
                context.fill(textRect)
                drawFittingText(text, in: textRect.insetBy(dx: 4, dy: 4), context: context)
            }
        }
    }

    private static func drawDeterministicCorrectionOverlay(on image: CGImage, blocks: [MangaOverlayProbeBlock]) throws -> CGImage {
        try draw(on: image) { context, _ in
            let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            for block in blocks {
                let rect = rect(from: block.bbox)
                let changed = !block.deterministicCorrectionAppliedRules.isEmpty
                context.setStrokeColor(changed
                    ? CGColor(red: 0.58, green: 0.12, blue: 0.92, alpha: 0.95)
                    : CGColor(red: 0.36, green: 0.36, blue: 0.36, alpha: 0.65)
                )
                context.setLineWidth(changed ? 2.5 : 1.5)
                context.stroke(rect)

                let originalSimilarity = block.ocrGroundTruthSimilarity.map {
                    $0.formatted(.number.precision(.fractionLength(3)))
                } ?? "n/a"
                let correctedSimilarity = block.deterministicCorrectionSimilarity.map {
                    $0.formatted(.number.precision(.fractionLength(3)))
                } ?? "n/a"
                let rules = block.deterministicCorrectionAppliedRules.isEmpty
                    ? "rules: <none>"
                    : "rules: \(block.deterministicCorrectionAppliedRules.joined(separator: ", "))"
                let correctedText = block.deterministicCorrectionText ?? block.finalTextUsedForTranslation
                let text = "#\(block.index) deterministic OCR\nsim: \(originalSimilarity) -> \(correctedSimilarity)\nraw:\n\(block.finalTextUsedForTranslation)\nfix:\n\(correctedText)\n\(rules)"
                let textRect = expand(rect, by: changed ? 0.32 : 0.22, bounds: bounds)
                context.setFillColor(changed
                    ? CGColor(red: 0.97, green: 0.92, blue: 1, alpha: 0.9)
                    : CGColor(red: 1, green: 1, blue: 1, alpha: 0.8)
                )
                context.fill(textRect)
                drawFittingText(text, in: textRect.insetBy(dx: 4, dy: 4), context: context)
            }
        }
    }

    private static func drawDeterministicTranslationOverlay(on image: CGImage, blocks: [MangaOverlayProbeBlock]) throws -> CGImage {
        try draw(on: image) { context, _ in
            let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            for block in blocks {
                guard block.deterministicCorrectionTranslationPassed != nil else { continue }
                let rect = rect(from: block.bbox)
                let passed = block.deterministicCorrectionTranslationPassed == true
                context.setStrokeColor(passed
                    ? CGColor(red: 0.05, green: 0.55, blue: 0.25, alpha: 0.95)
                    : CGColor(red: 0.85, green: 0.16, blue: 0.18, alpha: 0.95)
                )
                context.setLineWidth(2.5)
                context.stroke(rect)

                let correctedText = block.deterministicCorrectionText ?? ""
                let candidate = block.deterministicCorrectionTranslationCandidate ?? ""
                let failure = block.deterministicCorrectionTranslationFailureDetail ?? "passed"
                let text = "#\(block.index) deterministic translation\nfix:\n\(correctedText)\ntranslation:\n\(candidate)\n\(failure)"
                let textRect = expand(rect, by: 0.34, bounds: bounds)
                context.setFillColor(passed
                    ? CGColor(red: 0.9, green: 1, blue: 0.93, alpha: 0.9)
                    : CGColor(red: 1, green: 0.92, blue: 0.92, alpha: 0.9)
                )
                context.fill(textRect)
                drawFittingText(text, in: textRect.insetBy(dx: 4, dy: 4), context: context)
            }
        }
    }

    private static func drawBlockCrops(
        from image: CGImage,
        blocks: [MangaOverlayProbeBlock],
        preprocessing: MangaOverlayPreprocessingOptions
    ) throws -> CGImage {
        let tileWidth: CGFloat = 260
        let tileHeight: CGFloat = 220
        let columns = 2
        let rows = max(1, Int(ceil(Double(blocks.count) / Double(columns))))
        let canvasSize = CGSize(width: tileWidth * CGFloat(columns), height: tileHeight * CGFloat(rows))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        var renderError: Error?
        let rendered = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.setFillColor(CGColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1))
            context.fill(CGRect(origin: .zero, size: canvasSize))

            for (offset, block) in blocks.enumerated() {
                let column = offset % columns
                let row = offset / columns
                let origin = CGPoint(x: CGFloat(column) * tileWidth, y: CGFloat(row) * tileHeight)
                let tileRect = CGRect(x: origin.x + 8, y: origin.y + 8, width: tileWidth - 16, height: tileHeight - 16)
                do {
                    let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
                    let cropRect = expand(rect(from: block.bbox), by: 0.25, bounds: bounds).integral
                    let cropped = try croppedImage(image, rect: cropRect)
                    let processed = preprocessing.enabled ? try preprocessedImage(cropped, options: preprocessing) : cropped
                    let cropImage = UIImage(cgImage: processed)
                    let imageRect = CGRect(x: tileRect.minX, y: tileRect.minY + 28, width: tileRect.width, height: tileRect.height - 62)
                    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                    context.fill(tileRect)
                    drawText("#\(block.index)", in: CGRect(x: tileRect.minX, y: tileRect.minY, width: 80, height: 24), fontSize: 16, textColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1), backgroundColor: CGColor(red: 1, green: 0.08, blue: 0.18, alpha: 0.88), context: context)
                    cropImage.draw(in: aspectFitRect(imageSize: CGSize(width: processed.width, height: processed.height), bounds: imageRect))
                    drawText(block.afterPreprocessingOcrText ?? block.rawOcrText, in: CGRect(x: tileRect.minX, y: tileRect.maxY - 32, width: tileRect.width, height: 30), fontSize: 11, textColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1), backgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 0.82), context: context)
                } catch {
                    renderError = error
                }
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

    private static func aspectFitRect(imageSize: CGSize, bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
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
