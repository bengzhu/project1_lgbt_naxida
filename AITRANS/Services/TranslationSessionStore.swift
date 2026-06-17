import Combine
import Foundation
import Speech

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
    @Published var audioRecognitionState: AudioRecognitionState = .idle
    @Published var audioRecognitionMessage = "选择音频文件后，会强制使用 Apple 本机语音识别测试离线能力"
    @Published var lastRecognizedSpeechText = ""
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
    private var ticker: Task<Void, Never>?
    private var modelDownloadTask: Task<Void, Never>?
    private var audioRecognitionTask: SFSpeechRecognitionTask?
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
                isProUnlocked: isProUnlocked
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

    func createPrompt(title: String, instruction: String, tone: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTone = tone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanInstruction.isEmpty else { return }

        let prompt = PromptTemplate(
            title: cleanTitle,
            instruction: cleanInstruction,
            tone: cleanTone.isEmpty ? "自然、准确" : cleanTone
        )
        prompts.insert(prompt, at: 0)
        selectedPromptID = prompt.id
    }

    func updatePrompt(_ prompt: PromptTemplate, title: String, instruction: String, tone: String) {
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }), !prompts[index].isBuiltIn else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTone = tone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanInstruction.isEmpty else { return }

        prompts[index].title = cleanTitle
        prompts[index].instruction = cleanInstruction
        prompts[index].tone = cleanTone.isEmpty ? "自然、准确" : cleanTone
        prompts[index].updatedAt = Date()
    }

    func duplicatePrompt(_ prompt: PromptTemplate) {
        let copy = PromptTemplate(
            title: "\(prompt.title) 副本",
            instruction: prompt.instruction,
            tone: prompt.tone
        )
        prompts.insert(copy, at: 0)
        selectedPromptID = copy.id
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
        isRunningLLMSmokeTest = true
        llmSmokeTest = LLMInterfaceSmokeTest(
            input: LLMInterfaceSmokeTest.defaultInput,
            output: "",
            state: .running,
            message: "正在通过当前适配器发送模拟请求...",
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
    private func submit(_ text: String, timestamp: String) async -> Bool {
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
            draftText = ""
            await refreshSummaryAfterTranslation()
            return true
        } catch {
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
        let result = try await generateWithSelectedEngine(request)
        return result.text
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
            writeLaunchLLMSmokeProbe("generate-start task=\(request.task.rawValue) input=\(request.inputText)")
            let result = try await primary.generate(request)
            writeLaunchLLMSmokeProbe(
                "generate-done engine=\(result.engineName) chars=\(result.text.count) output=\(result.text)"
            )
            lastGenerationLabel = "\(result.engineName) · \(result.durationMilliseconds ?? 0)ms"
            return result
        } catch {
            writeLaunchLLMSmokeProbe("generate-error \(error.localizedDescription)")
            guard selectedEngine == .local, error is GemmaLocalServiceError else { throw error }
            guard !isLocalModelInstalled else { throw error }
            try await mockService.prepare()
            let fallback = try await mockService.generate(request)
            lastGenerationLabel = "Local 缺失，已回退 Mock · \(fallback.durationMilliseconds ?? 0)ms"
            dataTransferMessage = "Local 缺失：请先下载或导入 GGUF。已临时回退 Mock。"
            refreshModelStatus()
            return fallback
        }
    }

    private func performLLMInterfaceSmokeTest() async {
        let input = llmSmokeTest.input.isEmpty ? LLMInterfaceSmokeTest.defaultInput : llmSmokeTest.input
        writeLaunchLLMSmokeProbe("perform-start input=\(input)")
        llmSmokeTest = LLMInterfaceSmokeTest(
            input: input,
            output: "",
            state: .running,
            message: "正在通过当前适配器发送模拟请求...",
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
            let passed = !trimmedOutput.isEmpty && !repeatsInput
            let message: String
            if trimmedOutput.isEmpty {
                message = "接口异常：适配器返回空输出。"
            } else if repeatsInput {
                message = "接口异常：适配器返回了原始输入。"
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

#if DEBUG
    private func runLaunchTranslationProbeSuite() async {
        guard !isRunningLLMSmokeTest, !isRunningDiagnostics else { return }
        isRunningLLMSmokeTest = true
        defer {
            isRunningLLMSmokeTest = false
            persist()
        }

        writeLaunchLLMSmokeProbe("translation-probe-suite-start cases=\(Self.launchTranslationProbeInputs.count)")

        var passedCount = 0
        var lastOutput = ""
        var lastMessage = ""

        for (index, input) in Self.launchTranslationProbeInputs.enumerated() {
            let caseNumber = index + 1
            let request = makeRequest(task: .translation, inputText: input)

            do {
                let result = try await generateWithSelectedEngine(request)
                let verdict = translationProbeVerdict(input: input, output: result.text)
                if verdict.passed {
                    passedCount += 1
                }
                lastOutput = result.text
                lastMessage = verdict.message
                writeLaunchLLMSmokeProbe(
                    "translation-probe case=\(caseNumber) " +
                    "state=\(verdict.passed ? "passed" : "failed") " +
                    "engine=\(result.engineName) " +
                    "duration=\(result.durationMilliseconds ?? 0)ms " +
                    "input=\(Self.probeField(input)) " +
                    "output=\(Self.probeField(result.text)) " +
                    "reason=\(Self.probeField(verdict.message))"
                )
            } catch {
                lastMessage = error.localizedDescription
                writeLaunchLLMSmokeProbe(
                    "translation-probe case=\(caseNumber) state=failed " +
                    "input=\(Self.probeField(input)) error=\(Self.probeField(error.localizedDescription))"
                )
            }
        }

        let allPassed = passedCount == Self.launchTranslationProbeInputs.count
        let suiteMessage = "翻译接口探针 \(passedCount)/\(Self.launchTranslationProbeInputs.count) 通过。\(lastMessage)"
        llmSmokeTest = LLMInterfaceSmokeTest(
            input: Self.launchTranslationProbeInputs.joined(separator: " | "),
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
            "passed=\(passedCount)/\(Self.launchTranslationProbeInputs.count)"
        )
    }

    private func translationProbeVerdict(input: String, output: String) -> (passed: Bool, message: String) {
        let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let cleanInput = input.trimmingCharacters(in: trimSet)
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

        guard Self.containsCJK(output) else {
            return (false, "输出不是中文")
        }

        guard !output.localizedCaseInsensitiveContains("简体中文翻译") else {
            return (false, "输出是模板占位")
        }

        return (true, "有效中文译文")
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
                isProUnlocked: isProUnlocked
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
    private static var shouldRunLLMSmokeTestFromLaunchEnvironment: Bool {
        ProcessInfo.processInfo.environment["AITRANS_RUN_LLM_SMOKE"] == "1"
    }

    private static let launchTranslationProbeInputs = [
        "Keep the model on device.",
        "Translate this short sentence.",
        "The meeting starts at 9:30 tomorrow.",
        "Save the transcript locally."
    ]

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
    }

    private static func probeField(_ text: String) -> String {
        text
            .replacing("\n", with: "\\n")
            .replacing("\t", with: "\\t")
            .replacing("|", with: "\\|")
    }
#endif

    private static let liveSamples = [
        "We should keep the model on device so meeting content never leaves the phone.",
        "The first version can use mock output, but the interface should already match the real model adapter.",
        "For history, every session needs transcript lines, a summary, prompt settings, and model metadata.",
        "When the quantized model is ready, we can swap the mock service for the local inference runtime."
    ]

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
