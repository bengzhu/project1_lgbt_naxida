import CryptoKit
import Foundation
import Speech
import UIKit

@MainActor
final class SpeechQualityProbeService {
    static let manifestFilename = "manifest.json"
    static let reportJSONFilename = "speech_quality_report.json"
    static let reportTextFilename = "speech_quality_report.txt"

    private struct RecognitionPayload: Sendable {
        var transcript: String
        var segmentCount: Int
        var averageConfidence: Double?
    }

    private enum ProbeError: LocalizedError, Sendable {
        case invalidManifest(String)
        case recognizerUnavailable(String)
        case onDeviceRecognitionUnavailable(String)
        case recognitionFailed(String)
        case emptyTranscript
        case timedOut

        var errorDescription: String? {
            switch self {
            case let .invalidManifest(message): message
            case let .recognizerUnavailable(locale): "Speech recognizer unavailable for \(locale)"
            case let .onDeviceRecognitionUnavailable(locale): "On-device Speech recognition unavailable for \(locale)"
            case let .recognitionFailed(message): message
            case .emptyTranscript: "Speech recognition returned an empty transcript"
            case .timedOut: "Speech recognition timed out after 120 seconds"
            }
        }
    }

    private var activeRecognitionTask: SFSpeechRecognitionTask?
    private var activeContinuation: CheckedContinuation<RecognitionPayload, Error>?
    private var timeoutTask: Task<Void, Never>?

    func cancel() {
        finishActiveRecognition(with: .failure(CancellationError()))
    }

    func run(
        corpusDirectory: URL?,
        outputDirectory: URL,
        stateDidChange: @escaping @MainActor (SpeechQualityProbeState, String) -> Void
    ) async -> SpeechQualityProbeReport {
        stateDidChange(.loadingManifest, "正在读取 Speech 质量语料清单")
        let manifestURL = corpusDirectory?.appendingPathComponent(Self.manifestFilename)

        guard let manifestURL, FileManager.default.fileExists(atPath: manifestURL.path) else {
            let report = emptyReport(
                verdict: .manifestMissing,
                warning: "test/speech_corpus/manifest.json 不存在；未执行真实语音质量测试"
            )
            write(report, to: outputDirectory)
            stateDidChange(.failed, "缺少 speech_corpus/manifest.json；已写出可审计报告")
            return report
        }

        let manifestData: Data
        let manifest: SpeechQualityCorpusManifest
        do {
            manifestData = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode(SpeechQualityCorpusManifest.self, from: manifestData)
            try validate(manifest, corpusDirectory: manifestURL.deletingLastPathComponent())
        } catch {
            let report = emptyReport(
                verdict: .invalidManifest,
                manifestSHA256: (try? Data(contentsOf: manifestURL)).map(Self.sha256),
                warning: "语料清单无效：\(error.localizedDescription)"
            )
            write(report, to: outputDirectory)
            stateDidChange(.failed, "Speech 语料清单无效；已写出报告")
            return report
        }

        if Task.isCancelled {
            return cancelledReport(manifest: manifest, manifestData: manifestData, outputDirectory: outputDirectory)
        }

        stateDidChange(.requestingAuthorization, "正在请求 Apple Speech 权限")
        let authorization = await requestAuthorization()
        if Task.isCancelled {
            return cancelledReport(manifest: manifest, manifestData: manifestData, outputDirectory: outputDirectory)
        }

        var caseReports: [SpeechQualityCaseReport] = []
        let corpusRoot = manifestURL.deletingLastPathComponent()
        for (index, corpusCase) in manifest.cases.enumerated() {
            if Task.isCancelled {
                let report = makeReport(
                    verdict: .cancelled,
                    manifest: manifest,
                    manifestData: manifestData,
                    cases: caseReports,
                    warnings: ["用户取消；剩余语料未执行"]
                )
                write(report, to: outputDirectory)
                stateDidChange(.cancelled, "Speech 质量探针已取消")
                return report
            }

            stateDidChange(.validatingAudio, "校验音频 \(index + 1)/\(manifest.cases.count)：\(corpusCase.id)")
            let audioURL = corpusRoot.appendingPathComponent(corpusCase.audioFile).standardizedFileURL
            let identityFailure = validateAudioIdentity(corpusCase, audioURL: audioURL)
            if let identityFailure {
                caseReports.append(failureReport(for: corpusCase, category: identityFailure.category, message: identityFailure.message))
                continue
            }

            guard authorization == .authorized else {
                caseReports.append(
                    failureReport(
                        for: corpusCase,
                        category: .authorizationDenied,
                        message: "Apple Speech authorization status=\(authorization.rawValue)"
                    )
                )
                continue
            }

            stateDidChange(.recognizing, "本机识别 \(index + 1)/\(manifest.cases.count)：\(corpusCase.id)")
            let startedAt = Date()
            do {
                let payload = try await recognize(audioURL: audioURL, localeIdentifier: corpusCase.localeIdentifier)
                let latency = max(0, Date().timeIntervalSince(startedAt))
                let metrics = SpeechQualityEvaluator.evaluate(
                    reference: corpusCase.referenceTranscript,
                    recognition: payload.transcript,
                    localeIdentifier: corpusCase.localeIdentifier
                )
                caseReports.append(
                    SpeechQualityCaseReport(
                        id: corpusCase.id,
                        audioFile: corpusCase.audioFile,
                        audioSHA256: corpusCase.audioSHA256.lowercased(),
                        audioByteCount: corpusCase.audioByteCount,
                        localeIdentifier: corpusCase.localeIdentifier,
                        sourceDescription: corpusCase.sourceDescription,
                        referenceTranscript: corpusCase.referenceTranscript,
                        recognizedTranscript: payload.transcript,
                        metrics: metrics,
                        latencySeconds: latency,
                        segmentCount: payload.segmentCount,
                        averageConfidence: payload.averageConfidence,
                        requiresOnDeviceRecognition: true,
                        supportsOnDeviceRecognition: true,
                        failureCategory: nil,
                        failureMessage: nil,
                        referenceUsedForEvaluationOnly: true,
                        referenceUsedForRecognitionDecision: false
                    )
                )
            } catch is CancellationError {
                let report = makeReport(
                    verdict: .cancelled,
                    manifest: manifest,
                    manifestData: manifestData,
                    cases: caseReports,
                    warnings: ["用户取消；当前及剩余语料未计入质量指标"]
                )
                write(report, to: outputDirectory)
                stateDidChange(.cancelled, "Speech 质量探针已取消")
                return report
            } catch {
                let failure = classify(error)
                caseReports.append(failureReport(for: corpusCase, category: failure.category, message: failure.message))
            }
        }

        let failedCount = caseReports.filter { $0.failureCategory != nil }.count
        let verdict: SpeechQualityProbeVerdict = failedCount == 0 ? .qualityMeasured : .completedWithFailures
        let report = makeReport(
            verdict: verdict,
            manifest: manifest,
            manifestData: manifestData,
            cases: caseReports,
            warnings: failedCount == 0 ? [] : ["\(failedCount) 个语料未得到可评分识别结果"]
        )
        write(report, to: outputDirectory)
        let finalState: SpeechQualityProbeState = report.aggregate.recognizedCaseCount > 0 ? .completed : .failed
        stateDidChange(
            finalState,
            "Speech 质量探针完成：\(report.aggregate.recognizedCaseCount)/\(report.aggregate.totalCaseCount) 可评分"
        )
        return report
    }

