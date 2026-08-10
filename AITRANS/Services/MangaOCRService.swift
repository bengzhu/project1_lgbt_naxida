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

    private var runtime: MangaOCRRuntime?

    func recognize(
        image: CGImage,
        requests: [MangaOCRRequest]
    ) throws -> [MangaOCRResult] {
        guard !requests.isEmpty else { return [] }
        let runtime = try loadedRuntime()
        var results: [MangaOCRResult] = []
        results.reserveCapacity(requests.count)

        for request in requests {
            try Task.checkCancellation()
            guard let crop = Self.cropImage(image, normalizedRect: request.cropRect) else {
                continue
            }
            do {
                let recognition = try runtime.recognize(crop)
                guard Self.containsJapaneseLetter(recognition.text) else { continue }
                results.append(
                    MangaOCRResult(
                        text: recognition.text,
                        confidence: recognition.confidence,
                        textRect: request.textRect
                    )
                )
            } catch is CancellationError {
                // A user cancellation must stop the whole bounded batch.
                throw CancellationError()
            } catch {
                // One malformed crop or model output must not discard good regions.
                continue
            }
        }
        return results
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
    private static let vocabularySize = 6_144
    private static let decoderStartToken = 2
    private static let decoderEndToken = 3
    private static let maximumTokens = 300

    private let encoder: MLModel
    private let decoder: MLModel
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
        let planeSize = imageSize * imageSize
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

        let values = try MLMultiArray(
            shape: [1, 3, NSNumber(value: imageSize), NSNumber(value: imageSize)],
            dataType: .float32
        )
        let pointer = values.dataPointer.bindMemory(
            to: Float.self,
            capacity: planeSize * 3
        )
        for index in 0..<planeSize {
            let normalized = Float(grayscale[index]) / 127.5 - 1
            pointer[index] = normalized
            pointer[planeSize + index] = normalized
            pointer[planeSize * 2 + index] = normalized
        }
        return values
    }

    private static func makeInputIDs(_ tokens: [Int]) throws -> MLMultiArray {
        let values = try MLMultiArray(
            shape: [1, NSNumber(value: tokens.count)],
            dataType: .int32
        )
        let pointer = values.dataPointer.bindMemory(to: Int32.self, capacity: tokens.count)
        for (index, token) in tokens.enumerated() {
            pointer[index] = Int32(token)
        }
        return values
    }

    private static func nextToken(
        in logits: MLMultiArray
    ) throws -> (id: Int, probability: Double) {
        guard logits.dataType == .float32, logits.count == vocabularySize else {
            throw MangaOCRServiceError.modelOutputMissing("next_token_logits")
        }
        let pointer = logits.dataPointer.bindMemory(to: Float.self, capacity: logits.count)
        var bestIndex = 0
        var bestLogit = pointer[0]
        for index in 1..<logits.count where pointer[index] > bestLogit {
            bestIndex = index
            bestLogit = pointer[index]
        }
        var denominator = 0.0
        for index in 0..<logits.count {
            denominator += exp(Double(pointer[index] - bestLogit))
        }
        let probability = denominator.isFinite && denominator > 0 ? 1 / denominator : 0
        return (bestIndex, probability)
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
