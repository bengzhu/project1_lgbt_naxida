import SwiftUI

private enum SettingsDestination: Hashable {
    case prompts
    case model
    case developer
}

struct SettingsView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab
    let isEmbeddedInNavigationStack: Bool
    @State private var developerPassword = ""
    @State private var navigationPath = NavigationPath()
    @State private var advancedExpanded = false

    init(
        selectedTab: Binding<AppTab>,
        isEmbeddedInNavigationStack: Bool = false
    ) {
        _selectedTab = selectedTab
        self.isEmbeddedInNavigationStack = isEmbeddedInNavigationStack
    }

    var body: some View {
        Group {
            if isEmbeddedInNavigationStack {
                settingsContent
            } else {
                NavigationStack(path: $navigationPath) {
                    settingsContent
                }
            }
        }
        .task {
            guard !isUIEvidenceScenario else { return }
            store.loadProSubscriptionProduct()
            store.refreshSpeechRecognitionCapabilities()
        }
        .onChange(of: store.isDeveloperModeEnabled) { _, isEnabled in
            if !isEnabled {
                navigationPath = NavigationPath()
            }
        }
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                AppPageHeader(
                    title: "设置",
                    subtitle: "模型、提示词与本地数据",
                    systemImage: "gearshape.fill",
                    status: store.isProUnlocked ? "Pro 已解锁" : "免费模式",
                    statusTone: store.isProUnlocked ? .success : .locked,
                    feature: .settings
                )

                AppearanceSection()
                BrowserSettingsSection()
                ProAccessPanel()
                SettingsNavigationSection()
                SettingsAdvancedSection(
                    password: $developerPassword,
                    isExpanded: $advancedExpanded
                )
                DataSafetySection(selectedTab: $selectedTab)
            }
            .enterprisePageFrame()
            .padding(.vertical, AppTheme.Spacing.section)
            .padding(.bottom, 72)
        }
        .background(Color.appCanvas)
        .navigationDestination(for: SettingsDestination.self) { destination in
            switch destination {
            case .prompts: PromptLibraryView()
            case .model: ModelManagementView()
            case .developer: DeveloperConsoleView()
            }
        }
    }

    private var isUIEvidenceScenario: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["AITRANS_UI_EVIDENCE_SCENARIO"] != nil
#else
        false
#endif
    }
}

private struct SettingsAdvancedSection: View {
    @Binding var password: String
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                ProFeatureGrid()
                Divider().overlay(Color.appBorder)
                DeveloperAccessSection(password: $password)
            }
            .padding(.top, AppTheme.Spacing.section)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label("高级与开发", systemImage: "ellipsis.rectangle")
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)
                Text("Pro 能力说明与受保护的诊断入口")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
        .appSurface()
    }
}

private struct AppearanceSection: View {
    @AppStorage("aitrans.ui.appearance") private var appearanceRawValue = AppAppearance.system.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(title: "外观", subtitle: appearance.rawValue, systemImage: "circle.lefthalf.filled")
            Picker("外观", selection: $appearanceRawValue) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.rawValue).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityValue(appearance.rawValue)
        }
        .appSurface()
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }
}

private struct BrowserSettingsSection: View {
    @AppStorage("aitrans.browser.blockAds") private var blockAds = true
    @AppStorage("aitrans.browser.blockPopups") private var blockPopups = true
    @AppStorage("aitrans.browser.blockRedirects") private var blockRedirects = true
    @AppStorage("aitrans.browser.elementRemoval") private var elementRemovalEnabled = false
    @AppStorage("aitrans.browser.antiHijacking") private var antiHijackingEnabled = true
    @AppStorage("aitrans.browser.sourceLanguage") private var sourceLanguageRaw = SupportedLanguage.japanese.rawValue
    @AppStorage("aitrans.browser.targetLanguage") private var targetLanguageRaw = SupportedLanguage.simplifiedChinese.rawValue
    @AppStorage("aitrans.browser.fontName") private var fontName = "system"
    @AppStorage("aitrans.browser.fontScale") private var fontScale = 1.0

