import Combine
import Foundation
import Translation

enum TranslationEngineRoutingError: LocalizedError, Sendable {
    case requiresIOS18
    case unsupportedTask(ModelTask)
    case unsupportedLanguagePair(SupportedLanguage, SupportedLanguage)
    case reservedEngine(ModelEngine)
    case requestAlreadyRunning
    case malformedMangaBatch
    case timedOut

    var errorDescription: String? {
        switch self {
        case .requiresIOS18:
            "Apple Translation 需要 iOS 18 或更高版本。"
        case .unsupportedTask(let task):
            "Apple Translation 不支持 \(task.rawValue) 任务。"
        case .unsupportedLanguagePair(let source, let target):
            "Apple Translation 不支持 \(source.rawValue)到\(target.rawValue)的翻译。"
        case .reservedEngine(let engine):
            "\(engine.selectionTitle) 尚未接入，仅保留配置入口。"
        case .requestAlreadyRunning:
            "Apple Translation 正在处理上一条请求，请稍后重试。"
        case .malformedMangaBatch:
            "漫画批翻译输入缺少有效的文字块编号。"
        case .timedOut:
            "Apple Translation 长时间没有响应，请确认语言包已安装后重试。"
        }
    }
}

struct ReservedTranslationService: LocalLanguageModeling {
    let metadata: ModelAdapterMetadata

    init(engine: ModelEngine) {
        metadata = ModelAdapterMetadata(
            engine: engine,
            displayName: engine.displayName,
            modelName: "预留适配器",
            quantization: "未接入",
            supportsStreaming: false
        )
    }

    func prepare() async throws {
        throw TranslationEngineRoutingError.reservedEngine(metadata.engine)
    }

    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResult {
        throw TranslationEngineRoutingError.reservedEngine(metadata.engine)
    }
}

struct AppleTranslationPayload: Identifiable, Equatable, Sendable {
    let id: String
    let sourceText: String
    let outputPrefix: String?
}

struct AppleTranslationJob: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceLanguage: SupportedLanguage
    let targetLanguage: SupportedLanguage
    let invalidatesConfiguration: Bool
    let payloads: [AppleTranslationPayload]
    let startedAt: Date
}

/// `TranslationSession` instances are supplied by SwiftUI's `translationTask`
/// modifier, so this adapter owns the request/continuation boundary while the
/// root view only supplies the system session. Product callers continue to use
/// the same `ModelGenerationRequest` / `ModelGenerationResult` contract as
/// Gemma.
@MainActor
final class AppleTranslationService: ObservableObject {
    let metadata = ModelAdapterMetadata(
        engine: .appleTranslation,
        displayName: "Apple Translation",
        modelName: "系统原生离线翻译",
        quantization: "Apple 系统语言模型",
        supportsStreaming: false
    )

    @Published private(set) var pendingJob: AppleTranslationJob?

    private var continuation: CheckedContinuation<ModelGenerationResult, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var invalidatesNextConfiguration = false