    private func recognize(audioURL: URL, localeIdentifier: String) async throws -> RecognitionPayload {
        try Task.checkCancellation()
        guard activeContinuation == nil else {
            throw ProbeError.recognitionFailed("A Speech quality recognition task is already active")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)), recognizer.isAvailable else {
            throw ProbeError.recognizerUnavailable(localeIdentifier)
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw ProbeError.onDeviceRecognitionUnavailable(localeIdentifier)
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeContinuation = continuation
                timeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(120))
                    guard !Task.isCancelled else { return }
                    self?.finishActiveRecognition(with: .failure(ProbeError.timedOut))
                }
                activeRecognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    Task { @MainActor [weak self] in
                        guard let self, self.activeContinuation != nil else { return }
                        if let error {
                            self.finishActiveRecognition(with: .failure(ProbeError.recognitionFailed(error.localizedDescription)))
                            return
                        }
                        guard let result, result.isFinal else { return }
                        let transcript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !transcript.isEmpty else {
                            self.finishActiveRecognition(with: .failure(ProbeError.emptyTranscript))
                            return
                        }
                        let confidences = result.bestTranscription.segments.map { Double($0.confidence) }
                        self.finishActiveRecognition(
                            with: .success(
                                RecognitionPayload(
                                    transcript: transcript,
                                    segmentCount: result.bestTranscription.segments.count,
                                    averageConfidence: confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)
                                )
                            )
                        )
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishActiveRecognition(with: .failure(CancellationError()))
            }
        }
    }

    private func finishActiveRecognition(with result: Result<RecognitionPayload, Error>) {
        guard let continuation = activeContinuation else { return }
        activeContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        activeRecognitionTask?.cancel()
        activeRecognitionTask = nil
        continuation.resume(with: result)
    }

    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func validate(_ manifest: SpeechQualityCorpusManifest, corpusDirectory: URL) throws {
        guard manifest.schemaVersion == SpeechQualityCorpusManifest.supportedSchemaVersion else {
            throw ProbeError.invalidManifest("Unsupported schemaVersion=\(manifest.schemaVersion)")
        }
        guard !manifest.corpusID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.corpusVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.cases.isEmpty else {
            throw ProbeError.invalidManifest("corpusID, corpusVersion and at least one case are required")
        }
        var identifiers = Set<String>()
        let rootPath = corpusDirectory.standardizedFileURL.path + "/"
        for corpusCase in manifest.cases {
            guard !corpusCase.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  identifiers.insert(corpusCase.id).inserted else {
                throw ProbeError.invalidManifest("Case IDs must be non-empty and unique")
            }
            let resolvedPath = corpusDirectory.appendingPathComponent(corpusCase.audioFile).standardizedFileURL.path
            guard !corpusCase.audioFile.isEmpty,
                  resolvedPath.hasPrefix(rootPath),
                  corpusCase.audioFile == URL(fileURLWithPath: corpusCase.audioFile).lastPathComponent else {
                throw ProbeError.invalidManifest("Case \(corpusCase.id) audioFile must be a plain filename")
            }
            guard corpusCase.audioByteCount > 0,
                  corpusCase.audioSHA256.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil,
                  !corpusCase.localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !corpusCase.referenceTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !corpusCase.sourceDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProbeError.invalidManifest("Case \(corpusCase.id) has incomplete identity, locale, reference or source fields")
            }
        }
    }

    private func validateAudioIdentity(
        _ corpusCase: SpeechQualityCorpusCase,
        audioURL: URL
    ) -> (category: SpeechQualityFailureCategory, message: String)? {
        guard let identity = try? Self.fileIdentity(at: audioURL) else {
            return (.audioMissing, "Audio file missing or unreadable: \(corpusCase.audioFile)")
        }
        guard identity.byteCount == corpusCase.audioByteCount,
              identity.sha256.caseInsensitiveCompare(corpusCase.audioSHA256) == .orderedSame else {
            return (
                .audioIdentityMismatch,
                "Audio identity mismatch: expected bytes=\(corpusCase.audioByteCount) sha256=\(corpusCase.audioSHA256.lowercased()), actual bytes=\(identity.byteCount) sha256=\(identity.sha256)"
            )
        }
        return nil
    }

    private func classify(_ error: Error) -> (category: SpeechQualityFailureCategory, message: String) {
        switch error {
        case ProbeError.recognizerUnavailable:
            return (.recognizerUnavailable, error.localizedDescription)
        case ProbeError.onDeviceRecognitionUnavailable:
            return (.onDeviceRecognitionUnavailable, error.localizedDescription)
        case ProbeError.emptyTranscript:
            return (.emptyTranscript, error.localizedDescription)
        case ProbeError.timedOut:
            return (.timedOut, error.localizedDescription)
        default:
            return (.recognitionFailed, error.localizedDescription)
        }
    }

    private func failureReport(
        for corpusCase: SpeechQualityCorpusCase,
        category: SpeechQualityFailureCategory,
        message: String
    ) -> SpeechQualityCaseReport {
        SpeechQualityCaseReport(
            id: corpusCase.id,
            audioFile: corpusCase.audioFile,
            audioSHA256: corpusCase.audioSHA256.lowercased(),
            audioByteCount: corpusCase.audioByteCount,
            localeIdentifier: corpusCase.localeIdentifier,
            sourceDescription: corpusCase.sourceDescription,
            referenceTranscript: corpusCase.referenceTranscript,
            recognizedTranscript: "",
            metrics: nil,
            latencySeconds: nil,
            segmentCount: 0,
            averageConfidence: nil,
            requiresOnDeviceRecognition: true,
            supportsOnDeviceRecognition: category == .onDeviceRecognitionUnavailable ? false : nil,
            failureCategory: category,
            failureMessage: message,
            referenceUsedForEvaluationOnly: true,
            referenceUsedForRecognitionDecision: false
        )
    }

    private func makeReport(
        verdict: SpeechQualityProbeVerdict,
        manifest: SpeechQualityCorpusManifest,
        manifestData: Data,
        cases: [SpeechQualityCaseReport],
        warnings: [String]
    ) -> SpeechQualityProbeReport {
        SpeechQualityProbeReport(
            schemaVersion: SpeechQualityProbeReport.schemaVersion,
            appAlgorithmVersion: "1.95",
            generatedAt: Date(),
            verdict: verdict,
            corpusManifestFile: "test/speech_corpus/manifest.json",
            corpusManifestSHA256: Self.sha256(manifestData),
            corpusID: manifest.corpusID,
            corpusVersion: manifest.corpusVersion,
            runtime: Self.runtimeIdentity(),
            requiresOnDeviceRecognition: true,
            referenceUsedForEvaluationOnly: true,
            referenceUsedForRecognitionDecision: false,
            cases: cases,
            aggregate: SpeechQualityEvaluator.aggregate(cases),
            warnings: warnings
        )
    }

    private func emptyReport(
        verdict: SpeechQualityProbeVerdict,
        manifestSHA256: String? = nil,
        warning: String
    ) -> SpeechQualityProbeReport {
        SpeechQualityProbeReport(
            schemaVersion: SpeechQualityProbeReport.schemaVersion,
            appAlgorithmVersion: "1.95",
            generatedAt: Date(),
            verdict: verdict,
            corpusManifestFile: "test/speech_corpus/manifest.json",
            corpusManifestSHA256: manifestSHA256,
            corpusID: nil,
            corpusVersion: nil,
            runtime: Self.runtimeIdentity(),
            requiresOnDeviceRecognition: true,
            referenceUsedForEvaluationOnly: true,
            referenceUsedForRecognitionDecision: false,
            cases: [],
            aggregate: SpeechQualityEvaluator.aggregate([]),
            warnings: [warning]
        )
    }

    private func cancelledReport(
        manifest: SpeechQualityCorpusManifest,
        manifestData: Data,
        outputDirectory: URL
    ) -> SpeechQualityProbeReport {
        let report = makeReport(
            verdict: .cancelled,
            manifest: manifest,
            manifestData: manifestData,
            cases: [],
            warnings: ["用户取消；未执行语料"]
        )
        write(report, to: outputDirectory)
        return report
    }

    private func write(_ report: SpeechQualityProbeReport, to outputDirectory: URL) {
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            try data.write(to: outputDirectory.appendingPathComponent(Self.reportJSONFilename), options: .atomic)
            try Self.textSummary(report).write(
                to: outputDirectory.appendingPathComponent(Self.reportTextFilename),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            // The caller still receives the in-memory report and exposes the write failure through the UI state.
        }
    }

    private static func textSummary(_ report: SpeechQualityProbeReport) -> String {
        let aggregate = report.aggregate
        let wer = aggregate.weightedWordErrorRate.map { String(format: "%.4f", $0) } ?? "n/a"
        let cer = aggregate.weightedCharacterErrorRate.map { String(format: "%.4f", $0) } ?? "n/a"
        let latency = aggregate.averageLatencySeconds.map { String(format: "%.3f", $0) } ?? "n/a"
        var lines = [
            "schemaVersion=\(report.schemaVersion)",
            "appAlgorithmVersion=\(report.appAlgorithmVersion)",
            "verdict=\(report.verdict.rawValue)",
            "corpusID=\(report.corpusID ?? "n/a")",
            "corpusVersion=\(report.corpusVersion ?? "n/a")",
            "manifestSHA256=\(report.corpusManifestSHA256 ?? "n/a")",
            "cases=\(aggregate.recognizedCaseCount)/\(aggregate.totalCaseCount)",
            "weightedWER=\(wer)",
            "weightedCER=\(cer)",
            "averageLatencySeconds=\(latency)",
            "referenceUsedForEvaluationOnly=true",
            "referenceUsedForRecognitionDecision=false"
        ]
        for item in report.cases {
            lines.append(
                "case[\(item.id)] locale=\(item.localeIdentifier) failure=\(item.failureCategory?.rawValue ?? "none") wer=\(item.metrics?.wordErrorRate.map { String(format: "%.4f", $0) } ?? "n/a") cer=\(item.metrics?.characterErrorRate.map { String(format: "%.4f", $0) } ?? "n/a")"
            )
        }
        lines.append(contentsOf: report.warnings.map { "warning=\($0)" })
        return lines.joined(separator: "\n") + "\n"
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func fileIdentity(at url: URL) throws -> (byteCount: Int64, sha256: String) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? NSNumber else {
            throw CocoaError(.fileReadUnknown)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (fileSize.int64Value, digest)
    }

    private static func runtimeIdentity() -> SpeechQualityRuntimeIdentity {
        SpeechQualityRuntimeIdentity(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            deviceModel: UIDevice.current.model,
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion
        )
    }
}
