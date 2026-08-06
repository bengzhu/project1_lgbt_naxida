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

private enum MangaProbeDiagnosticFilter: String, CaseIterable, Identifiable, Hashable {
    case all = "全部"
    case failures = "失败"
    case ocr = "OCR"
    case translation = "翻译"
    case render = "布局"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .failures: "xmark.octagon"
        case .ocr: "text.viewfinder"
        case .translation: "character.bubble"
        case .render: "rectangle.3.group"
        }
    }

    func matches(_ block: MangaOverlayProbeBlock, report: MangaOverlayProbeReport) -> Bool {
        switch self {
        case .all:
            true
        case .failures:
            !block.blockPassed
        case .ocr:
            mangaProbeOCRRiskBlockSet(report).contains(block.index)
        case .translation:
            mangaProbeTranslationRiskBlockSet(report).contains(block.index)
        case .render:
            mangaProbeRenderRiskBlockSet(report).contains(block.index)
        }
    }
}

// These sets are report-only views of existing probe evidence. They deliberately
// do not select OCR candidates, rerun translation, or mutate the report/store.
private func mangaProbeOCRRiskBlockSet(_ report: MangaOverlayProbeReport) -> Set<Int> {
    var blockIDs = Set(report.diagnostics.likelyOCRIssueBlocks)
    blockIDs.formUnion(report.diagnostics.translationUsableButOCRSuspectBlocks)
    blockIDs.formUnion(report.translationModelFloorComparisonReport?.noisyOCRSuspectBlocks ?? [])
    blockIDs.formUnion(
        report.blocks
            .filter { block in block.failureCategory == "ocrInputSuspect" }
            .map(\.index)
    )
    return blockIDs
}

private func mangaProbeTranslationRiskBlockSet(_ report: MangaOverlayProbeReport) -> Set<Int> {
    var blockIDs = Set(report.diagnostics.translationLanguageQualityFailedBlocks)
    if let modelFloor = report.translationModelFloorComparisonReport {
        blockIDs.formUnion(modelFloor.noisyModelFloorBlocks)
        blockIDs.formUnion(modelFloor.noisyTranslationLanguageQualityBlocks)
    }
    blockIDs.formUnion(
        report.blocks
            .filter { block in
                block.failureCategory == "modelOutputFailure"
                    || block.failureCategory == "translationLanguageQualityFailure"
            }
            .map(\.index)
    )
    return blockIDs
}

private func mangaProbeRenderRiskBlockSet(_ report: MangaOverlayProbeReport) -> Set<Int> {
    var blockIDs = Set(
        report.diagnostics.renderCollisionUnresolvedBlocks
            + report.diagnostics.renderMinFontSizeReachedBlocks
            + report.diagnostics.renderTextTruncatedBlocks
    )
    if let fitPlanner = report.koharuRenderSpriteFitPlannerReport {
        blockIDs.formUnion(fitPlanner.fontBudgetRiskBlocks)
        blockIDs.formUnion(fitPlanner.renderMinFontSizeReachedBlocks)
        blockIDs.formUnion(fitPlanner.spriteContainmentRiskBlocks)
        blockIDs.formUnion(fitPlanner.siblingOverlapRiskBlocks)
        blockIDs.formUnion(fitPlanner.failureOverlayRiskBlocks)
    }
    if let renderLock = report.koharuRenderRegressionLockReport {
        blockIDs.formUnion(renderLock.renderIssueBlocks)
        blockIDs.formUnion(renderLock.renderMinFontSizeReachedBlocks)
        blockIDs.formUnion(renderLock.renderTextTruncatedBlocks)
    }
    return blockIDs
}

private struct MangaProbeBlockReportAction {
    let localizedAction: String
    let source: String
    let diagnosis: String?
    let executionBoundary: String?
    let gateAction: String?
    let convergenceContext: MangaProbeConvergenceContext?

    var summary: String {
        var parts = [localizedAction, "来源：\(source)"]
        if let diagnosis, !diagnosis.isEmpty {
            parts.append("依据：\(diagnosis)")
        }
        if let executionBoundary, !executionBoundary.isEmpty {
            parts.append("执行边界：\(executionBoundary)")
        }
        if let gateAction, !gateAction.isEmpty {
            parts.append("Koharu 工件门：\(gateAction)")
        }
        if let convergenceContext, !convergenceContext.summary.isEmpty {
            parts.append("Koharu 收敛：\(convergenceContext.summary)")
            if convergenceContext.isBlocked {
                parts.append("收敛状态：阻断")
            } else if convergenceContext.isReportOnly {
                parts.append("收敛状态：仅报告")
            }
        }
        return parts.joined(separator: "；")
    }
}

private func mangaProbeBlockReportAction(
    _ report: MangaOverlayProbeReport,
    blockIndex: Int
) -> MangaProbeBlockReportAction? {
    let internalSummary = report.internalStructureBottleneckReport?.blockSummaries.first {
        $0.blockIndex == blockIndex
    }
    let floorSummary = report.translationModelFloorComparisonReport?.noisyBlockSummaries.first {
        $0.blockIndex == blockIndex
    }
    let renderLedger = report.koharuRenderSpriteFitPlannerReport?.blockLedgers.first {
        $0.blockIndex == blockIndex
    }
    let artifactTrace = report.koharuArtifactDAGReport?.blockTraces.first {
        $0.blockIndex == blockIndex
    }

    let primary: (action: String, source: String)? = {
        if let action = internalSummary?.recommendedNextAction, !action.isEmpty, action != "noActionPassed" {
            return (action, "内部结构瓶颈")
        }
        if let action = floorSummary?.recommendedNextAction, !action.isEmpty, action != "noActionPassed" {
            return (action, "模型底线对照")
        }
        if let action = renderLedger?.nextAction, !action.isEmpty, action != "manualReviewOnly" {
            return (action, "覆盖布局规划")
        }
        if let action = artifactTrace?.recommendedNextAction, !action.isEmpty {
            return (action, "Koharu 工件 DAG")
        }
        return nil
    }()

    let gateAction = artifactTrace.map { mangaProbeActionLabel($0.recommendedNextAction) }
    let gateDiagnosis: String? = artifactTrace.flatMap { trace in
        guard !trace.firstBlockingStage.isEmpty || !trace.firstBlockingReason.isEmpty else {
            return nil
        }
        let stage = mangaProbeDiagnosisLabel(trace.firstBlockingStage)
        let reason = mangaProbeDiagnosisLabel(trace.firstBlockingReason)
        if stage.isEmpty { return reason.isEmpty ? nil : reason }
        if reason.isEmpty { return stage }
        return "\(stage)：\(reason)"
    }
    let primaryDiagnosis: String? = {
        if let internalSummary {
            return mangaProbeDiagnosisSummary(
                [internalSummary.primaryBottleneck] + internalSummary.secondaryBottlenecks
            )
        }
        if let floorSummary {
            var labels: [String] = []
            if let primary = floorSummary.primaryBottleneckFromConvergence {
                labels.append(primary)
            }
            if floorSummary.modelFloorLimited {
                labels.append("modelFloorLimited")
            }
            if floorSummary.ocrInputSuspect {
                labels.append("ocrInputSuspect")
            }
            if floorSummary.translationLanguageQualityFailure {
                labels.append("translationLanguageQualityFailure")
            }
            return mangaProbeDiagnosisSummary(labels)
        }
        if let renderLedger {
            return mangaProbeDiagnosisSummary([
                renderLedger.primaryRenderBottleneck,
                renderLedger.fitVerdict,
                renderLedger.fontBudgetVerdict
            ])
        }
        return nil
    }()
    let diagnosis = [primaryDiagnosis, gateDiagnosis]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "；")
    let executionBoundary = mangaProbeBlockExecutionBoundary(report, blockIndex: blockIndex)
    let convergenceContext = mangaProbeConvergenceContext(report, blockIndex: blockIndex)
    guard let primary, primary.action != "noActionPassed" else {
        guard (gateAction?.isEmpty == false) || executionBoundary != nil || convergenceContext != nil else {
            return nil
        }
        return MangaProbeBlockReportAction(
            localizedAction: convergenceContext?.nextAction ?? "暂无块级改动",
            source: convergenceContext == nil ? "报告汇总" : "Koharu 收敛",
            diagnosis: diagnosis.isEmpty ? nil : diagnosis,
            executionBoundary: executionBoundary,
            gateAction: gateAction,
            convergenceContext: convergenceContext
        )
    }
    return MangaProbeBlockReportAction(
        localizedAction: mangaProbeActionLabel(primary.action),
        source: primary.source,
        diagnosis: diagnosis.isEmpty ? nil : diagnosis,
        executionBoundary: executionBoundary,
        gateAction: gateAction,
        convergenceContext: convergenceContext
    )
}

