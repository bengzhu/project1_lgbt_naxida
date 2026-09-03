import SwiftUI

enum AppTab: Hashable, CaseIterable, Identifiable {
    case text
    case image
    case manga
    case ocr
    case audio
    case library
    case history
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .text: "文本"
        case .image: "图片"
        case .manga: "漫画"
        case .ocr: "OCR 检测"
        case .audio: "音频"
        case .library: "资料库"
        case .history: "历史"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "text.bubble.fill"
        case .image: "photo.on.rectangle"
        case .manga: "book.pages.fill"
        case .ocr: "text.viewfinder"
        case .audio: "waveform.and.mic"
        case .library: "square.grid.2x2.fill"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape.fill"
        }
    }

    var feature: AppFeature {
        switch self {
        case .text: .text
        case .image: .image
        case .manga: .manga
        case .ocr: .ocr
        case .audio: .audio
        case .library, .history: .library
        case .settings: .settings
        }
    }

    static let phoneTabs: [AppTab] = [.text, .image, .manga, .ocr, .audio, .library]
    static let tabletSections: [(title: String, tabs: [AppTab])] = [
        ("创作", [.text, .image, .manga, .audio]),
        ("工具", [.ocr]),
        ("资料", [.history, .settings])
    ]
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("aitrans.ui.appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @State private var selectedTab: AppTab

    private let evidenceScenario: AppPreviewScenario?

    init() {
#if DEBUG
        let scenario = ProcessInfo.processInfo.environment["AITRANS_UI_EVIDENCE_SCENARIO"]
            .flatMap(AppPreviewScenario.init(rawValue:))
#else
        let scenario: AppPreviewScenario? = nil
#endif
        evidenceScenario = scenario
#if DEBUG
        let launchesImageOCRDiagnostic =
            ProcessInfo.processInfo.environment["AITRANS_IMAGE_TRANSLATION_UI_FOCUS"] == "ocr"
        let launchesBundledImageTranslationTest =
            ProcessInfo.processInfo.environment["AITRANS_RUN_BUNDLED_IMAGE_TRANSLATION_TEST"] == "1"
                || launchesImageOCRDiagnostic
#else
        let launchesImageOCRDiagnostic = false
        let launchesBundledImageTranslationTest = false
#endif
        _selectedTab = State(
            initialValue: scenario?.selectedTab
                ?? (launchesBundledImageTranslationTest ? .image : .text)
        )
    }

    var body: some View {
        ZStack {
            AppCanvasBackground()

            if evidenceScenario?.presentsPromptDirectly == true {
                PromptLibraryView()
            } else if evidenceScenario?.presentsDeveloperDirectly == true {
                DeveloperConsoleView()
            } else if evidenceScenario?.presentsModelDirectly == true {
                ModelManagementView()
            } else if evidenceScenario?.presentsHistoryDirectly == true {
                HistoryView(selectedTab: $selectedTab)
            } else if evidenceScenario?.presentsSettingsDirectly == true {
                SettingsView(selectedTab: $selectedTab)
            } else if horizontalSizeClass == .regular {
                TabletRootView(selectedTab: $selectedTab)
            } else {
                PhoneRootView(selectedTab: $selectedTab)
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .tint(selectedTab.feature.accent(for: colorScheme))
        .environment(\.appReduceMotionOverride, evidenceScenario == .audioRecognizing)
    }

    private var appearance: AppAppearance {
#if DEBUG
        if let evidenceValue = ProcessInfo.processInfo.environment["AITRANS_UI_EVIDENCE_APPEARANCE"],
           let evidenceAppearance = AppAppearance(rawValue: evidenceValue) {
            return evidenceAppearance
        }
#endif
        return AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

}

private struct PhoneRootView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.phoneTabs) { tab in
                AppTabRouter(tab: tab, selectedTab: $selectedTab)
                    .tag(tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .accessibilityLabel(tab.title)
                }
        }
        .onAppear(perform: normalizeSelection)
        .onChange(of: selectedTab) { _, _ in normalizeSelection() }
    }

    private func normalizeSelection() {
        guard !AppTab.phoneTabs.contains(selectedTab) else { return }
        selectedTab = .library
    }
}

