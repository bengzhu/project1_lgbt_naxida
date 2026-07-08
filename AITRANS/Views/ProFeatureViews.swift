import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ProFeatureGrid: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var showBackgroundPlan = false

    private let columns = [
        GridItem(.adaptive(minimum: 142), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Pro 功能", subtitle: store.isProUnlocked ? "已解锁" : "内购模式", icon: "crown.fill")

            LazyVGrid(columns: columns, spacing: 10) {
                ProFeatureCard(
                    icon: "camera.viewfinder",
                    title: "图片翻译",
                    detail: "Vision OCR + 本地模型翻译",
                    isUnlocked: store.isProUnlocked
                ) {
                    store.dataTransferMessage = store.isProUnlocked ? "请从图片页使用图片翻译" : "图片翻译需要 Pro"
                }

                ProFeatureCard(
                    icon: "waveform.badge.magnifyingglass",
                    title: "音频测试",
                    detail: "选择音频，断网本机识别后翻译",
                    isUnlocked: store.isProUnlocked
                ) {
                    store.dataTransferMessage = store.isProUnlocked ? "请从音频页使用音频翻译" : "音频离线识别测试需要 Pro"
                }

                ProFeatureCard(
                    icon: "rectangle.on.rectangle.badge.gearshape",
                    title: "后台翻译",
                    detail: "悬浮窗能力评估与扩展路线",
                    isUnlocked: store.isProUnlocked,
                    isComingSoon: true
                ) {
                    showBackgroundPlan = true
                }
            }

            SpeechCapabilityPanel()
        }
        .panelStyle()
        .alert("后台一键翻译", isPresented: $showBackgroundPlan) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("iOS 普通 App 不能常驻覆盖其他 App 的任意悬浮窗。可行路线是 Share Extension 处理截图/文本，或 ReplayKit Broadcast Upload Extension 获取屏幕帧后做本地 OCR，但需要用户显式启动屏幕广播。")
        }
    }
}

private struct ProFeatureCard: View {
    let icon: String
    let title: String
    let detail: String
    let isUnlocked: Bool
    var isComingSoon = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(isUnlocked ? Color.appAccent : Color.warning)
                    Spacer()
                    Image(systemName: isUnlocked ? "checkmark.circle.fill" : "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isUnlocked ? Color.success : Color.warning)
                }

                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(isComingSoon ? "开发中" : detail)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SpeechCapabilityPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.appAccent)
                Text("苹果本地语音识别")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(store.currentSpeechCapability.supportsOnDeviceRecognition ? "当前语言可用" : "当前语言需检测")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(store.currentSpeechCapability.supportsOnDeviceRecognition ? Color.success : Color.warning)
            }

            Text("iOS 13+ 的 Speech 框架可用 `supportsOnDeviceRecognition` 判断本机是否支持离线识别，并用 `requiresOnDeviceRecognition` 强制本地识别。支持情况取决于设备和语言包。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ForEach(store.speechRecognitionCapabilities.prefix(4)) { capability in
                    Text("\(capability.language.shortName) \(capability.supportsOnDeviceRecognition ? "本地" : "云端")")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(capability.supportsOnDeviceRecognition ? Color.success : .white.opacity(0.50))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

struct SpeechRecognitionRunSummaryPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        let summary = store.speechRecognitionRunSummary
        if summary.hasContent {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("识别质量", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(summary.mode.displayName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(summary.failureMessage == nil ? Color.appAccent : Color.danger)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    SpeechMetricTile(title: "语言", value: summary.localeIdentifier, icon: "globe.asia.australia.fill")
                    SpeechMetricTile(title: "离线", value: summary.requiresOnDeviceRecognition ? "强制本机" : "自动", icon: "wifi.slash")
                    SpeechMetricTile(title: "耗时", value: elapsedText(summary.elapsedSeconds), icon: "timer")
                    SpeechMetricTile(title: "词数", value: "\(summary.wordCount)", icon: "textformat.abc")
                    SpeechMetricTile(title: "片段", value: "\(summary.segmentCount)", icon: "waveform.path.ecg")
                    SpeechMetricTile(title: "置信", value: confidenceText(summary.averageConfidence), icon: "gauge.with.dots.needle.bottom.50percent")
                }

                if let failureMessage = summary.failureMessage {
                    Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !summary.transcriptPreview.isEmpty {
                    Text(summary.transcriptPreview)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(
                LinearGradient(
                    colors: [
                        Color.appAccent.opacity(0.20),
                        Color.white.opacity(0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
        }
    }

    private func elapsedText(_ elapsedSeconds: TimeInterval) -> String {
        "\(Int(elapsedSeconds.rounded()))s"
    }

    private func confidenceText(_ confidence: Double?) -> String {
        guard let confidence else { return "采集中" }
        return "\(Int((confidence * 100).rounded()))%"
    }
}

private struct SpeechMetricTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.54))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(value)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AudioRecognitionPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                Text("音频文件断网测试")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(statusText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
            }

            Text(store.audioRecognitionMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            if !store.lastRecognizedSpeechText.isEmpty {
                Text(store.lastRecognizedSpeechText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            SpeechRecognitionRunSummaryPanel()
        }
        .padding(12)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var icon: String {
        switch store.audioRecognitionState {
        case .idle: "waveform"
        case .checking: "magnifyingglass"
        case .recognizing: "waveform.path"
        case .translating: "character.bubble.fill"
        case .translated: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch store.audioRecognitionState {
        case .idle: .white.opacity(0.58)
        case .checking, .recognizing, .translating: Color.warning
        case .translated: Color.success
        case .failed: Color.danger
        }
    }

    private var statusText: String {
        switch store.audioRecognitionState {
        case .idle: "待选择"
        case .checking: "检查中"
        case .recognizing: "识别中"
        case .translating: "翻译中"
        case .translated: "已翻译"
        case .failed: "失败"
        }
    }
}
