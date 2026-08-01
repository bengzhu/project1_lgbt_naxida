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
                SpeechQualityProbeSection()
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

private struct SpeechQualityProbeSection: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(
                title: "语音识别质量探针",
                subtitle: "speech_corpus -> Output",
                systemImage: "waveform.badge.magnifyingglass"
            )
            AppStatusRow(title: statusTitle, detail: store.speechQualityProbeMessage, tone: statusTone)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.control) { actions }
                VStack(spacing: AppTheme.Spacing.control) { actions }
            }
            if let report = store.speechQualityProbeReport {
                DeveloperCodeBlock(title: "speech_quality_report summary", text: summary(report))
            }
        }
        .appSurface()
    }

    @ViewBuilder private var actions: some View {
        AppPrimaryButton(
            title: store.isRunningSpeechQualityProbe ? "质量探针运行中" : "运行语音质量探针",
            systemImage: "play.fill",
            isWorking: store.isRunningSpeechQualityProbe,
            action: store.runSpeechQualityProbe
        )
        .disabled(store.isRunningSpeechQualityProbe)
        if store.isRunningSpeechQualityProbe {
            AppSecondaryButton(title: "取消", systemImage: "stop.fill", tone: .warning, action: store.cancelSpeechQualityProbe)
        }
    }

    private var statusTitle: String {
        switch store.speechQualityProbeState {
        case .idle: "等待语料"
        case .loadingManifest: "读取清单"
        case .requestingAuthorization: "请求权限"
        case .validatingAudio: "校验音频"
        case .recognizing: "识别与评分"
        case .completed: "已完成"
        case .failed: "未执行"
        case .cancelled: "已取消"
        }
    }

    private var statusTone: AppStatusTone {
        switch store.speechQualityProbeState {
        case .idle: .neutral
        case .loadingManifest, .requestingAuthorization, .validatingAudio, .recognizing: .active
        case .completed: .success
        case .failed, .cancelled: .warning
        }
    }

    private func summary(_ report: SpeechQualityProbeReport) -> String {
        let aggregate = report.aggregate
        let wer = aggregate.weightedWordErrorRate.map { String(format: "%.4f", $0) } ?? "n/a"
        let cer = aggregate.weightedCharacterErrorRate.map { String(format: "%.4f", $0) } ?? "n/a"
        let latency = aggregate.averageLatencySeconds.map { String(format: "%.3fs", $0) } ?? "n/a"
        return "verdict=\(report.verdict.rawValue)\ncorpus=\(report.corpusID ?? "n/a")@\(report.corpusVersion ?? "n/a")\nmanifestSHA256=\(report.corpusManifestSHA256 ?? "n/a")\nscored=\(aggregate.recognizedCaseCount)/\(aggregate.totalCaseCount)\nweightedWER=\(wer)\nweightedCER=\(cer)\naverageLatency=\(latency)\nfailures=\(aggregate.failureBreakdown)\nreferenceUsedForRecognitionDecision=\(report.referenceUsedForRecognitionDecision)\nwarnings=\(report.warnings.joined(separator: " | "))"
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
                    ForEach(store.developerProbeCases, id: \.id) { probeCase in
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
                                    Text(probeCase.input).font(.caption).foregroundStyle(Color.appTextSecondary).lineLimit(2)
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("漫画覆盖翻译探针状态")
                .accessibilityValue(probeStatusAccessibilityValue)
                .accessibilityHint(probeStatusAccessibilityHint)
            AppPrimaryButton(
                title: store.isRunningMangaOverlayProbe ? "探针运行中" : "运行漫画覆盖翻译探针",
                systemImage: "photo.badge.checkmark",
                isWorking: store.isRunningMangaOverlayProbe,
                action: store.runMangaOverlayProbe
            )
            .disabled(store.isRunningMangaOverlayProbe)
            .accessibilityHint(mangaProbeActionAccessibilityHint)

            if let report = store.mangaOverlayProbeReport {
                DeveloperCodeBlock(
                    title: "probe_report summary",
                    text: "source=\(report.sourceImage)\nengine=\(report.engineUsed)\nblocks=\(report.totalBlocksDetected)\noverallPassed=\(report.overallPassed)\ndebug=\(report.outputFiles.debugBoxesImage)\noverlay=\(report.outputFiles.overlayImage)\nwarnings=\(report.warnings.joined(separator: " | "))"
                )
                if let readiness = report.externalArtifactReadinessReport {
                    MangaKoharuArtifactReadinessSummary(readiness: readiness)
                }
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

    private var probeStatusAccessibilityValue: String {
        let detail = store.mangaOverlayProbeMessage.isEmpty ? "暂无附加详情" : store.mangaOverlayProbeMessage
        return "\(probeStatusTitle)：\(detail)"
    }

    private var probeStatusAccessibilityHint: String {
        switch store.mangaOverlayProbeState {
        case .idle:
            "运行后读取 bundle 的 test/1.png，生成漫画探针诊断输出；不会改变普通图片 OCR、翻译或覆盖图"
        case .loading:
            "正在读取 bundle 的 test/1.png；当前结果只属于漫画探针诊断"
        case .recognizing:
            "正在执行 Vision OCR 诊断；识别块会保留在探针报告中供复查"
        case .translating:
            "正在执行漫画探针翻译；失败 block 仍会保留原文和失败详情"
        case .rendering:
            "正在生成覆盖图、JSON 和 TXT 输出；不会改变普通图片翻译结果"
        case .completed:
            "可查看 probe_report、覆盖图和逐块结果；再次运行仍只更新漫画探针诊断输出"
        case .failed:
            "探针失败；请查看状态详情和输出后重试，不会影响普通图片 OCR 或翻译"
        }
    }

    private var mangaProbeActionAccessibilityHint: String {
        if store.isRunningMangaOverlayProbe {
            return "漫画覆盖翻译探针正在运行；完成后可查看诊断报告和覆盖图"
        }
        return "读取 bundle 的 test/1.png，运行 Vision OCR、确定性翻译和覆盖绘制，并生成 Output 诊断文件；不会改变普通图片 OCR、翻译或覆盖图"
    }
}

private struct MangaKoharuArtifactReadinessSummary: View {
    let readiness: MangaOverlayExternalArtifactReadinessReport

    var body: some View {
        AppStatusRow(title: statusTitle, detail: statusDetail, tone: statusTone)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Koharu 工件就绪状态")
            .accessibilityValue(readinessAccessibilityValue)
            .accessibilityHint(readinessAccessibilityHint)
        DeveloperCodeBlock(title: "Koharu artifact readiness", text: summary)
    }

    private var statusTitle: String {
        switch readiness.readinessVerdict {
        case "readyForShadowOCR" where readiness.externalTextBoxesShadowOCRAllowed:
            "真实 Koharu 工件已就绪（仅 shadow OCR）"
        case "manifestMissing", "artifactFilesMissing":
            "等待真实 Koharu 四件套"
        default:
            "Koharu 工件需要修正"
        }
    }

    private var statusDetail: String {
        let missing = readiness.missingArtifacts.isEmpty
            ? "四件套已齐。"
            : "缺少：\(readiness.missingArtifacts.joined(separator: "、"))。"
        return "\(missing)\(nextActionDetail)\(readinessGateDetail) 本摘要只读，仅影响探针 shadow OCR，不改变普通图片 OCR、翻译或覆盖图。"
    }

    private var statusTone: AppStatusTone {
        switch readiness.readinessVerdict {
        case "readyForShadowOCR" where readiness.externalTextBoxesShadowOCRAllowed:
            .success
        case "manifestMissing", "artifactFilesMissing":
            .warning
        default:
            .danger
        }
    }

    private var nextActionDetail: String {
        switch readiness.nextAction {
        case "stopUntilArtifactsProvided":
            "请将真实四件套放入 test/koharu_artifacts/：1.manifest.json、1.textboxes.json、1.bubbles.json、1.segment_mask.json。"
        case "stopUntilArtifactContractFixed":
            "请先修正四件套契约、坐标或来源身份。"
        case "stopUntilRealDetectorSourceDeclared":
            "请先声明真实 detector / segmenter 来源；fixture 和 proxy 不能作为 active artifact。"
        case "continueWithExternalTextBoxesShadowOCR":
            "下一次探针可执行 external TextBoxes shadow OCR，结果仍只写入诊断输出。"
        default:
            "下一步：\(readiness.nextAction)。"
        }
    }

    private var readinessGateDetail: String {
        " 门控摘要：坐标\(coordinateGateStatus)、mask payload \(maskPayloadGateStatus)、mask 拓扑 \(maskTopologyGateStatus)、工件身份 \(artifactIdentityGateStatus)。"
    }

    private var coordinateGateStatus: String {
        guard readiness.manifestFound else { return "未评估" }
        return readiness.coordinateValidation.bboxValidationPassed ? "通过" : "待修正"
    }

    private var isLegacySummaryOnlyArtifact: Bool {
        readiness.coordinateValidation.schemaVersion == "aitrans.koharu_artifact_contract.v1"
            && readiness.bubbleMaskPayloadVerdict == "legacySummaryOnly"
            && readiness.segmentMaskPayloadVerdict == "legacySummaryOnly"
    }

    private var maskPayloadGateStatus: String {
        if isLegacySummaryOnlyArtifact {
            return "未要求（v1 summary-only）"
        }
        guard let gateReady = readiness.maskPayloadGateReady else { return "未评估" }
        if gateReady { return "通过" }
        let verdicts = [
            readiness.bubbleMaskPayloadVerdict,
            readiness.segmentMaskPayloadVerdict
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        if verdicts.isEmpty { return "未通过" }
        return "未通过（\(verdicts.joined(separator: "/"))）"
    }

    private var maskTopologyGateStatus: String {
        if isLegacySummaryOnlyArtifact {
            return "未要求（v2 拓扑）"
        }
        if readiness.maskTopologyGateReady == true { return "完整" }
        guard let report = readiness.maskTopologyReport else { return "未评估" }
        let verdict = report.topologyVerdict.isEmpty ? "待复核" : report.topologyVerdict
        if report.blockers.isEmpty { return verdict }
        return "\(verdict)，\(report.blockers.count) 个阻塞"
    }

    private var artifactIdentityGateStatus: String {
        readiness.artifactIdentityReceipt?.identityVerdict ?? "未记录"
    }

    private var readinessAccessibilityValue: String {
        "\(statusTitle)：\(statusDetail)"
    }

    private var readinessAccessibilityHint: String {
        let gateHint = readinessGateAccessibilityHint
        return switch readiness.nextAction {
        case "stopUntilArtifactsProvided":
            "请提供真实 Koharu 四件套后再运行漫画探针；\(gateHint)；该状态只影响 shadow OCR，不影响普通图片 OCR、翻译或覆盖图"
        case "stopUntilArtifactContractFixed":
            "请先修正四件套契约、坐标或来源身份；\(gateHint)；当前不会进入 shadow OCR"
        case "stopUntilRealDetectorSourceDeclared":
            "请声明真实 detector 或 segmenter 来源；\(gateHint)；fixture 和 proxy 不能作为 active artifact"
        case "continueWithExternalTextBoxesShadowOCR":
            "下一次漫画探针可执行 external TextBoxes shadow OCR；\(gateHint)；结果只写入诊断输出"
        default:
            "Koharu readiness 只用于漫画探针诊断；\(gateHint)；不会修改普通图片 OCR、翻译或覆盖图"
        }
    }

    private var readinessGateAccessibilityHint: String {
        var details: [String] = []
        if isLegacySummaryOnlyArtifact {
            details.append("当前为 v1 summary-only；v2 mask payload 和 topology 尚未要求")
        } else {
            if readiness.maskPayloadGateReady == false {
                details.append("mask payload 尚未通过")
            }
            if readiness.maskTopologyGateReady == false, readiness.maskTopologyReport != nil {
                details.append("mask 拓扑仍需稳定一对一分配和像素分区复核")
            }
        }
        if let receipt = readiness.artifactIdentityReceipt,
           receipt.identityVerdict != "activeArtifactIdentityRecorded" {
            details.append("工件身份为 \(receipt.identityVerdict)，需保留文件哈希并完成 CI 对账")
        }
        if details.isEmpty {
            return "摘要同时显示坐标、mask payload、mask 拓扑和工件身份门控"
        }
        return details.joined(separator: "；") + "。不要把 proxy 或 contract example 当作真实 Koharu 工件"
    }

    private var summary: String {
        let missing = readiness.missingArtifacts.isEmpty ? "none" : readiness.missingArtifacts.joined(separator: ",")
        let parseErrors = readiness.parseErrors.isEmpty ? "none" : readiness.parseErrors.joined(separator: " | ")
        let notes = readiness.notes.isEmpty ? "none" : readiness.notes.joined(separator: " | ")
        let coordinate = readiness.coordinateValidation
        let topology = readiness.maskTopologyReport
        let receipt = readiness.artifactIdentityReceipt
        let optionalBool: (Bool?) -> String = { $0.map(String.init) ?? "n/a" }
        let topologyBlockers = topology?.blockers.isEmpty == false
            ? topology?.blockers.joined(separator: " | ") ?? "none"
            : "none"
        return "source=\(readiness.sourceImage)\nartifactRoot=test/koharu_artifacts\nverdict=\(readiness.readinessVerdict)\nnextAction=\(readiness.nextAction)\nactiveArtifactsDirectory=\(readiness.activeArtifactsDirectory)\ncontractExampleOnly=\(readiness.contractExampleOnly)\nexternalTextBoxesShadowOCRAllowed=\(readiness.externalTextBoxesShadowOCRAllowed)\nmanifestFound=\(readiness.manifestFound)\ntextBoxesFound=\(readiness.textBoxesFound)\nbubbleMaskFound=\(readiness.bubbleMaskFound)\nsegmentMaskFound=\(readiness.segmentMaskFound)\nmissingArtifacts=\(missing)\nparseErrors=\(parseErrors)\ngeneratedBy=\(readiness.generatedBy ?? "n/a")\ntextBoxCount=\(readiness.textBoxCount)\nbubbleInstanceCount=\(readiness.bubbleInstanceCount)\nsegmentGlyphPixelCount=\(readiness.segmentGlyphPixelCount.map(String.init) ?? "n/a")\ncoordinateSchemaVersion=\(coordinate.schemaVersion ?? "n/a")\ncoordinateSpace=\(coordinate.coordinateSpace ?? "n/a")\ncoordinateBboxValidationPassed=\(coordinate.bboxValidationPassed)\nbubbleMaskPayloadVerdict=\(readiness.bubbleMaskPayloadVerdict ?? "n/a")\nsegmentMaskPayloadVerdict=\(readiness.segmentMaskPayloadVerdict ?? "n/a")\nmaskPayloadGateReady=\(optionalBool(readiness.maskPayloadGateReady))\nmaskTopologyGateReady=\(optionalBool(readiness.maskTopologyGateReady))\nmaskTopologyEvaluated=\(optionalBool(topology?.evaluated))\nmaskTopologyVerdict=\(topology?.topologyVerdict ?? "n/a")\nmaskTopologyBlockers=\(topologyBlockers)\nartifactIdentityVerdict=\(receipt?.identityVerdict ?? "n/a")\nartifactIdentityAllRequiredFilesPresent=\(optionalBool(receipt?.allRequiredFilesPresent))\nartifactIdentityAllRequiredFilesHaveSHA256=\(optionalBool(receipt?.allRequiredFilesHaveSHA256))\nsourceImageSHA256Matches=\(optionalBool(receipt?.sourceImageSHA256Matches))\nnotes=\(notes)\nshadowOnly=true\nmainFlowChanged=false"
        return "source=\(readiness.sourceImage)\nartifactRoot=test/koharu_artifacts\nverdict=\(readiness.readinessVerdict)\nnextAction=\(readiness.nextAction)\nactiveArtifactsDirectory=\(readiness.activeArtifactsDirectory)\ncontractExampleOnly=\(readiness.contractExampleOnly)\nexternalTextBoxesShadowOCRAllowed=\(readiness.externalTextBoxesShadowOCRAllowed)\nmanifestFound=\(readiness.manifestFound)\ntextBoxesFound=\(readiness.textBoxesFound)\nbubbleMaskFound=\(readiness.bubbleMaskFound)\nsegmentMaskFound=\(readiness.segmentMaskFound)\nmissingArtifacts=\(missing)\nparseErrors=\(parseErrors)\ngeneratedBy=\(readiness.generatedBy ?? "n/a")\ntextBoxCount=\(readiness.textBoxCount)\nbubbleInstanceCount=\(readiness.bubbleInstanceCount)\nsegmentGlyphPixelCount=\(readiness.segmentGlyphPixelCount.map(String.init) ?? "n/a")\ncoordinateSchemaVersion=\(coordinate.schemaVersion ?? "n/a")\ncoordinateSpace=\(coordinate.coordinateSpace ?? "n/a")\ncoordinateBboxValidationPassed=\(coordinate.bboxValidationPassed)\nbubbleMaskPayloadVerdict=\(readiness.bubbleMaskPayloadVerdict ?? "n/a")\nsegmentMaskPayloadVerdict=\(readiness.segmentMaskPayloadVerdict ?? "n/a")\nmaskPayloadGateReady=\(optionalBool(readiness.maskPayloadGateReady))\nmaskPayloadGateStatus=\(maskPayloadGateStatus)\nmaskTopologyGateReady=\(optionalBool(readiness.maskTopologyGateReady))\nmaskTopologyGateStatus=\(maskTopologyGateStatus)\nmaskTopologyEvaluated=\(optionalBool(topology?.evaluated))\nmaskTopologyVerdict=\(topology?.topologyVerdict ?? "n/a")\nmaskTopologyBlockers=\(topologyBlockers)\nartifactIdentityVerdict=\(receipt?.identityVerdict ?? "n/a")\nartifactIdentityAllRequiredFilesPresent=\(optionalBool(receipt?.allRequiredFilesPresent))\nartifactIdentityAllRequiredFilesHaveSHA256=\(optionalBool(receipt?.allRequiredFilesHaveSHA256))\nsourceImageSHA256Matches=\(optionalBool(receipt?.sourceImageSHA256Matches))\nnotes=\(notes)\nshadowOnly=true\nmainFlowChanged=false"
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
                    Text(block.ocrText).font(.caption).foregroundStyle(Color.appTextSecondary).lineLimit(2)
                }
                Spacer()
                AppStatusLabel(text: block.blockPassed ? "PASS" : "FAIL", tone: block.blockPassed ? .success : .danger)
            }
            .padding(.vertical, AppTheme.Spacing.control)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("漫画探针文字块 \(block.index)")
            .accessibilityValue(blockAccessibilityValue)
            .accessibilityHint(blockAccessibilityHint)
        }
        .overlay(alignment: .bottom) { Divider().overlay(Color.appBorder) }
    }

    private var blockAccessibilityValue: String {
        let ocrText = block.ocrText.isEmpty ? "空" : block.ocrText
        var parts = [
            block.blockPassed ? "通过" : "失败",
            "OCR 原文：\(ocrText)",
            "旋转 \(block.rotationAngleUsed) 度"
        ]
        if let confidence = block.ocrConfidence {
            let percent = Int((Double(min(max(confidence, 0), 1)) * 100).rounded())
            parts.append("OCR 置信度 \(percent)%")
        }
        if let qualityLabel = block.ocrQualityLabel, !qualityLabel.isEmpty {
            parts.append("OCR 质量：\(qualityLabel)")
        }
        if !block.translatedText.isEmpty {
            parts.append("译文：\(block.translatedText)")
        }
        if !block.failureReasons.isEmpty {
            parts.append("失败原因：\(block.failureReasons.joined(separator: "、"))")
        }
        if let translationFailureDetail = block.translationFailureDetail,
           !translationFailureDetail.isEmpty {
            parts.append("翻译失败详情：\(translationFailureDetail)")
        }
        return parts.joined(separator: "；")
    }

    private var blockAccessibilityHint: String {
        block.blockPassed
            ? "展开查看 OCR 原文、译文和诊断输出；此结果只属于漫画探针诊断，不会改变普通图片 OCR、翻译或覆盖图"
            : "展开查看 OCR 原文、翻译失败原因和诊断输出；此结果只属于漫画探针诊断，不会改变普通图片 OCR、翻译或覆盖图"
    }
}

private struct DeveloperCodeBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack {
                Text(title).font(.caption.monospaced().bold()).foregroundStyle(Color.appTextSecondary)
                Spacer()
                ShareLink(item: text) { Label("复制或分享", systemImage: "doc.on.doc").labelStyle(.iconOnly) }
                    .accessibilityLabel("复制或分享 \(title)")
            }
            ScrollView {
                Text(text)
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.appTextPrimary)
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
