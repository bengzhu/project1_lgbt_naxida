import SwiftUI

enum AppTab: Hashable, CaseIterable, Identifiable {
    case text
    case image
    case audio
    case history
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .text: "文本"
        case .image: "图片"
        case .audio: "音频"
        case .history: "历史"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "text.bubble.fill"
        case .image: "photo.on.rectangle"
        case .audio: "waveform.and.mic"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var store: TranslationSessionStore
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
        _selectedTab = State(initialValue: scenario?.selectedTab ?? .text)
    }

    var body: some View {
        ZStack {
            AppCanvasBackground()

            if evidenceScenario?.presentsModelDirectly == true {
                ModelManagementView()
            } else if horizontalSizeClass == .regular {
                TabletRootView(selectedTab: $selectedTab)
            } else {
                PhoneRootView(selectedTab: $selectedTab)
            }
        }
        .onChange(of: store.isDeveloperModeEnabled) { _, isEnabled in
            if !isEnabled, selectedTab == .settings {
                selectedTab = .settings
            }
        }
        .preferredColorScheme(appearance.colorScheme)
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
            ForEach(AppTab.allCases) { tab in
                AppTabRouter(tab: tab, selectedTab: $selectedTab)
                    .tag(tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .accessibilityLabel(tab.title)
            }
        }
        .tint(Color.appAccent)
    }
}

private struct TabletRootView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    ForEach(AppTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Label(tab.title, systemImage: tab.systemImage)
                                .font(selectedTab == tab ? .body.bold() : .body)
                                .foregroundStyle(selectedTab == tab ? Color.appAccent : Color.appTextPrimary)
                                .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selectedTab == tab ? Color.appSurfaceRaised : Color.clear)
                        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    }
                } header: {
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
                    .textCase(nil)
                    .padding(.vertical, AppTheme.Spacing.control)
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
        .tint(Color.appAccent)
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
        case .audio:
            AudioTranslationView()
        case .history:
            HistoryView(selectedTab: $selectedTab)
        case .settings:
            SettingsView(selectedTab: $selectedTab)
        }
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
