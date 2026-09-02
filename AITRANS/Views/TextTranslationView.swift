import SwiftUI

struct TextTranslationView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selectedTab: AppTab
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                    LanguageControlBar()

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: AppTheme.Spacing.section) {
                            TranslationInputPane(selectedTab: $selectedTab, inputFocused: $inputFocused)
                                .frame(minWidth: 320)
                            TranslationOutputPane()
                                .frame(minWidth: 320)
                        }

                        VStack(spacing: AppTheme.Spacing.section) {
                            TranslationInputPane(selectedTab: $selectedTab, inputFocused: $inputFocused)
                            TranslationOutputPane()
                        }
                    }

                    SessionCommandBar(startNewSession: startNewSession)
                    RecentTranslationList()
                }
                .enterprisePageFrame(maxWidth: AppTheme.Layout.workspaceMaxWidth)
                .padding(.vertical, AppTheme.Spacing.section)
                .padding(.bottom, AppTheme.Spacing.page)
            }
            .scrollDismissesKeyboard(.interactively)

            if horizontalSizeClass == .compact && (dynamicTypeSize >= .xxLarge || inputFocused) {
                Color.clear
                    .frame(height: AppTheme.Layout.floatingTabBarClearance)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成", action: dismissKeyboard)
                    .bold()
                    .accessibilityLabel("完成输入并收起键盘")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AppPageHeader(
                title: "秒译",
                subtitle: "本地处理",
                systemImage: "bolt.horizontal.circle.fill",
                status: store.modelStatus.title,
                statusTone: store.modelStatus.isReady ? .success : .warning,
                feature: .text
            )
            .enterprisePageFrame(maxWidth: AppTheme.Layout.workspaceMaxWidth)
            .padding(.vertical, AppTheme.Spacing.section)
            .background(Color.appCanvas)
            .overlay(alignment: .bottom) {
                Divider().overlay(Color.appBorder)
            }
        }
        .background { TextWorkspaceBackground().ignoresSafeArea() }
        .onChange(of: selectedTab) { _, tab in
            if tab != .text {
                dismissKeyboard()
            }
        }
    }

    private func dismissKeyboard() {
        inputFocused = false
    }

    private func startNewSession() {
        inputFocused = false
        store.startNewSession()
    }
}

private struct SessionCommandBar: View {
    @EnvironmentObject private var store: TranslationSessionStore
    let startNewSession: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.Spacing.control) { actions }
            VStack(spacing: AppTheme.Spacing.control) { actions }
        }
    }

    @ViewBuilder private var actions: some View {
        AppSecondaryButton(title: "新会话", systemImage: "plus.rectangle.on.rectangle", action: startNewSession)
        AppSecondaryButton(title: "归档当前", systemImage: "tray.and.arrow.down") {
            store.archiveCurrentSession()
        }
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
        .tint(Color.appTextPrimary)
        .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.control)
        .background(Color.appSurface, in: .rect(cornerRadius: AppTheme.Radius.control))
        .overlay { controlBorder }
    }

    private var swapButton: some View {
        Button("交换语言", systemImage: "arrow.left.arrow.right", action: store.swapLanguages)
            .labelStyle(.iconOnly)
            .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
            .foregroundStyle(AppTheme.TextWorkspace.swap)
            .background(AppTheme.TextWorkspace.swap.opacity(0.12), in: .rect(cornerRadius: AppTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                    .stroke(AppTheme.TextWorkspace.swap.opacity(0.72), lineWidth: 1)
            }
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
        .foregroundStyle(Color.appTextPrimary)
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
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: AppTab
    let inputFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(
                title: "原文",
                subtitle: store.sourceLanguage.rawValue,
                systemImage: "square.and.pencil"
            )

            TextField("输入要翻译的文字", text: $store.draftText, axis: .vertical)
                .font(.body)
                .lineLimit(6...18)
                .textFieldStyle(.plain)
                .focused(inputFocused)
                .foregroundStyle(Color.appTextPrimary)
                .padding(AppTheme.Spacing.section)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                .background(Color.appSurfaceRaised, in: .rect(cornerRadius: AppTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                        .stroke(Color.appBorder, lineWidth: 1)
                }

            TranslationInputToolBar(
                selectedTab: $selectedTab,
                inputFocused: inputFocused
            )
        }
        .appSurface(accent: AppFeature.text.accent(for: colorScheme))
        .task {
#if DEBUG
            inputFocused.wrappedValue = ProcessInfo.processInfo.environment["AITRANS_UI_EVIDENCE_SCENARIO"] == AppPreviewScenario.textKeyboard.rawValue
#endif
        }
    }

}

