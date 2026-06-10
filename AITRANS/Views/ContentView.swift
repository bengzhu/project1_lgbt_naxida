import SwiftUI
import UniformTypeIdentifiers

private enum AppTab: Hashable {
    case workspace
    case history
    case prompts
    case model
}

struct ContentView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var selectedTab: AppTab = .workspace

    var body: some View {
        ZStack {
            AppBackground()

            TabView(selection: $selectedTab) {
                WorkspaceView(selectedTab: $selectedTab)
                    .tag(AppTab.workspace)
                    .tabItem {
                        Label("工作台", systemImage: "waveform.and.mic")
                    }

                HistoryView(selectedTab: $selectedTab)
                    .tag(AppTab.history)
                    .tabItem {
                        Label("历史", systemImage: "clock.arrow.circlepath")
                    }

                PromptLibraryView()
                    .tag(AppTab.prompts)
                    .tabItem {
                        Label("提示词", systemImage: "text.badge.star")
                    }

                ModelSettingsView()
                    .tag(AppTab.model)
                    .tabItem {
                        Label("模型", systemImage: "memorychip")
                    }
            }
            .tint(Color.appAccent)
        }
        .preferredColorScheme(.dark)
    }
}

private struct WorkspaceView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                HeaderBar()
                ProAccountPanel()
                MainTranslatorPanel(selectedTab: $selectedTab)
                ProFeatureGrid(selectedTab: $selectedTab)
                RecentTranslationPanel()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 92)
        }
    }
}

private struct HistoryView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab
    @State private var query = ""
    @State private var showClearConfirmation = false
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var showImportResult = false
    @State private var exportDocument = JSONExportDocument(data: Data())

    private var filteredSessions: [TranslationSessionRecord] {
        let sessions = store.recentSessions
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return sessions }

        return sessions.filter { record in
            record.title.localizedCaseInsensitiveContains(cleanQuery)
                || record.transcript.contains { line in
                    line.original.localizedCaseInsensitiveContains(cleanQuery)
                        || line.translation.localizedCaseInsensitiveContains(cleanQuery)
                }
                || record.summary.bullets.contains { $0.localizedCaseInsensitiveContains(cleanQuery) }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                PageHeader(
                    title: "历史记录",
                    subtitle: store.storageSummary,
                    icon: "clock.arrow.circlepath"
                )

                StoragePanel()

                HStack(spacing: 10) {
                    SearchField(text: $query)

                    Button {
                        store.archiveCurrentSession()
                    } label: {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("归档当前会话")
                }

                HStack(spacing: 10) {
                    SecondaryActionButton(icon: "square.and.arrow.up", title: "导出 JSON") {
                        guard let url = store.exportSnapshot(),
                              let data = try? Data(contentsOf: url) else {
                            showImportResult = true
                            return
                        }

                        exportDocument = JSONExportDocument(data: data)
                        showExporter = true
                    }

                    SecondaryActionButton(icon: "square.and.arrow.down", title: "导入 JSON") {
                        showImporter = true
                    }

                    SecondaryActionButton(icon: "trash.fill", title: "清空历史", tint: Color.danger) {
                        showClearConfirmation = true
                    }
                    .disabled(store.history.isEmpty)
                    .opacity(store.history.isEmpty ? 0.52 : 1)
                }

                if filteredSessions.isEmpty {
                    EmptyStatePanel(
                        icon: "doc.text.magnifyingglass",
                        title: "没有匹配记录",
                        detail: "完成一次模拟翻译后，会话会自动保存在本地。"
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredSessions) { record in
                            HistorySessionCard(record: record) {
                                store.loadSession(record)
                                selectedTab = .workspace
                            } onDelete: {
                                store.deleteSession(record)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 92)
        }
        .confirmationDialog("清空历史记录", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) {
                store.clearHistory()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前会话会保留，历史列表会被清空。")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                _ = store.importSnapshot(from: url)
            case .failure(let error):
                store.dataTransferMessage = "导入失败：\(error.localizedDescription)"
            }
            showImportResult = true
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "aitrans-export"
        ) { result in
            switch result {
            case .success(let url):
                store.dataTransferMessage = "已导出到 \(url.lastPathComponent)"
            case .failure(let error):
                store.dataTransferMessage = "导出失败：\(error.localizedDescription)"
                showImportResult = true
            }
        }
        .alert("数据操作", isPresented: $showImportResult) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(store.dataTransferMessage)
        }
    }
}

