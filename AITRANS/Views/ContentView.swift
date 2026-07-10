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
    @State private var selectedTab: AppTab = .text

    var body: some View {
        ZStack {
            AppCanvasBackground()

            if horizontalSizeClass == .regular {
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
        .preferredColorScheme(.dark)
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
        .tint(.appAccent)
    }
}

private struct TabletRootView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section {
                    ForEach(AppTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.systemImage)
                            .font(.body.bold())
                            .tag(tab)
                            .frame(minHeight: AppTheme.Layout.minimumTarget)
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
                                .foregroundStyle(.appTextSecondary)
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
        .tint(.appAccent)
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
