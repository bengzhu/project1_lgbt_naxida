import SwiftUI

struct TextTranslationView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                AppPageHeader(
                    title: "秒译",
                    subtitle: "本地 AI 翻译工作台",
                    systemImage: "bolt.horizontal.circle.fill",
                    status: store.modelStatus.title,
                    statusTone: store.modelStatus.isReady ? .success : .warning
                )

                LanguageControlBar()

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .stretch, spacing: AppTheme.Spacing.section) {
                        TranslationInputPane(selectedTab: $selectedTab)
                            .frame(minWidth: 320)
                        TranslationOutputPane()
                            .frame(minWidth: 320)
                    }

                    VStack(spacing: AppTheme.Spacing.section) {
                        TranslationInputPane(selectedTab: $selectedTab)
                        TranslationOutputPane()
                    }
                }

                RecentTranslationList()
            }
            .enterprisePageFrame(maxWidth: AppTheme.Layout.workspaceMaxWidth)
            .padding(.vertical, AppTheme.Spacing.section)
            .padding(.bottom, 72)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appCanvas)
    }
}

private struct LanguageControlBar: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var showLockedLanguage = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.Spacing.control) {
                sourcePicker
                swapButton
                targetMenu
            }

            VStack(spacing: AppTheme.Spacing.control) {
                sourcePicker
                HStack(spacing: AppTheme.Spacing.control) {
                    swapButton
                    targetMenu
                }
            }
        }
        .alert("Pro 语言", isPresented: $showLockedLanguage) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(store.dataTransferMessage)
        }
    }

    private var sourcePicker: some View {
        Picker("输入语言", selection: $store.sourceLanguage) {
            ForEach(SupportedLanguage.allCases) { language in
                Text(language.rawValue).tag(language)
            }
        }
        .pickerStyle(.menu)
        .tint(.appTextPrimary)
        .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.control)
        .background(Color.appSurface, in: .rect(cornerRadius: AppTheme.Radius.control))
        .overlay { controlBorder }
    }

    private var swapButton: some View {
        Button("交换语言", systemImage: "arrow.left.arrow.right", action: store.swapLanguages)
            .labelStyle(.iconOnly)
            .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
            .foregroundStyle(.appTextPrimary)
            .background(Color.appSurfaceRaised, in: .rect(cornerRadius: AppTheme.Radius.control))
            .overlay { controlBorder }
            .accessibilityHint("交换输入语言和目标语言")
    }

    private var targetMenu: some View {
        Menu("目标语言：\(store.targetLanguage.rawValue)", systemImage: "character.bubble") {
            ForEach(store.availableTargetLanguages) { language in
                Button {
                    store.selectTargetLanguage(language)
                    if !store.canUseLanguage(language) {
                        showLockedLanguage = true
                    }
                } label: {
                    Label(language.rawValue, systemImage: store.canUseLanguage(language) ? "checkmark.circle" : "lock.fill")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.control)
        .foregroundStyle(.appTextPrimary)
        .background(Color.appSurface, in: .rect(cornerRadius: AppTheme.Radius.control))
        .overlay { controlBorder }
        .accessibilityValue(store.targetLanguage.rawValue)
    }

    private var controlBorder: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.control)
            .stroke(Color.appBorder, lineWidth: 1)
    }
}

private struct TranslationInputPane: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(
                title: "原文",
                subtitle: store.sourceLanguage.rawValue,
                systemImage: "square.and.pencil"
            )

            TextField("输入要翻译的文字", text: $store.draftText, axis: .vertical)
                .font(.body)
                .lineLimit(8...18)
                .textFieldStyle(.plain)
                .foregroundStyle(.appTextPrimary)
                .padding(AppTheme.Spacing.section)
                .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
                .background(Color.appCanvas, in: .rect(cornerRadius: AppTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                        .stroke(Color.appBorder, lineWidth: 1)
                }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.control) { actions }
                VStack(spacing: AppTheme.Spacing.control) { actions }
            }
        }
        .appSurface()
    }

    @ViewBuilder private var actions: some View {
        Button {
            selectedTab = .settings
        } label: {
            Label(store.selectedPrompt.title, systemImage: "text.badge.star")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.appTextSecondary)
        .background(Color.appSurfaceRaised, in: .rect(cornerRadius: AppTheme.Radius.control))
        .accessibilityHint("前往设置管理提示词")

        AppPrimaryButton(
            title: store.isProcessing ? "翻译中" : "翻译",
            systemImage: "arrow.right.circle.fill",
            isWorking: store.isProcessing,
            action: store.submitDraft
        )
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.46)
        .accessibilityHint(canSubmit ? "使用当前提示词和模型翻译输入内容" : "请输入内容并选择可用目标语言")
    }

    private var canSubmit: Bool {
        !store.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !store.isProcessing
            && store.canUseLanguage(store.targetLanguage)
    }
}

private struct TranslationOutputPane: View {
    @EnvironmentObject private var store: TranslationSessionStore

    private var latestLine: TranscriptLine? { store.transcript.first }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(
                title: "译文",
                subtitle: store.targetLanguage.rawValue,
                systemImage: "text.bubble.fill"
            )

            Group {
                if store.isProcessing {
                    VStack(spacing: AppTheme.Spacing.section) {
                        ProgressView()
                            .tint(.appAccent)
                        Text("正在使用 \(store.selectedEngine.rawValue) 生成译文")
                            .font(.subheadline)
                            .foregroundStyle(.appTextSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 190)
                } else if let latestLine {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                            Text(latestLine.translation)
                                .font(.title3.bold())
                                .foregroundStyle(.appTextPrimary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Divider().overlay(Color.appBorder)
                            Text(latestLine.original)
                                .font(.subheadline)
                                .foregroundStyle(.appTextSecondary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
                } else {
                    AppEmptyState(
                        title: "等待翻译",
                        detail: "译文会在这里显示，不会上传到云端。",
                        systemImage: "text.bubble"
                    )
                }
            }

            AppStatusRow(
                title: store.lastGenerationLabel,
                detail: "\(store.selectedEngine.rawValue) · \(store.selectedPrompt.title)",
                tone: store.isProcessing ? .active : (latestLine == nil ? .neutral : .success)
            )
        }
        .appSurface()
    }
}

private struct RecentTranslationList: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
            AppSectionHeader(
                title: "最近翻译",
                subtitle: "\(store.transcript.count) 条",
                systemImage: "clock.arrow.circlepath"
            )

            if store.transcript.isEmpty {
                AppEmptyState(
                    title: "暂无记录",
                    detail: "完成一次翻译后，最近结果会显示在这里。",
                    systemImage: "text.bubble"
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(store.transcript.prefix(4)) { line in
                        HStack(alignment: .top, spacing: AppTheme.Spacing.control) {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                                Text(line.translation)
                                    .font(.body.bold())
                                    .foregroundStyle(.appTextPrimary)
                                    .lineLimit(3)
                                Text(line.original)
                                    .font(.subheadline)
                                    .foregroundStyle(.appTextSecondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Text(line.time)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.appTextSecondary)
                        }
                        .padding(.vertical, AppTheme.Spacing.control)
                        .overlay(alignment: .bottom) { Divider().overlay(Color.appBorder) }
                    }
                }
            }
        }
    }
}