private struct PromptLibraryView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var newTitle = ""
    @State private var newInstruction = ""
    @State private var newTone = ""
    @State private var editorPrompt: PromptTemplate?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                PageHeader(
                    title: "提示词",
                    subtitle: "当前：\(store.selectedPrompt.title)",
                    icon: "text.badge.star"
                )

                PromptComposer(
                    title: $newTitle,
                    instruction: $newInstruction,
                    tone: $newTone
                ) {
                    store.createPrompt(title: newTitle, instruction: newInstruction, tone: newTone)
                    newTitle = ""
                    newInstruction = ""
                    newTone = ""
                }

                LazyVStack(spacing: 12) {
                    ForEach(store.prompts) { prompt in
                        PromptCard(
                            prompt: prompt,
                            isSelected: store.selectedPromptID == prompt.id
                        ) {
                            store.selectPrompt(prompt)
                        } onEdit: {
                            editorPrompt = prompt
                        } onDuplicate: {
                            store.duplicatePrompt(prompt)
                        } onDelete: {
                            store.deletePrompt(prompt)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 92)
        }
        .sheet(item: $editorPrompt) { prompt in
            PromptEditorSheet(prompt: prompt)
                .environmentObject(store)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct ModelSettingsView: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                PageHeader(
                    title: "模型设置",
                    subtitle: store.modelStatus.title,
                    icon: "memorychip"
                )

                ModelStatusPanel()
                DiagnosticsPanel()
                EngineSelectorPanel()
                SamplingPanel()
                AdapterContractPanel()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 92)
        }
    }
}

private struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.07, blue: 0.08),
                Color(red: 0.06, green: 0.11, blue: 0.13),
                Color(red: 0.10, green: 0.08, blue: 0.11)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.37, blue: 0.42).opacity(0.65),
                    Color(red: 0.30, green: 0.18, blue: 0.33).opacity(0.35),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 260)
        }
        .overlay {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.035), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .ignoresSafeArea()
    }
}

private struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private extension UTType {
    static let ggufModel = UTType(filenameExtension: "gguf") ?? .data
}

private struct HeaderBar: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                AppMark()
                brand

                Spacer(minLength: 12)

                modelStatus(alignment: .trailing)
                    .frame(maxWidth: 176, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    AppMark()
                    brand
                    Spacer(minLength: 8)
                }

                modelStatus(alignment: .leading)
            }
        }
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("秒译")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text("本地 AI 翻译")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.70))
                .lineLimit(1)
        }
    }

    private func modelStatus(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Label(
                store.modelStatus.title,
                systemImage: store.modelStatus.isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            )
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(store.modelStatus.isReady ? Color.success : Color.warning)
            .lineLimit(1)
            .minimumScaleFactor(0.70)

            Text(store.lastGenerationLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.54))
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
    }
}

private struct PageHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            AppMark()
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Label(subtitle, systemImage: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct AppMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.55, blue: 0.60),
                            Color(red: 0.16, green: 0.32, blue: 0.70)
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
                .shadow(color: Color(red: 0.04, green: 0.36, blue: 0.40).opacity(0.40), radius: 12, y: 6)

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(.white)

            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.warning)
                .offset(x: -5, y: 4)
        }
        .frame(width: 54, height: 54)
    }
}

private struct ProAccountPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(store.proStatusTitle, systemImage: store.isProUnlocked ? "crown.fill" : "person.crop.circle.badge.plus")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(store.isProUnlocked ? Color.warning : .white)
                Text(store.isProUnlocked ? store.proPlan.detail : "免费：中文、英语文本翻译")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(store.proPlan.productID) · \(store.proPlan.displayPrice)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }

            Spacer(minLength: 8)

            Button {
                if store.isProUnlocked {
                    store.restoreFreeModeForDevelopment()
                } else {
                    store.activateProForDevelopment()
                }
            } label: {
                Text(store.isProUnlocked ? "切回免费" : "开通 Pro")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(store.isProUnlocked ? .white.opacity(0.86) : .black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 13)
                    .frame(height: 36)
                    .background(store.isProUnlocked ? Color.white.opacity(0.09) : Color.warning, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.isProUnlocked ? "切回免费模式" : "开通 Pro")
        }
        .panelStyle()
    }
}

