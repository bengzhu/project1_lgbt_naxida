import SwiftUI

struct DeveloperConsoleView: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                AppPageHeader(
                    title: "开发控制台",
                    subtitle: "原始模型输入、输出与探针",
                    systemImage: "hammer.fill",
                    status: store.isRunningDeveloperProbe ? "运行中" : "已开启",
                    statusTone: store.isRunningDeveloperProbe ? .active : .warning
                )
                DeveloperTestSection()
                RawProbeSection()
                DeveloperProbeCasesSection()
                DeveloperRawOutputSection()
                MangaProbeSection()
                AppSecondaryButton(title: "关闭开发者模式", systemImage: "lock.fill", tone: .warning, action: store.disableDeveloperMode)
            }
            .enterprisePageFrame(maxWidth: 1_100)
            .padding(.vertical, AppTheme.Spacing.section)
            .padding(.bottom, 72)
        }
        .background(Color.appCanvas)
    }
}

private struct DeveloperTestSection: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(title: "固定测试入口", subtitle: "bundle test/", systemImage: "testtube.2")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.control) { actions }
                VStack(spacing: AppTheme.Spacing.control) { actions }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        AppSecondaryButton(title: "运行 test/ 音频", systemImage: "waveform.badge.magnifyingglass", action: store.runBundledAudioTest)
        AppSecondaryButton(title: "运行 test/ OCR", systemImage: "text.viewfinder", action: store.runBundledOCRImageTest)
    }
}

private struct RawProbeSection: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(
                title: "原始接口",
                subtitle: "\(store.sourceLanguage.shortName) -> \(store.targetLanguage.shortName)",
                systemImage: "terminal.fill"
            )
            TextField("探针输入", text: $store.developerProbeInput, axis: .vertical)
                .font(.body.monospaced())
                .lineLimit(5...12)
                .textFieldStyle(.plain)
                .padding(AppTheme.Spacing.section)
                .background(Color.appCanvas, in: .rect(cornerRadius: AppTheme.Radius.control))
                .overlay { RoundedRectangle(cornerRadius: AppTheme.Radius.control).stroke(Color.appBorder) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.control) { actions }
                VStack(spacing: AppTheme.Spacing.control) { actions }
            }
        }
        .appSurface()
    }

    @ViewBuilder private var actions: some View {
        AppPrimaryButton(title: store.isRunningDeveloperProbe ? "运行中" : "运行原始接口", systemImage: "play.fill", isWorking: store.isRunningDeveloperProbe, action: store.runDeveloperRawProbe)
            .disabled(store.isRunningDeveloperProbe)
        AppSecondaryButton(title: "运行批量探针", systemImage: "list.bullet.clipboard.fill", action: store.runDeveloperRawProbeSuite)
            .disabled(store.isRunningDeveloperProbe)
    }
}

private struct DeveloperProbeCasesSection: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        if !store.developerProbeCases.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
                AppSectionHeader(title: "批量结果", subtitle: "\(store.developerProbeCases.count) 条", systemImage: "list.bullet.rectangle")
                LazyVStack(spacing: 0) {
                    ForEach(store.developerProbeCases) { probeCase in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
                                if !probeCase.prompt.isEmpty { DeveloperCodeBlock(title: "prompt", text: probeCase.prompt) }
                                if let errorCode = probeCase.errorCode, !errorCode.isEmpty {
                                    DeveloperCodeBlock(title: "error", text: errorCode)
                                } else if !probeCase.output.isEmpty {
                                    DeveloperCodeBlock(title: "raw output", text: probeCase.output)
                                }
                            }
                            .padding(.vertical, AppTheme.Spacing.control)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(probeCase.sourceLanguage.shortName) -> \(probeCase.targetLanguage.shortName)").font(.subheadline.bold())
                                    Text(probeCase.input).font(.caption).foregroundStyle(.appTextSecondary).lineLimit(2)
                                }
                                Spacer()
                                AppStatusLabel(text: probeCase.verdict, tone: probeCase.errorCode == nil ? .success : .danger)
                            }
                            .padding(.vertical, AppTheme.Spacing.control)
                        }
                        .overlay(alignment: .bottom) { Divider().overlay(Color.appBorder) }
                    }
                }
            }
        }
    }
}

