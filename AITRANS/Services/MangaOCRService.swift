import CoreGraphics
import CoreML
import Foundation

struct MangaOCRRequest: Sendable {
    var textRect: ImageOCRLayoutRect
    var cropRect: ImageOCRLayoutRect
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

    private var runtime: MangaOCRRuntime?

    func recognize(
        image: CGImage,
        requests: [MangaOCRRequest]
    ) throws -> [MangaOCRResult] {
        guard !requests.isEmpty else { return [] }
        let runtime = try loadedRuntime()
        var results: [MangaOCRResult] = []
        results.reserveCapacity(requests.count)

        var croppedRequests: [(request: MangaOCRRequest, crop: CGImage)] = []
        croppedRequests.reserveCapacity(requests.count)
        for request in requests {
            try Task.checkCancellation()
            guard let crop = Self.cropImage(image, normalizedRect: request.cropRect) else {
                continue
            }
            croppedRequests.append((request, crop))
        }

        for start in stride(from: 0, to: croppedRequests.count, by: Self.maximumBatchSize) {
            try Task.checkCancellation()
            let end = min(start + Self.maximumBatchSize, croppedRequests.count)
            let chunk = Array(croppedRequests[start..<end])

            if runtime.supportsBatchInference {
                do {
                    let recognitions = try runtime.recognizeBatch(
                        chunk.map { $0.crop }
                    )
                    guard recognitions.count == chunk.count else {
                        throw MangaOCRServiceError.modelOutputMissing(
                            "batched recognition row count"
                        )
                    }
                    for (entry, recognition) in zip(chunk, recognitions) {
                        Self.appendJapaneseResult(
                            recognition,
                            request: entry.request,
                            to: &results
                        )
                    }
                    continue
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // A bad batch falls back to isolated crops below so one row
                    // cannot hide otherwise valid Japanese regions.
                }
            }

            for entry in chunk {
                try Task.checkCancellation()
                do {
                    let recognition = try runtime.recognize(entry.crop)
                    Self.appendJapaneseResult(
                        recognition,
                        request: entry.request,
                        to: &results
                    )
                } catch is CancellationError {
                    // A user cancellation must stop the whole bounded batch.
                    throw CancellationError()
                } catch {
                    // One malformed crop or model output must not discard good regions.
                    continue
                }
            }
        }
        return results
    }

    private static func appendJapaneseResult(
        _ recognition: (text: String, confidence: Float),
        request: MangaOCRRequest,
        to results: inout [MangaOCRResult]
    ) {
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

    private static func containsJapaneseLetter(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3041...0x3096, 0x30A1...0x30FA, 0x30FD...0x30FF,
                 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                 0xFF66...0xFF9D:
                true
            default:
                false
            }
        }
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
        for _ in 1..<Self.maximumTokens {
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

        for _ in 1..<Self.maximumTokens {
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
        var output = ""
        var dotCount = 0
        for character in noWhitespace.replacing("…", with: "...") {
            if character == "." || character == "・" {
                dotCount += 1
                continue
            }
            if dotCount > 0 {
                output.append(String(repeating: ".", count: dotCount))
                dotCount = 0
            }
            if let scalar = character.unicodeScalars.first,
               character.unicodeScalars.count == 1,
               scalar.value >= 0x21,
               scalar.value <= 0x7E,
               let fullwidth = UnicodeScalar(scalar.value + 0xFEE0) {
                output.unicodeScalars.append(fullwidth)
            } else {
                output.append(character)
            }
        }
        if dotCount > 0 {
            output.append(String(repeating: ".", count: dotCount))
        }
        return output
    }
}