private struct MainTranslatorPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab

    private var latestLine: TranscriptLine? {
        store.transcript.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    CompactLanguagePicker(title: "输入", selection: $store.sourceLanguage, showsProLocks: false)
                    swapButton
                    TargetLanguageMenu()
                }

                VStack(spacing: 10) {
                    CompactLanguagePicker(title: "输入", selection: $store.sourceLanguage, showsProLocks: false)
                    HStack(spacing: 10) {
                        swapButton
                        TargetLanguageMenu()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $store.draftText)
                    .frame(minHeight: 128)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if store.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("输入要翻译的文字")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.white.opacity(0.34))
                                .padding(.top, 20)
                                .padding(.leading, 17)
                        }
                    }

                HStack(spacing: 10) {
                    Label(store.selectedPrompt.title, systemImage: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 0)

                    Button {
                        selectedTab = .prompts
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("设置提示词")

                    Button {
                        store.submitDraft()
                    } label: {
                        Label(store.isProcessing ? "翻译中" : "翻译", systemImage: store.isProcessing ? "hourglass" : "arrow.right.circle.fill")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 104, height: 40)
                            .background(canSend ? Color.appAccent : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }

            Divider()
                .overlay(.white.opacity(0.14))

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label(store.targetLanguage.rawValue, systemImage: "text.bubble.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.appAccent)
                    Spacer()
                    Text(store.lastGenerationLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                }

                Text(latestLine?.translation ?? "译文会显示在这里。")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(latestLine == nil ? 0.42 : 0.92))
                    .fixedSize(horizontal: false, vertical: true)

                if let original = latestLine?.original {
                    Text(original)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .panelStyle(cornerRadius: 22)
    }

    private var canSend: Bool {
        !store.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !store.isProcessing
            && store.canUseLanguage(store.targetLanguage)
    }

    private var swapButton: some View {
        Button {
            store.swapLanguages()
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.09), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换源语言和目标语言")
    }
}

private struct CompactLanguagePicker: View {
    @EnvironmentObject private var store: TranslationSessionStore

    let title: String
    @Binding var selection: SupportedLanguage
    let showsProLocks: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.48))
            Picker(title, selection: $selection) {
                ForEach(SupportedLanguage.allCases) { language in
                    Text(language.rawValue).tag(language)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .font(.system(size: 14, weight: .bold))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 58)
        .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TargetLanguageMenu: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var showLockedAlert = false

    var body: some View {
        Menu {
            ForEach(store.availableTargetLanguages) { language in
                Button {
                    if store.canUseLanguage(language) {
                        store.selectTargetLanguage(language)
                    } else {
                        store.selectTargetLanguage(language)
                        showLockedAlert = true
                    }
                } label: {
                    Label(language.rawValue, systemImage: store.canUseLanguage(language) ? "checkmark.circle" : "lock.fill")
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text("翻译成")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.48))
                HStack(spacing: 7) {
                    Text(store.targetLanguage.rawValue)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                    if !store.canUseLanguage(store.targetLanguage) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.warning)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 58)
            .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .alert("Pro 语言", isPresented: $showLockedAlert) {
            Button("知道了", role: .cancel) {}
            Button("开通 Pro") {
                store.activateProForDevelopment()
            }
        } message: {
            Text(store.dataTransferMessage)
        }
    }
}