private struct TranslationInputToolBar: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab
    let inputFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: AppTheme.Spacing.control) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.control) {
                    pasteButton
                    promptButton
                }
                VStack(spacing: AppTheme.Spacing.control) {
                    pasteButton
                    promptButton
                }
            }

            AppPrimaryButton(
                title: store.isProcessing ? "翻译中" : "翻译",
                systemImage: "arrow.right.circle.fill",
                isWorking: store.isProcessing,
                action: submitTranslation
            )
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.62)
            .accessibilityHint(canSubmit ? "使用当前提示词和模型翻译输入内容" : "请输入内容并选择可用目标语言")
        }
    }

    private var pasteButton: some View {
        TextWorkspacePasteButton(onPaste: pasteText)
            .accessibilityLabel("粘贴剪贴板文本")
            .accessibilityHint("输入为空时填入文本，已有内容时换行追加")
    }

    private var promptButton: some View {
        Button(action: openPromptLibrary) {
            Label(store.selectedPrompt.title, systemImage: "text.badge.star")
                .font(.subheadline.bold())
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget)
                .padding(.horizontal, AppTheme.Spacing.control)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.TextWorkspace.prompt)
        .background(AppTheme.TextWorkspace.prompt.opacity(0.12), in: .rect(cornerRadius: AppTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                .stroke(AppTheme.TextWorkspace.prompt.opacity(0.72), lineWidth: 1)
        }
        .accessibilityHint("前往设置管理提示词")
    }

    private var canSubmit: Bool {
        !store.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !store.isProcessing
            && store.canUseLanguage(store.targetLanguage)
    }

    private func pasteText(_ items: [String]) {
        guard let text = resolvedPasteText(from: items), !text.isEmpty else { return }
        if store.draftText.isEmpty {
            store.draftText = text
        } else {
            store.draftText += "\n\(text)"
        }
        inputFocused.wrappedValue = true
    }

    /// Pure text paste resolution. Release only uses the system PasteButton payload.
    /// DEBUG may fall back to `AITRANS_UI_TEST_PASTE_TEXT` when the payload is empty so
    /// XCUITest can exercise fill/append without sharing the host pasteboard.
    /// Never called from lifecycle hooks; only from the user-facing paste control.
    private func resolvedPasteText(from items: [String]) -> String? {
        if let text = items.first, !text.isEmpty {
            return text
        }
#if DEBUG
        if let injected = ProcessInfo.processInfo.environment["AITRANS_UI_TEST_PASTE_TEXT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !injected.isEmpty {
            return injected
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-AITRANS_UI_TEST_PASTE_TEXT"),
           arguments.index(after: index) < arguments.endIndex {
            let injected = arguments[arguments.index(after: index)]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !injected.isEmpty {
                return injected
            }
        }
#endif
        return nil
    }

    private func openPromptLibrary() {
        inputFocused.wrappedValue = false
        selectedTab = .library
    }

    private func submitTranslation() {
        inputFocused.wrappedValue = false
        store.submitDraft()
    }
}

private struct TranslationOutputPane: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Environment(\.colorScheme) private var colorScheme

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
                            .tint(Color.appAccent)
                        Text("正在使用 \(store.selectedEngine.rawValue) 生成译文")
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 190)
                } else if let latestLine {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                            Text(latestLine.translation)
                                .font(.title3.bold())
                                .foregroundStyle(Color.appTextPrimary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Divider().overlay(Color.appBorder)
                            Text(latestLine.original)
                                .font(.subheadline)
                                .foregroundStyle(Color.appTextSecondary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
                } else {
                    AppEmptyState(
                        title: "等待翻译",
                        detail: "译文将在此显示。",
                        systemImage: "text.bubble"
                    )
                }
            }

            AppStatusRow(
                title: store.lastGenerationLabel,
                detail: "\(store.selectedEngine.rawValue) · \(store.selectedPrompt.title)",
                tone: statusTone
            )
        }
        .appSurface(accent: AppFeature.image.accent(for: colorScheme))
    }

    private var statusTone: AppStatusTone {
        if store.isProcessing { return .active }
        if store.lastGenerationLabel.localizedStandardContains("失败") { return .danger }
        return latestLine == nil ? .neutral : .success
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
                                    .foregroundStyle(Color.appTextPrimary)
                                    .lineLimit(3)
                                Text(line.original)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appTextSecondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Text(line.time)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.appTextSecondary)
                        }
                        .padding(.vertical, AppTheme.Spacing.control)
                        .overlay(alignment: .bottom) { Divider().overlay(Color.appBorder) }
                    }
                }
            }
        }
    }
}
