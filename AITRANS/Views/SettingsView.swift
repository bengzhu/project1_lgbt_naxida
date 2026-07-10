import SwiftUI

private enum SettingsDestination: Hashable {
    case prompts
    case model
    case developer
}

struct SettingsView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab
    @State private var developerPassword = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                    AppPageHeader(
                        title: "设置",
                        subtitle: "模型、提示词与本地数据",
                        systemImage: "gearshape.fill",
                        status: store.isProUnlocked ? "Pro 已解锁" : "免费模式",
                        statusTone: store.isProUnlocked ? .success : .locked
                    )

                    AppearanceSection()
                    ProAccessPanel()
                    SettingsNavigationSection()
                    ProFeatureGrid()
                    DeveloperAccessSection(password: $developerPassword)
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
        .task {
            store.loadProSubscriptionProduct()
            store.refreshSpeechRecognitionCapabilities()
        }
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
        .appSurface()
    }
}

private struct DataSafetySection: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(title: "本地数据", subtitle: store.persistedLocationDisplay, systemImage: "externaldrive.fill")
            AppStatusRow(title: store.storageSummary, detail: store.dataTransferMessage, tone: .neutral)
            AppSecondaryButton(title: "前往历史管理", systemImage: "clock.arrow.circlepath") { selectedTab = .history }
        }
    }
}