    func prepare() async throws {
        guard #available(iOS 18.0, *) else {
            throw TranslationEngineRoutingError.requiresIOS18
        }
    }

    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResult {
        guard request.task == .translation else {
            throw TranslationEngineRoutingError.unsupportedTask(request.task)
        }
        try await prepare()
        guard pendingJob == nil, continuation == nil else {
            throw TranslationEngineRoutingError.requestAlreadyRunning
        }

        let jobPayloads = try payloads(for: request)
        invalidatesNextConfiguration.toggle()
        let job = AppleTranslationJob(
            id: UUID(),
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            invalidatesConfiguration: invalidatesNextConfiguration,
            payloads: jobPayloads,
            startedAt: .now
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                pendingJob = job
                scheduleTimeout(for: job.id)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel(jobID: job.id)
            }
        }
    }

    func cancelPendingRequest() {
        guard let jobID = pendingJob?.id else { return }
        cancel(jobID: jobID)
    }

    @available(iOS 18.0, *)
    var configuration: TranslationSession.Configuration? {
        guard let job = pendingJob else { return nil }
        var configuration = TranslationSession.Configuration(
            source: job.sourceLanguage.appleTranslationLanguage,
            target: job.targetLanguage.appleTranslationLanguage
        )
        // SwiftUI compares configurations by language pair and version. Toggle
        // the version for each accepted job so consecutive requests using the
        // same languages always restart `translationTask`.
        if job.invalidatesConfiguration {
            configuration.invalidate()
        }
        return configuration
    }

    @available(iOS 18.0, *)
    func runPendingJob(with session: sending TranslationSession) async {
        guard let job = pendingJob else { return }

        do {
            let result = try await Self.translate(job: job, with: session)
            finish(jobID: job.id, result: .success(result))
        } catch {
            finish(jobID: job.id, result: .failure(error))
        }
    }

    @available(iOS 18.0, *)
    nonisolated private static func translate(
        job: AppleTranslationJob,
        with session: sending TranslationSession
    ) async throws -> ModelGenerationResult {
        let source = job.sourceLanguage.appleTranslationLanguage
        let target = job.targetLanguage.appleTranslationLanguage
        let availability = await LanguageAvailability().status(from: source, to: target)
        guard availability != .unsupported else {
            throw TranslationEngineRoutingError.unsupportedLanguagePair(
                job.sourceLanguage,
                job.targetLanguage
            )
        }

        try await session.prepareTranslation()
        let translatedTexts: [String]
        if job.payloads.count == 1, let payload = job.payloads.first {
            translatedTexts = [try await session.translate(payload.sourceText).targetText]
        } else {
            let requests = job.payloads.map {
                TranslationSession.Request(
                    sourceText: $0.sourceText,
                    clientIdentifier: $0.id
                )
            }
            var responseByID: [String: String] = [:]
            for try await response in session.translate(batch: requests) {
                if let clientIdentifier = response.clientIdentifier {
                    responseByID[clientIdentifier] = response.targetText
                }
            }
            translatedTexts = try job.payloads.map { payload in
                guard let text = responseByID[payload.id] else {
                    throw TranslationEngineRoutingError.malformedMangaBatch
                }
                return text
            }
        }

        let output = zip(job.payloads, translatedTexts).map { payload, translatedText in
            if let prefix = payload.outputPrefix {
                return "\(prefix) \(translatedText)"
            }
            return translatedText
        }.joined(separator: "\n")
        return ModelGenerationResult(
            text: output,
            summary: nil,
            engineName: "Apple Translation",
            tokenCount: nil,
            durationMilliseconds: Int(Date.now.timeIntervalSince(job.startedAt) * 1_000)
        )
    }

    private func payloads(for request: ModelGenerationRequest) throws -> [AppleTranslationPayload] {
        guard request.translationProfile == .mangaBlocks else {
            return [
                AppleTranslationPayload(
                    id: UUID().uuidString,
                    sourceText: request.inputText,
                    outputPrefix: nil
                )
            ]
        }

        let payloads = request.inputText
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> AppleTranslationPayload? in
                let value = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard value.first == "[",
                      let closingBracket = value.firstIndex(of: "]") else {
                    return nil
                }
                let prefix = String(value[...closingBracket])
                let text = String(value[value.index(after: closingBracket)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return AppleTranslationPayload(
                    id: prefix,
                    sourceText: text,
                    outputPrefix: prefix
                )
            }
        guard !payloads.isEmpty else {
            throw TranslationEngineRoutingError.malformedMangaBatch
        }
        return payloads
    }

    private func cancel(jobID: UUID) {
        finish(jobID: jobID, result: .failure(CancellationError()))
    }

    private func scheduleTimeout(for jobID: UUID) {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.requestTimeoutSeconds))
            } catch {
                return
            }
            self?.finish(
                jobID: jobID,
                result: .failure(TranslationEngineRoutingError.timedOut)
            )
        }
    }

    private static var requestTimeoutSeconds: Int {
#if DEBUG
        if let rawValue = ProcessInfo.processInfo.environment["AITRANS_APPLE_TRANSLATION_TIMEOUT_SECONDS"],
           let value = Int(rawValue), value > 0 {
            return value
        }
#endif
        return 300
    }

    private func finish(jobID: UUID, result: Result<ModelGenerationResult, Error>) {
        guard pendingJob?.id == jobID, let continuation else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        self.continuation = nil
        pendingJob = nil
        continuation.resume(with: result)
    }
}

private extension SupportedLanguage {
    var appleTranslationLanguage: Locale.Language {
        switch self {
        case .englishUS:
            Locale.Language(identifier: "en-US")
        case .simplifiedChinese:
            Locale.Language(identifier: "zh-Hans")
        case .japanese:
            Locale.Language(identifier: "ja")
        case .french:
            Locale.Language(identifier: "fr")
        case .german:
            Locale.Language(identifier: "de")
        }
    }
}