private struct TabletRootView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(AppTab.tabletSections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.tabs) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                Label(tab.title, systemImage: tab.systemImage)
                                    .font(selectedTab == tab ? .body.bold() : .body)
                                    .foregroundStyle(selectedTab == tab ? tab.feature.accent(for: colorScheme) : Color.appTextPrimary)
                                    .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget, alignment: .leading)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(selectedTab == tab ? tab.feature.accent(for: colorScheme).opacity(0.12) : Color.clear)
                            .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                        }
                    }
                }

                Section {
                    HStack(spacing: AppTheme.Spacing.control) {
                        BrandMark()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("秒译")
                                .font(.headline)
                            Text(store.selectedEngine.rawValue)
                                .font(.caption)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.control)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.appCanvas)
            .navigationTitle("工作区")
        } detail: {
            AppTabRouter(tab: selectedTab, selectedTab: $selectedTab)
                .navigationTitle(selectedTab.title)
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct AppTabRouter: View {
    let tab: AppTab
    @Binding var selectedTab: AppTab

    var body: some View {
        switch tab {
        case .text:
            TextTranslationView(selectedTab: $selectedTab)
        case .image:
            ImageTranslationView()
        case .manga:
            MangaBrowserView(selectedTab: $selectedTab)
        case .ocr:
            ImageOCRDetectionView()
        case .audio:
            AudioTranslationView()
        case .library:
            LibraryHubView(selectedTab: $selectedTab)
        case .history:
            HistoryView(selectedTab: $selectedTab)
        case .settings:
            SettingsView(selectedTab: $selectedTab)
        }
    }
}

private enum LibraryDestination: Hashable {
    case history
    case settings
}

private struct LibraryHubView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                    AppPageHeader(
                        title: "资料库",
                        subtitle: "回看成果，调整你的本地工作空间",
                        systemImage: AppFeature.library.symbol,
                        status: "\(store.totalSessionCount) 个会话",
                        statusTone: .neutral,
                        feature: .library
                    )

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: AppTheme.Spacing.section) { destinationCards }
                        VStack(spacing: AppTheme.Spacing.section) { destinationCards }
                    }
                }
                .enterprisePageFrame()
                .padding(.vertical, AppTheme.Spacing.section)
                .padding(.bottom, 72)
            }
            .background { AppCanvasBackground() }
            .navigationDestination(for: LibraryDestination.self) { destination in
                switch destination {
                case .history: HistoryView(selectedTab: $selectedTab)
                case .settings:
                    SettingsView(
                        selectedTab: $selectedTab,
                        isEmbeddedInNavigationStack: true
                    )
                }
            }
        }
    }

    @ViewBuilder private var destinationCards: some View {
        LibraryDestinationCard(
            title: "历史",
            detail: "继续会话、检索译文与管理导入导出",
            metric: "\(store.totalSessionCount) 个会话",
            systemImage: "clock.arrow.circlepath",
            accent: AppFeature.library.accent(for: colorScheme),
            destination: .history
        )
        LibraryDestinationCard(
            title: "设置",
            detail: "模型、提示词、外观与本地数据控制",
            metric: store.modelStatus.title,
            systemImage: "slider.horizontal.3",
            accent: AppFeature.settings.accent(for: colorScheme),
            destination: .settings
        )
    }
}

private struct LibraryDestinationCard: View {
    let title: String
    let detail: String
    let metric: String
    let systemImage: String
    let accent: Color
    let destination: LibraryDestination

    var body: some View {
        NavigationLink(value: destination) {
            HStack(spacing: AppTheme.Spacing.control) {
                Image(systemName: systemImage)
                    .font(.headline.bold())
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.14), in: .rect(cornerRadius: AppTheme.Radius.control))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.bold())
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.appTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(metric)
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                    Image(systemName: "arrow.up.right")
                        .font(.headline.bold())
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.section)
            .padding(.vertical, AppTheme.Spacing.compact)
            .appSurface(padded: false, accent: accent)
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开\(title)")
    }
}

#Preview("iPhone") {
    ContentView()
        .environmentObject(TranslationSessionStore(modelService: MockGemmaService()))
}

#Preview("iPad", traits: .fixedLayout(width: 1_024, height: 768)) {
    ContentView()
        .environmentObject(TranslationSessionStore(modelService: MockGemmaService()))
}