    private let fontOptions = [
        ("system", "系统圆体"),
        ("kaiti", "楷体"),
        ("rounded", "漫画圆体")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(
                title: "浏览器设置",
                subtitle: "漫画阅读、翻译与安全防护（逐项独立）",
                systemImage: "book.pages.fill"
            )
            Toggle("基础广告拦截", isOn: $blockAds)
                .accessibilityHint("拦截常见广告域名与第三方广告资源")
            Toggle("弹窗拦截", isOn: $blockPopups)
                .accessibilityHint("阻止网页创建新的弹窗标签")
            Toggle("重定向拦截", isOn: $blockRedirects)
                .accessibilityHint("阻止非用户点击触发的跨站强制跳转")
            Toggle("点选元素消除", isOn: $elementRemovalEnabled)
                .accessibilityHint("在浏览器中点选网页元素即可移除，并记住规则")
            Toggle("防劫持保护", isOn: $antiHijackingEnabled)
                .accessibilityHint("保护触摸和剪贴板不被网页脚本劫持")

            Divider().overlay(Color.appBorder)
            Picker("浏览器源语言", selection: $sourceLanguageRaw) {
                ForEach([SupportedLanguage.japanese, .englishUS, .simplifiedChinese, .french, .german]) { language in
                    Text(language.rawValue).tag(language.rawValue)
                }
            }
            Picker("浏览器目标语言", selection: $targetLanguageRaw) {
                ForEach(SupportedLanguage.allCases) { language in
                    Text(language.rawValue).tag(language.rawValue)
                }
            }
            Picker("漫画字体", selection: $fontName) {
                ForEach(fontOptions, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("译文大小")
                    Spacer()
                    Text("\(Int(fontScale * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.appTextSecondary)
                }
                Slider(value: $fontScale, in: 0.75...1.35, step: 0.05)
                    .accessibilityValue("\(Int(fontScale * 100))%")
            }
            Text("浏览器翻译只保留在当前页面的内存缓存；清除规则不会影响文本、图片或 OCR 会话。")
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
        }
        .appSurface()
    }
}

private struct SettingsNavigationSection: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppSectionHeader(title: "工作设置", subtitle: "高频入口", systemImage: "slider.horizontal.3")
                .padding(.bottom, AppTheme.Spacing.control)
            SettingsLink(title: "提示词", detail: store.selectedPrompt.title, systemImage: "text.badge.star", destination: .prompts)
            SettingsLink(title: "模型", detail: store.modelStatus.title, systemImage: store.selectedEngine.systemImage, destination: .model)
            if store.isDeveloperModeEnabled {
                SettingsLink(title: "开发诊断", detail: "raw probe 与漫画报告", systemImage: "hammer.fill", destination: .developer)
            }
        }
    }
}

private struct SettingsLink: View {
    let title: String
    let detail: String
    let systemImage: String
    let destination: SettingsDestination

    var body: some View {
        NavigationLink(value: destination) {
            HStack(spacing: AppTheme.Spacing.control) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.bold()).foregroundStyle(Color.appTextPrimary)
                    Text(detail).font(.subheadline).foregroundStyle(Color.appTextSecondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Color.appTextSecondary).accessibilityHidden(true)
            }
            .frame(minHeight: 58)
            .overlay(alignment: .bottom) { Divider().overlay(Color.appBorder) }
        }
        .buttonStyle(.plain)
    }
}

private struct DeveloperAccessSection: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var password: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(
                title: "开发者模式",
                subtitle: store.isDeveloperModeEnabled ? "已开启" : "受保护",
                systemImage: store.isDeveloperModeEnabled ? "lock.open.fill" : "lock.fill"
            )
            if store.isDeveloperModeEnabled {
                AppStatusRow(title: "诊断入口可见", detail: store.developerModeMessage, tone: .warning)
                AppSecondaryButton(title: "关闭开发者模式", systemImage: "lock.fill", action: store.disableDeveloperMode)
            } else {
                SecureField("开发者密码", text: $password)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, AppTheme.Spacing.control)
                    .frame(minHeight: AppTheme.Layout.minimumTarget)
                    .background(Color.appCanvas, in: .rect(cornerRadius: AppTheme.Radius.control))
                    .overlay { RoundedRectangle(cornerRadius: AppTheme.Radius.control).stroke(Color.appBorder) }
                AppPrimaryButton(title: "开启开发者模式", systemImage: "lock.open.fill") {
                    if store.unlockDeveloperMode(password: password) { password = "" }
                }
                Text(store.developerModeMessage).font(.subheadline).foregroundStyle(Color.appTextSecondary)
            }
        }
    }
}

private struct DataSafetySection: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(title: "本地数据", subtitle: store.persistedLocationDisplay, systemImage: "externaldrive.fill")
            AppStatusRow(title: store.storageSummary, detail: store.dataTransferMessage, tone: .neutral)
            AppSecondaryButton(title: "返回资料库", systemImage: "square.grid.2x2.fill") { selectedTab = .library }
        }
    }
}
