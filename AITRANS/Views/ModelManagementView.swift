import SwiftUI
import UniformTypeIdentifiers

struct ModelManagementView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var showModelImporter = false
    @State private var showRemoveConfirmation = false
    @State private var showImportResult = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                AppPageHeader(
                    title: "模型",
                    subtitle: "运行引擎与生成参数",
                    systemImage: "cpu.fill",
                    status: store.modelStatus.title,
                    statusTone: store.modelStatus.isReady ? .success : .warning
                )
                EngineSection()
                ModelFileSection(
                    importModel: { showModelImporter = true },
                    removeModel: { showRemoveConfirmation = true }
                )
                SamplingSection()
                DiagnosticsSection()
                AdapterSection()
            }
            .enterprisePageFrame()
            .padding(.vertical, AppTheme.Spacing.section)
            .padding(.bottom, 72)
        }
        .background(Color.appCanvas)
        .fileImporter(isPresented: $showModelImporter, allowedContentTypes: [.ggufModel]) { result in
            switch result {
            case .success(let url): _ = store.importLocalModel(from: url)
            case .failure(let error): store.dataTransferMessage = "模型选择失败：\(error.localizedDescription)"
            }
            showImportResult = true
        }
        .confirmationDialog("移除本地模型？", isPresented: $showRemoveConfirmation, titleVisibility: .visible) {
            Button("移除模型", role: .destructive, action: store.removeLocalModel)
            Button("取消", role: .cancel) {}
        } message: {
            Text("GGUF 文件将从 App 沙盒删除，Mock 引擎不受影响。")
        }
        .alert("模型文件", isPresented: $showImportResult) {} message: { Text(store.dataTransferMessage) }
    }
}

private struct EngineSection: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(title: "运行引擎", subtitle: store.selectedEngine.rawValue, systemImage: "switch.2")
            Picker("运行引擎", selection: engineBinding) {
                ForEach(ModelEngine.allCases) { engine in
                    Label(engine.rawValue, systemImage: engine.systemImage).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            AppStatusRow(
                title: store.modelStatus.title,
                detail: store.modelStatus.detail,
                tone: store.modelStatus.isReady ? .success : .warning
            )
        }
        .appSurface()
    }

    private var engineBinding: Binding<ModelEngine> {
        Binding(get: { store.selectedEngine }, set: store.selectEngine)
    }
}

private struct ModelFileSection: View {
    @EnvironmentObject private var store: TranslationSessionStore
    let importModel: () -> Void
    let removeModel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(title: "模型文件", subtitle: store.localModelSizeDisplay, systemImage: "externaldrive.fill")
            AppStatusRow(
                title: store.isLocalModelInstalled ? "Local 已就绪" : "尚未安装 GGUF",
                detail: store.localModelPathDisplay,
                tone: store.isLocalModelInstalled ? .success : .warning
            )

            if store.modelDownload.isDownloading {
                ProgressView(value: store.modelDownload.fractionCompleted)
                    .tint(.appAccent)
                LabeledContent("下载") { Text(store.modelDownloadProgressDisplay).monospacedDigit() }
                LabeledContent("速度") { Text(store.modelDownloadSpeedDisplay).monospacedDigit() }
                AppSecondaryButton(title: "取消下载", systemImage: "xmark.circle.fill", tone: .danger, action: store.cancelModelDownload)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.Spacing.control) { fileActions }
                    VStack(spacing: AppTheme.Spacing.control) { fileActions }
                }
            }
            Text(store.dataTransferMessage).font(.subheadline).foregroundStyle(.appTextSecondary)
        }
        .appSurface()
    }

    @ViewBuilder private var fileActions: some View {
        AppPrimaryButton(title: store.isLocalModelInstalled ? "模型已安装" : "下载内置模型", systemImage: "arrow.down.circle.fill", action: store.downloadBuiltInModel)
            .disabled(store.isLocalModelInstalled)
        AppSecondaryButton(title: "导入 GGUF", systemImage: "square.and.arrow.down", action: importModel)
        if store.isLocalModelInstalled {
            AppSecondaryButton(title: "移除模型", systemImage: "trash", tone: .danger, action: removeModel)
        }
    }
}

private struct SamplingSection: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(title: "生成参数", subtitle: "本地保存", systemImage: "dial.low.fill")
            LabeledContent("Temperature") {
                Text(store.sampling.temperature, format: .number.precision(.fractionLength(2))).monospacedDigit().foregroundStyle(.appAccent)
            }
            Slider(value: temperatureBinding, in: 0...1.2).tint(.appAccent)
                .accessibilityValue(store.sampling.temperature.formatted(.number.precision(.fractionLength(2))))
            Stepper(value: maxTokensBinding, in: 128...2_048, step: 128) {
                LabeledContent("Max Tokens") { Text(store.sampling.maxTokens, format: .number).monospacedDigit().foregroundStyle(.appAccent) }
            }
        }
        .appSurface()
    }

    private var temperatureBinding: Binding<Double> { Binding(get: { store.sampling.temperature }, set: store.setTemperature) }
    private var maxTokensBinding: Binding<Int> { Binding(get: { store.sampling.maxTokens }, set: store.setMaxTokens) }
}

private struct DiagnosticsSection: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(title: "诊断", subtitle: store.selectedAdapterMetadata.displayName, systemImage: "checklist.checked")
            LazyVStack(spacing: 0) {
                ForEach(store.diagnostics) { check in
                    AppStatusRow(title: check.title, detail: check.detail, tone: tone(check.state))
                }
            }
            AppStatusRow(title: "LLM 接口自测", detail: store.llmSmokeTest.message, tone: tone(store.llmSmokeTest.state))
            if !store.llmSmokeTest.output.isEmpty { SelectableTextBlock(title: "自测输出", text: store.llmSmokeTest.output) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.control) { diagnosticActions }
                VStack(spacing: AppTheme.Spacing.control) { diagnosticActions }
            }
        }
        .appSurface()
    }

    @ViewBuilder private var diagnosticActions: some View {
        AppPrimaryButton(title: store.isRunningDiagnostics ? "自检中" : "运行自检", systemImage: "play.fill", isWorking: store.isRunningDiagnostics, action: store.runDiagnostics)
            .disabled(store.isRunningDiagnostics || store.isRunningLLMSmokeTest)
        AppSecondaryButton(title: store.isRunningLLMSmokeTest ? "接口测试中" : "运行接口自测", systemImage: "arrow.left.arrow.right.circle", action: store.runLLMInterfaceSmokeTest)
            .disabled(store.isRunningDiagnostics || store.isRunningLLMSmokeTest)
    }

    private func tone(_ state: DiagnosticState) -> AppStatusTone {
        switch state {
        case .idle: .neutral
        case .running: .active
        case .passed: .success
        case .failed: .danger
        }
    }
}

private struct AdapterSection: View {
    @EnvironmentObject private var store: TranslationSessionStore
    var body: some View {
        let metadata = store.selectedAdapterMetadata
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(title: "适配器", subtitle: metadata.displayName, systemImage: "point.3.connected.trianglepath.dotted")
            AppStatusRow(title: metadata.modelName, detail: "\(metadata.quantization) · \(metadata.supportsStreaming ? "流式" : "一次性返回")", tone: .neutral)
        }
    }
}

private extension UTType {
    static let ggufModel = UTType(filenameExtension: "gguf") ?? .data
}