private func mangaProbeBlockExecutionBoundary(
    _ report: MangaOverlayProbeReport,
    blockIndex: Int
) -> String? {
    let resolverTrace = report.koharuPipelineResolverReport?.blockTraces.first {
        $0.blockIndex == blockIndex
    }
    let workOrderRoute = report.koharuWorkOrderRouterReport?.blockRoutes.first {
        $0.blockIndex == blockIndex
    }
    let artifactRequest = report.koharuExternalArtifactRequestPacketReport?.blockRequests.first {
        $0.blockIndex == blockIndex
    }
    let nativeReplayRoute = report.koharuNativeAlgorithmReplayMatrixReport?.blockRoutes.first {
        $0.blockIndex == blockIndex
    }

    var parts: [String] = []
    func append(_ value: String) {
        guard !value.isEmpty, !parts.contains(value) else { return }
        parts.append(value)
    }
    func runBoundary(
        canRunInCIFast: Bool,
        requiresFullProbe: Bool,
        requiresExternalArtifact: Bool
    ) -> String {
        if requiresExternalArtifact { return "等待真实外部工件" }
        if requiresFullProbe { return "需 full probe" }
        if canRunInCIFast { return "可 CI-fast" }
        return "当前不可执行"
    }

    if let trace = resolverTrace {
        if !trace.recommendedExecutionItemID.isEmpty {
            append("执行项 \(trace.recommendedExecutionItemID)")
            if let item = report.koharuPipelineResolverReport?.executionQueue.first(where: {
                $0.executionItemID == trace.recommendedExecutionItemID
            }) {
                if !item.title.isEmpty { append("目标 \(item.title)") }
                if !item.status.isEmpty { append("状态 \(item.status)") }
            }
        }
        if !trace.firstBlockedStage.isEmpty {
            append("首阻断阶段 \(mangaProbeDiagnosisLabel(trace.firstBlockedStage))")
        }
        if !trace.firstBlockedReason.isEmpty {
            append("阻断原因 \(mangaProbeDiagnosisLabel(trace.firstBlockedReason))")
        }
        append(runBoundary(
            canRunInCIFast: trace.canRunInCIFast,
            requiresFullProbe: trace.requiresFullProbe,
            requiresExternalArtifact: trace.requiresExternalArtifact
        ))
    }

    if let route = workOrderRoute {
        if !route.primaryWorkOrderID.isEmpty {
            append("工单 \(route.primaryWorkOrderID)")
            if let workOrder = report.koharuWorkOrderRouterReport?.workOrders.first(where: {
                $0.workOrderID == route.primaryWorkOrderID
            }) {
                if !workOrder.title.isEmpty { append("工单目标 \(workOrder.title)") }
                if !workOrder.targetStage.isEmpty { append("目标阶段 \(workOrder.targetStage)") }
                if !workOrder.targetKoharuArtifact.isEmpty { append("目标工件 \(workOrder.targetKoharuArtifact)") }
                if !workOrder.budgetClass.isEmpty { append("预算 \(workOrder.budgetClass)") }
                if !workOrder.remainingBlockers.isEmpty {
                    append("剩余阻塞 \(workOrder.remainingBlockers.joined(separator: "、"))")
                }
                if !workOrder.allowedInThisVersion {
                    append("本版本禁止升级")
                }
            }
        }
        if !route.primaryBottleneck.isEmpty {
            append("工单瓶颈 \(mangaProbeDiagnosisLabel(route.primaryBottleneck))")
        }
        append(runBoundary(
            canRunInCIFast: route.canRunInCIFast,
            requiresFullProbe: route.requiresFullProbe,
            requiresExternalArtifact: route.requiresExternalArtifact
        ))
        if !route.mustNotPromoteReasons.isEmpty {
            append("禁止晋级：\(route.mustNotPromoteReasons.joined(separator: "、"))")
        }
    }

    if let request = artifactRequest {
        let requiredArtifacts = [
            request.needsTextBoxes ? "TextBoxes" : nil,
            request.needsBubbleMask ? "BubbleMask" : nil,
            request.needsSegmentMask ? "SegmentMask" : nil
        ].compactMap { $0 }
        if !requiredArtifacts.isEmpty {
            append("需要真实 \(requiredArtifacts.joined(separator: "/"))")
        }
        if !request.externalArtifactReadinessVerdict.isEmpty {
            append("工件就绪 \(mangaProbeDiagnosisLabel(request.externalArtifactReadinessVerdict))")
        }
        if !request.missingRealArtifactReasons.isEmpty {
            append("工件阻塞：\(request.missingRealArtifactReasons.joined(separator: "、"))")
        }
        if !request.forbiddenLocalActions.isEmpty {
            append("禁止本地调参：\(request.forbiddenLocalActions.joined(separator: "、"))")
        }
    }

    if let replay = nativeReplayRoute {
        if !replay.primaryKoharuStage.isEmpty {
            append("回放阶段 \(replay.primaryKoharuStage)")
        }
        if !replay.primaryReplayCandidateID.isEmpty {
            append("回放候选 \(replay.primaryReplayCandidateID)")
        }
        if replay.nativeReplayAllowed {
            append("可本地回放")
        } else if replay.shadowOnlyAllowed {
            append("仅 shadow 回放")
        } else {
            append("回放不可执行")
        }
        if replay.requiresExternalArtifact {
            append("回放等待外部工件")
        }
    }

    return parts.isEmpty ? nil : parts.joined(separator: "；")
}

private func mangaProbeDiagnosisSummary(_ rawLabels: [String]) -> String? {
    var seen = Set<String>()
    let labels = rawLabels
        .filter { !$0.isEmpty }
        .map(mangaProbeDiagnosisLabel)
        .filter { seen.insert($0).inserted }
    return labels.isEmpty ? nil : labels.joined(separator: "、")
}

