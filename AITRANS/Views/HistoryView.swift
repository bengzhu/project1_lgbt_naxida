import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedTab: AppTab
    @State private var query = ""
    @State private var showClearConfirmation = false
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var showResult = false
    @State private var pendingDeletion: TranslationSessionRecord?
    @State private var exportDocument = JSONExportDocument(data: Data())

    private var filteredSessions: [TranslationSessionRecord] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return store.recentSessions }
        return store.recentSessions.filter { record in
            record.title.localizedStandardContains(cleanQuery)
                || record.transcript.contains { line in
                    line.original.localizedStandardContains(cleanQuery)
                        || line.translation.localizedStandardContains(cleanQuery)
                }
                || record.summary.bullets.contains { $0.localizedStandardContains(cleanQuery) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                AppPageHeader(
                    title: "历史",
                    subtitle: store.storageSummary,
                    systemImage: "clock.arrow.circlepath",
                    status: "\(store.totalSessionCount) 个会话",
                    statusTone: .neutral,
                    feature: .library
                )
                commandBar

                if store.history.isEmpty {
                    AppEmptyState(title: "暂无历史", detail: "归档当前会话后，记录会保存在本机。", systemImage: "clock")
                } else if filteredSessions.isEmpty {
                    ContentUnavailableView.search
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(minHeight: 240)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSessions) { record in
                            HistorySessionRow(
                                record: record,
                                open: { open(record) },
                                delete: { pendingDeletion = record }
                            )
                        }
                    }
                }
            }
            .enterprisePageFrame()
            .padding(.vertical, AppTheme.Spacing.section)
            .padding(.bottom, 72)
        }
        .background(Color.appCanvas)
        .confirmationDialog("清空全部历史？", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) { store.clearHistory() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前会话会保留，历史记录将从本机删除。")
        }
        .confirmationDialog("删除这条历史？", isPresented: deletionPresented, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let pendingDeletion { store.deleteSession(pendingDeletion) }
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], onCompletion: importSnapshot)
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "aitrans-export",
            onCompletion: finishExport
        )
        .alert("数据操作", isPresented: $showResult) {} message: {
            Text(store.dataTransferMessage)
        }
    }

    private var commandBar: some View {
        HStack(spacing: AppTheme.Spacing.control) {
            TextField("搜索历史", text: $query)
                .textFieldStyle(.plain)
                .padding(.horizontal, AppTheme.Spacing.control)
                .frame(minHeight: AppTheme.Layout.minimumTarget)
                .background(Color.appSurface, in: .rect(cornerRadius: AppTheme.Radius.control))
                .overlay { RoundedRectangle(cornerRadius: AppTheme.Radius.control).stroke(Color.appBorder) }

            Menu("历史操作", systemImage: "ellipsis.circle") {
                Button("归档当前", systemImage: "tray.and.arrow.down", action: store.archiveCurrentSession)
                Button("导入", systemImage: "square.and.arrow.down") { showImporter = true }
                Button("导出", systemImage: "square.and.arrow.up", action: prepareExport)
                Divider()
                Button("清空", systemImage: "trash", role: .destructive) { showClearConfirmation = true }
                    .disabled(store.history.isEmpty)
            }
            .labelStyle(.iconOnly)
            .font(.title3.bold())
            .foregroundStyle(Color.appTextPrimary)
            .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
            .background(Color.appSurfaceRaised, in: .rect(cornerRadius: AppTheme.Radius.control))
            .overlay { RoundedRectangle(cornerRadius: AppTheme.Radius.control).stroke(Color.appBorder) }
            .accessibilityLabel("历史操作")
        }
    }

    private var deletionPresented: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    private func open(_ record: TranslationSessionRecord) {
        store.loadSession(record)
        selectedTab = .text
    }

    private func prepareExport() {
        guard let url = store.exportSnapshot(), let data = try? Data(contentsOf: url) else {
            showResult = true
            return
        }
        exportDocument = JSONExportDocument(data: data)
        showExporter = true
    }

    private func importSnapshot(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url): _ = store.importSnapshot(from: url)
        case .failure(let error): store.dataTransferMessage = "导入失败：\(error.localizedDescription)"
        }
        showResult = true
    }

    private func finishExport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url): store.dataTransferMessage = "已导出到 \(url.lastPathComponent)"
        case .failure(let error): store.dataTransferMessage = "导出失败：\(error.localizedDescription)"
        }
        showResult = true
    }
}

private struct HistorySessionRow: View {
    let record: TranslationSessionRecord
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.control) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    HStack {
                        Text(record.title).font(.body.bold()).foregroundStyle(Color.appTextPrimary)
                        Spacer(minLength: AppTheme.Spacing.control)
                        Text(record.updatedAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    Label(
                        "\(record.sourceLanguage.shortName) -> \(record.targetLanguage.shortName) · \(record.transcript.count) 条",
                        systemImage: record.selectedEngine.systemImage
                    )
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
                    Text(record.transcript.first?.translation ?? record.summary.title)
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextPrimary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("恢复这次会话并返回文本工作台")

            AppIconButton(title: "删除 \(record.title)", systemImage: "trash", tone: .danger, action: delete)
        }
        .padding(.vertical, AppTheme.Spacing.control)
        .overlay(alignment: .bottom) { Divider().overlay(Color.appBorder) }
    }
}

private struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
