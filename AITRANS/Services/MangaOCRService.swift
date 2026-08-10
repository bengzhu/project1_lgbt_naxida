import CoreGraphics
import CoreImage
import CoreML
import Foundation

enum MangaOCRCropOrientation: Int, Sendable {
    case natural = 0
    /// Koharu's vertical `warp_line_region` feeds Manga OCR after rotate270.
    case koharuVertical270 = 270
}

struct MangaOCRRequest: Sendable {
    var textRect: ImageOCRLayoutRect
    var cropRect: ImageOCRLayoutRect
    /// Orientation for the detector bbox crop. Ownership geometry remains in
    /// `textRect`/`cropRect`; this only changes pixels presented to the model.
    var cropOrientation: MangaOCRCropOrientation
    /// Optional Koharu `line_polygon` equivalent. The detector/layout rectangle
    /// remains the ownership geometry and is always the safe fallback.
    var cropQuad: ImageOCRLayoutQuad?
    /// Only the strict Japanese vertical detector hint uses Koharu's bounded
    /// target canvas and rotate270 orientation. Unmarked quads retain the
    /// historical natural perspective crop for compatibility with callers that
    /// use a quad as a generic content fallback.
    var cropQuadIsVertical: Bool

    init(
        textRect: ImageOCRLayoutRect,
        cropRect: ImageOCRLayoutRect,
        cropOrientation: MangaOCRCropOrientation = .natural,
        cropQuad: ImageOCRLayoutQuad? = nil,
        cropQuadIsVertical: Bool = false
    ) {
        self.textRect = textRect
        self.cropRect = cropRect
        self.cropOrientation = cropOrientation
        self.cropQuad = cropQuad
        self.cropQuadIsVertical = cropQuadIsVertical
    }
}

struct MangaOCRResult: Sendable {
    var text: String
    var confidence: Float
    var textRect: ImageOCRLayoutRect
}

enum MangaOCRServiceError: LocalizedError {
    case imageDecodeFailed
    case modelResourceMissing(String)
    case modelOutputMissing(String)
    case vocabularyInvalid

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:
            "无法为 Manga OCR 解码图片。"
        case .modelResourceMissing(let name):
            "Manga OCR 模型资源缺失：\(name)。"
        case .modelOutputMissing(let name):
            "Manga OCR 模型输出缺失：\(name)。"
        case .vocabularyInvalid:
            "Manga OCR 词表无效。"
        }
    }
}

