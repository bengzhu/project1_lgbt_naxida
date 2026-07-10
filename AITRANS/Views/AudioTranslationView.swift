import SwiftUI
import UniformTypeIdentifiers

struct AudioTranslationView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var showAudioImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                AppPageHeader(
                    title: "音频翻译",
                    subtitle: "Apple Speech 本机识别",
                    systemImage: "waveform.and.mic",
                    status: statusTitle,
                    statusTone: statusTone
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.section) {
                        LiveSpeechPanel().frame(minWidth: 360)
                        AudioFilePanel(openImporter: { showAudioImporter = true }).frame(minWidth: 360)
                    }
                    VStack(spacing: AppTheme.Spacing.section) {
                        LiveSpeechPanel()
                        AudioFilePanel(openImporter: { showAudioImporter = true })
                    }
                }

                SpeechRecognitionRunSummaryPanel()
                SpeechCapabilityPanel()
            }
            .enterprisePageFrame(maxWidth: AppTheme.Layout.workspaceMaxWidth)
            .padding(.vertical, AppTheme.Spacing.section)
            .padding(.bottom, 72)
        }
        .background(Color.appCanvas)
        .fileImporter(isPresented: $showAudioImporter, allowedContentTypes: [.audio], onCompletion: handleImport)
    }

    private var statusTitle: String {
        switch store.audioRecognitionState {
        case .idle: store.audioRecognitionMessage == "语音识别已取消" ? "已取消" : "待输入"
        case .checking: "检查中"
        case .recognizing: "识别中"
        case .translating: "翻译中"
        case .translated: "已完成"
        case .failed: "失败"
        }
    }

    private var statusTone: AppStatusTone {
        switch store.audioRecognitionState {
        case .idle: .neutral
        case .checking, .recognizing, .translating: .active
        case .translated: .success
        case .failed: .danger
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            store.recognizeAudioFileAndTranslate(from: url)
        case .failure(let error):
            store.audioRecognitionState = .failed
            store.audioRecognitionMessage = "音频文件选择失败：\(error.localizedDescription)"
            store.dataTransferMessage = store.audioRecognitionMessage
        }
    }
}

private struct LiveSpeechPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(title: "实时语音", subtitle: "长按说话，松手结束", systemImage: "mic.fill")

            Button(action: {}) {
                Label(
                    store.isCapturingProSpeech ? "松手结束识别" : "按住开始识别",
                    systemImage: store.isCapturingProSpeech ? "stop.circle.fill" : "mic.circle.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 72)
                .foregroundStyle(store.isProUnlocked ? Color.appCanvas : Color.appTextSecondary)
                .background(store.isProUnlocked ? Color.appAccent : Color.appSurfaceRaised, in: .rect(cornerRadius: AppTheme.Radius.surface))
            }
            .buttonStyle(.plain)
            .disabled(!store.isProUnlocked)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !store.isCapturingProSpeech { store.beginProLiveSpeechCapture() }
                    }
                    .onEnded { _ in store.endProLiveSpeechCapture() }
            )
            .scaleEffect(store.isCapturingProSpeech && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppTheme.Motion.quick, value: store.isCapturingProSpeech)
            .accessibilityHint(store.isProUnlocked ? "按住按钮说话，松开结束" : "需要先开通或开发解锁 Pro")

            if !store.isProUnlocked {
                AppStatusRow(title: "Pro 功能已锁定", detail: "开通 Pro 后可使用实时本机语音识别。", tone: .locked)
            } else {
                AppStatusRow(
                    title: store.isCapturingProSpeech ? "正在识别" : "麦克风就绪",
                    detail: store.audioRecognitionMessage,
                    tone: store.isCapturingProSpeech ? .active : .neutral
                )
            }

            if !store.proLiveTranscriptText.isEmpty {
                SelectableTextBlock(title: "识别文本", text: store.proLiveTranscriptText)
                AppPrimaryButton(
                    title: store.isProcessing ? "翻译中" : "翻译识别文本",
                    systemImage: "arrow.right.circle.fill",
                    isWorking: store.isProcessing,
                    action: store.translateProLiveTranscript
                )
                .disabled(store.isProcessing)
            }

            if !store.proLiveTranslationText.isEmpty {
                SelectableTextBlock(title: "译文", text: store.proLiveTranslationText)
            }
        }
        .appSurface()
    }
}

private struct AudioFilePanel: View {
    @EnvironmentObject private var store: TranslationSessionStore
    let openImporter: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(title: "音频文件", subtitle: "强制本机识别", systemImage: "waveform.badge.magnifyingglass")
            AudioRecognitionPanel()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.control) { actions }
                VStack(spacing: AppTheme.Spacing.control) { actions }
            }
        }
        .appSurface()
    }

    @ViewBuilder private var actions: some View {
        AppPrimaryButton(title: "选择音频", systemImage: "folder", action: openImporter)
            .disabled(isRunning)
        AppSecondaryButton(title: "运行 test/ 音频", systemImage: "testtube.2", action: store.runBundledAudioTest)
            .disabled(isRunning)
        if canCancel {
            AppSecondaryButton(title: "取消识别", systemImage: "xmark.circle.fill", tone: .danger) {
                store.cancelAudioRecognition()
            }
        }
    }

    private var isRunning: Bool {
        switch store.audioRecognitionState {
        case .checking, .recognizing, .translating: true
        case .idle, .translated, .failed: false
        }
    }

    private var canCancel: Bool {
        switch store.audioRecognitionState {
        case .checking, .recognizing: true
        case .idle, .translating, .translated, .failed: false
        }
    }
}

struct SelectableTextBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text(title).font(.caption.bold()).foregroundStyle(.appTextSecondary)
            Text(text)
                .font(.body)
                .foregroundStyle(.appTextPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppTheme.Spacing.control)
        .background(Color.appCanvas, in: .rect(cornerRadius: AppTheme.Radius.control))
        .overlay { RoundedRectangle(cornerRadius: AppTheme.Radius.control).stroke(Color.appBorder) }
    }
}
