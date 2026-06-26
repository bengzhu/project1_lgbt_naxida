import Combine
import AVFoundation
import Foundation
import Speech
import StoreKit

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
    private var audioRecognitionTask: SFSpeechRecognitionTask?
    private var liveAudioEngine: AVAudioEngine?
    private var liveSpeechRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var proSubscriptionProduct: Product?
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

    func translateImage(from url: URL) {
        guard !isProcessing else { return }
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

        imageTranslationState = .loading
        imageTranslationMessage = "正在载入图片"
        imageTranslationBlocks = []
        imageTranslationData = nil
        imageTranslationRevision += 1
        imageTranslationFilename = url.lastPathComponent
        isProcessing = true

        Task { [weak self] in
            guard let self else { return }

            do {
                let data = try await Self.loadSecurityScopedData(from: url)
                self.imageTranslationData = data
                self.imageTranslationRevision += 1
                self.imageTranslationState = .recognizing
                self.imageTranslationMessage = "正在用 Vision 本机 OCR 识别文字和位置"

                let recognizedBlocks = try await self.visionOCRService.recognizeTextBlocks(
                    in: data,
                    sourceLanguage: self.sourceLanguage
                )
                guard !recognizedBlocks.isEmpty else {
                    self.imageTranslationState = .failed
                    self.imageTranslationMessage = "Vision OCR 没有识别到可翻译文字"
                    self.dataTransferMessage = self.imageTranslationMessage
                    self.isProcessing = false
                    return
                }

                self.imageTranslationBlocks = recognizedBlocks
                self.imageTranslationState = .translating
                self.imageTranslationMessage = "已识别 \(recognizedBlocks.count) 个文本块，正在交给本地模型翻译"

                var translatedBlocks: [ImageTranslationBlock] = []
                for block in recognizedBlocks {
                    var translatedBlock = block
                    translatedBlock.translation = try await self.translate(block.original)
                    translatedBlocks.append(translatedBlock)
                    self.imageTranslationBlocks = translatedBlocks + Array(recognizedBlocks.dropFirst(translatedBlocks.count))
                }

                self.imageTranslationBlocks = translatedBlocks
                self.imageTranslationState = .translated
                self.imageTranslationMessage = "已完成 Vision OCR、本地翻译和定位覆盖"
                self.dataTransferMessage = self.imageTranslationMessage
                self.appendImageTranslationTranscript(blocks: translatedBlocks)
                self.isProcessing = false
                self.persist()
            } catch {
                self.imageTranslationState = .failed
                self.imageTranslationMessage = "图片翻译失败：\(error.localizedDescription)"
                self.dataTransferMessage = self.imageTranslationMessage
                self.isProcessing = false
                self.persist()
            }
        }
    }

    func clearImageTranslation() {
        imageTranslationState = .idle
        imageTranslationMessage = "选择图片后，会用 Apple Vision 本机 OCR 识别文字并定位"
        imageTranslationBlocks = []
        imageTranslationData = nil
        imageTranslationFilename = ""
        imageTranslationRevision += 1
    }

    func setImageOverlayMode(_ mode: ImageTranslationOverlayMode) {
        imageOverlayMode = mode
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
                let data = try Data(contentsOf: url)
                self.mangaOverlayProbeState = .recognizing
                self.mangaOverlayProbeMessage = "正在用 0/90/180/270 多角度 Vision OCR"
                let recognized = try await self.mangaOverlayProbeService.recognizeTextBlocks(in: data)

                var probeBlocks = recognized.blocks.enumerated().map { index, block in
                    MangaOverlayProbeBlock(
                        index: index,
                        bbox: Self.bboxArray(from: block.boundingBox),
                        rotationAngleUsed: block.rotationAngle,
                        ocrText: block.text,
                        ocrConfidence: block.confidence
                    )
                }
                self.mangaOverlayProbeBlocks = probeBlocks

                self.mangaOverlayProbeState = .translating
                self.mangaOverlayProbeMessage = "已识别 \(probeBlocks.count) 个文本块，正在逐块翻译"

                for index in probeBlocks.indices {
                    let translated = await self.translateMangaProbeBlock(probeBlocks[index])
                    probeBlocks[index] = translated
                    self.mangaOverlayProbeBlocks = probeBlocks
                }

                self.mangaOverlayProbeState = .rendering
                self.mangaOverlayProbeMessage = "正在生成 bbox 调试图、覆盖合成图和 probe_report.json"
                let outputFiles = try await self.mangaOverlayProbeService.renderOutputs(
                    image: recognized.image,
                    blocks: probeBlocks,
                    outputDirectory: self.mangaOverlayOutputDirectory
                )

                let report = self.makeMangaOverlayProbeReport(
                    blocks: probeBlocks,
                    outputFiles: outputFiles
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
                    extraWarnings: ["运行错误：\(type(of: error)): \(error.localizedDescription)"]
                )
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

    private func translateMangaProbeBlock(_ block: MangaOverlayProbeBlock) async -> MangaOverlayProbeBlock {
        let request = makeProbeRequest(
            source: .englishUS,
            target: .simplifiedChinese,
            input: block.ocrText
        )
        let prompt: String
        let rawOutput: String
        let translatedText: String
        let errorCode: String?

        if selectedEngine == .local {
            let probe = localService.rawTranslationProbe(for: request)
            prompt = probe.prompt
            rawOutput = probe.output
            translatedText = probe.output.trimmingCharacters(in: .whitespacesAndNewlines)
            errorCode = probe.errorCode
        } else {
            prompt = debugPromptPreview(for: request) + "\n\n注意：Mock 模式为模拟输出，不是真实模型 raw prompt。"
            do {
                try await mockService.prepare()
                let result = try await mockService.generate(request)
                rawOutput = result.text
                translatedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                errorCode = nil
            } catch {
                rawOutput = ""
                translatedText = ""
                errorCode = "\(type(of: error)): \(error.localizedDescription)"
            }
        }

        let checks = mangaProbeChecks(
            original: block.ocrText,
            translation: translatedText,
            errorCode: errorCode
        )

        return MangaOverlayProbeBlock(
            id: block.id,
            index: block.index,
            bbox: block.bbox,
            rotationAngleUsed: block.rotationAngleUsed,
            ocrText: block.ocrText,
            ocrConfidence: block.ocrConfidence,
            translatedText: translatedText,
            prompt: prompt,
            rawOutput: rawOutput,
            errorCode: errorCode,
            checks: checks,
            blockPassed: Self.mangaProbeBlockPassed(checks, errorCode: errorCode)
        )
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
            looksLikeChinese: translationNotEmpty && Self.containsCJK(cleanTranslation)
        )
    }

    private static func mangaProbeBlockPassed(_ checks: MangaOverlayProbeChecks, errorCode: String?) -> Bool {
        errorCode == nil
            && checks.ocrNotEmpty
            && checks.translationNotEmpty
            && checks.translationNotEqualOriginal
            && checks.translationNotContainOriginal
            && checks.looksLikeChinese
    }

    private func makeMangaOverlayProbeReport(
        blocks: [MangaOverlayProbeBlock],
        outputFiles: MangaOverlayProbeOutputFiles,
        extraWarnings: [String] = []
    ) -> MangaOverlayProbeReport {
        var warnings = extraWarnings
        if blocks.isEmpty {
            warnings.append("检测到 0 个文字块")
        }
        for block in blocks where !block.blockPassed {
            warnings.append("block \(block.index) 判定失败")
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

        let allBlocksPassed = !blocks.isEmpty && blocks.allSatisfy(\.blockPassed)
        let filesPresent = Self.fileIsNonEmpty(path: outputFiles.debugBoxesImage)
            && Self.fileIsNonEmpty(path: outputFiles.overlayImage)
        return MangaOverlayProbeReport(
            sourceImage: "test/1.png",
            engineUsed: selectedAdapterMetadata.displayName,
            totalBlocksDetected: blocks.count,
            blocks: blocks,
            overallPassed: allBlocksPassed && filesPresent,
            outputFiles: outputFiles,
            warnings: warnings
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

    private static func containsLatinLetter(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x41...0x5A).contains(Int(scalar.value)) || (0x61...0x7A).contains(Int(scalar.value))
        }
    }

    private static func isPlaceholderTranslationOutput(_ output: String) -> Bool {
        let markers = [
            "请您提供",
            "请提供",
            "想要翻译的文本",
            "需要翻译的文本",
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