private struct ProFeatureGrid: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab
    @State private var showAudioImporter = false
    @State private var showBackgroundPlan = false
    @State private var showImagePlan = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Pro 功能", subtitle: store.isProUnlocked ? "已解锁" : "内购模式", icon: "crown.fill")

            HStack(spacing: 10) {
                ProFeatureCard(
                    icon: "waveform.and.mic",
                    title: "同声传译",
                    detail: "系统本地语音识别 + 本地大模型翻译",
                    isUnlocked: store.isProUnlocked
                ) {
                    if store.isProUnlocked {
                        store.mode = .live
                        if !store.isRecording {
                            store.toggleRecording()
                        }
                    } else {
                        store.dataTransferMessage = "同声传译需要 Pro"
                    }
                }

                ProFeatureCard(
                    icon: "camera.viewfinder",
                    title: "图片翻译",
                    detail: "Vision OCR + 本地模型翻译",
                    isUnlocked: store.isProUnlocked,
                    isComingSoon: true
                ) {
                    showImagePlan = true
                }
            }

            HStack(spacing: 10) {
                ProFeatureCard(
                    icon: "waveform.badge.magnifyingglass",
                    title: "音频测试",
                    detail: "选择音频，断网本机识别后翻译",
                    isUnlocked: store.isProUnlocked
                ) {
                    if store.isProUnlocked {
                        showAudioImporter = true
                    } else {
                        store.dataTransferMessage = "音频离线识别测试需要 Pro"
                    }
                }

                ProFeatureCard(
                    icon: "rectangle.on.rectangle.badge.gearshape",
                    title: "后台翻译",
                    detail: "悬浮窗能力评估与扩展路线",
                    isUnlocked: store.isProUnlocked,
                    isComingSoon: true
                ) {
                    // iOS does not allow a normal app to draw a persistent overlay above other apps.
                    showBackgroundPlan = true
                }
            }

            AudioRecognitionPanel()
            SpeechCapabilityPanel()
        }
        .panelStyle()
        .fileImporter(isPresented: $showAudioImporter, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url):
                store.recognizeAudioFileAndTranslate(from: url)
            case .failure(let error):
                store.audioRecognitionState = .failed
                store.audioRecognitionMessage = "音频文件选择失败：\(error.localizedDescription)"
                store.dataTransferMessage = store.audioRecognitionMessage
            }
        }
        .alert("后台一键翻译", isPresented: $showBackgroundPlan) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("iOS 普通 App 不能常驻覆盖其他 App 的任意悬浮窗。可行路线是 Share Extension 处理截图/文本，或 ReplayKit Broadcast Upload Extension 获取屏幕帧后做本地 OCR，但需要用户显式启动屏幕广播。")
        }
        .alert("图片翻译方案", isPresented: $showImagePlan) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("离线优先方案：Vision VNRecognizeTextRequest 做本机 OCR，拿到文字和 boundingBox，按行/块送入本地模型翻译，再用覆盖层把译文贴在原位置旁边或替换原区域。")
        }
    }
}

private struct ProFeatureCard: View {
    let icon: String
    let title: String
    let detail: String
    let isUnlocked: Bool
    var isComingSoon = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(isUnlocked ? Color.appAccent : Color.warning)
                    Spacer()
                    Image(systemName: isUnlocked ? "checkmark.circle.fill" : "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isUnlocked ? Color.success : Color.warning)
                }

                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(isComingSoon ? "开发中" : detail)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SpeechCapabilityPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.appAccent)
                Text("苹果本地语音识别")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(store.currentSpeechCapability.supportsOnDeviceRecognition ? "当前语言可用" : "当前语言需检测")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(store.currentSpeechCapability.supportsOnDeviceRecognition ? Color.success : Color.warning)
            }

            Text("iOS 13+ 的 Speech 框架可用 `supportsOnDeviceRecognition` 判断本机是否支持离线识别，并用 `requiresOnDeviceRecognition` 强制本地识别。支持情况取决于设备和语言包。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ForEach(store.speechRecognitionCapabilities.prefix(4)) { capability in
                    Text("\(capability.language.shortName) \(capability.supportsOnDeviceRecognition ? "本地" : "云端")")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(capability.supportsOnDeviceRecognition ? Color.success : .white.opacity(0.50))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct AudioRecognitionPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                Text("音频文件断网测试")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(statusText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
            }

            Text(store.audioRecognitionMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            if !store.lastRecognizedSpeechText.isEmpty {
                Text(store.lastRecognizedSpeechText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var icon: String {
        switch store.audioRecognitionState {
        case .idle: "waveform"
        case .checking: "magnifyingglass"
        case .recognizing: "waveform.path"
        case .translated: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch store.audioRecognitionState {
        case .idle: .white.opacity(0.58)
        case .checking, .recognizing: Color.warning
        case .translated: Color.success
        case .failed: Color.danger
        }
    }

    private var statusText: String {
        switch store.audioRecognitionState {
        case .idle: "待选择"
        case .checking: "检查中"
        case .recognizing: "识别中"
        case .translated: "已翻译"
        case .failed: "失败"
        }
    }
}

private struct RecentTranslationPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "最近翻译", subtitle: "\(store.transcript.count) 条", icon: "clock.arrow.circlepath")

            if store.transcript.isEmpty {
                EmptyStatePanel(icon: "text.bubble", title: "暂无记录", detail: "完成一次翻译后会自动保存到本地历史。")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(store.transcript.prefix(3)) { line in
                        TranscriptCard(line: line)
                    }
                }
            }
        }
        .panelStyle()
    }
}