private func mangaProbeDiagnosisLabel(_ label: String) -> String {
    return switch label {
    case "modelTranslationQuality": "模型翻译质量"
    case "ocrCharacterDamage": "OCR 字符损伤"
    case "bubbleAssignmentOrSplit": "气泡拆分或归属"
    case "externalArtifactOptionalMissing": "可选外部工件缺失"
    case "bubbleMask": "气泡 mask"
    case "currentSpriteFits": "当前覆盖 sprite 已适配"
    case "fontBudgetTight": "字号预算紧张"
    case "renderOnly": "仅覆盖布局"
    case "seamConstrainedSafeArea": "气泡边界限制"
    case "noneRenderLocked": "当前无渲染锁"
    case "passed": "已通过"
    case "modelFloorLimited": "模型底线受限"
    case "ocrInputSuspect": "OCR 输入疑似"
    case "translationLanguageQualityFailure": "翻译语言质量风险"
    case "textBoxes": "文本框阶段"
    case "manifestMissing": "manifest 缺失"
    case "bubbleMaskMissing": "BubbleMask 缺失"
    case "segmentMaskMissing": "SegmentMask 缺失"
    case "bubbleMaskNotReady": "BubbleMask 未就绪"
    case "segmentMaskNotReady": "SegmentMask 未就绪"
    default: label
    }
}

private func mangaProbeActionLabel(_ action: String) -> String {
    return switch action {
    case "tryPromptOrModelComparison": "比较提示词或模型（仅诊断）"
    case "improveTextBoxOrSegmentEvidence": "优先补充文本框或 segment 证据"
    case "improveBubbleSplitOrAssignment": "优先复核气泡拆分或归属"
    case "classifyCurrentModelFloorBeforeOCRTuning": "先确认模型底线，再调 OCR"
    case "keepOCRInputSuspectSeparateFromModelFloor": "保持 OCR 疑似与模型底线分开"
    case "keepRenderSpriteFitPlannerReportOnly": "保留覆盖布局报告（仅诊断）"
    case "routeToRenderRegressionLock": "转入覆盖回归锁（仅诊断）"
    case "routeToTranslationModelFloorComparison": "转入翻译模型底线对照（仅诊断）"
    case "collectRealKoharuArtifact": "收集真实 Koharu 工件"
    case "stopLocalCropLineDeskewTuning": "停止本地裁剪、逐行和去倾斜调参"
    case "keepReportOnly": "保留 report-only"
    case "manualReviewOnly": "人工复核当前块"
    case "provideRealKoharuArtifact": "提供真实 Koharu 工件"
    case "noActionPassed": "无需块级改动"
    default: action
    }
}

private struct MangaProbePromotionBoundaryContext {
    let summary: String
    let nextAction: String
    let isBlocked: Bool
    let isReportOnly: Bool
}

private func mangaProbePromotionBoundaryLabel(_ value: String) -> String {
    return switch value {
    case "blockedByMissingActiveArtifacts": "缺少 active 工件"
    case "blockedByMissingAppSideArtifactIdentity": "缺少 App 侧身份回执"
    case "dryRunPreviewsBlockedByContract": "dry-run 预览未满足契约"
    case "activeArtifactsReadyForShadowOCR": "active 工件可进入 shadow OCR"
    case "blockedByMissingRealArtifact": "缺少真实 Koharu 工件"
    case "blockedByProxyEvidence": "仅有 proxy 证据"
    case "blockedByModelFloor": "模型底线阻断"
    case "blockedByRenderLock": "覆盖布局锁定"
    case "shadowReviewEligible": "可 shadow 复核"
    case "reportOnlyStable": "report-only 稳定"
    case "manifestMissing": "manifest 缺失"
    case "artifactFilesMissing": "四件套文件缺失"
    default: value
    }
}

private func mangaProbePromotionBoundary(
    _ report: MangaOverlayProbeReport
) -> MangaProbePromotionBoundaryContext? {
    let promotion = report.koharuNativePromotionGateLiteReport
    let contract = report.koharuNativeArtifactContractDryRunReport
    let identity = report.koharuArtifactIdentityReconciliationReport
    let convergence = report.koharuArtifactConvergenceReport
    guard promotion != nil || contract != nil || identity != nil || convergence != nil else {
        return nil
    }

    var parts: [String] = []
    var blocked = false
    var reportOnly = false
    var nextAction: String?

    func append(_ value: String) {
        guard !value.isEmpty, !parts.contains(value) else { return }
        parts.append(value)
    }

    if let promotion {
        if !promotion.promotionVerdict.isEmpty {
            append("native 晋级：\(mangaProbePromotionBoundaryLabel(promotion.promotionVerdict))")
        }
        reportOnly = promotion.nativePromotionPreviewOnly || promotion.diagnosticOnly
        if promotion.nativePromotionPreviewOnly {
            append("仅候选预览")
        }
        if !promotion.diagnosticOnly || promotion.wouldChangeMainFlow {
            blocked = true
            append("报告边界异常")
        }
        let realArtifactBlocks = Set(
            promotion.needsRealTextBoxesBlocks
                + promotion.needsRealBubbleMaskBlocks
                + promotion.needsRealSegmentMaskBlocks
        )
        if !realArtifactBlocks.isEmpty {
            blocked = true
            append("需真实工件 \(realArtifactBlocks.count) 块")
            nextAction = "提供真实 Koharu 四件套，再进行 CI 身份对账"
        }
        if !promotion.stopLocalTuningBlocks.isEmpty {
            append("停止本地调参 \(promotion.stopLocalTuningBlocks.count) 块")
            nextAction = nextAction ?? "停止本地几何调参，先处理模型底线或覆盖布局门"
        }
        if let action = promotion.gateLedger.first(where: { $0.status != "passed" })?.recommendedAction,
           !action.isEmpty {
            append("门控下一步：\(mangaProbePromotionBoundaryLabel(action))")
            nextAction = nextAction ?? action
        }
        if promotion.promotionVerdict.hasPrefix("blocked") {
            blocked = true
        }
    }

    if let contract {
        if !contract.contractDryRunVerdict.isEmpty {
            append("契约 dry-run：\(mangaProbePromotionBoundaryLabel(contract.contractDryRunVerdict))")
        }
        if contract.dryRunOnly || !contract.activeExportAllowed {
            reportOnly = true
            append("禁止 active export")
        }
        if !contract.diagnosticOnly || contract.wouldChangeMainFlow {
            blocked = true
            append("契约报告边界异常")
        }
        if !contract.blockedPreviewIDs.isEmpty {
            blocked = true
            append("契约阻塞预览 \(contract.blockedPreviewIDs.count) 个")
            nextAction = nextAction ?? "先补齐预览必需字段并保留 dry-run"
        }
        if contract.readinessVerdict != "readyForShadowOCR" {
            blocked = true
            append("shadow OCR 就绪：\(mangaProbePromotionBoundaryLabel(contract.readinessVerdict))")
            nextAction = nextAction ?? "提供并校验真实四件套后再进入 shadow OCR"
        }
    }

    if let identity {
        if !identity.identityReconciliationVerdict.isEmpty {
            append("身份对账：\(mangaProbePromotionBoundaryLabel(identity.identityReconciliationVerdict))")
        }
        if identity.dryRunOnly || !identity.activeExportAllowed {
            reportOnly = true
            append("身份仅 dry-run")
        }
        if !identity.readyForCIManifestComparison || identity.manualCIComparisonRequired {
            blocked = true
            append("需 CI manifest 身份对账")
            nextAction = nextAction ?? "比较 App receipt 与 CI manifest 的文件大小和 SHA256"
        }
        if !identity.hashMissingFileKinds.isEmpty {
            blocked = true
            append("缺少 SHA256：\(identity.hashMissingFileKinds.joined(separator: "、"))")
        }
    }

    if let convergence {
        if convergence.diagnosticOnly || !convergence.wouldChangeMainFlow {
            reportOnly = true
            append("收敛报告仅诊断")
        }
        if !convergence.openWorkItems.isEmpty {
            reportOnly = true
            let visibleWorkItems = convergence.openWorkItems.prefix(3).joined(separator: "、")
            let suffix = convergence.openWorkItems.count > 3
                ? " 等 \(convergence.openWorkItems.count) 个"
                : ""
            append("未闭环工单：\(visibleWorkItems)\(suffix)")
            if let workItem = convergence.workItemLedger.first(where: {
                convergence.openWorkItems.contains($0.workItemID) && !$0.nextAction.isEmpty
            }) {
                nextAction = nextAction ?? mangaProbeActionLabel(workItem.nextAction)
            }
        }
        if !convergence.stopWorkItems.isEmpty {
            blocked = true
            append("停止工单 \(convergence.stopWorkItems.count) 个")
            nextAction = nextAction ?? "按 convergence work item 停止被禁止的本地调参"
        }
        if !convergence.needsRealArtifactBlocks.isEmpty {
            blocked = true
            append("convergence 等待真实工件 \(convergence.needsRealArtifactBlocks.count) 块")
            nextAction = nextAction ?? "完成真实工件交付并重新生成只读报告"
        }
    }

    let action = nextAction ?? "保持 report-only；等待真实工件与 CI 身份对账"
    return MangaProbePromotionBoundaryContext(
        summary: parts.isEmpty ? "未提供晋级边界详情" : parts.joined(separator: "；"),
        nextAction: action,
        isBlocked: blocked,
        isReportOnly: reportOnly
    )
}

