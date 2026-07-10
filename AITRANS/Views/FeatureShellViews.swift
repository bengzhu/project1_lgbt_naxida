import SwiftUI

struct ImageTranslationView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                AppPageHeader(title: "图片翻译", subtitle: "Vision OCR 与本地翻译", systemImage: "photo.on.rectangle")
                ImageTranslationPanel()
            }
            .enterprisePageFrame(maxWidth: 900)
            .padding(.vertical, AppTheme.Spacing.section)
            .padding(.bottom, 72)
        }
        .background(Color.appCanvas)
    }
}

struct AudioTranslationView: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                AppPageHeader(
                    title: "音频翻译",
                    subtitle: "Apple Speech 本机识别",
                    systemImage: "waveform.and.mic",
                    status: store.audioRecognitionMessage,
                    statusTone: .neutral
                )
                AudioRecognitionPanel()
                SpeechCapabilityPanel()
            }
            .enterprisePageFrame(maxWidth: 900)
            .padding(.vertical, AppTheme.Spacing.section)
            .padding(.bottom, 72)
        }
        .background(Color.appCanvas)
    }
}

struct HistoryView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                AppPageHeader(title: "历史", subtitle: store.storageSummary, systemImage: "clock.arrow.circlepath")
                if store.recentSessions.isEmpty {
                    AppEmptyState(title: "暂无历史", detail: "归档会话后会显示在这里。", systemImage: "clock")
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(store.recentSessions) { record in
                            Button {
                                store.loadSession(record)
                                selectedTab = .text
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(record.title).font(.body.bold())
                                        Text("\(record.sourceLanguage.shortName) -> \(record.targetLanguage.shortName)")
                                            .font(.subheadline)
                                            .foregroundStyle(.appTextSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").accessibilityHidden(true)
                                }
                                .frame(minHeight: AppTheme.Layout.minimumTarget)
                                .padding(.vertical, AppTheme.Spacing.control)
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .bottom) { Divider().overlay(Color.appBorder) }
                        }
                    }
                }
            }
            .enterprisePageFrame()
            .padding(.vertical, AppTheme.Spacing.section)
            .padding(.bottom, 72)
        }
        .background(Color.appCanvas)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                AppPageHeader(
                    title: "设置",
                    subtitle: "模型、提示词与本地数据",
                    systemImage: "gearshape.fill",
                    status: store.isProUnlocked ? "Pro 已解锁" : "免费模式",
                    statusTone: store.isProUnlocked ? .success : .locked
                )
                AppStatusRow(title: "运行引擎", detail: store.selectedEngine.title, tone: store.modelStatus.isReady ? .success : .warning)
                AppStatusRow(title: "当前提示词", detail: store.selectedPrompt.title, tone: .neutral)
                AppStatusRow(title: "本地数据", detail: store.storageSummary, tone: .neutral)
            }
            .enterprisePageFrame()
            .padding(.vertical, AppTheme.Spacing.section)
            .padding(.bottom, 72)
        }
        .background(Color.appCanvas)
    }
}