private struct HeroPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) {
                    heroCopy
                    Spacer(minLength: 12)
                    StatusPill(isRecording: store.isRecording)
                }

                VStack(alignment: .leading, spacing: 12) {
                    heroCopy
                    StatusPill(isRecording: store.isRecording)
                }
            }

            HStack(spacing: 10) {
                MetricTile(value: store.elapsedDisplay, label: "会话时长", icon: "timer")
                MetricTile(value: "\(store.transcript.count)", label: "转录片段", icon: "text.bubble.fill")
                MetricTile(value: store.targetLanguage.shortName, label: "目标语言", icon: "globe.asia.australia.fill")
            }

            HStack(spacing: 10) {
                LinkButton(icon: "clock.arrow.circlepath", title: "历史") {
                    selectedTab = .history
                }
                LinkButton(icon: "text.badge.star", title: store.selectedPrompt.title) {
                    selectedTab = .prompts
                }
                LinkButton(icon: "memorychip.fill", title: store.selectedEngine.rawValue) {
                    selectedTab = .model
                }
            }
        }
        .panelStyle(cornerRadius: 22)
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("离线同传工作台")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text("先用 Gemma 1.5B Mock 打通交互，后续替换本地推理层。")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StatusPill: View {
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isRecording ? Color.danger : Color.success)
                .frame(width: 8, height: 8)
            Text(isRecording ? "录音中" : "待机")
                .font(.system(size: 12, weight: .bold))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.26), in: Capsule())
    }
}

private struct MetricTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.appAccent)
            Text(value)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct LinkButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ModeSelector: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "工作模式", subtitle: store.mode.detail, icon: "square.grid.2x2.fill")

            HStack(spacing: 8) {
                ForEach(SessionMode.allCases) { mode in
                    Button {
                        store.mode = mode
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: mode.systemImage)
                                .font(.system(size: 15, weight: .bold))
                            Text(mode.rawValue)
                                .font(.system(size: 13, weight: .bold))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 66)
                        .background(
                            store.mode == mode ? Color.appAccent : Color.black.opacity(0.22),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panelStyle()
    }
}

private struct LanguagePanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(spacing: 12) {
            SectionTitle(title: "语言与提示词", subtitle: store.selectedPrompt.title, icon: "character.bubble")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    LanguagePicker(title: "源语言", selection: $store.sourceLanguage)
                    swapButton
                    LanguagePicker(title: "目标语言", selection: $store.targetLanguage)
                }

                VStack(spacing: 10) {
                    LanguagePicker(title: "源语言", selection: $store.sourceLanguage)
                    swapButton
                    LanguagePicker(title: "目标语言", selection: $store.targetLanguage)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.selectedPrompt.tone)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                    Text(store.selectedPrompt.instruction)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .panelStyle()
    }

    private var swapButton: some View {
        Button {
            store.swapLanguages()
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换语言")
    }
}

private struct LanguagePicker: View {
    let title: String
    @Binding var selection: SupportedLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.52))
            Picker(title, selection: $selection) {
                ForEach(SupportedLanguage.allCases) { language in
                    Text(language.rawValue).tag(language)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct TranscriptPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(
                title: "实时转录",
                subtitle: store.isRecording ? store.elapsedDisplay : "准备就绪",
                icon: "text.bubble.fill"
            )

            if store.transcript.isEmpty {
                EmptyStatePanel(
                    icon: "mic.badge.plus",
                    title: "等待输入",
                    detail: "点击麦克风模拟实时转录，或在下方输入文本。"
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(store.transcript) { line in
                        TranscriptCard(line: line)
                    }
                }
            }

            TextField("输入一句话，模拟音频识别文本", text: $store.draftText, axis: .vertical)
                .lineLimit(2...4)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(13)
                .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .submitLabel(.send)
                .onSubmit {
                    store.submitDraft()
                }
        }
        .panelStyle(cornerRadius: 22)
    }
}

private struct TranscriptCard: View {
    let line: TranscriptLine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(line.speaker, systemImage: line.isFinal ? "checkmark.circle.fill" : "waveform.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(line.isFinal ? Color.success : Color.appAccent)
                Spacer()
                Text(line.time)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
            }

            Text(line.original)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            Text(line.translation)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(red: 0.58, green: 0.86, blue: 0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SummaryPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionTitle(title: store.summary.title, subtitle: store.mode.rawValue, icon: "sparkles")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(store.summary.bullets, id: \.self) { item in
                    SummaryRow(icon: "sparkle", text: item)
                }
            }