private struct MangaProbeConvergenceContext {
    let summary: String
    let nextAction: String?
    let isBlocked: Bool
    let isReportOnly: Bool
}

private func mangaProbeConvergenceArtifactLabel(_ value: String) -> String {
    switch value {
    case "TextBoxes": "TextBoxes"
    case "BubbleMask": "BubbleMask"
    case "SegmentMask": "SegmentMask"
    case "OcrText": "OCR 文本"
    case "Translations": "翻译"
    case "FinalRender": "最终覆盖"
    case "RenderedSprites": "覆盖 sprite"
    case "ExternalArtifacts": "真实外部工件"
    case "none": "无首阻断"
    default: value
    }
}

private func mangaProbeConvergenceStatusLabel(_ value: String) -> String {
    switch value {
    case "open": "未闭环"
    case "blocked": "已阻断"
    case "stop": "要求停止本地调参"
    case "closed", "passed": "已闭环"
    case "closedReportOnly": "仅报告已闭环"
    default: value
    }
}

private func mangaProbeConvergenceWorkItemIsClosed(_ status: String) -> Bool {
    status == "passed" || status.hasPrefix("closed")
}

private func mangaProbeConvergenceContext(
    _ report: MangaOverlayProbeReport,
    blockIndex: Int
) -> MangaProbeConvergenceContext? {
    guard let convergence = report.koharuArtifactConvergenceReport else { return nil }

    let path = convergence.blockPaths.first { $0.blockIndex == blockIndex }
    let workItems = convergence.workItemLedger.filter { $0.targetBlocks.contains(blockIndex) }
    guard path != nil || !workItems.isEmpty else { return nil }

    var parts: [String] = []
    var nextAction: String?
    func append(_ value: String) {
        guard !value.isEmpty, !parts.contains(value) else { return }
        parts.append(value)
    }

    if let path {
        if !path.firstBlockingArtifact.isEmpty,
           path.firstBlockingArtifact != "none" {
            append("首阻断：" + mangaProbeConvergenceArtifactLabel(path.firstBlockingArtifact))
        }
        if !path.primaryStructuralBottleneck.isEmpty,
           path.primaryStructuralBottleneck != "none" {
            append("结构瓶颈：" + mangaProbeDiagnosisLabel(path.primaryStructuralBottleneck))
        }
        if path.needsRealArtifact {
            append("等待真实工件")
        }
        if !path.primaryNextAction.isEmpty {
            let action = mangaProbeActionLabel(path.primaryNextAction)
            append("收敛动作：" + action)
            nextAction = action
        }
    }

    let openWorkItemIDs = {
        var ids = path?.openWorkItems ?? []
        ids.append(contentsOf: workItems.filter {
            !mangaProbeConvergenceWorkItemIsClosed($0.status)
        }.map(\.workItemID))
        var seen = Set<String>()
        return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }()
    if !openWorkItemIDs.isEmpty {
        let visibleIDs = openWorkItemIDs.prefix(3).joined(separator: "、")
        let suffix = openWorkItemIDs.count > 3 ? " 等 " + String(openWorkItemIDs.count) + " 个" : ""
        append("开放工单：" + visibleIDs + suffix)
    }

    let activeWorkItems = workItems.filter { openWorkItemIDs.contains($0.workItemID) }
    for item in activeWorkItems.prefix(2) {
        append("工单 " + item.workItemID + "：" + mangaProbeConvergenceStatusLabel(item.status))
    }

    if activeWorkItems.contains(where: { $0.requiresExternalArtifact }) {
        append("执行边界：等待真实外部工件")
    } else if activeWorkItems.contains(where: { $0.requiresFullProbe }) {
        append("执行边界：需 full probe")
    } else if activeWorkItems.contains(where: { $0.canRunInCIFast }) {
        append("执行边界：可 CI-fast")
    } else if !activeWorkItems.isEmpty {
        append("执行边界：当前不可执行")
    }

    if nextAction == nil,
       let item = activeWorkItems.first(where: { !$0.nextAction.isEmpty }) {
        nextAction = mangaProbeActionLabel(item.nextAction)
    }

    let wouldChangeMainFlow = path?.wouldChangeMainFlow ?? convergence.wouldChangeMainFlow
    if wouldChangeMainFlow {
        append("报告边界异常")
    }
    let isBlocked = wouldChangeMainFlow
        || path?.needsRealArtifact == true
        || path.map { !$0.firstBlockingArtifact.isEmpty && $0.firstBlockingArtifact != "none" } == true
        || activeWorkItems.contains {
            !$0.remainingBlockers.isEmpty
                || $0.requiresExternalArtifact
                || $0.status == "blocked"
                || $0.status == "stop"
        }
    let isReportOnly = convergence.diagnosticOnly || path?.diagnosticOnly == true
    return MangaProbeConvergenceContext(
        summary: parts.isEmpty ? "无额外收敛详情" : parts.joined(separator: "；"),
        nextAction: nextAction,
        isBlocked: isBlocked,
        isReportOnly: isReportOnly
    )
}

