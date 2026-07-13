import SwiftUI

@MainActor
enum AppPreviewScenario: String {
    case empty
    case textSuccess
    case textFailure
    case textKeyboard
    case imageEmpty
    case imageSuccess
    case audioRecognizing
    case audioTranslating
    case audioFailure
    case history
    case promptLibrary
    case proLocked
    case proUnlocked
    case developerConsole
    case localMissing
    case localReady

    var selectedTab: AppTab {
        switch self {
        case .empty, .textSuccess, .textFailure, .textKeyboard: .text
        case .imageEmpty, .imageSuccess: .image
        case .audioRecognizing, .audioTranslating, .audioFailure: .audio
        case .history: .history
        case .promptLibrary, .proLocked, .proUnlocked, .developerConsole, .localMissing, .localReady: .settings
        }
    }

    var presentsPromptDirectly: Bool {
        self == .promptLibrary
    }

    var presentsDeveloperDirectly: Bool {
        self == .developerConsole
    }

    var presentsModelDirectly: Bool {
        self == .localMissing || self == .localReady
    }

    func makeStore() -> TranslationSessionStore {
        let store = TranslationSessionStore(
            modelService: MockGemmaService(),
            persistenceURL: FileManager.default.temporaryDirectory.appending(path: "aitrans-preview-\(UUID().uuidString).json"),
            performsStartupWork: false
        )
        configure(store)
        return store
    }

    func configure(_ store: TranslationSessionStore) {
        switch self {
        case .empty:
            store.draftText = ""
            store.transcript = []
        case .textSuccess:
            store.draftText = "Keep every model and translation on this device."
            store.lastGenerationLabel = "刚刚完成"
            store.transcript = [Self.sampleLine]
        case .textFailure:
            store.draftText = "Translate this with a missing local model."
            store.selectedEngine = .local
            store.modelStatus = ModelStatus(title: "Local GGUF", detail: "未找到 model.gguf", isReady: false)
            store.lastGenerationLabel = "模型加载失败"
        case .textKeyboard:
            store.draftText = "A long source paragraph remains editable while the keyboard is visible."
        case .imageEmpty:
            store.imageTranslationState = .idle
            store.imageTranslationData = nil
        case .imageSuccess:
            if let url = Bundle.main.url(forResource: "1", withExtension: "png", subdirectory: "test") {
                store.imageTranslationData = try? Data(contentsOf: url)
            }
            store.imageTranslationRevision += 1
            store.imageTranslationState = .translated
            store.imageTranslationMessage = "已识别 2 个文字块并完成翻译"
            store.imageTranslationBlocks = [
                ImageTranslationBlock(
                    original: "Let's Battle!",
                    translation: "来对战吧！",
                    confidence: 0.96,
                    boundingBox: NormalizedImageRect(x: 0.12, y: 0.14, width: 0.24, height: 0.08)
                ),
                ImageTranslationBlock(
                    original: "The tournament starts tomorrow.",
                    translation: "比赛明天开始。",
                    confidence: 0.88,
                    boundingBox: NormalizedImageRect(x: 0.58, y: 0.42, width: 0.28, height: 0.10)
                )
            ]
        case .audioRecognizing:
            store.isProUnlocked = true
            store.isCapturingProSpeech = true
            store.audioRecognitionState = .recognizing
            store.audioRecognitionMessage = "正在使用 en-US 强制本机识别"
            store.speechRecognitionRunSummary = Self.audioSummary(isFinal: false, failureMessage: nil)
        case .audioTranslating:
            store.isProUnlocked = true
            store.isProcessing = true
            store.proLiveTranscriptText = "Keep the model on device."
            store.lastRecognizedSpeechText = store.proLiveTranscriptText
            store.audioRecognitionState = .translating
            store.audioRecognitionMessage = "识别成功，正在交给翻译模型"
            store.speechRecognitionRunSummary = Self.audioSummary(isFinal: true, failureMessage: nil)
        case .audioFailure:
            store.isProUnlocked = true
            store.audioRecognitionState = .failed
            store.audioRecognitionMessage = "设备未安装当前语言的本机识别资源"
            store.speechRecognitionRunSummary = Self.audioSummary(isFinal: true, failureMessage: store.audioRecognitionMessage)
        case .history:
            store.history = [Self.sampleRecord, Self.sampleRecordTwo]
        case .promptLibrary:
            store.selectedPromptID = PromptTemplate.translatorID
        case .proLocked:
            store.isProUnlocked = false
            store.proPurchaseMessage = "App Store 商品暂不可用"
        case .proUnlocked:
            store.isProUnlocked = true
            store.proPurchaseMessage = "开发环境已解锁 Pro"
        case .developerConsole:
            store.isDeveloperModeEnabled = true
            store.developerModeMessage = "开发者模式已开启"
        case .localMissing:
            store.selectedEngine = .local
            store.modelStatus = ModelStatus(title: "Local GGUF", detail: "未找到 model.gguf", isReady: false)
        case .localReady:
            store.selectedEngine = .local
            store.modelStatus = ModelStatus(title: "Local GGUF", detail: "模型已校验，可开始本地推理", isReady: true)
            store.modelDownload = ModelDownloadProgress(
                phase: .installed,
                bytesReceived: store.builtInModel.expectedSizeBytes,
                totalBytes: store.builtInModel.expectedSizeBytes,
                speedBytesPerSecond: 0,
                message: "模型已安装"
            )
        }
    }