            Divider()
                .overlay(.white.opacity(0.18))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(store.summary.actions, id: \.self) { item in
                    SummaryRow(icon: "checklist", text: item)
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.33, blue: 0.36).opacity(0.72),
                    Color(red: 0.15, green: 0.13, blue: 0.20).opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
    }
}

private struct StoragePanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "本地数据", subtitle: "Application Support", icon: "internaldrive.fill")

            InfoRow(icon: "doc.text.fill", title: "状态文件", detail: store.persistedLocationDisplay)
            InfoRow(icon: "square.and.arrow.up.fill", title: "导出文件", detail: store.exportURL.path)
            InfoRow(icon: "arrow.left.arrow.right.circle.fill", title: "最近操作", detail: store.dataTransferMessage)
            InfoRow(icon: "archivebox.fill", title: "保存内容", detail: "当前会话、历史记录、提示词模板、模型设置和采样参数")
        }
        .panelStyle()
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
            TextField("搜索原文、译文、摘要", text: $text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 13)
        .frame(height: 46)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HistorySessionCard: View {
    let record: TranslationSessionRecord
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(record.updatedAt.displayString)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.52))
                }

                Spacer(minLength: 8)

                Text(record.mode.rawValue)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.appAccent.opacity(0.85), in: Capsule())
            }

            HStack(spacing: 8) {
                CompactBadge(icon: "character.book.closed.fill", text: "\(record.sourceLanguage.shortName) -> \(record.targetLanguage.shortName)")
                CompactBadge(icon: "text.bubble.fill", text: "\(record.transcript.count) 条")
                CompactBadge(icon: "timer", text: record.durationDisplay)
            }

            if let bullet = record.summary.bullets.first {
                Text(bullet)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                PrimaryActionButton(icon: "arrow.up.left.and.arrow.down.right", title: "打开", action: onOpen)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 44, height: 40)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.danger)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("删除历史记录")
            }
        }
        .panelStyle()
    }
}

private struct PromptComposer: View {
    @Binding var title: String
    @Binding var instruction: String
    @Binding var tone: String
    let onCreate: () -> Void

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "新建模板", subtitle: "本地保存", icon: "plus.message.fill")

            TextField("标题，例如：法务会议", text: $title)
                .fieldStyle()

            TextField("语气，例如：正式、谨慎、保留术语", text: $tone)
                .fieldStyle()

            TextEditor(text: $instruction)
                .frame(minHeight: 96)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if instruction.isEmpty {
                        Text("写清楚翻译规则、输出格式和禁止事项")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.36))
                            .padding(.top, 18)
                            .padding(.leading, 16)
                    }
                }

            PrimaryActionButton(icon: "plus", title: "保存提示词", action: onCreate)
                .disabled(!canCreate)
                .opacity(canCreate ? 1 : 0.55)
        }
        .panelStyle()
    }
}

private struct PromptCard: View {
    let prompt: PromptTemplate
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(prompt.title)
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        if prompt.isBuiltIn {
                            Text("内置")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.warning)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color.warning.opacity(0.14), in: Capsule())
                        }
                    }

                    Text(prompt.tone)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.56))
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isSelected ? Color.success : .white.opacity(0.42))
            }

            Text(prompt.instruction)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                PrimaryActionButton(icon: "checkmark", title: isSelected ? "使用中" : "使用", action: onSelect)
                    .disabled(isSelected)
                    .opacity(isSelected ? 0.72 : 1)

                IconActionButton(icon: "doc.on.doc.fill", action: onDuplicate, label: "复制提示词")

                if prompt.isBuiltIn {
                    IconActionButton(icon: "lock.fill", action: {}, label: "内置提示词不可编辑")
                        .disabled(true)
                        .opacity(0.46)
                } else {
                    IconActionButton(icon: "pencil", action: onEdit, label: "编辑提示词")
                    IconActionButton(icon: "trash.fill", action: onDelete, label: "删除提示词", tint: Color.danger)
                }
            }
        }
        .panelStyle()
    }
}