private struct MangaProbeConvergenceOverview {
    let summary: String
    let nextAction: String?
    let isBlocked: Bool
    let isReportOnly: Bool
}

private func mangaProbeConvergenceOverview(
    _ report: MangaOverlayProbeReport
) -> MangaProbeConvergenceOverview? {
    guard let convergence = report.koharuArtifactConvergenceReport else { return nil }

    let openWorkItems = Array(Set(convergence.openWorkItems)).filter { !$0.isEmpty }.sorted()
    let closedWorkItems = Array(Set(convergence.closedWorkItems)).filter { !$0.isEmpty }.sorted()
    let stopWorkItems = Array(Set(convergence.stopWorkItems)).filter { !$0.isEmpty }.sorted()
    let statusBreakdown = convergence.workItemStatusBreakdown
        .filter { !$0.key.isEmpty && $0.value > 0 }
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: ",")
    var parts: [String] = []
    func append(_ value: String) {
        guard !value.isEmpty, !parts.contains(value) else { return }
        parts.append(value)
    }

    append("工单：开放 \(openWorkItems.count) / 已闭环 \(closedWorkItems.count)")
    if !stopWorkItems.isEmpty {
        append("要求停止 \(stopWorkItems.count)")
    }
    if convergence.blockPathCount > 0 {
        append("block path \(convergence.blockPathCount)")
    }
    if convergence.workItemLedgerCount > 0 {
        append("工单 ledger \(convergence.workItemLedgerCount)")
    }
    if convergence.externalArtifactsRequiredForThisReport {
        append("需要真实外部工件")
    }
    if !statusBreakdown.isEmpty {
        append("状态：" + statusBreakdown)
    }
    if !openWorkItems.isEmpty {
        let visibleIDs = openWorkItems.prefix(3).joined(separator: "、")
        let suffix = openWorkItems.count > 3 ? " 等 \(openWorkItems.count) 个" : ""
        append("开放：" + visibleIDs + suffix)
    }

    let nextAction = convergence.workItemLedger
        .first { openWorkItems.contains($0.workItemID) && !$0.nextAction.isEmpty }
        .map { mangaProbeActionLabel($0.nextAction) }
    let activeWorkItems = convergence.workItemLedger.filter {
        openWorkItems.contains($0.workItemID)
            || !mangaProbeConvergenceWorkItemIsClosed($0.status)
    }
    let hasBlocker = !convergence.needsRealArtifactBlocks.isEmpty
        || !stopWorkItems.isEmpty
        || convergence.wouldChangeMainFlow
        || activeWorkItems.contains {
            !$0.remainingBlockers.isEmpty
                || $0.requiresExternalArtifact
                || $0.status == "blocked"
                || $0.status == "stop"
        }
    return MangaProbeConvergenceOverview(
        summary: parts.joined(separator: "；"),
        nextAction: nextAction,
        isBlocked: hasBlocker,
        isReportOnly: convergence.diagnosticOnly || !convergence.wouldChangeMainFlow || !openWorkItems.isEmpty
    )
}

private struct MangaProbeDiagnosticFilterControl: View {
    let report: MangaOverlayProbeReport
    let blocks: [MangaOverlayProbeBlock]
    @Binding var selection: MangaProbeDiagnosticFilter

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Picker("漫画探针诊断筛选", selection: $selection) {
                ForEach(MangaProbeDiagnosticFilter.allCases) { filter in
                    Text(filterTitle(filter)).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Menu {
                ForEach(MangaProbeDiagnosticFilter.allCases) { filter in
                    Button {
                        selection = filter
                    } label: {
                        Label(filterTitle(filter), systemImage: filter.systemImage)
                    }
                }
            } label: {
                Label("诊断筛选：\(selection.rawValue)", systemImage: selection.systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: AppTheme.Layout.minimumTarget)
            }
        }
        .accessibilityLabel("漫画探针诊断筛选")
        .accessibilityValue(
            "当前：\(selection.rawValue)，显示 \(selectedBlockCount) 个，共 \(blocks.count) 个文字块"
        )
        .accessibilityHint("只筛选下方逐块诊断结果，不修改 probe_report、普通图片 OCR、翻译或覆盖图")
    }

    private var selectedBlockCount: Int {
        blocks.count(where: { selection.matches($0, report: report) })
    }

    private func filterTitle(_ filter: MangaProbeDiagnosticFilter) -> String {
        "\(filter.rawValue) \(blocks.count(where: { filter.matches($0, report: report) }))"
    }
}

