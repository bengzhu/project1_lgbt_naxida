import SwiftUI
import Foundation

#if DEBUG
struct BrowserDebugLogView: View {
    @Environment(BrowserDebugLogStore.self) private var debugLogStore
    @State private var selectedSession: BrowserDebugLogStore.Session?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                AppPageHeader(
                    title: "浏览器诊断日志",
                    subtitle: "仅记录漫画 WKWebView 的请求与 DOM 元数据",
                    systemImage: "ladybug.fill",
                    status: debugLogStore.isRecording ? "录制中" : "已停止",
                    statusTone: debugLogStore.isRecording ? .warning : .neutral,
                    feature: .library
                )

                recordingPanel
                sessionsPanel
            }
            .enterprisePageFrame()
            .padding(.vertical, AppTheme.Spacing.section)
            .padding(.bottom, 72)
        }
        .background(Color.appCanvas)
        .navigationTitle("浏览器诊断日志")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedSession) { session in
            NavigationStack {
                BrowserDebugLogSessionDetail(session: session)
            }
        }
    }

    private var recordingPanel: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(
                title: "录制控制",
                subtitle: "不读取请求/响应正文，不参与广告拦截或翻译",
                systemImage: "record.circle"
            )
            HStack(spacing: AppTheme.Spacing.control) {
                Button {
                    debugLogStore.send(.stop)
                } label: {
                    Label(
                        "停止录制",
                        systemImage: "stop.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!debugLogStore.isRecording)

                if !debugLogStore.sessions.isEmpty {
                    Button("清空已保存") { debugLogStore.send(.clearAll) }
                        .buttonStyle(.bordered)
                        .disabled(debugLogStore.isRecording)
                }
            }
            if !debugLogStore.isRecording {
                Text("开始录制请返回漫画页，打开翻译悬浮球并点击 Debug 日志。")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            Text(debugLogStore.message)
                .font(.caption)
                .foregroundStyle(debugLogStore.lastError == nil ? Color.appTextSecondary : Color.orange)
                .lineLimit(3)
            if debugLogStore.isRecording {
                Label(
                    "当前条目 \(debugLogStore.currentEntries.count)",
                    systemImage: "waveform.path.ecg"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.appTextSecondary)
            }
        }
        .appSurface()
    }

    private var sessionsPanel: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(
                title: "已保存录制",
                subtitle: "最多保留 20 个会话，每个会话最多 2,000 条元数据",
                systemImage: "archivebox"
            )
            if debugLogStore.sessions.isEmpty {
                ContentUnavailableView(
                    "暂无诊断日志",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("在漫画页悬浮球中开始录制，再打开此处导出。")
                )
            } else {
                ForEach(debugLogStore.sessions) { session in
                    BrowserDebugLogSessionRow(
                        session: session,
                        onOpen: { selectedSession = session },
                        onDelete: { debugLogStore.send(.delete(session.id)) },
                        exportData: debugLogStore.exportData(for: session.id)
                    )
                }
            }
        }
        .appSurface()
    }
}

private struct BrowserDebugLogSessionRow: View {
    let session: BrowserDebugLogStore.Session
    let onOpen: () -> Void
    let onDelete: () -> Void
    let exportData: Data?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.control) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.appTextPrimary)
                    Text("条目 \(session.entries.count) · 时长 \(String(format: "%.1f", session.duration)) 秒")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开诊断日志")

            if let exportData {
                ShareLink(
                    item: exportData,
                    preview: SharePreview("浏览器诊断日志", image: Image(systemName: "ladybug.fill"))
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("导出诊断日志")
            }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("删除诊断日志")
        }
        .padding(.vertical, AppTheme.Spacing.compact)
        Divider().overlay(Color.appBorder)
    }
}

private struct BrowserDebugLogSessionDetail: View {
    let session: BrowserDebugLogStore.Session

    var body: some View {
        List {
            Section {
                LabeledContent("开始", value: session.startedAt.formatted(date: .abbreviated, time: .standard))
                LabeledContent("结束", value: session.endedAt.formatted(date: .abbreviated, time: .standard))
                LabeledContent("条目", value: "\(session.entries.count)")
                LabeledContent("标签页", value: String(session.tabID.uuidString.prefix(8)) + "…")
            }
            Section("事件") {
                ForEach(session.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.kind.rawValue)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if let url = entry.url, !url.isEmpty {
                            Text(url)
                                .font(.caption2.monospaced())
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                        if !entry.detail.isEmpty {
                            Text(entry.detail.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("诊断日志详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