private struct PromptEditorSheet: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Environment(\.dismiss) private var dismiss

    let prompt: PromptTemplate
    @State private var title: String
    @State private var instruction: String
    @State private var tone: String

    init(prompt: PromptTemplate) {
        self.prompt = prompt
        _title = State(initialValue: prompt.title)
        _instruction = State(initialValue: prompt.instruction)
        _tone = State(initialValue: prompt.tone)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("标题", text: $title)
                }

                Section("语气") {
                    TextField("语气", text: $tone)
                }

                Section("指令") {
                    TextEditor(text: $instruction)
                        .frame(minHeight: 160)
                }
            }
            .navigationTitle("编辑提示词")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.updatePrompt(prompt, title: title, instruction: instruction, tone: tone)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ModelStatusPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var showModelImporter = false
    @State private var showModelActionResult = false
    @State private var showRemoveConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "运行状态", subtitle: store.selectedEngine.rawValue, icon: "gauge.with.dots.needle.67percent")

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: store.modelStatus.isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(store.modelStatus.isReady ? Color.success : Color.warning)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(store.modelStatus.title)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                    Text(store.modelStatus.detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.70))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            InfoRow(icon: "folder.fill", title: "模型目录", detail: store.localModelPathDisplay)
            InfoRow(icon: "shippingbox.fill", title: "模型文件", detail: "\(store.localModelFilename) / \(store.localModelSizeDisplay)")

            HStack(spacing: 10) {
                PrimaryActionButton(icon: "folder.badge.plus", title: "导入 GGUF") {
                    showModelImporter = true
                }

                SecondaryActionButton(icon: "trash.fill", title: "移除模型", tint: Color.danger) {
                    showRemoveConfirmation = true
                }
                .disabled(!store.isLocalModelInstalled)
                .opacity(store.isLocalModelInstalled ? 1 : 0.52)
            }

            SecondaryActionButton(icon: "arrow.clockwise", title: "刷新模型状态") {
                store.refreshModelStatus()
                store.dataTransferMessage = store.modelStatus.detail
                showModelActionResult = true
            }
        }
        .panelStyle()
        .fileImporter(isPresented: $showModelImporter, allowedContentTypes: [.ggufModel]) { result in
            switch result {
            case .success(let url):
                _ = store.importLocalModel(from: url)
            case .failure(let error):
                store.dataTransferMessage = "模型导入失败：\(error.localizedDescription)"
                store.refreshModelStatus()
            }
            showModelActionResult = true
        }
        .confirmationDialog("移除本地模型", isPresented: $showRemoveConfirmation, titleVisibility: .visible) {
            Button("移除模型", role: .destructive) {
                store.removeLocalModel()
                showModelActionResult = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除 App 沙盒中的 model.gguf，不会影响原始文件。")
        }
        .alert("模型文件", isPresented: $showModelActionResult) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(store.dataTransferMessage)
        }
    }
}

private struct EngineSelectorPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "推理引擎", subtitle: "Mock / Local", icon: "slider.horizontal.3")

            HStack(spacing: 8) {
                ForEach(ModelEngine.allCases) { engine in
                    Button {
                        store.selectEngine(engine)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: engine.systemImage)
                                .font(.system(size: 20, weight: .bold))
                            Text(engine.title)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.74)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 86)
                        .background(
                            store.selectedEngine == engine ? Color.appAccent : Color.black.opacity(0.22),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panelStyle()
    }
}

private struct DiagnosticsPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(
                title: "自检",
                subtitle: store.isRunningDiagnostics ? "运行中" : "可运行",
                icon: "checklist.checked"
            )

            VStack(spacing: 9) {
                ForEach(store.diagnostics) { check in
                    DiagnosticRow(check: check)
                }
            }

            PrimaryActionButton(
                icon: store.isRunningDiagnostics ? "hourglass" : "play.fill",
                title: store.isRunningDiagnostics ? "正在检查" : "运行自检"
            ) {
                store.runDiagnostics()
            }
            .disabled(store.isRunningDiagnostics)
            .opacity(store.isRunningDiagnostics ? 0.62 : 1)
        }
        .panelStyle()
    }
}

private struct DiagnosticRow: View {
    let check: DiagnosticCheck

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(check.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
                Text(check.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var icon: String {
        switch check.state {
        case .idle: "circle"
        case .running: "arrow.triangle.2.circlepath"
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch check.state {
        case .idle: .white.opacity(0.48)
        case .running: Color.warning
        case .passed: Color.success
        case .failed: Color.danger
        }
    }
}

private struct SamplingPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "生成参数", subtitle: "本地保存", icon: "dial.low.fill")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Temperature")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text(store.sampling.temperature.formatted(.number.precision(.fractionLength(2))))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.appAccent)
                }