private struct MangaProbeSection: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var diagnosticFilter: MangaProbeDiagnosticFilter = .all
    @State private var diagnosticExpansionResetID = 0
    @State private var diagnosticAccessibilityFocusRequestID = 0
    @AccessibilityFocusState private var diagnosticAccessibilityFocusID: String?
    private static let diagnosticProbeEmptyAccessibilityFocusID = "manga-diagnostic-probe-empty"
    private static let diagnosticFilterEmptyAccessibilityFocusID = "manga-diagnostic-filter-empty"
    private static let diagnosticKoharuReadinessAccessibilityFocusID = "manga-diagnostic-koharu-readiness"

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
                    MangaKoharuArtifactReadinessSummary(
                        readiness: readiness,
                        accessibilityFocus: $diagnosticAccessibilityFocusID,
                        accessibilityFocusID: Self.diagnosticKoharuReadinessAccessibilityFocusID
                    )
                }
                MangaProbeDiagnosticTriageSummary(report: report)

                if store.mangaOverlayProbeBlocks.isEmpty {
                    AppStatusRow(
                        title: "未生成逐块诊断",
                        detail: emptyProbeBlocksDetail,
                        tone: .warning
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("漫画探针未生成逐块诊断")
                    .accessibilityValue(emptyProbeBlocksDetail)
                    .accessibilityHint("请查看上方探针状态和 warnings，确认 test/1.png 与 Output 状态后重试")
                    .accessibilityFocused(
                        $diagnosticAccessibilityFocusID,
                        equals: Self.diagnosticProbeEmptyAccessibilityFocusID
                    )
                } else {
                    MangaProbeDiagnosticFilterControl(
                        report: report,
                        blocks: store.mangaOverlayProbeBlocks,
                        selection: $diagnosticFilter
                    )

                    AppStatusRow(
                        title: "逐块诊断结果：\(diagnosticFilter.rawValue)",
                        detail: "显示 \(filteredProbeBlocks.count) / \(store.mangaOverlayProbeBlocks.count) 个文字块",
                        tone: filteredProbeBlocks.isEmpty ? .warning : .neutral
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("漫画探针逐块诊断结果")
                    .accessibilityValue("筛选为 \(diagnosticFilter.rawValue)，显示 \(filteredProbeBlocks.count) 个，共 \(store.mangaOverlayProbeBlocks.count) 个文字块")
                    .accessibilityHint("切换上方诊断筛选可聚焦 OCR、翻译、布局或失败 block")
                }
            }

            if store.mangaOverlayProbeReport != nil, store.mangaOverlayProbeBlocks.isEmpty {
                AppEmptyState(
                    title: "本次探针未生成文字块",
                    detail: emptyProbeBlocksDetail,
                    systemImage: "exclamationmark.triangle"
                )
            } else if store.mangaOverlayProbeReport != nil, filteredProbeBlocks.isEmpty {
                VStack(spacing: AppTheme.Spacing.control) {
                    AppEmptyState(
                        title: "当前诊断筛选没有结果",
                        detail: "切换到全部或其他诊断类别查看逐块报告。",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("当前漫画诊断筛选没有结果")
                    .accessibilityValue(
                        "筛选为 \(diagnosticFilter.rawValue)，显示 0 个，共 \(store.mangaOverlayProbeBlocks.count) 个文字块；切换到全部或其他诊断类别查看逐块报告"
                    )
                    .accessibilityHint("使用上方漫画探针诊断筛选恢复逐块结果；也可在此执行“显示全部诊断”")
                    .accessibilityAction(named: "显示全部诊断") {
                        showAllDiagnosticResults()
                    }
                    .accessibilityFocused(
                        $diagnosticAccessibilityFocusID,
                        equals: Self.diagnosticFilterEmptyAccessibilityFocusID
                    )

                    AppSecondaryButton(
                        title: "显示全部诊断",
                        systemImage: "list.bullet",
                        action: showAllDiagnosticResults
                    )
                    .accessibilityHint("切换到全部诊断，查看本次探针的所有文字块")
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredProbeBlocks) { block in
                        MangaProbeBlockRow(block: block, report: store.mangaOverlayProbeReport,
                            accessibilityFocus: $diagnosticAccessibilityFocusID,
                            accessibilityFocusID: diagnosticBlockAccessibilityFocusID(block.index),
                            expansionResetID: diagnosticExpansionResetID,
                            requestAccessibilityFocus: { focusID in
                                moveDiagnosticAccessibilityFocus(to: focusID)
                            }
                        )
                    }
                }
            }
        }
        .appSurface()
        .onChange(of: store.mangaOverlayProbeState) { _, state in
            guard state == .loading else { return }
            diagnosticFilter = .all
            diagnosticExpansionResetID += 1
            diagnosticAccessibilityFocusRequestID &+= 1
            diagnosticAccessibilityFocusID = nil
        }
        .onChange(of: diagnosticFilter) { _, _ in
            diagnosticExpansionResetID += 1
            focusDiagnosticFilterResultIfNeeded()
        }
        .onChange(of: store.mangaOverlayProbeReport) { _, report in
            guard report != nil else { return }
            focusDiagnosticProbeResultIfNeeded()
        }
    }

    private var filteredProbeBlocks: [MangaOverlayProbeBlock] {
        guard let report = store.mangaOverlayProbeReport else {
            return store.mangaOverlayProbeBlocks
        }
        return store.mangaOverlayProbeBlocks.filter { diagnosticFilter.matches($0, report: report) }
    }

    private func showAllDiagnosticResults() {
        guard diagnosticFilter != .all else { return }
        diagnosticFilter = .all
    }

    private func focusEmptyDiagnosticStateIfNeeded() {
        guard store.mangaOverlayProbeReport != nil,
              !store.mangaOverlayProbeBlocks.isEmpty,
              filteredProbeBlocks.isEmpty else { return }
        moveDiagnosticAccessibilityFocus(to: Self.diagnosticFilterEmptyAccessibilityFocusID)
    }

    private func focusDiagnosticFilterResultIfNeeded() {
        guard store.mangaOverlayProbeReport != nil,
              !filteredProbeBlocks.isEmpty else {
            focusEmptyDiagnosticStateIfNeeded()
            return
        }
        let focusID = diagnosticBlockAccessibilityFocusID(filteredProbeBlocks[0].index)
        moveDiagnosticAccessibilityFocus(to: focusID)
    }

    private func focusDiagnosticProbeResultIfNeeded() {
        let focusID: String
        if let readiness = store.mangaOverlayProbeReport?.externalArtifactReadinessReport,
           diagnosticReadinessIsBlocking(readiness) {
            focusID = Self.diagnosticKoharuReadinessAccessibilityFocusID
        } else if store.mangaOverlayProbeBlocks.isEmpty {
            focusID = Self.diagnosticProbeEmptyAccessibilityFocusID
        } else if let firstBlock = filteredProbeBlocks.first {
            focusID = diagnosticBlockAccessibilityFocusID(firstBlock.index)
        } else {
            focusID = Self.diagnosticFilterEmptyAccessibilityFocusID
        }
        moveDiagnosticAccessibilityFocus(to: focusID)
    }

    private func diagnosticReadinessIsBlocking(
        _ readiness: MangaOverlayExternalArtifactReadinessReport
    ) -> Bool {
        switch readiness.nextAction {
        case "stopUntilArtifactsProvided",
             "stopUntilArtifactContractFixed",
             "stopUntilRealDetectorSourceDeclared":
            true
        default:
            false
        }
    }

    private func moveDiagnosticAccessibilityFocus(to focusID: String?) {
        diagnosticAccessibilityFocusRequestID &+= 1
        let requestID = diagnosticAccessibilityFocusRequestID
        Task { @MainActor in
            await Task.yield()
            guard requestID == diagnosticAccessibilityFocusRequestID else { return }
            diagnosticAccessibilityFocusID = focusID
        }
    }

    private func diagnosticBlockAccessibilityFocusID(_ blockIndex: Int) -> String {
        "manga-diagnostic-block-\(blockIndex)"
    }

    private var emptyProbeBlocksDetail: String {
        let message = store.mangaOverlayProbeMessage.isEmpty
            ? "探针没有生成可展示的 OCR 文字块。"
            : store.mangaOverlayProbeMessage
        return "\(message) 请确认 bundle 的 test/1.png 和 Output 清理状态后重试。"
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

private struct MangaProbeDiagnosticTriageSummary: View {
    let report: MangaOverlayProbeReport

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
            AppStatusRow(title: statusTitle, detail: statusDetail, tone: statusTone)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("漫画探针诊断分流")
                .accessibilityValue(accessibilityValue)
                .accessibilityHint("这是只读的漫画探针诊断分流；可展开下方摘要查看 OCR、翻译模型、覆盖布局、晋级边界和真实 Koharu 工件的下一步，不会修改普通图片 OCR、翻译 prompt、模型或覆盖图")
            DeveloperCodeBlock(title: "diagnostic triage", text: summary)
        }
        .padding(.top, AppTheme.Spacing.control)
    }

    private var modelFloor: MangaTranslationModelFloorComparisonReport? {
        report.translationModelFloorComparisonReport
    }

    private var ocrBlocks: Set<Int> {
        mangaProbeOCRRiskBlockSet(report)
    }

    private var translationBlocks: Set<Int> {
        mangaProbeTranslationRiskBlockSet(report)
    }

    private var renderBlocks: Set<Int> {
        mangaProbeRenderRiskBlockSet(report)
    }

    private var promotionBoundary: MangaProbePromotionBoundaryContext? {
        mangaProbePromotionBoundary(report)
    }

    private var convergenceOverview: MangaProbeConvergenceOverview? {
        mangaProbeConvergenceOverview(report)
    }

    private var artifactBlocked: Bool {
        guard let readiness = report.externalArtifactReadinessReport else { return false }
        return readiness.nextAction == "stopUntilArtifactsProvided"
            || readiness.nextAction == "stopUntilArtifactContractFixed"
            || readiness.nextAction == "stopUntilRealDetectorSourceDeclared"
    }

    private var statusTitle: String {
        if artifactBlocked { return "等待真实 Koharu 工件" }
        if convergenceOverview?.isBlocked == true { return "Koharu 收敛待闭环" }
        if promotionBoundary?.isBlocked == true { return "Koharu 晋级待修正" }
        if convergenceOverview?.isReportOnly == true || promotionBoundary?.isReportOnly == true {
            return "Koharu 仅报告/预览"
        }
        if !translationBlocks.isEmpty { return "翻译模型待比较" }
        if !ocrBlocks.isEmpty { return "OCR 待复核" }
        if !renderBlocks.isEmpty { return "覆盖布局待复核" }
        return report.overallPassed ? "诊断通过" : "诊断已分流"
    }

    private var statusTone: AppStatusTone {
        if artifactBlocked { return .warning }
        if convergenceOverview?.isBlocked == true
            || convergenceOverview?.isReportOnly == true
            || promotionBoundary?.isBlocked == true
            || promotionBoundary?.isReportOnly == true { return .warning }
        if report.overallPassed { return .success }
        return .warning
    }

    private var nextAction: String {
        if artifactBlocked { return "提供真实 Koharu 四件套并完成 CI 身份对账" }
        if let promotionBoundary { return promotionBoundary.nextAction }
        if let convergenceAction = convergenceOverview?.nextAction, !convergenceAction.isEmpty {
            return convergenceAction
        }
        if !translationBlocks.isEmpty { return "保持模型底线与 OCR 分流，未来再比较更强模型" }
        if !ocrBlocks.isEmpty { return "人工复核 OCR 原文，等待真实 TextBoxes/BubbleMask/SegmentMask" }
        if !renderBlocks.isEmpty { return "保留覆盖布局锁定报告并复核异常块" }
        return report.overallPassed ? "继续观察云端探针" : "打开逐块结果查看失败详情"
    }

    private var statusDetail: String {
        let boundary = promotionBoundary.map { "晋级边界：\($0.summary)。" } ?? "晋级边界：未提供。"
        let convergence = convergenceOverview.map { "收敛：\($0.summary)。" } ?? "收敛：未提供。"
        return "失败 \(report.diagnostics.failedBlocks) 块；OCR 疑似 \(ocrBlocks.count)；翻译模型/语言 \(translationBlocks.count)；覆盖布局 \(renderBlocks.count)。\(convergence)\(boundary) 下一步：\(nextAction)。"
    }

    private var accessibilityValue: String {
        "\(statusTitle)：\(statusDetail) 诊断只读，主流程不变。"
    }

    private func rate(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(4))) } ?? "n/a"
    }

    private var summary: String {
        let readiness = report.externalArtifactReadinessReport
        let model = modelFloor
        let ocr = ocrBlocks.sorted().map(String.init).joined(separator: ",")
        let translation = translationBlocks.sorted().map(String.init).joined(separator: ",")
        let render = renderBlocks.sorted().map(String.init).joined(separator: ",")
        let floorVerdict = model?.floorVerdict ?? "notExecuted"
        let baselinePassRate = rate(model?.baselinePassRate)
        let variantPromptID = model?.variantPromptID ?? "n/a"
        let variantPassRate = rate(model?.variantPassRate)
        let passRateDelta = rate(model?.passRateDelta)
        let variantFixedCases = model?.variantFixedCases.map(String.init).joined(separator: ",") ?? "none"
        let variantRegressedCases = model?.variantRegressedCases.map(String.init).joined(separator: ",") ?? "none"
        let readinessVerdict = readiness?.readinessVerdict ?? "notAvailable"
        let groundTruthDecision = model.map { String($0.groundTruthUsedForDecision) } ?? "n/a"
        let groundTruthEvaluation = model.map { String($0.groundTruthUsedForEvaluationOnly) } ?? "n/a"
        let diagnosticOnly = model.map { String($0.diagnosticOnly) } ?? "n/a"
        let mainFlowChange = model.map { String($0.wouldChangeMainFlow) } ?? "false"
        return [
            "failedBlocks=\(report.diagnostics.failedBlocks)",
            "ocrSuspectBlocks=\(ocr.isEmpty ? "none" : ocr)",
            "translationModelOrLanguageBlocks=\(translation.isEmpty ? "none" : translation)",
            "renderIssueBlocks=\(render.isEmpty ? "none" : render)",
            "convergence=\(convergenceOverview?.summary ?? "notAvailable")",
            "convergenceNextAction=\(convergenceOverview?.nextAction ?? "notAvailable")",
            "promotionBoundary=\(promotionBoundary?.summary ?? "notAvailable")",
            "promotionNextAction=\(promotionBoundary?.nextAction ?? "notAvailable")",
            "floorVerdict=\(floorVerdict)",
            "baselinePassRate=\(baselinePassRate)",
            "variantPromptID=\(variantPromptID)",
            "variantPassRate=\(variantPassRate)",
            "passRateDelta=\(passRateDelta)",
            "variantFixedCases=\(variantFixedCases)",
            "variantRegressedCases=\(variantRegressedCases)",
            "readiness=\(readinessVerdict)",
            "nextAction=\(nextAction)",
            "groundTruthUsedForDecision=\(groundTruthDecision)",
            "groundTruthUsedForEvaluationOnly=\(groundTruthEvaluation)",
            "diagnosticOnly=\(diagnosticOnly)",
            "wouldChangeMainFlow=\(mainFlowChange)",
            "mainFlowChanged=false"
        ].joined(separator: "\n")
    }
}

