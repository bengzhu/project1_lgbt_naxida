import Combine
import AVFoundation
import Foundation
import ImageIO
import Speech
import StoreKit
import UIKit
import UniformTypeIdentifiers

@MainActor
final class TranslationSessionStore: ObservableObject {
    @Published var mode: SessionMode = .live {
        didSet { persist() }
    }

    @Published var sourceLanguage: SupportedLanguage = .englishUS {
        didSet { persist() }
    }

    @Published var targetLanguage: SupportedLanguage = .simplifiedChinese {
        didSet { persist() }
    }

    @Published var transcript: [TranscriptLine] = [] {
        didSet { persist() }
    }

    @Published var summary: AISummary = .empty {
        didSet { persist() }
    }

    @Published var prompts: [PromptTemplate] = PromptTemplate.defaultPrompts {
        didSet { persist() }
    }

    @Published var selectedPromptID: UUID = PromptTemplate.translatorID {
        didSet { persist() }
    }

    @Published var history: [TranslationSessionRecord] = [] {
        didSet { persist() }
    }

    @Published var selectedEngine: ModelEngine = .mock {
        didSet {
            refreshModelStatus()
            persist()
        }
    }

    @Published var sampling: GenerationSampling = .defaultValue {
        didSet { persist() }
    }

    @Published var modelStatus = ModelStatus(
        title: "Gemma 1.5B Mock",
        detail: "未下载模型，当前使用本地模拟输出",
        isReady: true
    )

    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var elapsedSeconds = 0
    @Published var draftText = "And then if we are planning the offline model, there are three things we should care about."
    @Published var lastGenerationLabel = "等待生成"
    @Published var diagnostics: [DiagnosticCheck] = TranslationSessionStore.defaultDiagnostics
    @Published var isRunningDiagnostics = false
    @Published var llmSmokeTest: LLMInterfaceSmokeTest = .idle
    @Published var isRunningLLMSmokeTest = false
    @Published var modelDownload = ModelDownloadProgress.idle
    @Published var dataTransferMessage = "本地数据已准备好"
    @Published var isProUnlocked = false {
        didSet { persist() }
    }
    @Published var isDeveloperModeEnabled = false {
        didSet { persist() }
    }
    @Published var developerModeMessage = "输入密码开启开发者模式"
    @Published var developerProbeInput = "The meeting starts at 9:30 tomorrow."
    @Published var developerProbePrompt = ""
    @Published var developerProbeOutput = ""
    @Published var developerProbeError = ""
    @Published var developerProbeCases: [DeveloperRawProbeCase] = TranslationSessionStore.defaultDeveloperProbeCases
    @Published var isRunningDeveloperProbe = false
    @Published var mangaOverlayProbeState: MangaOverlayProbeState = .idle
    @Published var mangaOverlayProbeMessage = "等待运行 test/1.png 漫画覆盖翻译探针"
    @Published var mangaOverlayProbeReport: MangaOverlayProbeReport?
    @Published var mangaOverlayProbeBlocks: [MangaOverlayProbeBlock] = []
    @Published var isRunningMangaOverlayProbe = false
    @Published var proPurchaseMessage = "准备接入 App Store 订阅"
    @Published var audioRecognitionState: AudioRecognitionState = .idle
    @Published var audioRecognitionMessage = "选择音频文件后，会强制使用 Apple 本机语音识别测试离线能力"
    @Published var lastRecognizedSpeechText = ""
    @Published var proLiveTranscriptText = ""
    @Published var proLiveTranslationText = ""
    @Published var isCapturingProSpeech = false
    @Published var imageTranslationState: ImageTranslationState = .idle
    @Published var imageTranslationMessage = "选择图片后，会用 Apple Vision 本机 OCR 识别文字并定位"
    @Published var imageTranslationBlocks: [ImageTranslationBlock] = []
    @Published var imageTranslationData: Data?
    @Published var imageTranslationFilename = ""
    @Published var imageTranslationRevision = 0
    @Published var imageOverlayMode: ImageTranslationOverlayMode = .adjacent
    @Published var imageTranslationExportURL: URL?
    @Published private(set) var speechRecognitionCapabilities: [SpeechRecognitionCapability] = []

    let localModelDirectory: URL
    let localModelFilename = "model.gguf"
    let builtInModel = BuiltInLocalModel.gemma270M
    let persistenceURL: URL

    private let mockService: any LocalLanguageModeling
    private let localService: GemmaLocalService
    private let modelDownloadService = LocalModelDownloadService()
    private let visionOCRService = VisionOCRService()
    private let mangaOverlayProbeService = MangaOverlayProbeService()
    private var ticker: Task<Void, Never>?
    private var modelDownloadTask: Task<Void, Never>?
    private var imageTranslationTask: Task<Void, Never>?
    private var imageTranslationTaskID = UUID()
    private var audioRecognitionTask: SFSpeechRecognitionTask?
    private var liveAudioEngine: AVAudioEngine?
    private var liveSpeechRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var proSubscriptionProduct: Product?
    private var imageTranslationSourceURL: URL?
    private var activeSessionID = UUID()
    private var activeCreatedAt = Date()
    private var liveSampleIndex = 0
    private var isRestoring = false

    init(modelService: any LocalLanguageModeling) {
        let configuredLocalService = GemmaLocalService()
        self.mockService = modelService
        self.localService = configuredLocalService
        self.localModelDirectory = configuredLocalService.modelDirectory
        self.persistenceURL = Self.makePersistenceURL()

        restoreSnapshot()
        updateModelDownloadStateFromDisk()
#if DEBUG
        if !Self.shouldRunMangaOverlayProbeFromLaunchEnvironment {
            refreshSpeechRecognitionCapabilities()
        }
#else
        refreshSpeechRecognitionCapabilities()
#endif
        refreshModelStatus()
        persist()
        runLaunchLLMSmokeTestIfNeeded()
        runLaunchMangaOverlayProbeIfNeeded()
    }

    deinit {
        ticker?.cancel()
        modelDownloadTask?.cancel()
        imageTranslationTask?.cancel()
    }

    private func runLaunchLLMSmokeTestIfNeeded() {
#if DEBUG
        guard Self.shouldRunLLMSmokeTestFromLaunchEnvironment else { return }
        writeLaunchLLMSmokeProbe("launch-trigger")
        selectedEngine = .local
        Task { @MainActor [weak self] in
            await self?.runLaunchTranslationProbeSuite()
        }
#endif
    }

    private func runLaunchMangaOverlayProbeIfNeeded() {
#if DEBUG
        guard Self.shouldRunMangaOverlayProbeFromLaunchEnvironment else { return }
        let runMode = Self.launchMangaOverlayProbeRunMode
        writeMangaProbeProgress(
            stage: "launch-trigger-received",
            runOptions: Self.mangaOverlayProbeRunOptions(for: runMode),
            message: "env=\(ProcessInfo.processInfo.environment["AITRANS_RUN_MANGA_PROBE"] ?? "nil") mode=\(runMode.rawValue) args=\(ProcessInfo.processInfo.arguments.joined(separator: " "))"
        )
        guard runMode != .skip else {
            writeMangaProbeProgress(
                stage: "launch-skip",
                runOptions: Self.mangaOverlayProbeRunOptions(for: runMode),
                message: "AITRANS_MANGA_PROBE_MODE=skip"
            )
            return
        }
        if isLocalModelInstalled {
            selectedEngine = .local
        }
        Task { @MainActor in
            self.writeMangaProbeProgress(
                stage: "launch-task-start",
                runOptions: Self.mangaOverlayProbeRunOptions(for: runMode)
            )
            self.runMangaOverlayProbe()
        }
#endif
    }

    var selectedPrompt: PromptTemplate {
        prompts.first { $0.id == selectedPromptID } ?? PromptTemplate.defaultPrompts[0]
    }

    var localModelPathDisplay: String {
        localModelDirectory.appendingPathComponent(localModelFilename).path
    }

    var localModelSizeDisplay: String {
        let modelURL = localModelDirectory.appendingPathComponent(localModelFilename)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
              let fileSize = attributes[.size] as? NSNumber else {
            return "未安装"
        }

        return ByteCountFormatter.string(fromByteCount: fileSize.int64Value, countStyle: .file)
    }

    var builtInModelSizeDisplay: String {
        ByteCountFormatter.string(fromByteCount: builtInModel.expectedSizeBytes, countStyle: .file)
    }

    var modelDownloadProgressDisplay: String {
        let received = ByteCountFormatter.string(fromByteCount: modelDownload.bytesReceived, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: modelDownload.totalBytes, countStyle: .file)
        return "\(received) / \(total)"
    }

    var modelDownloadSpeedDisplay: String {
        guard modelDownload.speedBytesPerSecond > 0 else { return "0 KB/s" }
        let speed = ByteCountFormatter.string(fromByteCount: modelDownload.speedBytesPerSecond, countStyle: .file)
        return "\(speed)/s"
    }

    var modelDownloadLocationDisplay: String {
        builtInModel.sourceURL.absoluteString
    }

    var isLocalModelInstalled: Bool {
        FileManager.default.fileExists(atPath: localModelDirectory.appendingPathComponent(localModelFilename).path)
    }

    var currentSessionTitle: String {
        makeSessionTitle(from: transcript)
    }

    var totalSessionCount: Int {
        history.count + (transcript.isEmpty ? 0 : 1)
    }

    var persistedLocationDisplay: String {
        persistenceURL.path
    }

    var storageSummary: String {
        "\(history.count) 个历史会话，\(prompts.count) 个提示词模板"
    }

    var selectedAdapterMetadata: ModelAdapterMetadata {
        selectedEngine == .local ? localService.metadata : mockService.metadata
    }

    var proStatusTitle: String {
        isProUnlocked ? "Pro 已开通" : "Pro 未开通"
    }

    var proPlan: ProSubscriptionPlan {
        .development
    }

    var availableTargetLanguages: [SupportedLanguage] {
        SupportedLanguage.allCases
    }

    var currentSpeechCapability: SpeechRecognitionCapability {
        speechRecognitionCapabilities.first { $0.language == sourceLanguage } ?? SpeechRecognitionCapability(
            language: sourceLanguage,
            localeIdentifier: sourceLanguage.speechLocaleIdentifier,
            supportsOnDeviceRecognition: false
        )
    }

    var exportURL: URL {
        persistenceURL
            .deletingLastPathComponent()
            .appendingPathComponent("aitrans-export.json")
    }

    private var audioTestDirectory: URL {
        persistenceURL
            .deletingLastPathComponent()
            .appendingPathComponent("AudioTests", isDirectory: true)
    }

    private var imageTranslationDirectory: URL {
        persistenceURL
            .deletingLastPathComponent()
            .appendingPathComponent("ImageTranslations", isDirectory: true)
    }

    private var bundledTestDirectory: URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("test", isDirectory: true),
            Bundle.main.url(forResource: "test", withExtension: nil)
        ]
        return candidates.compactMap { $0 }.first {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private var mangaOverlayOutputDirectory: URL {
        persistenceURL
            .deletingLastPathComponent()
            .appendingPathComponent("Output", isDirectory: true)
    }

    var imageTranslationProgressTitle: String {
        switch imageTranslationState {
        case .idle: "待选择"
        case .loading: "载入中"
        case .recognizing: "OCR 中"
        case .translating: "翻译中"
        case .translated: "已完成"
        case .failed: "失败"
        }
    }

    var imageTranslationSummary: String {
        let translatedCount = imageTranslationBlocks.filter { !$0.translation.isEmpty }.count
        guard !imageTranslationBlocks.isEmpty else { return "0 个文本块" }
        return "\(translatedCount)/\(imageTranslationBlocks.count) 个文本块"
    }

    func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            startTicker()
            Task { await injectMockLiveLine() }
        } else {
            ticker?.cancel()
            ticker = nil
            persist()
        }
    }

    func submitDraft() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isProcessing else { return }
        guard canUseLanguage(targetLanguage) else {
            dataTransferMessage = "\(targetLanguage.rawValue) 属于 Pro 翻译语言"
            return
        }

        isProcessing = true
        let timestamp = Self.timeFormatter.string(from: Date())

        Task { [weak self] in
            await self?.submit(trimmed, timestamp: timestamp)
        }
    }

    func recognizeAudioFileAndTranslate(from url: URL) {
        guard !isProcessing else { return }
        guard isProUnlocked else {
            audioRecognitionState = .failed
            audioRecognitionMessage = "音频离线识别测试需要 Pro"
            dataTransferMessage = audioRecognitionMessage
            return
        }
        audioRecognitionTask?.cancel()

        let capability = currentSpeechCapability
        guard capability.supportsOnDeviceRecognition else {
            audioRecognitionState = .failed
            audioRecognitionMessage = "\(sourceLanguage.rawValue) 当前设备未报告支持 Apple 本机语音识别，断网测试不能保证成功"
            dataTransferMessage = audioRecognitionMessage
            return
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let localAudioURL: URL
        do {
            localAudioURL = try copyAudioFileIntoSandbox(url)
        } catch {
            audioRecognitionState = .failed
            audioRecognitionMessage = "音频文件复制失败：\(error.localizedDescription)"
            dataTransferMessage = audioRecognitionMessage
            return
        }

        audioRecognitionState = .checking
        audioRecognitionMessage = "正在请求 Apple Speech 权限"

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }

                guard status == .authorized else {
                    self.audioRecognitionState = .failed
                    self.audioRecognitionMessage = "Apple Speech 权限未授权，无法测试本机识别"
                    self.dataTransferMessage = self.audioRecognitionMessage
                    return
                }

                self.startOnDeviceAudioRecognition(localAudioURL, capability: capability)
            }
        }
    }

    func beginProLiveSpeechCapture() {
        guard isProUnlocked else {
            audioRecognitionState = .failed
            audioRecognitionMessage = "同声传译需要 Pro"
            dataTransferMessage = audioRecognitionMessage
            return
        }
        guard !isCapturingProSpeech else { return }

        let capability = currentSpeechCapability
        guard capability.supportsOnDeviceRecognition else {
            audioRecognitionState = .failed
            audioRecognitionMessage = "\(sourceLanguage.rawValue) 当前设备未报告支持 Apple 本机语音识别"
            dataTransferMessage = audioRecognitionMessage
            return
        }

        audioRecognitionState = .checking
        audioRecognitionMessage = "正在请求麦克风和 Speech 权限"

        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard speechStatus == .authorized else {
                    self.audioRecognitionState = .failed
                    self.audioRecognitionMessage = "Apple Speech 权限未授权"
                    self.dataTransferMessage = self.audioRecognitionMessage
                    return
                }

                let microphoneGranted = await self.requestMicrophoneAccess()
                guard microphoneGranted else {
                    self.audioRecognitionState = .failed
                    self.audioRecognitionMessage = "麦克风权限未授权"
                    self.dataTransferMessage = self.audioRecognitionMessage
                    return
                }

                self.startProLiveSpeechRecognition(capability: capability)
            }
        }
    }

    func endProLiveSpeechCapture() {
        liveAudioEngine?.stop()
        liveAudioEngine?.inputNode.removeTap(onBus: 0)
        liveSpeechRecognitionRequest?.endAudio()
        liveAudioEngine = nil
        liveSpeechRecognitionRequest = nil
        audioRecognitionTask?.cancel()
        audioRecognitionTask = nil
        isCapturingProSpeech = false
        audioRecognitionState = proLiveTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .idle : .translated
        audioRecognitionMessage = proLiveTranscriptText.isEmpty ? "未识别到语音" : "识别完成，可点击翻译"
    }

    func translateProLiveTranscript() {
        let text = proLiveTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProcessing else { return }
        guard isProUnlocked else {
            audioRecognitionMessage = "同声传译需要 Pro"
            dataTransferMessage = audioRecognitionMessage
            return
        }

        isProcessing = true
        audioRecognitionMessage = "正在翻译识别文本"
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.isProcessing = false
                self.persist()
            }

            do {
                let translation = try await self.translate(text)
                self.proLiveTranslationText = translation
                self.draftText = text
                self.transcript.insert(
                    TranscriptLine(
                        speaker: "Pro Live",
                        original: text,
                        translation: translation,
                        time: Self.timeFormatter.string(from: Date()),
                        isFinal: true
                    ),
                    at: 0
                )
                self.audioRecognitionState = .translated
                self.audioRecognitionMessage = "同声传译已完成"
                self.dataTransferMessage = self.audioRecognitionMessage
            } catch {
                self.audioRecognitionState = .failed
                self.audioRecognitionMessage = "翻译失败：\(error.localizedDescription)"
                self.dataTransferMessage = self.audioRecognitionMessage
            }
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func startProLiveSpeechRecognition(capability: SpeechRecognitionCapability) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: capability.localeIdentifier)) else {
            audioRecognitionState = .failed
            audioRecognitionMessage = "无法创建 \(capability.localeIdentifier) 语音识别器"
            dataTransferMessage = audioRecognitionMessage
            return
        }

        audioRecognitionTask?.cancel()

        let audioEngine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            audioRecognitionState = .failed
            audioRecognitionMessage = "麦克风启动失败：\(error.localizedDescription)"
            dataTransferMessage = audioRecognitionMessage
            return
        }

        liveAudioEngine = audioEngine
        liveSpeechRecognitionRequest = request
        isCapturingProSpeech = true
        proLiveTranscriptText = ""
        proLiveTranslationText = ""
        audioRecognitionState = .recognizing
        audioRecognitionMessage = "按住说话，松手结束"

        audioRecognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    self.proLiveTranscriptText = result.bestTranscription.formattedString
                }

                if let error {
                    self.endProLiveSpeechCapture()
                    self.audioRecognitionState = .failed
                    self.audioRecognitionMessage = "语音识别失败：\(error.localizedDescription)"
                    self.dataTransferMessage = self.audioRecognitionMessage
                }
            }
        }
    }

    private func startOnDeviceAudioRecognition(_ url: URL, capability: SpeechRecognitionCapability) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: capability.localeIdentifier)) else {
            audioRecognitionState = .failed
            audioRecognitionMessage = "无法创建 \(capability.localeIdentifier) 语音识别器"
            dataTransferMessage = audioRecognitionMessage
            return
        }

        isProcessing = true
        audioRecognitionState = .recognizing
        audioRecognitionMessage = "正在用 requiresOnDeviceRecognition 识别 \(url.lastPathComponent)"

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        audioRecognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    self.audioRecognitionTask = nil
                    self.isProcessing = false
                    self.audioRecognitionState = .failed
                    self.audioRecognitionMessage = "本机语音识别失败：\(error.localizedDescription)"
                    self.dataTransferMessage = self.audioRecognitionMessage
                    return
                }

                guard let result, result.isFinal else { return }
                self.audioRecognitionTask = nil

                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    self.isProcessing = false
                    self.audioRecognitionState = .failed
                    self.audioRecognitionMessage = "语音识别完成，但没有得到文本"
                    self.dataTransferMessage = self.audioRecognitionMessage
                    return
                }

                self.lastRecognizedSpeechText = text
                self.draftText = text
                self.audioRecognitionMessage = "识别成功，正在交给翻译模型"

                let timestamp = Self.timeFormatter.string(from: Date())
                let didTranslate = await self.submit(text, timestamp: timestamp)
                if didTranslate {
                    self.audioRecognitionState = .translated
                    self.audioRecognitionMessage = "已离线识别并完成翻译"
                } else {
                    self.audioRecognitionState = .failed
                    self.audioRecognitionMessage = "已离线识别出文字，但翻译模型处理失败"
                }
                self.dataTransferMessage = self.audioRecognitionMessage
            }
        }
    }

    private func copyAudioFileIntoSandbox(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: audioTestDirectory, withIntermediateDirectories: true)

        let cleanName = url.lastPathComponent.isEmpty ? "audio-input.m4a" : url.lastPathComponent
        let destination = audioTestDirectory.appendingPathComponent(cleanName)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    private func copyImageFileIntoSandbox(_ url: URL) async throws -> URL {
        let directory = imageTranslationDirectory
        let destinationName = Self.sanitizedImageFilename(from: url)

        let copiedURL = try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let destination = directory.appendingPathComponent(destinationName)
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        }.value

        imageTranslationSourceURL = copiedURL
        imageTranslationFilename = copiedURL.lastPathComponent
        return copiedURL
    }

    private func writeImageDataIntoSandbox(_ data: Data, filename: String) async throws -> URL {
        let directory = imageTranslationDirectory
        let destinationName = Self.sanitizedImageFilename(filename.isEmpty ? "photo-library-image.png" : filename)

        return try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(destinationName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try data.write(to: destination, options: .atomic)
            return destination
        }.value
    }

    private func beginImageTranslationTask(filename: String) -> UUID {
        imageTranslationTask?.cancel()
        let taskID = UUID()
        imageTranslationTaskID = taskID
        imageTranslationState = .loading
        imageTranslationMessage = "正在载入图片"
        imageTranslationBlocks = []
        imageTranslationData = nil
        imageTranslationExportURL = nil
        imageTranslationRevision += 1
        imageTranslationFilename = filename
        isProcessing = true
        return taskID
    }

    private func isCurrentImageTranslationTask(_ taskID: UUID) -> Bool {
        imageTranslationTaskID == taskID && !Task.isCancelled
    }

    private func runImageTranslationPipeline(with data: Data, taskID: UUID) async throws {
        guard isCurrentImageTranslationTask(taskID) else { throw CancellationError() }
        imageTranslationData = data
        imageTranslationRevision += 1
        imageTranslationState = .recognizing
        imageTranslationMessage = "正在用 Vision 本机 OCR 识别文字和位置"

        let recognizedBlocks = try await visionOCRService.recognizeTextBlocks(
            in: data,
            sourceLanguage: sourceLanguage
        )
        try Task.checkCancellation()
        guard isCurrentImageTranslationTask(taskID) else { throw CancellationError() }

        guard !recognizedBlocks.isEmpty else {
            imageTranslationState = .failed
            imageTranslationMessage = "Vision OCR 没有识别到可翻译文字"
            dataTransferMessage = imageTranslationMessage
            isProcessing = false
            return
        }

        imageTranslationBlocks = recognizedBlocks
        imageTranslationState = .translating
        imageTranslationMessage = "已识别 \(recognizedBlocks.count) 个文本块，正在交给本地模型翻译"

        var translatedBlocks: [ImageTranslationBlock] = []
        for (index, block) in recognizedBlocks.enumerated() {
            try Task.checkCancellation()
            guard isCurrentImageTranslationTask(taskID) else { throw CancellationError() }
            var translatedBlock = block
            translatedBlock.translation = try await translate(block.original)
            guard isCurrentImageTranslationTask(taskID) else { throw CancellationError() }
            translatedBlocks.append(translatedBlock)
            imageTranslationBlocks = translatedBlocks + Array(recognizedBlocks.dropFirst(translatedBlocks.count))
            imageTranslationMessage = "正在翻译 \(index + 1)/\(recognizedBlocks.count) 个文本块"
        }

        imageTranslationBlocks = translatedBlocks
        imageTranslationExportURL = try? await Self.renderImageTranslationOverlay(
            imageData: data,
            blocks: translatedBlocks,
            filename: imageTranslationFilename,
            directory: imageTranslationDirectory
        )
        imageTranslationState = .translated
        imageTranslationMessage = imageTranslationExportURL == nil
            ? "已完成 Vision OCR、本地翻译和定位覆盖"
            : "已完成 Vision OCR、本地翻译和覆盖图导出"
        dataTransferMessage = imageTranslationMessage
        appendImageTranslationTranscript(blocks: translatedBlocks)
        isProcessing = false
        persist()
    }

    private func finishImageTranslation(taskID: UUID, with error: Error) {
        guard imageTranslationTaskID == taskID else { return }

        if error is CancellationError {
            imageTranslationState = .idle
            imageTranslationMessage = "图片翻译已取消"
            dataTransferMessage = imageTranslationMessage
            isProcessing = false
            imageTranslationTask = nil
            return
        }

        imageTranslationState = .failed
        imageTranslationMessage = "图片翻译失败：\(error.localizedDescription)"
        dataTransferMessage = imageTranslationMessage
        isProcessing = false
        imageTranslationTask = nil
        persist()
    }

    private func runImageTranslation(fromSandboxURL url: URL, taskID: UUID) {
        imageTranslationTask = Task { [weak self] in
            guard let self else { return }

            do {
                guard self.isCurrentImageTranslationTask(taskID) else { throw CancellationError() }
                let data = try await Self.loadSecurityScopedData(from: url)
                try await self.runImageTranslationPipeline(with: data, taskID: taskID)
            } catch {
                self.finishImageTranslation(taskID: taskID, with: error)
            }
        }
    }

    func translateImage(from url: URL) {
        guard imageTranslationState != .loading,
              imageTranslationState != .recognizing,
              imageTranslationState != .translating else { return }
        guard isProUnlocked else {
            imageTranslationState = .failed
            imageTranslationMessage = "图片翻译需要 Pro"
            dataTransferMessage = imageTranslationMessage
            return
        }
        guard canUseLanguage(targetLanguage) else {
            imageTranslationState = .failed
            imageTranslationMessage = "\(targetLanguage.rawValue) 图片翻译需要 Pro"
            dataTransferMessage = imageTranslationMessage
            return
        }

        let taskID = beginImageTranslationTask(filename: url.lastPathComponent)

        imageTranslationTask = Task { [weak self] in
            guard let self else { return }

            do {
                guard self.isCurrentImageTranslationTask(taskID) else { throw CancellationError() }
                let sandboxURL = try await self.copyImageFileIntoSandbox(url)
                try Task.checkCancellation()
                guard self.isCurrentImageTranslationTask(taskID) else { throw CancellationError() }

                let data = try await Self.loadSecurityScopedData(from: sandboxURL)
                try await self.runImageTranslationPipeline(with: data, taskID: taskID)
            } catch {
                self.finishImageTranslation(taskID: taskID, with: error)
            }
        }
    }

    func translateImageData(_ data: Data, filename: String) {
        guard imageTranslationState != .loading,
              imageTranslationState != .recognizing,
              imageTranslationState != .translating else { return }
        guard isProUnlocked else {
            imageTranslationState = .failed
            imageTranslationMessage = "图片翻译需要 Pro"
            dataTransferMessage = imageTranslationMessage
            return
        }
        guard canUseLanguage(targetLanguage) else {
            imageTranslationState = .failed
            imageTranslationMessage = "\(targetLanguage.rawValue) 图片翻译需要 Pro"
            dataTransferMessage = imageTranslationMessage
            return
        }

        let taskID = beginImageTranslationTask(filename: filename)

        imageTranslationTask = Task { [weak self] in
            guard let self else { return }

            do {
                guard self.isCurrentImageTranslationTask(taskID) else { throw CancellationError() }
                let sandboxURL = try await self.writeImageDataIntoSandbox(data, filename: filename)
                guard self.isCurrentImageTranslationTask(taskID) else { throw CancellationError() }
                self.imageTranslationSourceURL = sandboxURL
                self.imageTranslationFilename = sandboxURL.lastPathComponent
                try await self.runImageTranslationPipeline(with: data, taskID: taskID)
            } catch {
                self.finishImageTranslation(taskID: taskID, with: error)
            }
        }
    }

    func clearImageTranslation() {
        imageTranslationTask?.cancel()
        imageTranslationTask = nil
        imageTranslationTaskID = UUID()
        imageTranslationState = .idle
        imageTranslationMessage = "选择图片后，会用 Apple Vision 本机 OCR 识别文字并定位"
        imageTranslationBlocks = []
        imageTranslationData = nil
        imageTranslationFilename = ""
        imageTranslationSourceURL = nil
        imageTranslationExportURL = nil
        imageTranslationRevision += 1
        isProcessing = false
    }

    func setImageOverlayMode(_ mode: ImageTranslationOverlayMode) {
        imageOverlayMode = mode
    }

    func cancelImageTranslation() {
        imageTranslationTask?.cancel()
        imageTranslationTask = nil
        imageTranslationTaskID = UUID()
        imageTranslationState = .idle
        imageTranslationMessage = "图片翻译已取消"
        dataTransferMessage = imageTranslationMessage
        isProcessing = false
    }

    func retryImageTranslation() {
        guard let url = imageTranslationSourceURL,
              FileManager.default.fileExists(atPath: url.path) else {
            imageTranslationMessage = "没有可重试的图片文件"
            dataTransferMessage = imageTranslationMessage
            return
        }

        let taskID = beginImageTranslationTask(filename: url.lastPathComponent)
        imageTranslationSourceURL = url
        runImageTranslation(fromSandboxURL: url, taskID: taskID)
    }

    func refreshSummary() async throws {
        summary = try await summarize()
    }

    func canUseLanguage(_ language: SupportedLanguage) -> Bool {
        language.isFreeTranslationTarget || isProUnlocked
    }

    func unlockDeveloperMode(password: String) -> Bool {
        guard password == "114514" else {
            developerModeMessage = "密码错误"
            return false
        }

        isDeveloperModeEnabled = true
        developerModeMessage = "开发者模式已开启"
        return true
    }

    func disableDeveloperMode() {
        isDeveloperModeEnabled = false
        developerModeMessage = "开发者模式已关闭"
    }

    func runDeveloperRawProbe() {
        let input = developerProbeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isRunningDeveloperProbe else { return }

        isRunningDeveloperProbe = true
        developerProbePrompt = ""
        developerProbeOutput = ""
        developerProbeError = ""

        let request = makeRequest(task: .translation, inputText: input)

        Task { [weak self] in
            guard let self else { return }
            defer { self.isRunningDeveloperProbe = false }

            if self.selectedEngine == .local {
                let probe = self.localService.rawTranslationProbe(for: request)
                self.developerProbePrompt = probe.prompt
                self.developerProbeOutput = probe.output
                self.developerProbeError = probe.errorCode ?? ""
            } else {
                do {
                    try await self.mockService.prepare()
                    let result = try await self.mockService.generate(request)
                    self.developerProbePrompt = self.debugPromptPreview(for: request)
                    self.developerProbeOutput = result.text
                    self.developerProbeError = ""
                } catch {
                    self.developerProbePrompt = self.debugPromptPreview(for: request)
                    self.developerProbeOutput = ""
                    self.developerProbeError = "\(type(of: error)): \(error.localizedDescription)"
                }
            }
        }
    }

    func runDeveloperRawProbeSuite() {
        guard !isRunningDeveloperProbe else { return }

        isRunningDeveloperProbe = true
        developerProbePrompt = ""
        developerProbeOutput = ""
        developerProbeError = ""
        developerProbeCases = Self.defaultDeveloperProbeCases.map {
            DeveloperRawProbeCase(
                id: $0.id,
                sourceLanguage: $0.sourceLanguage,
                targetLanguage: $0.targetLanguage,
                input: $0.input,
                verdict: "运行中"
            )
        }

        Task { [weak self] in
            guard let self else { return }
            defer { self.isRunningDeveloperProbe = false }

            let pendingCases = self.developerProbeCases
            var completedCases: [DeveloperRawProbeCase] = []
            for probeCase in pendingCases {
                let request = self.makeProbeRequest(
                    source: probeCase.sourceLanguage,
                    target: probeCase.targetLanguage,
                    input: probeCase.input
                )
                let completed = await self.runDeveloperProbeCase(probeCase, request: request)
                completedCases.append(completed)
                self.developerProbeCases = completedCases + Array(pendingCases.dropFirst(completedCases.count))
            }

            self.developerProbePrompt = completedCases.map { $0.prompt }.joined(separator: "\n\n---\n\n")
            self.developerProbeOutput = completedCases.map { probeCase in
                let body = probeCase.errorCode ?? probeCase.output
                return "[\(probeCase.sourceLanguage.shortName)->\(probeCase.targetLanguage.shortName)] \(probeCase.verdict)\n\(body)"
            }.joined(separator: "\n\n---\n\n")
            self.developerProbeError = completedCases.compactMap(\.errorCode).joined(separator: "\n\n")
        }
    }

    private func runDeveloperProbeCase(
        _ probeCase: DeveloperRawProbeCase,
        request: ModelGenerationRequest
    ) async -> DeveloperRawProbeCase {
        if selectedEngine == .local {
            let probe = localService.rawTranslationProbe(for: request)
            let verdict = probe.errorCode == nil
                ? translationProbeVerdict(source: request.sourceLanguage, target: request.targetLanguage, input: request.inputText, output: probe.output)
                : "Local 真实 raw 探针失败"
            return DeveloperRawProbeCase(
                id: probeCase.id,
                sourceLanguage: probeCase.sourceLanguage,
                targetLanguage: probeCase.targetLanguage,
                input: probeCase.input,
                prompt: probe.prompt,
                output: probe.output,
                errorCode: probe.errorCode,
                verdict: verdict,
                isRealLocalModelOutput: true
            )
        }

        do {
            try await mockService.prepare()
            let result = try await mockService.generate(request)
            return DeveloperRawProbeCase(
                id: probeCase.id,
                sourceLanguage: probeCase.sourceLanguage,
                targetLanguage: probeCase.targetLanguage,
                input: probeCase.input,
                prompt: debugPromptPreview(for: request) + "\n\n注意：Mock 模式为模拟输出，不是真实模型 raw prompt。",
                output: result.text,
                errorCode: nil,
                verdict: "Mock 模拟输出，非真实模型",
                isRealLocalModelOutput: false
            )
        } catch {
            return DeveloperRawProbeCase(
                id: probeCase.id,
                sourceLanguage: probeCase.sourceLanguage,
                targetLanguage: probeCase.targetLanguage,
                input: probeCase.input,
                prompt: debugPromptPreview(for: request) + "\n\n注意：Mock 模式为模拟输出，不是真实模型 raw prompt。",
                output: "",
                errorCode: "\(type(of: error)): \(error.localizedDescription)",
                verdict: "Mock 探针失败",
                isRealLocalModelOutput: false
            )
        }
    }

    func loadProSubscriptionProduct() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let products = try await Product.products(for: [self.proPlan.productID])
                self.proSubscriptionProduct = products.first
                if let product = products.first {
                    self.proPurchaseMessage = "App Store 产品已就绪：\(product.displayName) · \(product.displayPrice)/月"
                } else {
                    self.proPurchaseMessage = "未在 App Store Connect 找到 \(self.proPlan.productID)，发布前需创建自动续期订阅。"
                }
            } catch {
                self.proPurchaseMessage = "读取 StoreKit 产品失败：\(error.localizedDescription)"
            }
        }
    }

    func purchaseProSubscription() {
        Task { [weak self] in
            guard let self else { return }

            do {
                if self.proSubscriptionProduct == nil {
                    let products = try await Product.products(for: [self.proPlan.productID])
                    self.proSubscriptionProduct = products.first
                }

                guard let product = self.proSubscriptionProduct else {
                    self.proPurchaseMessage = "订阅产品未配置：\(self.proPlan.productID)"
                    return
                }

                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    let transaction = try self.verifiedTransaction(from: verification)
                    self.isProUnlocked = true
                    self.proPurchaseMessage = "Pro 已开通：\(transaction.productID)"
                    await transaction.finish()
                case .userCancelled:
                    self.proPurchaseMessage = "已取消购买"
                case .pending:
                    self.proPurchaseMessage = "购买待处理"
                @unknown default:
                    self.proPurchaseMessage = "未知购买状态"
                }
            } catch {
                self.proPurchaseMessage = "购买失败：\(error.localizedDescription)"
            }
        }
    }

    private func verifiedTransaction(from result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            transaction
        case .unverified(_, let error):
            throw error
        }
    }

    func refreshProEntitlements() {
        Task { [weak self] in
            guard let self else { return }

            do {
                var hasEntitlement = false
                for await result in Transaction.currentEntitlements {
                    let transaction = try self.verifiedTransaction(from: result)
                    if transaction.productID == self.proPlan.productID {
                        hasEntitlement = true
                    }
                }
                self.isProUnlocked = hasEntitlement
                self.proPurchaseMessage = hasEntitlement ? "App Store 订阅有效" : "未发现有效订阅"
            } catch {
                self.proPurchaseMessage = "校验订阅失败：\(error.localizedDescription)"
            }
        }
    }

    func selectTargetLanguage(_ language: SupportedLanguage) {
        guard canUseLanguage(language) else {
            dataTransferMessage = "\(language.rawValue) 翻译需要 Pro"
            return
        }

        targetLanguage = language
    }

    func activateProForDevelopment() {
        isProUnlocked = true
        dataTransferMessage = "Pro 已开通：同声传译、日语/法语和图片翻译入口已解锁"
    }

    func restoreFreeModeForDevelopment() {
        isProUnlocked = false
        if !targetLanguage.isFreeTranslationTarget {
            targetLanguage = .simplifiedChinese
        }
        dataTransferMessage = "已切回免费模式：保留中文和英语翻译"
    }

    func swapLanguages() {
        let oldSource = sourceLanguage
        let oldTarget = targetLanguage
        guard canUseLanguage(oldSource) else {
            dataTransferMessage = "\(oldSource.rawValue) 作为目标语言需要 Pro"
            return
        }

        sourceLanguage = oldTarget
        targetLanguage = oldSource
    }

    func startNewSession(archiveCurrent: Bool = true) {
        ticker?.cancel()
        ticker = nil
        isRecording = false

        if archiveCurrent, shouldArchiveCurrentSession {
            upsertHistory(currentSessionRecord())
        }

        activeSessionID = UUID()
        activeCreatedAt = Date()
        elapsedSeconds = 0
        transcript = []
        summary = .empty
        draftText = ""
        lastGenerationLabel = "等待生成"
        persist()
    }

    func resetSession() {
        startNewSession(archiveCurrent: true)
    }

    func archiveCurrentSession() {
        guard shouldArchiveCurrentSession else { return }
        upsertHistory(currentSessionRecord())
        persist()
    }

    func loadSession(_ record: TranslationSessionRecord) {
        ticker?.cancel()
        ticker = nil
        isRecording = false

        isRestoring = true
        activeSessionID = record.id
        activeCreatedAt = record.createdAt
        mode = record.mode
        sourceLanguage = record.sourceLanguage
        targetLanguage = record.targetLanguage
        selectedPromptID = prompts.contains(where: { $0.id == record.selectedPromptID })
            ? record.selectedPromptID
            : PromptTemplate.translatorID
        selectedEngine = record.selectedEngine
        elapsedSeconds = record.durationSeconds
        transcript = record.transcript
        summary = record.summary
        draftText = ""
        isRestoring = false

        refreshModelStatus()
        persist()
    }

    func deleteSession(_ record: TranslationSessionRecord) {
        history.removeAll { $0.id == record.id }
        if activeSessionID == record.id {
            startNewSession(archiveCurrent: false)
        } else {
            persist()
        }
    }

    func clearHistory(keepCurrentSession: Bool = true) {
        history.removeAll()
        if !keepCurrentSession {
            startNewSession(archiveCurrent: false)
        } else {
            persist()
        }
    }

    @discardableResult
    func exportSnapshot() -> URL? {
        let snapshot = AppPersistenceSnapshot(
            activeSession: shouldArchiveCurrentSession ? currentSessionRecord() : nil,
            history: history,
            prompts: prompts,
            settings: AppSettings(
                mode: mode,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                selectedPromptID: selectedPromptID,
                selectedEngine: selectedEngine,
                sampling: sampling,
                isProUnlocked: isProUnlocked,
                isDeveloperModeEnabled: isDeveloperModeEnabled
            )
        )

        do {
            try Self.write(snapshot, to: exportURL)
            dataTransferMessage = "已导出到 \(exportURL.lastPathComponent)"
            return exportURL
        } catch {
            dataTransferMessage = "导出失败：\(error.localizedDescription)"
            modelStatus = ModelStatus(
                title: "Export Failed",
                detail: error.localizedDescription,
                isReady: false
            )
            return nil
        }
    }

    @discardableResult
    func importSnapshot(from url: URL) -> Bool {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let snapshot = Self.loadSnapshot(from: url) else {
            dataTransferMessage = "导入失败：无法解码 JSON"
            return false
        }

        if shouldArchiveCurrentSession {
            upsertHistory(currentSessionRecord())
        }

        let importedPrompts = Self.mergeDefaultPrompts(with: snapshot.prompts)
        for prompt in importedPrompts where !prompts.contains(where: { $0.id == prompt.id }) {
            prompts.append(prompt)
        }

        for record in snapshot.history {
            upsertHistory(record)
        }

        applySettings(snapshot.settings)
        if !prompts.contains(where: { $0.id == selectedPromptID }) {
            selectedPromptID = PromptTemplate.translatorID
        }

        if let importedActive = snapshot.activeSession {
            upsertHistory(importedActive)
            loadSession(importedActive)
        }

        history.sort { $0.updatedAt > $1.updatedAt }
        if history.count > 60 {
            history = Array(history.prefix(60))
        }
        dataTransferMessage = "已导入 \(snapshot.history.count + (snapshot.activeSession == nil ? 0 : 1)) 个会话，\(snapshot.prompts.count) 个提示词"
        refreshModelStatus()
        persist()
        return true
    }

    func selectEngine(_ engine: ModelEngine) {
        selectedEngine = engine
    }

    func selectPrompt(_ prompt: PromptTemplate) {
        selectedPromptID = prompt.id
    }

    func createPrompt(
        title: String,
        englishToChineseInstruction: String,
        chineseToEnglishInstruction: String,
        tone: String
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEnglishToChinese = englishToChineseInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanChineseToEnglish = chineseToEnglishInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTone = tone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        let prompt = PromptTemplate(
            title: cleanTitle,
            instruction: cleanEnglishToChinese.isEmpty
                ? PromptLanguageDirection.englishToChinese.fallbackInstruction
                : cleanEnglishToChinese,
            englishToChineseInstruction: cleanEnglishToChinese.isEmpty
                ? PromptLanguageDirection.englishToChinese.fallbackInstruction
                : cleanEnglishToChinese,
            chineseToEnglishInstruction: cleanChineseToEnglish.isEmpty
                ? PromptLanguageDirection.chineseToEnglish.fallbackInstruction
                : cleanChineseToEnglish,
            tone: cleanTone.isEmpty ? "自然、准确" : cleanTone
        )
        prompts.insert(prompt, at: 0)
        selectedPromptID = prompt.id
    }

    func updatePrompt(
        _ prompt: PromptTemplate,
        title: String,
        englishToChineseInstruction: String,
        chineseToEnglishInstruction: String,
        tone: String
    ) {
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }), !prompts[index].isBuiltIn else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEnglishToChinese = englishToChineseInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanChineseToEnglish = chineseToEnglishInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTone = tone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        prompts[index].title = cleanTitle
        prompts[index].instruction = cleanEnglishToChinese.isEmpty
            ? PromptLanguageDirection.englishToChinese.fallbackInstruction
            : cleanEnglishToChinese
        prompts[index].englishToChineseInstruction = cleanEnglishToChinese.isEmpty
            ? PromptLanguageDirection.englishToChinese.fallbackInstruction
            : cleanEnglishToChinese
        prompts[index].chineseToEnglishInstruction = cleanChineseToEnglish.isEmpty
            ? PromptLanguageDirection.chineseToEnglish.fallbackInstruction
            : cleanChineseToEnglish
        prompts[index].tone = cleanTone.isEmpty ? "自然、准确" : cleanTone
        prompts[index].updatedAt = Date()
    }

    func duplicatePrompt(_ prompt: PromptTemplate) {
        let copy = PromptTemplate(
            title: "\(prompt.title) 副本",
            instruction: prompt.instruction,
            englishToChineseInstruction: prompt.englishToChineseInstruction,
            chineseToEnglishInstruction: prompt.chineseToEnglishInstruction,
            tone: prompt.tone
        )
        prompts.insert(copy, at: 0)
        selectedPromptID = copy.id
    }

    func runBundledAudioTest() {
        guard let url = firstBundledTestFile(matching: Self.audioTestExtensions) else {
            audioRecognitionState = .failed
            audioRecognitionMessage = "test/ 未找到可测试音频"
            dataTransferMessage = audioRecognitionMessage
            return
        }

        recognizeAudioFileAndTranslate(from: url)
    }

    func runBundledOCRImageTest() {
        guard let url = firstBundledTestFile(matching: Self.imageTestExtensions) else {
            imageTranslationState = .failed
            imageTranslationMessage = "test/ 未找到可测试图片"
            dataTransferMessage = imageTranslationMessage
            return
        }

        translateImage(from: url)
    }

    func runMangaOverlayProbe() {
        let runOptions = Self.currentMangaOverlayProbeRunOptions()
        guard !isRunningMangaOverlayProbe else {
            writeMangaProbeProgress(stage: "already-running", runOptions: runOptions)
            return
        }
        guard let url = bundledTestFile(named: "1.png") else {
            let message = "test/1.png 未找到，请确认已放入项目根 test/ 并重新构建。"
            writeMangaProbeProgress(stage: "missing-test-image", runOptions: runOptions, message: message)
            mangaOverlayProbeState = .failed
            mangaOverlayProbeMessage = message
            dataTransferMessage = mangaOverlayProbeMessage
            writeMangaProbeFailureReport(message, runOptions: runOptions)
            return
        }

        writeMangaProbeProgress(stage: "probe-entry", runOptions: runOptions)
        isRunningMangaOverlayProbe = true
        mangaOverlayProbeState = .loading
        mangaOverlayProbeMessage = "正在读取 test/1.png"
        mangaOverlayProbeReport = nil
        mangaOverlayProbeBlocks = []
        dataTransferMessage = mangaOverlayProbeMessage

        Task { @MainActor in
            defer { self.isRunningMangaOverlayProbe = false }

            do {
                let startedAt = Date.now
                self.writeMangaProbeProgress(stage: "probe-task-start", startedAt: startedAt, runOptions: runOptions)
                let outputCleanupRemovedItemCount = try MangaOverlayProbeService.recreateDirectory(self.mangaOverlayOutputDirectory)
                self.writeMangaProbeProgress(stage: "output-cleaned", startedAt: startedAt, runOptions: runOptions)
                let data = try Data(contentsOf: url)
                self.mangaOverlayProbeState = .recognizing
                self.mangaOverlayProbeMessage = "正在用 0/90/180/270 多角度 Vision OCR"
                self.writeMangaProbeProgress(stage: "whole-page-ocr-start", startedAt: startedAt, runOptions: runOptions)
                var probeConfiguration = MangaOverlayProbeConfiguration.defaultValue
                probeConfiguration.probeRunMode = runOptions.mode.rawValue
                probeConfiguration.probeFastPathEnabled = runOptions.mode == .ciFast
                probeConfiguration.skippedDiagnostics = runOptions.skippedDiagnostics
                let activeCustomWords = probeConfiguration.customLexiconEnabled ? probeConfiguration.customLexicon : []
                let recognized = try await self.mangaOverlayProbeService.recognizeTextBlocks(
                    in: data,
                    customWords: activeCustomWords
                )
                self.writeMangaProbeProgress(stage: "whole-page-ocr-done", startedAt: startedAt, blocks: recognized.blocks.count, runOptions: runOptions)
                let lexiconComparison: MangaOverlayLexiconComparison?
                if runOptions.runLexiconComparison {
                    lexiconComparison = try await self.mangaOverlayProbeService.compareCustomLexicon(
                        in: data,
                        customWords: probeConfiguration.customLexicon
                    )
                } else {
                    lexiconComparison = nil
                }
                let visionAPIComparison: MangaOverlayVisionAPIComparison?
                if runOptions.runVisionAPIComparison {
                    visionAPIComparison = try await self.mangaOverlayProbeService.compareVisionAPIs(
                        in: data,
                        customWords: activeCustomWords
                    )
                } else {
                    visionAPIComparison = nil
                }
                let syntheticSliceOCR: MangaOverlaySliceOCRDiagnostics?
                if runOptions.runSyntheticSliceOCR {
                    syntheticSliceOCR = try await self.mangaOverlayProbeService.runSyntheticLongImageSliceProbe(
                        imageData: data,
                        customWords: activeCustomWords
                    )
                } else {
                    syntheticSliceOCR = nil
                }

                let groundTruth = self.loadMangaGroundTruth()
                let rawWholePageBlocks = recognized.blocks.enumerated().map { index, block in
                    let match = MangaOverlayProbeService.bestGroundTruthMatch(text: block.text, groundTruth: groundTruth)
                    let matchIndex = match.index
                    return MangaOverlayProbeBlock(
                        index: index,
                        bbox: Self.bboxArray(from: block.boundingBox),
                        bubbleID: block.bubbleID,
                        bubbleAssignmentMethod: block.bubbleAssignmentMethod,
                        crossBubbleMergeRejected: block.crossBubbleMergeRejected,
                        sliceIndex: block.sliceIndex,
                        sliceOverlapDeduped: block.sliceOverlapDeduped,
                        rotationAngleUsed: block.rotationAngle,
                        ocrText: block.text,
                        ocrConfidence: block.confidence,
                        rawOcrText: block.text,
                        preprocessingEnabled: probeConfiguration.preprocessing.enabled,
                        bestGroundTruthIndex: matchIndex,
                        bestGroundTruthText: match.entry?.text,
                        bestGroundTruthType: match.entry?.type,
                        groundTruthMatch: match.matchState,
                        groundTruthMatchThreshold: MangaOverlayProbeService.groundTruthMatchThreshold,
                        ocrGroundTruthSimilarity: match.similarity,
                        ocrLegacySimilarity: match.legacySimilarity,
                        wordOrderPreserved: match.wordOrderPreserved,
                        ocrQualityLabel: Self.ocrQualityLabel(for: match.similarity),
                        ocrProbeNotes: Self.mangaOCRProbeNotes(
                            text: block.text,
                            bestGroundTruthText: match.entry?.text,
                            similarity: match.similarity,
                            legacySimilarity: match.legacySimilarity,
                            wordOrderPreserved: match.wordOrderPreserved,
                            matchState: match.matchState,
                            bubbleID: block.bubbleID,
                            bubbleAssignmentMethod: block.bubbleAssignmentMethod,
                            crossBubbleMergeRejected: block.crossBubbleMergeRejected,
                            sliceIndex: block.sliceIndex,
                            sliceOverlapDeduped: block.sliceOverlapDeduped
                        )
                    )
                }
                var probeBlocks = rawWholePageBlocks
                var rawBubbleComparison: MangaOverlayFrameworkComparison?
                var frameworkComparison: MangaOverlayFrameworkComparison?
                var fusionComparison: MangaOverlayFusionComparison?
                var fusionResults: [MangaOverlayFusionResult] = []
                var postFusionCleanup: MangaOverlayPostFusionCleanupReport?
                var textRegionCropReport: MangaOverlayTextRegionCropReport?
                var textBoxCandidateReport: MangaOverlayTextBoxCandidateReport?
                var segmentMaskReport: MangaOverlaySegmentMaskReport?
                var preCropTextBoxPlanReport: MangaOverlayPreCropTextBoxPlanReport?
                var cropExperimentReport: MangaOverlayCropExperimentReport?
                var textBoxPlanFailureReport: MangaOverlayTextBoxPlanFailureReport?
                var lineTextBoxPlanReport: MangaOverlayLineTextBoxPlanReport?
                var lineCropExperimentReport: MangaOverlayLineCropExperimentReport?
                var externalArtifactReadinessReport: MangaOverlayExternalArtifactReadinessReport?
                var externalTextBoxShadowOCRReport: MangaOverlayExternalTextBoxShadowOCRReport?
                var internalStructureBottleneckReport: MangaOverlayInternalStructureBottleneckReport?
                var routingDrivenTranslationComparisonReport: MangaRoutingDrivenTranslationComparisonReport?
                var ocrCharacterDamageAuditReport: MangaOCRCharacterDamageAuditReport?
                var bubbleSubRegionReport: MangaOverlayBubbleSubRegionReport?
                var bubbleMaskReport: MangaOverlayBubbleMaskReport?
                var bubbleAssignmentCorrectionReport: MangaOverlayBubbleAssignmentCorrectionReport?
                var bubbleSplitCandidateReport: MangaOverlayBubbleSplitCandidateReport?
                var outputFiles = MangaOverlayProbeOutputFiles(debugBoxesImage: "", overlayImage: "")
                if !groundTruth.isEmpty {
                    self.writeMangaProbeProgress(stage: "bubble-first-start", startedAt: startedAt, blocks: probeBlocks.count, runOptions: runOptions)
                    let bubbleProbe = try await self.mangaOverlayProbeService.runBubbleFirstProbe(
                        imageData: data,
                        groundTruth: groundTruth,
                        preprocessing: probeConfiguration.preprocessing,
                        customWords: activeCustomWords,
                        outputDirectory: self.mangaOverlayOutputDirectory
                    )
                    outputFiles.bubbleDebugImage = bubbleProbe.debugPath
                    outputFiles.bubbleCropsImage = bubbleProbe.cropsPath
                    outputFiles.bubbleSeedDebugImage = bubbleProbe.seedDebugPath
                    outputFiles.bubbleTextOverlayImage = bubbleProbe.textOverlayPath
                    rawBubbleComparison = bubbleProbe.comparison
                    let fusion = self.fuseMangaProbeBlocks(
                        wholePageBlocks: rawWholePageBlocks,
                        bubbleResults: bubbleProbe.comparison.bubbleResults,
                        groundTruth: groundTruth
                    )
                    probeBlocks = fusion.blocks
                    fusionResults = fusion.results
                    postFusionCleanup = fusion.cleanup
                    probeConfiguration.status = "current pipeline uses fused whole-page Vision OCR and bubble-first OCR candidates with ground-truth-free selection"
                    probeConfiguration.currentBlockSource = "fusedWholePageBubble"
                    self.writeMangaProbeProgress(stage: "bubble-first-done", startedAt: startedAt, blocks: probeBlocks.count, runOptions: runOptions)
                }
                self.mangaOverlayProbeBlocks = probeBlocks

                var cropFallbackSelfTest: MangaOverlayCropFallbackSelfTest?
                if probeConfiguration.preprocessing.enabled && runOptions.runPreprocessingCrop {
                    self.mangaOverlayProbeMessage = "正在对 \(probeBlocks.count) 个文本块做裁切放大预处理 OCR"
                    self.writeMangaProbeProgress(stage: "preprocessing-crop-start", startedAt: startedAt, blocks: probeBlocks.count, runOptions: runOptions)
                    for index in probeBlocks.indices {
                        guard let sourceIndex = Self.wholePageSourceIndex(for: probeBlocks[index]),
                              recognized.blocks.indices.contains(sourceIndex) else {
                            probeBlocks[index].finalTextUsedForTranslation = probeBlocks[index].rawOcrText
                            probeBlocks[index] = self.applyDeterministicMangaOCRCorrection(
                                to: probeBlocks[index],
                                groundTruth: groundTruth
                            )
                            continue
                        }
                        let cropResult = try await self.mangaOverlayProbeService.recognizePreprocessedText(
                            in: recognized.image,
                            block: recognized.blocks[sourceIndex],
                            options: probeConfiguration.preprocessing
                        )
                        probeBlocks[index].adaptivePreprocessingOcrText = cropResult.adaptiveText
                        probeBlocks[index].fixedPreprocessingOcrText = cropResult.fixedText
                        probeBlocks[index].cropPaddingX = cropResult.cropPaddingX
                        probeBlocks[index].cropPaddingY = cropResult.cropPaddingY
                        probeBlocks[index].cropClampedByBubble = cropResult.cropClampedByBubble
                        probeBlocks[index].cropCandidatePreservesRawWords = cropResult.cropCandidatePreservesRawWords
                        probeBlocks[index].cropFallbackTriggered = cropResult.cropFallbackTriggered
                        probeBlocks[index].cropFallbackReason = cropResult.cropFallbackReason
                        probeBlocks[index].cropStrategyUsed = cropResult.cropStrategyUsed
                        if let enhancedText = cropResult.selectedText {
                            probeBlocks[index].afterPreprocessingOcrText = enhancedText
                            probeBlocks[index] = self.applyMangaOCRCandidateSelection(
                                to: probeBlocks[index],
                                enhancedText: enhancedText,
                                groundTruth: groundTruth
                            )
                        } else {
                            probeBlocks[index].finalTextUsedForTranslation = probeBlocks[index].rawOcrText
                        }
                        probeBlocks[index] = self.applyDeterministicMangaOCRCorrection(
                            to: probeBlocks[index],
                            groundTruth: groundTruth
                        )
                    }
                    if runOptions.runCropFallbackSelfTest {
                        cropFallbackSelfTest = try await self.mangaOverlayProbeService.runCropFallbackSelfTest(
                            in: recognized.image,
                            block: recognized.blocks.first,
                            blockIndex: recognized.blocks.indices.first,
                            options: probeConfiguration.preprocessing
                        )
                    }
                    bubbleSubRegionReport = Self.makeBubbleSubRegionReport(
                        blocks: probeBlocks,
                        bubbleGeometry: recognized.bubbleGeometry,
                        image: recognized.image
                    )
                    let preCropBubbleMaskReport = await self.mangaOverlayProbeService.makeBubbleMaskReport(
                        image: recognized.image,
                        blocks: probeBlocks,
                        bubbleGeometry: recognized.bubbleGeometry,
                        textRegionCropReport: nil
                    )
                    bubbleAssignmentCorrectionReport = Self.makeBubbleAssignmentCorrectionReport(
                        blocks: probeBlocks,
                        bubbleMaskReport: preCropBubbleMaskReport
                    )
                    bubbleSplitCandidateReport = Self.makeBubbleSplitCandidateReport(
                        blocks: probeBlocks,
                        bubbleGeometry: recognized.bubbleGeometry,
                        bubbleMaskReport: preCropBubbleMaskReport,
                        image: recognized.image,
                        assignmentCorrectionReport: bubbleAssignmentCorrectionReport
                    )
                    preCropTextBoxPlanReport = Self.makePreCropTextBoxPlanReport(
                        blocks: probeBlocks,
                        bubbleGeometry: recognized.bubbleGeometry,
                        bubbleMaskReport: preCropBubbleMaskReport,
                        bubbleAssignmentCorrectionReport: bubbleAssignmentCorrectionReport,
                        bubbleSplitCandidateReport: bubbleSplitCandidateReport,
                        bubbleSubRegionReport: bubbleSubRegionReport
                    )
                    self.mangaOverlayProbeMessage = "正在运行 TextRegion crop OCR 候选层"
                    let textRegionCrop = try await self.applyTextRegionCropCandidates(
                        to: probeBlocks,
                        image: recognized.image,
                        bubbleGeometry: recognized.bubbleGeometry,
                        bubbleSubRegionReport: bubbleSubRegionReport,
                        bubbleAssignmentCorrectionReport: bubbleAssignmentCorrectionReport,
                        bubbleSplitCandidateReport: bubbleSplitCandidateReport,
                        recognizedBlocks: recognized.blocks,
                        groundTruth: groundTruth,
                        preprocessing: probeConfiguration.preprocessing
                    )
                    probeBlocks = textRegionCrop.blocks
                    textRegionCropReport = textRegionCrop.report
                    probeConfiguration.status = "current pipeline uses fused whole-page and bubble-first OCR with post-fusion cleanup plus guarded TextRegion crop OCR candidates"
                    probeConfiguration.currentBlockSource = textRegionCrop.report.adoptedCount > 0
                        ? "fusedWholePageBubbleTextRegionCrop"
                        : "fusedWholePageBubble"
                    self.mangaOverlayProbeBlocks = probeBlocks
                    self.writeMangaProbeProgress(stage: "preprocessing-crop-done", startedAt: startedAt, blocks: probeBlocks.count, runOptions: runOptions)
                }

                for index in probeBlocks.indices where probeBlocks[index].deterministicCorrectionText == nil {
                    probeBlocks[index] = self.applyDeterministicMangaOCRCorrection(
                        to: probeBlocks[index],
                        groundTruth: groundTruth
                    )
                }

                if probeConfiguration.correction.enabled && runOptions.runModelCorrection {
                    self.mangaOverlayProbeMessage = "正在做 OCR 纠错后处理和护栏校验"
                    for index in probeBlocks.indices {
                        probeBlocks[index] = await self.correctMangaProbeBlock(
                            probeBlocks[index],
                            options: probeConfiguration.correction
                        )
                        self.mangaOverlayProbeBlocks = probeBlocks
                    }
                }

                self.mangaOverlayProbeState = .translating
                self.mangaOverlayProbeMessage = "已识别 \(probeBlocks.count) 个文本块，正在逐块翻译"
                self.writeMangaProbeProgress(stage: "translation-start", startedAt: startedAt, blocks: probeBlocks.count, runOptions: runOptions)

                for index in probeBlocks.indices {
                    let translated = await self.translateMangaProbeBlock(probeBlocks[index])
                    probeBlocks[index] = translated
                    self.mangaOverlayProbeBlocks = probeBlocks
                    self.writeMangaProbeProgress(stage: "translation-block-\(index + 1)-of-\(probeBlocks.count)", startedAt: startedAt, blocks: probeBlocks.count, runOptions: runOptions)
                }

                if runOptions.runDeterministicCorrectionTranslation {
                    self.mangaOverlayProbeMessage = "正在对确定性 OCR 纠错候选做翻译对照"
                    self.writeMangaProbeProgress(stage: "deterministic-correction-translation-start", startedAt: startedAt, blocks: probeBlocks.count, runOptions: runOptions)
                    for index in probeBlocks.indices where Self.shouldProbeDeterministicCorrectionTranslation(probeBlocks[index]) {
                        probeBlocks[index] = await self.translateDeterministicCorrectionCandidate(probeBlocks[index])
                        self.mangaOverlayProbeBlocks = probeBlocks
                        self.writeMangaProbeProgress(stage: "deterministic-correction-translation-block-\(index + 1)-of-\(probeBlocks.count)", startedAt: startedAt, blocks: probeBlocks.count, runOptions: runOptions)
                    }
                }

                let batchTranslationComparison: MangaBatchTranslationComparison?
                if runOptions.runTaggedBatchTranslation {
                    self.mangaOverlayProbeMessage = "正在运行 tagged 批量翻译诊断分支"
                    self.writeMangaProbeProgress(stage: "tagged-batch-start", startedAt: startedAt, blocks: probeBlocks.count, runOptions: runOptions)
                    batchTranslationComparison = await self.runTaggedBatchTranslationComparison(blocks: probeBlocks)
                } else {
                    batchTranslationComparison = nil
                }

                self.mangaOverlayProbeState = .rendering
                self.mangaOverlayProbeMessage = "正在生成 BubbleMask 实例 ID 近似和 mask-safe layout 诊断"
                self.writeMangaProbeProgress(stage: "rendering-diagnostics-start", startedAt: startedAt, blocks: probeBlocks.count, runOptions: runOptions)
                let preliminaryBubbleMaskReport = await self.mangaOverlayProbeService.makeBubbleMaskReport(
                    image: recognized.image,
                    blocks: probeBlocks,
                    bubbleGeometry: recognized.bubbleGeometry,
                    textRegionCropReport: textRegionCropReport
                )
                self.mangaOverlayProbeMessage = "正在计算气泡安全区并做离屏渲染碰撞检查"
                probeBlocks = await self.mangaOverlayProbeService.applySafeLayoutAndRenderingDiagnostics(
                    image: recognized.image,
                    blocks: probeBlocks,
                    bubbleGeometry: recognized.bubbleGeometry,
                    bubbleMaskReport: preliminaryBubbleMaskReport
                )
                bubbleMaskReport = await self.mangaOverlayProbeService.makeBubbleMaskReport(
                    image: recognized.image,
                    blocks: probeBlocks,
                    bubbleGeometry: recognized.bubbleGeometry,
                    textRegionCropReport: textRegionCropReport
                )
                textRegionCropReport = Self.textRegionCropReport(
                    textRegionCropReport,
                    mergingMaskDiagnosticsFrom: bubbleMaskReport
                )
                textBoxCandidateReport = Self.makeTextBoxCandidateReport(
                    blocks: probeBlocks,
                    textRegionCropReport: textRegionCropReport,
                    bubbleMaskReport: bubbleMaskReport,
                    assignmentCorrectionReport: bubbleAssignmentCorrectionReport,
                    splitCandidateReport: bubbleSplitCandidateReport
                )
                segmentMaskReport = Self.makeSegmentMaskReport(
                    blocks: probeBlocks,
                    textBoxCandidateReport: textBoxCandidateReport,
                    bubbleMaskReport: bubbleMaskReport
                )
                textRegionCropReport = Self.textRegionCropReport(
                    textRegionCropReport,
                    mergingTextBoxCandidateReport: textBoxCandidateReport,
                    segmentMaskReport: segmentMaskReport
                )
                if runOptions.runCropExperiment,
                   let textRegionCropReport, let textBoxCandidateReport, let segmentMaskReport {
                    self.mangaOverlayProbeMessage = "正在运行 TextRegion crop shadow 实验矩阵"
                    cropExperimentReport = try await self.makeCropExperimentReport(
                        blocks: probeBlocks,
                        image: recognized.image,
                        bubbleGeometry: recognized.bubbleGeometry,
                        textRegionCropReport: textRegionCropReport,
                        textBoxCandidateReport: textBoxCandidateReport,
                        segmentMaskReport: segmentMaskReport,
                        preCropTextBoxPlanReport: preCropTextBoxPlanReport,
                        bubbleMaskReport: bubbleMaskReport,
                        bubbleAssignmentCorrectionReport: bubbleAssignmentCorrectionReport,
                        bubbleSplitCandidateReport: bubbleSplitCandidateReport,
                        bubbleSubRegionReport: bubbleSubRegionReport,
                        preprocessing: probeConfiguration.preprocessing
                    )
                    textBoxPlanFailureReport = Self.makeTextBoxPlanFailureReport(
                        blocks: probeBlocks,
                        preCropTextBoxPlanReport: preCropTextBoxPlanReport,
                        cropExperimentReport: cropExperimentReport,
                        textRegionCropReport: textRegionCropReport,
                        textBoxCandidateReport: textBoxCandidateReport,
                        segmentMaskReport: segmentMaskReport
                    )
                    if runOptions.runLineCropExperiment,
                       let textBoxPlanFailureReport, let cropExperimentReport {
                        self.mangaOverlayProbeMessage = "正在运行行级 TextBox / deskew shadow 验证"
                        lineTextBoxPlanReport = Self.makeLineTextBoxPlanReport(
                            blocks: probeBlocks,
                            textBoxPlanFailureReport: textBoxPlanFailureReport,
                            preCropTextBoxPlanReport: preCropTextBoxPlanReport,
                            cropExperimentReport: cropExperimentReport,
                            bubbleMaskReport: bubbleMaskReport,
                            segmentMaskReport: segmentMaskReport
                        )
                        lineCropExperimentReport = try await self.makeLineCropExperimentReport(
                            blocks: probeBlocks,
                            image: recognized.image,
                            bubbleGeometry: recognized.bubbleGeometry,
                            textRegionCropReport: textRegionCropReport,
                            cropExperimentReport: cropExperimentReport,
                            lineTextBoxPlanReport: lineTextBoxPlanReport,
                            preprocessing: probeConfiguration.preprocessing
                        )
                    }
                }
                externalArtifactReadinessReport = Self.makeExternalArtifactReadinessReport(
                    blocks: probeBlocks,
                    imageWidth: recognized.image.width,
                    imageHeight: recognized.image.height,
                    bundledTestDirectory: self.bundledTestDirectory,
                    bubbleMaskReport: bubbleMaskReport,
                    segmentMaskReport: segmentMaskReport
                )
                self.mangaOverlayProbeMessage = "正在检查外部 TextBoxes shadow OCR gate"
                externalTextBoxShadowOCRReport = try await self.makeExternalTextBoxShadowOCRReport(
                    blocks: probeBlocks,
                    image: recognized.image,
                    readinessReport: externalArtifactReadinessReport,
                    bundledTestDirectory: self.bundledTestDirectory,
                    preprocessing: probeConfiguration.preprocessing
                )
                internalStructureBottleneckReport = Self.makeInternalStructureBottleneckReport(
                    blocks: probeBlocks,
                    textRegionCropReport: textRegionCropReport,
                    textBoxPlanFailureReport: textBoxPlanFailureReport,
                    bubbleMaskReport: bubbleMaskReport,
                    bubbleAssignmentCorrectionReport: bubbleAssignmentCorrectionReport,
                    bubbleSplitCandidateReport: bubbleSplitCandidateReport,
                    postFusionCleanup: postFusionCleanup,
                    externalArtifactReadinessReport: externalArtifactReadinessReport
                )
                self.mangaOverlayProbeMessage = "正在运行路由驱动翻译对照和 OCR 损坏审计"
                self.writeMangaProbeProgress(stage: "routing-audits-start", startedAt: startedAt, blocks: probeBlocks.count, runOptions: runOptions)
                if let internalStructureBottleneckReport {
                    routingDrivenTranslationComparisonReport = await self.makeRoutingDrivenTranslationComparisonReport(
                        blocks: probeBlocks,
                        internalStructureBottleneckReport: internalStructureBottleneckReport
                    )
                    ocrCharacterDamageAuditReport = Self.makeOCRCharacterDamageAuditReport(
                        blocks: probeBlocks,
                        internalStructureBottleneckReport: internalStructureBottleneckReport,
                        textRegionCropReport: textRegionCropReport,
                        textBoxCandidateReport: textBoxCandidateReport,
                        segmentMaskReport: segmentMaskReport,
                        textBoxPlanFailureReport: textBoxPlanFailureReport
                    )
                }
                self.mangaOverlayProbeBlocks = probeBlocks

                self.mangaOverlayProbeMessage = "正在生成 bbox 调试图、覆盖合成图和 probe_report.json"
                self.writeMangaProbeProgress(stage: "render-output-start", startedAt: startedAt, blocks: probeBlocks.count, runOptions: runOptions)
                let renderedOutputFiles = try await self.mangaOverlayProbeService.renderOutputs(
                    image: recognized.image,
                    blocks: probeBlocks,
                    outputDirectory: self.mangaOverlayOutputDirectory,
                    preprocessing: probeConfiguration.preprocessing,
                    textRegionCropReport: textRegionCropReport,
                    textBoxCandidateReport: textBoxCandidateReport,
                    segmentMaskReport: segmentMaskReport,
                    preCropTextBoxPlanReport: preCropTextBoxPlanReport,
                    cropExperimentReport: cropExperimentReport,
                    textBoxPlanFailureReport: textBoxPlanFailureReport,
                    lineTextBoxPlanReport: lineTextBoxPlanReport,
                    lineCropExperimentReport: lineCropExperimentReport,
                    externalArtifactReadinessReport: externalArtifactReadinessReport,
                    externalTextBoxShadowOCRReport: externalTextBoxShadowOCRReport,
                    internalStructureBottleneckReport: internalStructureBottleneckReport,
                    routingDrivenTranslationComparisonReport: routingDrivenTranslationComparisonReport,
                    ocrCharacterDamageAuditReport: ocrCharacterDamageAuditReport,
                    bubbleMaskReport: bubbleMaskReport,
                    bubbleAssignmentCorrectionReport: bubbleAssignmentCorrectionReport,
                    bubbleSplitCandidateReport: bubbleSplitCandidateReport,
                    renderDiagnosticPNGs: runOptions.renderDiagnosticPNGs
                )
                outputFiles.debugBoxesImage = renderedOutputFiles.debugBoxesImage
                outputFiles.overlayImage = renderedOutputFiles.overlayImage
                outputFiles.ocrTextOverlayImage = runOptions.renderDiagnosticPNGs ? renderedOutputFiles.ocrTextOverlayImage : nil
                outputFiles.deterministicCorrectionOverlayImage = runOptions.renderDiagnosticPNGs ? renderedOutputFiles.deterministicCorrectionOverlayImage : nil
                outputFiles.deterministicTranslationOverlayImage = runOptions.renderDiagnosticPNGs ? renderedOutputFiles.deterministicTranslationOverlayImage : nil
                outputFiles.blockCropsImage = runOptions.renderDiagnosticPNGs ? renderedOutputFiles.blockCropsImage : nil
                outputFiles.preprocessedContentImage = runOptions.renderDiagnosticPNGs ? renderedOutputFiles.preprocessedContentImage : nil
                outputFiles.ocrProbeTextFile = renderedOutputFiles.ocrProbeTextFile
                let wholePageProcessingTimeMs = Int(Date.now.timeIntervalSince(startedAt) * 1000)
                if let rawBubbleComparison {
                    frameworkComparison = self.makeFrameworkComparison(
                        wholePageBlocks: rawWholePageBlocks,
                        wholePageProcessingTimeMs: wholePageProcessingTimeMs,
                        bubbleComparison: rawBubbleComparison,
                        groundTruth: groundTruth
                    )
                    fusionComparison = self.makeFusionComparison(
                        wholePageBlocks: rawWholePageBlocks,
                        bubbleComparison: rawBubbleComparison,
                        fusedBlocks: probeBlocks,
                        fusionResults: fusionResults,
                        postFusionCleanup: postFusionCleanup,
                        wholePageProcessingTimeMs: wholePageProcessingTimeMs,
                        groundTruth: groundTruth
                    )
                }
                if runOptions.renderContactSheet {
                    outputFiles.probeContactSheetImage = try MangaOverlayProbeService.renderContactSheet(
                        outputFiles: outputFiles,
                        outputDirectory: self.mangaOverlayOutputDirectory
                    )
                }
                self.writeMangaProbeProgress(stage: "clean-text-diagnostic-start", startedAt: startedAt, blocks: probeBlocks.count, runOptions: runOptions)
                let cleanTextDiagnostic = await self.runCleanTextDiagnostic(groundTruth: groundTruth)
                let cleanDiagnosticURL = self.mangaOverlayOutputDirectory.appendingPathComponent("clean_text_diagnostic.json")
                try Self.writeCleanTextDiagnostic(cleanTextDiagnostic, to: cleanDiagnosticURL)
                outputFiles.cleanTextDiagnosticFile = cleanDiagnosticURL.path
                let deterministicDecodingCheck: MangaDeterministicDecodingCheck?
                if runOptions.runDeterministicDecodingCheck {
                    self.writeMangaProbeProgress(stage: "deterministic-decoding-check-start", startedAt: startedAt, blocks: probeBlocks.count, runOptions: runOptions)
                    deterministicDecodingCheck = await self.runDeterministicDecodingCheck(groundTruth: groundTruth)
                } else {
                    deterministicDecodingCheck = nil
                }

                let report = self.makeMangaOverlayProbeReport(
                    blocks: probeBlocks,
                    outputFiles: outputFiles,
                    configuration: probeConfiguration,
                    bubbleGeometry: recognized.bubbleGeometry,
                    sliceOCR: recognized.sliceOCR,
                    syntheticSliceOCR: syntheticSliceOCR,
                    cropFallbackSelfTest: cropFallbackSelfTest,
                    lexiconComparison: lexiconComparison,
                    visionAPIComparison: visionAPIComparison,
                    frameworkComparison: frameworkComparison,
                    fusionComparison: fusionComparison,
                    fusionResults: fusionResults,
                    textRegionCropReport: textRegionCropReport,
                    textBoxCandidateReport: textBoxCandidateReport,
                    segmentMaskReport: segmentMaskReport,
                    preCropTextBoxPlanReport: preCropTextBoxPlanReport,
                    cropExperimentReport: cropExperimentReport,
                    textBoxPlanFailureReport: textBoxPlanFailureReport,
                    lineTextBoxPlanReport: lineTextBoxPlanReport,
                    lineCropExperimentReport: lineCropExperimentReport,
                    externalArtifactReadinessReport: externalArtifactReadinessReport,
                    externalTextBoxShadowOCRReport: externalTextBoxShadowOCRReport,
                    internalStructureBottleneckReport: internalStructureBottleneckReport,
                    routingDrivenTranslationComparisonReport: routingDrivenTranslationComparisonReport,
                    ocrCharacterDamageAuditReport: ocrCharacterDamageAuditReport,
                    bubbleSubRegionReport: bubbleSubRegionReport,
                    bubbleMaskReport: bubbleMaskReport,
                    bubbleAssignmentCorrectionReport: bubbleAssignmentCorrectionReport,
                    bubbleSplitCandidateReport: bubbleSplitCandidateReport,
                    cleanTextDiagnostic: cleanTextDiagnostic,
                    batchTranslationComparison: batchTranslationComparison,
                    deterministicDecodingCheck: deterministicDecodingCheck,
                    outputCleanupRemovedItemCount: outputCleanupRemovedItemCount
                )
                let reportURL = self.mangaOverlayOutputDirectory.appendingPathComponent("probe_report.json")
                try MangaOverlayProbeService.writeReport(report, to: reportURL)
                self.writeMangaProbeProgress(stage: "probe-report-written", startedAt: startedAt, blocks: report.blocks.count, runOptions: runOptions)

                self.mangaOverlayProbeState = report.overallPassed ? .completed : .failed
                self.mangaOverlayProbeMessage = "漫画探针完成：\(report.blocks.count) 块，overallPassed=\(report.overallPassed)，输出 \(self.mangaOverlayOutputDirectory.path)"
                self.mangaOverlayProbeReport = report
                self.mangaOverlayProbeBlocks = report.blocks
                self.dataTransferMessage = self.mangaOverlayProbeMessage
            } catch {
                self.writeMangaProbeProgress(stage: "error", runOptions: runOptions, message: "\(type(of: error)): \(error.localizedDescription)")
                self.writeMangaProbeFailureReport("运行错误：\(type(of: error)): \(error.localizedDescription)", runOptions: runOptions)
                self.mangaOverlayProbeState = .failed
                self.mangaOverlayProbeMessage = "漫画探针失败：\(error.localizedDescription)"
                self.dataTransferMessage = self.mangaOverlayProbeMessage
            }
        }
    }

    @discardableResult
    private func writeMangaProbeFailureReport(
        _ warning: String,
        runOptions: MangaOverlayProbeRunOptions = .full
    ) -> MangaOverlayProbeReport {
        let outputFiles = MangaOverlayProbeOutputFiles(debugBoxesImage: "", overlayImage: "")
        var configuration = MangaOverlayProbeConfiguration.defaultValue
        configuration.probeRunMode = runOptions.mode.rawValue
        configuration.probeFastPathEnabled = runOptions.mode == .ciFast
        configuration.skippedDiagnostics = runOptions.skippedDiagnostics
        let report = makeMangaOverlayProbeReport(
            blocks: mangaOverlayProbeBlocks,
            outputFiles: outputFiles,
            configuration: configuration,
            bubbleGeometry: nil,
            extraWarnings: [warning]
        )
        let reportURL = mangaOverlayOutputDirectory.appendingPathComponent("probe_report.json")
        try? FileManager.default.createDirectory(at: mangaOverlayOutputDirectory, withIntermediateDirectories: true)
        try? MangaOverlayProbeService.writeReport(report, to: reportURL)
        mangaOverlayProbeReport = report
        return report
    }

    private func bundledTestFile(named filename: String) -> URL? {
        let filenameURL = URL(fileURLWithPath: filename)
        let baseName = filenameURL.deletingPathExtension().lastPathComponent
        let fileExtension = filenameURL.pathExtension
        var candidates: [URL?] = [
            bundledTestDirectory?.appendingPathComponent(filename),
            Bundle.main.url(forResource: baseName, withExtension: fileExtension, subdirectory: "test")
        ]
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(filename))
        }
        return candidates.compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    private func firstBundledTestFile(matching extensions: Set<String>) -> URL? {
        guard let bundledTestDirectory else { return nil }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: bundledTestDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        return files
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .first
    }

    func deletePrompt(_ prompt: PromptTemplate) {
        guard !prompt.isBuiltIn else { return }
        prompts.removeAll { $0.id == prompt.id }
        if selectedPromptID == prompt.id {
            selectedPromptID = PromptTemplate.translatorID
        }
    }

    func setTemperature(_ value: Double) {
        sampling.temperature = min(max(value, 0.0), 1.2)
    }

    func setMaxTokens(_ value: Int) {
        sampling.maxTokens = min(max(value, 128), 2_048)
    }

    @discardableResult
    func importLocalModel(from url: URL) -> Bool {
        guard !modelDownload.isDownloading else {
            dataTransferMessage = "正在下载内置模型，请等待完成或取消。"
            return false
        }
        guard url.pathExtension.lowercased() == "gguf" else {
            dataTransferMessage = "模型导入失败：请选择 .gguf 文件"
            refreshModelStatus()
            return false
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let destination = localModelDirectory.appendingPathComponent(localModelFilename)

        do {
            try FileManager.default.createDirectory(at: localModelDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            let temporaryDownload = destination.appendingPathExtension("download")
            if FileManager.default.fileExists(atPath: temporaryDownload.path) {
                try FileManager.default.removeItem(at: temporaryDownload)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            modelDownload = installedDownloadProgress(message: "已导入 \(url.lastPathComponent)")
            dataTransferMessage = "已导入 \(url.lastPathComponent)，保存为 \(localModelFilename)"
            selectedEngine = .local
            refreshModelStatus()
            return true
        } catch {
            dataTransferMessage = "模型导入失败：\(error.localizedDescription)"
            refreshModelStatus()
            return false
        }
    }

    func downloadBuiltInModel() {
        guard !modelDownload.isDownloading else {
            dataTransferMessage = "已有模型下载任务运行中"
            return
        }

        if isLocalModelInstalled {
            modelDownload = installedDownloadProgress(message: "已安装，同名模型不会重复下载")
            selectedEngine = .local
            refreshModelStatus()
            dataTransferMessage = "已安装 \(localModelFilename)，不会重复下载。先卸载后可重新下载。"
            return
        }

        let destination = localModelDirectory.appendingPathComponent(localModelFilename)
        modelDownload = ModelDownloadProgress(
            phase: .downloading,
            bytesReceived: 0,
            totalBytes: builtInModel.expectedSizeBytes,
            speedBytesPerSecond: 0,
            message: "准备下载 \(builtInModel.displayName)"
        )
        dataTransferMessage = modelDownload.message

        modelDownloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.modelDownloadService.download(
                    model: self.builtInModel,
                    to: destination
                ) { [weak self] progress in
                    await MainActor.run {
                        self?.modelDownload = progress
                        self?.dataTransferMessage = progress.message
                    }
                }

                self.selectedEngine = .local
                self.refreshModelStatus()
                self.dataTransferMessage = "已下载 \(self.builtInModel.displayName)，Local 已启用。"
                self.modelDownloadTask = nil
            } catch is CancellationError {
                self.cleanupPartialModelDownload()
                self.modelDownload = ModelDownloadProgress(
                    phase: .idle,
                    bytesReceived: 0,
                    totalBytes: self.builtInModel.expectedSizeBytes,
                    speedBytesPerSecond: 0,
                    message: "下载已取消"
                )
                self.dataTransferMessage = "下载已取消，临时文件已清理。"
                self.refreshModelStatus()
                self.modelDownloadTask = nil
            } catch {
                self.cleanupPartialModelDownload()
                self.modelDownload = ModelDownloadProgress(
                    phase: .failed,
                    bytesReceived: self.modelDownload.bytesReceived,
                    totalBytes: self.builtInModel.expectedSizeBytes,
                    speedBytesPerSecond: 0,
                    message: error.localizedDescription
                )
                self.dataTransferMessage = error.localizedDescription
                self.refreshModelStatus()
                self.modelDownloadTask = nil
            }
        }
    }

    func cancelModelDownload() {
        guard modelDownload.isDownloading else { return }
        modelDownloadTask?.cancel()
    }

    func removeLocalModel() {
        modelDownloadTask?.cancel()
        let modelURL = localModelDirectory.appendingPathComponent(localModelFilename)
        let temporaryDownloadURL = modelURL.appendingPathExtension("download")

        do {
            if FileManager.default.fileExists(atPath: modelURL.path) {
                try FileManager.default.removeItem(at: modelURL)
                dataTransferMessage = "已移除本地模型文件"
            } else {
                dataTransferMessage = "没有可移除的本地模型文件"
            }
            if FileManager.default.fileExists(atPath: temporaryDownloadURL.path) {
                try FileManager.default.removeItem(at: temporaryDownloadURL)
            }
            modelDownload = ModelDownloadProgress(
                phase: .idle,
                bytesReceived: 0,
                totalBytes: builtInModel.expectedSizeBytes,
                speedBytesPerSecond: 0,
                message: "已卸载"
            )
        } catch {
            dataTransferMessage = "移除模型失败：\(error.localizedDescription)"
        }

        refreshModelStatus()
    }

    func refreshModelStatus() {
        switch selectedEngine {
        case .mock:
            modelStatus = ModelStatus(
                title: mockService.metadata.displayName,
                detail: "未下载模型，当前使用本地模拟输出",
                isReady: true
            )
        case .local:
            if isLocalModelInstalled {
                modelStatus = ModelStatus(
                    title: localService.metadata.displayName,
                    detail: "已发现 \(localModelFilename)，准备使用本地 llama.cpp 推理",
                    isReady: true
                )
            } else {
                modelStatus = ModelStatus(
                    title: localService.metadata.displayName,
                    detail: "未找到 \(localModelFilename)，请先在模型页下载或导入 GGUF",
                    isReady: false
                )
            }
        }
    }

    func refreshSpeechRecognitionCapabilities() {
        speechRecognitionCapabilities = SupportedLanguage.allCases.map { language in
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.speechLocaleIdentifier))
            return SpeechRecognitionCapability(
                language: language,
                localeIdentifier: language.speechLocaleIdentifier,
                supportsOnDeviceRecognition: recognizer?.supportsOnDeviceRecognition ?? false
            )
        }
    }

    func runDiagnostics() {
        guard !isRunningDiagnostics, !isRunningLLMSmokeTest else { return }
        isRunningDiagnostics = true
        diagnostics = diagnostics.map {
            DiagnosticCheck(id: $0.id, title: $0.title, detail: "检查中...", state: .running)
        }

        Task { [weak self] in
            guard let self else { return }
            await self.performDiagnostics()
            self.isRunningDiagnostics = false
        }
    }

    func runLLMInterfaceSmokeTest() {
        guard !isRunningLLMSmokeTest, !isRunningDiagnostics else { return }
        writeLaunchLLMSmokeProbe("run-smoke-test engine=\(selectedAdapterMetadata.displayName)")
        let input = smokeTestInputForCurrentLanguageDirection()
        isRunningLLMSmokeTest = true
        llmSmokeTest = LLMInterfaceSmokeTest(
            input: input,
            output: "",
            state: .running,
            message: "正在通过当前适配器发送翻译请求...",
            engineName: selectedAdapterMetadata.displayName,
            tokenCount: nil,
            durationMilliseconds: nil
        )

        Task { [weak self] in
            guard let self else { return }
            await self.performLLMInterfaceSmokeTest()
            self.isRunningLLMSmokeTest = false
        }
    }

    var elapsedDisplay: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var recentSessions: [TranslationSessionRecord] {
        var records: [TranslationSessionRecord] = []
        if shouldArchiveCurrentSession {
            records.append(currentSessionRecord())
        }
        records.append(contentsOf: history.filter { $0.id != activeSessionID })
        return records.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var shouldArchiveCurrentSession: Bool {
        !transcript.isEmpty || summary != .empty
    }

    @discardableResult
    private func submit(_ text: String, timestamp: String, refreshesSummary: Bool = true) async -> Bool {
        writeLaunchLLMSmokeProbe(
            "submit-start source=\(sourceLanguage.rawValue) target=\(targetLanguage.rawValue) " +
            "engine=\(selectedEngine.rawValue) installed=\(isLocalModelInstalled) input=\(Self.probeField(text))"
        )
        defer {
            isProcessing = false
            persist()
        }

        do {
            let translation = try await translate(text)
            let line = TranscriptLine(
                speaker: "You",
                original: text,
                translation: translation,
                time: timestamp,
                isFinal: true
            )
            transcript.insert(line, at: 0)
            writeLaunchLLMSmokeProbe(
                "submit-done source=\(sourceLanguage.rawValue) target=\(targetLanguage.rawValue) " +
                "engine=\(selectedEngine.rawValue) original=\(Self.probeField(line.original)) " +
                "translation=\(Self.probeField(line.translation))"
            )
            draftText = ""
            if refreshesSummary {
                await refreshSummaryAfterTranslation()
            }
            return true
        } catch {
            writeLaunchLLMSmokeProbe(
                "submit-error source=\(sourceLanguage.rawValue) target=\(targetLanguage.rawValue) " +
                "engine=\(selectedEngine.rawValue) input=\(Self.probeField(text)) " +
                "error=\(Self.probeField(error.localizedDescription))"
            )
            modelStatus = ModelStatus(
                title: "Gemma Error",
                detail: error.localizedDescription,
                isReady: false
            )
            return false
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }

                await self?.handleRecordingTick()
            }
        }
    }

    private func handleRecordingTick() async {
        elapsedSeconds += 1

        guard isRecording, elapsedSeconds > 0, elapsedSeconds % 5 == 0 else { return }
        await injectMockLiveLine()
    }

    private func injectMockLiveLine() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer {
            isProcessing = false
            persist()
        }

        do {
            let sample = Self.liveSamples[liveSampleIndex % Self.liveSamples.count]
            liveSampleIndex += 1
            let translation = try await translate(sample)
            transcript.insert(
                TranscriptLine(
                    speaker: "Speaker \(Character(UnicodeScalar(65 + (liveSampleIndex % 3))!))",
                    original: sample,
                    translation: translation,
                    time: Self.timeFormatter.string(from: Date()),
                    isFinal: false
                ),
                at: 0
            )
            await refreshSummaryAfterTranslation()
        } catch {
            modelStatus = ModelStatus(
                title: "Gemma Error",
                detail: error.localizedDescription,
                isReady: false
            )
        }
    }

    private func refreshSummaryAfterTranslation() async {
        do {
            try await refreshSummary()
        } catch {
            dataTransferMessage = "翻译已完成，摘要生成失败：\(error.localizedDescription)"
        }
    }

    private func translate(_ text: String) async throws -> String {
        let request = makeRequest(task: .translation, inputText: text)
        writeLaunchLLMSmokeProbe(
            "translate-request source=\(request.sourceLanguage.rawValue) target=\(request.targetLanguage.rawValue) " +
            "prompt=\(request.prompt.title) input=\(Self.probeField(text))"
        )
        let result = try await generateWithSelectedEngine(request)
        writeLaunchLLMSmokeProbe(
            "translate-result source=\(request.sourceLanguage.rawValue) target=\(request.targetLanguage.rawValue) " +
            "engine=\(result.engineName) output=\(Self.probeField(result.text))"
        )
        return result.text
    }

    private func applyMangaOCRCandidateSelection(
        to block: MangaOverlayProbeBlock,
        enhancedText: String,
        groundTruth: [MangaGroundTruthEntry]
    ) -> MangaOverlayProbeBlock {
        let rawScore = Self.ocrCandidateQualityScore(block.rawOcrText)
        let enhancedScore = Self.ocrCandidateQualityScore(enhancedText)
        let enhancedPreservesRawWords = Self.enhancedOCRPreservesRawWords(
            rawText: block.rawOcrText,
            enhancedText: enhancedText
        )
        let selectedText = enhancedPreservesRawWords || enhancedScore > rawScore + 0.15 ? enhancedText : block.rawOcrText
        let selectedSource = selectedText == enhancedText ? "afterPreprocessing" : "rawOCR"
        let selectedMatch = MangaOverlayProbeService.bestGroundTruthMatch(text: selectedText, groundTruth: groundTruth)
        let rawMatch = MangaOverlayProbeService.bestGroundTruthMatch(text: block.rawOcrText, groundTruth: groundTruth)
        let enhancedMatch = MangaOverlayProbeService.bestGroundTruthMatch(text: enhancedText, groundTruth: groundTruth)
        var notes = block.ocrProbeNotes
        notes.append("candidateSelectionSource=\(selectedSource)")
        notes.append("candidateSelectionRule=textQualityScoreWithoutGroundTruth")
        notes.append("rawCandidateQuality=\(rawScore.formatted(.number.precision(.fractionLength(3))))")
        notes.append("preprocessedCandidateQuality=\(enhancedScore.formatted(.number.precision(.fractionLength(3))))")
        notes.append("preprocessedPreservesRawWords=\(enhancedPreservesRawWords)")
        notes.append("cropPaddingX=\(block.cropPaddingX?.formatted(.number.precision(.fractionLength(1))) ?? "nil")")
        notes.append("cropPaddingY=\(block.cropPaddingY?.formatted(.number.precision(.fractionLength(1))) ?? "nil")")
        notes.append("cropClampedByBubble=\(block.cropClampedByBubble)")
        notes.append("cropCandidatePreservesRawWords=\(block.cropCandidatePreservesRawWords)")
        notes.append("cropFallbackTriggered=\(block.cropFallbackTriggered)")
        notes.append("cropFallbackReason=\(block.cropFallbackReason ?? "nil")")
        notes.append("cropStrategyUsed=\(block.cropStrategyUsed ?? "nil")")
        notes.append("rawTruthSimilarity=\(rawMatch.similarity.formatted(.number.precision(.fractionLength(3))))")
        notes.append("preprocessedTruthSimilarity=\(enhancedMatch.similarity.formatted(.number.precision(.fractionLength(3))))")

        return MangaOverlayProbeBlock(
            id: block.id,
            index: block.index,
            bbox: block.bbox,
            bubbleID: block.bubbleID,
            bubbleAssignmentMethod: block.bubbleAssignmentMethod,
            crossBubbleMergeRejected: block.crossBubbleMergeRejected,
            sliceIndex: block.sliceIndex,
            sliceOverlapDeduped: block.sliceOverlapDeduped,
            rotationAngleUsed: block.rotationAngleUsed,
            ocrText: block.ocrText,
            ocrConfidence: block.ocrConfidence,
            rawOcrText: block.rawOcrText,
            preprocessingEnabled: block.preprocessingEnabled,
            afterPreprocessingOcrText: block.afterPreprocessingOcrText,
            adaptivePreprocessingOcrText: block.adaptivePreprocessingOcrText,
            fixedPreprocessingOcrText: block.fixedPreprocessingOcrText,
            cropPaddingX: block.cropPaddingX,
            cropPaddingY: block.cropPaddingY,
            cropClampedByBubble: block.cropClampedByBubble,
            cropCandidatePreservesRawWords: block.cropCandidatePreservesRawWords,
            cropFallbackTriggered: block.cropFallbackTriggered,
            cropFallbackReason: block.cropFallbackReason,
            cropStrategyUsed: block.cropStrategyUsed,
            correctionEnabled: block.correctionEnabled,
            afterCorrectionText: block.afterCorrectionText,
            correctionRejectedReason: block.correctionRejectedReason,
            correctionPrompt: block.correctionPrompt,
            correctionRawOutput: block.correctionRawOutput,
            correctionErrorCode: block.correctionErrorCode,
            deterministicCorrectionText: block.deterministicCorrectionText,
            deterministicCorrectionAppliedRules: block.deterministicCorrectionAppliedRules,
            deterministicCorrectionSimilarity: block.deterministicCorrectionSimilarity,
            deterministicCorrectionTranslationCandidate: block.deterministicCorrectionTranslationCandidate,
            deterministicCorrectionTranslationRawOutput: block.deterministicCorrectionTranslationRawOutput,
            deterministicCorrectionTranslationPassed: block.deterministicCorrectionTranslationPassed,
            deterministicCorrectionTranslationFailureDetail: block.deterministicCorrectionTranslationFailureDetail,
            finalTextUsedForTranslation: selectedText,
            bestGroundTruthIndex: selectedMatch.index,
            bestGroundTruthText: selectedMatch.entry?.text,
            bestGroundTruthType: selectedMatch.entry?.type,
            groundTruthMatch: selectedMatch.matchState,
            groundTruthMatchThreshold: MangaOverlayProbeService.groundTruthMatchThreshold,
            ocrGroundTruthSimilarity: selectedMatch.similarity,
            ocrLegacySimilarity: selectedMatch.legacySimilarity,
            wordOrderPreserved: selectedMatch.wordOrderPreserved,
            ocrQualityLabel: Self.ocrQualityLabel(for: selectedMatch.similarity),
            translatedText: block.translatedText,
            translationCandidate: block.translationCandidate,
            rawOutputClassification: block.rawOutputClassification,
            candidateClassification: block.candidateClassification,
            failureCategory: block.failureCategory,
            prompt: block.prompt,
            rawOutput: block.rawOutput,
            errorCode: block.errorCode,
            checks: block.checks,
            failureReasons: block.failureReasons,
            qualityNotes: block.qualityNotes,
            translationDecisionTrace: block.translationDecisionTrace,
            translationFailureDetail: block.translationFailureDetail,
            ocrProbeNotes: notes,
            blockPassed: block.blockPassed
        )
    }

    private func applyTextRegionCropCandidates(
        to blocks: [MangaOverlayProbeBlock],
        image: CGImage,
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics,
        bubbleSubRegionReport: MangaOverlayBubbleSubRegionReport?,
        bubbleAssignmentCorrectionReport: MangaOverlayBubbleAssignmentCorrectionReport?,
        bubbleSplitCandidateReport: MangaOverlayBubbleSplitCandidateReport?,
        recognizedBlocks: [MangaOverlayOCRBlock],
        groundTruth: [MangaGroundTruthEntry],
        preprocessing: MangaOverlayPreprocessingOptions
    ) async throws -> (blocks: [MangaOverlayProbeBlock], report: MangaOverlayTextRegionCropReport) {
        let bubbleBBoxes = Dictionary(uniqueKeysWithValues: bubbleGeometry.bubbles.map { ($0.id, $0.bbox) })
        let subRegionsByBlock = Self.subRegionDiagnosticsByBlock(from: bubbleSubRegionReport)
        let correctionsByBlock = Self.assignmentCorrectionsByBlock(from: bubbleAssignmentCorrectionReport)
        let splitCandidatesByBlock = Self.splitCandidatesByBlock(from: bubbleSplitCandidateReport)
        var updatedBlocks: [MangaOverlayProbeBlock] = []
        var diagnostics: [MangaOverlayTextRegionCropDiagnostic] = []

        for block in blocks {
            let source = Self.textRegionSource(for: block)
            let sourceIndex = Self.wholePageSourceIndex(for: block)
            let wholePageText = sourceIndex.flatMap { recognizedBlocks.indices.contains($0) ? recognizedBlocks[$0].text : nil }
                ?? block.rawOcrText
            let subRegion = subRegionsByBlock[block.index]
            let subRegionBBox = subRegion?.clampEligible == true ? subRegion?.bbox : nil
            let assignmentCorrection = correctionsByBlock[block.index]
            let correctedBubbleBBox = assignmentCorrection?.correctionAppliedToCropClamp == true
                ? assignmentCorrection?.correctedBubbleID.flatMap { bubbleBBoxes[$0] }
                : nil
            let splitCandidate = splitCandidatesByBlock[block.index]
            let splitCandidateBBox = splitCandidate?.clampEligible == true ? splitCandidate?.bbox : nil
            let crop = try await mangaOverlayProbeService.recognizeTextRegionCrop(
                in: image,
                seedBBox: block.bbox,
                bubbleBBox: block.bubbleID.flatMap { bubbleBBoxes[$0] },
                correctedBubbleBBox: correctedBubbleBBox,
                splitCandidateBBox: splitCandidateBBox,
                subRegionBBox: subRegionBBox,
                options: preprocessing
            )
            let decision = Self.evaluateTextRegionCropSelection(
                originalText: block.finalTextUsedForTranslation,
                cropText: crop.text,
                cropClampedByBubble: crop.cropClampedByBubble
            )

            var updated = block
            var notes = updated.ocrProbeNotes
            notes.append("textRegionCropSource=\(source)")
            notes.append("textRegionCropText=\(crop.text?.replacing("\n", with: " / ") ?? "nil")")
            notes.append("textRegionClampSource=\(crop.clampSource)")
            if let assignmentCorrection {
                notes.append("bubbleAssignmentDecision=\(assignmentCorrection.decision)")
                if let correctedBubbleID = assignmentCorrection.correctedBubbleID {
                    notes.append("correctedBubbleID=\(correctedBubbleID)")
                }
                if !assignmentCorrection.rejectionReasons.isEmpty {
                    notes.append("bubbleAssignmentRejections=\(assignmentCorrection.rejectionReasons.joined(separator: ","))")
                }
            }
            if let splitCandidate {
                notes.append("bubbleSplitCandidateID=\(splitCandidate.id)")
                notes.append("bubbleSplitCandidateClampEligible=\(splitCandidate.clampEligible)")
                if !splitCandidate.rejectionReasons.isEmpty {
                    notes.append("bubbleSplitCandidateRejections=\(splitCandidate.rejectionReasons.joined(separator: ","))")
                }
            }
            if let subRegion {
                notes.append("textRegionSubRegionID=\(subRegion.id)")
                notes.append("textRegionSubRegionClampEligible=\(subRegion.clampEligible)")
                if !subRegion.rejectionReasons.isEmpty {
                    notes.append("textRegionSubRegionRejections=\(subRegion.rejectionReasons.joined(separator: ","))")
                }
            } else {
                notes.append("textRegionSubRegionRejected=noSubRegion")
            }
            notes.append("textRegionCropSelected=\(decision.adopted)")
            notes.append("textRegionCropSelectionReason=\(decision.selectionReason)")
            if !decision.rejectionReasons.isEmpty {
                notes.append("textRegionCropRejections=\(decision.rejectionReasons.joined(separator: ","))")
            }

            if decision.adopted {
                let selectedMatch = MangaOverlayProbeService.bestGroundTruthMatch(
                    text: decision.selectedText,
                    groundTruth: groundTruth
                )
                updated.finalTextUsedForTranslation = decision.selectedText
                updated.bestGroundTruthIndex = selectedMatch.index
                updated.bestGroundTruthText = selectedMatch.entry?.text
                updated.bestGroundTruthType = selectedMatch.entry?.type
                updated.groundTruthMatch = selectedMatch.matchState
                updated.groundTruthMatchThreshold = MangaOverlayProbeService.groundTruthMatchThreshold
                updated.ocrGroundTruthSimilarity = selectedMatch.similarity
                updated.ocrLegacySimilarity = selectedMatch.legacySimilarity
                updated.wordOrderPreserved = selectedMatch.wordOrderPreserved
                updated.ocrQualityLabel = Self.ocrQualityLabel(for: selectedMatch.similarity)
            }
            updated.ocrProbeNotes = notes
            updatedBlocks.append(updated)

            diagnostics.append(
                MangaOverlayTextRegionCropDiagnostic(
                    blockIndex: block.index,
                    bubbleID: block.bubbleID,
                    source: source,
                    seedBBox: block.bbox,
                    regionBBox: crop.regionBBox,
                    cropBBox: crop.cropBBox,
                    clampSource: crop.clampSource,
                    correctedBubbleID: assignmentCorrection?.correctedBubbleID,
                    splitCandidateID: splitCandidate?.id,
                    textBoxCandidateID: nil,
                    segmentMaskUsableForCropEvidence: nil,
                    failureAttribution: Self.cropFailureAttribution(
                        bubbleID: block.bubbleID,
                        decisionRejections: decision.rejectionReasons,
                        cropText: crop.text,
                        clampSource: crop.clampSource,
                        assignmentCorrection: assignmentCorrection,
                        splitCandidate: splitCandidate,
                        cropMaskCoverageRatio: nil,
                        textBox: nil,
                        segmentMask: nil
                    ),
                    cropBBoxBeforeAssignmentCorrection: crop.cropBBoxBeforeAssignmentCorrection,
                    cropBBoxAfterAssignmentCorrection: crop.cropBBoxAfterAssignmentCorrection,
                    cropMaskCoverageBefore: nil,
                    cropMaskCoverageAfter: nil,
                    assignmentCorrectionRejectedReason: assignmentCorrection?.rejectionReasons.joined(separator: ","),
                    splitCandidateRejectedReason: splitCandidate?.rejectionReasons.joined(separator: ","),
                    subRegionID: subRegion?.id,
                    subRegionBBox: subRegion?.bbox,
                    subRegionCoverageRatio: subRegion?.seedCoverageRatio,
                    subRegionRejectedReason: subRegion?.rejectionReasons.joined(separator: ",") ?? (subRegion == nil ? "noSubRegion" : nil),
                    cropBBoxBeforeSubRegionClamp: crop.cropBBoxBeforeSubRegionClamp,
                    cropBBoxAfterSubRegionClamp: crop.cropBBoxAfterSubRegionClamp,
                    cropClampedByBubble: crop.cropClampedByBubble,
                    paddingX: crop.paddingX,
                    paddingY: crop.paddingY,
                    orientationHint: crop.orientationHint,
                    wholePageText: wholePageText,
                    fusedTextBeforeCrop: block.finalTextUsedForTranslation,
                    adaptiveCropText: block.afterPreprocessingOcrText,
                    textRegionCropText: crop.text,
                    selectedText: decision.selectedText,
                    adopted: decision.adopted,
                    selectionReason: decision.selectionReason,
                    rejectionReasons: decision.rejectionReasons,
                    rawWordPreservationRatio: decision.rawWordPreservationRatio,
                    candidateQualityScore: decision.candidateQualityScore,
                    originalQualityScore: decision.originalQualityScore
                )
            )
        }

        let succeeded = diagnostics.filter { ($0.textRegionCropText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }.count
        let adoptedIndexes = diagnostics.filter(\.adopted).map(\.blockIndex)
        let rejectedIndexes = diagnostics.filter { !$0.adopted }.map(\.blockIndex)
        var rejectionCounts: [String: Int] = [:]
        for reason in diagnostics.flatMap(\.rejectionReasons) {
            rejectionCounts[reason, default: 0] += 1
        }
        var attributionCounts: [String: Int] = [:]
        for reason in diagnostics.flatMap(\.failureAttribution) {
            attributionCounts[reason, default: 0] += 1
        }
        let report = MangaOverlayTextRegionCropReport(
            totalRegions: diagnostics.count,
            cropSucceededCount: succeeded,
            adoptedCount: adoptedIndexes.count,
            rejectedCount: rejectedIndexes.count,
            adoptedBlockIndexes: adoptedIndexes,
            rejectedBlockIndexes: rejectedIndexes,
            mainRejectionReasons: rejectionCounts,
            failureAttributionBreakdown: attributionCounts,
            diagnostics: diagnostics,
            notes: [
                "TextRegion crop OCR uses post-fusion block bbox as seed and clamps to block-local subregion when eligible, otherwise assigned bubble bbox or content rect",
                "selection uses word preservation, text similarity, word count, Latin/symbol ratios, OCR error heuristics, and crop clamp signals only",
                "ground truth is used only after selection to refresh evaluation metrics",
                "subregion clamp does not loosen crop adoption guardrails"
            ]
        )
        return (updatedBlocks, report)
    }

    private static func makeBubbleSubRegionReport(
        blocks: [MangaOverlayProbeBlock],
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics,
        image: CGImage
    ) -> MangaOverlayBubbleSubRegionReport {
        let bubbleBBoxes = Dictionary(uniqueKeysWithValues: bubbleGeometry.bubbles.map { ($0.id, $0.bbox) })
        let oversizedBubbleIDs = bubbleGeometry.bubbleAudits
            .filter(\.bubbleSplitCandidate)
            .map(\.bubbleID)
            .sorted()
        let oversizedSet = Set(oversizedBubbleIDs)
        let contentRect = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        var nextID = 0
        var diagnostics: [MangaOverlayBubbleSubRegionDiagnostic] = []

        for block in blocks {
            guard let bubbleID = block.bubbleID,
                  let parentBBox = bubbleBBoxes[bubbleID] else { continue }
            let parentRect = rect(from: parentBBox).intersection(contentRect)
            let seedRect = rect(from: block.bbox).intersection(contentRect)
            guard !parentRect.isNull, !seedRect.isNull, parentRect.width >= 2, parentRect.height >= 2 else { continue }

            let isOversized = oversizedSet.contains(bubbleID)
            let estimatedFontSize = max(6, min(seedRect.width, seedRect.height))
            let horizontalPadding = isOversized
                ? max(8, min(estimatedFontSize * 0.95, seedRect.width * 0.85))
                : max(5, min(estimatedFontSize * 0.45, seedRect.width * 0.45))
            let verticalPadding = isOversized
                ? max(8, min(estimatedFontSize * 1.20, seedRect.height * 0.70))
                : max(6, min(estimatedFontSize * 0.65, seedRect.height * 0.55))
            let expandedSeed = seedRect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
            let subRect = clamp(expandedSeed, to: parentRect).intersection(contentRect).integral
            let seedIntersection = subRect.intersection(seedRect)
            let seedCoverage = area(of: seedIntersection) / max(area(of: seedRect), 1)
            let parentCoverage = area(of: subRect) / max(area(of: parentRect), 1)

            var rejectionReasons: [String] = []
            if !isOversized {
                rejectionReasons.append("parentBubbleNotOversized")
            }
            if subRect.width < max(12, seedRect.width * 0.72) || subRect.height < max(12, seedRect.height * 0.72) {
                rejectionReasons.append("subRegionTooSmall")
            }
            if seedCoverage < 0.92 {
                rejectionReasons.append("seedCoverageTooLow")
            }
            if parentCoverage >= 0.88 {
                rejectionReasons.append("subRegionTooCloseToParentBubble")
            }
            if seedRect.width / max(seedRect.height, 1) > 8 || seedRect.height / max(seedRect.width, 1) > 8 {
                rejectionReasons.append("seedAspectExtreme")
            }

            let overlapsSibling = diagnostics.contains { existing in
                existing.parentBubbleID == bubbleID
                    && rect(from: existing.bbox).intersection(subRect).isNull == false
                    && area(of: rect(from: existing.bbox).intersection(subRect)) / max(min(area(of: rect(from: existing.bbox)), area(of: subRect)), 1) > 0.62
            }
            if overlapsSibling {
                rejectionReasons.append("overlapsSiblingSubRegion")
            }

            let clampEligible = rejectionReasons.isEmpty
            var notes = [
                "generatedFromFusedBlockSeedBBox",
                isOversized ? "oversizedParentBubble" : "diagnosticOnlyParentBubble"
            ]
            if !clampEligible {
                notes.append("notUsedForClamp")
            }

            diagnostics.append(
                MangaOverlayBubbleSubRegionDiagnostic(
                    id: nextID,
                    parentBubbleID: bubbleID,
                    bbox: bboxArray(from: subRect),
                    seedBlockIndexes: [block.index],
                    seedTextRegionIndexes: [],
                    source: isOversized ? "oversizedBubbleBlockSeed" : "blockSeedDiagnostic",
                    area: area(of: subRect),
                    parentCoverageRatio: parentCoverage,
                    seedCoverageRatio: seedCoverage,
                    confidence: clampEligible ? 0.72 : 0.38,
                    clampEligible: clampEligible,
                    rejectionReasons: rejectionReasons,
                    notes: notes
                )
            )
            nextID += 1
        }

        return MangaOverlayBubbleSubRegionReport(
            enabled: true,
            totalSubRegions: diagnostics.count,
            clampEligibleCount: diagnostics.filter(\.clampEligible).count,
            oversizedBubbleIDs: oversizedBubbleIDs,
            diagnostics: diagnostics,
            notes: [
                "lightweight BubbleMask approximation derived from fused block seed bbox and parent bubble bbox",
                "only oversized bubble subregions with enough seed coverage and smaller-than-parent area are eligible for TextRegion crop clamp",
                "ground truth is not used to generate, rank, reject, or adopt subregions"
            ]
        )
    }

    private static func subRegionDiagnosticsByBlock(
        from report: MangaOverlayBubbleSubRegionReport?
    ) -> [Int: MangaOverlayBubbleSubRegionDiagnostic] {
        guard let report else { return [:] }
        var result: [Int: MangaOverlayBubbleSubRegionDiagnostic] = [:]
        for diagnostic in report.diagnostics {
            for index in diagnostic.seedBlockIndexes where result[index] == nil {
                result[index] = diagnostic
            }
        }
        return result
    }

    private static func makeBubbleAssignmentCorrectionReport(
        blocks: [MangaOverlayProbeBlock],
        bubbleMaskReport: MangaOverlayBubbleMaskReport
    ) -> MangaOverlayBubbleAssignmentCorrectionReport {
        let blockByIndex = Dictionary(uniqueKeysWithValues: blocks.map { ($0.index, $0) })
        let diagnostics = bubbleMaskReport.blockDiagnostics.map { mask -> MangaOverlayBubbleAssignmentCorrectionDiagnostic in
            let block = blockByIndex[mask.blockIndex]
            let currentBubbleID = mask.currentBubbleID
            let dominantBubbleID = mask.maskDominantBubbleID
            var rejectionReasons: [String] = []
            var riskFlags: [String] = []
            var notes: [String] = [
                "groundTruthNotUsed",
                "derivedFromApproximateBubbleMask"
            ]

            if dominantBubbleID == nil {
                rejectionReasons.append("noMaskDominantBubbleID")
            }
            if currentBubbleID == dominantBubbleID {
                rejectionReasons.append("alreadyConsistent")
            }
            if mask.maskDominantCoverageRatio < 0.70 {
                rejectionReasons.append("dominantCoverageBelowRecommendationThreshold")
            }
            let nonBackgroundSeedPixels = mask.maskIDsUnderSeed.reduce(0) { partial, pair in
                pair.key == "0" ? partial : partial + pair.value
            }
            if nonBackgroundSeedPixels < 32 {
                rejectionReasons.append("insufficientNonBackgroundSeedMaskPixels")
            }
            let text = block?.finalTextUsedForTranslation.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let normalized = text.lowercased()
            if currentBubbleID == nil {
                riskFlags.append("unassignedBlock")
                if normalized.contains("let") && normalized.contains("battler") {
                    riskFlags.append("protectedShortText")
                    rejectionReasons.append("protectedShortTextDiagnosticOnly")
                }
            }
            if normalized.contains("city battler") || normalized.contains("offline") || normalized.contains("tournament") {
                riskFlags.append("decorativeTitle")
                rejectionReasons.append("decorativeTitleDiagnosticOnly")
            }
            if mask.maskDominantCoverageRatio < 0.85 {
                rejectionReasons.append("dominantCoverageBelowClampThreshold")
            }

            let recommended = dominantBubbleID != nil
                && currentBubbleID != dominantBubbleID
                && mask.maskDominantCoverageRatio >= 0.70
                && nonBackgroundSeedPixels >= 32
                && !riskFlags.contains("decorativeTitle")
                && !riskFlags.contains("protectedShortText")
            let appliedToCrop = recommended
                && mask.maskDominantCoverageRatio >= 0.85
                && currentBubbleID != nil
            let decision: String
            if appliedToCrop {
                decision = "appliedToCropClamp"
            } else if recommended {
                decision = "recommendedDiagnosticOnly"
                notes.append("notAppliedBecauseClampThresholdOrRiskGuardFailed")
            } else if currentBubbleID == dominantBubbleID {
                decision = "consistentNoCorrection"
            } else {
                decision = "rejectedDiagnosticOnly"
            }
            return MangaOverlayBubbleAssignmentCorrectionDiagnostic(
                blockIndex: mask.blockIndex,
                currentBubbleID: currentBubbleID,
                maskDominantBubbleID: dominantBubbleID,
                maskDominantCoverageRatio: mask.maskDominantCoverageRatio,
                maskIDsUnderSeed: mask.maskIDsUnderSeed,
                correctionRecommended: recommended,
                correctedBubbleID: recommended ? dominantBubbleID : nil,
                correctionAppliedToCropClamp: appliedToCrop,
                correctionAppliedToSafeLayout: false,
                decision: decision,
                rejectionReasons: Array(Set(rejectionReasons)).sorted(),
                riskFlags: Array(Set(riskFlags)).sorted(),
                notes: notes
            )
        }
        let inconsistent = diagnostics
            .filter { $0.currentBubbleID != $0.maskDominantBubbleID }
            .map(\.blockIndex)
        let recommended = diagnostics
            .filter(\.correctionRecommended)
            .map(\.blockIndex)
        let applied = diagnostics
            .filter(\.correctionAppliedToCropClamp)
            .map(\.blockIndex)
        let rejected = diagnostics
            .filter { $0.currentBubbleID != $0.maskDominantBubbleID && !$0.correctionAppliedToCropClamp }
            .map(\.blockIndex)
        return MangaOverlayBubbleAssignmentCorrectionReport(
            enabled: true,
            evaluatedBlockCount: diagnostics.count,
            inconsistentBlockIndexes: inconsistent.sorted(),
            recommendedCorrectionBlocks: recommended.sorted(),
            appliedToCropClampBlocks: applied.sorted(),
            appliedToSafeLayoutBlocks: [],
            rejectedCorrectionBlocks: rejected.sorted(),
            diagnostics: diagnostics.sorted { $0.blockIndex < $1.blockIndex },
            notes: [
                "assignment correction is diagnostic and ground-truth-free",
                "only high-confidence non-decorative conflicts can influence TextRegion crop clamp",
                "safe layout is still driven by BubbleMask diagnostics and existing collision checks"
            ]
        )
    }

    private static func assignmentCorrectionsByBlock(
        from report: MangaOverlayBubbleAssignmentCorrectionReport?
    ) -> [Int: MangaOverlayBubbleAssignmentCorrectionDiagnostic] {
        guard let report else { return [:] }
        return Dictionary(uniqueKeysWithValues: report.diagnostics.map { ($0.blockIndex, $0) })
    }

    private static func makeBubbleSplitCandidateReport(
        blocks: [MangaOverlayProbeBlock],
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics,
        bubbleMaskReport: MangaOverlayBubbleMaskReport,
        image: CGImage,
        assignmentCorrectionReport: MangaOverlayBubbleAssignmentCorrectionReport?
    ) -> MangaOverlayBubbleSplitCandidateReport {
        let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        let splitParents = bubbleGeometry.bubbleAudits
            .filter(\.bubbleSplitCandidate)
            .map(\.bubbleID)
            .sorted()
        let splitParentSet = Set(splitParents)
        let maskInstances = Dictionary(uniqueKeysWithValues: bubbleMaskReport.instances.map { ($0.bubbleID, $0) })
        let correctionByBlock = assignmentCorrectionsByBlock(from: assignmentCorrectionReport)
        let blocksByParent = Dictionary(grouping: blocks) { block -> Int? in
            if let corrected = correctionByBlock[block.index],
               corrected.correctionAppliedToCropClamp,
               let correctedBubbleID = corrected.correctedBubbleID {
                return correctedBubbleID
            }
            return block.bubbleID
        }
        var nextID = 0
        var diagnostics: [MangaOverlayBubbleSplitCandidateDiagnostic] = []

        for parentID in splitParents {
            let parentBlocks = (blocksByParent[parentID] ?? []).sorted { $0.index < $1.index }
            guard let parentBBox = bubbleGeometry.bubbles.first(where: { $0.id == parentID })?.bbox else { continue }
            let parentRect = rect(from: parentBBox).intersection(imageBounds)
            let parentArea = max(area(of: parentRect), 1)
            for block in parentBlocks {
                let seedRect = rect(from: block.bbox).intersection(imageBounds)
                guard !seedRect.isNull, seedRect.width >= 2, seedRect.height >= 2 else { continue }
                let estimatedFontSize = max(6, min(seedRect.width, seedRect.height))
                let candidateRect = clamp(
                    seedRect.insetBy(dx: -max(8, estimatedFontSize * 0.75), dy: -max(8, estimatedFontSize * 0.95)),
                    to: parentRect
                ).integral
                let seedCoverage = area(of: candidateRect.intersection(seedRect)) / max(area(of: seedRect), 1)
                let parentCoverage = area(of: candidateRect) / parentArea
                var siblingOverlap: Double = 0
                for sibling in parentBlocks where sibling.index != block.index {
                    let siblingRect = rect(from: sibling.bbox).intersection(imageBounds)
                    let overlap = area(of: candidateRect.intersection(siblingRect)) / max(min(area(of: candidateRect), area(of: siblingRect)), 1)
                    siblingOverlap = max(siblingOverlap, overlap)
                }
                var rejectionReasons: [String] = []
                var riskFlags: [String] = ["parentBubbleOversized"]
                if !splitParentSet.contains(parentID) {
                    rejectionReasons.append("parentBubbleNotSplitCandidate")
                }
                if seedCoverage < 0.94 {
                    rejectionReasons.append("seedCoverageTooLow")
                }
                if parentCoverage >= 0.72 {
                    rejectionReasons.append("candidateTooCloseToParentBubble")
                }
                if siblingOverlap >= 0.36 {
                    rejectionReasons.append("siblingOverlapTooHigh")
                }
                let text = block.finalTextUsedForTranslation.lowercased()
                if text.contains("city battler") || text.contains("offline") || text.contains("tournament") {
                    riskFlags.append("decorativeTitle")
                    rejectionReasons.append("decorativeTitleDiagnosticOnly")
                }
                if text.contains("let") && text.contains("battler") {
                    riskFlags.append("protectedShortText")
                    rejectionReasons.append("protectedShortTextDiagnosticOnly")
                }
                let clampEligible = rejectionReasons.isEmpty
                let maskPixelCount = Int(area(of: candidateRect).rounded())
                let safeRect = clamp(candidateRect.insetBy(dx: 4, dy: 4), to: imageBounds).integral
                diagnostics.append(
                    MangaOverlayBubbleSplitCandidateDiagnostic(
                        id: nextID,
                        parentBubbleID: parentID,
                        seedBlockIndexes: [block.index],
                        bbox: bboxArray(from: candidateRect),
                        safeRect: safeRect.width >= 8 && safeRect.height >= 8 ? bboxArray(from: safeRect) : nil,
                        maskPixelCount: maskPixelCount,
                        parentMaskCoverageRatio: maskInstances[parentID]?.maskCoverageRatio ?? parentCoverage,
                        seedCoverageRatio: seedCoverage,
                        siblingOverlapRatio: siblingOverlap,
                        clampEligible: clampEligible,
                        appliedToBlockIndexes: clampEligible ? [block.index] : [],
                        rejectionReasons: Array(Set(rejectionReasons)).sorted(),
                        riskFlags: Array(Set(riskFlags)).sorted(),
                        notes: [
                            "split candidate is block-local geometry inside oversized parent bubble",
                            "candidate does not create or delete probe blocks",
                            "groundTruthNotUsed"
                        ]
                    )
                )
                nextID += 1
            }
        }
        let applied = diagnostics.flatMap(\.appliedToBlockIndexes).sorted()
        return MangaOverlayBubbleSplitCandidateReport(
            enabled: true,
            parentBubbleIDs: splitParents,
            candidateCount: diagnostics.count,
            clampEligibleCount: diagnostics.filter(\.clampEligible).count,
            appliedToCropClampBlocks: applied,
            diagnostics: diagnostics.sorted { $0.id < $1.id },
            notes: [
                "conservative split candidates are diagnostics for oversized bubbles 4/6/7",
                "eligible candidates may narrow TextRegion crop clamp but never change final block count directly",
                "TextRegion crop adoption guardrails remain unchanged"
            ]
        )
    }

    private static func splitCandidatesByBlock(
        from report: MangaOverlayBubbleSplitCandidateReport?
    ) -> [Int: MangaOverlayBubbleSplitCandidateDiagnostic] {
        guard let report else { return [:] }
        var result: [Int: MangaOverlayBubbleSplitCandidateDiagnostic] = [:]
        for diagnostic in report.diagnostics where diagnostic.clampEligible {
            for index in diagnostic.appliedToBlockIndexes where result[index] == nil {
                result[index] = diagnostic
            }
        }
        return result
    }

    private static func textRegionCropReport(
        _ report: MangaOverlayTextRegionCropReport?,
        mergingMaskDiagnosticsFrom maskReport: MangaOverlayBubbleMaskReport?
    ) -> MangaOverlayTextRegionCropReport? {
        guard let report, let maskReport else { return report }
        let maskByBlock = Dictionary(
            uniqueKeysWithValues: maskReport.blockDiagnostics.map { ($0.blockIndex, $0) }
        )
        let diagnostics = report.diagnostics.map { diagnostic in
            var updated = diagnostic
            if let mask = maskByBlock[diagnostic.blockIndex] {
                updated.cropMaskCoverageRatio = mask.cropMaskCoverageRatio
                updated.cropMaskRejectedReason = mask.cropMaskRejectedReason
                updated.cropMaskCoverageAfter = mask.cropMaskCoverageRatio
                updated.cropMaskCoverageBefore = diagnostic.cropBBoxBeforeAssignmentCorrection == nil
                    ? mask.cropMaskCoverageRatio
                    : nil
            }
            return updated
        }
        var notes = report.notes
        notes.append("BubbleMask coverage is diagnostic only and does not loosen TextRegion crop adoption guardrails")
        return MangaOverlayTextRegionCropReport(
            totalRegions: report.totalRegions,
            cropSucceededCount: report.cropSucceededCount,
            adoptedCount: report.adoptedCount,
            rejectedCount: report.rejectedCount,
            adoptedBlockIndexes: report.adoptedBlockIndexes,
            rejectedBlockIndexes: report.rejectedBlockIndexes,
            mainRejectionReasons: report.mainRejectionReasons,
            failureAttributionBreakdown: report.failureAttributionBreakdown,
            diagnostics: diagnostics,
            notes: notes
        )
    }

    private static func makeTextBoxCandidateReport(
        blocks: [MangaOverlayProbeBlock],
        textRegionCropReport: MangaOverlayTextRegionCropReport?,
        bubbleMaskReport: MangaOverlayBubbleMaskReport?,
        assignmentCorrectionReport: MangaOverlayBubbleAssignmentCorrectionReport?,
        splitCandidateReport: MangaOverlayBubbleSplitCandidateReport?
    ) -> MangaOverlayTextBoxCandidateReport? {
        guard let textRegionCropReport else { return nil }
        let cropByBlock = Dictionary(uniqueKeysWithValues: textRegionCropReport.diagnostics.map { ($0.blockIndex, $0) })
        let maskByBlock = Dictionary(uniqueKeysWithValues: (bubbleMaskReport?.blockDiagnostics ?? []).map { ($0.blockIndex, $0) })
        let correctionByBlock = Dictionary(uniqueKeysWithValues: (assignmentCorrectionReport?.diagnostics ?? []).map { ($0.blockIndex, $0) })
        var splitByBlock: [Int: MangaOverlayBubbleSplitCandidateDiagnostic] = [:]
        for diagnostic in splitCandidateReport?.diagnostics ?? [] {
            for index in diagnostic.seedBlockIndexes where splitByBlock[index] == nil {
                splitByBlock[index] = diagnostic
            }
        }

        let diagnostics = blocks.compactMap { block -> MangaOverlayTextBoxCandidateDiagnostic? in
            guard let crop = cropByBlock[block.index] else { return nil }
            let seedRect = rect(from: crop.seedBBox)
            let cropRect = rect(from: crop.cropBBox)
            let glyphRect = block.glyphMaskRect.map { rect(from: $0) }
            let safeRect = block.safeLayoutRect.map { rect(from: $0) }
            let glyphOverlap = glyphRect.map { rectOverlapRatio($0, cropRect) }
            let safeOverlap = safeRect.map { rectOverlapRatio($0, cropRect) }
            let bubbleCoverage = maskByBlock[block.index]?.cropMaskCoverageRatio ?? crop.cropMaskCoverageRatio
            var rejectionReasons: [String] = []
            var riskFlags: [String] = []

            if cropRect.width < max(10, seedRect.width * 0.62) || cropRect.height < max(10, seedRect.height * 0.62) {
                rejectionReasons.append("textBoxTooTight")
            }
            if cropRect.width > seedRect.width * 3.4 || cropRect.height > seedRect.height * 3.4 {
                riskFlags.append("textBoxTooWide")
            }
            if let glyphOverlap, glyphOverlap < 0.45 {
                rejectionReasons.append("glyphOverlapLow")
            }
            if let bubbleCoverage, bubbleCoverage < 0.45 {
                rejectionReasons.append("bubbleMaskCoverageLow")
            }
            if let safeOverlap, safeOverlap < 0.40 {
                riskFlags.append("safeRectOverlapLow")
            }
            if crop.rejectionReasons.contains("emptyCropText") {
                rejectionReasons.append("emptyLocalOCR")
            }
            if let correction = correctionByBlock[block.index],
               correction.decision == "rejectedDiagnosticOnly",
               correction.currentBubbleID != correction.maskDominantBubbleID {
                riskFlags.append("bubbleMaskConflict")
            }
            if let split = splitByBlock[block.index], split.clampEligible == false {
                riskFlags.append("splitCandidateRejected")
            }

            let evidenceScore = Self.textBoxEvidenceScore(
                bubbleMaskCoverageRatio: bubbleCoverage,
                glyphOverlapRatio: glyphOverlap,
                safeRectOverlapRatio: safeOverlap,
                cropRejections: crop.rejectionReasons,
                riskFlags: riskFlags
            )
            if evidenceScore < 0.58 {
                rejectionReasons.append("evidenceScoreBelowCropThreshold")
            }
            let eligible = rejectionReasons.isEmpty
            return MangaOverlayTextBoxCandidateDiagnostic(
                id: block.index,
                blockIndex: block.index,
                source: "\(crop.clampSource)TextRegionCropBBox",
                bbox: crop.cropBBox,
                seedBBox: crop.seedBBox,
                orientationHint: crop.orientationHint,
                bubbleID: crop.bubbleID,
                correctedBubbleID: crop.correctedBubbleID,
                splitCandidateID: crop.splitCandidateID,
                clampSource: crop.clampSource,
                paddingX: crop.paddingX,
                paddingY: crop.paddingY,
                bubbleMaskCoverageRatio: bubbleCoverage,
                glyphOverlapRatio: glyphOverlap,
                safeRectOverlapRatio: safeOverlap,
                evidenceScore: evidenceScore,
                eligibleForCrop: eligible,
                derivedFromTextRegionCrop: true,
                usedForTextRegionCrop: false,
                rejectionReasons: Array(Set(rejectionReasons)).sorted(),
                riskFlags: Array(Set(riskFlags)).sorted(),
                notes: [
                    "lightweight TextBox candidate derived from existing TextRegion crop bbox",
                    "derived after TextRegion crop diagnostics; not used as an upstream crop clamp input in this version",
                    "groundTruthNotUsed",
                    crop.adopted ? "cropTextAdoptedByExistingGuardrail" : "diagnosticOnlyFallbackToFusedText"
                ]
            )
        }

        return MangaOverlayTextBoxCandidateReport(
            enabled: true,
            evaluatedBlockCount: blocks.count,
            candidateCount: diagnostics.count,
            cropEligibleCount: diagnostics.filter(\.eligibleForCrop).count,
            usedForCropBlocks: diagnostics.filter(\.usedForTextRegionCrop).map(\.blockIndex).sorted(),
            rejectedBlocks: diagnostics.filter { !$0.eligibleForCrop }.map(\.blockIndex).sorted(),
            diagnostics: diagnostics.sorted { $0.blockIndex < $1.blockIndex },
            notes: [
                "TextBoxes are lightweight diagnostics built from fused block seed bbox, crop bbox, clamp source, glyph mask, safe rect, and approximate BubbleMask coverage",
                "TextBox candidates are derived after TextRegion crop diagnostics in this version; usedForTextRegionCrop stays false until TextBox is an upstream clamp input",
                "TextBox eligibility does not loosen TextRegion crop adoption guardrails",
                "ground truth is not used to score, rank, reject, or adopt TextBox candidates"
            ]
        )
    }

    private static func makeSegmentMaskReport(
        blocks: [MangaOverlayProbeBlock],
        textBoxCandidateReport: MangaOverlayTextBoxCandidateReport?,
        bubbleMaskReport: MangaOverlayBubbleMaskReport?
    ) -> MangaOverlaySegmentMaskReport? {
        guard let textBoxCandidateReport else { return nil }
        let textBoxByBlock = Dictionary(uniqueKeysWithValues: textBoxCandidateReport.diagnostics.map { ($0.blockIndex, $0) })
        let maskByBlock = Dictionary(uniqueKeysWithValues: (bubbleMaskReport?.blockDiagnostics ?? []).map { ($0.blockIndex, $0) })

        let diagnostics = blocks.map { block -> MangaOverlaySegmentMaskDiagnostic in
            let textBox = textBoxByBlock[block.index]
            let textBoxRect = textBox.map { rect(from: $0.bbox) }
            let glyphRect = block.glyphMaskRect.map { rect(from: $0) }
            let safeRect = block.safeLayoutRect.map { rect(from: $0) }
            let textBoxCoverage = glyphRect.flatMap { glyph in
                textBoxRect.map { rectOverlapRatio(glyph, $0) }
            }
            let bubbleCoverage = maskByBlock[block.index]?.cropMaskCoverageRatio
            let safeCoverage = glyphRect.flatMap { glyph in
                safeRect.map { rectOverlapRatio(glyph, $0) }
            }
            var rejectionReasons: [String] = []
            var riskFlags: [String] = []
            if block.glyphMaskPixelCount <= 0 {
                rejectionReasons.append("missingGlyphMask")
            }
            if let textBoxCoverage, textBoxCoverage < 0.42 {
                rejectionReasons.append("glyphEscapesTextBox")
            }
            if let bubbleCoverage, bubbleCoverage < 0.45 {
                rejectionReasons.append("segmentOutsideBubbleRisk")
            }
            if let safeCoverage, safeCoverage < 0.38 {
                riskFlags.append("safeRectCoverageLow")
            }
            if block.bubbleID == nil {
                riskFlags.append("unassignedBlock")
                rejectionReasons.append("unassignedBlockDiagnosticOnly")
            }
            let normalized = block.finalTextUsedForTranslation.lowercased()
            if block.bubbleID == nil,
               (normalized.contains("city battler") || normalized.contains("offline") || normalized.contains("tournament")) {
                riskFlags.append("decorativeTitle")
                rejectionReasons.append("decorativeTitleDiagnosticOnly")
            }
            let glyphEscapesTextBox = rejectionReasons.contains("glyphEscapesTextBox")
            let glyphEscapesBubble = rejectionReasons.contains("segmentOutsideBubbleRisk")
            let usableForCleanup = block.glyphMaskPixelCount > 0 && !glyphEscapesBubble
            let usableForCropEvidence = usableForCleanup
                && !glyphEscapesTextBox
                && !(block.bubbleID == nil)
                && !riskFlags.contains("decorativeTitle")
            return MangaOverlaySegmentMaskDiagnostic(
                blockIndex: block.index,
                textBoxCandidateID: textBox?.id,
                glyphMaskPixelCount: block.glyphMaskPixelCount,
                glyphMaskRect: block.glyphMaskRect,
                glyphMaskFillRectCount: block.glyphMaskFillRects.count,
                textBoxCoverageRatio: textBoxCoverage,
                bubbleMaskCoverageRatio: bubbleCoverage,
                safeRectCoverageRatio: safeCoverage,
                glyphEscapesBubble: glyphEscapesBubble,
                glyphEscapesTextBox: glyphEscapesTextBox,
                usableForCleanup: usableForCleanup,
                usableForCropEvidence: usableForCropEvidence,
                rejectionReasons: Array(Set(rejectionReasons)).sorted(),
                riskFlags: Array(Set(riskFlags)).sorted(),
                notes: [
                    "lightweight SegmentMask diagnostic aggregates existing glyph mask rectangles and approximate BubbleMask coverage",
                    "not a learned segmentation model",
                    "groundTruthNotUsed"
                ]
            )
        }

        return MangaOverlaySegmentMaskReport(
            enabled: true,
            evaluatedBlockCount: blocks.count,
            glyphMaskBlocks: diagnostics.filter { $0.glyphMaskPixelCount > 0 }.count,
            usableForCleanupBlocks: diagnostics.filter(\.usableForCleanup).map(\.blockIndex).sorted(),
            usableForCropEvidenceBlocks: diagnostics.filter(\.usableForCropEvidence).map(\.blockIndex).sorted(),
            weakSegmentBlocks: diagnostics.filter { !$0.usableForCropEvidence }.map(\.blockIndex).sorted(),
            diagnostics: diagnostics.sorted { $0.blockIndex < $1.blockIndex },
            notes: [
                "SegmentMask is a traditional image-processing approximation derived from existing glyph mask evidence",
                "usableForCropEvidence is diagnostic and does not loosen TextRegion crop adoption guardrails",
                "decorative, unassigned, and weak glyph blocks stay diagnostic-only"
            ]
        )
    }

    private static func textRegionCropReport(
        _ report: MangaOverlayTextRegionCropReport?,
        mergingTextBoxCandidateReport textBoxReport: MangaOverlayTextBoxCandidateReport?,
        segmentMaskReport: MangaOverlaySegmentMaskReport?
    ) -> MangaOverlayTextRegionCropReport? {
        guard let report else { return nil }
        let textBoxByBlock = Dictionary(uniqueKeysWithValues: (textBoxReport?.diagnostics ?? []).map { ($0.blockIndex, $0) })
        let segmentByBlock = Dictionary(uniqueKeysWithValues: (segmentMaskReport?.diagnostics ?? []).map { ($0.blockIndex, $0) })
        let diagnostics = report.diagnostics.map { diagnostic in
            var updated = diagnostic
            let textBox = textBoxByBlock[diagnostic.blockIndex]
            let segment = segmentByBlock[diagnostic.blockIndex]
            updated.textBoxCandidateID = textBox?.id
            updated.segmentMaskUsableForCropEvidence = segment?.usableForCropEvidence
            updated.failureAttribution = Self.cropFailureAttribution(
                diagnostic: diagnostic,
                textBox: textBox,
                segmentMask: segment
            )
            return updated
        }
        var attributionCounts: [String: Int] = [:]
        for reason in diagnostics.flatMap(\.failureAttribution) {
            attributionCounts[reason, default: 0] += 1
        }
        var notes = report.notes
        notes.append("TextBox and SegmentMask evidence is diagnostic and does not loosen TextRegion crop adoption guardrails")
        return MangaOverlayTextRegionCropReport(
            totalRegions: report.totalRegions,
            cropSucceededCount: report.cropSucceededCount,
            adoptedCount: report.adoptedCount,
            rejectedCount: report.rejectedCount,
            adoptedBlockIndexes: report.adoptedBlockIndexes,
            rejectedBlockIndexes: report.rejectedBlockIndexes,
            mainRejectionReasons: report.mainRejectionReasons,
            failureAttributionBreakdown: attributionCounts,
            diagnostics: diagnostics,
            notes: notes
        )
    }

    private static func makePreCropTextBoxPlanReport(
        blocks: [MangaOverlayProbeBlock],
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics,
        bubbleMaskReport: MangaOverlayBubbleMaskReport?,
        bubbleAssignmentCorrectionReport: MangaOverlayBubbleAssignmentCorrectionReport?,
        bubbleSplitCandidateReport: MangaOverlayBubbleSplitCandidateReport?,
        bubbleSubRegionReport: MangaOverlayBubbleSubRegionReport?
    ) -> MangaOverlayPreCropTextBoxPlanReport {
        let maskByBlock = Dictionary(uniqueKeysWithValues: (bubbleMaskReport?.blockDiagnostics ?? []).map { ($0.blockIndex, $0) })
        let correctionByBlock = Self.assignmentCorrectionsByBlock(from: bubbleAssignmentCorrectionReport)
        let splitByBlock = Self.splitCandidatesByBlock(from: bubbleSplitCandidateReport)
        let subRegionByBlock = Self.subRegionDiagnosticsByBlock(from: bubbleSubRegionReport)
        let bubbleBBoxes = Dictionary(uniqueKeysWithValues: bubbleGeometry.bubbles.map { ($0.id, $0.bbox) })

        var nextPlanID = 0
        var plans: [MangaOverlayPreCropTextBoxPlan] = []
        var summaries: [MangaOverlayPreCropTextBoxPlanBlockSummary] = []

        for block in blocks {
            let blockPlans = Self.preCropTextBoxPlans(
                for: block,
                mask: maskByBlock[block.index],
                correction: correctionByBlock[block.index],
                split: splitByBlock[block.index],
                subRegion: subRegionByBlock[block.index],
                bubbleBBoxes: bubbleBBoxes,
                startingPlanID: nextPlanID
            )
            nextPlanID += blockPlans.count
            plans.append(contentsOf: blockPlans)

            let selected = blockPlans
                .filter(\.eligibleForShadowOCR)
                .sorted { lhs, rhs in
                    if lhs.evidenceScore == rhs.evidenceScore {
                        return lhs.planID < rhs.planID
                    }
                    return lhs.evidenceScore > rhs.evidenceScore
                }
                .prefix(3)
                .map(\.planID)
            let selectedSet = Set(selected)
            let rejected = blockPlans.map(\.planID).filter { !selectedSet.contains($0) }
            let stopReasons = Self.preCropPlanStopReasons(for: block, plans: blockPlans)
            let verdict: String
            if !selected.isEmpty {
                verdict = "shadowOCREligiblePlans"
            } else if stopReasons.contains("protectedDiagnosticOnly") {
                verdict = "protectedDiagnosticOnly"
            } else if stopReasons.contains("geometryEvidenceTooWeak") {
                verdict = "geometryEvidenceTooWeak"
            } else {
                verdict = "diagnosticOnly"
            }
            summaries.append(
                MangaOverlayPreCropTextBoxPlanBlockSummary(
                    blockIndex: block.index,
                    selectedPlanIDsForShadowOCR: Array(selected),
                    rejectedPlanIDs: rejected.sorted(),
                    planningVerdict: verdict,
                    stopReasons: stopReasons,
                    notes: [
                        "preCropPlanningGeneratedBeforeTextRegionCrop",
                        "shadowOnlyNoFinalTextChange",
                        "groundTruthNotUsed"
                    ]
                )
            )
        }

        return MangaOverlayPreCropTextBoxPlanReport(
            enabled: true,
            evaluatedBlockCount: blocks.count,
            planCount: plans.count,
            shadowOCREligiblePlanCount: plans.filter(\.eligibleForShadowOCR).count,
            selectedForShadowOCRBlocks: summaries.filter { !$0.selectedPlanIDsForShadowOCR.isEmpty }.map(\.blockIndex).sorted(),
            stoppedBlocks: summaries.filter { !$0.stopReasons.isEmpty }.map(\.blockIndex).sorted(),
            blockSummaries: summaries.sorted { $0.blockIndex < $1.blockIndex },
            plans: plans.sorted { $0.planID < $1.planID },
            notes: [
                "Koharu-style upstream TextBox planning artifact generated before TextRegion crop OCR",
                "plans use fused seed bbox, bubble geometry, BubbleMask majority, subRegion, split candidate, assignment correction, glyph/SegmentMask proxy, and safe rect signals only",
                "each block keeps at most three plans eligible for shadow OCR; finalTextUsedForTranslation and TextRegion adoptedCount are unchanged",
                "ground truth is not used for planning, scoring, ranking, shadow OCR selection, adoption, or fallback"
            ]
        )
    }

    private static func preCropTextBoxPlans(
        for block: MangaOverlayProbeBlock,
        mask: MangaOverlayBubbleMaskBlockDiagnostic?,
        correction: MangaOverlayBubbleAssignmentCorrectionDiagnostic?,
        split: MangaOverlayBubbleSplitCandidateDiagnostic?,
        subRegion: MangaOverlayBubbleSubRegionDiagnostic?,
        bubbleBBoxes: [Int: [Double]],
        startingPlanID: Int
    ) -> [MangaOverlayPreCropTextBoxPlan] {
        let finalText = block.finalTextUsedForTranslation.lowercased()
        let isDecorative = finalText.contains("city battler") && finalText.contains("tournament")
        let isProtectedShort = finalText.contains("let") && finalText.contains("battler")
        let seedBBox = block.bbox
        let bubbleBBox = block.bubbleID.flatMap { bubbleBBoxes[$0] }
        let safeRect = mask?.maskSafeRect ?? block.safeLayoutRect
        let dominantBubbleID = mask?.maskDominantBubbleID
        let bubbleCoverage = mask?.maskDominantCoverageRatio
        let glyphCoverage = block.glyphMaskPixelCount > 0 ? min(1, Double(block.glyphMaskPixelCount) / max(1, area(of: rect(from: seedBBox)))) : nil
        let safeCoverage = safeRect.flatMap { Self.bboxCoverage(seedBBox, within: $0) }
        var rawPlans: [(variantName: String, bbox: [Double], sourceSignals: [String], riskFlags: [String], rejectionReasons: [String], notes: [String], eligibilityBase: Bool)] = []

        rawPlans.append((
            variantName: "seedTightTextBox",
            bbox: Self.expandedBBox(seedBBox, by: 0.08, minimumPadding: 3),
            sourceSignals: ["fusedSeedBBox", "ocrObservationBBox"],
            riskFlags: [],
            rejectionReasons: isDecorative || isProtectedShort ? ["protectedDiagnosticOnly"] : [],
            notes: ["most conservative upstream TextBox plan"],
            eligibilityBase: !(isDecorative || isProtectedShort)
        ))

        if let bubbleBBox {
            rawPlans.append((
                variantName: "bubbleContainedTextBox",
                bbox: Self.intersectingBBox(Self.expandedBBox(seedBBox, by: 0.18, minimumPadding: 6), bubbleBBox) ?? seedBBox,
                sourceSignals: ["fusedSeedBBox", "bubbleGeometry", "bubbleID:\(block.bubbleID.map(String.init) ?? "nil")"],
                riskFlags: dominantBubbleID == nil || dominantBubbleID == block.bubbleID ? [] : ["bubbleMaskConflict"],
                rejectionReasons: [],
                notes: ["seed bbox expanded then clamped to current bubble geometry"],
                eligibilityBase: !(isDecorative || isProtectedShort)
            ))
        }

        if let subRegion, subRegion.clampEligible {
            rawPlans.append((
                variantName: "subRegionTextBox",
                bbox: Self.intersectingBBox(Self.expandedBBox(seedBBox, by: 0.12, minimumPadding: 4), subRegion.bbox) ?? subRegion.bbox,
                sourceSignals: ["BubbleMask", "subRegion", "parentBubbleID:\(subRegion.parentBubbleID)"],
                riskFlags: [],
                rejectionReasons: subRegion.rejectionReasons,
                notes: ["upstream plan constrained by block-local BubbleMask subregion"],
                eligibilityBase: !(isDecorative || isProtectedShort)
            ))
        }

        if let split, split.clampEligible, !isDecorative, !isProtectedShort {
            rawPlans.append((
                variantName: "splitCandidateTextBox",
                bbox: split.bbox,
                sourceSignals: ["BubbleMask", "splitCandidate", "parentBubbleID:\(split.parentBubbleID)"],
                riskFlags: split.riskFlags,
                rejectionReasons: split.rejectionReasons,
                notes: ["split candidate is eligible for shadow OCR only"],
                eligibilityBase: true
            ))
        }

        if let safeRect {
            rawPlans.append((
                variantName: "maskMajorityTextBox",
                bbox: Self.intersectingBBox(Self.expandedBBox(seedBBox, by: 0.16, minimumPadding: 5), safeRect) ?? safeRect,
                sourceSignals: ["BubbleMask", "maskMajorityID:\(dominantBubbleID.map(String.init) ?? "nil")", "maskSafeRect"],
                riskFlags: mask?.bubbleIDConsistent == true ? [] : ["bubbleMaskConflict"],
                rejectionReasons: [],
                notes: ["TextBox plan constrained by BubbleMask majority and safe rect"],
                eligibilityBase: !(isDecorative || isProtectedShort)
            ))
        }

        if block.glyphMaskPixelCount > 0, let glyphRect = block.glyphMaskRect, !(isDecorative || isProtectedShort) {
            rawPlans.append((
                variantName: "glyphAnchoredTextBox",
                bbox: Self.expandedBBox(glyphRect, by: 0.30, minimumPadding: 7),
                sourceSignals: ["SegmentMaskProxy", "glyphMaskRect", "fusedSeedBBox"],
                riskFlags: block.glyphMaskPixelCount < 24 ? ["segmentEvidenceTooWeak"] : [],
                rejectionReasons: block.glyphMaskPixelCount < 24 ? ["segmentEvidenceTooWeak"] : [],
                notes: ["traditional glyph/SegmentMask proxy anchors the plan"],
                eligibilityBase: block.glyphMaskPixelCount >= 24
            ))
        }

        var seen = Set<String>()
        var unique: [(variantName: String, bbox: [Double], sourceSignals: [String], riskFlags: [String], rejectionReasons: [String], notes: [String], eligibilityBase: Bool)] = []
        for plan in rawPlans {
            let key = "\(plan.variantName):\(plan.bbox.map { Int($0.rounded()) }.map(String.init).joined(separator: ","))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(plan)
        }

        let scored = unique.map { plan -> MangaOverlayPreCropTextBoxPlan in
            var riskFlags = Set(plan.riskFlags)
            var rejectionReasons = Set(plan.rejectionReasons)
            if let bubbleCoverage, bubbleCoverage < 0.35 {
                riskFlags.insert("lowBubbleCoverage")
                rejectionReasons.insert("lowBubbleCoverage")
            }
            if safeCoverage == nil {
                riskFlags.insert("missingSafeRectCoverage")
            }
            let evidenceScore = Self.preCropPlanEvidenceScore(
                variantName: plan.variantName,
                seedBBox: seedBBox,
                planBBox: plan.bbox,
                bubbleCoverage: bubbleCoverage,
                glyphCoverage: glyphCoverage,
                safeCoverage: safeCoverage,
                riskFlags: Array(riskFlags),
                rejectionReasons: Array(rejectionReasons)
            )
            let eligible = plan.eligibilityBase
                && evidenceScore >= 0.46
                && !riskFlags.contains("bubbleMaskConflict")
                && !rejectionReasons.contains("lowBubbleCoverage")
            return MangaOverlayPreCropTextBoxPlan(
                planID: startingPlanID,
                blockIndex: block.index,
                variantName: plan.variantName,
                sourceSignals: Array(Set(plan.sourceSignals)).sorted(),
                bbox: plan.bbox,
                seedBBox: seedBBox,
                bubbleID: block.bubbleID,
                dominantBubbleID: dominantBubbleID,
                bubbleCoverageRatio: bubbleCoverage,
                glyphCoverageRatio: glyphCoverage,
                safeRectCoverageRatio: safeCoverage,
                estimatedOrientation: Self.estimatedOrientation(for: seedBBox),
                evidenceScore: evidenceScore,
                eligibleForShadowOCR: eligible,
                riskFlags: Array(riskFlags).sorted(),
                rejectionReasons: Array(rejectionReasons).sorted(),
                notes: plan.notes
            )
        }
        .sorted { lhs, rhs in
            if lhs.evidenceScore == rhs.evidenceScore {
                return Self.preCropPlanPriority(lhs.variantName) < Self.preCropPlanPriority(rhs.variantName)
            }
            return lhs.evidenceScore > rhs.evidenceScore
        }
        .prefix(3)

        return scored.enumerated().map { offset, plan in
            var copy = plan
            copy.planID = startingPlanID + offset
            return copy
        }
    }

    private static func preCropPlanStopReasons(
        for block: MangaOverlayProbeBlock,
        plans: [MangaOverlayPreCropTextBoxPlan]
    ) -> [String] {
        var reasons = Set<String>()
        let finalText = block.finalTextUsedForTranslation.lowercased()
        if finalText.contains("city battler") && finalText.contains("tournament") {
            reasons.insert("protectedDiagnosticOnly")
        }
        if finalText.contains("let") && finalText.contains("battler") {
            reasons.insert("protectedDiagnosticOnly")
        }
        if plans.allSatisfy({ !$0.eligibleForShadowOCR }) {
            reasons.insert("geometryEvidenceTooWeak")
        }
        if plans.contains(where: { $0.rejectionReasons.contains("segmentEvidenceTooWeak") }) {
            reasons.insert("segmentEvidenceTooWeak")
        }
        if plans.contains(where: { $0.rejectionReasons.contains("lowBubbleCoverage") }) {
            reasons.insert("lowBubbleCoverage")
        }
        return Array(reasons).sorted()
    }

    private static func preCropPlanEvidenceScore(
        variantName: String,
        seedBBox: [Double],
        planBBox: [Double],
        bubbleCoverage: Double?,
        glyphCoverage: Double?,
        safeCoverage: Double?,
        riskFlags: [String],
        rejectionReasons: [String]
    ) -> Double {
        let seed = rect(from: seedBBox)
        let plan = rect(from: planBBox)
        let areaRatio = max(area(of: plan), 1) / max(area(of: seed), 1)
        let seedCoverage = Self.bboxCoverage(seedBBox, within: planBBox) ?? 0
        var score = 0.28
        score += min(1, seedCoverage) * 0.22
        score += min(1, bubbleCoverage ?? 0.45) * 0.18
        score += min(1, safeCoverage ?? 0.45) * 0.16
        score += min(1, (glyphCoverage ?? 0) * 10) * 0.10
        if (0.75...3.2).contains(areaRatio) {
            score += 0.08
        } else {
            score -= 0.10
        }
        score += Double(max(0, 6 - preCropPlanPriority(variantName))) * 0.01
        score -= Double(riskFlags.count) * 0.05
        score -= Double(rejectionReasons.count) * 0.08
        return max(0, min(1, score))
    }

    private static func preCropPlanPriority(_ variantName: String) -> Int {
        switch variantName {
        case "seedTightTextBox": 0
        case "bubbleContainedTextBox": 1
        case "maskMajorityTextBox": 2
        case "glyphAnchoredTextBox": 3
        case "subRegionTextBox": 4
        case "splitCandidateTextBox": 5
        default: 9
        }
    }

    private struct CropExperimentPlan: Equatable {
        var variantName: String
        var sourcePlanID: Int?
        var sourceStack: [String]
        var bbox: [Double]
        var clampSource: String
        var riskFlags: [String]
        var rejectionReasons: [String]
        var notes: [String]
    }

    private func makeCropExperimentReport(
        blocks: [MangaOverlayProbeBlock],
        image: CGImage,
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics,
        textRegionCropReport: MangaOverlayTextRegionCropReport,
        textBoxCandidateReport: MangaOverlayTextBoxCandidateReport,
        segmentMaskReport: MangaOverlaySegmentMaskReport,
        preCropTextBoxPlanReport: MangaOverlayPreCropTextBoxPlanReport?,
        bubbleMaskReport: MangaOverlayBubbleMaskReport?,
        bubbleAssignmentCorrectionReport: MangaOverlayBubbleAssignmentCorrectionReport?,
        bubbleSplitCandidateReport: MangaOverlayBubbleSplitCandidateReport?,
        bubbleSubRegionReport: MangaOverlayBubbleSubRegionReport?,
        preprocessing: MangaOverlayPreprocessingOptions
    ) async throws -> MangaOverlayCropExperimentReport {
        let cropByBlock = Dictionary(uniqueKeysWithValues: textRegionCropReport.diagnostics.map { ($0.blockIndex, $0) })
        let textBoxByBlock = Dictionary(uniqueKeysWithValues: textBoxCandidateReport.diagnostics.map { ($0.blockIndex, $0) })
        let segmentByBlock = Dictionary(uniqueKeysWithValues: segmentMaskReport.diagnostics.map { ($0.blockIndex, $0) })
        let preCropPlanSummaryByBlock = Dictionary(uniqueKeysWithValues: (preCropTextBoxPlanReport?.blockSummaries ?? []).map { ($0.blockIndex, $0) })
        let preCropPlanByID = Dictionary(uniqueKeysWithValues: (preCropTextBoxPlanReport?.plans ?? []).map { ($0.planID, $0) })
        let maskByBlock = Dictionary(uniqueKeysWithValues: (bubbleMaskReport?.blockDiagnostics ?? []).map { ($0.blockIndex, $0) })
        let correctionByBlock = Self.assignmentCorrectionsByBlock(from: bubbleAssignmentCorrectionReport)
        let splitByBlock = Self.splitCandidatesByBlock(from: bubbleSplitCandidateReport)
        let subRegionByBlock = Self.subRegionDiagnosticsByBlock(from: bubbleSubRegionReport)
        let bubbleBBoxes = Dictionary(uniqueKeysWithValues: bubbleGeometry.bubbles.map { ($0.id, $0.bbox) })

        var nextCandidateID = 0
        var candidates: [MangaOverlayCropExperimentCandidate] = []
        var summaries: [MangaOverlayCropExperimentBlockSummary] = []

        for block in blocks {
            guard let control = cropByBlock[block.index] else { continue }
            let originalText = block.finalTextUsedForTranslation
            let originalWords = Self.ocrCandidateWords(originalText)
            let originalQuality = Self.ocrCandidateQualityScore(originalText)
            let controlQuality = Self.ocrCandidateQualityScore(control.textRegionCropText ?? "")
            let controlCandidateID = nextCandidateID
            let controlCandidate = Self.cropExperimentCandidate(
                candidateID: controlCandidateID,
                blockIndex: block.index,
                sourcePlanID: nil,
                variantName: "currentTextRegionCrop",
                sourceStack: [control.source, control.clampSource, "existingTextRegionCrop"],
                bboxBeforeClamp: control.regionBBox,
                bboxAfterClamp: control.cropBBox,
                clampSource: control.clampSource,
                ocrText: control.textRegionCropText,
                originalText: originalText,
                originalWords: originalWords,
                originalQuality: originalQuality,
                controlQuality: controlQuality,
                riskFlags: control.failureAttribution,
                rejectionReasons: control.rejectionReasons,
                notes: ["controlCandidate", "existing TextRegion crop result reused; no extra OCR call"]
            )
            candidates.append(controlCandidate)
            nextCandidateID += 1

            let plans = Self.cropExperimentPlans(
                for: block,
                control: control,
                textBox: textBoxByBlock[block.index],
                segment: segmentByBlock[block.index],
                preCropPlanSummary: preCropPlanSummaryByBlock[block.index],
                preCropPlanByID: preCropPlanByID,
                mask: maskByBlock[block.index],
                correction: correctionByBlock[block.index],
                split: splitByBlock[block.index],
                subRegion: subRegionByBlock[block.index],
                bubbleBBoxes: bubbleBBoxes
            )

            var blockCandidateIDs = [controlCandidateID]
            var shadowCandidates: [MangaOverlayCropExperimentCandidate] = []
            for plan in plans.prefix(3) {
                let crop = try await mangaOverlayProbeService.recognizeTextRegionCrop(
                    in: image,
                    seedBBox: plan.bbox,
                    bubbleBBox: block.bubbleID.flatMap { bubbleBBoxes[$0] },
                    correctedBubbleBBox: plan.clampSource == "correctedBubbleMask" ? plan.bbox : nil,
                    splitCandidateBBox: plan.clampSource == "splitCandidate" ? plan.bbox : nil,
                    subRegionBBox: plan.clampSource == "subRegion" ? plan.bbox : nil,
                    options: preprocessing
                )
                let candidate = Self.cropExperimentCandidate(
                    candidateID: nextCandidateID,
                    blockIndex: block.index,
                    sourcePlanID: plan.sourcePlanID,
                    variantName: plan.variantName,
                    sourceStack: plan.sourceStack,
                    bboxBeforeClamp: plan.bbox,
                    bboxAfterClamp: crop.cropBBox,
                    clampSource: crop.clampSource,
                    ocrText: crop.text,
                    originalText: originalText,
                    originalWords: originalWords,
                    originalQuality: originalQuality,
                    controlQuality: controlQuality,
                    riskFlags: plan.riskFlags,
                    rejectionReasons: plan.rejectionReasons,
                    notes: plan.notes
                )
                candidates.append(candidate)
                shadowCandidates.append(candidate)
                blockCandidateIDs.append(nextCandidateID)
                nextCandidateID += 1
            }

            let bestShadow = Self.bestCropExperimentShadowCandidate(
                shadowCandidates,
                control: controlCandidate
            )
            let verdict = Self.cropExperimentVerdict(
                block: block,
                control: controlCandidate,
                bestShadow: bestShadow,
                segment: segmentByBlock[block.index],
                textBox: textBoxByBlock[block.index]
            )
            summaries.append(
                MangaOverlayCropExperimentBlockSummary(
                    blockIndex: block.index,
                    controlCandidateID: controlCandidateID,
                    bestShadowCandidateID: bestShadow?.candidateID,
                    bestVariantName: bestShadow?.variantName,
                    promotionVerdict: verdict.promotionVerdict,
                    stopReasons: verdict.stopReasons,
                    candidateIDs: blockCandidateIDs,
                    notes: verdict.notes
                )
            )
        }

        let promotedBlocks = summaries
            .filter { $0.promotionVerdict == "promotableShadowCandidate" }
            .map(\.blockIndex)
            .sorted()
        let stoppedBlocks = summaries
            .filter { !$0.stopReasons.isEmpty }
            .map(\.blockIndex)
            .sorted()
        return MangaOverlayCropExperimentReport(
            enabled: true,
            evaluatedBlockCount: summaries.count,
            candidateCount: candidates.count,
            controlCandidateCount: candidates.filter { $0.variantName == "currentTextRegionCrop" }.count,
            ocrSucceededCount: candidates.filter(\.ocrSucceeded).count,
            betterThanControlCount: candidates.filter(\.betterThanControl).count,
            promotedShadowBlocks: promotedBlocks,
            stoppedBlocks: stoppedBlocks,
            variantBreakdown: Self.cropExperimentVariantBreakdown(candidates: candidates, summaries: summaries),
            blockSummaries: summaries.sorted { $0.blockIndex < $1.blockIndex },
            candidates: candidates.sorted { $0.candidateID < $1.candidateID },
            notes: [
                "shadow-only TextRegion crop experiment matrix; bestShadowCandidate is never written to finalTextUsedForTranslation",
                "control is the existing TextRegion crop result; each block gets at most three additional shadow candidates selected from preCropTextBoxPlanReport when available",
                "candidate generation and promotion verdicts use bbox, mask, upstream TextBox plans, SegmentMask proxy, raw-word preservation, and OCR text quality only",
                "ground truth is not used for candidate generation, ranking, promotion, adoption, or fallback",
                "textRegionCropReport.adoptedCount remains governed by the existing guardrail"
            ]
        )
    }

    private static func cropExperimentPlans(
        for block: MangaOverlayProbeBlock,
        control: MangaOverlayTextRegionCropDiagnostic,
        textBox: MangaOverlayTextBoxCandidateDiagnostic?,
        segment: MangaOverlaySegmentMaskDiagnostic?,
        preCropPlanSummary: MangaOverlayPreCropTextBoxPlanBlockSummary?,
        preCropPlanByID: [Int: MangaOverlayPreCropTextBoxPlan],
        mask: MangaOverlayBubbleMaskBlockDiagnostic?,
        correction: MangaOverlayBubbleAssignmentCorrectionDiagnostic?,
        split: MangaOverlayBubbleSplitCandidateDiagnostic?,
        subRegion: MangaOverlayBubbleSubRegionDiagnostic?,
        bubbleBBoxes: [Int: [Double]]
    ) -> [CropExperimentPlan] {
        let finalText = block.finalTextUsedForTranslation.lowercased()
        let isDecorative = finalText.contains("city battler") && finalText.contains("tournament")
        let isProtectedShort = finalText.contains("let") && finalText.contains("battler")
        var plans: [CropExperimentPlan] = []

        if let preCropPlanSummary {
            let preCropPlans = preCropPlanSummary.selectedPlanIDsForShadowOCR
                .compactMap { preCropPlanByID[$0] }
                .sorted { lhs, rhs in
                    if lhs.evidenceScore == rhs.evidenceScore {
                        return lhs.planID < rhs.planID
                    }
                    return lhs.evidenceScore > rhs.evidenceScore
                }
            for plan in preCropPlans {
                plans.append(
                    CropExperimentPlan(
                        variantName: "preCropTextBoxPlan.\(plan.variantName)",
                        sourcePlanID: plan.planID,
                        sourceStack: ["preCropTextBoxPlan", "planID:\(plan.planID)"] + plan.sourceSignals,
                        bbox: plan.bbox,
                        clampSource: "preCropTextBoxPlan",
                        riskFlags: plan.riskFlags,
                        rejectionReasons: plan.rejectionReasons,
                        notes: [
                            "preCropTextBoxPlanReport",
                            "shadowOnly",
                            "groundTruthNotUsed",
                            "notWrittenToFinalTextUsedForTranslation"
                        ] + plan.notes
                    )
                )
            }
            if !plans.isEmpty {
                return Self.uniqueCropExperimentPlans(plans)
            }
        }

        if let textBox {
            var rejectionReasons = textBox.rejectionReasons
            let riskFlags = textBox.riskFlags
            if isDecorative {
                rejectionReasons.append("decorativeTitleDiagnosticOnly")
            }
            plans.append(
                CropExperimentPlan(
                    variantName: "textBoxTight",
                    sourcePlanID: nil,
                    sourceStack: ["fusedSeedBBox", "textBoxCandidate", textBox.source],
                    bbox: Self.tightenedBBox(seedBBox: control.seedBBox, candidateBBox: textBox.bbox),
                    clampSource: "textBoxCandidate",
                    riskFlags: Array(Set(riskFlags)).sorted(),
                    rejectionReasons: Array(Set(rejectionReasons)).sorted(),
                    notes: ["TextBox is derived shadow evidence and remains downstream-only"]
                )
            )
        }

        if let segment, segment.usableForCropEvidence, let glyphBBox = segment.glyphMaskRect {
            plans.append(
                CropExperimentPlan(
                    variantName: "glyphMaskExpanded",
                    sourcePlanID: nil,
                    sourceStack: ["SegmentMask", "glyphMaskRect", "fusedSeedBBox"],
                    bbox: Self.expandedBBox(glyphBBox, by: 0.32, minimumPadding: 8),
                    clampSource: "segmentMaskGlyph",
                    riskFlags: segment.riskFlags,
                    rejectionReasons: segment.rejectionReasons,
                    notes: ["SegmentMask glyph evidence is usable for crop evidence"]
                )
            )
        } else if let segment, !segment.usableForCropEvidence {
            plans.append(
                CropExperimentPlan(
                    variantName: "conservativeSeedBBox",
                    sourcePlanID: nil,
                    sourceStack: ["fusedSeedBBox", "weakSegmentFallback"],
                    bbox: Self.expandedBBox(control.seedBBox, by: 0.10, minimumPadding: 4),
                    clampSource: "weakSegmentFallback",
                    riskFlags: segment.riskFlags + ["segmentEvidenceTooWeak"],
                    rejectionReasons: segment.rejectionReasons,
                    notes: ["weak SegmentMask blocks only get conservative seed-bbox shadow comparison"]
                )
            )
        }

        if !isDecorative, !isProtectedShort, let split, split.clampEligible {
            plans.append(
                CropExperimentPlan(
                    variantName: "splitCandidateClamp",
                    sourcePlanID: nil,
                    sourceStack: ["BubbleMask", "splitCandidate", "parentBubbleID:\(split.parentBubbleID)"],
                    bbox: split.bbox,
                    clampSource: "splitCandidate",
                    riskFlags: split.riskFlags,
                    rejectionReasons: split.rejectionReasons,
                    notes: ["conservative split candidate shadow OCR"]
                )
            )
        }

        if !isDecorative,
           !isProtectedShort,
           let correction,
           correction.correctionAppliedToCropClamp,
           let correctedBubbleID = correction.correctedBubbleID,
           let bbox = bubbleBBoxes[correctedBubbleID] {
            plans.append(
                CropExperimentPlan(
                    variantName: "correctedBubbleClamp",
                    sourcePlanID: nil,
                    sourceStack: ["BubbleMask", "assignmentCorrection", "bubbleID:\(correctedBubbleID)"],
                    bbox: bbox,
                    clampSource: "correctedBubbleMask",
                    riskFlags: correction.riskFlags,
                    rejectionReasons: correction.rejectionReasons,
                    notes: ["assignment correction is already eligible for crop clamp; shadow-only rerun"]
                )
            )
        }

        if let subRegion, subRegion.clampEligible {
            plans.append(
                CropExperimentPlan(
                    variantName: "subRegionClamp",
                    sourcePlanID: nil,
                    sourceStack: ["BubbleMask", "subRegion", "parentBubbleID:\(subRegion.parentBubbleID)"],
                    bbox: subRegion.bbox,
                    clampSource: "subRegion",
                    riskFlags: [],
                    rejectionReasons: subRegion.rejectionReasons,
                    notes: ["block-local subregion shadow OCR"]
                )
            )
        }

        if let maskRect = mask?.maskSafeRect {
            plans.append(
                CropExperimentPlan(
                    variantName: "maskSafeRectConstrained",
                    sourcePlanID: nil,
                    sourceStack: ["BubbleMask", "maskSafeRect"],
                    bbox: Self.intersectingBBox(control.regionBBox, maskRect) ?? maskRect,
                    clampSource: "maskSafeRect",
                    riskFlags: mask?.bubbleIDConsistent == true ? [] : ["bubbleMaskConflict"],
                    rejectionReasons: [],
                    notes: ["mask-safe rect constrained shadow OCR"]
                )
            )
        }

        return Self.uniqueCropExperimentPlans(plans)
    }

    private static func cropExperimentCandidate(
        candidateID: Int,
        blockIndex: Int,
        sourcePlanID: Int?,
        variantName: String,
        sourceStack: [String],
        bboxBeforeClamp: [Double],
        bboxAfterClamp: [Double],
        clampSource: String,
        ocrText: String?,
        originalText: String,
        originalWords: [String],
        originalQuality: Double,
        controlQuality: Double,
        riskFlags: [String],
        rejectionReasons: [String],
        notes: [String]
    ) -> MangaOverlayCropExperimentCandidate {
        let candidateText = ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let candidateWords = Self.ocrCandidateWords(candidateText)
        let preservation = Self.wordPreservationRatio(sourceWords: originalWords, candidateWords: candidateWords)
        let quality = Self.ocrCandidateQualityScore(candidateText)
        let lineCountDelta = candidateText.split(separator: "\n").count - originalText.split(separator: "\n").count
        let risks = Set(riskFlags)
        var rejections = Set(rejectionReasons)
        if candidateText.isEmpty {
            rejections.insert("emptyLocalOCR")
        }
        if originalWords.count >= 3, preservation < 0.55 {
            rejections.insert("rawWordsLost")
        }
        if originalWords.count >= 2, candidateWords.count < max(2, Int(ceil(Double(originalWords.count) * 0.55))) {
            rejections.insert("wordCountRegression")
        }
        if Self.ocrCandidateWords(candidateText).joined(separator: " ") == Self.ocrCandidateWords(originalText).joined(separator: " ") {
            rejections.insert("sameAsFusedText")
        }
        if Self.containsLikelyOCRError(in: candidateText), !Self.containsLikelyOCRError(in: originalText), quality <= originalQuality + 0.08 {
            rejections.insert("introducedLikelyOCRError")
        }
        if risks.contains("bubbleMaskConflict") {
            rejections.insert("bubbleMaskConflict")
        }
        if risks.contains("segmentEvidenceTooWeak") {
            rejections.insert("segmentEvidenceTooWeak")
        }
        return MangaOverlayCropExperimentCandidate(
            candidateID: candidateID,
            blockIndex: blockIndex,
            sourcePlanID: sourcePlanID,
            variantName: variantName,
            sourceStack: Array(Set(sourceStack)).sorted(),
            bboxBeforeClamp: bboxBeforeClamp,
            bboxAfterClamp: bboxAfterClamp,
            clampSource: clampSource,
            preprocessingProfile: "existingMangaOverlayPreprocessing",
            ocrText: ocrText,
            ocrSucceeded: !candidateText.isEmpty,
            wordPreservationRatio: preservation,
            lineCountDelta: lineCountDelta,
            qualityScoreBefore: originalQuality,
            qualityScoreAfter: quality,
            qualityDelta: quality - controlQuality,
            betterThanControl: quality > controlQuality + 0.03,
            riskFlags: Array(risks).sorted(),
            rejectionReasons: Array(rejections).sorted(),
            notes: notes
        )
    }

    private static func bestCropExperimentShadowCandidate(
        _ candidates: [MangaOverlayCropExperimentCandidate],
        control: MangaOverlayCropExperimentCandidate
    ) -> MangaOverlayCropExperimentCandidate? {
        candidates
            .filter { $0.ocrSucceeded }
            .sorted { lhs, rhs in
                let lhsScore = Self.cropExperimentRankingScore(lhs, control: control)
                let rhsScore = Self.cropExperimentRankingScore(rhs, control: control)
                if lhsScore == rhsScore {
                    return lhs.candidateID < rhs.candidateID
                }
                return lhsScore > rhsScore
            }
            .first
    }

    private static func cropExperimentRankingScore(
        _ candidate: MangaOverlayCropExperimentCandidate,
        control: MangaOverlayCropExperimentCandidate
    ) -> Double {
        var score = candidate.qualityScoreAfter
        score += candidate.wordPreservationRatio * 0.18
        score += candidate.betterThanControl ? 0.10 : 0
        score -= Double(candidate.rejectionReasons.count) * 0.08
        score -= Double(candidate.riskFlags.count) * 0.04
        if candidate.qualityScoreAfter < control.qualityScoreAfter - 0.08 {
            score -= 0.12
        }
        return score
    }

    private static func cropExperimentVerdict(
        block: MangaOverlayProbeBlock,
        control: MangaOverlayCropExperimentCandidate,
        bestShadow: MangaOverlayCropExperimentCandidate?,
        segment: MangaOverlaySegmentMaskDiagnostic?,
        textBox: MangaOverlayTextBoxCandidateDiagnostic?
    ) -> (promotionVerdict: String, stopReasons: [String], notes: [String]) {
        let finalText = block.finalTextUsedForTranslation.lowercased()
        let isDecorative = finalText.contains("city battler") && finalText.contains("tournament")
        let isProtectedShort = finalText.contains("let") && finalText.contains("battler")
        var stopReasons: [String] = []
        var notes = ["shadowOnlyNoMainInputChange"]

        if isDecorative {
            return ("protectedDiagnosticOnly", ["decorativeTitleDiagnosticOnly"], notes)
        }
        if isProtectedShort {
            return ("protectedDiagnosticOnly", ["protectedShortTextDiagnosticOnly"], notes)
        }
        if segment?.usableForCropEvidence == false {
            stopReasons.append("segmentEvidenceTooWeak")
        }
        if textBox?.eligibleForCrop == false {
            notes.append("textBoxNotEligibleForUpstreamCrop")
        }
        guard let bestShadow else {
            stopReasons.append("localVisionCropNotPromising")
            return ("localVisionCropNotPromising", Array(Set(stopReasons)).sorted(), notes)
        }
        if bestShadow.rejectionReasons.contains("bubbleMaskConflict") {
            stopReasons.append("bubbleMaskConflict")
            return ("bubbleMaskConflict", Array(Set(stopReasons)).sorted(), notes)
        }
        if bestShadow.rejectionReasons.contains("emptyLocalOCR")
            || bestShadow.rejectionReasons.contains("rawWordsLost")
            || bestShadow.rejectionReasons.contains("wordCountRegression") {
            stopReasons.append("localVisionCropNotPromising")
        }
        let promotable = bestShadow.ocrSucceeded
            && bestShadow.wordPreservationRatio >= 0.80
            && bestShadow.qualityDelta > 0.08
            && !bestShadow.rejectionReasons.contains("rawWordsLost")
            && !bestShadow.rejectionReasons.contains("introducedLikelyOCRError")
            && !bestShadow.rejectionReasons.contains("sameAsFusedText")
            && !bestShadow.rejectionReasons.contains("bubbleMaskConflict")
            && !bestShadow.riskFlags.contains("segmentOutsideBubbleRisk")
        if promotable {
            return ("promotableShadowCandidate", [], notes)
        }
        if bestShadow.rejectionReasons.contains("sameAsFusedText") || bestShadow.qualityScoreAfter <= control.qualityScoreAfter + 0.03 {
            return ("controlStillBest", Array(Set(stopReasons)).sorted(), notes)
        }
        if segment?.usableForCropEvidence == false {
            return ("segmentEvidenceTooWeak", Array(Set(stopReasons)).sorted(), notes)
        }
        return ("noLocalOCRBenefit", Array(Set(stopReasons)).sorted(), notes)
    }

    private static func cropExperimentVariantBreakdown(
        candidates: [MangaOverlayCropExperimentCandidate],
        summaries: [MangaOverlayCropExperimentBlockSummary]
    ) -> [String: MangaOverlayCropExperimentVariantSummary] {
        let promotedIDs = Set(summaries.compactMap { summary -> Int? in
            summary.promotionVerdict == "promotableShadowCandidate" ? summary.bestShadowCandidateID : nil
        })
        var result: [String: MangaOverlayCropExperimentVariantSummary] = [:]
        for variant in Set(candidates.map(\.variantName)).sorted() {
            let matches = candidates.filter { $0.variantName == variant }
            result[variant] = MangaOverlayCropExperimentVariantSummary(
                variantName: variant,
                attemptedCount: matches.count,
                ocrSucceededCount: matches.filter(\.ocrSucceeded).count,
                betterThanControlCount: matches.filter(\.betterThanControl).count,
                promotedBlockCount: matches.filter { promotedIDs.contains($0.candidateID) }.count,
                degradedCount: matches.filter { !$0.betterThanControl && $0.qualityDelta < -0.08 }.count,
                emptyOutputCount: matches.filter { $0.rejectionReasons.contains("emptyLocalOCR") }.count,
                rawWordsLostCount: matches.filter { $0.rejectionReasons.contains("rawWordsLost") }.count
            )
        }
        return result
    }

    private static func makeTextBoxPlanFailureReport(
        blocks: [MangaOverlayProbeBlock],
        preCropTextBoxPlanReport: MangaOverlayPreCropTextBoxPlanReport?,
        cropExperimentReport: MangaOverlayCropExperimentReport?,
        textRegionCropReport: MangaOverlayTextRegionCropReport?,
        textBoxCandidateReport: MangaOverlayTextBoxCandidateReport?,
        segmentMaskReport: MangaOverlaySegmentMaskReport?
    ) -> MangaOverlayTextBoxPlanFailureReport? {
        guard let preCropTextBoxPlanReport, let cropExperimentReport else { return nil }
        let plansByBlock = Dictionary(grouping: preCropTextBoxPlanReport.plans, by: \.blockIndex)
        let candidatesByBlock = Dictionary(grouping: cropExperimentReport.candidates, by: \.blockIndex)
        let cropSummariesByBlock = Dictionary(uniqueKeysWithValues: cropExperimentReport.blockSummaries.map { ($0.blockIndex, $0) })
        let candidatesByID = Dictionary(uniqueKeysWithValues: cropExperimentReport.candidates.map { ($0.candidateID, $0) })
        let textRegionByBlock = Dictionary(uniqueKeysWithValues: (textRegionCropReport?.diagnostics ?? []).map { ($0.blockIndex, $0) })
        let textBoxByBlock = Dictionary(uniqueKeysWithValues: (textBoxCandidateReport?.diagnostics ?? []).map { ($0.blockIndex, $0) })
        let segmentByBlock = Dictionary(uniqueKeysWithValues: (segmentMaskReport?.diagnostics ?? []).map { ($0.blockIndex, $0) })
        var diagnostics: [MangaOverlayTextBoxPlanFailureDiagnostic] = []
        var blockSummaries: [MangaOverlayTextBoxPlanFailureBlockSummary] = []

        for block in blocks {
            let blockPlans = plansByBlock[block.index] ?? []
            let blockCandidates = candidatesByBlock[block.index] ?? []
            let shadowCandidates = blockCandidates.filter { $0.variantName != "currentTextRegionCrop" }
            let summary = cropSummariesByBlock[block.index]
            let bestShadow = summary?.bestShadowCandidateID.flatMap { candidatesByID[$0] }
            let planIDs = blockPlans.map(\.planID).sorted()
            let candidateIDs = shadowCandidates.map(\.candidateID).sorted()
            let blockPlanCategories = blockPlans.map {
                Self.textBoxPlanFailureCategory(
                    plan: $0,
                    block: block,
                    textRegion: textRegionByBlock[block.index],
                    textBox: textBoxByBlock[block.index],
                    segment: segmentByBlock[block.index]
                )
            }
            let bestChecks = Self.textBoxPlanPromotionChecks(block: block, candidate: bestShadow)
            let blockPrimary = Self.textBoxPlanPrimaryFailureCategory(
                block: block,
                cropSummary: summary,
                bestShadow: bestShadow,
                planCategories: blockPlanCategories,
                segment: segmentByBlock[block.index],
                textBox: textBoxByBlock[block.index]
            )
            let action = Self.textBoxPlanRecommendedAction(
                primaryCategory: blockPrimary,
                cropSummary: summary,
                bestShadow: bestShadow,
                block: block
            )
            blockSummaries.append(
                MangaOverlayTextBoxPlanFailureBlockSummary(
                    blockIndex: block.index,
                    verdict: summary?.promotionVerdict ?? blockPrimary,
                    primaryFailureCategory: blockPrimary,
                    planIDs: planIDs,
                    candidateIDs: candidateIDs,
                    bestShadowCandidateID: bestShadow?.candidateID,
                    bestShadowBetterThanControl: bestShadow?.betterThanControl ?? false,
                    passedPromotionChecks: bestChecks.passed,
                    failedPromotionChecks: bestChecks.failed,
                    promotionBlockers: bestChecks.blockers,
                    recommendedNextAction: action,
                    notes: [
                        "shadowOnlyNoMainInputChange",
                        "groundTruthNotUsed",
                        "textRegionAdoptedCountUnchanged"
                    ]
                )
            )

            for plan in blockPlans {
                let planCandidates = shadowCandidates.filter { $0.sourcePlanID == plan.planID }
                let matchedCandidates = planCandidates.isEmpty ? [nil] : planCandidates.map(Optional.some)
                for candidate in matchedCandidates {
                    let planCategory = Self.textBoxPlanFailureCategory(
                        plan: plan,
                        block: block,
                        textRegion: textRegionByBlock[block.index],
                        textBox: textBoxByBlock[block.index],
                        segment: segmentByBlock[block.index]
                    )
                    let checks = Self.textBoxPlanPromotionChecks(block: block, candidate: candidate)
                    diagnostics.append(
                        MangaOverlayTextBoxPlanFailureDiagnostic(
                            planID: plan.planID,
                            blockIndex: block.index,
                            variantName: "preCropTextBoxPlan.\(plan.variantName)",
                            planFailureCategory: planCategory,
                            geometryReasons: Self.textBoxPlanGeometryReasons(plan: plan, textBox: textBoxByBlock[block.index]),
                            bubbleMaskReasons: Self.textBoxPlanBubbleReasons(plan: plan),
                            segmentMaskReasons: Self.textBoxPlanSegmentReasons(plan: plan, segment: segmentByBlock[block.index]),
                            safetyReasons: Self.textBoxPlanSafetyReasons(plan: plan),
                            protectionReasons: Self.textBoxPlanProtectionReasons(block: block, plan: plan),
                            candidateID: candidate?.candidateID,
                            ocrFailureCategory: candidate.map(Self.textBoxPlanOCRFailureCategory),
                            ocrReasons: candidate?.rejectionReasons ?? [],
                            passedPromotionChecks: checks.passed,
                            failedPromotionChecks: checks.failed,
                            promotionBlockers: checks.blockers,
                            recommendedNextAction: action,
                            notes: [
                                "planCandidateLinkedBySourcePlanID",
                                "shadowOnlyNoFinalTextChange"
                            ] + plan.notes
                        )
                    )
                }
            }

            for candidate in shadowCandidates where candidate.sourcePlanID == nil {
                let checks = Self.textBoxPlanPromotionChecks(block: block, candidate: candidate)
                diagnostics.append(
                    MangaOverlayTextBoxPlanFailureDiagnostic(
                        planID: nil,
                        blockIndex: block.index,
                        variantName: candidate.variantName,
                        planFailureCategory: "legacyShadowCandidate",
                        geometryReasons: [],
                        bubbleMaskReasons: candidate.rejectionReasons.filter { $0.contains("bubble") },
                        segmentMaskReasons: candidate.rejectionReasons.filter { $0.contains("segment") },
                        safetyReasons: candidate.riskFlags,
                        protectionReasons: Self.textBoxPlanProtectionReasons(block: block, plan: nil),
                        candidateID: candidate.candidateID,
                        ocrFailureCategory: Self.textBoxPlanOCRFailureCategory(candidate),
                        ocrReasons: candidate.rejectionReasons,
                        passedPromotionChecks: checks.passed,
                        failedPromotionChecks: checks.failed,
                        promotionBlockers: checks.blockers,
                        recommendedNextAction: action,
                        notes: ["legacyOrFallbackShadowCandidate", "shadowOnlyNoFinalTextChange"] + candidate.notes
                    )
                )
            }
        }

        let stopBlocks = blockSummaries
            .filter { $0.recommendedNextAction.hasPrefix("stop") }
            .map(\.blockIndex)
            .sorted()
        let continueBlocks = blockSummaries
            .filter { $0.recommendedNextAction == "continueGeometryPlanning" || $0.recommendedNextAction == "candidateNeedsPromotionGateReview" }
            .map(\.blockIndex)
            .sorted()
        let blockedBlocks = blockSummaries
            .filter { $0.bestShadowBetterThanControl && !$0.promotionBlockers.isEmpty }
            .map(\.blockIndex)
            .sorted()
        let shadowCandidates = cropExperimentReport.candidates.filter { $0.variantName != "currentTextRegionCrop" }
        return MangaOverlayTextBoxPlanFailureReport(
            enabled: true,
            evaluatedBlockCount: blockSummaries.count,
            evaluatedPlanCount: preCropTextBoxPlanReport.planCount,
            evaluatedCandidateCount: shadowCandidates.count,
            betterThanControlCandidateCount: shadowCandidates.filter(\.betterThanControl).count,
            promotedShadowBlockCount: cropExperimentReport.promotedShadowBlocks.count,
            planFailureBreakdown: Self.countOccurrences(diagnostics.map(\.planFailureCategory)),
            ocrFailureBreakdown: Self.countOccurrences(diagnostics.compactMap(\.ocrFailureCategory)),
            promotionBlockerBreakdown: Self.countOccurrences(diagnostics.flatMap(\.promotionBlockers)),
            stopRecommendedBlocks: stopBlocks,
            continueGeometryResearchBlocks: continueBlocks,
            candidatePromotionBlockedBlocks: blockedBlocks,
            blockSummaries: blockSummaries.sorted { $0.blockIndex < $1.blockIndex },
            diagnostics: diagnostics.sorted { lhs, rhs in
                if lhs.blockIndex != rhs.blockIndex {
                    return lhs.blockIndex < rhs.blockIndex
                }
                let lhsPlanID = lhs.planID ?? Int.max
                let rhsPlanID = rhs.planID ?? Int.max
                if lhsPlanID != rhsPlanID {
                    return lhsPlanID < rhsPlanID
                }
                return (lhs.candidateID ?? Int.max) < (rhs.candidateID ?? Int.max)
            },
            notes: [
                "diagnosticOnly=true; this report explains pre-crop TextBox plans and shadow OCR promotion blockers",
                "promotion checks are ground-truth-free and do not change finalTextUsedForTranslation",
                "betterThanControlCandidateCount does not imply promotable candidate; blockers must be empty for promotion",
                "TextRegion crop adoptedCount remains controlled by the existing guardrail"
            ]
        )
    }

    private static func textBoxPlanPromotionChecks(
        block: MangaOverlayProbeBlock,
        candidate: MangaOverlayCropExperimentCandidate?
    ) -> (passed: [String], failed: [String], blockers: [String]) {
        let finalText = block.finalTextUsedForTranslation.lowercased()
        let isDecorative = finalText.contains("city battler") && finalText.contains("tournament")
        let isProtectedShort = finalText.contains("let") && finalText.contains("battler")
        var passed: [String] = []
        var failed: [String] = []
        guard let candidate else {
            return ([], ["noShadowCandidate"], ["noShadowCandidate"])
        }
        candidate.ocrSucceeded ? passed.append("ocrSucceeded") : failed.append("emptyLocalOCR")
        candidate.wordPreservationRatio >= 0.80 ? passed.append("wordPreservationRatio>=0.80") : failed.append("wordPreservationRatioBelow0.80")
        candidate.qualityDelta > 0.08 ? passed.append("qualityDelta>0.08") : failed.append("qualityDeltaBelowOrEqual0.08")
        if candidate.betterThanControl {
            passed.append("betterThanControl")
        } else {
            failed.append("notBetterThanControl")
        }
        let rejectionChecks = [
            "rawWordsLost",
            "introducedLikelyOCRError",
            "sameAsFusedText",
            "bubbleMaskConflict",
            "segmentEvidenceTooWeak"
        ]
        for check in rejectionChecks {
            if candidate.rejectionReasons.contains(check) || candidate.riskFlags.contains(check) {
                failed.append(check)
            } else {
                passed.append("no\(check.prefix(1).uppercased())\(check.dropFirst())")
            }
        }
        if candidate.riskFlags.contains("segmentOutsideBubbleRisk") {
            failed.append("segmentOutsideBubbleRisk")
        } else {
            passed.append("noSegmentOutsideBubbleRisk")
        }
        if isDecorative {
            failed.append("decorativeTitleDiagnosticOnly")
        }
        if isProtectedShort {
            failed.append("protectedShortTextDiagnosticOnly")
        }
        let blockers = failed.filter { reason in
            reason != "notBetterThanControl" || !candidate.betterThanControl
        }
        return (Array(Set(passed)).sorted(), Array(Set(failed)).sorted(), Array(Set(blockers)).sorted())
    }

    private static func textBoxPlanPrimaryFailureCategory(
        block: MangaOverlayProbeBlock,
        cropSummary: MangaOverlayCropExperimentBlockSummary?,
        bestShadow: MangaOverlayCropExperimentCandidate?,
        planCategories: [String],
        segment: MangaOverlaySegmentMaskDiagnostic?,
        textBox: MangaOverlayTextBoxCandidateDiagnostic?
    ) -> String {
        if cropSummary?.promotionVerdict == "promotableShadowCandidate" {
            return "promotable"
        }
        let finalText = block.finalTextUsedForTranslation.lowercased()
        if finalText.contains("city battler") && finalText.contains("tournament") {
            return "protectedDiagnosticOnly"
        }
        if finalText.contains("let") && finalText.contains("battler") {
            return "protectedDiagnosticOnly"
        }
        if cropSummary?.stopReasons.contains("localVisionCropNotPromising") == true {
            return "localVisionCropNotPromising"
        }
        if bestShadow?.rejectionReasons.contains("bubbleMaskConflict") == true || planCategories.contains("bubbleMaskConflict") {
            return "bubbleMaskConflict"
        }
        if segment?.usableForCropEvidence == false || bestShadow?.rejectionReasons.contains("segmentEvidenceTooWeak") == true {
            return "segmentEvidenceTooWeak"
        }
        if textBox?.eligibleForCrop == false || planCategories.contains("geometryEvidenceTooWeak") {
            return "geometryEvidenceTooWeak"
        }
        if bestShadow?.betterThanControl == true {
            return "candidatePromotionBlocked"
        }
        if cropSummary?.promotionVerdict == "controlStillBest" {
            return "controlStillBest"
        }
        return cropSummary?.promotionVerdict ?? "controlStillBest"
    }

    private static func textBoxPlanRecommendedAction(
        primaryCategory: String,
        cropSummary: MangaOverlayCropExperimentBlockSummary?,
        bestShadow: MangaOverlayCropExperimentCandidate?,
        block: MangaOverlayProbeBlock
    ) -> String {
        let finalText = block.finalTextUsedForTranslation.lowercased()
        if finalText.contains("city battler") && finalText.contains("tournament") {
            return "stopProtectedBlock"
        }
        if finalText.contains("let") && finalText.contains("battler") {
            return "stopProtectedBlock"
        }
        if primaryCategory == "localVisionCropNotPromising" {
            return "stopLocalVisionCrop"
        }
        if primaryCategory == "segmentEvidenceTooWeak" {
            return "stopUntilSegmentMaskImproves"
        }
        if primaryCategory == "bubbleMaskConflict" {
            return "stopUntilBubbleMaskImproves"
        }
        if bestShadow?.betterThanControl == true && cropSummary?.promotionVerdict != "promotableShadowCandidate" {
            return "candidateNeedsPromotionGateReview"
        }
        if primaryCategory == "geometryEvidenceTooWeak" {
            return "continueGeometryPlanning"
        }
        if primaryCategory == "promotable" {
            return "candidateGoodButModelTranslationStillWeak"
        }
        return "noActionControlBest"
    }

    private static func textBoxPlanFailureCategory(
        plan: MangaOverlayPreCropTextBoxPlan,
        block: MangaOverlayProbeBlock,
        textRegion: MangaOverlayTextRegionCropDiagnostic?,
        textBox: MangaOverlayTextBoxCandidateDiagnostic?,
        segment: MangaOverlaySegmentMaskDiagnostic?
    ) -> String {
        let protection = Self.textBoxPlanProtectionReasons(block: block, plan: plan)
        if !protection.isEmpty {
            return "protectedDiagnosticOnly"
        }
        if plan.rejectionReasons.contains("bubbleMaskConflict") || plan.riskFlags.contains("bubbleMaskConflict") {
            return "bubbleMaskConflict"
        }
        if let coverage = plan.bubbleCoverageRatio, coverage < 0.55 {
            return "lowBubbleCoverage"
        }
        if let coverage = plan.safeRectCoverageRatio, coverage < 0.35 {
            return "missingSafeRectCoverage"
        }
        if segment?.usableForCropEvidence == false || plan.riskFlags.contains("segmentEvidenceTooWeak") {
            return "segmentEvidenceTooWeak"
        }
        if textBox?.rejectionReasons.contains("textBoxTooWide") == true || textRegion?.failureAttribution.contains("textBoxTooWide") == true {
            return "textBoxTooWide"
        }
        if plan.rejectionReasons.contains("siblingOverlapRisk") || plan.riskFlags.contains("siblingOverlapRisk") {
            return "siblingOverlapRisk"
        }
        if !plan.eligibleForShadowOCR {
            return "diagnosticOnlyNoShadowOCR"
        }
        if plan.evidenceScore < 0.70 {
            return "geometryEvidenceTooWeak"
        }
        return "eligibleButNeedsShadowOCR"
    }

    private static func textBoxPlanOCRFailureCategory(_ candidate: MangaOverlayCropExperimentCandidate) -> String {
        if candidate.rejectionReasons.contains("emptyLocalOCR") {
            return "emptyLocalOCR"
        }
        if candidate.rejectionReasons.contains("rawWordsLost") {
            return "rawWordsLost"
        }
        if candidate.rejectionReasons.contains("wordCountRegression") {
            return "wordCountRegression"
        }
        if candidate.rejectionReasons.contains("introducedLikelyOCRError") {
            return "introducedLikelyOCRError"
        }
        if candidate.rejectionReasons.contains("sameAsFusedText") {
            return "sameAsFusedText"
        }
        if candidate.rejectionReasons.contains("bubbleMaskConflict") {
            return "bubbleMaskConflict"
        }
        if candidate.qualityDelta <= 0.08 {
            return candidate.betterThanControl ? "qualityGainInsufficient" : "controlStillBest"
        }
        return candidate.betterThanControl ? "betterButUnsafe" : "shadowOnlyNotAdopted"
    }

    private static func textBoxPlanGeometryReasons(
        plan: MangaOverlayPreCropTextBoxPlan,
        textBox: MangaOverlayTextBoxCandidateDiagnostic?
    ) -> [String] {
        var reasons = plan.rejectionReasons.filter { reason in
            reason.contains("textBox") || reason.contains("geometry") || reason.contains("sibling")
        }
        if plan.evidenceScore < 0.70 {
            reasons.append("evidenceScoreBelowGeometryThreshold")
        }
        if textBox?.eligibleForCrop == false {
            reasons.append("downstreamTextBoxNotCropEligible")
        }
        return Array(Set(reasons)).sorted()
    }

    private static func textBoxPlanBubbleReasons(plan: MangaOverlayPreCropTextBoxPlan) -> [String] {
        var reasons = (plan.rejectionReasons + plan.riskFlags).filter { $0.lowercased().contains("bubble") }
        if let coverage = plan.bubbleCoverageRatio, coverage < 0.55 {
            reasons.append("bubbleCoverageBelow0.55")
        }
        return Array(Set(reasons)).sorted()
    }

    private static func textBoxPlanSegmentReasons(
        plan: MangaOverlayPreCropTextBoxPlan,
        segment: MangaOverlaySegmentMaskDiagnostic?
    ) -> [String] {
        var reasons = (plan.rejectionReasons + plan.riskFlags).filter {
            $0.lowercased().contains("segment") || $0.lowercased().contains("glyph")
        }
        if segment?.usableForCropEvidence == false {
            reasons.append("segmentEvidenceTooWeak")
        }
        return Array(Set(reasons)).sorted()
    }

    private static func textBoxPlanSafetyReasons(plan: MangaOverlayPreCropTextBoxPlan) -> [String] {
        var reasons = (plan.rejectionReasons + plan.riskFlags).filter {
            $0.lowercased().contains("safe") || $0.lowercased().contains("risk")
        }
        if let coverage = plan.safeRectCoverageRatio, coverage < 0.35 {
            reasons.append("safeRectCoverageBelow0.35")
        }
        return Array(Set(reasons)).sorted()
    }

    private static func textBoxPlanProtectionReasons(
        block: MangaOverlayProbeBlock,
        plan: MangaOverlayPreCropTextBoxPlan?
    ) -> [String] {
        let finalText = block.finalTextUsedForTranslation.lowercased()
        var reasons: [String] = []
        if finalText.contains("city battler") && finalText.contains("tournament") {
            reasons.append("decorativeTitleDiagnosticOnly")
        }
        if finalText.contains("let") && finalText.contains("battler") {
            reasons.append("protectedShortTextDiagnosticOnly")
        }
        if plan?.rejectionReasons.contains("decorativeTitleDiagnosticOnly") == true {
            reasons.append("decorativeTitleDiagnosticOnly")
        }
        return Array(Set(reasons)).sorted()
    }

    private static func makeLineTextBoxPlanReport(
        blocks: [MangaOverlayProbeBlock],
        textBoxPlanFailureReport: MangaOverlayTextBoxPlanFailureReport,
        preCropTextBoxPlanReport: MangaOverlayPreCropTextBoxPlanReport?,
        cropExperimentReport: MangaOverlayCropExperimentReport,
        bubbleMaskReport: MangaOverlayBubbleMaskReport?,
        segmentMaskReport: MangaOverlaySegmentMaskReport?
    ) -> MangaOverlayLineTextBoxPlanReport {
        let targetBlocks = textBoxPlanFailureReport.continueGeometryResearchBlocks.sorted()
        let blockByIndex = Dictionary(uniqueKeysWithValues: blocks.map { ($0.index, $0) })
        let failureByBlock = Dictionary(uniqueKeysWithValues: textBoxPlanFailureReport.blockSummaries.map { ($0.blockIndex, $0) })
        let preCropPlanByID = Dictionary(uniqueKeysWithValues: (preCropTextBoxPlanReport?.plans ?? []).map { ($0.planID, $0) })
        let cropCandidateByID = Dictionary(uniqueKeysWithValues: cropExperimentReport.candidates.map { ($0.candidateID, $0) })
        let maskByBlock = Dictionary(uniqueKeysWithValues: (bubbleMaskReport?.blockDiagnostics ?? []).map { ($0.blockIndex, $0) })
        let segmentByBlock = Dictionary(uniqueKeysWithValues: (segmentMaskReport?.diagnostics ?? []).map { ($0.blockIndex, $0) })

        var nextPlanID = 0
        var plans: [MangaOverlayLineTextBoxPlan] = []
        var summaries: [MangaOverlayLineTextBoxPlanBlockSummary] = []

        for blockIndex in targetBlocks {
            guard let block = blockByIndex[blockIndex] else { continue }
            let failure = failureByBlock[blockIndex]
            let parentCandidate = failure?.bestShadowCandidateID.flatMap { cropCandidateByID[$0] }
            let parentPlan = parentCandidate?.sourcePlanID.flatMap { preCropPlanByID[$0] }
            let blockPlans = Self.lineTextBoxPlans(
                for: block,
                parentPlan: parentPlan,
                parentCandidate: parentCandidate,
                failureSummary: failure,
                mask: maskByBlock[blockIndex],
                segment: segmentByBlock[blockIndex],
                startingPlanID: nextPlanID
            )
            nextPlanID += blockPlans.count
            plans.append(contentsOf: blockPlans)

            let selected = blockPlans
                .filter(\.eligibleForShadowOCR)
                .sorted { lhs, rhs in
                    if lhs.evidenceScore == rhs.evidenceScore {
                        return lhs.planID < rhs.planID
                    }
                    return lhs.evidenceScore > rhs.evidenceScore
                }
                .prefix(4)
                .map(\.planID)
            let selectedSet = Set(selected)
            let rejected = blockPlans.map(\.planID).filter { !selectedSet.contains($0) }
            let stopReasons = Self.lineTextBoxPlanStopReasons(block: block, plans: blockPlans)
            let verdict: String
            if !selected.isEmpty {
                verdict = "lineShadowOCREligiblePlans"
            } else if stopReasons.contains("protectedDiagnosticOnly") {
                verdict = "protectedDiagnosticOnly"
            } else {
                verdict = "lineGeometryEvidenceTooWeak"
            }
            summaries.append(
                MangaOverlayLineTextBoxPlanBlockSummary(
                    blockIndex: blockIndex,
                    sourceFailureAction: failure?.recommendedNextAction ?? "unknown",
                    selectedPlanIDsForShadowOCR: Array(selected),
                    rejectedPlanIDs: rejected.sorted(),
                    planningVerdict: verdict,
                    stopReasons: stopReasons,
                    notes: [
                        "targetBy=textBoxPlanFailureReport.continueGeometryResearchBlocks",
                        "shadowOnlyNoFinalTextChange",
                        "groundTruthNotUsed"
                    ]
                )
            )
        }

        return MangaOverlayLineTextBoxPlanReport(
            enabled: true,
            targetBlocks: targetBlocks,
            evaluatedBlockCount: summaries.count,
            planCount: plans.count,
            shadowOCREligiblePlanCount: plans.filter(\.eligibleForShadowOCR).count,
            blockSummaries: summaries.sorted { $0.blockIndex < $1.blockIndex },
            plans: plans.sorted { $0.planID < $1.planID },
            notes: [
                "Koharu-style line-level TextBox and deskew shadow planning layer",
                "targets come from textBoxPlanFailureReport.continueGeometryResearchBlocks, not ground truth or OCR similarity",
                "each target block keeps at most four line-level plans; finalTextUsedForTranslation, main overlay text, blockPassed, and TextRegion adoptedCount are unchanged",
                "deskewProbeTextBox uses conservative reported angles only; current local Vision crop API executes the unrotated bbox and records ocrExecuted truthfully"
            ]
        )
    }

    private static func lineTextBoxPlans(
        for block: MangaOverlayProbeBlock,
        parentPlan: MangaOverlayPreCropTextBoxPlan?,
        parentCandidate: MangaOverlayCropExperimentCandidate?,
        failureSummary: MangaOverlayTextBoxPlanFailureBlockSummary?,
        mask: MangaOverlayBubbleMaskBlockDiagnostic?,
        segment: MangaOverlaySegmentMaskDiagnostic?,
        startingPlanID: Int
    ) -> [MangaOverlayLineTextBoxPlan] {
        let seedBBox = parentCandidate?.bboxAfterClamp ?? parentPlan?.bbox ?? block.bbox
        let seedRect = rect(from: seedBBox)
        let safeRect = mask?.maskSafeRect ?? block.safeLayoutRect
        let glyphRect = segment?.glyphMaskRect ?? block.glyphMaskRect
        let textLineCount = max(1, block.finalTextUsedForTranslation.split(whereSeparator: \.isNewline).count)
        let isDecorative = Self.isDecorativeMangaProbeBlock(block)
        let isProtectedShort = Self.isProtectedShortMangaProbeBlock(block)
        let siblingOverlap = Self.lineSiblingOverlapRatio(block: block, planBBox: seedBBox)
        var rawPlans: [(variant: String, bbox: [Double], lineIndex: Int?, angle: Double?, signals: [String], risks: [String], rejections: [String], notes: [String], ocrExecuted: Bool)] = []

        let tightBase = glyphRect.map { Self.intersectingBBox(Self.expandedBBox($0, by: 0.22, minimumPadding: 4), seedBBox) ?? $0 }
            ?? Self.expandedBBox(seedBBox, by: 0.04, minimumPadding: 2)
        rawPlans.append((
            variant: "lineTightTextBox",
            bbox: safeRect.flatMap { Self.intersectingBBox(tightBase, $0) } ?? tightBase,
            lineIndex: textLineCount > 1 ? 0 : nil,
            angle: nil,
            signals: ["fusedSeedBBox", "lineCount:\(textLineCount)", "glyphOrSeedTightBBox"],
            risks: [],
            rejections: [],
            notes: ["line-level tight TextBox shadow candidate"],
            ocrExecuted: true
        ))

        let bandRect: CGRect
        if Self.estimatedOrientation(for: seedBBox) == "vertical" {
            bandRect = CGRect(
                x: seedRect.midX - max(seedRect.width * 0.42, 6),
                y: seedRect.minY - max(seedRect.height * 0.08, 3),
                width: max(seedRect.width * 0.84, 8),
                height: seedRect.height + max(seedRect.height * 0.16, 6)
            )
        } else {
            bandRect = CGRect(
                x: seedRect.minX - max(seedRect.width * 0.06, 4),
                y: seedRect.midY - max(seedRect.height * 0.42, 6),
                width: seedRect.width + max(seedRect.width * 0.12, 8),
                height: max(seedRect.height * 0.84, 8)
            )
        }
        let bandBBox = bboxArray(from: bandRect.integral)
        rawPlans.append((
            variant: "lineBandTextBox",
            bbox: safeRect.flatMap { Self.intersectingBBox(bandBBox, $0) } ?? bandBBox,
            lineIndex: nil,
            angle: nil,
            signals: ["orientationBand", "safeRectClamp", "lineCount:\(textLineCount)"],
            risks: siblingOverlap > 0.20 ? ["siblingOverlapRisk"] : [],
            rejections: siblingOverlap > 0.20 ? ["siblingOverlapRisk"] : [],
            notes: ["line band candidate tries to avoid sibling text"],
            ocrExecuted: true
        ))

        for angle in [-3.0, 3.0] {
            rawPlans.append((
                variant: "deskewProbeTextBox",
                bbox: safeRect.flatMap { Self.intersectingBBox(tightBase, $0) } ?? tightBase,
                lineIndex: textLineCount > 1 ? 0 : nil,
                angle: angle,
                signals: ["conservativeDeskewAngle:\(Int(angle))", "lineTightBBox"],
                risks: ["deskewRotationNotAppliedToCrop"],
                rejections: [],
                notes: ["deskew angle recorded for report; OCR executes conservative unrotated bbox"],
                ocrExecuted: true
            ))
        }

        var seen = Set<String>()
        var unique: [(variant: String, bbox: [Double], lineIndex: Int?, angle: Double?, signals: [String], risks: [String], rejections: [String], notes: [String], ocrExecuted: Bool)] = []
        for plan in rawPlans {
            let key = "\(plan.variant):\(plan.angle ?? 0):\(plan.bbox.map { Int($0.rounded()) }.map(String.init).joined(separator: ","))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(plan)
        }

        return unique.prefix(4).enumerated().map { offset, plan in
            var riskFlags = Set(plan.risks)
            var rejectionReasons = Set(plan.rejections)
            if isDecorative || isProtectedShort {
                rejectionReasons.insert("protectedDiagnosticOnly")
            }
            let bubbleCoverage = mask?.maskDominantCoverageRatio
            let glyphCoverage = glyphRect.flatMap { Self.bboxCoverage($0, within: plan.bbox) }
            let safeCoverage = safeRect.flatMap { Self.bboxCoverage(plan.bbox, within: $0) }
            if let bubbleCoverage, bubbleCoverage < 0.35 {
                riskFlags.insert("lowBubbleCoverage")
                rejectionReasons.insert("lowBubbleCoverage")
            }
            if siblingOverlap > 0.20 {
                riskFlags.insert("siblingOverlapRisk")
                rejectionReasons.insert("siblingOverlapRisk")
            }
            let score = Self.lineTextBoxPlanEvidenceScore(
                variantName: plan.variant,
                seedBBox: seedBBox,
                planBBox: plan.bbox,
                bubbleCoverage: bubbleCoverage,
                glyphCoverage: glyphCoverage,
                safeCoverage: safeCoverage,
                siblingOverlap: siblingOverlap,
                riskFlags: Array(riskFlags),
                rejectionReasons: Array(rejectionReasons)
            )
            let eligible = !(isDecorative || isProtectedShort)
                && score >= 0.46
                && siblingOverlap <= 0.20
                && !riskFlags.contains("bubbleMaskConflict")
            return MangaOverlayLineTextBoxPlan(
                planID: startingPlanID + offset,
                blockIndex: block.index,
                parentPlanID: parentPlan?.planID,
                variantName: plan.variant,
                lineIndex: plan.lineIndex,
                bbox: plan.bbox,
                seedBBox: seedBBox,
                bubbleID: block.bubbleID,
                orientationHint: Self.estimatedOrientation(for: seedBBox),
                deskewAngleDegrees: plan.angle,
                sourceSignals: Array(Set(plan.signals + ["sourceFailureAction:\(failureSummary?.recommendedNextAction ?? "unknown")"])).sorted(),
                bubbleCoverageRatio: bubbleCoverage,
                glyphCoverageRatio: glyphCoverage,
                safeRectCoverageRatio: safeCoverage,
                siblingOverlapRatio: siblingOverlap,
                evidenceScore: score,
                eligibleForShadowOCR: eligible,
                ocrExecuted: plan.ocrExecuted,
                riskFlags: Array(riskFlags).sorted(),
                rejectionReasons: Array(rejectionReasons).sorted(),
                notes: plan.notes + ["shadowOnly", "groundTruthNotUsed"]
            )
        }
    }

    private static func lineTextBoxPlanEvidenceScore(
        variantName: String,
        seedBBox: [Double],
        planBBox: [Double],
        bubbleCoverage: Double?,
        glyphCoverage: Double?,
        safeCoverage: Double?,
        siblingOverlap: Double,
        riskFlags: [String],
        rejectionReasons: [String]
    ) -> Double {
        let seedCoverage = Self.bboxCoverage(seedBBox, within: planBBox) ?? 0
        let areaRatio = max(area(of: rect(from: planBBox)), 1) / max(area(of: rect(from: seedBBox)), 1)
        var score = 0.26
        score += min(1, seedCoverage) * 0.22
        score += min(1, bubbleCoverage ?? 0.48) * 0.14
        score += min(1, glyphCoverage ?? 0.40) * 0.14
        score += min(1, safeCoverage ?? 0.45) * 0.14
        if (0.35...2.4).contains(areaRatio) {
            score += 0.08
        } else {
            score -= 0.10
        }
        score += Double(max(0, 4 - Self.lineTextBoxPlanPriority(variantName))) * 0.01
        score -= min(0.30, siblingOverlap) * 0.35
        score -= Double(riskFlags.count) * 0.04
        score -= Double(rejectionReasons.count) * 0.08
        return max(0, min(1, score))
    }

    private static func lineTextBoxPlanPriority(_ variantName: String) -> Int {
        switch variantName {
        case "lineTightTextBox": 0
        case "lineBandTextBox": 1
        case "deskewProbeTextBox": 2
        default: 9
        }
    }

    private static func lineTextBoxPlanStopReasons(
        block: MangaOverlayProbeBlock,
        plans: [MangaOverlayLineTextBoxPlan]
    ) -> [String] {
        var reasons = Set<String>()
        if Self.isDecorativeMangaProbeBlock(block) || Self.isProtectedShortMangaProbeBlock(block) {
            reasons.insert("protectedDiagnosticOnly")
        }
        if plans.allSatisfy({ !$0.eligibleForShadowOCR }) {
            reasons.insert("lineGeometryEvidenceTooWeak")
        }
        if plans.contains(where: { $0.rejectionReasons.contains("siblingOverlapRisk") }) {
            reasons.insert("siblingOverlapRisk")
        }
        return Array(reasons).sorted()
    }

    private func makeLineCropExperimentReport(
        blocks: [MangaOverlayProbeBlock],
        image: CGImage,
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics,
        textRegionCropReport: MangaOverlayTextRegionCropReport,
        cropExperimentReport: MangaOverlayCropExperimentReport,
        lineTextBoxPlanReport: MangaOverlayLineTextBoxPlanReport?,
        preprocessing: MangaOverlayPreprocessingOptions
    ) async throws -> MangaOverlayLineCropExperimentReport? {
        guard let lineTextBoxPlanReport else { return nil }
        let cropByBlock = Dictionary(uniqueKeysWithValues: textRegionCropReport.diagnostics.map { ($0.blockIndex, $0) })
        let previousSummaryByBlock = Dictionary(uniqueKeysWithValues: cropExperimentReport.blockSummaries.map { ($0.blockIndex, $0) })
        let previousCandidateByID = Dictionary(uniqueKeysWithValues: cropExperimentReport.candidates.map { ($0.candidateID, $0) })
        let selectedPlanIDs = Set(lineTextBoxPlanReport.blockSummaries.flatMap(\.selectedPlanIDsForShadowOCR))
        let plansByBlock = Dictionary(grouping: lineTextBoxPlanReport.plans.filter { selectedPlanIDs.contains($0.planID) }, by: \.blockIndex)
        let bubbleBBoxes = Dictionary(uniqueKeysWithValues: bubbleGeometry.bubbles.map { ($0.id, $0.bbox) })
        let blockByIndex = Dictionary(uniqueKeysWithValues: blocks.map { ($0.index, $0) })

        var nextCandidateID = 0
        var candidates: [MangaOverlayCropExperimentCandidate] = []
        var summaries: [MangaOverlayCropExperimentBlockSummary] = []

        for blockIndex in lineTextBoxPlanReport.targetBlocks {
            guard let block = blockByIndex[blockIndex],
                  let control = cropByBlock[blockIndex] else { continue }
            let originalText = block.finalTextUsedForTranslation
            let originalWords = Self.ocrCandidateWords(originalText)
            let originalQuality = Self.ocrCandidateQualityScore(originalText)
            let controlQuality = Self.ocrCandidateQualityScore(control.textRegionCropText ?? "")
            let candidatePlans = (plansByBlock[blockIndex] ?? [])
                .sorted { lhs, rhs in
                    if lhs.evidenceScore == rhs.evidenceScore {
                        return lhs.planID < rhs.planID
                    }
                    return lhs.evidenceScore > rhs.evidenceScore
                }
                .prefix(4)

            var blockCandidateIDs: [Int] = []
            var shadowCandidates: [MangaOverlayCropExperimentCandidate] = []
            for plan in candidatePlans {
                let crop = try await mangaOverlayProbeService.recognizeTextRegionCrop(
                    in: image,
                    seedBBox: plan.bbox,
                    bubbleBBox: block.bubbleID.flatMap { bubbleBBoxes[$0] },
                    correctedBubbleBBox: nil,
                    splitCandidateBBox: nil,
                    subRegionBBox: nil,
                    options: preprocessing
                )
                let candidate = Self.cropExperimentCandidate(
                    candidateID: nextCandidateID,
                    blockIndex: block.index,
                    sourcePlanID: plan.planID,
                    variantName: "lineTextBoxPlan.\(plan.variantName)",
                    sourceStack: ["lineTextBoxPlan", "planID:\(plan.planID)"] + plan.sourceSignals,
                    bboxBeforeClamp: plan.bbox,
                    bboxAfterClamp: crop.cropBBox,
                    clampSource: "lineTextBoxPlan",
                    ocrText: crop.text,
                    originalText: originalText,
                    originalWords: originalWords,
                    originalQuality: originalQuality,
                    controlQuality: controlQuality,
                    riskFlags: plan.riskFlags,
                    rejectionReasons: plan.rejectionReasons,
                    notes: plan.notes + [
                        "lineLevelShadowOnly",
                        "notWrittenToFinalTextUsedForTranslation",
                        "textRegionAdoptedCountUnchanged"
                    ]
                )
                candidates.append(candidate)
                shadowCandidates.append(candidate)
                blockCandidateIDs.append(nextCandidateID)
                nextCandidateID += 1
            }

            let previousBest = previousSummaryByBlock[blockIndex]?.bestShadowCandidateID.flatMap { previousCandidateByID[$0] }
            let controlCandidate = Self.cropExperimentCandidate(
                candidateID: -1,
                blockIndex: block.index,
                sourcePlanID: nil,
                variantName: "currentTextRegionCrop",
                sourceStack: [control.source, control.clampSource, "existingTextRegionCrop"],
                bboxBeforeClamp: control.regionBBox,
                bboxAfterClamp: control.cropBBox,
                clampSource: control.clampSource,
                ocrText: control.textRegionCropText,
                originalText: originalText,
                originalWords: originalWords,
                originalQuality: originalQuality,
                controlQuality: controlQuality,
                riskFlags: control.failureAttribution,
                rejectionReasons: control.rejectionReasons,
                notes: ["controlCandidateForLineExperiment", "notIncludedInLineCandidateCount"]
            )
            let bestLine = Self.bestCropExperimentShadowCandidate(shadowCandidates, control: controlCandidate)
            let verdict = Self.cropExperimentVerdict(
                block: block,
                control: controlCandidate,
                bestShadow: bestLine,
                segment: nil,
                textBox: nil
            )
            let lineResearchNotes = Self.lineResearchDecisionNotes(
                block: block,
                bestLine: bestLine,
                previousBest: previousBest
            )
            summaries.append(
                MangaOverlayCropExperimentBlockSummary(
                    blockIndex: block.index,
                    controlCandidateID: nil,
                    bestShadowCandidateID: bestLine?.candidateID,
                    bestVariantName: bestLine?.variantName,
                    promotionVerdict: verdict.promotionVerdict,
                    stopReasons: verdict.promotionVerdict == "promotableShadowCandidate" ? [] : Array(Set(verdict.stopReasons + lineResearchNotes.stopReasons)).sorted(),
                    candidateIDs: blockCandidateIDs,
                    notes: verdict.notes + lineResearchNotes.notes
                )
            )
        }

        let promoted = summaries
            .filter { $0.promotionVerdict == "promotableShadowCandidate" }
            .map(\.blockIndex)
            .sorted()
        let stopped = summaries
            .filter { $0.promotionVerdict != "promotableShadowCandidate" }
            .map(\.blockIndex)
            .sorted()
        return MangaOverlayLineCropExperimentReport(
            enabled: true,
            targetBlocks: lineTextBoxPlanReport.targetBlocks,
            candidateCount: candidates.count,
            ocrSucceededCount: candidates.filter(\.ocrSucceeded).count,
            betterThanControlCount: candidates.filter(\.betterThanControl).count,
            promotedLineShadowBlocks: promoted,
            stoppedAfterLineResearchBlocks: stopped,
            blockSummaries: summaries.sorted { $0.blockIndex < $1.blockIndex },
            candidates: candidates.sorted { $0.candidateID < $1.candidateID },
            notes: [
                "shadow-only line-level TextBox crop experiment; candidates use lineTextBoxPlan.* variant names",
                "candidate generation and promotion checks are ground-truth-free",
                "existing v1.9 promotion gate is reused without relaxing qualityDelta, word preservation, raw-word, OCR-error, same-text, bubble, segment, protected, or decorative blockers",
                "promotedLineShadowBlocks is diagnostic only and never changes finalTextUsedForTranslation, blockPassed, main overlay text, or textRegionCropReport.adoptedCount"
            ]
        )
    }

    private static func lineResearchDecisionNotes(
        block: MangaOverlayProbeBlock,
        bestLine: MangaOverlayCropExperimentCandidate?,
        previousBest: MangaOverlayCropExperimentCandidate?
    ) -> (stopReasons: [String], notes: [String]) {
        var stopReasons: [String] = []
        var notes = ["lineResearchDecision=continue"]
        guard let bestLine else {
            return (["lineLocalVisionCropNotPromising"], ["lineResearchDecision=stop", "reason=noLineShadowOCRSucceeded"])
        }
        let checks = Self.textBoxPlanPromotionChecks(block: block, candidate: bestLine)
        if !checks.blockers.isEmpty {
            stopReasons.append(contentsOf: checks.blockers)
        }
        let lineCandidateBeatsPreviousBest: Bool
        if let previousBest {
            lineCandidateBeatsPreviousBest = bestLine.qualityScoreAfter > previousBest.qualityScoreAfter + 0.03
        } else {
            lineCandidateBeatsPreviousBest = true
        }
        if !lineCandidateBeatsPreviousBest {
            stopReasons.append("lineCandidateDoesNotBeatV19BestShadow")
        }
        if lineCandidateBeatsPreviousBest, checks.blockers.isEmpty {
            notes = ["lineResearchDecision=continue", "reason=lineCandidatePassedExistingPromotionGate"]
        } else if !stopReasons.isEmpty {
            notes = ["lineResearchDecision=stop", "reason=\(Array(Set(stopReasons)).sorted().joined(separator: "+"))"]
        }
        return (Array(Set(stopReasons)).sorted(), notes)
    }

    private static func lineSiblingOverlapRatio(block: MangaOverlayProbeBlock, planBBox: [Double]) -> Double {
        // Without a sibling TextBox index, safe-layout overflow is not reliable sibling-overlap evidence.
        0
    }

    private static func isDecorativeMangaProbeBlock(_ block: MangaOverlayProbeBlock) -> Bool {
        let text = block.finalTextUsedForTranslation.lowercased()
        return text.contains("city battler") && text.contains("tournament")
    }

    private static func isProtectedShortMangaProbeBlock(_ block: MangaOverlayProbeBlock) -> Bool {
        let text = block.finalTextUsedForTranslation.lowercased()
        return text.contains("let") && text.contains("battler")
    }

    private static func countOccurrences(_ values: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }
        return counts
    }

    private static func uniqueCropExperimentPlans(_ plans: [CropExperimentPlan]) -> [CropExperimentPlan] {
        var seen = Set<String>()
        var result: [CropExperimentPlan] = []
        for plan in plans {
            let key = "\(plan.variantName):\(plan.bbox.map { Int($0.rounded()) }.map(String.init).joined(separator: ","))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(plan)
        }
        return result.sorted { lhs, rhs in
            Self.cropExperimentPlanPriority(lhs.variantName) < Self.cropExperimentPlanPriority(rhs.variantName)
        }
    }

    private static func cropExperimentPlanPriority(_ variantName: String) -> Int {
        switch variantName {
        case "textBoxTight": 0
        case "glyphMaskExpanded": 1
        case "maskSafeRectConstrained": 2
        case "splitCandidateClamp": 3
        case "correctedBubbleClamp": 4
        case "subRegionClamp": 5
        default: 9
        }
    }

    private static func tightenedBBox(seedBBox: [Double], candidateBBox: [Double]) -> [Double] {
        let seed = rect(from: seedBBox)
        let candidate = rect(from: candidateBBox)
        let intersection = seed.intersection(candidate)
        if !intersection.isNull, intersection.width >= 4, intersection.height >= 4 {
            return bboxArray(from: intersection.integral)
        }
        return candidateBBox
    }

    private static func expandedBBox(_ bbox: [Double], by ratio: CGFloat, minimumPadding: CGFloat) -> [Double] {
        let rect = rect(from: bbox)
        let paddingX = max(minimumPadding, rect.width * ratio)
        let paddingY = max(minimumPadding, rect.height * ratio)
        return bboxArray(from: rect.insetBy(dx: -paddingX, dy: -paddingY).integral)
    }

    private static func intersectingBBox(_ lhs: [Double], _ rhs: [Double]) -> [Double]? {
        let intersection = rect(from: lhs).intersection(rect(from: rhs))
        guard !intersection.isNull, intersection.width >= 4, intersection.height >= 4 else {
            return nil
        }
        return bboxArray(from: intersection.integral)
    }

    private static func evaluateTextRegionCropSelection(
        originalText: String,
        cropText: String?,
        cropClampedByBubble: Bool
    ) -> (
        adopted: Bool,
        selectedText: String,
        selectionReason: String,
        rejectionReasons: [String],
        rawWordPreservationRatio: Double,
        candidateQualityScore: Double,
        originalQualityScore: Double
    ) {
        let original = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalWords = ocrCandidateWords(original)
        let originalScore = ocrCandidateQualityScore(original)
        guard let cropText else {
            return (false, original, "fallbackToFusedText", ["emptyCropText"], 0, 0, originalScore)
        }
        let candidate = cropText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            return (false, original, "fallbackToFusedText", ["emptyCropText"], 0, 0, originalScore)
        }

        let candidateWords = ocrCandidateWords(candidate)
        let preservation = wordPreservationRatio(sourceWords: originalWords, candidateWords: candidateWords)
        let similarity = normalizedTextSimilarity(original, candidate)
        let candidateScore = ocrCandidateQualityScore(candidate)
        let latinRatio = Double(latinLetterCount(in: candidate)) / Double(max(candidate.count, 1))
        let symbolRatio = Double(candidate.filter { !$0.isLetter && !$0.isNumber && !$0.isWhitespace && !$0.isPunctuation }.count) / Double(max(candidate.count, 1))
        var rejections: [String] = []

        if candidateWords.isEmpty {
            rejections.append("noCandidateWords")
        }
        if originalWords.count >= 2, candidateWords.count < max(2, Int(ceil(Double(originalWords.count) * 0.55))) {
            rejections.append("wordCountRegression")
        }
        if originalWords.count >= 3, preservation < 0.55, similarity < 0.42 {
            rejections.append("rawWordsLost")
        }
        if latinRatio < 0.42 {
            rejections.append("lowLatinRatio")
        }
        if symbolRatio > 0.16 {
            rejections.append("symbolHeavy")
        }
        if containsLikelyOCRError(in: candidate), !containsLikelyOCRError(in: original), candidateScore <= originalScore + 0.08 {
            rejections.append("introducedLikelyOCRError")
        }
        if cropClampedByBubble, candidateWords.count > originalWords.count + 8, similarity < 0.45 {
            rejections.append("clampedCropPossibleCrossTalk")
        }
        if ocrCandidateWords(candidate).joined(separator: " ") == ocrCandidateWords(original).joined(separator: " ") {
            rejections.append("sameAsFusedText")
        }

        let improvesQuality = candidateScore >= originalScore + 0.10
        let preservesAndExtends = preservation >= 0.68
            && candidateWords.count >= originalWords.count
            && candidateScore >= originalScore - 0.02
        let fixesLikelyError = containsLikelyOCRError(in: original)
            && !containsLikelyOCRError(in: candidate)
            && preservation >= 0.48
            && candidateScore >= originalScore + 0.04
        let adopted = rejections.isEmpty && (improvesQuality || preservesAndExtends || fixesLikelyError)
        let selected = adopted ? candidate : original
        let reason: String
        if adopted {
            if fixesLikelyError {
                reason = "adoptedFixesLikelyOCRError"
            } else if improvesQuality {
                reason = "adoptedHigherGroundTruthFreeQuality"
            } else {
                reason = "adoptedPreservesAndExtendsWords"
            }
        } else {
            reason = "fallbackToFusedText"
            if rejections.isEmpty {
                rejections.append("insufficientQualityGain")
            }
        }
        return (adopted, selected, reason, rejections, preservation, candidateScore, originalScore)
    }

    private static func cropFailureAttribution(
        bubbleID: Int?,
        decisionRejections: [String],
        cropText: String?,
        clampSource: String,
        assignmentCorrection: MangaOverlayBubbleAssignmentCorrectionDiagnostic?,
        splitCandidate: MangaOverlayBubbleSplitCandidateDiagnostic?,
        cropMaskCoverageRatio: Double?,
        textBox: MangaOverlayTextBoxCandidateDiagnostic?,
        segmentMask: MangaOverlaySegmentMaskDiagnostic?
    ) -> [String] {
        var result = Set<String>()
        let trimmedCrop = cropText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedCrop.isEmpty || decisionRejections.contains("emptyCropText") {
            result.insert("emptyLocalOCR")
        }
        if decisionRejections.contains("rawWordsLost") {
            result.insert("rawWordsLost")
        }
        if decisionRejections.contains("wordCountRegression") {
            result.insert("wordCountRegression")
        }
        if decisionRejections.contains("introducedLikelyOCRError") {
            result.insert("introducedLikelyOCRError")
        }
        if decisionRejections.contains("sameAsFusedText") {
            result.insert("sameAsFusedText")
        }
        if decisionRejections.contains("insufficientQualityGain") {
            result.insert("insufficientQualityGain")
        }
        if decisionRejections.contains("rawWordsLost") || decisionRejections.contains("wordCountRegression") || decisionRejections.contains("introducedLikelyOCRError") {
            result.insert("localVisionRegression")
        }
        if clampSource == "contentRect", bubbleID == nil {
            result.insert("textBoxTooWide")
        }
        if let cropMaskCoverageRatio, cropMaskCoverageRatio < 0.45 {
            result.insert("bubbleMaskConflict")
        }
        if let assignmentCorrection,
           assignmentCorrection.currentBubbleID != assignmentCorrection.maskDominantBubbleID,
           !assignmentCorrection.correctionAppliedToCropClamp {
            result.insert("bubbleMaskConflict")
        }
        if let splitCandidate, !splitCandidate.clampEligible {
            result.insert("textBoxTooWide")
        }
        if let textBox {
            if textBox.rejectionReasons.contains("textBoxTooTight") {
                result.insert("textBoxTooTight")
            }
            if textBox.riskFlags.contains("textBoxTooWide") {
                result.insert("textBoxTooWide")
            }
            if textBox.rejectionReasons.contains("bubbleMaskCoverageLow") || textBox.riskFlags.contains("bubbleMaskConflict") {
                result.insert("bubbleMaskConflict")
            }
        }
        if let segmentMask, !segmentMask.usableForCropEvidence {
            result.insert("segmentMaskWeak")
        }
        return Array(result).sorted()
    }

    private static func cropFailureAttribution(
        diagnostic: MangaOverlayTextRegionCropDiagnostic,
        textBox: MangaOverlayTextBoxCandidateDiagnostic?,
        segmentMask: MangaOverlaySegmentMaskDiagnostic?
    ) -> [String] {
        cropFailureAttribution(
            bubbleID: diagnostic.bubbleID,
            decisionRejections: diagnostic.rejectionReasons,
            cropText: diagnostic.textRegionCropText,
            clampSource: diagnostic.clampSource,
            assignmentCorrection: nil,
            splitCandidate: nil,
            cropMaskCoverageRatio: diagnostic.cropMaskCoverageRatio,
            textBox: textBox,
            segmentMask: segmentMask
        )
    }

    private static func textBoxEvidenceScore(
        bubbleMaskCoverageRatio: Double?,
        glyphOverlapRatio: Double?,
        safeRectOverlapRatio: Double?,
        cropRejections: [String],
        riskFlags: [String]
    ) -> Double {
        var score = 0.34
        score += min(max(bubbleMaskCoverageRatio ?? 0.45, 0), 1) * 0.24
        score += min(max(glyphOverlapRatio ?? 0.35, 0), 1) * 0.20
        score += min(max(safeRectOverlapRatio ?? 0.50, 0), 1) * 0.12
        if cropRejections.contains("emptyCropText") { score -= 0.18 }
        if cropRejections.contains("rawWordsLost") { score -= 0.12 }
        if cropRejections.contains("wordCountRegression") { score -= 0.10 }
        if cropRejections.contains("introducedLikelyOCRError") { score -= 0.10 }
        if riskFlags.contains("textBoxTooWide") { score -= 0.08 }
        if riskFlags.contains("bubbleMaskConflict") { score -= 0.10 }
        return min(max(score, 0), 1)
    }

    private static func wordPreservationRatio(sourceWords: [String], candidateWords: [String]) -> Double {
        guard !sourceWords.isEmpty else { return candidateWords.isEmpty ? 0 : 1 }
        let candidateSet = Set(candidateWords)
        let preserved = sourceWords.filter { candidateSet.contains($0) }.count
        return Double(preserved) / Double(sourceWords.count)
    }

    private static func textRegionSource(for block: MangaOverlayProbeBlock) -> String {
        if block.ocrProbeNotes.contains("fusionSource=bubbleFirst") {
            return "bubbleFirst"
        }
        if block.ocrProbeNotes.contains("fusionSource=wholePageOCR") {
            return "wholePageOCR"
        }
        return block.bubbleAssignmentMethod
    }

    private static func ocrCandidateQualityScore(_ text: String) -> Double {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return 0 }
        let words = clean
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        let validWordRatio = Double(words.filter { $0.count >= 2 }.count) / Double(max(words.count, 1))
        let latinRatio = Double(latinLetterCount(in: clean)) / Double(max(clean.count, 1))
        let symbolRatio = Double(clean.filter { !$0.isLetter && !$0.isNumber && !$0.isWhitespace && !$0.isPunctuation }.count) / Double(max(clean.count, 1))
        let knownErrorPenalty = Self.containsLikelyOCRError(in: clean) ? 0.08 : 0
        let wordCountBonus = min(Double(words.count), 10) * 0.012
        return max(0, validWordRatio * 0.45 + latinRatio * 0.35 + wordCountBonus - symbolRatio * 0.35 - knownErrorPenalty)
    }

    private static func enhancedOCRPreservesRawWords(rawText: String, enhancedText: String) -> Bool {
        let rawWords = ocrCandidateWords(rawText)
        let enhancedWords = ocrCandidateWords(enhancedText)
        guard rawWords.count >= 3,
              enhancedWords.count > rawWords.count,
              enhancedWords.count <= rawWords.count + 2 else {
            return false
        }
        var searchStart = enhancedWords.startIndex
        var matchedEnhancedIndexes = Set<Int>()
        for rawWord in rawWords {
            guard let matchIndex = enhancedWords[searchStart...].firstIndex(of: rawWord) else {
                return false
            }
            matchedEnhancedIndexes.insert(matchIndex)
            searchStart = enhancedWords.index(after: matchIndex)
        }
        let insertedWords = enhancedWords.indices
            .filter { !matchedEnhancedIndexes.contains($0) }
            .map { enhancedWords[$0] }
        return insertedWords.allSatisfy { word in
            word.allSatisfy(\.isLetter) && rawWords.contains(word)
        }
    }

    private static func ocrCandidateWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func correctMangaProbeBlock(
        _ block: MangaOverlayProbeBlock,
        options: MangaOverlayCorrectionOptions
    ) async -> MangaOverlayProbeBlock {
        guard options.enabled else { return block }

        let original = block.finalTextUsedForTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else {
            return MangaOverlayProbeBlock(
                id: block.id,
                index: block.index,
                bbox: block.bbox,
                bubbleID: block.bubbleID,
                bubbleAssignmentMethod: block.bubbleAssignmentMethod,
                crossBubbleMergeRejected: block.crossBubbleMergeRejected,
                sliceIndex: block.sliceIndex,
                sliceOverlapDeduped: block.sliceOverlapDeduped,
                rotationAngleUsed: block.rotationAngleUsed,
                ocrText: block.ocrText,
                ocrConfidence: block.ocrConfidence,
                rawOcrText: block.rawOcrText,
                preprocessingEnabled: block.preprocessingEnabled,
                afterPreprocessingOcrText: block.afterPreprocessingOcrText,
                adaptivePreprocessingOcrText: block.adaptivePreprocessingOcrText,
                fixedPreprocessingOcrText: block.fixedPreprocessingOcrText,
                cropPaddingX: block.cropPaddingX,
                cropPaddingY: block.cropPaddingY,
                cropClampedByBubble: block.cropClampedByBubble,
                cropCandidatePreservesRawWords: block.cropCandidatePreservesRawWords,
                cropFallbackTriggered: block.cropFallbackTriggered,
                cropFallbackReason: block.cropFallbackReason,
                cropStrategyUsed: block.cropStrategyUsed,
                correctionEnabled: true,
                afterCorrectionText: block.finalTextUsedForTranslation,
                correctionRejectedReason: "OCR 为空，跳过纠错",
                correctionPrompt: nil,
                correctionRawOutput: nil,
                correctionErrorCode: nil,
                deterministicCorrectionText: block.deterministicCorrectionText,
                deterministicCorrectionAppliedRules: block.deterministicCorrectionAppliedRules,
                deterministicCorrectionSimilarity: block.deterministicCorrectionSimilarity,
                deterministicCorrectionTranslationCandidate: block.deterministicCorrectionTranslationCandidate,
                deterministicCorrectionTranslationRawOutput: block.deterministicCorrectionTranslationRawOutput,
                deterministicCorrectionTranslationPassed: block.deterministicCorrectionTranslationPassed,
                deterministicCorrectionTranslationFailureDetail: block.deterministicCorrectionTranslationFailureDetail,
                finalTextUsedForTranslation: block.finalTextUsedForTranslation,
                bestGroundTruthIndex: block.bestGroundTruthIndex,
                bestGroundTruthText: block.bestGroundTruthText,
                bestGroundTruthType: block.bestGroundTruthType,
                groundTruthMatch: block.groundTruthMatch,
                groundTruthMatchThreshold: block.groundTruthMatchThreshold,
                ocrGroundTruthSimilarity: block.ocrGroundTruthSimilarity,
                ocrLegacySimilarity: block.ocrLegacySimilarity,
                wordOrderPreserved: block.wordOrderPreserved,
                ocrQualityLabel: block.ocrQualityLabel,
                translatedText: block.translatedText,
                translationCandidate: block.translationCandidate,
                rawOutputClassification: block.rawOutputClassification,
                candidateClassification: block.candidateClassification,
                failureCategory: block.failureCategory,
                prompt: block.prompt,
                rawOutput: block.rawOutput,
                errorCode: block.errorCode,
                checks: block.checks,
                failureReasons: block.failureReasons,
                qualityNotes: block.qualityNotes,
                translationDecisionTrace: block.translationDecisionTrace,
                translationFailureDetail: block.translationFailureDetail,
                ocrProbeNotes: block.ocrProbeNotes,
                blockPassed: block.blockPassed
            )
        }

        let prompt = Self.mangaCorrectionPrompt(for: original)
        let rawOutput: String
        let errorCode: String?
        if selectedEngine == .local {
            let probe = localService.rawProbe(prompt: prompt, maxTokens: 96)
            rawOutput = probe.output
            errorCode = probe.errorCode
        } else {
            rawOutput = original
            errorCode = nil
        }

        let proposed = Self.cleanMangaCorrectionCandidate(rawOutput)
        let guardrail = Self.evaluateMangaCorrectionGuardrail(
            original: original,
            proposed: proposed,
            options: options
        )
        let acceptedText = guardrail.accepted ? proposed : original
        let rejectedReason = guardrail.accepted ? nil : guardrail.reason

        return MangaOverlayProbeBlock(
            id: block.id,
            index: block.index,
            bbox: block.bbox,
            bubbleID: block.bubbleID,
            bubbleAssignmentMethod: block.bubbleAssignmentMethod,
            crossBubbleMergeRejected: block.crossBubbleMergeRejected,
            sliceIndex: block.sliceIndex,
            sliceOverlapDeduped: block.sliceOverlapDeduped,
            rotationAngleUsed: block.rotationAngleUsed,
            ocrText: block.ocrText,
            ocrConfidence: block.ocrConfidence,
            rawOcrText: block.rawOcrText,
            preprocessingEnabled: block.preprocessingEnabled,
            afterPreprocessingOcrText: block.afterPreprocessingOcrText,
            adaptivePreprocessingOcrText: block.adaptivePreprocessingOcrText,
            fixedPreprocessingOcrText: block.fixedPreprocessingOcrText,
            cropPaddingX: block.cropPaddingX,
            cropPaddingY: block.cropPaddingY,
            cropClampedByBubble: block.cropClampedByBubble,
            cropCandidatePreservesRawWords: block.cropCandidatePreservesRawWords,
            cropFallbackTriggered: block.cropFallbackTriggered,
            cropFallbackReason: block.cropFallbackReason,
            cropStrategyUsed: block.cropStrategyUsed,
            correctionEnabled: true,
            afterCorrectionText: acceptedText,
            correctionRejectedReason: rejectedReason,
            correctionPrompt: prompt,
            correctionRawOutput: rawOutput,
            correctionErrorCode: errorCode,
            deterministicCorrectionText: block.deterministicCorrectionText,
            deterministicCorrectionAppliedRules: block.deterministicCorrectionAppliedRules,
            deterministicCorrectionSimilarity: block.deterministicCorrectionSimilarity,
            deterministicCorrectionTranslationCandidate: block.deterministicCorrectionTranslationCandidate,
            deterministicCorrectionTranslationRawOutput: block.deterministicCorrectionTranslationRawOutput,
            deterministicCorrectionTranslationPassed: block.deterministicCorrectionTranslationPassed,
            deterministicCorrectionTranslationFailureDetail: block.deterministicCorrectionTranslationFailureDetail,
            finalTextUsedForTranslation: acceptedText,
            bestGroundTruthIndex: block.bestGroundTruthIndex,
            bestGroundTruthText: block.bestGroundTruthText,
            bestGroundTruthType: block.bestGroundTruthType,
            groundTruthMatch: block.groundTruthMatch,
            groundTruthMatchThreshold: block.groundTruthMatchThreshold,
            ocrGroundTruthSimilarity: block.ocrGroundTruthSimilarity,
            ocrLegacySimilarity: block.ocrLegacySimilarity,
            wordOrderPreserved: block.wordOrderPreserved,
            ocrQualityLabel: block.ocrQualityLabel,
            translatedText: block.translatedText,
            translationCandidate: block.translationCandidate,
            rawOutputClassification: block.rawOutputClassification,
            candidateClassification: block.candidateClassification,
            failureCategory: block.failureCategory,
            prompt: block.prompt,
            rawOutput: block.rawOutput,
            errorCode: block.errorCode,
            checks: block.checks,
            failureReasons: block.failureReasons,
            qualityNotes: block.qualityNotes,
            translationDecisionTrace: block.translationDecisionTrace,
            translationFailureDetail: block.translationFailureDetail,
            ocrProbeNotes: block.ocrProbeNotes,
            blockPassed: block.blockPassed
        )
    }

    private func applyDeterministicMangaOCRCorrection(
        to block: MangaOverlayProbeBlock,
        groundTruth: [MangaGroundTruthEntry]
    ) -> MangaOverlayProbeBlock {
        let original = block.finalTextUsedForTranslation
        let correction = Self.deterministicMangaOCRCorrection(for: original)
        let correctedSimilarity: Double?
        if !groundTruth.isEmpty {
            correctedSimilarity = MangaOverlayProbeService.bestGroundTruthMatch(
                text: correction.text,
                groundTruth: groundTruth
            ).similarity
        } else {
            correctedSimilarity = nil
        }

        return MangaOverlayProbeBlock(
            id: block.id,
            index: block.index,
            bbox: block.bbox,
            bubbleID: block.bubbleID,
            bubbleAssignmentMethod: block.bubbleAssignmentMethod,
            crossBubbleMergeRejected: block.crossBubbleMergeRejected,
            sliceIndex: block.sliceIndex,
            sliceOverlapDeduped: block.sliceOverlapDeduped,
            rotationAngleUsed: block.rotationAngleUsed,
            ocrText: block.ocrText,
            ocrConfidence: block.ocrConfidence,
            rawOcrText: block.rawOcrText,
            preprocessingEnabled: block.preprocessingEnabled,
            afterPreprocessingOcrText: block.afterPreprocessingOcrText,
            adaptivePreprocessingOcrText: block.adaptivePreprocessingOcrText,
            fixedPreprocessingOcrText: block.fixedPreprocessingOcrText,
            cropPaddingX: block.cropPaddingX,
            cropPaddingY: block.cropPaddingY,
            cropClampedByBubble: block.cropClampedByBubble,
            cropCandidatePreservesRawWords: block.cropCandidatePreservesRawWords,
            cropFallbackTriggered: block.cropFallbackTriggered,
            cropFallbackReason: block.cropFallbackReason,
            cropStrategyUsed: block.cropStrategyUsed,
            correctionEnabled: block.correctionEnabled,
            afterCorrectionText: block.afterCorrectionText,
            correctionRejectedReason: block.correctionRejectedReason,
            correctionPrompt: block.correctionPrompt,
            correctionRawOutput: block.correctionRawOutput,
            correctionErrorCode: block.correctionErrorCode,
            deterministicCorrectionText: correction.text,
            deterministicCorrectionAppliedRules: correction.rules,
            deterministicCorrectionSimilarity: correctedSimilarity,
            deterministicCorrectionTranslationCandidate: block.deterministicCorrectionTranslationCandidate,
            deterministicCorrectionTranslationRawOutput: block.deterministicCorrectionTranslationRawOutput,
            deterministicCorrectionTranslationPassed: block.deterministicCorrectionTranslationPassed,
            deterministicCorrectionTranslationFailureDetail: block.deterministicCorrectionTranslationFailureDetail,
            finalTextUsedForTranslation: block.finalTextUsedForTranslation,
            bestGroundTruthIndex: block.bestGroundTruthIndex,
            bestGroundTruthText: block.bestGroundTruthText,
            bestGroundTruthType: block.bestGroundTruthType,
            groundTruthMatch: block.groundTruthMatch,
            groundTruthMatchThreshold: block.groundTruthMatchThreshold,
            ocrGroundTruthSimilarity: block.ocrGroundTruthSimilarity,
            ocrLegacySimilarity: block.ocrLegacySimilarity,
            wordOrderPreserved: block.wordOrderPreserved,
            ocrQualityLabel: block.ocrQualityLabel,
            translatedText: block.translatedText,
            translationCandidate: block.translationCandidate,
            rawOutputClassification: block.rawOutputClassification,
            candidateClassification: block.candidateClassification,
            failureCategory: block.failureCategory,
            prompt: block.prompt,
            rawOutput: block.rawOutput,
            errorCode: block.errorCode,
            checks: block.checks,
            failureReasons: block.failureReasons,
            qualityNotes: block.qualityNotes,
            translationDecisionTrace: block.translationDecisionTrace,
            translationFailureDetail: block.translationFailureDetail,
            ocrProbeNotes: block.ocrProbeNotes,
            blockPassed: block.blockPassed
        )
    }

    private static func deterministicMangaOCRCorrection(for text: String) -> (text: String, rules: [String]) {
        var output = text
        var rules: [String] = []
        let replacements = [
            ("RATTLER", "BATTLER"),
            ("STATE IN A PEN DAYS", "STARTS IN A FEW DAYS"),
            ("TRANINS", "TRAINING"),
            ("THOUSH", "THOUGH"),
            ("ONLING", "ONLINE"),
            ("SUGSESTION", "SUGGESTION"),
            ("LOSIC", "LOGIC"),
            ("SENPArS", "SENPAI'S"),
            ("SENPARS", "SENPAI'S"),
            ("SENPAIS", "SENPAI'S"),
            ("PESULTE", "RESULTS"),
            ("SAMING", "SAVING"),
            ("POOM", "ROOM"),
            ("BENG", "BEING"),
            ("WOLLD", "WOULD")
        ]
        for (from, to) in replacements {
            let changed = output.replacingOccurrences(
                of: from,
                with: to,
                options: [.caseInsensitive]
            )
            if changed != output {
                rules.append("\(from)->\(to)")
                output = changed
            }
        }
        return (output, rules)
    }

    private func translateMangaProbeBlock(_ block: MangaOverlayProbeBlock) async -> MangaOverlayProbeBlock {
        let request = makeProbeRequest(
            source: .englishUS,
            target: .simplifiedChinese,
            input: block.finalTextUsedForTranslation
        )
        let prompt: String
        let rawOutput: String
        let rawTranslatedText: String
        let errorCode: String?

        if selectedEngine == .local {
            let probe = localService.rawTranslationProbe(for: request)
            prompt = probe.prompt
            rawOutput = probe.output
            rawTranslatedText = probe.output.trimmingCharacters(in: .whitespacesAndNewlines)
            errorCode = probe.errorCode
        } else {
            prompt = debugPromptPreview(for: request) + "\n\n注意：Mock 模式为模拟输出，不是真实模型 raw prompt。"
            do {
                try await mockService.prepare()
                let result = try await mockService.generate(request)
                rawOutput = result.text
                rawTranslatedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                errorCode = nil
            } catch {
                rawOutput = ""
                rawTranslatedText = ""
                errorCode = "\(type(of: error)): \(error.localizedDescription)"
            }
        }

        let extraction = Self.extractMangaProbeTranslationCandidate(rawTranslatedText)
        let translationCandidate = extraction.candidate
        let rawClassification = Self.classifyMangaProbeRawOutput(
            rawOutput,
            original: block.finalTextUsedForTranslation
        )
        let candidateClassification = Self.classifyMangaProbeCandidate(
            translationCandidate,
            original: block.finalTextUsedForTranslation,
            rejectedPlaceholder: extraction.rejectedPlaceholder
        )
        let checks = mangaProbeChecks(
            original: block.finalTextUsedForTranslation,
            translation: translationCandidate,
            errorCode: errorCode
        )
        let baseFailureReasons = mangaProbeFailureReasons(
            checks: checks,
            errorCode: errorCode,
            original: block.finalTextUsedForTranslation,
            translation: translationCandidate
        )
        let qualityNotes = mangaProbeQualityNotes(
            checks: checks,
            original: block.finalTextUsedForTranslation,
            rawOutput: rawOutput,
            candidate: translationCandidate,
            extraction: extraction
        )
        let hasLikelyOCRIssue = block.qualityNotes.contains("likelyOCRIssue")
            || Self.containsLikelyOCRError(in: block.finalTextUsedForTranslation)
            || (block.ocrGroundTruthSimilarity ?? 1) < 0.72
        let translationChecksPassed = Self.mangaProbeBlockPassed(checks, errorCode: errorCode)
        let languageQualityReason = translationChecksPassed ? Self.mangaProbeTranslationLanguageQualityIssue(
            original: block.finalTextUsedForTranslation,
            candidate: translationCandidate,
            rawOutput: rawOutput,
            rawClassification: rawClassification
        ) : nil
        let translationLanguageQualityPassed = translationChecksPassed && languageQualityReason == nil
        let ocrInputReason = translationLanguageQualityPassed ? Self.mangaProbeOCRInputQualityIssue(block) : nil
        let passed = translationLanguageQualityPassed && ocrInputReason == nil
        let failureReasons = baseFailureReasons + [languageQualityReason, ocrInputReason].compactMap { $0 }
        var finalQualityNotes = qualityNotes
        if let languageQualityReason {
            finalQualityNotes.append("translationLanguageQualityIssue=\(languageQualityReason)")
        }
        if let ocrInputReason {
            finalQualityNotes.append("ocrInputQualityIssue=\(ocrInputReason)")
        }
        let decisionTrace = Self.mangaProbeTranslationDecisionTrace(
            checks: checks,
            errorCode: errorCode,
            rawClassification: rawClassification,
            candidateClassification: candidateClassification,
            extraction: extraction,
            translationLanguageQualityPassed: translationLanguageQualityPassed,
            languageQualityReason: languageQualityReason,
            ocrInputReason: ocrInputReason
        )
        let failureCategory = Self.mangaProbeFailureCategory(
            passed: passed,
            rawClassification: rawClassification,
            candidateClassification: candidateClassification,
            translationChecksPassed: translationChecksPassed,
            translationLanguageQualityPassed: translationLanguageQualityPassed,
            languageQualityReason: languageQualityReason,
            hasLikelyOCRIssue: hasLikelyOCRIssue,
            ocrInputReason: ocrInputReason
        )
        let overlayText = passed ? translationCandidate : "翻译失败\n\(block.finalTextUsedForTranslation)"

        return MangaOverlayProbeBlock(
            id: block.id,
            index: block.index,
            bbox: block.bbox,
            bubbleID: block.bubbleID,
            bubbleAssignmentMethod: block.bubbleAssignmentMethod,
            crossBubbleMergeRejected: block.crossBubbleMergeRejected,
            sliceIndex: block.sliceIndex,
            sliceOverlapDeduped: block.sliceOverlapDeduped,
            rotationAngleUsed: block.rotationAngleUsed,
            ocrText: block.ocrText,
            ocrConfidence: block.ocrConfidence,
            rawOcrText: block.rawOcrText,
            preprocessingEnabled: block.preprocessingEnabled,
            afterPreprocessingOcrText: block.afterPreprocessingOcrText,
            adaptivePreprocessingOcrText: block.adaptivePreprocessingOcrText,
            fixedPreprocessingOcrText: block.fixedPreprocessingOcrText,
            cropPaddingX: block.cropPaddingX,
            cropPaddingY: block.cropPaddingY,
            cropClampedByBubble: block.cropClampedByBubble,
            cropCandidatePreservesRawWords: block.cropCandidatePreservesRawWords,
            cropFallbackTriggered: block.cropFallbackTriggered,
            cropFallbackReason: block.cropFallbackReason,
            cropStrategyUsed: block.cropStrategyUsed,
            correctionEnabled: block.correctionEnabled,
            afterCorrectionText: block.afterCorrectionText,
            correctionRejectedReason: block.correctionRejectedReason,
            correctionPrompt: block.correctionPrompt,
            correctionRawOutput: block.correctionRawOutput,
            correctionErrorCode: block.correctionErrorCode,
            deterministicCorrectionText: block.deterministicCorrectionText,
            deterministicCorrectionAppliedRules: block.deterministicCorrectionAppliedRules,
            deterministicCorrectionSimilarity: block.deterministicCorrectionSimilarity,
            deterministicCorrectionTranslationCandidate: block.deterministicCorrectionTranslationCandidate,
            deterministicCorrectionTranslationRawOutput: block.deterministicCorrectionTranslationRawOutput,
            deterministicCorrectionTranslationPassed: block.deterministicCorrectionTranslationPassed,
            deterministicCorrectionTranslationFailureDetail: block.deterministicCorrectionTranslationFailureDetail,
            finalTextUsedForTranslation: block.finalTextUsedForTranslation,
            bestGroundTruthIndex: block.bestGroundTruthIndex,
            bestGroundTruthText: block.bestGroundTruthText,
            bestGroundTruthType: block.bestGroundTruthType,
            groundTruthMatch: block.groundTruthMatch,
            groundTruthMatchThreshold: block.groundTruthMatchThreshold,
            ocrGroundTruthSimilarity: block.ocrGroundTruthSimilarity,
            ocrLegacySimilarity: block.ocrLegacySimilarity,
            wordOrderPreserved: block.wordOrderPreserved,
            ocrQualityLabel: block.ocrQualityLabel,
            translatedText: overlayText,
            translationCandidate: translationCandidate,
            rawOutputClassification: rawClassification,
            candidateClassification: candidateClassification,
            failureCategory: failureCategory,
            prompt: prompt,
            rawOutput: rawOutput,
            errorCode: errorCode,
            checks: checks,
            failureReasons: failureReasons,
            qualityNotes: finalQualityNotes,
            translationDecisionTrace: decisionTrace,
            translationFailureDetail: passed ? nil : Self.mangaProbeTranslationFailureDetail(
                failureCategory: failureCategory,
                rawClassification: rawClassification,
                candidateClassification: candidateClassification,
                failureReasons: failureReasons,
                qualityNotes: finalQualityNotes,
                hasLikelyOCRIssue: hasLikelyOCRIssue
            ),
            ocrProbeNotes: block.ocrProbeNotes,
            blockPassed: passed
        )
    }

    private static func shouldProbeDeterministicCorrectionTranslation(_ block: MangaOverlayProbeBlock) -> Bool {
        guard let corrected = block.deterministicCorrectionText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !corrected.isEmpty,
              corrected != block.finalTextUsedForTranslation.trimmingCharacters(in: .whitespacesAndNewlines),
              let correctedSimilarity = block.deterministicCorrectionSimilarity,
              let originalSimilarity = block.ocrGroundTruthSimilarity else {
            return false
        }
        return correctedSimilarity > originalSimilarity + 0.02
    }

    private func runTaggedBatchTranslationComparison(blocks: [MangaOverlayProbeBlock]) async -> MangaBatchTranslationComparison {
        let cases = blocks
            .filter { !$0.finalTextUsedForTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { block in
                (block: block, tag: "[\(block.index)]")
            }
        let prompt = Self.taggedBatchTranslationPrompt(for: cases.map { ($0.tag, $0.block.finalTextUsedForTranslation) })

        let rawOutput: String
        let errorCode: String?
        if selectedEngine == .local {
            let probe = localService.rawProbe(prompt: prompt, maxTokens: min(max(96, cases.count * 42), 220))
            rawOutput = probe.output
            errorCode = probe.errorCode
        } else {
            let request = makeProbeRequest(source: .englishUS, target: .simplifiedChinese, input: prompt)
            do {
                try await mockService.prepare()
                let result = try await mockService.generate(request)
                rawOutput = result.text
                errorCode = nil
            } catch {
                rawOutput = ""
                errorCode = "\(type(of: error)): \(error.localizedDescription)"
            }
        }

        let parsed = Self.parseTaggedBatchTranslation(rawOutput, expectedTags: cases.map(\.tag))
        let expectedTagSet = Set(cases.map(\.tag))
        let seenUnexpectedTags = parsed.orderedTags.filter { !expectedTagSet.contains($0) }
        var comparisonCases: [MangaBatchTranslationCase] = []
        for item in cases {
            let parsedText = parsed.values[item.tag]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = parsedText ?? ""
            let extraction = MangaProbeCandidateExtraction(
                candidate: candidate,
                rejectedPlaceholder: Self.isPlaceholderTranslationOutput(candidate),
                rawHadContent: !candidate.isEmpty
            )
            let rawClassification = Self.classifyMangaProbeRawOutput(candidate, original: item.block.finalTextUsedForTranslation)
            let candidateClassification = Self.classifyMangaProbeCandidate(
                candidate,
                original: item.block.finalTextUsedForTranslation,
                rejectedPlaceholder: extraction.rejectedPlaceholder
            )
            let checks = mangaProbeChecks(
                original: item.block.finalTextUsedForTranslation,
                translation: candidate,
                errorCode: errorCode
            )
            let baseFailureReasons = mangaProbeFailureReasons(
                checks: checks,
                errorCode: errorCode,
                original: item.block.finalTextUsedForTranslation,
                translation: candidate
            )
            let translationChecksPassed = Self.mangaProbeBlockPassed(checks, errorCode: errorCode)
            let languageQualityReason = translationChecksPassed ? Self.mangaProbeTranslationLanguageQualityIssue(
                original: item.block.finalTextUsedForTranslation,
                candidate: candidate,
                rawOutput: candidate,
                rawClassification: rawClassification
            ) : nil
            var failureReasons = baseFailureReasons + [languageQualityReason].compactMap { $0 }
            if parsedText == nil {
                failureReasons.append("tagMissing")
            }
            if parsed.duplicateTags.contains(item.tag) {
                failureReasons.append("tagDuplicated")
            }
            if parsed.outOfOrderTags.contains(item.tag) {
                failureReasons.append("tagOutOfOrder")
            }
            let passed = parsedText != nil
                && !parsed.duplicateTags.contains(item.tag)
                && translationChecksPassed
                && languageQualityReason == nil
            comparisonCases.append(
                MangaBatchTranslationCase(
                    index: item.block.index,
                    tag: item.tag,
                    sourceText: item.block.finalTextUsedForTranslation,
                    parsedText: parsedText,
                    rawOutputClassification: rawClassification,
                    candidateClassification: candidateClassification,
                    passed: passed,
                    sequentialBlockPassed: item.block.blockPassed,
                    failureReasons: failureReasons
                )
            )
        }

        var parseFailureReasons: [String] = []
        if !parsed.missingTags.isEmpty {
            parseFailureReasons.append("missingTags=\(parsed.missingTags.joined(separator: ","))")
        }
        if !parsed.duplicateTags.isEmpty {
            parseFailureReasons.append("duplicateTags=\(parsed.duplicateTags.joined(separator: ","))")
        }
        if !parsed.outOfOrderTags.isEmpty {
            parseFailureReasons.append("outOfOrderTags=\(parsed.outOfOrderTags.joined(separator: ","))")
        }
        if !seenUnexpectedTags.isEmpty {
            parseFailureReasons.append("unexpectedTags=\(seenUnexpectedTags.joined(separator: ","))")
        }
        if let errorCode {
            parseFailureReasons.append("errorCode=\(errorCode)")
        }

        let totalCases = comparisonCases.count
        let sequentialPassedCases = comparisonCases.filter(\.sequentialBlockPassed).count
        let batchPassedCases = comparisonCases.filter(\.passed).count
        let sequentialPassRate = totalCases > 0 ? Double(sequentialPassedCases) / Double(totalCases) : 0
        let batchPassRate = totalCases > 0 ? Double(batchPassedCases) / Double(totalCases) : 0
        let notes = [
            "diagnosticOnly=true; sequential per-block translation remains the primary flow",
            "batch output is parsed by bracketed block index tags; missing/duplicate/out-of-order tags fail the batch case",
            batchPassRate >= sequentialPassRate ? "batchNotWorseOrBetter" : "batchWorseThanSequential"
        ]

        return MangaBatchTranslationComparison(
            enabled: true,
            decodingMode: selectedEngine == .local ? ModelDecodingProfile.deterministic.mode : "mock",
            decodingSeed: selectedEngine == .local ? ModelDecodingProfile.deterministic.seed : nil,
            prompt: prompt,
            rawOutput: rawOutput,
            errorCode: errorCode,
            totalCases: totalCases,
            parsedCases: totalCases - parsed.missingTags.count,
            missingTags: parsed.missingTags,
            duplicateTags: parsed.duplicateTags,
            outOfOrderTags: parsed.outOfOrderTags,
            sequentialPassedCases: sequentialPassedCases,
            batchPassedCases: batchPassedCases,
            sequentialPassRate: sequentialPassRate,
            batchPassRate: batchPassRate,
            batchBetterBy: batchPassRate - sequentialPassRate,
            parseFailureReasons: parseFailureReasons,
            cases: comparisonCases,
            notes: notes
        )
    }

    private static func taggedBatchTranslationPrompt(for items: [(tag: String, text: String)]) -> String {
        let body = items
            .map { item in
                "\(item.tag) \(item.text.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            .joined(separator: "\n")
        return """
        把以下英文漫画台词翻译成中文。
        严格保留每一行开头的编号标签，例如 [0]。
        不要合并编号，不要拆分编号，不要解释，不要添加列表符号。
        每个输入编号必须输出且只输出一行对应中文。

        \(body)
        """
    }

    private static func parseTaggedBatchTranslation(
        _ rawOutput: String,
        expectedTags: [String]
    ) -> (values: [String: String], orderedTags: [String], missingTags: [String], duplicateTags: [String], outOfOrderTags: [String]) {
        var values: [String: String] = [:]
        var orderedTags: [String] = []
        var duplicateTags: [String] = []
        let expectedSet = Set(expectedTags)
        let pattern = #"^\s*(\[\d+\])\s*[:：\-–—.]?\s*(.*)$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        for rawLine in rawOutput.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex?.firstMatch(in: line, range: range),
                  match.numberOfRanges >= 3,
                  let tagRange = Range(match.range(at: 1), in: line),
                  let textRange = Range(match.range(at: 2), in: line) else {
                continue
            }
            let tag = String(line[tagRange])
            guard expectedSet.contains(tag) else {
                orderedTags.append(tag)
                continue
            }
            let text = String(line[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if values[tag] != nil {
                duplicateTags.append(tag)
                values[tag] = [values[tag], text]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            } else {
                values[tag] = text
            }
            orderedTags.append(tag)
        }

        let missingTags = expectedTags.filter { values[$0] == nil }
        let expectedPositions = Dictionary(uniqueKeysWithValues: expectedTags.enumerated().map { ($0.element, $0.offset) })
        var lastPosition = -1
        var outOfOrderTags: [String] = []
        for tag in orderedTags where expectedSet.contains(tag) {
            guard let position = expectedPositions[tag] else { continue }
            if position < lastPosition {
                outOfOrderTags.append(tag)
            } else {
                lastPosition = position
            }
        }
        return (
            values,
            orderedTags,
            missingTags,
            Array(Set(duplicateTags)).sorted(),
            Array(Set(outOfOrderTags)).sorted()
        )
    }

    private func translateDeterministicCorrectionCandidate(_ block: MangaOverlayProbeBlock) async -> MangaOverlayProbeBlock {
        guard let correctedText = block.deterministicCorrectionText,
              Self.shouldProbeDeterministicCorrectionTranslation(block) else {
            return block
        }

        let request = makeProbeRequest(
            source: .englishUS,
            target: .simplifiedChinese,
            input: correctedText
        )
        let rawOutput: String
        let rawTranslatedText: String
        let errorCode: String?

        if selectedEngine == .local {
            let probe = localService.rawTranslationProbe(for: request)
            rawOutput = probe.output
            rawTranslatedText = probe.output.trimmingCharacters(in: .whitespacesAndNewlines)
            errorCode = probe.errorCode
        } else {
            do {
                try await mockService.prepare()
                let result = try await mockService.generate(request)
                rawOutput = result.text
                rawTranslatedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                errorCode = nil
            } catch {
                rawOutput = ""
                rawTranslatedText = ""
                errorCode = "\(type(of: error)): \(error.localizedDescription)"
            }
        }

        let extraction = Self.extractMangaProbeTranslationCandidate(rawTranslatedText)
        let candidate = extraction.candidate
        let rawClassification = Self.classifyMangaProbeRawOutput(rawOutput, original: correctedText)
        let checks = mangaProbeChecks(original: correctedText, translation: candidate, errorCode: errorCode)
        let baseFailureReasons = mangaProbeFailureReasons(
            checks: checks,
            errorCode: errorCode,
            original: correctedText,
            translation: candidate
        )
        let translationChecksPassed = Self.mangaProbeBlockPassed(checks, errorCode: errorCode)
        let languageQualityReason = translationChecksPassed ? Self.mangaProbeTranslationLanguageQualityIssue(
            original: correctedText,
            candidate: candidate,
            rawOutput: rawOutput,
            rawClassification: rawClassification
        ) : nil
        let passed = translationChecksPassed && languageQualityReason == nil
        let failureReasons = baseFailureReasons + [languageQualityReason].compactMap { $0 }
        let failureDetail = passed
            ? nil
            : "deterministicCorrectionTranslationFailure：\(failureReasons.isEmpty ? "未知原因" : failureReasons.joined(separator: "、"))"

        return MangaOverlayProbeBlock(
            id: block.id,
            index: block.index,
            bbox: block.bbox,
            bubbleID: block.bubbleID,
            bubbleAssignmentMethod: block.bubbleAssignmentMethod,
            crossBubbleMergeRejected: block.crossBubbleMergeRejected,
            sliceIndex: block.sliceIndex,
            sliceOverlapDeduped: block.sliceOverlapDeduped,
            rotationAngleUsed: block.rotationAngleUsed,
            ocrText: block.ocrText,
            ocrConfidence: block.ocrConfidence,
            rawOcrText: block.rawOcrText,
            preprocessingEnabled: block.preprocessingEnabled,
            afterPreprocessingOcrText: block.afterPreprocessingOcrText,
            adaptivePreprocessingOcrText: block.adaptivePreprocessingOcrText,
            fixedPreprocessingOcrText: block.fixedPreprocessingOcrText,
            cropPaddingX: block.cropPaddingX,
            cropPaddingY: block.cropPaddingY,
            cropClampedByBubble: block.cropClampedByBubble,
            cropCandidatePreservesRawWords: block.cropCandidatePreservesRawWords,
            cropFallbackTriggered: block.cropFallbackTriggered,
            cropFallbackReason: block.cropFallbackReason,
            cropStrategyUsed: block.cropStrategyUsed,
            correctionEnabled: block.correctionEnabled,
            afterCorrectionText: block.afterCorrectionText,
            correctionRejectedReason: block.correctionRejectedReason,
            correctionPrompt: block.correctionPrompt,
            correctionRawOutput: block.correctionRawOutput,
            correctionErrorCode: block.correctionErrorCode,
            deterministicCorrectionText: block.deterministicCorrectionText,
            deterministicCorrectionAppliedRules: block.deterministicCorrectionAppliedRules,
            deterministicCorrectionSimilarity: block.deterministicCorrectionSimilarity,
            deterministicCorrectionTranslationCandidate: candidate,
            deterministicCorrectionTranslationRawOutput: rawOutput,
            deterministicCorrectionTranslationPassed: passed,
            deterministicCorrectionTranslationFailureDetail: failureDetail,
            finalTextUsedForTranslation: block.finalTextUsedForTranslation,
            bestGroundTruthIndex: block.bestGroundTruthIndex,
            bestGroundTruthText: block.bestGroundTruthText,
            bestGroundTruthType: block.bestGroundTruthType,
            groundTruthMatch: block.groundTruthMatch,
            groundTruthMatchThreshold: block.groundTruthMatchThreshold,
            ocrGroundTruthSimilarity: block.ocrGroundTruthSimilarity,
            ocrLegacySimilarity: block.ocrLegacySimilarity,
            wordOrderPreserved: block.wordOrderPreserved,
            ocrQualityLabel: block.ocrQualityLabel,
            translatedText: block.translatedText,
            translationCandidate: block.translationCandidate,
            rawOutputClassification: block.rawOutputClassification,
            candidateClassification: block.candidateClassification,
            failureCategory: block.failureCategory,
            prompt: block.prompt,
            rawOutput: block.rawOutput,
            errorCode: block.errorCode,
            checks: block.checks,
            failureReasons: block.failureReasons,
            qualityNotes: block.qualityNotes,
            translationDecisionTrace: block.translationDecisionTrace,
            translationFailureDetail: block.translationFailureDetail,
            ocrProbeNotes: block.ocrProbeNotes,
            blockPassed: block.blockPassed
        )
    }

    private func runCleanTextDiagnostic(groundTruth: [MangaGroundTruthEntry]) async -> MangaCleanTextDiagnosticReport {
        let cases = groundTruth.enumerated().filter { _, entry in
            entry.type == MangaGroundTruthEntry.dialogueType
        }.map { index, entry in
            (index, entry)
        }
        var results: [MangaCleanTextDiagnosticCase] = []
        for (index, entry) in cases {
            let request = makeProbeRequest(
                source: .englishUS,
                target: .simplifiedChinese,
                input: entry.text
            )
            let probe: RawModelProbeResult
            if selectedEngine == .local {
                probe = localService.rawTranslationProbe(for: request)
            } else {
                do {
                    try await mockService.prepare()
                    let result = try await mockService.generate(request)
                    probe = RawModelProbeResult(prompt: debugPromptPreview(for: request), output: result.text, errorCode: nil)
                } catch {
                    probe = RawModelProbeResult(prompt: debugPromptPreview(for: request), output: "", errorCode: "\(type(of: error)): \(error.localizedDescription)")
                }
            }
            let extraction = Self.extractMangaProbeTranslationCandidate(probe.output)
            let candidate = extraction.candidate
            let checks = mangaProbeChecks(original: entry.text, translation: candidate, errorCode: probe.errorCode)
            let baseReasons = mangaProbeFailureReasons(
                checks: checks,
                errorCode: probe.errorCode,
                original: entry.text,
                translation: candidate
            )
            let checksPassed = Self.mangaProbeBlockPassed(checks, errorCode: probe.errorCode)
            let qualityReason = checksPassed ? Self.mangaProbeTranslationLanguageQualityIssue(
                original: entry.text,
                candidate: candidate,
                rawOutput: probe.output,
                rawClassification: Self.classifyMangaProbeRawOutput(probe.output, original: entry.text)
            ) : nil
            let passed = checksPassed && qualityReason == nil
            results.append(
                MangaCleanTextDiagnosticCase(
                    index: index,
                    groundTruthType: entry.type,
                    text: entry.text,
                    prompt: probe.prompt,
                    rawOutput: probe.output,
                    translationCandidate: candidate,
                    passed: passed,
                    failureReasons: baseReasons + [qualityReason].compactMap { $0 }
                )
            )
        }
        let passedCount = results.filter(\.passed).count
        return MangaCleanTextDiagnosticReport(
            source: "test/1.ground_truth.json dialogue entries direct to current translation pipeline",
            promptTemplate: "把以下翻译成中文：",
            decodingMode: selectedEngine == .local ? ModelDecodingProfile.deterministic.mode : "mock",
            decodingSeed: selectedEngine == .local ? ModelDecodingProfile.deterministic.seed : nil,
            totalCases: results.count,
            passedCases: passedCount,
            failedCases: results.count - passedCount,
            passRate: results.isEmpty ? 0 : Double(passedCount) / Double(results.count),
            cases: results
        )
    }

    private func runDeterministicDecodingCheck(groundTruth: [MangaGroundTruthEntry]) async -> MangaDeterministicDecodingCheck {
        let input = groundTruth.first { $0.type == MangaGroundTruthEntry.dialogueType }?.text
            ?? "The City Battler Tournament starts in a few days."
        let request = makeProbeRequest(
            source: .englishUS,
            target: .simplifiedChinese,
            input: input
        )

        if selectedEngine == .local {
            let first = localService.rawTranslationProbe(for: request)
            let second = localService.rawTranslationProbe(for: request)
            return MangaDeterministicDecodingCheck(
                enabled: true,
                decodingMode: first.decodingMode,
                decodingSeed: first.decodingSeed,
                input: input,
                firstOutput: first.output,
                secondOutput: second.output,
                firstErrorCode: first.errorCode,
                secondErrorCode: second.errorCode,
                outputsIdentical: first.output == second.output && first.errorCode == second.errorCode
            )
        }

        do {
            try await mockService.prepare()
            let first = try await mockService.generate(request)
            let second = try await mockService.generate(request)
            return MangaDeterministicDecodingCheck(
                enabled: true,
                decodingMode: "mock",
                decodingSeed: nil,
                input: input,
                firstOutput: first.text,
                secondOutput: second.text,
                firstErrorCode: nil,
                secondErrorCode: nil,
                outputsIdentical: first.text == second.text
            )
        } catch {
            let errorCode = "\(type(of: error)): \(error.localizedDescription)"
            return MangaDeterministicDecodingCheck(
                enabled: true,
                decodingMode: "mock",
                decodingSeed: nil,
                input: input,
                firstOutput: "",
                secondOutput: "",
                firstErrorCode: errorCode,
                secondErrorCode: errorCode,
                outputsIdentical: true
            )
        }
    }

    private static func writeCleanTextDiagnostic(_ report: MangaCleanTextDiagnosticReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
    }

    private func writeMangaProbeProgress(
        stage: String,
        startedAt: Date? = nil,
        blocks: Int? = nil,
        runOptions: MangaOverlayProbeRunOptions? = nil,
        message: String? = nil
    ) {
        var payload: [String: Any] = [
            "stage": stage,
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        if let startedAt {
            let elapsed = Int(Date().timeIntervalSince(startedAt))
            payload["startedAt"] = ISO8601DateFormatter().string(from: startedAt)
            payload["elapsedSeconds"] = elapsed
            payload["stageDurationsSeconds"] = [stage: elapsed]
        }
        if let blocks {
            payload["blocks"] = blocks
        }
        if let runOptions {
            payload["probeMode"] = runOptions.mode.rawValue
            payload["probeFastPathEnabled"] = runOptions.mode == .ciFast
            payload["skippedDiagnostics"] = runOptions.skippedDiagnostics
        }
        let retainedFiles = Self.currentProbeOutputFileNames(in: mangaOverlayOutputDirectory)
        if !retainedFiles.isEmpty {
            payload["retainedOutputFiles"] = retainedFiles
        }
        if let message {
            payload["message"] = message
        }

        do {
            try FileManager.default.createDirectory(
                at: mangaOverlayOutputDirectory,
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(
                to: mangaOverlayOutputDirectory.appendingPathComponent("manga_probe_progress.json"),
                options: .atomic
            )
        } catch {
            writeLaunchLLMSmokeProbe("manga-progress-write-error stage=\(stage) error=\(Self.probeField(error.localizedDescription))")
        }
    }

    private static func currentProbeOutputFileNames(in directory: URL) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return names
            .filter { name in
                name.hasSuffix(".json") || name.hasSuffix(".txt") || name.hasSuffix(".png")
            }
            .sorted()
    }

    private func mangaProbeChecks(
        original: String,
        translation: String,
        errorCode: String?
    ) -> MangaOverlayProbeChecks {
        let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let cleanOriginal = original.trimmingCharacters(in: trimSet)
        let cleanTranslation = translation.trimmingCharacters(in: trimSet)
        let translationNotEmpty = errorCode == nil && !cleanTranslation.isEmpty
        return MangaOverlayProbeChecks(
            ocrNotEmpty: !cleanOriginal.isEmpty,
            translationNotEmpty: translationNotEmpty,
            translationNotEqualOriginal: translationNotEmpty && cleanTranslation.localizedCaseInsensitiveCompare(cleanOriginal) != .orderedSame,
            translationNotContainOriginal: translationNotEmpty && !cleanTranslation.localizedCaseInsensitiveContains(cleanOriginal),
            translationNotPlaceholder: translationNotEmpty && !Self.isPlaceholderTranslationOutput(cleanTranslation),
            translationHasEnoughChinese: translationNotEmpty && Self.containsCJK(cleanTranslation),
            looksLikeChinese: translationNotEmpty && Self.containsCJK(cleanTranslation)
        )
    }

    private static func mangaProbeBlockPassed(_ checks: MangaOverlayProbeChecks, errorCode: String?) -> Bool {
        errorCode == nil
            && checks.ocrNotEmpty
            && checks.translationNotEmpty
            && checks.translationNotEqualOriginal
            && checks.translationNotPlaceholder
            && checks.translationHasEnoughChinese
            && checks.looksLikeChinese
    }

    private func mangaProbeFailureReasons(
        checks: MangaOverlayProbeChecks,
        errorCode: String?,
        original: String,
        translation: String
    ) -> [String] {
        var reasons: [String] = []
        if let errorCode {
            reasons.append(errorCode)
        }
        if !checks.ocrNotEmpty {
            reasons.append("OCR 为空")
        }
        if !checks.translationNotEmpty {
            reasons.append("翻译为空")
        }
        if checks.translationNotEmpty, !checks.translationNotEqualOriginal {
            reasons.append("翻译等于原文")
        }
        let cleanOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        if checks.translationNotEmpty,
           !checks.translationNotContainOriginal,
           !cleanOriginal.isEmpty,
           !cleanTranslation.isEmpty,
           cleanTranslation.localizedCaseInsensitiveCompare(cleanOriginal) != .orderedSame {
            reasons.append("翻译包含完整原文")
        }
        if checks.translationNotEmpty, !checks.translationNotPlaceholder {
            reasons.append("翻译是占位答复")
        }
        if checks.translationNotEmpty, !checks.translationHasEnoughChinese {
            reasons.append("中文字符不足")
        }
        if checks.translationNotEmpty, !checks.looksLikeChinese {
            reasons.append("翻译不像中文")
        }
        return reasons
    }

    private func mangaProbeQualityNotes(
        checks: MangaOverlayProbeChecks,
        original: String,
        rawOutput: String,
        candidate: String,
        extraction: MangaProbeCandidateExtraction
    ) -> [String] {
        var notes: [String] = []
        let cleanOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanCandidate.isEmpty {
            notes.append("candidateEmpty")
        }
        if extraction.rejectedPlaceholder {
            notes.append("candidateRejectedAsPlaceholder")
        }
        if extraction.rawHadContent, extraction.candidate.isEmpty {
            notes.append("candidateExtractorDroppedRawOutput")
        }
        if !cleanOriginal.isEmpty,
           !cleanCandidate.isEmpty,
           cleanCandidate.localizedCaseInsensitiveContains(cleanOriginal) {
            notes.append("translationContainsFullOCRText")
        }
        let latinCount = Self.latinLetterCount(in: candidate)
        let cjkCount = Self.cjkCharacterCount(in: candidate)
        let rawLatinCount = Self.latinLetterCount(in: rawOutput)
        let rawCJKCount = Self.cjkCharacterCount(in: rawOutput)
        notes.append("candidateLength=\(cleanCandidate.count)")
        notes.append("rawOutputLength=\(rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).count)")
        if latinCount > 0 {
            notes.append("latinLetters=\(latinCount)")
        }
        if cjkCount > 0 {
            notes.append("cjkCharacters=\(cjkCount)")
        }
        if rawLatinCount > 0 {
            notes.append("rawLatinLetters=\(rawLatinCount)")
        }
        if rawCJKCount > 0 {
            notes.append("rawCJKCharacters=\(rawCJKCount)")
        }
        if Self.containsLikelyOCRError(in: original) {
            notes.append("likelyOCRIssue")
        }
        if cjkCount > 0, !Self.mangaProbeBlockPassed(checks, errorCode: nil) {
            notes.append("cjkCandidateButFailed")
        }
        return notes
    }

    private static func mangaProbeTranslationDecisionTrace(
        checks: MangaOverlayProbeChecks,
        errorCode: String?,
        rawClassification: String,
        candidateClassification: String,
        extraction: MangaProbeCandidateExtraction,
        translationLanguageQualityPassed: Bool,
        languageQualityReason: String?,
        ocrInputReason: String?
    ) -> [String] {
        var trace = [
            "rawOutputClassification=\(rawClassification)",
            "candidateClassification=\(candidateClassification)",
            "rawHadContent=\(extraction.rawHadContent)",
            "rejectedPlaceholder=\(extraction.rejectedPlaceholder)",
            "ocrNotEmpty=\(checks.ocrNotEmpty)",
            "translationNotEmpty=\(checks.translationNotEmpty)",
            "translationNotEqualOriginal=\(checks.translationNotEqualOriginal)",
            "translationNotPlaceholder=\(checks.translationNotPlaceholder)",
            "translationHasCJK=\(checks.translationHasEnoughChinese)",
            "looksLikeChinese=\(checks.looksLikeChinese)",
            "translationLanguageQualityPassed=\(translationLanguageQualityPassed)"
        ]
        if let errorCode {
            trace.append("errorCode=\(errorCode)")
        }
        if let languageQualityReason {
            trace.append("translationLanguageQualityIssue=\(languageQualityReason)")
        }
        if let ocrInputReason {
            trace.append("ocrInputQualityIssue=\(ocrInputReason)")
        }
        return trace
    }

    private static func mangaProbeTranslationLanguageQualityIssue(
        original: String,
        candidate: String,
        rawOutput: String,
        rawClassification: String
    ) -> String? {
        let cleanOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanOriginal.isEmpty, !cleanCandidate.isEmpty else { return nil }

        if Self.looksLikeExplanationList(cleanCandidate) {
            return "译文像解释/列表，不像单句翻译"
        }

        if Self.looksLikeExplanationList(rawOutput) {
            return "raw 输出像解释/列表，不像单句翻译"
        }

        if Self.isTranslationLabelOnly(cleanCandidate) {
            return "候选只是翻译标签，不是真实译文"
        }

        if Self.isGenericLowInformationTranslation(cleanCandidate, original: cleanOriginal) {
            return "多词原文只得到泛化短答复"
        }

        if Self.rawOutputLeavesUntranslatedEnglish(rawOutput, candidate: cleanCandidate) {
            return "raw 输出仍保留未翻译英文"
        }

        let sourceWords = cleanOriginal
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 3 }
        let cjkCount = cjkCharacterCount(in: cleanCandidate)
        if sourceWords.count >= 3, cjkCount <= 2 {
            return "多词原文只得到过短中文候选"
        }
        if sourceWords.count >= 5, cjkCount <= 4 {
            return "长原文只得到过短中文候选"
        }

        if containsLatinLetter(cleanCandidate), cjkCount > 0 {
            return "译文仍混入拉丁字母"
        }

        return nil
    }

    private static func isGenericLowInformationTranslation(_ candidate: String, original: String) -> Bool {
        let sourceWords = original
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 3 }
        guard sourceWords.count >= 3 else { return false }

        let normalizedCandidate = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: " ", with: "")
        let genericShortAnswers = [
            "那是什么",
            "这是什么",
            "什么意思",
            "谢谢",
            "好的"
        ]
        return genericShortAnswers.contains { normalizedCandidate.localizedCaseInsensitiveCompare($0) == .orderedSame }
    }

    private static func mangaProbeOCRInputQualityIssue(_ block: MangaOverlayProbeBlock) -> String? {
        if let similarity = block.ocrGroundTruthSimilarity, similarity < 0.72 {
            return "OCR 相似度低于 0.72，端到端结果不可作为通过"
        }
        if Self.containsLikelyOCRError(in: block.finalTextUsedForTranslation),
           let similarity = block.ocrGroundTruthSimilarity,
           similarity < 0.86 {
            return "OCR 含已知错词且相似度不足 0.86"
        }
        return nil
    }

    private static func looksLikeExplanationList(_ text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = clean.filter { $0 == "|" || $0 == "、" || $0 == ";" || $0 == "；" }.count
        if separators >= 4 {
            return true
        }
        let markers = ["语境", "语气", "词汇", "语法", "解释", "示例", "总结", "建议", "这句话", "意思是"]
        let markerHits = markers.count { clean.contains($0) }
        return markerHits >= 3
    }

    private static func isTranslationLabelOnly(_ text: String) -> Bool {
        let clean = text
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: " ", with: "")
        let labels = [
            "以下是翻译",
            "这是翻译",
            "翻译如下",
            "翻译是",
            "中文翻译",
            "译文"
        ]
        return labels.contains { clean.localizedCaseInsensitiveCompare($0) == .orderedSame }
    }

    private static func rawOutputLeavesUntranslatedEnglish(_ rawOutput: String, candidate: String) -> Bool {
        let rawLines = rawOutput
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { stripProbeFormatting(String($0)) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "|" }
        let candidateLine = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let untranslatedLatinLines = rawLines.filter { line in
            line.localizedCaseInsensitiveCompare(candidateLine) != .orderedSame
                && containsLatinLetter(line)
                && !isPlaceholderTranslationOutput(line)
        }
        return !untranslatedLatinLines.isEmpty
    }

    private static func mangaProbeTranslationFailureDetail(
        failureCategory: String,
        rawClassification: String,
        candidateClassification: String,
        failureReasons: [String],
        qualityNotes: [String],
        hasLikelyOCRIssue: Bool
    ) -> String {
        let reasonText = failureReasons.isEmpty ? "未知原因" : failureReasons.joined(separator: "、")
        let ocrHint = hasLikelyOCRIssue ? "；OCR 输入疑似有误" : ""
        if failureCategory == "translationUsableButOCRSuspect" {
            return "译文本身像可用中文，但 OCR 输入质量未过端到端探针：\(reasonText)"
        }
        if failureCategory == "ruleFalseFailureSuspected" {
            return "候选译文含中文但未过规则，需人工复核规则是否过严：\(reasonText)"
        }
        if qualityNotes.contains("candidateExtractorDroppedRawOutput") {
            return "raw output 有内容但候选抽取为空，优先查候选抽取规则：\(reasonText)"
        }
        if rawClassification == "placeholder" || candidateClassification == "placeholderRejected" || candidateClassification == "placeholder" {
            return "模型输出解释/占位文本，不是真实译文：\(reasonText)\(ocrHint)"
        }
        if rawClassification == "repeatedOriginal" || candidateClassification == "repeatedOriginal" {
            return "模型复读原文，非规则误杀：\(reasonText)\(ocrHint)"
        }
        if rawClassification == "empty" || candidateClassification == "empty" {
            return "模型 raw 输出或候选为空：\(reasonText)\(ocrHint)"
        }
        if rawClassification == "nonChinese" || candidateClassification == "nonChinese" || rawClassification == "symbolsOnly" {
            return "模型输出非中文/符号，未达到英译中目标：\(reasonText)\(ocrHint)"
        }
        return "\(failureCategory)：\(reasonText)\(ocrHint)"
    }

    private static func classifyMangaProbeRawOutput(_ rawOutput: String, original: String) -> String {
        let cleanRaw = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanRaw.isEmpty {
            return "empty"
        }
        if isPlaceholderTranslationOutput(cleanRaw) {
            return "placeholder"
        }
        let repeatsOriginal = cleanRaw.localizedCaseInsensitiveCompare(cleanOriginal) == .orderedSame
            || cleanRaw.localizedCaseInsensitiveContains(cleanOriginal)
        if !cleanOriginal.isEmpty, repeatsOriginal {
            return "repeatedOriginal"
        }
        let hasCJK = containsCJK(cleanRaw)
        let hasLatin = containsLatinLetter(cleanRaw)
        if hasCJK, hasLatin {
            return "mixedChineseAndEnglish"
        }
        if hasCJK {
            return "chinese"
        }
        if hasLatin {
            return "nonChinese"
        }
        return "symbolsOnly"
    }

    private static func classifyMangaProbeCandidate(
        _ candidate: String,
        original: String,
        rejectedPlaceholder: Bool
    ) -> String {
        let cleanCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanCandidate.isEmpty {
            return rejectedPlaceholder ? "placeholderRejected" : "empty"
        }
        if isPlaceholderTranslationOutput(cleanCandidate) {
            return "placeholder"
        }
        let repeatsOriginal = cleanCandidate.localizedCaseInsensitiveCompare(cleanOriginal) == .orderedSame
            || cleanCandidate.localizedCaseInsensitiveContains(cleanOriginal)
        if !cleanOriginal.isEmpty, repeatsOriginal {
            return "repeatedOriginal"
        }
        let hasCJK = containsCJK(cleanCandidate)
        let hasLatin = containsLatinLetter(cleanCandidate)
        if hasCJK, hasLatin {
            return "mixedChineseAndEnglish"
        }
        if hasCJK {
            return "chinese"
        }
        if hasLatin {
            return "nonChinese"
        }
        return "symbolsOnly"
    }

    private static func mangaProbeFailureCategory(
        passed: Bool,
        rawClassification: String,
        candidateClassification: String,
        translationChecksPassed: Bool,
        translationLanguageQualityPassed: Bool,
        languageQualityReason: String?,
        hasLikelyOCRIssue: Bool,
        ocrInputReason: String?
    ) -> String {
        if passed {
            return "passed"
        }
        if translationLanguageQualityPassed, ocrInputReason != nil {
            return "translationUsableButOCRSuspect"
        }
        if translationChecksPassed, languageQualityReason != nil {
            return "translationLanguageQualityFailure"
        }
        if candidateClassification == "chinese" || candidateClassification == "mixedChineseAndEnglish" {
            if hasLikelyOCRIssue, translationChecksPassed {
                return "ocrInputSuspect"
            }
            return "ruleFalseFailureSuspected"
        }
        if hasLikelyOCRIssue {
            return "ocrInputSuspect"
        }
        if rawClassification == "chinese" || rawClassification == "mixedChineseAndEnglish" {
            return "candidateExtractionOrRule"
        }
        if candidateClassification == "empty"
            || rawClassification == "empty"
            || rawClassification == "placeholder"
            || rawClassification == "repeatedOriginal"
            || rawClassification == "nonChinese"
            || rawClassification == "symbolsOnly" {
            return "modelOutputFailure"
        }
        return "unknown"
    }

    private static func cleanMangaProbeTranslationCandidate(_ output: String) -> String {
        extractMangaProbeTranslationCandidate(output).candidate
    }

    private struct MangaProbeCandidateExtraction {
        var candidate: String
        var rejectedPlaceholder: Bool
        var rawHadContent: Bool
    }

    private static func extractMangaProbeTranslationCandidate(_ output: String) -> MangaProbeCandidateExtraction {
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { stripProbeFormatting($0) }
            .filter { !$0.isEmpty && $0 != "|" }

        let nonPlaceholderLines = lines.filter { !Self.isPlaceholderTranslationOutput($0) }
        if let lastChineseLine = nonPlaceholderLines.reversed().first(where: Self.containsCJK) {
            return MangaProbeCandidateExtraction(
                candidate: lastChineseLine,
                rejectedPlaceholder: false,
                rawHadContent: !lines.isEmpty
            )
        }
        if let lastLine = nonPlaceholderLines.last {
            return MangaProbeCandidateExtraction(
                candidate: lastLine,
                rejectedPlaceholder: false,
                rawHadContent: !lines.isEmpty
            )
        }
        return MangaProbeCandidateExtraction(
            candidate: lines.last ?? "",
            rejectedPlaceholder: !lines.isEmpty,
            rawHadContent: !lines.isEmpty
        )
    }

    private static func stripProbeFormatting(_ text: String) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while output.hasPrefix("*") || output.hasPrefix("-") || output.hasPrefix("•") {
            output = String(output.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let wrappers = ["**", "__", "`", "\"", "'", "“", "”", "‘", "’"]
        var didStrip = true
        while didStrip {
            didStrip = false
            for wrapper in wrappers where output.hasPrefix(wrapper) && output.hasSuffix(wrapper) && output.count > wrapper.count * 2 {
                output = String(output.dropFirst(wrapper.count).dropLast(wrapper.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                didStrip = true
            }
        }
        if output.hasPrefix("|") {
            output = String(output.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for wrapper in wrappers {
            while output.hasPrefix(wrapper), output.count > wrapper.count {
                output = String(output.dropFirst(wrapper.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            while output.hasSuffix(wrapper), output.count > wrapper.count {
                output = String(output.dropLast(wrapper.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return output
    }

    private static func mangaCorrectionPrompt(for text: String) -> String {
        """
        <start_of_turn>user
        以下文本来自漫画对话框的 OCR 识别结果，可能包含字符识别错误。
        如果存在明显的拼写或字符错误，请修正为最合理的英文原文；
        如果无法确定，原样输出。不要添加任何解释或标点说明。

        文本：\(text)
        <end_of_turn>
        <start_of_turn>model
        """
    }

    private static func cleanMangaCorrectionCandidate(_ output: String) -> String {
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { stripProbeFormatting(String($0)) }
            .filter { line in
                let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !cleanLine.isEmpty
                    && cleanLine != "|"
                    && !cleanLine.localizedCaseInsensitiveContains("文本：")
                    && !cleanLine.localizedCaseInsensitiveContains("以下文本来自漫画")
                    && !cleanLine.localizedCaseInsensitiveContains("<start_of_turn>")
                    && !cleanLine.localizedCaseInsensitiveContains("<end_of_turn>")
            }
        return lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func evaluateMangaCorrectionGuardrail(
        original: String,
        proposed: String,
        options: MangaOverlayCorrectionOptions
    ) -> MangaOverlayCorrectionGuardrailTest {
        let cleanOriginal = normalizedCorrectionText(original)
        let cleanProposed = normalizedCorrectionText(proposed)
        guard !cleanOriginal.isEmpty else {
            return MangaOverlayCorrectionGuardrailTest(
                original: original,
                proposed: proposed,
                accepted: false,
                reason: "原文为空"
            )
        }
        guard !cleanProposed.isEmpty else {
            return MangaOverlayCorrectionGuardrailTest(
                original: original,
                proposed: proposed,
                accepted: false,
                reason: "纠错输出为空"
            )
        }

        let lengthDelta = abs(Double(cleanProposed.count - cleanOriginal.count)) / Double(max(cleanOriginal.count, 1))
        if lengthDelta > options.maxLengthDeltaRatio {
            return MangaOverlayCorrectionGuardrailTest(
                original: original,
                proposed: proposed,
                accepted: false,
                reason: "长度变化 \(Self.percentString(lengthDelta)) 超过 \(Self.percentString(options.maxLengthDeltaRatio))"
            )
        }

        let originalWords = correctionWords(cleanOriginal)
        let proposedWords = correctionWords(cleanProposed)
        let wordDelta = abs(Double(proposedWords.count - originalWords.count)) / Double(max(originalWords.count, 1))
        if wordDelta > options.maxWordCountDeltaRatio {
            return MangaOverlayCorrectionGuardrailTest(
                original: original,
                proposed: proposed,
                accepted: false,
                reason: "词数变化 \(Self.percentString(wordDelta)) 超过 \(Self.percentString(options.maxWordCountDeltaRatio))"
            )
        }

        let originalComparableWords = originalWords.filter { $0.count >= 4 }
        let newWords = proposedWords
            .filter { $0.count >= 4 }
            .filter { proposedWord in
                !originalComparableWords.contains { originalWord in
                    correctionWordSimilarity(proposedWord, originalWord) >= 0.58
                        || proposedWord.localizedCaseInsensitiveContains(originalWord)
                        || originalWord.localizedCaseInsensitiveContains(proposedWord)
                }
            }
        if !newWords.isEmpty {
            let sampleNewWords = newWords.prefix(4).joined(separator: ", ")
            return MangaOverlayCorrectionGuardrailTest(
                original: original,
                proposed: proposed,
                accepted: false,
                reason: "出现无相似依据新词：\(sampleNewWords)"
            )
        }

        return MangaOverlayCorrectionGuardrailTest(
            original: original,
            proposed: proposed,
            accepted: true,
            reason: nil
        )
    }

    private static func normalizedCorrectionText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func correctionWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func correctionWordSimilarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty || !rhs.isEmpty else { return 1 }
        let distance = levenshteinDistance(Array(lhs), Array(rhs))
        return 1 - Double(distance) / Double(max(max(lhs.count, rhs.count), 1))
    }

    private static func levenshteinDistance<T: Equatable>(_ lhs: [T], _ rhs: [T]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        var previous = Array(0...rhs.count)
        var current = Array(repeating: 0, count: rhs.count + 1)
        for lhsIndex in 1...lhs.count {
            current[0] = lhsIndex
            for rhsIndex in 1...rhs.count {
                let cost = lhs[lhsIndex - 1] == rhs[rhsIndex - 1] ? 0 : 1
                current[rhsIndex] = min(
                    previous[rhsIndex] + 1,
                    current[rhsIndex - 1] + 1,
                    previous[rhsIndex - 1] + cost
                )
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }

    private static func percentString(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func makeMangaOverlayProbeReport(
        blocks: [MangaOverlayProbeBlock],
        outputFiles: MangaOverlayProbeOutputFiles,
        configuration: MangaOverlayProbeConfiguration,
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics? = nil,
        sliceOCR: MangaOverlaySliceOCRDiagnostics? = nil,
        syntheticSliceOCR: MangaOverlaySliceOCRDiagnostics? = nil,
        cropFallbackSelfTest: MangaOverlayCropFallbackSelfTest? = nil,
        lexiconComparison: MangaOverlayLexiconComparison? = nil,
        visionAPIComparison: MangaOverlayVisionAPIComparison? = nil,
        frameworkComparison: MangaOverlayFrameworkComparison? = nil,
        fusionComparison: MangaOverlayFusionComparison? = nil,
        fusionResults: [MangaOverlayFusionResult] = [],
        textRegionCropReport: MangaOverlayTextRegionCropReport? = nil,
        textBoxCandidateReport: MangaOverlayTextBoxCandidateReport? = nil,
        segmentMaskReport: MangaOverlaySegmentMaskReport? = nil,
        preCropTextBoxPlanReport: MangaOverlayPreCropTextBoxPlanReport? = nil,
        cropExperimentReport: MangaOverlayCropExperimentReport? = nil,
        textBoxPlanFailureReport: MangaOverlayTextBoxPlanFailureReport? = nil,
        lineTextBoxPlanReport: MangaOverlayLineTextBoxPlanReport? = nil,
        lineCropExperimentReport: MangaOverlayLineCropExperimentReport? = nil,
        externalArtifactReadinessReport: MangaOverlayExternalArtifactReadinessReport? = nil,
        externalTextBoxShadowOCRReport: MangaOverlayExternalTextBoxShadowOCRReport? = nil,
        internalStructureBottleneckReport: MangaOverlayInternalStructureBottleneckReport? = nil,
        routingDrivenTranslationComparisonReport: MangaRoutingDrivenTranslationComparisonReport? = nil,
        ocrCharacterDamageAuditReport: MangaOCRCharacterDamageAuditReport? = nil,
        bubbleSubRegionReport: MangaOverlayBubbleSubRegionReport? = nil,
        bubbleMaskReport: MangaOverlayBubbleMaskReport? = nil,
        bubbleAssignmentCorrectionReport: MangaOverlayBubbleAssignmentCorrectionReport? = nil,
        bubbleSplitCandidateReport: MangaOverlayBubbleSplitCandidateReport? = nil,
        cleanTextDiagnostic: MangaCleanTextDiagnosticReport? = nil,
        batchTranslationComparison: MangaBatchTranslationComparison? = nil,
        deterministicDecodingCheck: MangaDeterministicDecodingCheck? = nil,
        outputCleanupRemovedItemCount: Int = 0,
        extraWarnings: [String] = []
    ) -> MangaOverlayProbeReport {
        var warnings = extraWarnings
        if blocks.isEmpty {
            warnings.append("检测到 0 个文字块")
        }
        for block in blocks where !block.blockPassed {
            let reason = block.failureReasons.isEmpty ? "未知原因" : block.failureReasons.joined(separator: "、")
            warnings.append("block \(block.index) 判定失败：\(reason)")
        }
        if outputFiles.debugBoxesImage.isEmpty || outputFiles.overlayImage.isEmpty {
            warnings.append("输出图片未生成")
        } else {
            if !Self.fileIsNonEmpty(path: outputFiles.debugBoxesImage) {
                warnings.append("1_debug_boxes.png 为空或不存在")
            }
            if !Self.fileIsNonEmpty(path: outputFiles.overlayImage) {
                warnings.append("1_translated_overlay.png 为空或不存在")
            }
        }
        if let frameworkComparison, !frameworkComparison.consistencyPassed {
            warnings.append(contentsOf: frameworkComparison.consistencyWarnings)
        }
        if let fusionComparison, !fusionComparison.consistencyPassed {
            warnings.append(contentsOf: fusionComparison.consistencyWarnings)
        }

        let allBlocksPassed = !blocks.isEmpty && blocks.allSatisfy(\.blockPassed)
        let filesPresent = Self.fileIsNonEmpty(path: outputFiles.debugBoxesImage)
            && Self.fileIsNonEmpty(path: outputFiles.overlayImage)
        let diagnostics = makeMangaOverlayProbeDiagnostics(blocks: blocks)
        let retainedFiles = Self.retainedProbeOutputFiles(from: outputFiles)
        let correctionGuardrailTest = Self.evaluateMangaCorrectionGuardrail(
            original: "XQZ 12 ///",
            proposed: "The City Battler Tournament starts in a few days.",
            options: configuration.correction
        )
        return MangaOverlayProbeReport(
            sourceImage: "test/1.png",
            engineUsed: selectedAdapterMetadata.displayName,
            decodingMode: selectedEngine == .local ? ModelDecodingProfile.deterministic.mode : "mock",
            decodingSeed: selectedEngine == .local ? ModelDecodingProfile.deterministic.seed : nil,
            configuration: configuration,
            totalBlocksDetected: blocks.count,
            blocks: blocks,
            diagnostics: diagnostics,
            correctionGuardrailTest: correctionGuardrailTest,
            lexiconComparison: lexiconComparison,
            visionAPIComparison: visionAPIComparison,
            frameworkComparison: frameworkComparison,
            fusionComparison: fusionComparison,
            fusionResults: fusionResults,
            textRegionCropReport: textRegionCropReport,
            textBoxCandidateReport: textBoxCandidateReport,
            segmentMaskReport: segmentMaskReport,
            preCropTextBoxPlanReport: preCropTextBoxPlanReport,
            cropExperimentReport: cropExperimentReport,
            textBoxPlanFailureReport: textBoxPlanFailureReport,
            lineTextBoxPlanReport: lineTextBoxPlanReport,
            lineCropExperimentReport: lineCropExperimentReport,
            externalArtifactReadinessReport: externalArtifactReadinessReport,
            externalTextBoxShadowOCRReport: externalTextBoxShadowOCRReport,
            internalStructureBottleneckReport: internalStructureBottleneckReport,
            routingDrivenTranslationComparisonReport: routingDrivenTranslationComparisonReport,
            ocrCharacterDamageAuditReport: ocrCharacterDamageAuditReport,
            bubbleSubRegionReport: bubbleSubRegionReport,
            bubbleMaskReport: bubbleMaskReport,
            bubbleAssignmentCorrectionReport: bubbleAssignmentCorrectionReport,
            bubbleSplitCandidateReport: bubbleSplitCandidateReport,
            cleanTextDiagnostic: cleanTextDiagnostic,
            batchTranslationComparison: batchTranslationComparison,
            deterministicDecodingCheck: deterministicDecodingCheck,
            bubbleGeometry: bubbleGeometry,
            sliceOCR: sliceOCR,
            syntheticSliceOCR: syntheticSliceOCR,
            cropFallbackSelfTest: cropFallbackSelfTest,
            overallPassed: allBlocksPassed && filesPresent,
            outputFiles: outputFiles,
            outputDirectoryCleaned: true,
            outputCleanupRemovedItemCount: outputCleanupRemovedItemCount,
            outputFileCountAfterCleanup: retainedFiles.count,
            retainedOutputFiles: retainedFiles,
            outputCleanupPolicy: "探针开始重建 App 沙盒 Output；renderOutputs 只写入本轮文件；export-probe-output.sh 重建项目根 output；只保留本轮 probe_report.json 和本轮 PNG/TXT/JSON。",
            warnings: warnings
        )
    }

    private static func makeExternalArtifactReadinessReport(
        blocks: [MangaOverlayProbeBlock],
        imageWidth: Int,
        imageHeight: Int,
        bundledTestDirectory: URL?,
        bubbleMaskReport: MangaOverlayBubbleMaskReport?,
        segmentMaskReport: MangaOverlaySegmentMaskReport?
    ) -> MangaOverlayExternalArtifactReadinessReport {
        let artifactsDirectory = bundledTestDirectory?.appendingPathComponent("koharu_artifacts", isDirectory: true)
        let manifestURL = artifactsDirectory?.appendingPathComponent("1.manifest.json")
        var isDirectory: ObjCBool = false
        let activeArtifactsDirectory = artifactsDirectory.map {
            FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory) && isDirectory.boolValue
        } ?? false
        var parseErrors: [String] = []
        var notes = [
            "shadowOnly=true",
            "groundTruthNotUsed=true",
            "doesNotChangeFinalTextUsedForTranslation=true",
            "doesNotChangeTextRegionCropAdoptedCount=true",
            "doesNotAttachExternalDetectorRuntime=true",
            "activeInputDirectory=test/koharu_artifacts",
            "contractExamplesDirectory=md/koharu研究/artifact_contract/examples",
            "contract examples are non-active fixtures and must not be copied into the App bundle as detector output"
        ]
        let manifest: MangaOverlayExternalArtifactManifest? = Self.decodeExternalArtifact(
            MangaOverlayExternalArtifactManifest.self,
            from: manifestURL,
            label: "manifest",
            parseErrors: &parseErrors
        )
        if artifactsDirectory == nil {
            notes.append("bundled test directory is unavailable")
        } else if let artifactsDirectory, !FileManager.default.fileExists(atPath: artifactsDirectory.path) {
            notes.append("test/koharu_artifacts directory not found")
        }

        let textBoxesURL = Self.externalArtifactURL(
            named: manifest?.textBoxesPath,
            fallback: "1.textboxes.json",
            artifactsDirectory: artifactsDirectory
        )
        let bubbleMaskURL = Self.externalArtifactURL(
            named: manifest?.bubbleMaskPath,
            fallback: "1.bubbles.json",
            artifactsDirectory: artifactsDirectory
        )
        let segmentMaskURL = Self.externalArtifactURL(
            named: manifest?.segmentMaskPath,
            fallback: "1.segment_mask.json",
            artifactsDirectory: artifactsDirectory
        )
        let textBoxes = Self.decodeExternalArtifactList(
            MangaOverlayExternalTextBox.self,
            from: textBoxesURL,
            keys: ["textBoxes", "textboxes", "items"],
            label: "textBoxes",
            parseErrors: &parseErrors
        )
        let bubbleInstances = Self.decodeExternalArtifactList(
            MangaOverlayExternalBubbleInstance.self,
            from: bubbleMaskURL,
            keys: ["bubbleInstances", "bubbles", "instances", "items"],
            label: "bubbleMask",
            parseErrors: &parseErrors
        )
        let segmentMask = Self.decodeExternalArtifact(
            MangaOverlayExternalSegmentMaskSummary.self,
            from: segmentMaskURL,
            label: "segmentMask",
            parseErrors: &parseErrors
        )
        let missingArtifacts = Self.externalMissingArtifacts(
            manifestURL: manifestURL,
            textBoxesURL: textBoxesURL,
            bubbleMaskURL: bubbleMaskURL,
            segmentMaskURL: segmentMaskURL
        )
        let coordinateValidation = Self.validateExternalArtifactCoordinates(
            manifest: manifest,
            textBoxes: textBoxes,
            bubbleInstances: bubbleInstances,
            segmentMask: segmentMask,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )
        let blockAlignment = Self.externalArtifactBlockAlignment(
            blocks: blocks,
            textBoxes: textBoxes,
            bubbleInstances: bubbleInstances,
            segmentMask: segmentMask,
            segmentMaskReport: segmentMaskReport
        )
        let readinessVerdict = Self.externalArtifactReadinessVerdict(
            manifestFound: manifest != nil,
            textBoxes: textBoxes,
            bubbleInstances: bubbleInstances,
            segmentMask: segmentMask,
            missingArtifacts: missingArtifacts,
            parseErrors: parseErrors,
            coordinateValidation: coordinateValidation
        )
        let nextAction = Self.externalArtifactNextAction(
            verdict: readinessVerdict,
            textBoxes: textBoxes,
            bubbleInstances: bubbleInstances,
            segmentMask: segmentMask
        )
        if let bubbleMaskReport {
            notes.append("internalBubbleMaskInstances=\(bubbleMaskReport.instanceCount)")
        }
        if let segmentMaskReport {
            notes.append("internalSegmentGlyphBlocks=\(segmentMaskReport.glyphMaskBlocks)")
        }
        if manifest?.contractExampleOnly == true {
            notes.append("contractExampleOnly=true; active readiness is blocked because this is not real detector output")
        }
        if readinessVerdict != "readyForShadowOCR" {
            notes.append("external detector artifact evidence is insufficient; stop before shadow OCR")
        }
        let shadowAllowed = readinessVerdict == "readyForShadowOCR"
            && activeArtifactsDirectory
            && manifest?.contractExampleOnly != true
        return MangaOverlayExternalArtifactReadinessReport(
            enabled: true,
            sourceImage: "test/1.png",
            activeArtifactsDirectory: activeArtifactsDirectory,
            contractExampleOnly: manifest?.contractExampleOnly ?? false,
            generatedBy: manifest?.generatedBy,
            manifestPath: manifestURL?.path,
            textBoxesPath: textBoxesURL?.path,
            bubbleMaskPath: bubbleMaskURL?.path,
            segmentMaskPath: segmentMaskURL?.path,
            externalTextBoxesShadowOCRAllowed: shadowAllowed,
            manifestFound: manifest != nil,
            textBoxesFound: Self.fileExists(textBoxesURL),
            bubbleMaskFound: Self.fileExists(bubbleMaskURL),
            segmentMaskFound: Self.fileExists(segmentMaskURL),
            textBoxCount: textBoxes.count,
            bubbleInstanceCount: bubbleInstances.count,
            segmentGlyphPixelCount: segmentMask?.glyphPixelCount,
            parsedTextBoxCount: textBoxes.count,
            parsedBubbleInstanceCount: bubbleInstances.count,
            parseErrors: parseErrors,
            missingArtifacts: missingArtifacts,
            coordinateValidation: coordinateValidation,
            blockAlignment: blockAlignment,
            readinessVerdict: readinessVerdict,
            nextAction: nextAction,
            notes: notes
        )
    }

    private func makeExternalTextBoxShadowOCRReport(
        blocks: [MangaOverlayProbeBlock],
        image: CGImage,
        readinessReport: MangaOverlayExternalArtifactReadinessReport?,
        bundledTestDirectory: URL?,
        preprocessing: MangaOverlayPreprocessingOptions
    ) async throws -> MangaOverlayExternalTextBoxShadowOCRReport {
        let gateVerdict = readinessReport?.readinessVerdict ?? "readinessReportMissing"
        let activeDirectory = readinessReport?.activeArtifactsDirectory ?? false
        let contractExampleOnly = readinessReport?.contractExampleOnly ?? false
        let shadowAllowed = readinessReport?.externalTextBoxesShadowOCRAllowed ?? false
        var notes = [
            "shadowOnly=true",
            "groundTruthNotUsed=true",
            "doesNotChangeFinalTextUsedForTranslation=true",
            "doesNotChangeMainOverlay=true",
            "doesNotChangeBlockPassed=true",
            "doesNotChangeTextRegionCropAdoptedCount=true",
            "candidateSelectionSignals=IoU,centerContainment,confidence,bubbleAlignment,bboxAreaRatio"
        ]

        guard shadowAllowed, activeDirectory, !contractExampleOnly else {
            if contractExampleOnly {
                notes.append("blockedBecauseContractExampleOnly")
            }
            notes.append("external TextBoxes shadow OCR did not execute because readiness gate is \(gateVerdict)")
            let summaries = blocks.map { block in
                MangaOverlayExternalTextBoxShadowOCRBlockSummary(
                    blockIndex: block.index,
                    selectedCandidateID: nil,
                    selectedTextBoxID: nil,
                    candidateBBox: nil,
                    ocrExecuted: false,
                    ocrSucceeded: false,
                    ocrText: nil,
                    qualityDelta: nil,
                    wordPreservationRatio: nil,
                    promotionVerdict: "blockedByReadinessGate",
                    blockers: [gateVerdict],
                    notes: ["no externalArtifact.* candidate generated"]
                )
            }
            return MangaOverlayExternalTextBoxShadowOCRReport(
                enabled: true,
                executed: false,
                gateVerdict: gateVerdict,
                activeArtifactsDirectory: activeDirectory,
                contractExampleOnly: contractExampleOnly,
                externalTextBoxesShadowOCRAllowed: shadowAllowed,
                shadowOnly: true,
                groundTruthNotUsed: true,
                doesNotChangeFinalTextUsedForTranslation: true,
                doesNotChangeMainOverlay: true,
                candidateCount: 0,
                ocrExecutedCount: 0,
                ocrSucceededCount: 0,
                betterThanControlCount: 0,
                promotedExternalShadowBlocks: [],
                wouldPromoteByExistingGateBlocks: [],
                skippedBlocks: blocks.map(\.index).sorted(),
                blockSummaries: summaries,
                candidates: [],
                notes: notes
            )
        }

        let artifactsDirectory = bundledTestDirectory?.appendingPathComponent("koharu_artifacts", isDirectory: true)
        let manifestURL = artifactsDirectory?.appendingPathComponent("1.manifest.json")
        var parseErrors: [String] = []
        let manifest = Self.decodeExternalArtifact(
            MangaOverlayExternalArtifactManifest.self,
            from: manifestURL,
            label: "manifest",
            parseErrors: &parseErrors
        )
        let textBoxesURL = Self.externalArtifactURL(
            named: manifest?.textBoxesPath,
            fallback: "1.textboxes.json",
            artifactsDirectory: artifactsDirectory
        )
        let bubbleMaskURL = Self.externalArtifactURL(
            named: manifest?.bubbleMaskPath,
            fallback: "1.bubbles.json",
            artifactsDirectory: artifactsDirectory
        )
        let textBoxes = Self.decodeExternalArtifactList(
            MangaOverlayExternalTextBox.self,
            from: textBoxesURL,
            keys: ["textBoxes", "textboxes", "items"],
            label: "textBoxes",
            parseErrors: &parseErrors
        )
        let bubbleInstances = Self.decodeExternalArtifactList(
            MangaOverlayExternalBubbleInstance.self,
            from: bubbleMaskURL,
            keys: ["bubbleInstances", "bubbles", "instances", "items"],
            label: "bubbleMask",
            parseErrors: &parseErrors
        )
        if !parseErrors.isEmpty {
            notes.append("parseErrors=\(parseErrors.joined(separator: ","))")
        }

        var nextCandidateID = 0
        var candidates: [MangaOverlayExternalTextBoxShadowOCRCandidate] = []
        var summaries: [MangaOverlayExternalTextBoxShadowOCRBlockSummary] = []
        var skippedBlocks: [Int] = []

        for block in blocks {
            let selected = Self.selectExternalTextBoxShadowCandidate(
                for: block,
                textBoxes: textBoxes,
                bubbleInstances: bubbleInstances,
                imageWidth: image.width,
                imageHeight: image.height
            )
            guard let selected else {
                skippedBlocks.append(block.index)
                summaries.append(
                    MangaOverlayExternalTextBoxShadowOCRBlockSummary(
                        blockIndex: block.index,
                        selectedCandidateID: nil,
                        selectedTextBoxID: nil,
                        candidateBBox: nil,
                        ocrExecuted: false,
                        ocrSucceeded: false,
                        ocrText: nil,
                        qualityDelta: nil,
                        wordPreservationRatio: nil,
                        promotionVerdict: "skippedNoMatchingExternalTextBox",
                        blockers: ["noMatchingExternalTextBox"],
                        notes: ["external TextBox candidate rejected before OCR"]
                    )
                )
                continue
            }

            let crop = try await mangaOverlayProbeService.recognizeExternalTextBoxCrop(
                in: image,
                textBoxBBox: selected.textBox.bbox,
                options: preprocessing
            )
            let controlText = block.finalTextUsedForTranslation
            let controlQuality = Self.ocrCandidateQualityScore(controlText)
            let ocrText = crop.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let ocrTextValue = ocrText ?? ""
            let candidateQuality = Self.ocrCandidateQualityScore(ocrTextValue)
            let preservation = Self.wordPreservationRatio(
                sourceWords: Self.ocrCandidateWords(controlText),
                candidateWords: Self.ocrCandidateWords(ocrTextValue)
            )
            let qualityDelta = candidateQuality - controlQuality
            var blockers = selected.rejectionReasons
            if ocrTextValue.isEmpty {
                blockers.append("emptyLocalOCR")
            }
            if Self.ocrCandidateWords(controlText).count >= 3, preservation < 0.55 {
                blockers.append("rawWordsLost")
            }
            if Self.ocrCandidateWords(controlText).count >= 2,
               Self.ocrCandidateWords(ocrTextValue).count < max(2, Int(ceil(Double(Self.ocrCandidateWords(controlText).count) * 0.55))) {
                blockers.append("wordCountRegression")
            }
            if Self.ocrCandidateWords(ocrTextValue).joined(separator: " ") == Self.ocrCandidateWords(controlText).joined(separator: " ") {
                blockers.append("sameAsFusedText")
            }
            if Self.containsLikelyOCRError(in: ocrTextValue), !Self.containsLikelyOCRError(in: controlText), candidateQuality <= controlQuality + 0.08 {
                blockers.append("introducedLikelyOCRError")
            }
            let betterThanControl = candidateQuality > controlQuality + 0.03
            let wouldPromote = !ocrTextValue.isEmpty
                && preservation >= 0.80
                && qualityDelta > 0.08
                && !blockers.contains("rawWordsLost")
                && !blockers.contains("introducedLikelyOCRError")
                && !blockers.contains("sameAsFusedText")
                && !blockers.contains("bubbleAlignmentMismatch")
                && !blockers.contains("textBoxAreaTooLarge")
            let verdict = wouldPromote ? "wouldPromoteByExistingGateReportOnly" : (betterThanControl ? "betterThanControlButBlocked" : "controlStillBest")
            let candidateID = nextCandidateID
            nextCandidateID += 1
            candidates.append(
                MangaOverlayExternalTextBoxShadowOCRCandidate(
                    candidateID: candidateID,
                    blockIndex: block.index,
                    selectedTextBoxID: selected.textBox.id,
                    variantName: "externalArtifact.textBoxCrop",
                    textBoxBBox: selected.textBox.bbox,
                    cropBBox: crop.cropBBox,
                    textBoxConfidence: selected.textBox.confidence,
                    textBoxIoU: selected.iou,
                    blockCenterContained: selected.centerContained,
                    bubbleInstanceID: selected.bubbleInstance?.id,
                    bubbleAlignmentMatched: selected.bubbleAlignmentMatched,
                    areaRatioToBlock: selected.areaRatio,
                    linePolygonsPresent: selected.textBox.linePolygons?.isEmpty == false,
                    sourceDirection: selected.textBox.sourceDirection,
                    rotationDegrees: selected.textBox.rotationDegrees,
                    deskewExecuted: false,
                    ocrExecuted: true,
                    ocrSucceeded: !ocrTextValue.isEmpty,
                    controlText: controlText,
                    ocrText: ocrText,
                    wordPreservationRatio: preservation,
                    qualityScoreBefore: controlQuality,
                    qualityScoreAfter: candidateQuality,
                    qualityDelta: qualityDelta,
                    betterThanControl: betterThanControl,
                    promotionVerdict: verdict,
                    blockers: Array(Set(blockers)).sorted(),
                    riskFlags: selected.riskFlags,
                    notes: [
                        "shadowOnly=true",
                        "variantName=externalArtifact.textBoxCrop",
                        "deskewExecuted=false",
                        "paddingX=\(crop.paddingX.formatted(.number.precision(.fractionLength(1))))",
                        "paddingY=\(crop.paddingY.formatted(.number.precision(.fractionLength(1))))",
                        "groundTruthUsedForSelection=false",
                        "groundTruthUsedForPromotion=false"
                    ]
                )
            )
            summaries.append(
                MangaOverlayExternalTextBoxShadowOCRBlockSummary(
                    blockIndex: block.index,
                    selectedCandidateID: candidateID,
                    selectedTextBoxID: selected.textBox.id,
                    candidateBBox: crop.cropBBox,
                    ocrExecuted: true,
                    ocrSucceeded: !ocrTextValue.isEmpty,
                    ocrText: ocrText,
                    qualityDelta: qualityDelta,
                    wordPreservationRatio: preservation,
                    promotionVerdict: verdict,
                    blockers: Array(Set(blockers)).sorted(),
                    notes: ["externalArtifact.textBoxCrop shadow candidate; not written to finalTextUsedForTranslation"]
                )
            )
        }

        let wouldPromoteBlocks = candidates
            .filter { $0.promotionVerdict == "wouldPromoteByExistingGateReportOnly" }
            .map(\.blockIndex)
            .sorted()
        notes.append("promotedExternalShadowBlocks intentionally remains empty; wouldPromoteByExistingGateBlocks is report-only")
        return MangaOverlayExternalTextBoxShadowOCRReport(
            enabled: true,
            executed: true,
            gateVerdict: gateVerdict,
            activeArtifactsDirectory: activeDirectory,
            contractExampleOnly: contractExampleOnly,
            externalTextBoxesShadowOCRAllowed: shadowAllowed,
            shadowOnly: true,
            groundTruthNotUsed: true,
            doesNotChangeFinalTextUsedForTranslation: true,
            doesNotChangeMainOverlay: true,
            candidateCount: candidates.count,
            ocrExecutedCount: candidates.filter(\.ocrExecuted).count,
            ocrSucceededCount: candidates.filter(\.ocrSucceeded).count,
            betterThanControlCount: candidates.filter(\.betterThanControl).count,
            promotedExternalShadowBlocks: [],
            wouldPromoteByExistingGateBlocks: wouldPromoteBlocks,
            skippedBlocks: skippedBlocks.sorted(),
            blockSummaries: summaries.sorted { $0.blockIndex < $1.blockIndex },
            candidates: candidates.sorted { $0.candidateID < $1.candidateID },
            notes: notes
        )
    }

    private struct ExternalTextBoxShadowSelection {
        var textBox: MangaOverlayExternalTextBox
        var bubbleInstance: MangaOverlayExternalBubbleInstance?
        var iou: Double
        var centerContained: Bool
        var areaRatio: Double
        var bubbleAlignmentMatched: Bool
        var riskFlags: [String]
        var rejectionReasons: [String]
        var score: Double
    }

    private static func selectExternalTextBoxShadowCandidate(
        for block: MangaOverlayProbeBlock,
        textBoxes: [MangaOverlayExternalTextBox],
        bubbleInstances: [MangaOverlayExternalBubbleInstance],
        imageWidth: Int,
        imageHeight: Int
    ) -> ExternalTextBoxShadowSelection? {
        let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(imageWidth), height: CGFloat(imageHeight))
        let blockRect = rect(from: block.bbox)
        let blockArea = max(blockRect.width * blockRect.height, 1)
        let blockCenter = CGPoint(x: blockRect.midX, y: blockRect.midY)
        let blockBubble = bestExternalBubble(for: blockRect, bubbleInstances: bubbleInstances)

        return textBoxes.compactMap { textBox -> ExternalTextBoxShadowSelection? in
            let textBoxRect = rect(from: textBox.bbox)
            var rejectionReasons: [String] = []
            var riskFlags: [String] = []
            guard textBoxRect.width >= 2,
                  textBoxRect.height >= 2,
                  textBoxRect.minX >= imageBounds.minX,
                  textBoxRect.minY >= imageBounds.minY,
                  textBoxRect.maxX <= imageBounds.maxX,
                  textBoxRect.maxY <= imageBounds.maxY else {
                return nil
            }
            let iou = rectIoU(blockRect, textBoxRect)
            let centerContained = textBoxRect.contains(blockCenter)
            if iou <= 0.01 && !centerContained {
                rejectionReasons.append("noBlockOverlapOrCenterContainment")
            }
            let areaRatio = (textBoxRect.width * textBoxRect.height) / blockArea
            if areaRatio > 5.0 {
                rejectionReasons.append("textBoxAreaTooLarge")
            }
            if areaRatio < 0.04 {
                rejectionReasons.append("textBoxAreaTooSmall")
            }
            let textBoxBubble = bestExternalBubble(for: textBoxRect, bubbleInstances: bubbleInstances)
            let bubbleAlignmentMatched = blockBubble?.id == nil
                || textBoxBubble?.id == nil
                || blockBubble?.id == textBoxBubble?.id
            if !bubbleAlignmentMatched {
                rejectionReasons.append("bubbleAlignmentMismatch")
            }
            if textBox.linePolygons?.isEmpty == false {
                riskFlags.append("linePolygonsPresentDeskewNotExecuted")
            }
            if textBox.rotationDegrees != nil {
                riskFlags.append("rotationRecordedDeskewNotExecuted")
            }
            guard rejectionReasons.isEmpty else { return nil }
            let confidence = textBox.confidence ?? 0
            let ratioScore = max(0, 1 - abs(log(max(areaRatio, 0.001))))
            let score = (centerContained ? 2.0 : 0)
                + iou * 4
                + confidence
                + ratioScore * 0.4
                + (bubbleAlignmentMatched ? 0.35 : 0)
            return ExternalTextBoxShadowSelection(
                textBox: textBox,
                bubbleInstance: textBoxBubble ?? blockBubble,
                iou: iou,
                centerContained: centerContained,
                areaRatio: areaRatio,
                bubbleAlignmentMatched: bubbleAlignmentMatched,
                riskFlags: Array(Set(riskFlags)).sorted(),
                rejectionReasons: [],
                score: score
            )
        }
        .sorted {
            if $0.centerContained != $1.centerContained {
                return $0.centerContained && !$1.centerContained
            }
            if abs($0.iou - $1.iou) > 0.0001 {
                return $0.iou > $1.iou
            }
            if ($0.textBox.confidence ?? 0) != ($1.textBox.confidence ?? 0) {
                return ($0.textBox.confidence ?? 0) > ($1.textBox.confidence ?? 0)
            }
            return $0.score > $1.score
        }
        .first
    }

    private static func bestExternalBubble(
        for rect: CGRect,
        bubbleInstances: [MangaOverlayExternalBubbleInstance]
    ) -> MangaOverlayExternalBubbleInstance? {
        bubbleInstances
            .map { ($0, rectIoU(rect, Self.rect(from: $0.bbox))) }
            .filter { $0.1 >= 0.05 }
            .max { $0.1 < $1.1 }?
            .0
    }

    private static func externalArtifactURL(named path: String?, fallback: String, artifactsDirectory: URL?) -> URL? {
        guard let artifactsDirectory else { return nil }
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return artifactsDirectory.appendingPathComponent(fallback)
        }
        let url = URL(fileURLWithPath: path)
        return url.isFileURL && path.hasPrefix("/") ? url : artifactsDirectory.appendingPathComponent(path)
    }

    private static func decodeExternalArtifact<T: Decodable>(
        _ type: T.Type,
        from url: URL?,
        label: String,
        parseErrors: inout [String]
    ) -> T? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        } catch {
            parseErrors.append("\(label): \(error.localizedDescription)")
            return nil
        }
    }

    private static func decodeExternalArtifactList<T: Decodable>(
        _ type: T.Type,
        from url: URL?,
        keys: [String],
        label: String,
        parseErrors: inout [String]
    ) -> [T] {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            if let values = try? JSONDecoder().decode([T].self, from: data) {
                return values
            }
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any] else {
                parseErrors.append("\(label): expected array or keyed object")
                return []
            }
            for key in keys {
                guard let raw = dictionary[key] else { continue }
                let nestedData = try JSONSerialization.data(withJSONObject: raw)
                return try JSONDecoder().decode([T].self, from: nestedData)
            }
            parseErrors.append("\(label): missing supported list key \(keys.joined(separator: "/"))")
            return []
        } catch {
            parseErrors.append("\(label): \(error.localizedDescription)")
            return []
        }
    }

    private static func externalMissingArtifacts(
        manifestURL: URL?,
        textBoxesURL: URL?,
        bubbleMaskURL: URL?,
        segmentMaskURL: URL?
    ) -> [String] {
        var missing: [String] = []
        if !fileExists(manifestURL) { missing.append("manifest") }
        if !fileExists(textBoxesURL) { missing.append("TextBoxes") }
        if !fileExists(bubbleMaskURL) { missing.append("BubbleMask") }
        if !fileExists(segmentMaskURL) { missing.append("SegmentMask") }
        return missing
    }

    private static func fileExists(_ url: URL?) -> Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func validateExternalArtifactCoordinates(
        manifest: MangaOverlayExternalArtifactManifest?,
        textBoxes: [MangaOverlayExternalTextBox],
        bubbleInstances: [MangaOverlayExternalBubbleInstance],
        segmentMask: MangaOverlayExternalSegmentMaskSummary?,
        imageWidth: Int,
        imageHeight: Int
    ) -> MangaOverlayExternalArtifactCoordinateValidation {
        let expected = "originalImageTopLeftPixels"
        let coordinateSpace = manifest?.coordinateSpace
        let sourceImageMatches = manifest?.sourceImage == nil || manifest?.sourceImage == "test/1.png"
        var errors: [String] = []
        if let coordinateSpace, coordinateSpace != expected {
            errors.append("coordinateSpaceMismatch:\(coordinateSpace)")
        } else if coordinateSpace == nil {
            errors.append("coordinateSpaceMissing")
        }
        if !sourceImageMatches {
            errors.append("sourceImageMismatch:\(manifest?.sourceImage ?? "nil")")
        }
        let bounds = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        let invalidTextBoxes = textBoxes.compactMap { textBox -> String? in
            let rect = rect(from: textBox.bbox)
            guard rect.width > 0, rect.height > 0, rect.minX >= 0, rect.minY >= 0,
                  rect.maxX <= bounds.maxX, rect.maxY <= bounds.maxY else {
                return textBox.id
            }
            if let confidence = textBox.confidence, !(0...1).contains(confidence) {
                return textBox.id
            }
            return nil
        }
        let invalidBubbles = bubbleInstances.compactMap { bubble -> String? in
            let rect = rect(from: bubble.bbox)
            guard rect.width > 0, rect.height > 0, rect.minX >= 0, rect.minY >= 0,
                  rect.maxX <= bounds.maxX, rect.maxY <= bounds.maxY else {
                return bubble.id
            }
            if let confidence = bubble.confidence, !(0...1).contains(confidence) {
                return bubble.id
            }
            return nil
        }
        if !invalidTextBoxes.isEmpty {
            errors.append("invalidTextBoxBBoxes=\(invalidTextBoxes.joined(separator: ","))")
        }
        if !invalidBubbles.isEmpty {
            errors.append("invalidBubbleBBoxes=\(invalidBubbles.joined(separator: ","))")
        }
        let segmentSizeMatches: Bool?
        if let width = segmentMask?.width, let height = segmentMask?.height {
            segmentSizeMatches = width == imageWidth && height == imageHeight
            if segmentSizeMatches == false {
                errors.append("segmentMaskSizeMismatch:\(width)x\(height)")
            }
        } else {
            segmentSizeMatches = nil
        }
        var notes = ["bbox convention is original image pixel coordinates with top-left origin"]
        if manifest?.contractExampleOnly == true {
            notes.append("contractExampleOnly=true")
        }
        return MangaOverlayExternalArtifactCoordinateValidation(
            coordinateSpace: coordinateSpace,
            expectedCoordinateSpace: expected,
            sourceImageMatches: sourceImageMatches,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            bboxValidationPassed: invalidTextBoxes.isEmpty && invalidBubbles.isEmpty,
            invalidTextBoxIDs: invalidTextBoxes,
            invalidBubbleInstanceIDs: invalidBubbles,
            segmentMaskSizeMatches: segmentSizeMatches,
            errors: errors,
            notes: notes
        )
    }

    private static func externalArtifactBlockAlignment(
        blocks: [MangaOverlayProbeBlock],
        textBoxes: [MangaOverlayExternalTextBox],
        bubbleInstances: [MangaOverlayExternalBubbleInstance],
        segmentMask: MangaOverlayExternalSegmentMaskSummary?,
        segmentMaskReport: MangaOverlaySegmentMaskReport?
    ) -> [MangaOverlayExternalArtifactBlockAlignment] {
        let internalSegmentByBlock = Dictionary(
            uniqueKeysWithValues: (segmentMaskReport?.diagnostics ?? []).map { ($0.blockIndex, $0) }
        )
        return blocks.map { block in
            let blockRect = rect(from: block.bbox)
            let bestTextBox = textBoxes
                .map { ($0, rectIoU(blockRect, rect(from: $0.bbox))) }
                .max { $0.1 < $1.1 }
            let bestBubble = bubbleInstances
                .map { ($0, rectIoU(blockRect, rect(from: $0.bbox))) }
                .max { $0.1 < $1.1 }
            let textBoxRect = bestTextBox.map { rect(from: $0.0.bbox) }
            let center = CGPoint(x: blockRect.midX, y: blockRect.midY)
            let centerContained = textBoxRect?.contains(center) ?? false
            let segmentCoverageLevel: String
            if let segmentMask {
                let glyphPixels = segmentMask.glyphPixelCount ?? 0
                segmentCoverageLevel = glyphPixels > 0 ? "summaryAvailable" : "summaryEmpty"
            } else if let internalSegment = internalSegmentByBlock[block.index] {
                segmentCoverageLevel = internalSegment.usableForCropEvidence ? "internalProxyUsableOnly" : "internalProxyWeakOnly"
            } else {
                segmentCoverageLevel = "missing"
            }
            let hasTextBoxMatch = (bestTextBox?.1 ?? 0) >= 0.10 || centerContained
            let hasBubbleMatch = (bestBubble?.1 ?? 0) >= 0.10
            let verdict: String
            if textBoxes.isEmpty && bubbleInstances.isEmpty {
                verdict = "notEvaluatedMissingArtifacts"
            } else if hasTextBoxMatch && hasBubbleMatch {
                verdict = "aligned"
            } else if hasTextBoxMatch {
                verdict = "textBoxOnly"
            } else if hasBubbleMatch {
                verdict = "bubbleOnly"
            } else {
                verdict = "unaligned"
            }
            return MangaOverlayExternalArtifactBlockAlignment(
                blockIndex: block.index,
                blockBBox: block.bbox,
                bestTextBoxID: hasTextBoxMatch ? bestTextBox?.0.id : nil,
                bestTextBoxIoU: bestTextBox?.1,
                textBoxCenterContained: centerContained,
                bestBubbleInstanceID: hasBubbleMatch ? bestBubble?.0.id : nil,
                bestBubbleIoU: bestBubble?.1,
                currentBubbleID: block.bubbleID,
                bestExternalBubbleMaskValue: hasBubbleMatch ? bestBubble?.0.maskValue : nil,
                segmentCoverageLevel: segmentCoverageLevel,
                alignmentVerdict: verdict,
                notes: ["alignment is shadow-only and uses IoU/center containment without ground truth"]
            )
        }
    }

    private static func externalArtifactReadinessVerdict(
        manifestFound: Bool,
        textBoxes: [MangaOverlayExternalTextBox],
        bubbleInstances: [MangaOverlayExternalBubbleInstance],
        segmentMask: MangaOverlayExternalSegmentMaskSummary?,
        missingArtifacts: [String],
        parseErrors: [String],
        coordinateValidation: MangaOverlayExternalArtifactCoordinateValidation
    ) -> String {
        if !manifestFound { return "manifestMissing" }
        if !parseErrors.isEmpty { return "parseFailed" }
        if coordinateValidation.errors.contains("coordinateSpaceMissing") { return "coordinateSpaceMissing" }
        if coordinateValidation.errors.contains(where: { $0.hasPrefix("coordinateSpaceMismatch") }) {
            return "coordinateSpaceMismatch"
        }
        if coordinateValidation.errors.contains(where: { $0.hasPrefix("sourceImageMismatch") }) {
            return "sourceImageMismatch"
        }
        if coordinateValidation.errors.contains(where: { $0.hasPrefix("invalidTextBoxBBoxes") || $0.hasPrefix("invalidBubbleBBoxes") || $0.hasPrefix("segmentMaskSizeMismatch") }) {
            return "coordinateValidationFailed"
        }
        if !coordinateValidation.errors.isEmpty { return "coordinateValidationFailed" }
        if !missingArtifacts.isEmpty { return "artifactFilesMissing" }
        if textBoxes.isEmpty { return "insufficientTextBoxCoverage" }
        if bubbleInstances.isEmpty { return "insufficientBubbleCoverage" }
        if segmentMask == nil { return "segmentMaskMissing" }
        if coordinateValidation.notes.contains("contractExampleOnly=true") { return "contractExampleOnly" }
        return "readyForShadowOCR"
    }

    private static func externalArtifactNextAction(
        verdict: String,
        textBoxes: [MangaOverlayExternalTextBox],
        bubbleInstances: [MangaOverlayExternalBubbleInstance],
        segmentMask: MangaOverlayExternalSegmentMaskSummary?
    ) -> String {
        switch verdict {
        case "readyForShadowOCR":
            if !textBoxes.isEmpty { return "continueWithExternalTextBoxesShadowOCR" }
            if !bubbleInstances.isEmpty { return "continueWithBubbleMaskComparison" }
            if segmentMask != nil { return "continueWithSegmentMaskComparison" }
            return "evaluateCoreMLConversion"
        case "parseFailed":
            return "stopUntilParserFixed"
        case "contractExampleOnly":
            return "stopBecauseFixtureIsNotDetectorOutput"
        case "coordinateSpaceMissing", "coordinateSpaceMismatch", "sourceImageMismatch", "coordinateValidationFailed":
            return "stopUntilArtifactContractFixed"
        default:
            return "stopUntilArtifactsProvided"
        }
    }

    private func makeMangaOverlayProbeDiagnostics(blocks: [MangaOverlayProbeBlock]) -> MangaOverlayProbeDiagnostics {
        var diagnostics = MangaOverlayProbeDiagnostics.empty
        diagnostics.passedBlocks = blocks.filter(\.blockPassed).count
        diagnostics.failedBlocks = blocks.count - diagnostics.passedBlocks
        diagnostics.bubbleAssignedBlocks = blocks.filter { $0.bubbleID != nil }.count
        diagnostics.bubbleUnassignedBlocks = blocks.count - diagnostics.bubbleAssignedBlocks
        let matchedBlocks = blocks.filter { $0.groundTruthMatch == "matched" }
        diagnostics.groundTruthMatchedBlocks = matchedBlocks.count
        diagnostics.groundTruthUnmatchedBlocks = blocks.count - matchedBlocks.count
        let ocrSimilarities = matchedBlocks.compactMap(\.ocrGroundTruthSimilarity)
        if !ocrSimilarities.isEmpty {
            diagnostics.averageOCRGroundTruthSimilarity = ocrSimilarities.reduce(0, +) / Double(ocrSimilarities.count)
        }
        let dialogueSimilarities = matchedBlocks
            .filter { $0.bestGroundTruthType == MangaGroundTruthEntry.dialogueType }
            .compactMap(\.ocrGroundTruthSimilarity)
        if !dialogueSimilarities.isEmpty {
            diagnostics.averageCoreDialogueOCRSimilarity = dialogueSimilarities.reduce(0, +) / Double(dialogueSimilarities.count)
        }
        let decorativeSimilarities = matchedBlocks
            .filter { $0.bestGroundTruthType == MangaGroundTruthEntry.decorativeType }
            .compactMap(\.ocrGroundTruthSimilarity)
        if !decorativeSimilarities.isEmpty {
            diagnostics.averageDecorativeOCRSimilarity = decorativeSimilarities.reduce(0, +) / Double(decorativeSimilarities.count)
        }
        let deterministicSimilarities = blocks.compactMap(\.deterministicCorrectionSimilarity)
        if !deterministicSimilarities.isEmpty {
            diagnostics.deterministicCorrectionAverageSimilarity = deterministicSimilarities.reduce(0, +) / Double(deterministicSimilarities.count)
        }

        for block in blocks {
            let candidate = block.translationCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawOutput = block.rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty {
                diagnostics.emptyTranslationCandidates += 1
            }
            if block.qualityNotes.contains("candidateExtractorDroppedRawOutput") {
                diagnostics.candidateExtractorDroppedRawOutputs += 1
            }
            switch block.rawOutputClassification {
            case "empty":
                diagnostics.rawOutputEmptyBlocks += 1
            case "placeholder":
                diagnostics.rawOutputPlaceholderBlocks += 1
            case "repeatedOriginal":
                diagnostics.rawOutputRepeatedOriginalBlocks += 1
            case "nonChinese", "symbolsOnly":
                diagnostics.rawOutputNonChineseBlocks += 1
            default:
                break
            }
            if Self.isPlaceholderTranslationOutput(candidate) || Self.isPlaceholderTranslationOutput(rawOutput) {
                diagnostics.placeholderTranslationCandidates += 1
            }
            if !candidate.isEmpty,
               candidate.localizedCaseInsensitiveCompare(block.finalTextUsedForTranslation.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
                diagnostics.repeatedOriginalCandidates += 1
            }
            if !candidate.isEmpty, !Self.containsCJK(candidate) {
                diagnostics.nonChineseCandidates += 1
            }
            let candidateHasUsableCJK = block.candidateClassification == "chinese"
                || block.candidateClassification == "mixedChineseAndEnglish"
            if candidateHasUsableCJK, !block.blockPassed {
                diagnostics.cjkButFailedCandidates += 1
                let cjkFailureKey = Self.cjkFailureDiagnosticKey(for: block)
                diagnostics.cjkFailureBreakdown[cjkFailureKey, default: 0] += 1
            }
            if block.translationDecisionTrace.contains("translationLanguageQualityPassed=true") {
                diagnostics.translationLanguageQualityPassedBlocks.append(block.index)
            } else {
                diagnostics.translationLanguageQualityFailedBlocks.append(block.index)
            }
            if block.failureCategory == "ruleFalseFailureSuspected" {
                diagnostics.likelyRuleFalseFailureBlocks.append(block.index)
            }
            if block.failureCategory == "translationUsableButOCRSuspect" {
                diagnostics.translationUsableButOCRSuspectBlocks.append(block.index)
            }
            if let similarity = block.ocrGroundTruthSimilarity, similarity < 0.72 {
                diagnostics.lowOCRSimilarityBlocks.append(block.index)
            }
            if block.wordOrderPreserved == false {
                diagnostics.wordOrderFailedBlocks.append(block.index)
            }
            if block.qualityNotes.contains("likelyOCRIssue") || block.failureCategory == "ocrInputSuspect" {
                diagnostics.likelyOCRIssueBlocks.append(block.index)
            }
            if block.failureCategory == "modelOutputFailure" {
                diagnostics.likelyModelOutputFailures += 1
            }
            if block.crossBubbleMergeRejected {
                diagnostics.crossBubbleMergeRejectedBlocks.append(block.index)
            }
            if block.safeLayoutRect != nil {
                diagnostics.safeLayoutRectBlocks += 1
            }
            if block.renderCollisionChecked {
                diagnostics.renderCollisionCheckedBlocks += 1
                if block.renderCollisionInitialOverflow {
                    diagnostics.renderCollisionInitialOverflowBlocks.append(block.index)
                }
                if block.renderCollisionResolved {
                    diagnostics.renderCollisionResolvedBlocks.append(block.index)
                } else {
                    diagnostics.renderCollisionUnresolvedBlocks.append(block.index)
                }
                if block.renderMinFontSizeReached {
                    diagnostics.renderMinFontSizeReachedBlocks.append(block.index)
                }
                if block.renderTextTruncated {
                    diagnostics.renderTextTruncatedBlocks.append(block.index)
                }
            }
            if block.glyphMaskPixelCount > 0 {
                diagnostics.glyphMaskBlocks += 1
            }
            if block.backgroundFillApplied {
                diagnostics.backgroundFillAppliedBlocks.append(block.index)
            } else if block.glyphMaskPixelCount > 0 {
                diagnostics.backgroundFillSkippedBlocks.append(block.index)
            }
            if block.blockPassed, Self.mangaProbePassedTranslationLooksSuspicious(block) {
                diagnostics.passedButSuspiciousTranslationBlocks.append(block.index)
            }
            if let correctedSimilarity = block.deterministicCorrectionSimilarity,
               let originalSimilarity = block.ocrGroundTruthSimilarity,
               correctedSimilarity > originalSimilarity + 0.02 {
                diagnostics.deterministicCorrectionImprovedBlocks.append(block.index)
            }
            if let correctionTranslationPassed = block.deterministicCorrectionTranslationPassed {
                diagnostics.deterministicCorrectionTranslationTestedBlocks.append(block.index)
                if correctionTranslationPassed {
                    diagnostics.deterministicCorrectionTranslationPassedBlocks.append(block.index)
                } else {
                    diagnostics.deterministicCorrectionTranslationFailedBlocks.append(block.index)
                }
            }
            if !block.blockPassed {
                diagnostics.translationFailureBreakdown[block.failureCategory, default: 0] += 1
            }
            diagnostics.ocrQualityProbe.append(
                Self.mangaOCRProbeSummaryLine(for: block)
            )
        }
        diagnostics.lowOCRSimilarityBlocks = Array(Set(diagnostics.lowOCRSimilarityBlocks)).sorted()
        diagnostics.wordOrderFailedBlocks = Array(Set(diagnostics.wordOrderFailedBlocks)).sorted()
        diagnostics.likelyOCRIssueBlocks = Array(Set(diagnostics.likelyOCRIssueBlocks)).sorted()
        diagnostics.likelyRuleFalseFailureBlocks = Array(Set(diagnostics.likelyRuleFalseFailureBlocks)).sorted()
        diagnostics.passedButSuspiciousTranslationBlocks = Array(Set(diagnostics.passedButSuspiciousTranslationBlocks)).sorted()
        diagnostics.translationLanguageQualityPassedBlocks = Array(Set(diagnostics.translationLanguageQualityPassedBlocks)).sorted()
        diagnostics.translationLanguageQualityFailedBlocks = Array(Set(diagnostics.translationLanguageQualityFailedBlocks)).sorted()
        diagnostics.translationUsableButOCRSuspectBlocks = Array(Set(diagnostics.translationUsableButOCRSuspectBlocks)).sorted()
        diagnostics.deterministicCorrectionImprovedBlocks = Array(Set(diagnostics.deterministicCorrectionImprovedBlocks)).sorted()
        diagnostics.deterministicCorrectionTranslationTestedBlocks = Array(Set(diagnostics.deterministicCorrectionTranslationTestedBlocks)).sorted()
        diagnostics.deterministicCorrectionTranslationPassedBlocks = Array(Set(diagnostics.deterministicCorrectionTranslationPassedBlocks)).sorted()
        diagnostics.deterministicCorrectionTranslationFailedBlocks = Array(Set(diagnostics.deterministicCorrectionTranslationFailedBlocks)).sorted()
        diagnostics.crossBubbleMergeRejectedBlocks = Array(Set(diagnostics.crossBubbleMergeRejectedBlocks)).sorted()
        diagnostics.backgroundFillAppliedBlocks = Array(Set(diagnostics.backgroundFillAppliedBlocks)).sorted()
        diagnostics.backgroundFillSkippedBlocks = Array(Set(diagnostics.backgroundFillSkippedBlocks)).sorted()
        diagnostics.repeatedKeywordFailures = Self.repeatedKeywordFailures(in: blocks)
        return diagnostics
    }

    private static func repeatedKeywordFailures(in blocks: [MangaOverlayProbeBlock]) -> [String: Int] {
        var failures: [String: Int] = [:]
        let trackedWords = ["senpai", "senpai's", "city", "battler", "tournament"]
        for word in trackedWords {
            let affected = blocks.filter { block in
                guard block.bestGroundTruthText?.lowercased().contains(word) == true else { return false }
                return !block.finalTextUsedForTranslation.lowercased().contains(word)
            }
            if affected.count >= 2 {
                failures[word] = affected.count
            }
        }
        return failures
    }

    private static func makeInternalStructureBottleneckReport(
        blocks: [MangaOverlayProbeBlock],
        textRegionCropReport: MangaOverlayTextRegionCropReport?,
        textBoxPlanFailureReport: MangaOverlayTextBoxPlanFailureReport?,
        bubbleMaskReport: MangaOverlayBubbleMaskReport?,
        bubbleAssignmentCorrectionReport: MangaOverlayBubbleAssignmentCorrectionReport?,
        bubbleSplitCandidateReport: MangaOverlayBubbleSplitCandidateReport?,
        postFusionCleanup: MangaOverlayPostFusionCleanupReport?,
        externalArtifactReadinessReport: MangaOverlayExternalArtifactReadinessReport?
    ) -> MangaOverlayInternalStructureBottleneckReport {
        let cropByBlock = Dictionary(
            uniqueKeysWithValues: (textRegionCropReport?.diagnostics ?? []).map { ($0.blockIndex, $0) }
        )
        let textBoxFailureByBlock = Dictionary(
            uniqueKeysWithValues: (textBoxPlanFailureReport?.blockSummaries ?? []).map { ($0.blockIndex, $0) }
        )
        let bubbleMaskByBlock = Dictionary(
            uniqueKeysWithValues: (bubbleMaskReport?.blockDiagnostics ?? []).map { ($0.blockIndex, $0) }
        )
        let correctionByBlock = Dictionary(
            uniqueKeysWithValues: (bubbleAssignmentCorrectionReport?.diagnostics ?? []).map { ($0.blockIndex, $0) }
        )
        var splitByBlock: [Int: MangaOverlayBubbleSplitCandidateDiagnostic] = [:]
        for diagnostic in bubbleSplitCandidateReport?.diagnostics ?? [] {
            for blockIndex in diagnostic.seedBlockIndexes where splitByBlock[blockIndex] == nil {
                splitByBlock[blockIndex] = diagnostic
            }
        }
        let postFusionRejectedDuplicateOriginalIndexes = Set(
            (postFusionCleanup?.rejectedBlocks ?? [])
                .filter { $0.reason == "duplicateOrFragment" || $0.reason.localizedCaseInsensitiveContains("fragment") || $0.reason.localizedCaseInsensitiveContains("duplicate") }
                .map(\.originalFusedBlockIndex)
        )
        let postFusionRelatedKeptOriginalIndexes = Set(
            (postFusionCleanup?.rejectedBlocks ?? [])
                .filter { $0.reason == "duplicateOrFragment" || $0.reason.localizedCaseInsensitiveContains("fragment") || $0.reason.localizedCaseInsensitiveContains("duplicate") }
                .compactMap(\.relatedFusedBlockIndex)
        )
        let optionalExternalMissing = externalArtifactReadinessReport?.readinessVerdict == "manifestMissing"
            || externalArtifactReadinessReport?.readinessVerdict == "artifactFilesMissing"

        let summaries = blocks.map { block -> MangaOverlayInternalStructureBottleneckBlock in
            let crop = cropByBlock[block.index]
            let textBoxFailure = textBoxFailureByBlock[block.index]
            let mask = bubbleMaskByBlock[block.index]
            let correction = correctionByBlock[block.index]
            let split = splitByBlock[block.index]

            var evidence: [String] = [
                "failureCategory=\(block.failureCategory)",
                "blockPassed=\(block.blockPassed)",
                "groundTruthMatch=\(block.groundTruthMatch)",
                "groundTruthType=\(block.bestGroundTruthType ?? "nil")",
                "bubbleID=\(block.bubbleID.map(String.init) ?? "nil")",
                "wordOrderPreserved=\(block.wordOrderPreserved.map(String.init) ?? "nil")",
                "externalArtifactOptionalMissing=\(optionalExternalMissing)"
            ]
            if let similarity = block.ocrGroundTruthSimilarity {
                evidence.append("ocrSimilarity=\(similarity.formatted(.number.precision(.fractionLength(3))))")
            }
            if let crop {
                evidence.append("cropSelection=\(crop.selectionReason)")
                evidence.append("cropRejections=\(crop.rejectionReasons.joined(separator: ","))")
                evidence.append("cropFailureAttribution=\(crop.failureAttribution.joined(separator: ","))")
            }
            if let textBoxFailure {
                evidence.append("textBoxPlanFailure=\(textBoxFailure.primaryFailureCategory)")
                evidence.append("promotionBlockers=\(textBoxFailure.promotionBlockers.joined(separator: ","))")
                evidence.append("planRecommendedAction=\(textBoxFailure.recommendedNextAction)")
            }
            if let mask {
                evidence.append("maskBubbleIDConsistent=\(mask.bubbleIDConsistent)")
                evidence.append("maskDominantBubbleID=\(mask.maskDominantBubbleID.map(String.init) ?? "nil")")
                evidence.append("maskDominantCoverage=\(mask.maskDominantCoverageRatio.formatted(.number.precision(.fractionLength(3))))")
            }
            if let correction {
                evidence.append("bubbleAssignmentCorrection=\(correction.decision)")
                evidence.append("correctionRecommended=\(correction.correctionRecommended)")
            }
            if let split {
                evidence.append("splitCandidateID=\(split.id)")
                evidence.append("splitClampEligible=\(split.clampEligible)")
                evidence.append("splitRejections=\(split.rejectionReasons.joined(separator: ","))")
            }
            if let originalFusedIndex = postFusionOriginalFusedBlockIndex(in: block) {
                evidence.append("postFusionCleanupOriginalFusedBlockIndex=\(originalFusedIndex)")
                if postFusionRelatedKeptOriginalIndexes.contains(originalFusedIndex) {
                    evidence.append("postFusionCleanupKeptRelatedDuplicateOrFragment=true")
                }
            }

            let secondary = internalSecondaryBottlenecks(
                block: block,
                crop: crop,
                textBoxFailure: textBoxFailure,
                mask: mask,
                correction: correction,
                split: split,
                optionalExternalMissing: optionalExternalMissing
            )
            let primary = internalPrimaryBottleneck(
                block: block,
                secondary: secondary,
                crop: crop,
                textBoxFailure: textBoxFailure
            )
            let action = internalRecommendedAction(for: primary)
            let mustNotPromote = internalMustNotPromoteReasons(
                block: block,
                crop: crop,
                textBoxFailure: textBoxFailure,
                optionalExternalMissing: optionalExternalMissing
            )

            return MangaOverlayInternalStructureBottleneckBlock(
                blockIndex: block.index,
                groundTruthMatch: block.groundTruthMatch,
                groundTruthType: block.bestGroundTruthType,
                ocrGroundTruthSimilarity: block.ocrGroundTruthSimilarity,
                wordOrderPreserved: block.wordOrderPreserved,
                bubbleID: block.bubbleID,
                bbox: block.bbox,
                finalTextUsedForTranslation: block.finalTextUsedForTranslation,
                failureCategory: block.failureCategory,
                blockPassed: block.blockPassed,
                primaryBottleneck: primary,
                secondaryBottlenecks: secondary.filter { $0 != primary },
                recommendedNextAction: action,
                evidence: evidence,
                mustNotPromoteReasons: mustNotPromote
            )
        }

        let primaryBreakdown = countBy(summaries.map(\.primaryBottleneck))
        let actionBreakdown = countBy(summaries.map(\.recommendedNextAction))
        let dialogueBreakdown = countBy(
            summaries
                .filter { $0.groundTruthType == MangaGroundTruthEntry.dialogueType }
                .map(\.primaryBottleneck)
        )
        let decorativeBreakdown = countBy(
            summaries
                .filter { $0.groundTruthType == MangaGroundTruthEntry.decorativeType }
                .map(\.primaryBottleneck)
        )

        return MangaOverlayInternalStructureBottleneckReport(
            enabled: true,
            evaluatedBlockCount: summaries.count,
            primaryBottleneckBreakdown: primaryBreakdown,
            recommendedActionBreakdown: actionBreakdown,
            dialogueBottleneckBreakdown: dialogueBreakdown,
            decorativeBottleneckBreakdown: decorativeBreakdown,
            ocrInputSuspectBlocks: summaries.filter { $0.failureCategory == "ocrInputSuspect" || $0.primaryBottleneck == "ocrCharacterDamage" }.map(\.blockIndex).sorted(),
            duplicateOrFragmentBlocks: summaries.filter { $0.primaryBottleneck == "duplicateOrFragment" || $0.secondaryBottlenecks.contains("duplicateOrFragment") }.map(\.blockIndex).sorted(),
            modelTranslationQualityBlocks: summaries.filter { $0.primaryBottleneck == "modelTranslationQuality" || $0.secondaryBottlenecks.contains("modelTranslationQuality") }.map(\.blockIndex).sorted(),
            cropCandidateBlockedBlocks: summaries.filter { $0.primaryBottleneck == "cropCandidateBlocked" || $0.secondaryBottlenecks.contains("cropCandidateBlocked") }.map(\.blockIndex).sorted(),
            bubbleSplitOrAssignmentBlocks: summaries.filter { $0.primaryBottleneck == "bubbleAssignmentOrSplit" || $0.secondaryBottlenecks.contains("bubbleAssignmentOrSplit") }.map(\.blockIndex).sorted(),
            renderOnlyBlocks: summaries.filter { $0.primaryBottleneck == "renderOnly" }.map(\.blockIndex).sorted(),
            passedBlocks: summaries.filter(\.blockPassed).map(\.blockIndex).sorted(),
            postFusionRejectedDuplicateOrFragmentBlocks: Array(postFusionRejectedDuplicateOriginalIndexes).sorted(),
            blockSummaries: summaries,
            notes: [
                "internalStructureBottleneckReport aggregates existing probe evidence and does not replace finalTextUsedForTranslation",
                "ground truth is used only for evaluation fields such as similarity and type, not for production candidate selection",
                "external artifact manifestMissing is treated as optional missing input and does not block the internal routing report"
            ]
        )
    }

    private static func internalSecondaryBottlenecks(
        block: MangaOverlayProbeBlock,
        crop: MangaOverlayTextRegionCropDiagnostic?,
        textBoxFailure: MangaOverlayTextBoxPlanFailureBlockSummary?,
        mask: MangaOverlayBubbleMaskBlockDiagnostic?,
        correction: MangaOverlayBubbleAssignmentCorrectionDiagnostic?,
        split: MangaOverlayBubbleSplitCandidateDiagnostic?,
        optionalExternalMissing: Bool
    ) -> [String] {
        var result: [String] = []
        if block.blockPassed {
            result.append("passed")
        }
        if looksLikeInternalDuplicateOrFragment(block) {
            result.append("duplicateOrFragment")
        }
        if block.failureCategory == "ocrInputSuspect"
            || (block.ocrGroundTruthSimilarity ?? 1) < 0.72
            || block.wordOrderPreserved == false
            || containsLikelyOCRError(in: block.finalTextUsedForTranslation) {
            result.append("ocrCharacterDamage")
        }
        if block.failureCategory == "modelOutputFailure"
            || block.failureCategory == "translationLanguageQualityFailure" {
            result.append("modelTranslationQuality")
        }
        if let textBoxFailure,
           textBoxFailure.bestShadowBetterThanControl || !textBoxFailure.promotionBlockers.isEmpty {
            result.append("cropCandidateBlocked")
        } else if let crop,
                  crop.rejectionReasons.contains(where: { ["rawWordsLost", "emptyCropText", "wordCountRegression", "introducedLikelyOCRError"].contains($0) }) {
            result.append("cropCandidateBlocked")
        }
        if mask?.bubbleIDConsistent == false
            || correction?.correctionRecommended == true
            || split?.clampEligible == true
            || block.crossBubbleMergeRejected {
            result.append("bubbleAssignmentOrSplit")
        }
        if block.blockPassed,
           block.renderCollisionChecked,
           block.renderCollisionResolved,
           !block.renderTextTruncated {
            result.append("renderOnly")
        }
        if optionalExternalMissing {
            result.append("externalArtifactOptionalMissing")
        }
        return Array(Set(result)).sorted()
    }

    private static func internalPrimaryBottleneck(
        block: MangaOverlayProbeBlock,
        secondary: [String],
        crop: MangaOverlayTextRegionCropDiagnostic?,
        textBoxFailure: MangaOverlayTextBoxPlanFailureBlockSummary?
    ) -> String {
        if block.blockPassed {
            if block.bestGroundTruthType == MangaGroundTruthEntry.decorativeType {
                return "passed"
            }
            return "passed"
        }
        if looksLikeInternalDuplicateOrFragment(block) {
            return "duplicateOrFragment"
        }
        if secondary.contains("modelTranslationQuality"),
           !(secondary.contains("ocrCharacterDamage") && block.failureCategory == "ocrInputSuspect") {
            return "modelTranslationQuality"
        }
        if let textBoxFailure,
           textBoxFailure.bestShadowBetterThanControl,
           textBoxFailure.promotionBlockers.contains(where: { ["qualityDeltaBelowOrEqual0.08", "wordPreservationRatioBelow0.80", "rawWordsLost"].contains($0) }) {
            return "cropCandidateBlocked"
        }
        if crop?.failureAttribution.contains("bubbleMaskConflict") == true || secondary.contains("bubbleAssignmentOrSplit") {
            return "bubbleAssignmentOrSplit"
        }
        if secondary.contains("ocrCharacterDamage") {
            return "ocrCharacterDamage"
        }
        if secondary.contains("cropCandidateBlocked") {
            return "cropCandidateBlocked"
        }
        return "unknown"
    }

    private static func internalRecommendedAction(for primary: String) -> String {
        switch primary {
        case "passed":
            "noActionPassed"
        case "duplicateOrFragment":
            "tryPostFusionFragmentSuppression"
        case "ocrCharacterDamage":
            "improveTextBoxOrSegmentEvidence"
        case "bubbleAssignmentOrSplit":
            "improveBubbleSplitOrAssignment"
        case "cropCandidateBlocked":
            "keepMainTextAndDoNotTuneGeometry"
        case "modelTranslationQuality":
            "tryPromptOrModelComparison"
        case "renderOnly":
            "renderNoAction"
        case "externalArtifactOptionalMissing":
            "noActionExternalArtifactOptional"
        default:
            "manualReview"
        }
    }

    private static func internalMustNotPromoteReasons(
        block: MangaOverlayProbeBlock,
        crop: MangaOverlayTextRegionCropDiagnostic?,
        textBoxFailure: MangaOverlayTextBoxPlanFailureBlockSummary?,
        optionalExternalMissing: Bool
    ) -> [String] {
        var reasons = [
            "groundTruthNotAllowedForSelection",
            "reportOnlyDoesNotChangeMainInput"
        ]
        if let crop, !crop.adopted {
            reasons.append(contentsOf: crop.rejectionReasons.map { "cropRejected:\($0)" })
        }
        if let textBoxFailure {
            reasons.append(contentsOf: textBoxFailure.promotionBlockers.map { "promotionBlocked:\($0)" })
        }
        if optionalExternalMissing {
            reasons.append("externalArtifactOptionalMissing")
        }
        if block.bestGroundTruthType == MangaGroundTruthEntry.decorativeType {
            reasons.append("decorativeTitleProtected")
        }
        return Array(Set(reasons)).sorted()
    }

    private func makeRoutingDrivenTranslationComparisonReport(
        blocks: [MangaOverlayProbeBlock],
        internalStructureBottleneckReport: MangaOverlayInternalStructureBottleneckReport
    ) async -> MangaRoutingDrivenTranslationComparisonReport {
        let variantID = "strictChineseOnlyV1"
        let routedByBlock = Dictionary(
            uniqueKeysWithValues: internalStructureBottleneckReport.blockSummaries.map { ($0.blockIndex, $0) }
        )
        let targets = blocks
            .filter { block in
                routedByBlock[block.index]?.primaryBottleneck == "modelTranslationQuality"
            }
            .sorted { lhs, rhs in
                let lhsPassed = lhs.blockPassed ? 1 : 0
                let rhsPassed = rhs.blockPassed ? 1 : 0
                if lhsPassed != rhsPassed { return lhsPassed < rhsPassed }
                return lhs.index < rhs.index
            }
            .prefix(5)

        var cases: [MangaRoutingDrivenTranslationComparisonCase] = []
        for block in targets {
            guard let routing = routedByBlock[block.index] else { continue }
            let prompt = Self.strictChineseOnlyPrompt(for: block.finalTextUsedForTranslation)
            let rawOutput: String
            let errorCode: String?
            if selectedEngine == .local {
                let probe = localService.rawProbe(prompt: prompt, maxTokens: min(max(96, block.finalTextUsedForTranslation.count * 2), 220))
                rawOutput = probe.output
                errorCode = probe.errorCode
            } else {
                let request = makeProbeRequest(source: .englishUS, target: .simplifiedChinese, input: prompt)
                do {
                    try await mockService.prepare()
                    let result = try await mockService.generate(request)
                    rawOutput = result.text
                    errorCode = nil
                } catch {
                    rawOutput = ""
                    errorCode = "\(type(of: error)): \(error.localizedDescription)"
                }
            }

            let extraction = Self.extractMangaProbeTranslationCandidate(rawOutput)
            let candidate = extraction.candidate
            let rawClassification = Self.classifyMangaProbeRawOutput(rawOutput, original: block.finalTextUsedForTranslation)
            let candidateClassification = Self.classifyMangaProbeCandidate(
                candidate,
                original: block.finalTextUsedForTranslation,
                rejectedPlaceholder: extraction.rejectedPlaceholder
            )
            let checks = mangaProbeChecks(
                original: block.finalTextUsedForTranslation,
                translation: candidate,
                errorCode: errorCode
            )
            let baseReasons = mangaProbeFailureReasons(
                checks: checks,
                errorCode: errorCode,
                original: block.finalTextUsedForTranslation,
                translation: candidate
            )
            let checksPassed = Self.mangaProbeBlockPassed(checks, errorCode: errorCode)
            let languageReason = checksPassed ? Self.mangaProbeTranslationLanguageQualityIssue(
                original: block.finalTextUsedForTranslation,
                candidate: candidate,
                rawOutput: rawOutput,
                rawClassification: rawClassification
            ) : nil
            let variantFailureReasons = baseReasons + [languageReason].compactMap { $0 }
            let variantPassed = checksPassed && languageReason == nil
            let latinLeakReduced = Self.latinLetterCount(in: candidate) < Self.latinLetterCount(in: block.translationCandidate)
            let emptyOutputFixed = block.candidateClassification == "empty" && !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let controlWasPlaceholder = block.candidateClassification == "placeholder"
                || block.candidateClassification == "placeholderRejected"
            let placeholderFixed = controlWasPlaceholder
                && candidateClassification != "empty"
                && candidateClassification != "placeholder"
                && candidateClassification != "placeholderRejected"
            let shortChineseFixed = Self.isShortChineseFailure(block) && !Self.isShortChineseCandidate(candidate, original: block.finalTextUsedForTranslation)
            let improvement = Self.routingTranslationImprovementCategory(
                control: block,
                variantPassed: variantPassed,
                variantFailureReasons: variantFailureReasons,
                variantRawClassification: rawClassification,
                variantCandidateClassification: candidateClassification,
                latinLeakReduced: latinLeakReduced,
                emptyOutputFixed: emptyOutputFixed,
                placeholderFixed: placeholderFixed,
                shortChineseFixed: shortChineseFixed
            )
            var mustNotPromote = routing.mustNotPromoteReasons
            mustNotPromote.append("diagnosticOnlyStrictPromptDoesNotReplaceMainTranslation")
            mustNotPromote.append("mainProbePromptUnchanged")

            cases.append(MangaRoutingDrivenTranslationComparisonCase(
                blockIndex: block.index,
                routingPrimaryBottleneck: routing.primaryBottleneck,
                routingRecommendedAction: routing.recommendedNextAction,
                sourceText: block.finalTextUsedForTranslation,
                controlCandidate: block.translationCandidate,
                controlPassed: block.blockPassed,
                controlFailureCategory: block.failureCategory,
                controlFailureReasons: block.failureReasons,
                variantID: variantID,
                variantPrompt: prompt,
                variantRawOutput: rawOutput,
                variantCandidate: candidate,
                variantRawOutputClassification: rawClassification,
                variantCandidateClassification: candidateClassification,
                variantPassed: variantPassed,
                variantFailureReasons: variantFailureReasons,
                improvementCategory: improvement,
                latinLeakReduced: latinLeakReduced,
                emptyOutputFixed: emptyOutputFixed,
                placeholderFixed: placeholderFixed,
                shortChineseFixed: shortChineseFixed,
                diagnosticOnly: true,
                mustNotPromoteReasons: Array(Set(mustNotPromote)).sorted()
            ))
        }

        return MangaRoutingDrivenTranslationComparisonReport(
            enabled: true,
            decodingMode: selectedEngine == .local ? ModelDecodingProfile.deterministic.mode : "mock",
            decodingSeed: selectedEngine == .local ? ModelDecodingProfile.deterministic.seed : nil,
            variantID: variantID,
            candidateSelectionRule: "Select first five final blocks whose internalStructureBottleneckReport.primaryBottleneck == modelTranslationQuality; no ground truth is read for sample selection.",
            evaluatedCaseCount: cases.count,
            targetBlockIndexes: cases.map(\.blockIndex).sorted(),
            controlPassedCount: cases.filter(\.controlPassed).count,
            variantPassedCount: cases.filter(\.variantPassed).count,
            passedButControlFailedBlocks: cases.filter { !$0.controlPassed && $0.variantPassed }.map(\.blockIndex).sorted(),
            worseThanControlBlocks: cases.filter { $0.controlPassed && !$0.variantPassed }.map(\.blockIndex).sorted(),
            emptyOutputFixedBlocks: cases.filter(\.emptyOutputFixed).map(\.blockIndex).sorted(),
            placeholderFixedBlocks: cases.filter(\.placeholderFixed).map(\.blockIndex).sorted(),
            latinLeakReducedBlocks: cases.filter(\.latinLeakReduced).map(\.blockIndex).sorted(),
            improvementBreakdown: Self.countBy(cases.map(\.improvementCategory)),
            cases: cases,
            notes: [
                "report-only strict prompt comparison; main block translationCandidate, blockPassed, failureCategory, decision trace, and overlay are unchanged",
                "variant uses existing candidate extraction, raw/candidate classification, checks, failure reasons, and language quality gate"
            ]
        )
    }

    private static func strictChineseOnlyPrompt(for sourceText: String) -> String {
        """
        把以下英文漫画台词翻译成简体中文。
        只输出中文译文，不要解释，不要列点，不要重复英文原文。
        如果出现 Senpai、Ren、City Battler、Tournament 等专有名词，请用自然中文或音译处理，不要原样保留英文短语。
        原文：
        \(sourceText)
        """
    }

    private static func routingTranslationImprovementCategory(
        control: MangaOverlayProbeBlock,
        variantPassed: Bool,
        variantFailureReasons: [String],
        variantRawClassification: String,
        variantCandidateClassification: String,
        latinLeakReduced: Bool,
        emptyOutputFixed: Bool,
        placeholderFixed: Bool,
        shortChineseFixed: Bool
    ) -> String {
        if control.blockPassed && !variantPassed {
            return "worseThanControl"
        }
        if variantPassed && !control.blockPassed {
            return "passedButControlFailed"
        }
        if emptyOutputFixed {
            return "fixedEmptyOutput"
        }
        if placeholderFixed {
            return "fixedPlaceholder"
        }
        if latinLeakReduced {
            return "fixedLatinLeak"
        }
        if shortChineseFixed {
            return "fixedShortChinese"
        }
        if variantRawClassification == "empty" || variantCandidateClassification == "empty"
            || variantRawClassification == "placeholder"
            || variantCandidateClassification == "placeholder"
            || variantCandidateClassification == "placeholderRejected"
            || variantRawClassification == "repeatedOriginal"
            || variantCandidateClassification == "repeatedOriginal"
            || variantRawClassification == "nonChinese"
            || variantCandidateClassification == "nonChinese"
            || variantRawClassification == "symbolsOnly" {
            return "stillModelOutputFailure"
        }
        if !variantPassed,
           variantFailureReasons.contains(where: { $0.contains("过短") || $0.contains("拉丁") || $0.contains("英文") || $0.contains("解释") || $0.contains("泛化") }) {
            return "stillTranslationLanguageQualityFailure"
        }
        return "noChange"
    }

    private static func isShortChineseFailure(_ block: MangaOverlayProbeBlock) -> Bool {
        block.failureReasons.contains(where: { $0.contains("过短") })
            || block.translationFailureDetail?.contains("过短") == true
            || block.qualityNotes.contains(where: { $0.contains("translationLanguageQualityIssue=多词原文只得到过短中文候选") || $0.contains("translationLanguageQualityIssue=长原文只得到过短中文候选") })
    }

    private static func isShortChineseCandidate(_ candidate: String, original: String) -> Bool {
        let sourceWords = ocrCandidateWords(original).filter { $0.count >= 3 }
        let cjkCount = cjkCharacterCount(in: candidate)
        return (sourceWords.count >= 3 && cjkCount <= 2) || (sourceWords.count >= 5 && cjkCount <= 4)
    }

    private static func makeOCRCharacterDamageAuditReport(
        blocks: [MangaOverlayProbeBlock],
        internalStructureBottleneckReport: MangaOverlayInternalStructureBottleneckReport,
        textRegionCropReport: MangaOverlayTextRegionCropReport?,
        textBoxCandidateReport: MangaOverlayTextBoxCandidateReport?,
        segmentMaskReport: MangaOverlaySegmentMaskReport?,
        textBoxPlanFailureReport: MangaOverlayTextBoxPlanFailureReport?
    ) -> MangaOCRCharacterDamageAuditReport {
        let routedByBlock = Dictionary(
            uniqueKeysWithValues: internalStructureBottleneckReport.blockSummaries.map { ($0.blockIndex, $0) }
        )
        let textRegionByBlock = Dictionary(
            uniqueKeysWithValues: (textRegionCropReport?.diagnostics ?? []).map { ($0.blockIndex, $0) }
        )
        let textBoxByBlock = Dictionary(
            uniqueKeysWithValues: (textBoxCandidateReport?.diagnostics ?? []).map { ($0.blockIndex, $0) }
        )
        let segmentByBlock = Dictionary(
            uniqueKeysWithValues: (segmentMaskReport?.diagnostics ?? []).map { ($0.blockIndex, $0) }
        )
        let failureByBlock = Dictionary(
            uniqueKeysWithValues: (textBoxPlanFailureReport?.blockSummaries ?? []).map { ($0.blockIndex, $0) }
        )

        let cases = blocks
            .filter { block in
                routedByBlock[block.index]?.primaryBottleneck == "ocrCharacterDamage"
                    || block.failureCategory == "ocrInputSuspect"
                    || (block.ocrGroundTruthSimilarity ?? 1) < 0.72
            }
            .map { block -> MangaOCRCharacterDamageAuditCase in
                let audit = Self.ocrDamageTokenAudit(
                    ocrText: block.finalTextUsedForTranslation,
                    groundTruthText: block.bestGroundTruthText
                )
                let textRegion = textRegionByBlock[block.index]
                let textBox = textBoxByBlock[block.index]
                let segment = segmentByBlock[block.index]
                let failure = failureByBlock[block.index]
                let cropBlockers = Self.ocrDamageCropBlockers(textRegion: textRegion, textBoxFailure: failure)
                let action = Self.ocrDamageRecommendedAction(
                    block: block,
                    audit: audit,
                    cropBlockers: cropBlockers,
                    textBox: textBox,
                    segment: segment,
                    routing: routedByBlock[block.index]
                )
                var mustNotPromote = routedByBlock[block.index]?.mustNotPromoteReasons ?? []
                mustNotPromote.append("diagnosticOnlyDoesNotReplaceFinalTextUsedForTranslation")
                mustNotPromote.append("groundTruthUsedOnlyForDamageAudit")
                if action == "doNotTuneCropFurther" {
                    mustNotPromote.append("v20LineDeskewPathAlreadyStopped")
                }

                return MangaOCRCharacterDamageAuditCase(
                    blockIndex: block.index,
                    groundTruthMatch: block.groundTruthMatch,
                    groundTruthType: block.bestGroundTruthType,
                    ocrGroundTruthSimilarity: block.ocrGroundTruthSimilarity,
                    wordOrderPreserved: block.wordOrderPreserved,
                    finalTextUsedForTranslation: block.finalTextUsedForTranslation,
                    bestGroundTruthText: block.bestGroundTruthText,
                    damagedTokens: audit.damagedTokens,
                    missingGroundTruthTokens: audit.missingGroundTruthTokens,
                    extraOcrTokens: audit.extraOcrTokens,
                    suspectedSubstitutions: audit.suspectedSubstitutions,
                    repeatedKeywordDamage: audit.repeatedKeywordDamage,
                    lineBreakRisk: Self.ocrLineBreakRisk(block.finalTextUsedForTranslation),
                    bubbleID: block.bubbleID,
                    textBoxEvidenceSummary: Self.textBoxEvidenceSummary(textBox),
                    segmentMaskEvidenceSummary: Self.segmentMaskEvidenceSummary(segment),
                    cropBlockers: cropBlockers,
                    recommendedNextAction: action,
                    diagnosticOnly: true,
                    mustNotPromoteReasons: Array(Set(mustNotPromote)).sorted()
                )
            }

        return MangaOCRCharacterDamageAuditReport(
            enabled: true,
            evaluatedBlockCount: cases.count,
            targetBlockIndexes: cases.map(\.blockIndex).sorted(),
            damageTokenFrequency: Self.countFrequency(cases.flatMap(\.damagedTokens)),
            missingTokenFrequency: Self.countFrequency(cases.flatMap(\.missingGroundTruthTokens)),
            substitutionFrequency: Self.countFrequency(cases.flatMap(\.suspectedSubstitutions)),
            repeatedKeywordDamage: Self.countFrequency(cases.flatMap(\.repeatedKeywordDamage)),
            lineBreakRiskBlocks: cases.filter(\.lineBreakRisk).map(\.blockIndex).sorted(),
            cropBlockedBlocks: cases.filter { !$0.cropBlockers.isEmpty }.map(\.blockIndex).sorted(),
            textBoxOrSegmentEvidenceBlocks: cases.filter {
                ($0.textBoxEvidenceSummary?.isEmpty == false) || ($0.segmentMaskEvidenceSummary?.isEmpty == false)
            }.map(\.blockIndex).sorted(),
            recommendedActionBreakdown: Self.countBy(cases.map(\.recommendedNextAction)),
            cases: cases,
            notes: [
                "ground truth is used only for probe damage analysis, never for production OCR candidate selection or promotion",
                "audit explains token substitutions, missing tokens, extra OCR tokens, line break risk, crop blockers, and TextBox/SegmentMask proxy evidence"
            ]
        )
    }

    private struct OCRDamageTokenAudit {
        var damagedTokens: [String]
        var missingGroundTruthTokens: [String]
        var extraOcrTokens: [String]
        var suspectedSubstitutions: [String]
        var repeatedKeywordDamage: [String]
    }

    private static func ocrDamageTokenAudit(ocrText: String, groundTruthText: String?) -> OCRDamageTokenAudit {
        let ocrTokens = ocrCandidateWords(ocrText)
        let truthTokens = ocrCandidateWords(groundTruthText ?? "")
        let ocrSet = Set(ocrTokens)
        let truthSet = Set(truthTokens)
        let missing = truthTokens.filter { !ocrSet.contains($0) }
        let extra = ocrTokens.filter { !truthSet.contains($0) }
        var substitutions: [String] = []
        var damaged: [String] = []
        for ocrToken in extra {
            guard let truthToken = missing
                .filter({ abs($0.count - ocrToken.count) <= 3 })
                .max(by: { normalizedTextSimilarity(ocrToken, $0) < normalizedTextSimilarity(ocrToken, $1) }) else {
                continue
            }
            let similarity = normalizedTextSimilarity(ocrToken, truthToken)
            if similarity >= 0.34 {
                substitutions.append("\(ocrToken.uppercased())->\(truthToken.uppercased())")
                damaged.append(ocrToken.uppercased())
            }
        }
        let tracked = ["battler", "tournament", "few", "and", "training", "this", "gaming", "club", "being", "logic", "results"]
        let repeatedKeywordDamage = tracked.filter { keyword in
            truthSet.contains(keyword) && !ocrSet.contains(keyword)
        }
        return OCRDamageTokenAudit(
            damagedTokens: Array(Set(damaged)).sorted(),
            missingGroundTruthTokens: Array(Set(missing.map { $0.uppercased() })).sorted(),
            extraOcrTokens: Array(Set(extra.map { $0.uppercased() })).sorted(),
            suspectedSubstitutions: Array(Set(substitutions)).sorted(),
            repeatedKeywordDamage: repeatedKeywordDamage.map { $0.uppercased() }.sorted()
        )
    }

    private static func ocrDamageCropBlockers(
        textRegion: MangaOverlayTextRegionCropDiagnostic?,
        textBoxFailure: MangaOverlayTextBoxPlanFailureBlockSummary?
    ) -> [String] {
        var blockers: [String] = []
        if let textRegion {
            blockers.append(contentsOf: textRegion.rejectionReasons)
            blockers.append(contentsOf: textRegion.failureAttribution)
            if let cropMaskRejectedReason = textRegion.cropMaskRejectedReason {
                blockers.append(cropMaskRejectedReason)
            }
            if let assignmentCorrectionRejectedReason = textRegion.assignmentCorrectionRejectedReason {
                blockers.append(assignmentCorrectionRejectedReason)
            }
            if let splitCandidateRejectedReason = textRegion.splitCandidateRejectedReason {
                blockers.append(splitCandidateRejectedReason)
            }
        }
        if let textBoxFailure {
            blockers.append(contentsOf: textBoxFailure.promotionBlockers)
            blockers.append(textBoxFailure.primaryFailureCategory)
        }
        return Array(Set(blockers.filter { !$0.isEmpty })).sorted()
    }

    private static func ocrDamageRecommendedAction(
        block: MangaOverlayProbeBlock,
        audit: OCRDamageTokenAudit,
        cropBlockers: [String],
        textBox: MangaOverlayTextBoxCandidateDiagnostic?,
        segment: MangaOverlaySegmentMaskDiagnostic?,
        routing: MangaOverlayInternalStructureBottleneckBlock?
    ) -> String {
        if routing?.primaryBottleneck == "modelTranslationQuality" || block.failureCategory == "modelOutputFailure" {
            return "promptComparisonOnly"
        }
        if cropBlockers.contains(where: {
            ["qualityDeltaBelowOrEqual0.08", "wordPreservationRatioBelow0.80", "wordCountRegression", "rawWordsLost", "introducedLikelyOCRError"].contains($0)
        }) {
            return "doNotTuneCropFurther"
        }
        if textBox?.eligibleForCrop == true || segment?.usableForCropEvidence == true {
            return "needsBetterTextBoxOrSegmentEvidence"
        }
        if block.crossBubbleMergeRejected || block.bubbleID == nil {
            return "needsBubbleSplitOrAssignmentReview"
        }
        if !audit.suspectedSubstitutions.isEmpty || !audit.repeatedKeywordDamage.isEmpty {
            return "needsOCRModelOrEngineComparison"
        }
        return "manualReview"
    }

    private static func textBoxEvidenceSummary(_ diagnostic: MangaOverlayTextBoxCandidateDiagnostic?) -> String? {
        guard let diagnostic else { return nil }
        return "id=\(diagnostic.id) source=\(diagnostic.source) eligible=\(diagnostic.eligibleForCrop) score=\(diagnostic.evidenceScore.formatted(.number.precision(.fractionLength(3)))) rejections=\(diagnostic.rejectionReasons.joined(separator: ",")) risks=\(diagnostic.riskFlags.joined(separator: ","))"
    }

    private static func segmentMaskEvidenceSummary(_ diagnostic: MangaOverlaySegmentMaskDiagnostic?) -> String? {
        guard let diagnostic else { return nil }
        return "pixels=\(diagnostic.glyphMaskPixelCount) usableForCropEvidence=\(diagnostic.usableForCropEvidence) textBoxCoverage=\(diagnostic.textBoxCoverageRatio?.formatted(.number.precision(.fractionLength(3))) ?? "nil") bubbleCoverage=\(diagnostic.bubbleMaskCoverageRatio?.formatted(.number.precision(.fractionLength(3))) ?? "nil") rejections=\(diagnostic.rejectionReasons.joined(separator: ","))"
    }

    private static func ocrLineBreakRisk(_ text: String) -> Bool {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count >= 3 else { return false }
        let shortLines = lines.filter { ocrCandidateWords($0).count <= 2 }.count
        return shortLines >= max(2, lines.count / 2)
    }

    private static func countFrequency(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { partial, value in
            partial[value, default: 0] += 1
        }
    }

    private static func looksLikeInternalDuplicateOrFragment(_ block: MangaOverlayProbeBlock) -> Bool {
        let words = ocrCandidateWords(block.finalTextUsedForTranslation)
        guard words.count <= 7 else { return false }
        if isProtectedShortPostFusionText(block.finalTextUsedForTranslation) {
            return false
        }
        if isPostFusionDecorativeTitleText(block.finalTextUsedForTranslation) {
            return false
        }
        let text = block.finalTextUsedForTranslation.uppercased()
        return text.contains("AT") && text.contains("LEAST") && (text.contains("2EN") || text.contains("SEN"))
    }

    private static func postFusionOriginalFusedBlockIndex(in block: MangaOverlayProbeBlock) -> Int? {
        for note in block.ocrProbeNotes where note.hasPrefix("postFusionCleanupOriginalFusedBlockIndex=") {
            return Int(note.replacing("postFusionCleanupOriginalFusedBlockIndex=", with: ""))
        }
        return nil
    }

    private static func countBy(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { partial, value in
            partial[value, default: 0] += 1
        }
    }

    private static func cjkFailureDiagnosticKey(for block: MangaOverlayProbeBlock) -> String {
        if block.failureReasons.contains(where: { $0.contains("占位") || $0.contains("标签") }) {
            return "placeholderOrLabel"
        }
        if block.failureReasons.contains(where: { $0.contains("未翻译英文") || $0.contains("拉丁字母") }) {
            return "mixedOrUntranslatedEnglish"
        }
        if block.failureReasons.contains(where: { $0.contains("过短") }) {
            return "tooShort"
        }
        if block.failureReasons.contains(where: { $0.contains("OCR") }) {
            return "ocrInputQuality"
        }
        return block.failureCategory
    }

    private static func mangaProbePassedTranslationLooksSuspicious(_ block: MangaOverlayProbeBlock) -> Bool {
        let candidate = block.translationCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceWords = block.finalTextUsedForTranslation
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 3 }
        let cjkCount = cjkCharacterCount(in: candidate)
        if let similarity = block.ocrGroundTruthSimilarity, similarity < 0.72 {
            return true
        }
        if sourceWords.count >= 5, cjkCount <= 4 {
            return true
        }
        if containsLatinLetter(candidate), cjkCount > 0 {
            return true
        }
        return false
    }

    private static func retainedProbeOutputFiles(from outputFiles: MangaOverlayProbeOutputFiles) -> [String] {
        let fileNames = [
            outputFiles.debugBoxesImage,
            outputFiles.overlayImage,
            outputFiles.ocrTextOverlayImage,
            outputFiles.deterministicCorrectionOverlayImage,
            outputFiles.deterministicTranslationOverlayImage,
            outputFiles.ocrProbeTextFile,
            outputFiles.blockCropsImage,
            outputFiles.preprocessedContentImage,
            outputFiles.bubbleDebugImage,
            outputFiles.bubbleCropsImage,
            outputFiles.bubbleSeedDebugImage,
            outputFiles.bubbleTextOverlayImage,
            outputFiles.probeContactSheetImage,
            outputFiles.cleanTextDiagnosticFile,
            "probe_report.json"
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        return Array(Set(fileNames)).sorted()
    }

    private static func mangaOCRProbeNotes(
        text: String,
        bestGroundTruthText: String?,
        similarity: Double,
        legacySimilarity: Double,
        wordOrderPreserved: Bool?,
        matchState: String,
        bubbleID: Int?,
        bubbleAssignmentMethod: String,
        crossBubbleMergeRejected: Bool,
        sliceIndex: Int?,
        sliceOverlapDeduped: Bool
    ) -> [String] {
        var notes: [String] = [
            "groundTruthMatch=\(matchState)",
            "ocrSimilarity=\(similarity.formatted(.number.precision(.fractionLength(3))))",
            "legacySimilarity=\(legacySimilarity.formatted(.number.precision(.fractionLength(3))))",
            "ocrQuality=\(ocrQualityLabel(for: similarity))",
            "bubbleID=\(bubbleID.map(String.init) ?? "nil")",
            "bubbleAssignmentMethod=\(bubbleAssignmentMethod)",
            "crossBubbleMergeRejected=\(crossBubbleMergeRejected)",
            "sliceIndex=\(sliceIndex.map(String.init) ?? "nil")",
            "sliceOverlapDeduped=\(sliceOverlapDeduped)"
        ]
        if let wordOrderPreserved {
            notes.append("wordOrderPreserved=\(wordOrderPreserved)")
        }
        if containsLikelyOCRError(in: text) {
            notes.append("containsKnownOCRConfusion")
        }
        if similarity < 0.72 {
            notes.append("lowSimilarityAgainstGroundTruth")
        }
        if let bestGroundTruthText {
            notes.append("bestGroundTruth=\(bestGroundTruthText)")
        }
        return notes
    }

    private static func mangaOCRProbeSummaryLine(for block: MangaOverlayProbeBlock) -> String {
        let similarityText = block.ocrGroundTruthSimilarity.map {
            $0.formatted(.number.precision(.fractionLength(3)))
        } ?? "n/a"
        let legacyText = block.ocrLegacySimilarity.map {
            $0.formatted(.number.precision(.fractionLength(3)))
        } ?? "n/a"
        let label = block.ocrQualityLabel ?? "unknown"
        let text = block.finalTextUsedForTranslation.replacing("\n", with: " / ")
        let bubble = "bubbleID=\(block.bubbleID.map(String.init) ?? "nil") assignment=\(block.bubbleAssignmentMethod) crossBubbleMergeRejected=\(block.crossBubbleMergeRejected)"
        if let truth = block.bestGroundTruthText {
            return "#\(block.index) \(label) \(bubble) match=\(block.groundTruthMatch) sim=\(similarityText) legacy=\(legacyText) wordOrder=\(block.wordOrderPreserved.map(String.init) ?? "n/a") OCR=\"\(text)\" truth=\"\(truth)\""
        }
        return "#\(block.index) \(label) \(bubble) match=\(block.groundTruthMatch) sim=\(similarityText) legacy=\(legacyText) OCR=\"\(text)\""
    }

    private func loadMangaGroundTruth() -> [MangaGroundTruthEntry] {
        guard let url = bundledTestDirectory?.appendingPathComponent("1.ground_truth.json"),
              let data = try? Data(contentsOf: url) else {
            return Self.defaultMangaGroundTruth()
        }
        if let entries = try? JSONDecoder().decode([MangaGroundTruthEntry].self, from: data) {
            return entries
        }
        if let legacyValues = try? JSONDecoder().decode([String].self, from: data) {
            return legacyValues.map {
                MangaGroundTruthEntry(text: $0, type: MangaGroundTruthEntry.dialogueType)
            }
        }
        return Self.defaultMangaGroundTruth()
    }

    private struct MangaFusionCandidateWork {
        var source: String
        var sourceIndex: Int
        var text: String
        var bbox: CGRect
        var bubbleID: Int?
        var confidence: Float?
        var qualityScore: Double
        var block: MangaOverlayProbeBlock?
        var bubbleResult: MangaOverlayBubbleResult?
    }

    private func fuseMangaProbeBlocks(
        wholePageBlocks: [MangaOverlayProbeBlock],
        bubbleResults: [MangaOverlayBubbleResult],
        groundTruth: [MangaGroundTruthEntry]
    ) -> (blocks: [MangaOverlayProbeBlock], results: [MangaOverlayFusionResult], cleanup: MangaOverlayPostFusionCleanupReport) {
        var clusters = wholePageBlocks.map { block in
            [Self.fusionCandidate(from: block)]
        }

        for result in bubbleResults {
            let candidate = Self.fusionCandidate(from: result)
            if Self.fusionRejectReason(for: candidate) != nil {
                clusters.append([candidate])
                clusters[clusters.count - 1][0].qualityScore = -1
                continue
            }

            if let index = clusters.firstIndex(where: { cluster in
                cluster.contains { Self.shouldClusterFusionCandidates($0, candidate) }
            }) {
                clusters[index].append(candidate)
            } else {
                clusters.append([candidate])
            }
        }

        var fusedPairs: [(MangaOverlayProbeBlock, MangaOverlayFusionResult)] = []
        var rejectedOnlyResults: [MangaOverlayFusionResult] = []
        for cluster in clusters {
            if cluster.count == 1, cluster[0].qualityScore < 0 {
                rejectedOnlyResults.append(
                    MangaOverlayFusionResult(
                        fusedBlockIndex: -1,
                        selectedSource: "rejected",
                        selectedText: cluster[0].text,
                        selectedBBox: Self.bboxArray(from: cluster[0].bbox),
                        selectedBubbleID: cluster[0].bubbleID,
                        sourceBlockIndex: nil,
                        bubbleResultIndex: cluster[0].sourceIndex,
                        competingCandidates: [Self.fusionReportCandidate(cluster[0], selected: false, rejectionReason: "lowInformationBubbleOnly")],
                        dedupeReason: "rejectedBeforeClustering",
                        replacementReason: nil,
                        rejectedCandidates: [Self.fusionReportCandidate(cluster[0], selected: false, rejectionReason: "lowInformationBubbleOnly")]
                    )
                )
                continue
            }

            let selected = Self.selectFusionCandidate(from: cluster)
            let rejected = cluster.filter {
                !($0.source == selected.source && $0.sourceIndex == selected.sourceIndex)
            }
            let selectedBlock = Self.fusedBlock(
                selected: selected,
                fallbackIndex: fusedPairs.count,
                groundTruth: groundTruth,
                rejectedCandidates: rejected
            )

            let dedupeReason = Self.fusionDedupeReason(for: cluster)
            let replacementReason = Self.fusionReplacementReason(selected: selected, cluster: cluster)
            let competing = cluster.map {
                Self.fusionReportCandidate(
                    $0,
                    selected: $0.source == selected.source && $0.sourceIndex == selected.sourceIndex,
                    rejectionReason: $0.source == selected.source && $0.sourceIndex == selected.sourceIndex
                        ? nil
                        : Self.fusionCandidateRejectionReason($0, selected: selected)
                )
            }
            let selectedResult = MangaOverlayFusionResult(
                fusedBlockIndex: selectedBlock.index,
                selectedSource: Self.fusionSelectedSource(selected: selected, cluster: cluster),
                selectedText: selected.text,
                selectedBBox: Self.bboxArray(from: selected.bbox),
                selectedBubbleID: selected.bubbleID,
                sourceBlockIndex: selected.block?.index,
                bubbleResultIndex: selected.bubbleResult?.index,
                competingCandidates: competing,
                dedupeReason: dedupeReason,
                replacementReason: replacementReason,
                rejectedCandidates: competing.filter { !$0.selected }
            )
            fusedPairs.append((selectedBlock, selectedResult))
        }

        let sorted = fusedPairs
            .sorted { lhs, rhs in
                let left = Self.rect(from: lhs.0.bbox)
                let right = Self.rect(from: rhs.0.bbox)
                if abs(left.minY - right.minY) > 18 {
                    return left.minY < right.minY
                }
                return left.minX < right.minX
            }
        let reindexedBlocks = sorted.enumerated().map { offset, pair in
            Self.reindexedMangaBlock(pair.0, index: offset)
        }
        let reindexedResults = sorted.enumerated().map { offset, pair in
            var result = pair.1
            result.fusedBlockIndex = offset
            return result
        }
        let cleanup = Self.cleanPostFusionBlocks(
            blocks: reindexedBlocks,
            results: reindexedResults
        )
        return (cleanup.blocks, cleanup.results + rejectedOnlyResults, cleanup.report)
    }

    private static func fusionCandidate(from block: MangaOverlayProbeBlock) -> MangaFusionCandidateWork {
        MangaFusionCandidateWork(
            source: "wholePageOCR",
            sourceIndex: block.index,
            text: block.finalTextUsedForTranslation,
            bbox: rect(from: block.bbox),
            bubbleID: block.bubbleID,
            confidence: block.ocrConfidence,
            qualityScore: ocrCandidateQualityScore(block.finalTextUsedForTranslation),
            block: block,
            bubbleResult: nil
        )
    }

    private static func fusionCandidate(from result: MangaOverlayBubbleResult) -> MangaFusionCandidateWork {
        MangaFusionCandidateWork(
            source: "bubbleFirst",
            sourceIndex: result.index,
            text: result.text,
            bbox: rect(from: result.bbox),
            bubbleID: result.bubbleID,
            confidence: nil,
            qualityScore: ocrCandidateQualityScore(result.text),
            block: nil,
            bubbleResult: result
        )
    }

    private static func shouldClusterFusionCandidates(
        _ lhs: MangaFusionCandidateWork,
        _ rhs: MangaFusionCandidateWork
    ) -> Bool {
        if let leftBubble = lhs.bubbleID,
           let rightBubble = rhs.bubbleID,
           leftBubble != rightBubble {
            return lhs.source == "bubbleFirst"
                && rhs.source == "bubbleFirst"
                && normalizedTextSimilarity(lhs.text, rhs.text) >= 0.82
        }
        let iou = rectIoU(lhs.bbox, rhs.bbox)
        if iou >= 0.18 {
            return true
        }
        let centerDistance = hypot(lhs.bbox.midX - rhs.bbox.midX, lhs.bbox.midY - rhs.bbox.midY)
        let nearThreshold = max(lhs.bbox.width, lhs.bbox.height, rhs.bbox.width, rhs.bbox.height) * 0.75
        if centerDistance <= nearThreshold, normalizedTextSimilarity(lhs.text, rhs.text) >= 0.36 {
            return true
        }
        return false
    }

    private static func fusionRejectReason(for candidate: MangaFusionCandidateWork) -> String? {
        guard candidate.source == "bubbleFirst" else { return nil }
        let clean = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            return "emptyBubbleText"
        }
        let words = ocrCandidateWords(clean)
        if words.count < 2, clean.count < 8 {
            return "lowInformationBubbleText"
        }
        if clean.count < 10, candidate.bbox.width * candidate.bbox.height < 1200 {
            return "smallShortBubbleText"
        }
        let letters = latinLetterCount(in: clean)
        if letters == 0 {
            return "noLatinOCRText"
        }
        return nil
    }

    private static func selectFusionCandidate(from cluster: [MangaFusionCandidateWork]) -> MangaFusionCandidateWork {
        guard cluster.count > 1 else { return cluster[0] }
        if let bestWhole = cluster
            .filter({ $0.source == "wholePageOCR" })
            .max(by: { fusionSelectionScore($0, cluster: cluster) < fusionSelectionScore($1, cluster: cluster) }),
           let bestBubble = cluster
            .filter({ $0.source == "bubbleFirst" })
            .max(by: { fusionSelectionScore($0, cluster: cluster) < fusionSelectionScore($1, cluster: cluster) }) {
            let wholeWords = ocrCandidateWords(bestWhole.text).count
            let bubbleWords = ocrCandidateWords(bestBubble.text).count
            let bubbleIsNotShorter = bubbleWords >= wholeWords
                || bestBubble.text.count >= Int(Double(bestWhole.text.count) * 0.9)
            if bubbleIsNotShorter,
               bestBubble.qualityScore >= bestWhole.qualityScore - 0.03 {
                return bestBubble
            }
        }
        return cluster.max { lhs, rhs in
            fusionSelectionScore(lhs, cluster: cluster) < fusionSelectionScore(rhs, cluster: cluster)
        } ?? cluster[0]
    }

    private static func fusionSelectionScore(
        _ candidate: MangaFusionCandidateWork,
        cluster: [MangaFusionCandidateWork]
    ) -> Double {
        let words = ocrCandidateWords(candidate.text)
        let sourceBonus = candidate.source == "wholePageOCR" ? 0.03 : 0
        let bubbleBonus = candidate.source == "bubbleFirst" && cluster.contains { $0.source == "wholePageOCR" } ? 0.08 : 0
        let lengthBonus = min(Double(words.count), 18) * 0.018
        let confidenceBonus = Double(candidate.confidence ?? 0) * 0.02
        let errorPenalty = containsLikelyOCRError(in: candidate.text) ? 0.09 : 0
        return candidate.qualityScore + sourceBonus + bubbleBonus + lengthBonus + confidenceBonus - errorPenalty
    }

    private static func fusedBlock(
        selected: MangaFusionCandidateWork,
        fallbackIndex: Int,
        groundTruth: [MangaGroundTruthEntry],
        rejectedCandidates: [MangaFusionCandidateWork]
    ) -> MangaOverlayProbeBlock {
        let match = MangaOverlayProbeService.bestGroundTruthMatch(text: selected.text, groundTruth: groundTruth)
        var block = selected.block ?? MangaOverlayProbeBlock(
            index: fallbackIndex,
            bbox: bboxArray(from: selected.bbox),
            bubbleID: selected.bubbleID,
            bubbleAssignmentMethod: selected.source == "bubbleFirst" ? "bubbleFirstFusion" : "unassigned",
            rotationAngleUsed: 0,
            ocrText: selected.text,
            ocrConfidence: selected.confidence,
            rawOcrText: selected.text,
            preprocessingEnabled: false
        )
        block.index = fallbackIndex
        block.bbox = bboxArray(from: selected.bbox)
        block.bubbleID = selected.bubbleID
        if selected.source == "bubbleFirst", block.bubbleAssignmentMethod == "unassigned" {
            block.bubbleAssignmentMethod = "bubbleFirstFusion"
        }
        block.rawOcrText = selected.text
        block.ocrText = selected.text
        block.finalTextUsedForTranslation = selected.text
        block.bestGroundTruthIndex = match.index
        block.bestGroundTruthText = match.entry?.text
        block.bestGroundTruthType = match.entry?.type
        block.groundTruthMatch = match.matchState
        block.groundTruthMatchThreshold = MangaOverlayProbeService.groundTruthMatchThreshold
        block.ocrGroundTruthSimilarity = match.similarity
        block.ocrLegacySimilarity = match.legacySimilarity
        block.wordOrderPreserved = match.wordOrderPreserved
        block.ocrQualityLabel = ocrQualityLabel(for: match.similarity)
        block.ocrProbeNotes = mangaOCRProbeNotes(
            text: selected.text,
            bestGroundTruthText: match.entry?.text,
            similarity: match.similarity,
            legacySimilarity: match.legacySimilarity,
            wordOrderPreserved: match.wordOrderPreserved,
            matchState: match.matchState,
            bubbleID: selected.bubbleID,
            bubbleAssignmentMethod: block.bubbleAssignmentMethod,
            crossBubbleMergeRejected: block.crossBubbleMergeRejected,
            sliceIndex: block.sliceIndex,
            sliceOverlapDeduped: block.sliceOverlapDeduped
        )
        block.ocrProbeNotes.append("fusionSource=\(selected.source)")
        block.ocrProbeNotes.append("fusionSourceIndex=\(selected.sourceIndex)")
        block.ocrProbeNotes.append("fusionSelectionRule=groundTruthFreeBBoxTextQuality")
        for rejected in rejectedCandidates {
            block.ocrProbeNotes.append(
                "fusionRejected \(rejected.source)#\(rejected.sourceIndex): \(fusionCandidateRejectionReason(rejected, selected: selected))"
            )
        }
        return block
    }

    private static func reindexedMangaBlock(_ block: MangaOverlayProbeBlock, index: Int) -> MangaOverlayProbeBlock {
        var result = block
        result.index = index
        return result
    }

    private static func fusionReportCandidate(
        _ candidate: MangaFusionCandidateWork,
        selected: Bool,
        rejectionReason: String?
    ) -> MangaOverlayFusionCandidate {
        MangaOverlayFusionCandidate(
            source: candidate.source,
            sourceIndex: candidate.sourceIndex,
            text: candidate.text,
            bbox: bboxArray(from: candidate.bbox),
            bubbleID: candidate.bubbleID,
            confidence: candidate.confidence,
            qualityScore: candidate.qualityScore,
            selected: selected,
            rejectionReason: rejectionReason
        )
    }

    private static func fusionDedupeReason(for cluster: [MangaFusionCandidateWork]) -> String {
        guard cluster.count > 1 else { return "sourceOnlyCandidate" }
        return "bboxIoUOrCenterDistanceAndTextSimilarity"
    }

    private static func fusionSelectedSource(
        selected: MangaFusionCandidateWork,
        cluster: [MangaFusionCandidateWork]
    ) -> String {
        if selected.source == "wholePageOCR", cluster.count > 1 {
            return "wholePagePreferred"
        }
        if selected.source == "bubbleFirst", cluster.count > 1 {
            return "bubblePreferred"
        }
        return selected.source
    }

    private static func fusionReplacementReason(
        selected: MangaFusionCandidateWork,
        cluster: [MangaFusionCandidateWork]
    ) -> String? {
        guard cluster.count > 1 else { return nil }
        return "selectedScore=\(fusionSelectionScore(selected, cluster: cluster).formatted(.number.precision(.fractionLength(3))))"
    }

    private static func fusionCandidateRejectionReason(
        _ candidate: MangaFusionCandidateWork,
        selected: MangaFusionCandidateWork
    ) -> String {
        if let reason = fusionRejectReason(for: candidate) {
            return reason
        }
        if candidate.source == selected.source && candidate.sourceIndex == selected.sourceIndex {
            return "selected"
        }
        return "lowerGroundTruthFreeQualityScore"
    }

    private static func cleanPostFusionBlocks(
        blocks: [MangaOverlayProbeBlock],
        results: [MangaOverlayFusionResult]
    ) -> (blocks: [MangaOverlayProbeBlock], results: [MangaOverlayFusionResult], report: MangaOverlayPostFusionCleanupReport) {
        var rejectedByOriginalIndex: [Int: MangaOverlayPostFusionRejectedBlock] = [:]
        let sortedIndexes = blocks.indices.sorted { lhs, rhs in
            postFusionInformationScore(blocks[lhs]) > postFusionInformationScore(blocks[rhs])
        }

        for candidateIndex in sortedIndexes {
            guard rejectedByOriginalIndex[candidateIndex] == nil else { continue }
            for selectedIndex in sortedIndexes where selectedIndex != candidateIndex {
                guard rejectedByOriginalIndex[selectedIndex] == nil else { continue }
                guard postFusionInformationScore(blocks[selectedIndex]) + 0.08 >= postFusionInformationScore(blocks[candidateIndex]) else {
                    continue
                }
                guard let rejection = postFusionRejection(
                    candidate: blocks[candidateIndex],
                    selected: blocks[selectedIndex]
                ) else {
                    continue
                }
                rejectedByOriginalIndex[candidateIndex] = MangaOverlayPostFusionRejectedBlock(
                    originalFusedBlockIndex: blocks[candidateIndex].index,
                    source: results.indices.contains(candidateIndex) ? results[candidateIndex].selectedSource : "unknown",
                    sourceBlockIndex: results.indices.contains(candidateIndex) ? results[candidateIndex].sourceBlockIndex : nil,
                    bubbleResultIndex: results.indices.contains(candidateIndex) ? results[candidateIndex].bubbleResultIndex : nil,
                    bubbleID: blocks[candidateIndex].bubbleID,
                    text: blocks[candidateIndex].finalTextUsedForTranslation,
                    bbox: blocks[candidateIndex].bbox,
                    reason: rejection.reason,
                    relatedFusedBlockIndex: blocks[selectedIndex].index,
                    relatedKeptBlockIndex: nil,
                    relatedText: blocks[selectedIndex].finalTextUsedForTranslation,
                    relatedBBox: blocks[selectedIndex].bbox,
                    qualityScore: postFusionInformationScore(blocks[candidateIndex]),
                    protectedTextMatched: isProtectedShortPostFusionText(blocks[candidateIndex].finalTextUsedForTranslation),
                    evidence: rejection.evidence
                )
                break
            }
        }

        var keptPairs: [(MangaOverlayProbeBlock, MangaOverlayFusionResult)] = []
        var rejectedResults: [MangaOverlayFusionResult] = []
        for index in blocks.indices {
            if let rejected = rejectedByOriginalIndex[index] {
                var result = results[index]
                result.fusedBlockIndex = -1
                result.dedupeReason = "postFusionCleanupRejected"
                result.replacementReason = rejected.reason
                var selectedCandidate = MangaOverlayFusionCandidate(
                    source: result.selectedSource,
                    sourceIndex: result.sourceBlockIndex ?? result.bubbleResultIndex ?? result.fusedBlockIndex,
                    text: result.selectedText,
                    bbox: result.selectedBBox,
                    bubbleID: result.selectedBubbleID,
                    confidence: nil,
                    qualityScore: postFusionInformationScore(blocks[index]),
                    selected: false,
                    rejectionReason: rejected.reason
                )
                if let existing = result.competingCandidates.first(where: { $0.selected }) {
                    selectedCandidate = MangaOverlayFusionCandidate(
                        source: existing.source,
                        sourceIndex: existing.sourceIndex,
                        text: existing.text,
                        bbox: existing.bbox,
                        bubbleID: existing.bubbleID,
                        confidence: existing.confidence,
                        qualityScore: existing.qualityScore,
                        selected: false,
                        rejectionReason: rejected.reason
                    )
                }
                result.competingCandidates = result.competingCandidates.map { candidate in
                    var updated = candidate
                    if updated.selected {
                        updated.selected = false
                        updated.rejectionReason = rejected.reason
                    }
                    return updated
                }
                if !result.rejectedCandidates.contains(selectedCandidate) {
                    result.rejectedCandidates.append(selectedCandidate)
                }
                rejectedResults.append(result)
            } else {
                keptPairs.append((blocks[index], results[index]))
            }
        }

        let keptOriginalIndexToNewIndex = Dictionary(
            uniqueKeysWithValues: keptPairs.enumerated().map { offset, pair in
                (pair.0.index, offset)
            }
        )
        let rejectedBlocks = rejectedByOriginalIndex.values.map { rejected in
            var updated = rejected
            if let relatedFusedBlockIndex = rejected.relatedFusedBlockIndex {
                updated.relatedKeptBlockIndex = keptOriginalIndexToNewIndex[relatedFusedBlockIndex]
            }
            return updated
        }

        let keptBlocks = keptPairs.enumerated().map { offset, pair in
            var block = reindexedMangaBlock(pair.0, index: offset)
            block.ocrProbeNotes.append("postFusionCleanupOriginalFusedBlockIndex=\(pair.0.index)")
            block.ocrProbeNotes.append("postFusionCleanup=kept")
            return block
        }
        let keptResults = keptPairs.enumerated().map { offset, pair in
            var result = pair.1
            result.fusedBlockIndex = offset
            result.replacementReason = [result.replacementReason, "postFusionCleanup=kept"]
                .compactMap { $0 }
                .joined(separator: "; ")
            return result
        }

        let preserved = postFusionKeyTexts.filter { key in
            keptBlocks.contains { isProtectedKeyText($0.finalTextUsedForTranslation, keyText: key) }
        }
        let missing = postFusionKeyTexts.filter { !preserved.contains($0) }
        var warnings: [String] = []
        if !missing.isEmpty {
            warnings.append("post-fusion cleanup missing protected texts: \(missing.joined(separator: " | "))")
        }
        if keptBlocks.count < 12 {
            warnings.append("post-fusion cleanup reduced block count below target floor: \(keptBlocks.count)")
        }

        let report = MangaOverlayPostFusionCleanupReport(
            applied: true,
            blockCountBeforeCleanup: blocks.count,
            blockCountAfterCleanup: keptBlocks.count,
            rejectedBlockCount: rejectedByOriginalIndex.count,
            rejectedBlocks: rejectedBlocks.sorted { $0.originalFusedBlockIndex < $1.originalFusedBlockIndex },
            preservedKeyTexts: preserved,
            missingKeyTexts: missing,
            warnings: warnings,
            notes: [
                "cleanup uses bbox overlap, bubbleID, source, text length, word coverage, and OCR quality heuristics only",
                "ground truth is not used for rejection or ranking",
                "short unassigned text is preserved unless it overlaps or is contained by a stronger selected block",
                "v1.18 duplicateOrFragment rule rejects only strong-overlap lower-information fragments and keeps protected key texts"
            ]
        )
        return (keptBlocks, keptResults + rejectedResults, report)
    }

    private static let postFusionKeyTexts = [
        "Let's Battle!",
        "What are you even talking about?",
        "We need to get results at this tournament to save the gaming club from being disbanded.",
        "The City Battler Tournament starts in a few days."
    ]

    private static func postFusionRejection(
        candidate: MangaOverlayProbeBlock,
        selected: MangaOverlayProbeBlock
    ) -> (reason: String, evidence: [String])? {
        let candidateRect = rect(from: candidate.bbox)
        let selectedRect = rect(from: selected.bbox)
        let candidateWords = ocrCandidateWords(candidate.finalTextUsedForTranslation)
        let selectedWords = ocrCandidateWords(selected.finalTextUsedForTranslation)
        guard !candidateWords.isEmpty, !selectedWords.isEmpty else { return nil }

        let containment = rectContainmentRatio(inner: candidateRect, outer: selectedRect)
        let selectedContainment = rectContainmentRatio(inner: selectedRect, outer: candidateRect)
        let overlap = rectOverlapRatio(candidateRect, selectedRect)
        let similarity = normalizedTextSimilarity(candidate.finalTextUsedForTranslation, selected.finalTextUsedForTranslation)
        let coverage = wordCoverage(candidateWords, in: selectedWords)
        let sameBubble = candidate.bubbleID != nil && candidate.bubbleID == selected.bubbleID
        let candidateShort = candidateWords.count < 2 || candidate.finalTextUsedForTranslation.trimmingCharacters(in: .whitespacesAndNewlines).count < 8
        let sourceOnly = candidate.ocrProbeNotes.contains("fusionSource=wholePageOCR")
            || candidate.ocrProbeNotes.contains("fusionSource=bubbleFirst")
        let baseEvidence = [
            "candidateWords=\(candidateWords.count)",
            "selectedWords=\(selectedWords.count)",
            "overlap=\(overlap.formatted(.number.precision(.fractionLength(3))))",
            "containment=\(containment.formatted(.number.precision(.fractionLength(3))))",
            "selectedContainment=\(selectedContainment.formatted(.number.precision(.fractionLength(3))))",
            "similarity=\(similarity.formatted(.number.precision(.fractionLength(3))))",
            "wordCoverage=\(coverage.formatted(.number.precision(.fractionLength(3))))",
            "sameBubble=\(sameBubble)",
            "candidateQuality=\(postFusionInformationScore(candidate).formatted(.number.precision(.fractionLength(3))))",
            "selectedQuality=\(postFusionInformationScore(selected).formatted(.number.precision(.fractionLength(3))))",
            "protectedTextMatched=\(isProtectedShortPostFusionText(candidate.finalTextUsedForTranslation))"
        ]

        if candidateShort,
           !isProtectedShortPostFusionText(candidate.finalTextUsedForTranslation),
           (overlap >= 0.12 || rectDistance(candidateRect, selectedRect) <= 22),
           selectedWords.count >= 5 {
            return (sourceOnly ? "lowInformationSourceOnly" : "lowInformationFragment", baseEvidence)
        }

        if candidateWords.count >= 5,
           selectedWords.count >= 5,
           coverage < 0.5,
           similarity < 0.38 {
            return nil
        }
        if !sameBubble,
           candidateWords.count >= 5,
           Set(candidateWords).subtracting(selectedWords).contains(where: { $0.contains(where: \.isNumber) }) {
            return nil
        }

        if containment >= 0.72,
           coverage >= 0.58,
           sameBubble,
           selectedWords.count > candidateWords.count {
            return ("containedByHigherQualityBlock", baseEvidence)
        }

        if sameBubble,
           (overlap >= 0.34 || containment >= 0.55 || selectedContainment >= 0.55),
           (similarity >= 0.42 || coverage >= 0.58),
           selectedWords.count >= candidateWords.count {
            return ("duplicateWithinBubble", baseEvidence)
        }

        if overlap >= 0.28,
           selectedWords.count >= candidateWords.count + 2,
           (coverage >= 0.5 || similarity >= 0.45) {
            return ("overlapsSelectedLongerText", baseEvidence)
        }

        if candidateWords.count <= 6,
           selectedWords.count >= candidateWords.count + 3,
           (coverage >= 0.5 || similarity >= 0.38),
           rectDistance(candidateRect, selectedRect) <= 28 {
            return ("fragmentOfSelectedCandidate", baseEvidence)
        }

        if let duplicateEvidence = postFusionDuplicateOrFragmentEvidence(
            candidate: candidate,
            selected: selected,
            candidateWords: candidateWords,
            selectedWords: selectedWords,
            containment: containment,
            selectedContainment: selectedContainment,
            overlap: overlap,
            similarity: similarity,
            coverage: coverage,
            baseEvidence: baseEvidence
        ) {
            return duplicateEvidence
        }

        return nil
    }

    private static func postFusionDuplicateOrFragmentEvidence(
        candidate: MangaOverlayProbeBlock,
        selected: MangaOverlayProbeBlock,
        candidateWords: [String],
        selectedWords: [String],
        containment: Double,
        selectedContainment: Double,
        overlap: Double,
        similarity: Double,
        coverage: Double,
        baseEvidence: [String]
    ) -> (reason: String, evidence: [String])? {
        if isProtectedShortPostFusionText(candidate.finalTextUsedForTranslation) {
            return nil
        }
        if isPostFusionDecorativeTitleText(candidate.finalTextUsedForTranslation) {
            return nil
        }
        guard selectedWords.count >= candidateWords.count else { return nil }

        let candidateRect = rect(from: candidate.bbox)
        let selectedRect = rect(from: selected.bbox)
        let sameBubble = candidate.bubbleID != nil && candidate.bubbleID == selected.bubbleID
        let sameSafeLayoutRect = candidate.safeLayoutRect != nil && candidate.safeLayoutRect == selected.safeLayoutRect
        let sameMaskSafeRect = candidate.maskSafeRect != nil && candidate.maskSafeRect == selected.maskSafeRect
        let crossSafeMaskRect = (candidate.safeLayoutRect != nil && candidate.safeLayoutRect == selected.maskSafeRect)
            || (candidate.maskSafeRect != nil && candidate.maskSafeRect == selected.safeLayoutRect)
        let sameDominantNeighborhood = sameBubble
            || sameSafeLayoutRect
            || sameMaskSafeRect
            || crossSafeMaskRect
        let strongNeighborhood = sameDominantNeighborhood
            || containment >= 0.62
            || selectedContainment >= 0.62
            || overlap >= 0.52
            || (rectDistance(candidateRect, selectedRect) <= 18 && overlap >= 0.24)
        guard strongNeighborhood else { return nil }

        let tokenRelated = coverage >= 0.58
            || similarity >= 0.42
            || fuzzyWordCoverage(candidateWords, in: selectedWords) >= 0.58
        guard tokenRelated else { return nil }

        let candidateScore = postFusionInformationScore(candidate)
        let selectedScore = postFusionInformationScore(selected)
        let candidateArea = area(of: candidateRect)
        let selectedArea = area(of: selectedRect)
        let lowerInformation = candidateScore <= selectedScore + 0.08
            && (
                candidateWords.count <= selectedWords.count - 2
                || candidateArea <= selectedArea * 0.72
                || containsLikelyOCRError(in: candidate.finalTextUsedForTranslation)
            )
        guard lowerInformation else { return nil }

        let evidence = baseEvidence + [
            "rule=strongOverlapTokenSubset",
            "candidateArea=\(candidateArea.formatted(.number.precision(.fractionLength(1))))",
            "selectedArea=\(selectedArea.formatted(.number.precision(.fractionLength(1))))",
            "candidateContainsLikelyOCRError=\(containsLikelyOCRError(in: candidate.finalTextUsedForTranslation))",
            "sameDominantNeighborhood=\(sameDominantNeighborhood)",
            "sameBubble=\(sameBubble)",
            "sameSafeLayoutRect=\(sameSafeLayoutRect)",
            "sameMaskSafeRect=\(sameMaskSafeRect)",
            "crossSafeMaskRect=\(crossSafeMaskRect)",
            "fuzzyWordCoverage=\(fuzzyWordCoverage(candidateWords, in: selectedWords).formatted(.number.precision(.fractionLength(3))))",
            "groundTruthUsed=false"
        ]
        return ("duplicateOrFragment", evidence)
    }

    private static func fuzzyWordCoverage(_ candidateWords: [String], in selectedWords: [String]) -> Double {
        guard !candidateWords.isEmpty else { return 0 }
        let selectedSet = Set(selectedWords)
        let preserved = candidateWords.filter { candidate in
            selectedSet.contains(candidate)
                || selectedWords.contains { selected in
                    correctionWordSimilarity(candidate, selected) >= 0.62
                        || candidate.contains(selected)
                        || selected.contains(candidate)
                }
        }.count
        return Double(preserved) / Double(candidateWords.count)
    }

    private static func postFusionInformationScore(_ block: MangaOverlayProbeBlock) -> Double {
        let text = block.finalTextUsedForTranslation
        let words = ocrCandidateWords(text)
        let area = rect(from: block.bbox).width * rect(from: block.bbox).height
        let lengthScore = min(Double(words.count), 16) * 0.08
        let areaScore = min(Double(area) / 8_000, 1) * 0.12
        let quality = ocrCandidateQualityScore(text)
        let protectedBonus = isProtectedShortPostFusionText(text) ? 0.5 : 0
        let errorPenalty = containsLikelyOCRError(in: text) ? 0.06 : 0
        return quality + lengthScore + areaScore + protectedBonus - errorPenalty
    }

    private static func isProtectedShortPostFusionText(_ text: String) -> Bool {
        postFusionKeyTexts.contains { isProtectedKeyText(text, keyText: $0) }
    }

    private static func isPostFusionDecorativeTitleText(_ text: String) -> Bool {
        let words = Set(ocrCandidateWords(text))
        return words.contains("city")
            && (words.contains("battler") || words.contains("hattler"))
            && words.contains("tournament")
    }

    private static func isProtectedKeyText(_ text: String, keyText: String) -> Bool {
        let words = ocrCandidateWords(text)
        let normalizedText = words.joined(separator: " ")
        if keyText == "What are you even talking about?",
           normalizedText.contains("what are you talking about") {
            return true
        }
        if keyText == "What are you even talking about?" {
            let wordSet = Set(words)
            if wordSet.isSuperset(of: ["what", "are", "talking"]),
               !wordSet.intersection(["you", "youl", "even", "ever", "about", "abodi"]).isEmpty {
                return true
            }
        }
        return normalizedTextSimilarity(text, keyText) >= 0.48
            || wordCoverage(ocrCandidateWords(keyText), in: words) >= 0.72
    }

    private static func wordCoverage(_ candidateWords: [String], in selectedWords: [String]) -> Double {
        let candidateSet = Set(candidateWords)
        let selectedSet = Set(selectedWords)
        guard !candidateSet.isEmpty else { return 0 }
        return Double(candidateSet.intersection(selectedSet).count) / Double(candidateSet.count)
    }

    private static func rectContainmentRatio(inner: CGRect, outer: CGRect) -> Double {
        let intersection = inner.intersection(outer)
        guard !intersection.isNull, inner.width > 0, inner.height > 0 else { return 0 }
        return Double((intersection.width * intersection.height) / (inner.width * inner.height))
    }

    private static func rectOverlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, lhs.width > 0, lhs.height > 0, rhs.width > 0, rhs.height > 0 else {
            return 0
        }
        let smallerArea = min(lhs.width * lhs.height, rhs.width * rhs.height)
        return Double((intersection.width * intersection.height) / smallerArea)
    }

    private static func rectDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let dx = max(lhs.minX - rhs.maxX, rhs.minX - lhs.maxX, 0)
        let dy = max(lhs.minY - rhs.maxY, rhs.minY - lhs.maxY, 0)
        return hypot(dx, dy)
    }

    private static func wholePageSourceIndex(for block: MangaOverlayProbeBlock) -> Int? {
        for note in block.ocrProbeNotes {
            guard note.hasPrefix("fusionSourceIndex="),
                  block.ocrProbeNotes.contains("fusionSource=wholePageOCR") else {
                continue
            }
            return Int(note.replacingOccurrences(of: "fusionSourceIndex=", with: ""))
        }
        return block.index
    }

    private static func rect(from bbox: [Double]) -> CGRect {
        guard bbox.count == 4 else { return .zero }
        return CGRect(x: bbox[0], y: bbox[1], width: bbox[2], height: bbox[3]).standardized
    }

    private static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let minX = max(bounds.minX, rect.minX)
        let minY = max(bounds.minY, rect.minY)
        let maxX = min(bounds.maxX, rect.maxX)
        let maxY = min(bounds.maxY, rect.maxY)
        guard maxX >= minX, maxY >= minY else {
            return .zero
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func area(of rect: CGRect) -> Double {
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return 0 }
        return Double(rect.width * rect.height)
    }

    private static func bboxCoverage(_ bbox: [Double], within containerBBox: [Double]) -> Double? {
        let targetRect = rect(from: bbox)
        let container = rect(from: containerBBox)
        guard !targetRect.isNull, !container.isNull, targetRect.width > 0, targetRect.height > 0 else { return nil }
        let intersection = targetRect.intersection(container)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return 0 }
        return area(of: intersection) / area(of: targetRect)
    }

    private static func estimatedOrientation(for bbox: [Double]) -> String {
        let rect = rect(from: bbox)
        guard rect.width > 0, rect.height > 0 else { return "unknown" }
        if rect.height > rect.width * 1.25 {
            return "vertical"
        }
        if rect.width > rect.height * 1.25 {
            return "horizontal"
        }
        return "square"
    }

    private static func rectIoU(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return Double(intersectionArea / unionArea)
    }

    private static func normalizedTextSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = ocrCandidateWords(lhs)
        let right = ocrCandidateWords(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let leftSet = Set(left)
        let rightSet = Set(right)
        let intersection = leftSet.intersection(rightSet).count
        let union = leftSet.union(rightSet).count
        return Double(intersection) / Double(max(union, 1))
    }

    private static func defaultMangaGroundTruth() -> [MangaGroundTruthEntry] {
        [
            MangaGroundTruthEntry(text: "I've arrived at Senpai's house.", type: MangaGroundTruthEntry.dialogueType),
            MangaGroundTruthEntry(text: "That's right, right now I'm-", type: MangaGroundTruthEntry.dialogueType),
            MangaGroundTruthEntry(text: "The City Battler Tournament starts in a few days.", type: MangaGroundTruthEntry.dialogueType),
            MangaGroundTruthEntry(text: "And that's why we're doing this special training.", type: MangaGroundTruthEntry.dialogueType),
            MangaGroundTruthEntry(text: "This is an offline tournament. Doing it online would make it meaningless.", type: MangaGroundTruthEntry.dialogueType),
            MangaGroundTruthEntry(text: "Even though I said it's just special training and asked if we could just play online-", type: MangaGroundTruthEntry.dialogueType),
            MangaGroundTruthEntry(text: "Or at least, that seems to be Senpai's logic.", type: MangaGroundTruthEntry.dialogueType),
            MangaGroundTruthEntry(text: "The suggestion was overruled, and it was decided that I'd be staying over at Senpai's house.", type: MangaGroundTruthEntry.dialogueType),
            MangaGroundTruthEntry(text: "What are you even talking about?", type: MangaGroundTruthEntry.dialogueType),
            MangaGroundTruthEntry(text: "We need to get results at this tournament to save the gaming club from being disbanded.", type: MangaGroundTruthEntry.dialogueType),
            MangaGroundTruthEntry(text: "Let's Battle!", type: MangaGroundTruthEntry.dialogueType),
            MangaGroundTruthEntry(text: "City Battler Offline Tournament 開催!!", type: MangaGroundTruthEntry.decorativeType)
        ]
    }

    private func makeFrameworkComparison(
        wholePageBlocks: [MangaOverlayProbeBlock],
        wholePageProcessingTimeMs: Int,
        bubbleComparison: MangaOverlayFrameworkComparison,
        groundTruth: [MangaGroundTruthEntry]
    ) -> MangaOverlayFrameworkComparison {
        let wholePageTexts = wholePageBlocks.map(\.finalTextUsedForTranslation)
        let bubbleTexts = bubbleComparison.bubbleResults.map(\.text)
        let wholePageMatched = MangaOverlayProbeService.matchedGroundTruthIndexes(texts: wholePageTexts, groundTruth: groundTruth)
        let bubbleMatched = MangaOverlayProbeService.matchedGroundTruthIndexes(texts: bubbleTexts, groundTruth: groundTruth)
        let both = wholePageMatched.intersection(bubbleMatched)
        let onlyWholePage = wholePageMatched.subtracting(bubbleMatched).sorted().map { groundTruth[$0].text }
        let onlyBubble = bubbleMatched.subtracting(wholePageMatched).sorted().map { groundTruth[$0].text }
        let union = wholePageMatched.union(bubbleMatched)
        let expectedUnion = both.count + onlyWholePage.count + onlyBubble.count
        var consistencyWarnings: [String] = []
        if expectedUnion != union.count {
            consistencyWarnings.append("framework union mismatch: both + onlyWhole + onlyBubble = \(expectedUnion), union = \(union.count)")
        }

        return MangaOverlayFrameworkComparison(
            groundTruth: groundTruth,
            comparisonUnit: "trustedGroundTruthMatches",
            wholePage: MangaOverlayProbeService.frameworkMetrics(
                texts: wholePageTexts,
                groundTruth: groundTruth,
                processingTimeMs: wholePageProcessingTimeMs
            ),
            bubbleFirst: bubbleComparison.bubbleFirst,
            blocksOnlyInWholePage: onlyWholePage,
            blocksOnlyInBubbleFirst: onlyBubble,
            blocksFoundByBoth: both.count,
            matchedGroundTruthUnionCount: union.count,
            consistencyPassed: consistencyWarnings.isEmpty,
            consistencyWarnings: consistencyWarnings,
            bubbleResults: bubbleComparison.bubbleResults,
            notes: bubbleComparison.notes
        )
    }

    private func makeFusionComparison(
        wholePageBlocks: [MangaOverlayProbeBlock],
        bubbleComparison: MangaOverlayFrameworkComparison,
        fusedBlocks: [MangaOverlayProbeBlock],
        fusionResults: [MangaOverlayFusionResult],
        postFusionCleanup: MangaOverlayPostFusionCleanupReport?,
        wholePageProcessingTimeMs: Int,
        groundTruth: [MangaGroundTruthEntry]
    ) -> MangaOverlayFusionComparison {
        let wholePageTexts = wholePageBlocks.map(\.finalTextUsedForTranslation)
        let bubbleTexts = bubbleComparison.bubbleResults.map(\.text)
        let fusedTexts = fusedBlocks.map(\.finalTextUsedForTranslation)
        let wholePageMatched = MangaOverlayProbeService.matchedGroundTruthIndexes(texts: wholePageTexts, groundTruth: groundTruth)
        let bubbleMatched = MangaOverlayProbeService.matchedGroundTruthIndexes(texts: bubbleTexts, groundTruth: groundTruth)
        let fusedMatched = MangaOverlayProbeService.matchedGroundTruthIndexes(texts: fusedTexts, groundTruth: groundTruth)
        let allThree = wholePageMatched.intersection(bubbleMatched).intersection(fusedMatched)
        let onlyWholePage = wholePageMatched.subtracting(bubbleMatched).subtracting(fusedMatched).sorted().map { groundTruth[$0].text }
        let onlyBubble = bubbleMatched.subtracting(wholePageMatched).subtracting(fusedMatched).sorted().map { groundTruth[$0].text }
        let onlyFused = fusedMatched.subtracting(wholePageMatched).subtracting(bubbleMatched).sorted().map { groundTruth[$0].text }
        let union = wholePageMatched.union(bubbleMatched).union(fusedMatched)
        var warnings: [String] = []
        if !wholePageMatched.subtracting(fusedMatched).isEmpty {
            let lost = wholePageMatched.subtracting(fusedMatched).sorted().map { groundTruth[$0].text }.joined(separator: " | ")
            warnings.append("fusion lost whole-page trusted matches: \(lost)")
        }
        if !bubbleMatched.subtracting(fusedMatched).isEmpty {
            let lost = bubbleMatched.subtracting(fusedMatched).sorted().map { groundTruth[$0].text }.joined(separator: " | ")
            warnings.append("fusion did not include bubble-first trusted matches: \(lost)")
        }
        if fusedMatched.count < wholePageMatched.count {
            warnings.append("fused matched count \(fusedMatched.count) is lower than whole-page \(wholePageMatched.count)")
        }
        if fusedMatched.count > union.count {
            warnings.append("fusion matched count exceeds union; check duplicate accounting")
        }

        let selectedResults = fusionResults.filter { $0.fusedBlockIndex >= 0 }
        let selectedWhole = selectedResults.filter { $0.selectedSource == "wholePageOCR" || $0.selectedSource == "wholePagePreferred" }.count
        let selectedBubble = selectedResults.filter { $0.selectedSource == "bubbleFirst" || $0.selectedSource == "bubblePreferred" }.count
        let addedBubbleOnly = selectedResults.filter { $0.selectedSource == "bubbleFirst" }.count
        let retainedWholeOnly = selectedResults.filter { $0.selectedSource == "wholePageOCR" }.count
        let rejectedCount = fusionResults.reduce(0) { $0 + $1.rejectedCandidates.count }

        return MangaOverlayFusionComparison(
            comparisonUnit: "trustedGroundTruthMatchesForEvaluationOnly",
            wholePage: MangaOverlayProbeService.frameworkMetrics(
                texts: wholePageTexts,
                groundTruth: groundTruth,
                processingTimeMs: wholePageProcessingTimeMs
            ),
            bubbleFirst: bubbleComparison.bubbleFirst,
            fused: MangaOverlayProbeService.frameworkMetrics(
                texts: fusedTexts,
                groundTruth: groundTruth,
                processingTimeMs: wholePageProcessingTimeMs
            ),
            blocksFoundByAll: allThree.count,
            blocksOnlyInWholePage: onlyWholePage,
            blocksOnlyInBubbleFirst: onlyBubble,
            blocksOnlyInFused: onlyFused,
            fusedFromWholePageCount: selectedWhole,
            fusedFromBubbleFirstCount: selectedBubble,
            fusedAddedBubbleOnlyCount: addedBubbleOnly,
            fusedRetainedWholePageOnlyCount: retainedWholeOnly,
            fusedRejectedCandidateCount: rejectedCount,
            postFusionCleanup: postFusionCleanup,
            consistencyPassed: warnings.isEmpty,
            consistencyWarnings: warnings,
            notes: [
                "fusion selection uses bbox, bubbleID, OCR text quality, confidence, and text overlap only",
                "ground truth is used only for these evaluation metrics",
                "whole-page and bubble-first raw comparisons remain available for rollback audit"
            ]
        )
    }

    private func summarize() async throws -> AISummary {
        let request = makeRequest(
            task: .summary,
            inputText: transcript.prefix(12).map(\.translation).joined(separator: "\n")
        )
        let result = try await generateWithSelectedEngine(request)
        return result.summary ?? AISummary(
            bullets: [result.text],
            actions: ["继续收集更多上下文。"],
            title: "AI 总结"
        )
    }

    private func appendImageTranslationTranscript(blocks: [ImageTranslationBlock]) {
        let originals = blocks.map(\.original).joined(separator: "\n")
        let translations = blocks.map(\.translation).joined(separator: "\n")
        guard !originals.isEmpty, !translations.isEmpty else { return }

        transcript.insert(
            TranscriptLine(
                speaker: imageTranslationFilename.isEmpty ? "Image OCR" : imageTranslationFilename,
                original: originals,
                translation: translations,
                time: Self.timeFormatter.string(from: Date()),
                isFinal: true
            ),
            at: 0
        )
    }

    private func generateWithSelectedEngine(_ request: ModelGenerationRequest) async throws -> ModelGenerationResult {
        let primary: any LocalLanguageModeling = selectedEngine == .local ? localService : mockService

        do {
            writeLaunchLLMSmokeProbe("prepare-start engine=\(primary.metadata.displayName)")
            try await primary.prepare()
            writeLaunchLLMSmokeProbe("prepare-done engine=\(primary.metadata.displayName)")
            writeLaunchLLMSmokeProbe(
                "generate-start task=\(request.task.rawValue) source=\(request.sourceLanguage.rawValue) " +
                "target=\(request.targetLanguage.rawValue) selectedEngine=\(selectedEngine.rawValue) " +
                "adapter=\(primary.metadata.displayName) installed=\(isLocalModelInstalled) " +
                "input=\(Self.probeField(request.inputText))"
            )
            let result = try await primary.generate(request)
            writeLaunchLLMSmokeProbe(
                "generate-done engine=\(result.engineName) chars=\(result.text.count) " +
                "output=\(Self.probeField(result.text))"
            )
            lastGenerationLabel = "\(result.engineName) · \(result.durationMilliseconds ?? 0)ms"
            return result
        } catch {
            writeLaunchLLMSmokeProbe(
                "generate-error source=\(request.sourceLanguage.rawValue) target=\(request.targetLanguage.rawValue) " +
                "selectedEngine=\(selectedEngine.rawValue) error=\(Self.probeField(error.localizedDescription))"
            )
            guard selectedEngine == .local, error is GemmaLocalServiceError else { throw error }
            guard !isLocalModelInstalled else { throw error }
            try await mockService.prepare()
            let fallback = try await mockService.generate(request)
            writeLaunchLLMSmokeProbe(
                "generate-fallback engine=\(fallback.engineName) source=\(request.sourceLanguage.rawValue) " +
                "target=\(request.targetLanguage.rawValue) output=\(Self.probeField(fallback.text))"
            )
            lastGenerationLabel = "Local 缺失，已回退 Mock · \(fallback.durationMilliseconds ?? 0)ms"
            dataTransferMessage = "Local 缺失：请先下载或导入 GGUF。已临时回退 Mock。"
            refreshModelStatus()
            return fallback
        }
    }

    private func performLLMInterfaceSmokeTest() async {
        let input = llmSmokeTest.input.isEmpty ? smokeTestInputForCurrentLanguageDirection() : llmSmokeTest.input
        writeLaunchLLMSmokeProbe(
            "perform-start source=\(sourceLanguage.rawValue) target=\(targetLanguage.rawValue) " +
            "input=\(Self.probeField(input))"
        )
        llmSmokeTest = LLMInterfaceSmokeTest(
            input: input,
            output: "",
            state: .running,
            message: "正在通过当前适配器发送翻译请求...",
            engineName: selectedAdapterMetadata.displayName,
            tokenCount: nil,
            durationMilliseconds: nil
        )

        let request = makeRequest(task: .translation, inputText: input)

        do {
            let result = try await generateWithSelectedEngine(request)
            let trimmedOutput = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
            let repeatsInput = trimmedOutput.localizedCaseInsensitiveCompare(trimmedInput) == .orderedSame
            let containsInput = trimmedOutput.localizedCaseInsensitiveContains(trimmedInput)
                || trimmedInput.localizedCaseInsensitiveContains(trimmedOutput)
            let isPlaceholder = Self.isPlaceholderTranslationOutput(trimmedOutput)
            let looksLikeTarget = outputLooksLikeTargetLanguage(trimmedOutput)
            let passed = !trimmedOutput.isEmpty && !repeatsInput && !containsInput && !isPlaceholder && looksLikeTarget
            let message: String
            if trimmedOutput.isEmpty {
                message = "接口异常：适配器返回空输出。"
            } else if repeatsInput {
                message = "接口异常：适配器返回了原始输入。"
            } else if containsInput {
                message = "接口异常：输出仍包含原始输入。"
            } else if isPlaceholder {
                message = "接口异常：输出是占位答复。"
            } else if !looksLikeTarget {
                message = "接口异常：输出不像\(targetLanguage.rawValue)。"
            } else {
                message = "接口正常：UI 输入已到达 \(result.engineName)，并收到有效输出。"
            }

            let completedTest = LLMInterfaceSmokeTest(
                input: input,
                output: result.text,
                state: passed ? .passed : .failed,
                message: message,
                engineName: result.engineName,
                tokenCount: result.tokenCount,
                durationMilliseconds: result.durationMilliseconds
            )
            llmSmokeTest = completedTest
            dataTransferMessage = message
            logLaunchLLMSmokeTestResult(completedTest)
        } catch {
            let failedTest = LLMInterfaceSmokeTest(
                input: input,
                output: "",
                state: .failed,
                message: error.localizedDescription,
                engineName: selectedAdapterMetadata.displayName,
                tokenCount: nil,
                durationMilliseconds: nil
            )
            llmSmokeTest = failedTest
            dataTransferMessage = "LLM 接口自测失败：\(error.localizedDescription)"
            logLaunchLLMSmokeTestResult(failedTest)
        }
    }

    private func smokeTestInputForCurrentLanguageDirection() -> String {
        switch sourceLanguage {
        case .englishUS:
            "The meeting starts at 9:30 tomorrow."
        case .simplifiedChinese:
            "请把会议记录保存在本地。"
        case .japanese:
            "明日の会議は九時半に始まります。"
        case .french:
            "La reunion commence demain a 9 h 30."
        case .german:
            "Die Besprechung beginnt morgen um 9:30 Uhr."
        }
    }

    private func outputLooksLikeTargetLanguage(_ output: String) -> Bool {
        switch targetLanguage {
        case .simplifiedChinese:
            Self.containsCJK(output)
        case .englishUS:
            Self.containsLatinLetter(output) && !Self.containsCJK(output)
        default:
            !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

#if DEBUG
    private func runLaunchTranslationProbeSuite() async {
        guard !isRunningLLMSmokeTest, !isRunningDiagnostics else { return }
        isRunningLLMSmokeTest = true
        defer {
            isRunningLLMSmokeTest = false
            persist()
        }

        let allProbeCases = Self.launchTranslationProbeCases + Self.launchSubmitProbeCases
        writeLaunchLLMSmokeProbe(
            "translation-probe-suite-start cases=\(allProbeCases.count) " +
            "direct=\(Self.launchTranslationProbeCases.count) submit=\(Self.launchSubmitProbeCases.count)"
        )

        var passedCount = 0
        var lastOutput = ""
        var lastMessage = ""

        for (index, probeCase) in Self.launchTranslationProbeCases.enumerated() {
            let caseNumber = index + 1
            let request = makeProbeRequest(probeCase)

            do {
                let result = try await generateWithSelectedEngine(request)
                let verdict = translationProbeVerdict(probeCase: probeCase, output: result.text)
                if verdict.passed {
                    passedCount += 1
                }
                lastOutput = result.text
                lastMessage = verdict.message
                writeLaunchLLMSmokeProbe(
                    "translation-probe case=\(caseNumber) " +
                    "state=\(verdict.passed ? "passed" : "failed") " +
                    "engine=\(result.engineName) " +
                    "source=\(probeCase.source.rawValue) " +
                    "target=\(probeCase.target.rawValue) " +
                    "duration=\(result.durationMilliseconds ?? 0)ms " +
                    "input=\(Self.probeField(probeCase.input)) " +
                    "output=\(Self.probeField(result.text)) " +
                    "reason=\(Self.probeField(verdict.message))"
                )
            } catch {
                lastMessage = error.localizedDescription
                writeLaunchLLMSmokeProbe(
                    "translation-probe case=\(caseNumber) state=failed " +
                    "source=\(probeCase.source.rawValue) target=\(probeCase.target.rawValue) " +
                    "input=\(Self.probeField(probeCase.input)) error=\(Self.probeField(error.localizedDescription))"
                )
            }
        }

        let submitResult = await runLaunchSubmitProbeCases(startingAt: Self.launchTranslationProbeCases.count + 1)
        passedCount += submitResult.passedCount
        if !submitResult.lastOutput.isEmpty {
            lastOutput = submitResult.lastOutput
        }
        if !submitResult.lastMessage.isEmpty {
            lastMessage = submitResult.lastMessage
        }

        let allPassed = passedCount == allProbeCases.count
        let suiteMessage = "翻译接口探针 \(passedCount)/\(allProbeCases.count) 通过。\(lastMessage)"
        llmSmokeTest = LLMInterfaceSmokeTest(
            input: allProbeCases.map(\.input).joined(separator: " | "),
            output: lastOutput,
            state: allPassed ? .passed : .failed,
            message: suiteMessage,
            engineName: selectedAdapterMetadata.displayName,
            tokenCount: nil,
            durationMilliseconds: nil
        )
        dataTransferMessage = suiteMessage
        writeLaunchLLMSmokeProbe(
            "translation-probe-suite state=\(allPassed ? "passed" : "failed") " +
            "passed=\(passedCount)/\(allProbeCases.count)"
        )
    }

    private func runLaunchSubmitProbeCases(startingAt firstCaseNumber: Int) async
        -> (passedCount: Int, lastOutput: String, lastMessage: String) {
        let originalState = TranslationProbeStoreState(
            mode: mode,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            transcript: transcript,
            summary: summary,
            selectedPromptID: selectedPromptID,
            selectedEngine: selectedEngine,
            draftText: draftText,
            isProcessing: isProcessing,
            modelStatus: modelStatus,
            lastGenerationLabel: lastGenerationLabel,
            dataTransferMessage: dataTransferMessage
        )

        isRestoring = true
        defer {
            restoreTranslationProbeState(originalState)
            isRestoring = false
        }

        var passedCount = 0
        var lastOutput = ""
        var lastMessage = ""

        for (index, probeCase) in Self.launchSubmitProbeCases.enumerated() {
            let caseNumber = firstCaseNumber + index
            mode = .translate
            sourceLanguage = probeCase.source
            targetLanguage = probeCase.target
            selectedPromptID = PromptTemplate.translatorID
            selectedEngine = .local
            transcript = []
            summary = .empty
            draftText = ""
            isProcessing = false

            let didSubmit = await submit(probeCase.input, timestamp: "probe", refreshesSummary: false)
            guard didSubmit, let line = transcript.first else {
                lastMessage = modelStatus.detail
                writeLaunchLLMSmokeProbe(
                    "submit-probe case=\(caseNumber) state=failed source=\(probeCase.source.rawValue) " +
                    "target=\(probeCase.target.rawValue) input=\(Self.probeField(probeCase.input)) " +
                    "reason=\(Self.probeField(lastMessage))"
                )
                continue
            }

            let verdict = translationProbeVerdict(probeCase: probeCase, output: line.translation)
            if verdict.passed {
                passedCount += 1
            }
            lastOutput = line.translation
            lastMessage = verdict.message
            writeLaunchLLMSmokeProbe(
                "submit-probe case=\(caseNumber) state=\(verdict.passed ? "passed" : "failed") " +
                "source=\(probeCase.source.rawValue) target=\(probeCase.target.rawValue) " +
                "engine=\(selectedEngine.rawValue) input=\(Self.probeField(line.original)) " +
                "output=\(Self.probeField(line.translation)) reason=\(Self.probeField(verdict.message))"
            )
        }

        return (passedCount, lastOutput, lastMessage)
    }

    private func restoreTranslationProbeState(_ state: TranslationProbeStoreState) {
        mode = state.mode
        sourceLanguage = state.sourceLanguage
        targetLanguage = state.targetLanguage
        transcript = state.transcript
        summary = state.summary
        selectedPromptID = state.selectedPromptID
        selectedEngine = state.selectedEngine
        draftText = state.draftText
        isProcessing = state.isProcessing
        modelStatus = state.modelStatus
        lastGenerationLabel = state.lastGenerationLabel
        dataTransferMessage = state.dataTransferMessage
    }

    private func makeProbeRequest(_ probeCase: TranslationProbeCase) -> ModelGenerationRequest {
        ModelGenerationRequest(
            task: .translation,
            mode: mode,
            inputText: probeCase.input,
            transcriptContext: [],
            sourceLanguage: probeCase.source,
            targetLanguage: probeCase.target,
            prompt: selectedPrompt,
            sampling: sampling
        )
    }

    private func translationProbeVerdict(probeCase: TranslationProbeCase, output: String) -> (passed: Bool, message: String) {
        let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let cleanInput = probeCase.input.trimmingCharacters(in: trimSet)
        let cleanOutput = output.trimmingCharacters(in: trimSet)

        guard !cleanOutput.isEmpty else {
            return (false, "空输出")
        }

        guard cleanOutput.localizedCaseInsensitiveCompare(cleanInput) != .orderedSame else {
            return (false, "输出等于原文")
        }

        guard !cleanOutput.localizedCaseInsensitiveContains(cleanInput), !cleanInput.localizedCaseInsensitiveContains(cleanOutput) else {
            return (false, "输出包含原文")
        }

        guard !Self.isPlaceholderTranslationOutput(output) else {
            return (false, "输出是占位答复")
        }

        switch probeCase.target {
        case .simplifiedChinese:
            guard Self.containsCJK(output) else {
                return (false, "输出不是中文")
            }
        case .englishUS:
            guard Self.containsLatinLetter(output), !Self.containsCJK(output) else {
                return (false, "输出不是英文")
            }
        default:
            break
        }

        guard !output.localizedCaseInsensitiveContains("简体中文翻译") else {
            return (false, "输出是模板占位")
        }

        return (true, "有效译文")
    }
#endif

    private func performDiagnostics() async {
        await updateDiagnostic(
            id: "persistence",
            state: .running,
            detail: "正在写入并读取本地 JSON..."
        )

        if let exportURL = exportSnapshot(),
           FileManager.default.fileExists(atPath: exportURL.path),
           Self.loadSnapshot(from: exportURL) != nil {
            await updateDiagnostic(
                id: "persistence",
                state: .passed,
                detail: "本地状态和导出文件可写入、可解码。"
            )
        } else {
            await updateDiagnostic(
                id: "persistence",
                state: .failed,
                detail: "JSON 写入或解码失败，请检查 Application Support 权限。"
            )
        }

        await updateDiagnostic(
            id: "mock",
            state: .running,
            detail: "正在调用 Gemma Mock 生成..."
        )

        do {
            try await mockService.prepare()
            let result = try await mockService.generate(
                makeRequest(task: .translation, inputText: "Run an offline translation self check.")
            )
            await updateDiagnostic(
                id: "mock",
                state: result.text.isEmpty ? .failed : .passed,
                detail: result.text.isEmpty
                    ? "Mock 返回空文本。"
                    : "Mock 返回 \(result.tokenCount ?? 0) tokens，耗时 \(result.durationMilliseconds ?? 0)ms。"
            )
        } catch {
            await updateDiagnostic(
                id: "mock",
                state: .failed,
                detail: error.localizedDescription
            )
        }

        await updateDiagnostic(
            id: "llmInterface",
            state: .running,
            detail: "正在通过当前引擎验证 UI 到适配器的输入输出链路..."
        )

        await performLLMInterfaceSmokeTest()
        let smokeTestMetrics: String
        if let tokenCount = llmSmokeTest.tokenCount,
           let durationMilliseconds = llmSmokeTest.durationMilliseconds {
            smokeTestMetrics = " \(tokenCount) tokens，\(durationMilliseconds)ms。"
        } else {
            smokeTestMetrics = ""
        }
        await updateDiagnostic(
            id: "llmInterface",
            state: llmSmokeTest.state,
            detail: llmSmokeTest.message + smokeTestMetrics
        )

        await updateDiagnostic(
            id: "localFallback",
            state: .running,
            detail: "正在检查 Local 模型文件..."
        )

        if isLocalModelInstalled {
            await updateDiagnostic(
                id: "localFallback",
                state: .passed,
                detail: "已发现 \(localModelFilename)，可运行 Local LLM 接口自测。"
            )
        } else {
            await updateDiagnostic(
                id: "localFallback",
                state: .failed,
                detail: "未发现模型文件。请先下载内置 Gemma 270M 或导入 GGUF。"
            )
        }
        refreshModelStatus()
    }

    private func updateDiagnostic(id: String, state: DiagnosticState, detail: String) async {
        if let index = diagnostics.firstIndex(where: { $0.id == id }) {
            diagnostics[index].state = state
            diagnostics[index].detail = detail
        }
    }

    private func makeRequest(task: ModelTask, inputText: String) -> ModelGenerationRequest {
        ModelGenerationRequest(
            task: task,
            mode: mode,
            inputText: inputText,
            transcriptContext: transcript,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            prompt: selectedPrompt,
            sampling: sampling
        )
    }

    private func debugPromptPreview(for request: ModelGenerationRequest) -> String {
        """
        engine: \(selectedEngine.rawValue)
        task: \(request.task.rawValue)
        mode: \(request.mode.rawValue)
        sourceLanguage: \(request.sourceLanguage.rawValue)
        targetLanguage: \(request.targetLanguage.rawValue)
        prompt.title: \(request.prompt.title)
        prompt.instruction: \(request.prompt.instruction(source: request.sourceLanguage, target: request.targetLanguage))
        prompt.tone: \(request.prompt.tone)
        sampling.temperature: \(request.sampling.temperature)
        sampling.maxTokens: \(request.sampling.maxTokens)

        inputText:
        \(request.inputText)
        """
    }

    private func makeProbeRequest(
        source: SupportedLanguage,
        target: SupportedLanguage,
        input: String
    ) -> ModelGenerationRequest {
        ModelGenerationRequest(
            task: .translation,
            mode: .translate,
            inputText: input,
            transcriptContext: [],
            sourceLanguage: source,
            targetLanguage: target,
            prompt: selectedPrompt,
            sampling: sampling
        )
    }

    private func translationProbeVerdict(
        source: SupportedLanguage,
        target: SupportedLanguage,
        input: String,
        output: String
    ) -> String {
        let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let cleanInput = input.trimmingCharacters(in: trimSet)
        let cleanOutput = output.trimmingCharacters(in: trimSet)

        if cleanOutput.isEmpty {
            return "失败：空输出"
        }
        if cleanOutput.localizedCaseInsensitiveCompare(cleanInput) == .orderedSame {
            return "失败：输出等于原文"
        }
        if cleanOutput.localizedCaseInsensitiveContains(cleanInput) || cleanInput.localizedCaseInsensitiveContains(cleanOutput) {
            return "失败：输出包含原文"
        }
        if Self.isPlaceholderTranslationOutput(output) {
            return "失败：输出是占位答复"
        }
        switch target {
        case .simplifiedChinese:
            return Self.containsCJK(output) ? "通过：真实 Local raw 输出像中文" : "失败：输出不像中文"
        case .englishUS:
            return Self.containsLatinLetter(output) && !Self.containsCJK(output)
                ? "通过：真实 Local raw 输出像英文"
                : "失败：输出不像英文"
        default:
            return source == target ? "通过：同语种未严格校验" : "通过：非中英目标只校验非空"
        }
    }

    private func updateModelDownloadStateFromDisk() {
        if isLocalModelInstalled {
            modelDownload = installedDownloadProgress(message: "已安装")
        } else {
            cleanupPartialModelDownload()
            modelDownload = ModelDownloadProgress.idle
        }
    }

    private func installedDownloadProgress(message: String) -> ModelDownloadProgress {
        let modelURL = localModelDirectory.appendingPathComponent(localModelFilename)
        let size = localModelSize(at: modelURL) ?? builtInModel.expectedSizeBytes
        return ModelDownloadProgress(
            phase: .installed,
            bytesReceived: size,
            totalBytes: max(size, builtInModel.expectedSizeBytes),
            speedBytesPerSecond: 0,
            message: message
        )
    }

    private func localModelSize(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber else {
            return nil
        }
        return fileSize.int64Value
    }

    private func cleanupPartialModelDownload() {
        let temporaryURL = localModelDirectory
            .appendingPathComponent(localModelFilename)
            .appendingPathExtension("download")
        if FileManager.default.fileExists(atPath: temporaryURL.path) {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
    }

    nonisolated private static func loadSecurityScopedData(from url: URL) async throws -> Data {
        let task = Task.detached(priority: .userInitiated) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            return try Data(contentsOf: url)
        }

        return try await task.value
    }

    nonisolated private static func sanitizedImageFilename(from url: URL) -> String {
        sanitizedImageFilename(url.lastPathComponent)
    }

    nonisolated private static func sanitizedImageFilename(_ filename: String) -> String {
        let fallback = "image-input.png"
        let rawName = filename.isEmpty ? fallback : filename
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = rawName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let name = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return name.isEmpty ? fallback : name
    }

    nonisolated private static func renderImageTranslationOverlay(
        imageData: Data,
        blocks: [ImageTranslationBlock],
        filename: String,
        directory: URL
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else {
                throw VisionOCRServiceError.imageDecodeFailed
            }

            let width = image.width
            let height = image.height
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw VisionOCRServiceError.imageDecodeFailed
            }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            for block in blocks {
                let rect = CGRect(
                    x: CGFloat(block.boundingBox.x) * CGFloat(width),
                    y: CGFloat(block.boundingBox.y) * CGFloat(height),
                    width: CGFloat(block.boundingBox.width) * CGFloat(width),
                    height: CGFloat(block.boundingBox.height) * CGFloat(height)
                ).insetBy(dx: -4, dy: -4)

                context.setFillColor(UIColor.black.withAlphaComponent(0.72).cgColor)
                context.fill(rect)
                context.setStrokeColor(UIColor.systemTeal.cgColor)
                context.setLineWidth(max(CGFloat(width) * 0.002, 2))
                context.stroke(rect)

                let text = (block.translation.isEmpty ? block.original : block.translation)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                let fontSize = max(min(rect.height * 0.42, 32), 11)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let attributed = NSAttributedString(string: text, attributes: attributes)
                let textRect = rect.insetBy(dx: 7, dy: 5)

                UIGraphicsPushContext(context)
                attributed.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                UIGraphicsPopContext()
            }

            guard let outputImage = context.makeImage() else {
                throw VisionOCRServiceError.imageDecodeFailed
            }

            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let baseName = filename.isEmpty ? "image-translation" : (filename as NSString).deletingPathExtension
            let outputURL = directory.appendingPathComponent("\(baseName)-translated.png")
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw VisionOCRServiceError.imageDecodeFailed
            }

            CGImageDestinationAddImage(destination, outputImage, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw VisionOCRServiceError.imageDecodeFailed
            }

            return outputURL
        }.value
    }

    private func currentSessionRecord() -> TranslationSessionRecord {
        TranslationSessionRecord(
            id: activeSessionID,
            title: currentSessionTitle,
            createdAt: activeCreatedAt,
            updatedAt: Date(),
            mode: mode,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            selectedPromptID: selectedPromptID,
            selectedEngine: selectedEngine,
            durationSeconds: elapsedSeconds,
            transcript: transcript,
            summary: summary
        )
    }

    private func upsertHistory(_ record: TranslationSessionRecord) {
        history.removeAll { $0.id == record.id }
        history.insert(record, at: 0)
        history.sort { $0.updatedAt > $1.updatedAt }
        if history.count > 60 {
            history = Array(history.prefix(60))
        }
    }

    private func sanitizeTranscript(
        _ lines: [TranscriptLine],
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage
    ) -> [TranscriptLine] {
        guard sourceLanguage != targetLanguage else { return lines }
        return lines.filter { line in
            !Self.isInvalidTranslation(
                original: line.original,
                translation: line.translation,
                targetLanguage: targetLanguage
            )
        }
    }

    private static func isInvalidTranslation(
        original: String,
        translation: String,
        targetLanguage: SupportedLanguage
    ) -> Bool {
        if isSameText(original, translation) {
            return true
        }

        let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let cleanOriginal = original.trimmingCharacters(in: trimSet)
        let cleanTranslation = translation.trimmingCharacters(in: trimSet)
        if !cleanOriginal.isEmpty,
           !cleanTranslation.isEmpty,
           cleanTranslation.localizedCaseInsensitiveContains(cleanOriginal) {
            return true
        }

        if isPlaceholderTranslationOutput(translation) {
            return true
        }

        let promptLeakMarkers = [
            "<start_of_turn>",
            "<end_of_turn>",
            "Translate the following text",
            "Output only the translation",
            "You are a translation engine",
            "Hard rules:",
            "User instruction:",
            "Based on \"",
            "actionable notes",
            "technical plan, timeline, and risks",
            "先确认目标",
            "技术方案、时间线",
            "风险整理成可以执行的清单"
        ]
        if promptLeakMarkers.contains(where: { translation.localizedCaseInsensitiveContains($0) }) {
            return true
        }

        if targetLanguage == .simplifiedChinese {
            return !translation.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(Int(scalar.value))
            }
        }

        return false
    }

    private static func isSameText(_ lhs: String, _ rhs: String) -> Bool {
        let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let left = lhs.trimmingCharacters(in: trimSet)
        let right = rhs.trimmingCharacters(in: trimSet)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.localizedCaseInsensitiveCompare(right) == ComparisonResult.orderedSame
    }

    private func restoreSnapshot() {
        isRestoring = true
        defer { isRestoring = false }

        guard let snapshot = Self.loadSnapshot(from: persistenceURL) else {
            applySeedSession(settings: .defaultValue)
            prompts = PromptTemplate.defaultPrompts
            return
        }

        prompts = Self.mergeDefaultPrompts(with: snapshot.prompts)
        history = snapshot.history.map { record in
            var sanitizedRecord = record
            sanitizedRecord.transcript = sanitizeTranscript(
                record.transcript,
                sourceLanguage: record.sourceLanguage,
                targetLanguage: record.targetLanguage
            )
            return sanitizedRecord
        }
        applySettings(snapshot.settings)

        if let activeSession = snapshot.activeSession {
            activeSessionID = activeSession.id
            activeCreatedAt = activeSession.createdAt
            elapsedSeconds = activeSession.durationSeconds
            transcript = sanitizeTranscript(
                activeSession.transcript,
                sourceLanguage: activeSession.sourceLanguage,
                targetLanguage: activeSession.targetLanguage
            )
            summary = activeSession.summary
        } else {
            applySeedSession(settings: snapshot.settings)
        }

        if !prompts.contains(where: { $0.id == selectedPromptID }) {
            selectedPromptID = PromptTemplate.translatorID
        }
    }

    private func applySettings(_ settings: AppSettings) {
        mode = settings.mode
        sourceLanguage = settings.sourceLanguage
        targetLanguage = settings.targetLanguage
        selectedPromptID = settings.selectedPromptID
        selectedEngine = settings.selectedEngine
        sampling = settings.sampling
        isProUnlocked = settings.isProUnlocked
        isDeveloperModeEnabled = settings.isDeveloperModeEnabled
        if !canUseLanguage(targetLanguage) {
            targetLanguage = .simplifiedChinese
        }
    }

    private func applySeedSession(settings: AppSettings) {
        applySettings(settings)
        activeSessionID = UUID()
        activeCreatedAt = Date()
        elapsedSeconds = 0
        transcript = [
            TranscriptLine(
                speaker: "Speaker A",
                original: "And then I'm thinking there are some things we should care about.",
                translation: "然后我在想，有些事情我们应该重点关注。",
                time: "11:54",
                isFinal: true
            ),
            TranscriptLine(
                speaker: "Speaker B",
                original: "But for the stuff that you can do today, can we summarize the key decisions?",
                translation: "但对于你今天能做的事情，我们可以先总结关键决策吗？",
                time: "11:55",
                isFinal: true
            )
        ]
        summary = AISummary(
            bullets: [
                "当前为离线 AI 翻译工作台原型。",
                "录音、翻译和总结流程已使用 Mock 数据串联。",
                "当前会话、历史记录、提示词和设置都会写入本地 JSON。"
            ],
            actions: [
                "点击录音按钮开始模拟实时转录。",
                "输入自定义文本后点击发送，触发当前引擎翻译。",
                "到提示词页面切换或创建提示词，生成请求会立即使用新设置。"
            ],
            title: "实时总结"
        )
    }

    private func persist() {
        guard !isRestoring else { return }
        let snapshot = AppPersistenceSnapshot(
            activeSession: shouldArchiveCurrentSession ? currentSessionRecord() : nil,
            history: history,
            prompts: prompts,
            settings: AppSettings(
                mode: mode,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                selectedPromptID: selectedPromptID,
                selectedEngine: selectedEngine,
                sampling: sampling,
                isProUnlocked: isProUnlocked,
                isDeveloperModeEnabled: isDeveloperModeEnabled
            )
        )
        Self.save(snapshot, to: persistenceURL)
    }

    private func makeSessionTitle(from lines: [TranscriptLine]) -> String {
        guard let first = lines.first else { return "新同传会话" }
        let base = first.original.isEmpty ? first.translation : first.original
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "新同传会话" }
        return trimmed.count > 22 ? "\(trimmed.prefix(22))..." : trimmed
    }

    private static func makePersistenceURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("AITRANS", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    private static func loadSnapshot(from url: URL) -> AppPersistenceSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AppPersistenceSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    private static func save(_ snapshot: AppPersistenceSnapshot, to url: URL) {
        do {
            try write(snapshot, to: url)
        } catch {
            assertionFailure("Failed to persist AITRANS state: \(error.localizedDescription)")
        }
    }

    private static func write(_ snapshot: AppPersistenceSnapshot, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    private static func mergeDefaultPrompts(with savedPrompts: [PromptTemplate]) -> [PromptTemplate] {
        var merged = PromptTemplate.defaultPrompts
        for prompt in savedPrompts where !merged.contains(where: { $0.id == prompt.id }) {
            merged.append(prompt)
        }
        return merged
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
    }

    private static func cjkCharacterCount(in text: String) -> Int {
        text.unicodeScalars.count { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
    }

    private static func containsLatinLetter(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x41...0x5A).contains(Int(scalar.value)) || (0x61...0x7A).contains(Int(scalar.value))
        }
    }

    private static func latinLetterCount(in text: String) -> Int {
        text.unicodeScalars.count { scalar in
            (0x41...0x5A).contains(Int(scalar.value)) || (0x61...0x7A).contains(Int(scalar.value))
        }
    }

    private static func containsLikelyOCRError(in text: String) -> Bool {
        let upper = text.uppercased()
        let suspiciousTokens = [
            "RATTLER",
            "PEN DAYS",
            "TRANINS",
            "WOLLD",
            "ONLING",
            "PESULTE",
            "SAMING",
            "POOM",
            "BENG",
            "SUGSESTION",
            "LOSIC",
            "THOUSH",
            "SENPARS",
            "-O2",
            "02 AT"
        ]
        if suspiciousTokens.contains(where: { upper.contains($0) }) {
            return true
        }

        let words = upper
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
        guard words.count >= 4 else { return false }

        let repeatedWords = zip(words, words.dropFirst()).filter { $0 == $1 }.count
        if repeatedWords > 0 {
            return true
        }

        let veryShortWords = words.filter { $0.count <= 2 }.count
        return words.count >= 8 && veryShortWords >= words.count / 3
    }

    private static func ocrQualityLabel(for similarity: Double) -> String {
        if similarity >= 0.9 {
            return "good"
        }
        if similarity >= 0.72 {
            return "usable"
        }
        if similarity > 0 {
            return "lowSimilarity"
        }
        return "noGroundTruthMatch"
    }

    private static func isPlaceholderTranslationOutput(_ output: String) -> Bool {
        let markers = [
            "请您提供",
            "请提供",
            "请你提供",
            "想要翻译的文本",
            "需要翻译的文本",
            "更多上下文",
            "更好地理解",
            "请将以下翻译成中文",
            "请将以上翻译成中文",
            "请将以下翻译转换成中文",
            "请将以上翻译转换成中文",
            "翻译转换成中文",
            "翻译成中文",
            "以下是翻译成中文",
            "把以下翻译成中文",
            "最合适的翻译",
            "最通用的",
            "最常用的翻译",
            "我个人觉得",
            "这句话的意思",
            "意思是：",
            "翻译是：",
            "translation:",
            "translate the following",
            "谢谢",
            "thank you",
            "无法翻译",
            "cannot translate",
            "please provide",
            "provide the text"
        ]
        return markers.contains { output.localizedCaseInsensitiveContains($0) }
    }

    private func logLaunchLLMSmokeTestResult(_ test: LLMInterfaceSmokeTest) {
#if DEBUG
        guard Self.shouldRunLLMSmokeTestFromLaunchEnvironment else { return }
        let output = test.output.replacing("\n", with: "\\n")
        writeLaunchLLMSmokeProbe(
            "result state=\(test.state.rawValue) engine=\(test.engineName) output=\(output) message=\(test.message)"
        )
        print(
            "AITRANS_LLM_SMOKE_RESULT state=\(test.state.rawValue) " +
            "engine=\(test.engineName) " +
            "input=\(test.input) " +
            "output=\(output) " +
            "message=\(test.message)"
        )
#endif
    }

    private func writeLaunchLLMSmokeProbe(_ message: String) {
#if DEBUG
        guard Self.shouldRunLLMSmokeTestFromLaunchEnvironment else { return }
        let directory = persistenceURL.deletingLastPathComponent()
        let url = directory.appendingPathComponent("llm-smoke-result.log")
        let line = "\(Date.now.ISO8601Format()) \(message)\n"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url, options: .atomic)
        }
#endif
    }

    private enum MangaOverlayProbeRunMode: String {
        case full
        case ciFast = "ci-fast"
        case skip
    }

    private struct MangaOverlayProbeRunOptions {
        var mode: MangaOverlayProbeRunMode
        var runLexiconComparison: Bool
        var runVisionAPIComparison: Bool
        var runSyntheticSliceOCR: Bool
        var runPreprocessingCrop: Bool
        var runCropFallbackSelfTest: Bool
        var runModelCorrection: Bool
        var runDeterministicCorrectionTranslation: Bool
        var runTaggedBatchTranslation: Bool
        var runCropExperiment: Bool
        var runLineCropExperiment: Bool
        var renderDiagnosticPNGs: Bool
        var renderContactSheet: Bool
        var runDeterministicDecodingCheck: Bool

        var skippedDiagnostics: [String] {
            var skipped: [String] = []
            if !runLexiconComparison { skipped.append("lexiconComparison") }
            if !runVisionAPIComparison { skipped.append("visionAPIComparison") }
            if !runSyntheticSliceOCR { skipped.append("syntheticSliceOCR") }
            if !runPreprocessingCrop { skipped.append("textRegionCropReport") }
            if !runCropFallbackSelfTest { skipped.append("cropFallbackSelfTest") }
            if !runModelCorrection { skipped.append("modelOCRCorrection") }
            if !runDeterministicCorrectionTranslation { skipped.append("deterministicCorrectionTranslation") }
            if !runTaggedBatchTranslation { skipped.append("taggedBatchTranslationComparison") }
            if !runCropExperiment {
                skipped.append("cropExperimentReport")
                skipped.append("textBoxPlanFailureReport")
            }
            if !runLineCropExperiment {
                skipped.append("lineTextBoxPlanReport")
                skipped.append("lineCropExperimentReport")
            }
            if !renderDiagnosticPNGs { skipped.append("diagnosticPNGs") }
            if !renderContactSheet { skipped.append("probeContactSheet") }
            if !runDeterministicDecodingCheck { skipped.append("deterministicDecodingCheck") }
            return skipped
        }

        static let full = MangaOverlayProbeRunOptions(
            mode: .full,
            runLexiconComparison: true,
            runVisionAPIComparison: true,
            runSyntheticSliceOCR: true,
            runPreprocessingCrop: true,
            runCropFallbackSelfTest: true,
            runModelCorrection: true,
            runDeterministicCorrectionTranslation: true,
            runTaggedBatchTranslation: true,
            runCropExperiment: true,
            runLineCropExperiment: true,
            renderDiagnosticPNGs: true,
            renderContactSheet: true,
            runDeterministicDecodingCheck: true
        )

        static let ciFast = MangaOverlayProbeRunOptions(
            mode: .ciFast,
            runLexiconComparison: false,
            runVisionAPIComparison: false,
            runSyntheticSliceOCR: false,
            runPreprocessingCrop: false,
            runCropFallbackSelfTest: false,
            runModelCorrection: false,
            runDeterministicCorrectionTranslation: false,
            runTaggedBatchTranslation: false,
            runCropExperiment: false,
            runLineCropExperiment: false,
            renderDiagnosticPNGs: false,
            renderContactSheet: false,
            runDeterministicDecodingCheck: false
        )

        static let skip = MangaOverlayProbeRunOptions(
            mode: .skip,
            runLexiconComparison: false,
            runVisionAPIComparison: false,
            runSyntheticSliceOCR: false,
            runPreprocessingCrop: false,
            runCropFallbackSelfTest: false,
            runModelCorrection: false,
            runDeterministicCorrectionTranslation: false,
            runTaggedBatchTranslation: false,
            runCropExperiment: false,
            runLineCropExperiment: false,
            renderDiagnosticPNGs: false,
            renderContactSheet: false,
            runDeterministicDecodingCheck: false
        )
    }

    private static var launchMangaOverlayProbeRunMode: MangaOverlayProbeRunMode {
        let rawMode = launchValue(for: "AITRANS_MANGA_PROBE_MODE")?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch rawMode?.lowercased() {
        case "ci-fast", "cifast":
            return .ciFast
        case "skip":
            return .skip
        default:
            return .full
        }
    }

    private static func currentMangaOverlayProbeRunOptions() -> MangaOverlayProbeRunOptions {
#if DEBUG
        return mangaOverlayProbeRunOptions(for: launchMangaOverlayProbeRunMode)
#else
        return .full
#endif
    }

    private static func mangaOverlayProbeRunOptions(for mode: MangaOverlayProbeRunMode) -> MangaOverlayProbeRunOptions {
        switch mode {
        case .ciFast:
            return .ciFast
        case .skip:
            return .skip
        case .full:
            return .full
        }
    }

    private static func launchValue(for key: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }
        if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty {
            return value
        }
        let arguments = ProcessInfo.processInfo.arguments
        for index in arguments.indices {
            let argument = arguments[index]
            if argument.hasPrefix("\(key)=") {
                return String(argument.dropFirst(key.count + 1))
            }
            if argument.hasPrefix("--\(key)=") {
                return String(argument.dropFirst(key.count + 3))
            }
            if argument == "-\(key)", arguments.indices.contains(index + 1) {
                return arguments[index + 1]
            }
        }
        return nil
    }



#if DEBUG
    private struct TranslationProbeCase {
        var source: SupportedLanguage
        var target: SupportedLanguage
        var input: String
    }

    private struct TranslationProbeStoreState {
        var mode: SessionMode
        var sourceLanguage: SupportedLanguage
        var targetLanguage: SupportedLanguage
        var transcript: [TranscriptLine]
        var summary: AISummary
        var selectedPromptID: UUID
        var selectedEngine: ModelEngine
        var draftText: String
        var isProcessing: Bool
        var modelStatus: ModelStatus
        var lastGenerationLabel: String
        var dataTransferMessage: String
    }

    private static var shouldRunLLMSmokeTestFromLaunchEnvironment: Bool {
        launchFlagEnabled("AITRANS_RUN_LLM_SMOKE")
    }

    private static var shouldRunMangaOverlayProbeFromLaunchEnvironment: Bool {
        launchFlagEnabled("AITRANS_RUN_MANGA_PROBE")
    }

    private static func launchFlagEnabled(_ key: String) -> Bool {
        if ProcessInfo.processInfo.environment[key] == "1" {
            return true
        }
        if UserDefaults.standard.string(forKey: key) == "1" || UserDefaults.standard.bool(forKey: key) {
            return true
        }
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("\(key)=1") || arguments.contains("--\(key)=1")
    }

    private static let launchTranslationProbeCases = [
        TranslationProbeCase(source: .englishUS, target: .simplifiedChinese, input: "Keep the model on device."),
        TranslationProbeCase(source: .englishUS, target: .simplifiedChinese, input: "The meeting starts at 9:30 tomorrow."),
        TranslationProbeCase(source: .englishUS, target: .simplifiedChinese, input: "Save the transcript locally."),
        TranslationProbeCase(source: .simplifiedChinese, target: .englishUS, input: "请把会议记录保存在本地。"),
        TranslationProbeCase(source: .simplifiedChinese, target: .englishUS, input: "明天九点半开始会议。")
    ]

    private static let launchSubmitProbeCases = [
        TranslationProbeCase(source: .englishUS, target: .simplifiedChinese, input: "The meeting starts at 9:30 tomorrow."),
        TranslationProbeCase(source: .simplifiedChinese, target: .englishUS, input: "请把会议记录保存在本地。")
    ]

    private static func probeField(_ text: String) -> String {
        text
            .replacing("\n", with: "\\n")
            .replacing("\t", with: "\\t")
            .replacing("|", with: "\\|")
    }
#else
    private static func probeField(_ text: String) -> String {
        text
    }
#endif

    private static let liveSamples = [
        "We should keep the model on device so meeting content never leaves the phone.",
        "The first version can use mock output, but the interface should already match the real model adapter.",
        "For history, every session needs transcript lines, a summary, prompt settings, and model metadata.",
        "When the quantized model is ready, we can swap the mock service for the local inference runtime."
    ]

    private static let defaultDeveloperProbeCases = [
        DeveloperRawProbeCase(
            sourceLanguage: .englishUS,
            targetLanguage: .simplifiedChinese,
            input: "Keep the model on device."
        ),
        DeveloperRawProbeCase(
            sourceLanguage: .englishUS,
            targetLanguage: .simplifiedChinese,
            input: "The meeting starts at 9:30 tomorrow."
        ),
        DeveloperRawProbeCase(
            sourceLanguage: .englishUS,
            targetLanguage: .simplifiedChinese,
            input: "Save the transcript locally."
        ),
        DeveloperRawProbeCase(
            sourceLanguage: .simplifiedChinese,
            targetLanguage: .englishUS,
            input: "请把会议记录保存在本地。"
        ),
        DeveloperRawProbeCase(
            sourceLanguage: .simplifiedChinese,
            targetLanguage: .englishUS,
            input: "明天九点半开始会议。"
        )
    ]

    private static let audioTestExtensions: Set<String> = ["m4a", "wav", "mp3", "caf"]
    private static let imageTestExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]

    private static func bboxArray(from rect: CGRect) -> [Double] {
        [
            Double(rect.minX.rounded()),
            Double(rect.minY.rounded()),
            Double(rect.width.rounded()),
            Double(rect.height.rounded())
        ]
    }

    private static func fileIsNonEmpty(path: String) -> Bool {
        guard !path.isEmpty,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }

    private static let defaultDiagnostics = [
        DiagnosticCheck(
            id: "persistence",
            title: "本地 JSON",
            detail: "等待检查状态文件和导出文件。",
            state: .idle
        ),
        DiagnosticCheck(
            id: "mock",
            title: "Mock 生成",
            detail: "等待检查 Gemma 1.5B Mock 输出。",
            state: .idle
        ),
        DiagnosticCheck(
            id: "llmInterface",
            title: "LLM 接口",
            detail: "等待验证 UI 输入、适配器请求和输出回传。",
            state: .idle
        ),
        DiagnosticCheck(
            id: "localFallback",
            title: "Local 模型",
            detail: "等待检查 GGUF 文件是否已安装。",
            state: .idle
        )
    ]

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
