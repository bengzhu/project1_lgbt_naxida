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
    @Published var dataTransferMessage = "本地数据已准备好"
    @Published var isProUnlocked = false {
        didSet { persist() }
    }
    @Published var audioRecognitionState: AudioRecognitionState = .idle
    @Published var audioRecognitionMessage = "选择音频文件后，会强制使用 Apple 本机语音识别测试离线能力"
    @Published var lastRecognizedSpeechText = ""

    let localModelDirectory: URL
    let localModelFilename = "model.gguf"
    let persistenceURL: URL

    private let mockService: any LocalLanguageModeling
    private let localService: GemmaLocalService
    private var ticker: Task<Void, Never>?
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
        refreshModelStatus()
        persist()
    }

    deinit {
        ticker?.cancel()
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

    var speechRecognitionCapabilities: [SpeechRecognitionCapability] {
        SupportedLanguage.allCases.map { language in
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.speechLocaleIdentifier))
            return SpeechRecognitionCapability(
                language: language,
                localeIdentifier: language.speechLocaleIdentifier,
                supportsOnDeviceRecognition: recognizer?.supportsOnDeviceRecognition ?? false
            )
        }
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
            try FileManager.default.copyItem(at: url, to: destination)
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

    func removeLocalModel() {
        let modelURL = localModelDirectory.appendingPathComponent(localModelFilename)

        do {
            if FileManager.default.fileExists(atPath: modelURL.path) {
                try FileManager.default.removeItem(at: modelURL)
                dataTransferMessage = "已移除本地模型文件"
            } else {
                dataTransferMessage = "没有可移除的本地模型文件"
            }
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
                    detail: "已发现 \(localModelFilename)，准备使用本地推理占位层",
                    isReady: true
                )
            } else {
                modelStatus = ModelStatus(
                    title: localService.metadata.displayName,
                    detail: "未找到 \(localModelFilename)，结果会自动回退到 Mock",
                    isReady: false
                )
            }
        }
    }

    func runDiagnostics() {
        guard !isRunningDiagnostics else { return }
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
            try await refreshSummary()
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
            try await refreshSummary()
        } catch {
            modelStatus = ModelStatus(
                title: "Gemma Error",
                detail: error.localizedDescription,
                isReady: false
            )
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

    private func generateWithSelectedEngine(_ request: ModelGenerationRequest) async throws -> ModelGenerationResult {
        let primary: any LocalLanguageModeling = selectedEngine == .local ? localService : mockService

        do {
            try await primary.prepare()
            let result = try await primary.generate(request)
            lastGenerationLabel = "\(result.engineName) · \(result.durationMilliseconds ?? 0)ms"
            return result
        } catch {
            guard selectedEngine == .local else { throw error }
            refreshModelStatus()
            try await mockService.prepare()
            let fallback = try await mockService.generate(request)
            lastGenerationLabel = "Local 缺失，已回退 Mock · \(fallback.durationMilliseconds ?? 0)ms"
            return fallback
        }
    }

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
            id: "localFallback",
            state: .running,
            detail: "正在检查 Local 模型文件和缺失回退..."
        )

        let previousEngine = selectedEngine
        selectedEngine = .local
        do {
            _ = try await translate("Verify local fallback without downloading model.")
            await updateDiagnostic(
                id: "localFallback",
                state: .passed,
                detail: isLocalModelInstalled
                    ? "已发现本地模型，占位 Local 生成路径可用。"
                    : "未发现模型文件，已按预期回退到 Mock。"
            )
        } catch {
            await updateDiagnostic(
                id: "localFallback",
                state: .failed,
                detail: error.localizedDescription
            )
        }
        selectedEngine = previousEngine
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

    private func restoreSnapshot() {
        isRestoring = true
        defer { isRestoring = false }

        guard let snapshot = Self.loadSnapshot(from: persistenceURL) else {
            applySeedSession(settings: .defaultValue)
            prompts = PromptTemplate.defaultPrompts
            return
        }

        prompts = Self.mergeDefaultPrompts(with: snapshot.prompts)
        history = snapshot.history
        applySettings(snapshot.settings)

        if let activeSession = snapshot.activeSession {
            activeSessionID = activeSession.id
            activeCreatedAt = activeSession.createdAt
            elapsedSeconds = activeSession.durationSeconds
            transcript = activeSession.transcript
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
                "输入自定义文本后点击发送，触发 Gemma Mock 翻译。",
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
            id: "localFallback",
            title: "Local 回退",
            detail: "等待检查未下载模型时是否回退 Mock。",
            state: .idle
        )
    ]

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
