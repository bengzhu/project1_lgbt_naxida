import SwiftUI

struct ProAccessPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(
                title: store.proStatusTitle,
                subtitle: store.proPlan.displayPrice,
                systemImage: store.isProUnlocked ? "checkmark.seal.fill" : "lock.fill"
            )

            AppStatusRow(
                title: store.isProUnlocked ? "已解锁" : "免费模式",
                detail: store.isProUnlocked ? store.proPlan.detail : "中文、英语文本翻译可用；音频和扩展语言保持锁定。",
                tone: store.isProUnlocked ? .success : .locked
            )
            Text(store.proPurchaseMessage)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.control) { actions }
                VStack(spacing: AppTheme.Spacing.control) { actions }
            }
        }
        .appSurface()
    }

    @ViewBuilder private var actions: some View {
        if !store.isProUnlocked {
            AppPrimaryButton(title: "开通 Pro", systemImage: "crown.fill", action: store.purchaseProSubscription)
        }
        AppSecondaryButton(title: "校验订阅", systemImage: "arrow.clockwise", action: store.refreshProEntitlements)
        if store.isDeveloperModeEnabled {
            AppSecondaryButton(title: "开发解锁", systemImage: "wrench.and.screwdriver.fill", tone: .warning, action: store.activateProForDevelopment)
            if store.isProUnlocked {
                AppSecondaryButton(title: "切回免费", systemImage: "person.crop.circle.badge.minus", action: store.restoreFreeModeForDevelopment)
            }
        }
    }
}

struct ProFeatureGrid: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var showBackgroundPlan = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(title: "Pro 工具", subtitle: store.isProUnlocked ? "可用" : "已锁定", systemImage: "crown.fill")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: AppTheme.Spacing.section)], spacing: 0) {
                ProFeatureRow(title: "图片翻译", detail: "Vision OCR 与本地模型", systemImage: "camera.viewfinder", unlocked: store.isProUnlocked)
                ProFeatureRow(title: "音频翻译", detail: "Apple Speech 本机识别", systemImage: "waveform", unlocked: store.isProUnlocked)
                ProFeatureRow(title: "扩展语言", detail: "日语、法语与德语", systemImage: "globe", unlocked: store.isProUnlocked)
            }

            Button {
                showBackgroundPlan = true
            } label: {
                HStack(spacing: AppTheme.Spacing.control) {
                    Image(systemName: "rectangle.on.rectangle.badge.gearshape")
                        .foregroundStyle(Color.appAccent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("后台翻译路线").font(.subheadline.bold())
                        Text("Share Extension 或 ReplayKit 合规方案").font(.caption).foregroundStyle(Color.appTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "info.circle").accessibilityHidden(true)
                }
                .frame(minHeight: AppTheme.Layout.minimumTarget)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.appTextPrimary)
        }
        .alert("后台一键翻译", isPresented: $showBackgroundPlan) {} message: {
            Text("iOS 普通 App 不能常驻覆盖其他 App。可行路线是 Share Extension 处理截图或文本，或由用户显式启动 ReplayKit 屏幕广播后处理画面。")
        }
    }
}

private struct ProFeatureRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let unlocked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.control) {
            Image(systemName: systemImage).foregroundStyle(unlocked ? Color.appAccent : Color.locked).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(Color.appTextSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: unlocked ? "checkmark.circle.fill" : "lock.fill")
                .foregroundStyle(unlocked ? Color.success : Color.locked)
                .accessibilityLabel(unlocked ? "已解锁" : "已锁定")
        }
        .padding(.vertical, AppTheme.Spacing.control)
        .overlay(alignment: .bottom) { Divider().overlay(Color.appBorder) }
    }
}

struct SpeechCapabilityPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(title: "本机识别能力", subtitle: store.currentSpeechCapability.localeIdentifier, systemImage: "iphone.gen3.radiowaves.left.and.right")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: AppTheme.Spacing.section)], spacing: 0) {
                ForEach(store.speechRecognitionCapabilities) { capability in
                    AppStatusRow(
                        title: capability.language.rawValue,
                        detail: capability.supportsOnDeviceRecognition ? "支持本机识别" : "需要系统语言包",
                        tone: capability.supportsOnDeviceRecognition ? .success : .warning
                    )
                }
            }
        }
    }
}

struct SpeechRecognitionRunSummaryPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        let summary = store.speechRecognitionRunSummary
        if summary.hasContent {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                AppSectionHeader(title: "本次运行", subtitle: summary.inputName, systemImage: "gauge.with.dots.needle.bottom.50percent")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: AppTheme.Spacing.section)], spacing: 0) {
                    AppMetric(title: "模式", value: summary.mode.displayName, systemImage: "waveform")
                    AppMetric(title: "语言", value: summary.localeIdentifier, systemImage: "globe")
                    AppMetric(title: "离线", value: summary.requiresOnDeviceRecognition ? "强制本机" : "自动", systemImage: "wifi.slash")
                    AppMetric(title: "耗时", value: summary.elapsedSeconds.formatted(.number.precision(.fractionLength(1))) + "s", systemImage: "timer")
                    AppMetric(title: "词数", value: "\(summary.wordCount)", systemImage: "textformat.abc")
                    AppMetric(title: "片段", value: "\(summary.segmentCount)", systemImage: "waveform.path.ecg")
                    AppMetric(title: "置信度", value: confidenceText(summary.averageConfidence), systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
                if let failureMessage = summary.failureMessage {
                    AppStatusRow(title: "运行失败或取消", detail: failureMessage, tone: .danger)
                } else if !summary.transcriptPreview.isEmpty {
                    SelectableTextBlock(title: "识别预览", text: summary.transcriptPreview)
                }
            }
        }
    }

    private func confidenceText(_ confidence: Double?) -> String {
        confidence?.formatted(.percent.precision(.fractionLength(0))) ?? "采集中"
    }
}

struct AudioRecognitionPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        AppStatusRow(title: statusTitle, detail: store.audioRecognitionMessage, tone: statusTone)
        if !store.lastRecognizedSpeechText.isEmpty {
            SelectableTextBlock(title: "识别文本", text: store.lastRecognizedSpeechText)
        }
    }

    private var statusTitle: String {
        switch store.audioRecognitionState {
        case .idle: store.audioRecognitionMessage == "语音识别已取消" ? "已取消" : "等待音频"
        case .checking: "检查本机能力"
        case .recognizing: "正在识别"
        case .translating: "正在翻译"
        case .translated: "识别与翻译完成"
        case .failed: "处理失败"
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
}