    private static var sampleLine: TranscriptLine {
        TranscriptLine(
            speaker: "输入",
            original: "Keep every model and translation on this device.",
            translation: "将所有模型和翻译保留在此设备上。",
            time: "09:41",
            isFinal: true
        )
    }

    private static var sampleRecord: TranslationSessionRecord {
        TranslationSessionRecord(
            id: UUID(),
            title: "本地模型发布说明",
            createdAt: .now.addingTimeInterval(-3_600),
            updatedAt: .now.addingTimeInterval(-1_800),
            mode: .translate,
            sourceLanguage: .englishUS,
            targetLanguage: .simplifiedChinese,
            selectedPromptID: PromptTemplate.translatorID,
            selectedEngine: .local,
            durationSeconds: 84,
            transcript: [sampleLine],
            summary: AISummary(bullets: ["模型保持离线"], actions: [], title: "本地翻译")
        )
    }

    private static var sampleRecordTwo: TranslationSessionRecord {
        var record = sampleRecord
        record.id = UUID()
        record.title = "会议纪要翻译"
        record.updatedAt = .now.addingTimeInterval(-86_400)
        record.selectedEngine = .mock
        return record
    }

    private static func audioSummary(isFinal: Bool, failureMessage: String?) -> SpeechRecognitionRunSummary {
        SpeechRecognitionRunSummary(
            mode: .audioFile,
            inputName: "meeting-sample.m4a",
            localeIdentifier: "en-US",
            requiresOnDeviceRecognition: true,
            supportsOnDeviceRecognition: true,
            runToken: "PREVIEW1",
            startedAt: .now.addingTimeInterval(-12.4),
            completedAt: isFinal ? .now : nil,
            transcriptPreview: "The meeting starts at nine thirty tomorrow.",
            wordCount: 8,
            segmentCount: 3,
            averageConfidence: 0.91,
            isFinal: isFinal,
            failureMessage: failureMessage
        )
    }
}

private struct PreviewContainer<Content: View>: View {
    @State private var store: TranslationSessionStore
    @ViewBuilder let content: Content

    init(scenario: AppPreviewScenario, @ViewBuilder content: () -> Content) {
        _store = State(initialValue: scenario.makeStore())
        self.content = content()
    }

    var body: some View {
        content
            .environmentObject(store)
    }
}

#Preview("Text · iPhone · Empty", traits: .fixedLayout(width: 375, height: 812)) {
    PreviewContainer(scenario: .empty) { TextTranslationView(selectedTab: .constant(.text)) }
}

#Preview("Text · Day", traits: .fixedLayout(width: 430, height: 932)) {
    PreviewContainer(scenario: .textSuccess) { TextTranslationView(selectedTab: .constant(.text)) }
        .preferredColorScheme(.light)
}

#Preview("Text · iPhone · XXL", traits: .fixedLayout(width: 430, height: 932)) {
    PreviewContainer(scenario: .textSuccess) { TextTranslationView(selectedTab: .constant(.text)) }
        .dynamicTypeSize(.xxLarge)
}

#Preview("Text · Accessibility", traits: .fixedLayout(width: 430, height: 932)) {
    PreviewContainer(scenario: .textFailure) { TextTranslationView(selectedTab: .constant(.text)) }
        .dynamicTypeSize(.accessibility2)
}

#Preview("Text · iPad Landscape", traits: .fixedLayout(width: 1_180, height: 820)) {
    PreviewContainer(scenario: .textSuccess) { TextTranslationView(selectedTab: .constant(.text)) }
}

#Preview("Image · iPad Landscape", traits: .fixedLayout(width: 1_180, height: 820)) {
    PreviewContainer(scenario: .imageSuccess) { ImageTranslationView() }
}

#Preview("Audio · Reduce Motion", traits: .fixedLayout(width: 430, height: 932)) {
    PreviewContainer(scenario: .audioRecognizing) { AudioTranslationView() }
        .environment(\.appReduceMotionOverride, true)
}

#Preview("Audio · Translating", traits: .fixedLayout(width: 375, height: 812)) {
    PreviewContainer(scenario: .audioTranslating) { AudioTranslationView() }
}

#Preview("Audio · Failure", traits: .fixedLayout(width: 375, height: 812)) {
    PreviewContainer(scenario: .audioFailure) { AudioTranslationView() }
}

#Preview("History · Data", traits: .fixedLayout(width: 430, height: 932)) {
    PreviewContainer(scenario: .history) { HistoryView(selectedTab: .constant(.history)) }
}

#Preview("Settings · Pro Unlocked", traits: .fixedLayout(width: 834, height: 1_112)) {
    PreviewContainer(scenario: .proUnlocked) { SettingsView(selectedTab: .constant(.settings)) }
}

#Preview("Model · Local Missing", traits: .fixedLayout(width: 430, height: 932)) {
    PreviewContainer(scenario: .localMissing) { ModelManagementView() }
}

#Preview("Model · Local Ready", traits: .fixedLayout(width: 834, height: 1_112)) {
    PreviewContainer(scenario: .localReady) { ModelManagementView() }
}