private struct DeveloperRawOutputSection: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.section) {
                DeveloperCodeBlock(title: "大模型实际输入", text: store.developerProbePrompt.isEmpty ? "运行后显示完整 prompt。" : store.developerProbePrompt)
                DeveloperCodeBlock(title: store.developerProbeError.isEmpty ? "大模型实际输出" : "错误代码", text: outputText)
            }
            VStack(spacing: AppTheme.Spacing.section) {
                DeveloperCodeBlock(title: "大模型实际输入", text: store.developerProbePrompt.isEmpty ? "运行后显示完整 prompt。" : store.developerProbePrompt)
                DeveloperCodeBlock(title: store.developerProbeError.isEmpty ? "大模型实际输出" : "错误代码", text: outputText)
            }
        }
    }

    private var outputText: String {
        if !store.developerProbeError.isEmpty { return store.developerProbeError }
        return store.developerProbeOutput.isEmpty ? "运行后显示模型原始输出。" : store.developerProbeOutput
    }
}

private struct MangaProbeSection: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(title: "漫画覆盖翻译探针", subtitle: "test/1.png -> Output", systemImage: "rectangle.3.group.bubble.left.fill")
            AppStatusRow(title: probeStatusTitle, detail: store.mangaOverlayProbeMessage, tone: probeTone)
            AppPrimaryButton(
                title: store.isRunningMangaOverlayProbe ? "探针运行中" : "运行漫画覆盖翻译探针",
                systemImage: "photo.badge.checkmark",
                isWorking: store.isRunningMangaOverlayProbe,
                action: store.runMangaOverlayProbe
            )
            .disabled(store.isRunningMangaOverlayProbe)

            if let report = store.mangaOverlayProbeReport {
                DeveloperCodeBlock(
                    title: "probe_report summary",
                    text: "source=\(report.sourceImage)\nengine=\(report.engineUsed)\nblocks=\(report.totalBlocksDetected)\noverallPassed=\(report.overallPassed)\ndebug=\(report.outputFiles.debugBoxesImage)\noverlay=\(report.outputFiles.overlayImage)\nwarnings=\(report.warnings.joined(separator: " | "))"
                )
            }

            LazyVStack(spacing: 0) {
                ForEach(store.mangaOverlayProbeBlocks) { block in
                    MangaProbeBlockRow(block: block)
                }
            }
        }
        .appSurface()
    }

    private var probeStatusTitle: String {
        switch store.mangaOverlayProbeState {
        case .idle: "等待运行"
        case .loading: "载入图片"
        case .recognizing: "OCR 识别"
        case .translating: "翻译"
        case .rendering: "绘制输出"
        case .completed: "已完成"
        case .failed: "失败"
        }
    }

    private var probeTone: AppStatusTone {
        switch store.mangaOverlayProbeState {
        case .idle: .neutral
        case .loading, .recognizing, .translating, .rendering: .active
        case .completed: .success
        case .failed: .danger
        }
    }
}

private struct MangaProbeBlockRow: View {
    let block: MangaOverlayProbeBlock

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
                DeveloperCodeBlock(title: "ocr", text: block.ocrText)
                if !block.translatedText.isEmpty { DeveloperCodeBlock(title: "translation", text: block.translatedText) }
                if !block.failureReasons.isEmpty { DeveloperCodeBlock(title: "failure", text: block.failureReasons.joined(separator: "\n")) }
                if !block.prompt.isEmpty { DeveloperCodeBlock(title: "prompt", text: block.prompt) }
                if let errorCode = block.errorCode, !errorCode.isEmpty {
                    DeveloperCodeBlock(title: "error", text: errorCode)
                } else if !block.rawOutput.isEmpty {
                    DeveloperCodeBlock(title: "raw output", text: block.rawOutput)
                }
            }
            .padding(.vertical, AppTheme.Spacing.control)
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(block.index) · \(block.rotationAngleUsed) deg").font(.subheadline.bold())
                    Text(block.ocrText).font(.caption).foregroundStyle(.appTextSecondary).lineLimit(2)
                }
                Spacer()
                AppStatusLabel(text: block.blockPassed ? "PASS" : "FAIL", tone: block.blockPassed ? .success : .danger)
            }
            .padding(.vertical, AppTheme.Spacing.control)
        }
        .overlay(alignment: .bottom) { Divider().overlay(Color.appBorder) }
    }
}

private struct DeveloperCodeBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack {
                Text(title).font(.caption.monospaced().bold()).foregroundStyle(.appTextSecondary)
                Spacer()
                ShareLink(item: text) { Label("复制或分享", systemImage: "doc.on.doc").labelStyle(.iconOnly) }
                    .accessibilityLabel("复制或分享 \(title)")
            }
            ScrollView {
                Text(text)
                    .font(.caption.monospaced())
                    .foregroundStyle(.appTextPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 120, maxHeight: 280)
        }
        .padding(AppTheme.Spacing.control)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCanvas, in: .rect(cornerRadius: AppTheme.Radius.control))
        .overlay { RoundedRectangle(cornerRadius: AppTheme.Radius.control).stroke(Color.appBorder) }
    }
}