private struct MangaKoharuArtifactReadinessSummary: View {
    let readiness: MangaOverlayExternalArtifactReadinessReport
    let accessibilityFocus: AccessibilityFocusState<String?>.Binding
    let accessibilityFocusID: String

    var body: some View {
        AppStatusRow(title: statusTitle, detail: statusDetail, tone: statusTone)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Koharu 工件就绪状态")
            .accessibilityValue(readinessAccessibilityValue)
            .accessibilityHint(readinessAccessibilityHint)
            .accessibilityFocused(accessibilityFocus, equals: accessibilityFocusID)
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
        return "source=\(readiness.sourceImage)\nartifactRoot=test/koharu_artifacts\nverdict=\(readiness.readinessVerdict)\nnextAction=\(readiness.nextAction)\nactiveArtifactsDirectory=\(readiness.activeArtifactsDirectory)\ncontractExampleOnly=\(readiness.contractExampleOnly)\nexternalTextBoxesShadowOCRAllowed=\(readiness.externalTextBoxesShadowOCRAllowed)\nmanifestFound=\(readiness.manifestFound)\ntextBoxesFound=\(readiness.textBoxesFound)\nbubbleMaskFound=\(readiness.bubbleMaskFound)\nsegmentMaskFound=\(readiness.segmentMaskFound)\nmissingArtifacts=\(missing)\nparseErrors=\(parseErrors)\ngeneratedBy=\(readiness.generatedBy ?? "n/a")\ntextBoxCount=\(readiness.textBoxCount)\nbubbleInstanceCount=\(readiness.bubbleInstanceCount)\nsegmentGlyphPixelCount=\(readiness.segmentGlyphPixelCount.map(String.init) ?? "n/a")\ncoordinateSchemaVersion=\(coordinate.schemaVersion ?? "n/a")\ncoordinateSpace=\(coordinate.coordinateSpace ?? "n/a")\ncoordinateBboxValidationPassed=\(coordinate.bboxValidationPassed)\nbubbleMaskPayloadVerdict=\(readiness.bubbleMaskPayloadVerdict ?? "n/a")\nsegmentMaskPayloadVerdict=\(readiness.segmentMaskPayloadVerdict ?? "n/a")\nmaskPayloadGateReady=\(optionalBool(readiness.maskPayloadGateReady))\nmaskPayloadGateStatus=\(maskPayloadGateStatus)\nmaskTopologyGateReady=\(optionalBool(readiness.maskTopologyGateReady))\nmaskTopologyGateStatus=\(maskTopologyGateStatus)\nmaskTopologyEvaluated=\(optionalBool(topology?.evaluated))\nmaskTopologyVerdict=\(topology?.topologyVerdict ?? "n/a")\nmaskTopologyBlockers=\(topologyBlockers)\nartifactIdentityVerdict=\(receipt?.identityVerdict ?? "n/a")\nartifactIdentityAllRequiredFilesPresent=\(optionalBool(receipt?.allRequiredFilesPresent))\nartifactIdentityAllRequiredFilesHaveSHA256=\(optionalBool(receipt?.allRequiredFilesHaveSHA256))\nsourceImageSHA256Matches=\(optionalBool(receipt?.sourceImageSHA256Matches))\nnotes=\(notes)\nshadowOnly=true\nmainFlowChanged=false"
    }
}