                Slider(
                    value: Binding(
                        get: { store.sampling.temperature },
                        set: { store.setTemperature($0) }
                    ),
                    in: 0...1.2
                )
                .tint(Color.appAccent)
            }

            Stepper(
                value: Binding(
                    get: { store.sampling.maxTokens },
                    set: { store.setMaxTokens($0) }
                ),
                in: 128...2_048,
                step: 128
            ) {
                HStack {
                    Text("Max Tokens")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text("\(store.sampling.maxTokens)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
        .panelStyle()
    }
}

private struct AdapterContractPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        let metadata = store.selectedAdapterMetadata

        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "接入接口", subtitle: "已预留", icon: "point.3.connected.trianglepath.dotted")

            InfoRow(
                icon: metadata.engine.systemImage,
                title: "当前适配器",
                detail: "\(metadata.displayName) / \(metadata.modelName) / \(metadata.quantization)"
            )
            InfoRow(
                icon: metadata.supportsStreaming ? "dot.radiowaves.left.and.right" : "rectangle.and.text.magnifyingglass",
                title: "生成方式",
                detail: metadata.supportsStreaming ? "支持模拟流式输出；真实接入时可逐 token 回调 UI" : "当前 Local 占位为一次性返回；可在真实推理层中改成流式"
            )
            InfoRow(
                icon: "arrow.down.doc.fill",
                title: "输入",
                detail: "ModelGenerationRequest 包含任务类型、语言、提示词、上下文和采样参数"
            )
            InfoRow(
                icon: "arrow.up.doc.fill",
                title: "输出",
                detail: "ModelGenerationResult 返回文本、摘要、引擎名称、token 数和耗时"
            )
            InfoRow(
                icon: "switch.2",
                title: "替换点",
                detail: "实现 LocalLanguageModeling.generate 后即可替换 Mock，不影响 UI 和本地数据"
            )
        }
        .panelStyle()
    }
}

private struct SectionTitle: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.appAccent)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 8)
            Text(subtitle)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
    }
}

private struct SummaryRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.appAccent)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.appAccent)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct EmptyStatePanel: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.appAccent)
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct CompactBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.76))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.07), in: Capsule())
    }
}

private struct PrimaryActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SecondaryActionButton: View {
    let icon: String
    let title: String
    let tint: Color
    let action: () -> Void

    init(icon: String, title: String, tint: Color = .white, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .foregroundStyle(tint.opacity(0.92))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct IconActionButton: View {
    let icon: String
    let action: () -> Void
    let label: String
    var tint: Color = .white

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint.opacity(0.9))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct ControlDock: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        HStack(spacing: 14) {
            DockButton(icon: "plus.rectangle.on.rectangle", title: "新会话") {
                store.startNewSession()
            }

            Button {
                store.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(store.isRecording ? Color.danger : Color.appAccent)
                        .frame(width: 68, height: 68)
                        .shadow(color: (store.isRecording ? Color.danger : Color.appAccent).opacity(0.42), radius: 16, y: 7)

                    Image(systemName: store.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.isRecording ? "停止录音" : "开始录音")

            DockButton(icon: store.isProcessing ? "hourglass" : "paperplane.fill", title: "发送") {
                store.submitDraft()
            }
            .disabled(store.isProcessing)
            .opacity(store.isProcessing ? 0.62 : 1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct DockButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 38, height: 30)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 56, height: 54)
        }
        .buttonStyle(.plain)
    }
}

private extension TranslationSessionRecord {
    var durationDisplay: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private extension Date {
    var displayString: String {
        Self.historyFormatter.string(from: self)
    }

    private static let historyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}

private extension TextField {
    func fieldStyle() -> some View {
        self
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(13)
            .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private extension View {
    func panelStyle(cornerRadius: CGFloat = 20) -> some View {
        self
            .padding(14)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
    }
}

private extension Color {
    static let appAccent = Color(red: 0.08, green: 0.58, blue: 0.62)
    static let panel = Color.white.opacity(0.075)
    static let success = Color(red: 0.42, green: 0.92, blue: 0.58)
    static let warning = Color(red: 1.00, green: 0.73, blue: 0.28)
    static let danger = Color(red: 1.00, green: 0.30, blue: 0.36)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(TranslationSessionStore(modelService: MockGemmaService()))
    }
}