/// Serializes the bundled Core ML encoder/decoder and keeps both models warm
/// across image requests. CPU-only execution avoids the current Metal graph
/// failure for linearly quantized decoder masks while retaining bounded memory.
actor MangaOCRService {
    static let shared = MangaOCRService()
    private static let maximumBatchSize = 4
    private static let preferredCropConfidence: Float = 0.55
    private static let preferredJapaneseScriptDensity = 0.5
    private static let maximumQuadWarpDimension = 4_096
    private static let maximumQuadWarpPixels: CGFloat = 4_000_000

    private typealias Recognition = (text: String, confidence: Float)

    private struct CroppedRequest {
        var request: MangaOCRRequest
        var primaryBoundingBoxCrop: CGImage
        var lineQuadFallbackCrop: CGImage?
    }

    private var runtime: MangaOCRRuntime?

    func recognize(
        image: CGImage,
        requests: [MangaOCRRequest]
    ) throws -> [MangaOCRResult] {
        guard !requests.isEmpty else { return [] }
        let runtime = try loadedRuntime()
        var results: [MangaOCRResult] = []
        results.reserveCapacity(requests.count)

        var croppedRequests: [CroppedRequest] = []
        croppedRequests.reserveCapacity(requests.count)
        for request in requests {
            try Task.checkCancellation()
            guard let cropped = Self.cropImages(image, request: request) else {
                continue
            }
            croppedRequests.append(cropped)
        }

        for start in stride(from: 0, to: croppedRequests.count, by: Self.maximumBatchSize) {
            try Task.checkCancellation()
            let end = min(start + Self.maximumBatchSize, croppedRequests.count)
            let chunk = Array(croppedRequests[start..<end])

            let primaryRecognitions = try recognizeCrops(
                chunk.map(\.primaryBoundingBoxCrop),
                runtime: runtime
            )
            let fallbackIndexes = chunk.indices.filter { index in
                chunk[index].lineQuadFallbackCrop != nil
                    && Self.shouldRetryLineQuad(after: primaryRecognitions[index])
            }
            let fallbackCrops = fallbackIndexes.compactMap {
                chunk[$0].lineQuadFallbackCrop
            }
            let fallbackRecognitions = try recognizeCrops(
                fallbackCrops,
                runtime: runtime
            )
            var fallbackByIndex: [Int: Recognition] = [:]
            fallbackByIndex.reserveCapacity(fallbackIndexes.count)
            for (offset, index) in fallbackIndexes.enumerated() {
                if let recognition = fallbackRecognitions[offset] {
                    fallbackByIndex[index] = recognition
                }
            }

            for index in chunk.indices {
                let recognition = Self.preferredRecognition(
                    boundingBox: primaryRecognitions[index],
                    lineQuadFallback: fallbackByIndex[index]
                )
                Self.appendJapaneseResult(
                    recognition,
                    request: chunk[index].request,
                    to: &results
                )
            }
        }
        return results
    }

    /// Batch first, then isolate failures per crop. The same routine is used
    /// for primary Koharu bboxes and the smaller set of weak-result line retries.
    private func recognizeCrops(
        _ crops: [CGImage],
        runtime: MangaOCRRuntime
    ) throws -> [Recognition?] {
        guard !crops.isEmpty else { return [] }
        if runtime.supportsBatchInference {
            do {
                let recognitions = try runtime.recognizeBatch(crops)
                guard recognitions.count == crops.count else {
                    throw MangaOCRServiceError.modelOutputMissing(
                        "batched recognition row count"
                    )
                }
                return recognitions.map { Optional.some($0) }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A bad batch falls back to isolated crops below so one row
                // cannot hide otherwise valid Japanese regions.
                // Do not let a simultaneous cancellation be hidden by a Core ML
                // error before falling back to isolated crops.
                try Task.checkCancellation()
            }
        }

        var recognitions: [Recognition?] = []
        recognitions.reserveCapacity(crops.count)
        for crop in crops {
            try Task.checkCancellation()
            do {
                recognitions.append(try runtime.recognize(crop))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // One malformed crop or model output must not discard good regions.
                try Task.checkCancellation()
                recognitions.append(nil)
            }
        }
        return recognitions
    }

    /// Exposes the loaded model shape to the runtime harness without making
    /// Core ML models or mutable runtime state part of the app-facing API.
    func batchInferenceEnabled() throws -> Bool {
        try loadedRuntime().supportsBatchInference
    }

    private static func appendJapaneseResult(
        _ recognition: Recognition?,
        request: MangaOCRRequest,
        to results: inout [MangaOCRResult]
    ) {
        guard let recognition else { return }
        guard containsJapaneseLetter(recognition.text) else { return }
        results.append(
            MangaOCRResult(
                text: recognition.text,
                confidence: recognition.confidence,
                textRect: request.textRect
            )
        )
    }

    private func loadedRuntime() throws -> MangaOCRRuntime {
        if let runtime {
            return runtime
        }
        let loaded = try MangaOCRRuntime(bundle: .main)
        runtime = loaded
        return loaded
    }

    /// Koharu's Manga OCR consumes the expanded detector bbox. Keep it primary so
    /// a valid but misplaced line quad cannot assign a neighboring Japanese column
    /// to this detector owner. A strictly gated quad remains a weak-bbox fallback.
    private static func cropImages(
        _ image: CGImage,
        request: MangaOCRRequest
    ) -> CroppedRequest? {
        let boundingBoxCrop = cropImage(image, normalizedRect: request.cropRect)
            .map { orientedBoundingBoxCrop($0, orientation: request.cropOrientation) }
        let perspectiveCrop = request.cropQuad.flatMap {
            perspectiveCorrectedCrop(
                image,
                quad: $0,
                applyVerticalWarp: request.cropQuadIsVertical
            )
        }
        if let boundingBoxCrop {
            return CroppedRequest(
                request: request,
                primaryBoundingBoxCrop: boundingBoxCrop,
                lineQuadFallbackCrop: perspectiveCrop
            )
        }
        guard let perspectiveCrop else { return nil }
        return CroppedRequest(
            request: request,
            primaryBoundingBoxCrop: perspectiveCrop,
            lineQuadFallbackCrop: nil
        )
    }

    /// Keep the bbox primary while matching Koharu's vertical model-facing
    /// orientation. Rotation failure returns the natural crop, so a renderer
    /// or Core Graphics limitation cannot discard detector ownership.
    private static func orientedBoundingBoxCrop(
        _ crop: CGImage,
        orientation: MangaOCRCropOrientation
    ) -> CGImage {
        switch orientation {
        case .natural:
            return crop
        case .koharuVertical270:
            // RT-DETR ownership boxes can be broad even when their OCR result
            // is vertical. Rotate only a clearly line-like crop; a slightly
            // portrait detector bbox is still a multi-glyph ownership region
            // whose natural orientation is the recoverable model input.
            guard CGFloat(crop.height) > CGFloat(crop.width) * 1.75 else {
                return crop
            }
            return rotateImage270(crop) ?? crop
        }
    }

    private static func shouldRetryLineQuad(
        after recognition: Recognition?
    ) -> Bool {
        guard let recognition else { return true }
        return !isPreferredRecognition(recognition)
    }

    private static func preferredRecognition(
        boundingBox: Recognition?,
        lineQuadFallback: Recognition?
    ) -> Recognition? {
        let boundingBoxIsJapanese = boundingBox.map {
            containsJapaneseLetter($0.text)
        } ?? false
        let fallbackIsJapanese = lineQuadFallback.map {
            containsJapaneseLetter($0.text)
        } ?? false
        switch (boundingBoxIsJapanese, fallbackIsJapanese) {
        case (false, false):
            return nil
        case (true, false):
            return boundingBox
        case (false, true):
            return lineQuadFallback
        case (true, true):
            guard let boundingBox, let lineQuadFallback else { return boundingBox }
            let boundingBoxRank = recognitionQualityRank(boundingBox)
            let fallbackRank = recognitionQualityRank(lineQuadFallback)
            if fallbackRank != boundingBoxRank {
                return fallbackRank > boundingBoxRank ? lineQuadFallback : boundingBox
            }
            let boundingBoxConfidence = finiteConfidence(boundingBox.confidence)
            let fallbackConfidence = finiteConfidence(lineQuadFallback.confidence)
            if fallbackConfidence != boundingBoxConfidence {
                return fallbackConfidence > boundingBoxConfidence
                    ? lineQuadFallback
                    : boundingBox
            }
            return japaneseLetterCount(lineQuadFallback.text)
                > japaneseLetterCount(boundingBox.text)
                ? lineQuadFallback
                : boundingBox
        }
    }

    private static func finiteConfidence(_ confidence: Float) -> Float {
        confidence.isFinite ? confidence : -.infinity
    }

    private static func isPreferredRecognition(_ recognition: Recognition) -> Bool {
        recognition.confidence.isFinite
            && recognition.confidence >= preferredCropConfidence
            && containsJapaneseLetter(recognition.text)
            && japaneseScriptDensity(in: recognition.text)
                >= preferredJapaneseScriptDensity
    }

    private static func recognitionQualityRank(_ recognition: Recognition) -> Int {
        if isPreferredRecognition(recognition) { return 2 }
        return containsJapaneseLetter(recognition.text) ? 1 : 0
    }

    private static func cropImage(
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

    /// Port Koharu's `warp_line_region` boundary for detector-owned crops.
    /// Invalid or degenerate quads return nil so callers retain the proven bbox
    /// crop rather than losing a detector region.
    private static func perspectiveCorrectedCrop(
        _ image: CGImage,
        quad: ImageOCRLayoutQuad,
        applyVerticalWarp: Bool
    ) -> CGImage? {
        guard let normalizedQuad = quad.normalized() else { return nil }
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let points = normalizedQuad.points.map {
            CGPoint(x: $0.x * imageWidth, y: $0.y * imageHeight)
        }
        guard points.count == 4,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return nil
        }

        let imageBounds = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        let bounds = points.reduce(CGRect.null) { partial, point in
            partial.union(CGRect(origin: point, size: .zero))
        }.integral.intersection(imageBounds)
        guard bounds.width >= 2,
              bounds.height >= 2,
              bounds.width <= 4096,
              bounds.height <= 4096,
              let cropped = image.cropping(to: bounds) else {
            return nil
        }

        let localPoints = points.map {
            CGPoint(x: $0.x - bounds.minX, y: $0.y - bounds.minY)
        }
        let croppedHeight = CGFloat(cropped.height)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            return nil
        }
        let input = CIImage(cgImage: cropped)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(
            CIVector(cgPoint: CGPoint(
                x: localPoints[0].x,
                y: croppedHeight - localPoints[0].y
            )),
            forKey: "inputTopLeft"
        )
        filter.setValue(
            CIVector(cgPoint: CGPoint(
                x: localPoints[1].x,
                y: croppedHeight - localPoints[1].y
            )),
            forKey: "inputTopRight"
        )
        filter.setValue(
            CIVector(cgPoint: CGPoint(
                x: localPoints[2].x,
                y: croppedHeight - localPoints[2].y
            )),
            forKey: "inputBottomRight"
        )
        filter.setValue(
            CIVector(cgPoint: CGPoint(
                x: localPoints[3].x,
                y: croppedHeight - localPoints[3].y
            )),
            forKey: "inputBottomLeft"
        )
        guard let output = filter.outputImage else { return nil }
        let extent = output.extent.integral
        guard extent.width >= 2,
              extent.height >= 2,
              extent.width <= 4096,
              extent.height <= 4096 else {
            return nil
        }
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let rendered = context.createCGImage(output, from: extent) else {
            return nil
        }

        // Generic quad callers keep the natural projection. Only a strictly
        // gated Japanese vertical hint may change the model-facing orientation.
        guard applyVerticalWarp else { return rendered }

        // Koharu's vertical warp does not feed the projection's natural extent
        // directly to Manga OCR. It derives a bounded canvas from the quad's
        // long/short axes and rotates the line 270 degrees so the model sees
        // the original top-to-bottom column as a horizontal reading span.
        // This is only the strict Japanese line-quad fallback; the detector
        // bbox remains the primary crop and remains unrotated.
        guard let targetSize = koharuVerticalQuadWarpTargetSize(
            localPoints,
            maximumDimension: CGFloat(maximumQuadWarpDimension),
            maximumPixels: maximumQuadWarpPixels
        ) else {
            return rendered
        }
        let targetWidth = Int(targetSize.width.rounded())
        let targetHeight = Int(targetSize.height.rounded())
        guard targetWidth >= 2, targetHeight >= 2 else {
            return rendered
        }
        let bounded = rendered.width == targetWidth && rendered.height == targetHeight
            ? rendered
            : resizedImage(
                rendered,
                pixelWidth: targetWidth,
                pixelHeight: targetHeight
            )
        guard let bounded,
              let rotated = rotateImage270(bounded) else {
            // Natural projection is the compatibility fallback if either the
            // target canvas or the rotation renderer is unavailable.
            return rendered
        }
        return rotated
    }

    /// Match Koharu's `quad_axis_lengths` and vertical target canvas. The
    /// points are local image-space corners in top-left, top-right,
    /// bottom-right, bottom-left order.
    private static func koharuVerticalQuadWarpTargetSize(
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
              rawWidth > 0,
              rawHeight > 0 else {
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

    private static func resizedImage(
        _ image: CGImage,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> CGImage? {
        guard pixelWidth >= 2, pixelHeight >= 2 else { return nil }
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

    /// Return the Core Graphics equivalent of Koharu's `rotate270`.
    private static func rotateImage270(_ image: CGImage) -> CGImage? {
        let outputSize = CGSize(
            width: CGFloat(image.height),
            height: CGFloat(image.width)
        )
        guard let context = CGContext(
            data: nil,
            width: Int(outputSize.width),
            height: Int(outputSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.translateBy(x: 0, y: outputSize.height)
        context.rotate(by: -.pi / 2)
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )
        return context.makeImage()
    }

    private static func containsJapaneseLetter(_ text: String) -> Bool {
        japaneseLetterCount(text) > 0
    }

    private static func japaneseLetterCount(_ text: String) -> Int {
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
}

private struct MangaOCRRuntime {
    private static let imageSize = 224
    private static let encoderSequenceLength = 197
    private static let vocabularySize = 6_144
    private static let decoderStartToken = 2
    private static let decoderEndToken = 3
    private static let maximumTokens = 300

    private let encoder: MLModel
    private let decoder: MLModel
    private let batchEncoder: MLModel?
    private let batchDecoder: MLModel?
    private let vocabulary: [String]

    init(bundle: Bundle) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        encoder = try Self.loadModel(
            named: "MangaOCREncoderINT8",
            bundle: bundle,
            configuration: configuration
        )
        decoder = try Self.loadModel(
            named: "MangaOCRDecoderINT8",
            bundle: bundle,
            configuration: configuration
        )
        let optionalBatchEncoder = try? Self.loadModel(
            named: "MangaOCREncoderINT8Batch",
            bundle: bundle,
            configuration: configuration
        )
        let optionalBatchDecoder = try? Self.loadModel(
            named: "MangaOCRDecoderINT8Batch",
            bundle: bundle,
            configuration: configuration
        )
        if let optionalBatchEncoder, let optionalBatchDecoder {
            batchEncoder = optionalBatchEncoder
            batchDecoder = optionalBatchDecoder
        } else {
            batchEncoder = nil
            batchDecoder = nil
        }
        guard let vocabularyURL = bundle.url(
            forResource: "MangaOCRVocab",
            withExtension: "txt"
        ) else {
            throw MangaOCRServiceError.modelResourceMissing("MangaOCRVocab.txt")
        }
        let source = try String(contentsOf: vocabularyURL, encoding: .utf8)
        vocabulary = source.split(whereSeparator: \Character.isNewline).map(String.init)
        guard vocabulary.count == Self.vocabularySize else {
            throw MangaOCRServiceError.vocabularyInvalid
        }
    }

    var supportsBatchInference: Bool {
        batchEncoder != nil && batchDecoder != nil
    }

    func recognize(_ image: CGImage) throws -> (text: String, confidence: Float) {
        let pixels = try Self.makePixelValues(image)
        let encoderInput = try MLDictionaryFeatureProvider(
            dictionary: ["pixel_values": MLFeatureValue(multiArray: pixels)]
        )
        let encoderOutput = try encoder.prediction(from: encoderInput)
        guard let hiddenStates = encoderOutput
            .featureValue(for: "encoder_hidden_states")?
            .multiArrayValue else {
            throw MangaOCRServiceError.modelOutputMissing("encoder_hidden_states")
        }

        var tokens = [Self.decoderStartToken]
        var tokenLogProbabilities: [Double] = []
        tokenLogProbabilities.reserveCapacity(32)
        // Koharu's decoder performs max_length generation steps, including the
        // first step from the decoder start token.
        for _ in 0..<Self.maximumTokens {
            try Task.checkCancellation()
            let inputIDs = try Self.makeInputIDs(tokens)
            let decoderInput = try MLDictionaryFeatureProvider(
                dictionary: [
                    "input_ids": MLFeatureValue(multiArray: inputIDs),
                    "encoder_hidden_states": MLFeatureValue(multiArray: hiddenStates),
                ]
            )
            let decoderOutput = try decoder.prediction(from: decoderInput)
            guard let logits = decoderOutput
                .featureValue(for: "next_token_logits")?
                .multiArrayValue else {
                throw MangaOCRServiceError.modelOutputMissing("next_token_logits")
            }
            let prediction = try Self.nextToken(in: logits)
            tokens.append(prediction.id)
            if prediction.id >= 5 {
                tokenLogProbabilities.append(log(max(prediction.probability, 1e-12)))
            }
            if prediction.id == Self.decoderEndToken {
                break
            }
        }

        let decoded = tokens.compactMap { token -> String? in
            guard token >= 5, token < vocabulary.count else { return nil }
            return vocabulary[token]
        }
        .joined()
        let confidence = tokenLogProbabilities.isEmpty
            ? 0
            : exp(tokenLogProbabilities.reduce(0, +) / Double(tokenLogProbabilities.count))
        return (
            Self.postProcess(decoded),
            Float(min(max(confidence, 0), 1))
        )
    }

    func recognizeBatch(
        _ images: [CGImage]
    ) throws -> [(text: String, confidence: Float)] {
        guard !images.isEmpty,
              images.count <= 4,
              let batchEncoder,
              let batchDecoder else {
            throw MangaOCRServiceError.modelResourceMissing(
                "MangaOCREncoderINT8Batch.mlmodelc/MangaOCRDecoderINT8Batch.mlmodelc"
            )
        }

        let batch = images.count
        let pixels = try Self.makePixelValues(images)
        let encoderInput = try MLDictionaryFeatureProvider(
            dictionary: ["pixel_values": MLFeatureValue(multiArray: pixels)]
        )
        let encoderOutput = try batchEncoder.prediction(from: encoderInput)
        guard let hiddenStates = encoderOutput
            .featureValue(for: "encoder_hidden_states")?
            .multiArrayValue,
            hiddenStates.dataType == .float32,
            hiddenStates.count == batch * Self.encoderSequenceLength * 768 else {
            throw MangaOCRServiceError.modelOutputMissing("encoder_hidden_states")
        }

        var tokenRows = Array(
            repeating: [Self.decoderStartToken],
            count: batch
        )
        var logProbabilities = Array(repeating: [Double](), count: batch)
        var finished = Array(repeating: false, count: batch)

        for _ in 0..<Self.maximumTokens {
            try Task.checkCancellation()
            let inputIDs = try Self.makeInputIDs(tokenRows)
            let decoderInput = try MLDictionaryFeatureProvider(
                dictionary: [
                    "input_ids": MLFeatureValue(multiArray: inputIDs),
                    "encoder_hidden_states": MLFeatureValue(multiArray: hiddenStates),
                ]
            )
            let decoderOutput = try batchDecoder.prediction(from: decoderInput)
            guard let logits = decoderOutput
                .featureValue(for: "next_token_logits")?
                .multiArrayValue else {
                throw MangaOCRServiceError.modelOutputMissing("next_token_logits")
            }
            let predictions = try Self.nextTokens(in: logits, batch: batch)
            for index in 0..<batch where !finished[index] {
                let prediction = predictions[index]
                tokenRows[index].append(prediction.id)
                if prediction.id >= 5 {
                    logProbabilities[index].append(
                        log(max(prediction.probability, 1e-12))
                    )
                }
                if prediction.id == Self.decoderEndToken {
                    finished[index] = true
                }
            }
            if finished.allSatisfy({ $0 }) {
                break
            }
        }

        return tokenRows.enumerated().map { index, tokens in
            let decoded = tokens.compactMap { token -> String? in
                guard token >= 5, token < vocabulary.count else { return nil }
                return vocabulary[token]
            }
            .joined()
            let probabilities = logProbabilities[index]
            let confidence = probabilities.isEmpty
                ? 0
                : exp(probabilities.reduce(0, +) / Double(probabilities.count))
            return (
                Self.postProcess(decoded),
                Float(min(max(confidence, 0), 1))
            )
        }
    }

    private static func loadModel(
        named name: String,
        bundle: Bundle,
        configuration: MLModelConfiguration
    ) throws -> MLModel {
        guard let url = bundle.url(forResource: name, withExtension: "mlmodelc") else {
            throw MangaOCRServiceError.modelResourceMissing("\(name).mlmodelc")
        }
        return try MLModel(contentsOf: url, configuration: configuration)
    }

    private static func makePixelValues(_ image: CGImage) throws -> MLMultiArray {
        try makePixelValues([image])
    }

    private static func makePixelValues(_ images: [CGImage]) throws -> MLMultiArray {
        guard !images.isEmpty else {
            throw MangaOCRServiceError.imageDecodeFailed
        }
        let planeSize = imageSize * imageSize
        let grayscaleImages = try images.map { image in
            var grayscale = [UInt8](repeating: 0, count: planeSize)
            let rendered = grayscale.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(
                    data: bytes.baseAddress,
                    width: imageSize,
                    height: imageSize,
                    bitsPerComponent: 8,
                    bytesPerRow: imageSize,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                ) else {
                    return false
                }
                context.interpolationQuality = .high
                context.draw(
                    image,
                    in: CGRect(x: 0, y: 0, width: imageSize, height: imageSize)
                )
                return true
            }
            guard rendered else {
                throw MangaOCRServiceError.imageDecodeFailed
            }
            return grayscale
        }

        let values = try MLMultiArray(
            shape: [
                NSNumber(value: images.count),
                3,
                NSNumber(value: imageSize),
                NSNumber(value: imageSize),
            ],
            dataType: .float32
        )
        let pointer = values.dataPointer.bindMemory(
            to: Float.self,
            capacity: images.count * planeSize * 3
        )
        let imagePlaneSize = planeSize * 3
        for (imageIndex, grayscale) in grayscaleImages.enumerated() {
            let imageOffset = imageIndex * imagePlaneSize
            for index in 0..<planeSize {
                let normalized = Float(grayscale[index]) / 127.5 - 1
                pointer[imageOffset + index] = normalized
                pointer[imageOffset + planeSize + index] = normalized
                pointer[imageOffset + planeSize * 2 + index] = normalized
            }
        }
        return values
    }

    private static func makeInputIDs(_ tokens: [Int]) throws -> MLMultiArray {
        try makeInputIDs([tokens])
    }

    private static func makeInputIDs(_ tokenRows: [[Int]]) throws -> MLMultiArray {
        guard !tokenRows.isEmpty else {
            throw MangaOCRServiceError.modelOutputMissing("input_ids")
        }
        let sequenceLength = tokenRows.map(\.count).max() ?? 0
        guard sequenceLength > 0 else {
            throw MangaOCRServiceError.modelOutputMissing("input_ids")
        }
        let values = try MLMultiArray(
            shape: [
                NSNumber(value: tokenRows.count),
                NSNumber(value: sequenceLength),
            ],
            dataType: .int32
        )
        let pointer = values.dataPointer.bindMemory(
            to: Int32.self,
            capacity: tokenRows.count * sequenceLength
        )
        for (rowIndex, tokens) in tokenRows.enumerated() {
            let rowOffset = rowIndex * sequenceLength
            for index in 0..<sequenceLength {
                pointer[rowOffset + index] = Int32(
                    index < tokens.count ? tokens[index] : Self.decoderEndToken
                )
            }
        }
        return values
    }

    private static func nextToken(
        in logits: MLMultiArray
    ) throws -> (id: Int, probability: Double) {
        try nextTokens(in: logits, batch: 1)[0]
    }

    private static func nextTokens(
        in logits: MLMultiArray,
        batch: Int
    ) throws -> [(id: Int, probability: Double)] {
        guard batch > 0,
              logits.dataType == .float32,
              logits.count == batch * vocabularySize else {
            throw MangaOCRServiceError.modelOutputMissing("next_token_logits")
        }
        let pointer = logits.dataPointer.bindMemory(to: Float.self, capacity: logits.count)
        return (0..<batch).map { row in
            let offset = row * vocabularySize
            var bestIndex = 0
            var bestLogit = pointer[offset]
            for index in 1..<vocabularySize where pointer[offset + index] > bestLogit {
                bestIndex = index
                bestLogit = pointer[offset + index]
            }
            var denominator = 0.0
            for index in 0..<vocabularySize {
                denominator += exp(Double(pointer[offset + index] - bestLogit))
            }
            let probability = denominator.isFinite && denominator > 0 ? 1 / denominator : 0
            return (bestIndex, probability)
        }
    }

    private static func postProcess(_ text: String) -> String {
        let noWhitespace = text.filter { !$0.isWhitespace }
            .replacing("…", with: "...")
        var collapsed = ""
        var dotCount = 0

        func flushDots() {
            guard dotCount > 0 else { return }
            collapsed.append(contentsOf: String(repeating: ".", count: dotCount))
            dotCount = 0
        }

        for scalar in noWhitespace.unicodeScalars {
            if scalar.value == 0x2E || scalar.value == 0x30FB {
                dotCount += 1
                continue
            }
            flushDots()
            collapsed.unicodeScalars.append(scalar)
        }
        flushDots()

        var output = ""
        for scalar in collapsed.unicodeScalars {
            if scalar.value == 0x20,
               let fullwidthSpace = UnicodeScalar(0x3000) {
                output.unicodeScalars.append(fullwidthSpace)
            } else if (0x21...0x7E).contains(scalar.value),
                      let fullwidth = UnicodeScalar(scalar.value + 0xFEE0) {
                output.unicodeScalars.append(fullwidth)
            } else {
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }
}