private struct MangaProbeBlockRow: View {
    let block: MangaOverlayProbeBlock
    let report: MangaOverlayProbeReport?
    let accessibilityFocus: AccessibilityFocusState<String?>.Binding
    let accessibilityFocusID: String
    let expansionResetID: Int
    let requestAccessibilityFocus: (String) -> Void
    @State private var isExpanded = false
    @State private var suppressNextExpansionFocusHandoff = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
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
            .accessibilityElement(children: .contain)
            .accessibilityLabel("漫画探针文字块 \(block.index) 详细诊断")
            .accessibilityValue(blockAccessibilityValue)
            .accessibilityHint("已展开 OCR、译文和诊断输出；收起后回到结果行")
            .accessibilityFocused(accessibilityFocus, equals: detailAccessibilityFocusID)
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(block.index) · \(block.rotationAngleUsed) deg").font(.subheadline.bold())
                    Text(block.ocrText).font(.caption).foregroundStyle(Color.appTextSecondary).lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    AppStatusLabel(text: block.blockPassed ? "PASS" : "FAIL", tone: block.blockPassed ? .success : .danger)
                    if !block.blockPassed {
                        Text(diagnosticRouteLabel)
                            .font(.caption2.bold())
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    if !reportRiskLabels.isEmpty {
                        Text("风险：\(reportRiskSummary)")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.appTextSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                    if let reportAction {
                        Text("建议：\(reportAction.localizedAction)")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.appTextSecondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                        if let diagnosis = reportAction.diagnosis, !diagnosis.isEmpty {
                            Text("依据：\(diagnosis)")
                                .font(.caption2)
                                .foregroundStyle(Color.appTextSecondary)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                        }
                        if let executionBoundary = reportAction.executionBoundary, !executionBoundary.isEmpty {
                            Text("边界：\(executionBoundary)")
                                .font(.caption2)
                                .foregroundStyle(Color.appTextSecondary)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(3)
                        }
                        if let convergenceContext = reportAction.convergenceContext,
                           !convergenceContext.summary.isEmpty {
                            Text("收敛：\(convergenceContext.summary)")
                                .font(.caption2)
                                .foregroundStyle(Color.appTextSecondary)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(4)
                        }
                    }
                }
            }
            .padding(.vertical, AppTheme.Spacing.control)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("漫画探针文字块 \(block.index)")
            .accessibilityValue(blockAccessibilityValue)
            .accessibilityHint(blockAccessibilityHint)
            .accessibilityFocused(accessibilityFocus, equals: accessibilityFocusID)
        }
        .overlay(alignment: .bottom) { Divider().overlay(Color.appBorder) }
        .onChange(of: isExpanded) { _, expanded in
            guard !suppressNextExpansionFocusHandoff else {
                suppressNextExpansionFocusHandoff = false
                return
            }
            focusExpandedDiagnosticDetail(expanded)
        }
        .onChange(of: expansionResetID) { _, _ in
            guard isExpanded else { return }
            suppressNextExpansionFocusHandoff = true
            isExpanded = false
        }
    }

    private var detailAccessibilityFocusID: String {
        "manga-diagnostic-detail-\(block.index)"
    }

    private func focusExpandedDiagnosticDetail(_ expanded: Bool) {
        requestAccessibilityFocus(
            expanded
                ? detailAccessibilityFocusID
                : accessibilityFocusID
        )
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
        if !block.blockPassed {
            parts.append("诊断分流：\(diagnosticRouteLabel)")
        }
        if let translationFailureDetail = block.translationFailureDetail,
           !translationFailureDetail.isEmpty {
            parts.append("翻译失败详情：\(translationFailureDetail)")
        }
        parts.append("报告风险：\(reportRiskSummary)")
        if let reportAction {
            parts.append("报告下一步：\(reportAction.summary)")
        }
        parts.append(isExpanded ? "详细诊断已展开" : "详细诊断已收起")
        return parts.joined(separator: "；")
    }

    private var blockAccessibilityHint: String {
        let riskHint = reportRiskLabels.isEmpty
            ? "报告没有额外风险标签"
            : "报告风险标签：\(reportRiskSummary)"
        let actionHint = reportAction.map { "报告下一步：\($0.summary)" } ?? "报告没有块级下一步"
        let expansionHint = isExpanded
            ? "收起详细诊断并回到文字块结果行"
            : "展开查看 OCR 原文、译文和诊断输出"
        return block.blockPassed
            ? "\(expansionHint)；\(riskHint)；\(actionHint)；此结果只属于漫画探针诊断，不会改变普通图片 OCR、翻译或覆盖图"
            : "\(expansionHint)；当前分流为 \(diagnosticRouteLabel)；\(riskHint)；\(actionHint)；此结果只属于漫画探针诊断，不会改变普通图片 OCR、翻译或覆盖图"
    }

    private var reportRiskLabels: [String] {
        guard let report else { return [] }
        var labels: [String] = []
        if mangaProbeOCRRiskBlockSet(report).contains(block.index) {
            labels.append("OCR")
        }
        if mangaProbeTranslationRiskBlockSet(report).contains(block.index) {
            labels.append("翻译")
        }
        if mangaProbeRenderRiskBlockSet(report).contains(block.index) {
            labels.append("布局")
        }
        return labels
    }

    private var reportRiskSummary: String {
        reportRiskLabels.isEmpty ? "无额外风险" : reportRiskLabels.joined(separator: "、")
    }

    private var reportAction: MangaProbeBlockReportAction? {
        guard let report else { return nil }
        return mangaProbeBlockReportAction(report, blockIndex: block.index)
    }

    private var diagnosticRouteLabel: String {
        switch block.failureCategory {
        case "ocrInputSuspect": "OCR 疑似损坏"
        case "modelOutputFailure": "模型输出失败"
        case "translationLanguageQualityFailure": "译文质量失败"
        case "": "待复核"
        default: block.failureCategory
        }
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
