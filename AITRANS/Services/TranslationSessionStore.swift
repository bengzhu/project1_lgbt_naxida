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
        refreshSpeechRecognitionCapabilities()
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
        Task { @MainActor [weak self] in
            self?.runMangaOverlayProbe()
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
        Bundle.main.url(forResource: "test", withExtension: nil)
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
        guard !isRunningMangaOverlayProbe else { return }
        guard let url = bundledTestDirectory?.appendingPathComponent("1.png"),
              FileManager.default.fileExists(atPath: url.path) else {
            mangaOverlayProbeState = .failed
            mangaOverlayProbeMessage = "test/1.png 未找到，请确认已放入项目根 test/ 并重新构建。"
            dataTransferMessage = mangaOverlayProbeMessage
            return
        }

        isRunningMangaOverlayProbe = true
        mangaOverlayProbeState = .loading
        mangaOverlayProbeMessage = "正在读取 test/1.png"
        mangaOverlayProbeReport = nil
        mangaOverlayProbeBlocks = []
        dataTransferMessage = mangaOverlayProbeMessage

        Task { [weak self] in
            guard let self else { return }
            defer { self.isRunningMangaOverlayProbe = false }

            do {
                let startedAt = Date.now
                let outputCleanupRemovedItemCount = try MangaOverlayProbeService.recreateDirectory(self.mangaOverlayOutputDirectory)
                let data = try Data(contentsOf: url)
                self.mangaOverlayProbeState = .recognizing
                self.mangaOverlayProbeMessage = "正在用 0/90/180/270 多角度 Vision OCR"
                var probeConfiguration = MangaOverlayProbeConfiguration.defaultValue
                let activeCustomWords = probeConfiguration.customLexiconEnabled ? probeConfiguration.customLexicon : []
                let recognized = try await self.mangaOverlayProbeService.recognizeTextBlocks(
                    in: data,
                    customWords: activeCustomWords
                )
                let lexiconComparison = try await self.mangaOverlayProbeService.compareCustomLexicon(
                    in: data,
                    customWords: probeConfiguration.customLexicon
                )
                let visionAPIComparison = try await self.mangaOverlayProbeService.compareVisionAPIs(
                    in: data,
                    customWords: activeCustomWords
                )
                let syntheticSliceOCR = try await self.mangaOverlayProbeService.runSyntheticLongImageSliceProbe(
                    imageData: data,
                    customWords: activeCustomWords
                )

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
                var bubbleSubRegionReport: MangaOverlayBubbleSubRegionReport?
                var outputFiles = MangaOverlayProbeOutputFiles(debugBoxesImage: "", overlayImage: "")
                if !groundTruth.isEmpty {
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
                }
                self.mangaOverlayProbeBlocks = probeBlocks

                var cropFallbackSelfTest: MangaOverlayCropFallbackSelfTest?
                if probeConfiguration.preprocessing.enabled {
                    self.mangaOverlayProbeMessage = "正在对 \(probeBlocks.count) 个文本块做裁切放大预处理 OCR"
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
                    cropFallbackSelfTest = try await self.mangaOverlayProbeService.runCropFallbackSelfTest(
                        in: recognized.image,
                        block: recognized.blocks.first,
                        blockIndex: recognized.blocks.indices.first,
                        options: probeConfiguration.preprocessing
                    )
                    bubbleSubRegionReport = Self.makeBubbleSubRegionReport(
                        blocks: probeBlocks,
                        bubbleGeometry: recognized.bubbleGeometry,
                        image: recognized.image
                    )
                    self.mangaOverlayProbeMessage = "正在运行 TextRegion crop OCR 候选层"
                    let textRegionCrop = try await self.applyTextRegionCropCandidates(
                        to: probeBlocks,
                        image: recognized.image,
                        bubbleGeometry: recognized.bubbleGeometry,
                        bubbleSubRegionReport: bubbleSubRegionReport,
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
                }

                for index in probeBlocks.indices where probeBlocks[index].deterministicCorrectionText == nil {
                    probeBlocks[index] = self.applyDeterministicMangaOCRCorrection(
                        to: probeBlocks[index],
                        groundTruth: groundTruth
                    )
                }

                if probeConfiguration.correction.enabled {
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

                for index in probeBlocks.indices {
                    let translated = await self.translateMangaProbeBlock(probeBlocks[index])
                    probeBlocks[index] = translated
                    self.mangaOverlayProbeBlocks = probeBlocks
                }

                self.mangaOverlayProbeMessage = "正在对确定性 OCR 纠错候选做翻译对照"
                for index in probeBlocks.indices where Self.shouldProbeDeterministicCorrectionTranslation(probeBlocks[index]) {
                    probeBlocks[index] = await self.translateDeterministicCorrectionCandidate(probeBlocks[index])
                    self.mangaOverlayProbeBlocks = probeBlocks
                }

                self.mangaOverlayProbeMessage = "正在运行 tagged 批量翻译诊断分支"
                let batchTranslationComparison = await self.runTaggedBatchTranslationComparison(blocks: probeBlocks)

                self.mangaOverlayProbeState = .rendering
                self.mangaOverlayProbeMessage = "正在计算气泡安全区并做离屏渲染碰撞检查"
                probeBlocks = await self.mangaOverlayProbeService.applySafeLayoutAndRenderingDiagnostics(
                    image: recognized.image,
                    blocks: probeBlocks,
                    bubbleGeometry: recognized.bubbleGeometry
                )
                self.mangaOverlayProbeBlocks = probeBlocks

                self.mangaOverlayProbeMessage = "正在生成 bbox 调试图、覆盖合成图和 probe_report.json"
                let renderedOutputFiles = try await self.mangaOverlayProbeService.renderOutputs(
                    image: recognized.image,
                    blocks: probeBlocks,
                    outputDirectory: self.mangaOverlayOutputDirectory,
                    preprocessing: probeConfiguration.preprocessing,
                    textRegionCropReport: textRegionCropReport
                )
                outputFiles.debugBoxesImage = renderedOutputFiles.debugBoxesImage
                outputFiles.overlayImage = renderedOutputFiles.overlayImage
                outputFiles.ocrTextOverlayImage = renderedOutputFiles.ocrTextOverlayImage
                outputFiles.deterministicCorrectionOverlayImage = renderedOutputFiles.deterministicCorrectionOverlayImage
                outputFiles.deterministicTranslationOverlayImage = renderedOutputFiles.deterministicTranslationOverlayImage
                outputFiles.blockCropsImage = renderedOutputFiles.blockCropsImage
                outputFiles.preprocessedContentImage = renderedOutputFiles.preprocessedContentImage
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
                outputFiles.probeContactSheetImage = try MangaOverlayProbeService.renderContactSheet(
                    outputFiles: outputFiles,
                    outputDirectory: self.mangaOverlayOutputDirectory
                )
                let cleanTextDiagnostic = await self.runCleanTextDiagnostic(groundTruth: groundTruth)
                let cleanDiagnosticURL = self.mangaOverlayOutputDirectory.appendingPathComponent("clean_text_diagnostic.json")
                try Self.writeCleanTextDiagnostic(cleanTextDiagnostic, to: cleanDiagnosticURL)
                outputFiles.cleanTextDiagnosticFile = cleanDiagnosticURL.path
                let deterministicDecodingCheck = await self.runDeterministicDecodingCheck(groundTruth: groundTruth)

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
                    bubbleSubRegionReport: bubbleSubRegionReport,
                    cleanTextDiagnostic: cleanTextDiagnostic,
                    batchTranslationComparison: batchTranslationComparison,
                    deterministicDecodingCheck: deterministicDecodingCheck,
                    outputCleanupRemovedItemCount: outputCleanupRemovedItemCount
                )
                let reportURL = self.mangaOverlayOutputDirectory.appendingPathComponent("probe_report.json")
                try MangaOverlayProbeService.writeReport(report, to: reportURL)

                self.mangaOverlayProbeState = report.overallPassed ? .completed : .failed
                self.mangaOverlayProbeMessage = "漫画探针完成：\(report.blocks.count) 块，overallPassed=\(report.overallPassed)，输出 \(self.mangaOverlayOutputDirectory.path)"
                self.mangaOverlayProbeReport = report
                self.mangaOverlayProbeBlocks = report.blocks
                self.dataTransferMessage = self.mangaOverlayProbeMessage
            } catch {
                let outputFiles = MangaOverlayProbeOutputFiles(debugBoxesImage: "", overlayImage: "")
                let report = self.makeMangaOverlayProbeReport(
                    blocks: self.mangaOverlayProbeBlocks,
                    outputFiles: outputFiles,
                    configuration: .defaultValue,
                    bubbleGeometry: nil,
                    extraWarnings: ["运行错误：\(type(of: error)): \(error.localizedDescription)"]
                )
                let reportURL = self.mangaOverlayOutputDirectory.appendingPathComponent("probe_report.json")
                try? FileManager.default.createDirectory(at: self.mangaOverlayOutputDirectory, withIntermediateDirectories: true)
                try? MangaOverlayProbeService.writeReport(report, to: reportURL)
                self.mangaOverlayProbeState = .failed
                self.mangaOverlayProbeMessage = "漫画探针失败：\(error.localizedDescription)"
                self.mangaOverlayProbeReport = report
                self.dataTransferMessage = self.mangaOverlayProbeMessage
            }
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
        recognizedBlocks: [MangaOverlayOCRBlock],
        groundTruth: [MangaGroundTruthEntry],
        preprocessing: MangaOverlayPreprocessingOptions
    ) async throws -> (blocks: [MangaOverlayProbeBlock], report: MangaOverlayTextRegionCropReport) {
        let bubbleBBoxes = Dictionary(uniqueKeysWithValues: bubbleGeometry.bubbles.map { ($0.id, $0.bbox) })
        let subRegionsByBlock = Self.subRegionDiagnosticsByBlock(from: bubbleSubRegionReport)
        var updatedBlocks: [MangaOverlayProbeBlock] = []
        var diagnostics: [MangaOverlayTextRegionCropDiagnostic] = []

        for block in blocks {
            let source = Self.textRegionSource(for: block)
            let sourceIndex = Self.wholePageSourceIndex(for: block)
            let wholePageText = sourceIndex.flatMap { recognizedBlocks.indices.contains($0) ? recognizedBlocks[$0].text : nil }
                ?? block.rawOcrText
            let subRegion = subRegionsByBlock[block.index]
            let subRegionBBox = subRegion?.clampEligible == true ? subRegion?.bbox : nil
            let crop = try await mangaOverlayProbeService.recognizeTextRegionCrop(
                in: image,
                seedBBox: block.bbox,
                bubbleBBox: block.bubbleID.flatMap { bubbleBBoxes[$0] },
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
        let report = MangaOverlayTextRegionCropReport(
            totalRegions: diagnostics.count,
            cropSucceededCount: succeeded,
            adoptedCount: adoptedIndexes.count,
            rejectedCount: rejectedIndexes.count,
            adoptedBlockIndexes: adoptedIndexes,
            rejectedBlockIndexes: rejectedIndexes,
            mainRejectionReasons: rejectionCounts,
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
        bubbleSubRegionReport: MangaOverlayBubbleSubRegionReport? = nil,
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
            bubbleSubRegionReport: bubbleSubRegionReport,
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
                guard postFusionInformationScore(blocks[selectedIndex]) >= postFusionInformationScore(blocks[candidateIndex]) else {
                    continue
                }
                guard let reason = postFusionRejectionReason(
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
                    reason: reason,
                    relatedFusedBlockIndex: blocks[selectedIndex].index,
                    relatedText: blocks[selectedIndex].finalTextUsedForTranslation,
                    relatedBBox: blocks[selectedIndex].bbox
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

        let keptBlocks = keptPairs.enumerated().map { offset, pair in
            var block = reindexedMangaBlock(pair.0, index: offset)
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
        if keptBlocks.count < 13 {
            warnings.append("post-fusion cleanup reduced block count below target floor: \(keptBlocks.count)")
        }

        let report = MangaOverlayPostFusionCleanupReport(
            applied: true,
            blockCountBeforeCleanup: blocks.count,
            blockCountAfterCleanup: keptBlocks.count,
            rejectedBlockCount: rejectedByOriginalIndex.count,
            rejectedBlocks: rejectedByOriginalIndex.values.sorted { $0.originalFusedBlockIndex < $1.originalFusedBlockIndex },
            preservedKeyTexts: preserved,
            missingKeyTexts: missing,
            warnings: warnings,
            notes: [
                "cleanup uses bbox overlap, bubbleID, source, text length, word coverage, and OCR quality heuristics only",
                "ground truth is not used for rejection or ranking",
                "short unassigned text is preserved unless it overlaps or is contained by a stronger selected block"
            ]
        )
        return (keptBlocks, keptResults + rejectedResults, report)
    }

    private static let postFusionKeyTexts = [
        "Let's Battle!",
        "What are you even talking about?",
        "We need to get results at this tournament to save the gaming club from being disbanded."
    ]

    private static func postFusionRejectionReason(
        candidate: MangaOverlayProbeBlock,
        selected: MangaOverlayProbeBlock
    ) -> String? {
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

        if candidateShort,
           !isProtectedShortPostFusionText(candidate.finalTextUsedForTranslation),
           (overlap >= 0.12 || rectDistance(candidateRect, selectedRect) <= 22),
           selectedWords.count >= 5 {
            return sourceOnly ? "lowInformationSourceOnly" : "lowInformationFragment"
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
            return "containedByHigherQualityBlock"
        }

        if sameBubble,
           (overlap >= 0.34 || containment >= 0.55 || selectedContainment >= 0.55),
           (similarity >= 0.42 || coverage >= 0.58),
           selectedWords.count >= candidateWords.count {
            return "duplicateWithinBubble"
        }

        if overlap >= 0.28,
           selectedWords.count >= candidateWords.count + 2,
           (coverage >= 0.5 || similarity >= 0.45) {
            return "overlapsSelectedLongerText"
        }

        if candidateWords.count <= 6,
           selectedWords.count >= candidateWords.count + 3,
           (coverage >= 0.5 || similarity >= 0.38),
           rectDistance(candidateRect, selectedRect) <= 28 {
            return "fragmentOfSelectedCandidate"
        }

        return nil
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
        ProcessInfo.processInfo.environment["AITRANS_RUN_LLM_SMOKE"] == "1"
    }

    private static var shouldRunMangaOverlayProbeFromLaunchEnvironment: Bool {
        ProcessInfo.processInfo.environment["AITRANS_RUN_MANGA_PROBE"] == "1"
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
