import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private enum ImageOCRDirectionPresentation {
    static func displayTitle(for block: ImageTranslationBlock) -> String {
        switch block.effectiveSourceDirection {
        case .horizontal:
            "横排"
        case .vertical:
            "竖排"
        case .unknown, .none:
            "方向待定"
        }
    }

    static func accessibilityContext(for block: ImageTranslationBlock) -> String? {
        let title: String
        switch block.effectiveSourceDirection {
        case .horizontal:
            title = "横排"
        case .vertical:
            title = "竖排"
        case .unknown, .none:
            return nil
        }

        guard let rawConfidence = block.directionConfidence,
              rawConfidence.isFinite else {
            return block.hasSourceDirectionOverride ? "\(title)，手动覆盖" : title
        }
        let confidence = min(max(rawConfidence, 0), 1)
        let percent = Int((confidence * 100).rounded())
        let overrideSuffix = block.hasSourceDirectionOverride ? "，手动覆盖" : ""
        return "\(title)，方向置信度 \(percent)%\(overrideSuffix)"
    }

    static func choice(for block: ImageTranslationBlock) -> ImageTextDirectionOverrideChoice {
        switch block.sourceDirectionOverride {
        case .horizontal: .horizontal
        case .vertical: .vertical
        case .unknown, .none: .automatic
        }
    }
}

private enum ImageOCRGeometryPresentation {
    static func isLocatable(for block: ImageTranslationBlock) -> Bool {
        block.boundingBox.normalizedToUnit() != nil
    }
}

private struct ImageOCRDirectionOverrideMenu: View {
    let block: ImageTranslationBlock
    let canEdit: Bool
    let unavailableHint: String
    let setDirectionOverride: (ImageTextDirection?) -> Void

    var body: some View {
        Menu {
            ForEach(ImageTextDirectionOverrideChoice.allCases) { choice in
                Button {
                    setDirectionOverride(choice.direction)
                } label: {
                    Label(choice.rawValue, systemImage: choice.systemImage)
                }
            }
        } label: {
            Image(systemName: "text.alignleft")
                .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
        }
        .disabled(!canEdit)
        .opacity(canEdit ? 1 : 0.45)
        .accessibilityLabel("设置文字方向")
        .accessibilityValue(ImageOCRDirectionPresentation.choice(for: block).rawValue)
        .accessibilityHint(
            canEdit
                ? "选择自动、横排或竖排；只更新当前文字块的显示和导出方向"
                : unavailableHint
        )
    }
}

struct ImageTranslationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                    AppPageHeader(
                        title: "图片翻译",
                        subtitle: "Vision OCR 与本地翻译",
                        systemImage: "photo.on.rectangle",
                        status: statusTitle,
                        statusTone: statusTone
                    )
                    ImageTranslationPanel {
                        revealImagePreview(using: proxy)
                    }
                }
                .enterprisePageFrame(maxWidth: AppTheme.Layout.workspaceMaxWidth)
                .padding(.vertical, AppTheme.Spacing.section)
                .padding(.bottom, 72)
            }
            .background(Color.appCanvas)
        }
    }

    private func revealImagePreview(using proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(ImageTranslationPanel.previewScrollID, anchor: .top)
        } else {
            withAnimation(AppTheme.Motion.standard) {
                proxy.scrollTo(ImageTranslationPanel.previewScrollID, anchor: .top)
            }
        }
    }

    private var statusTone: AppStatusTone {
        switch store.imageTranslationShareState {
        case .preparing: return .active
        case .failed: return .danger
        case .idle: break
        }
        switch store.imageTranslationExportRenderState {
        case .rendering: return .active
        case .failed: return .danger
        case .idle: break
        }
        switch store.imageTranslationState {
        case .idle: return .neutral
        case .loading, .recognizing, .translating: return .active
        case .translated: return .success
        case .failed: return .danger
        }
    }

    private var statusTitle: String {
        switch store.imageTranslationShareState {
        case .preparing: return "准备分享"
        case .failed: return "分享失败"
        case .idle: break
        }
        switch store.imageTranslationExportRenderState {
        case .rendering: return "更新导出"
        case .failed: return "导出失败"
        case .idle: return store.imageTranslationProgressTitle
        }
    }
}

struct ImageTranslationPanel: View {
    private enum ImageTranslationRerecognitionFocusOrigin {
        case row
        case preview
    }

    private enum ImageTranslationCorrectionFocusOrigin: Equatable {
        case row
        case preview
    }

    static let previewScrollID = "imageTranslationPreview"
    private static let reviewCompletionAccessibilityFocusID = "image-review-complete"
    private static let reviewFilterAccessibilityFocusID = "image-review-filter"
    private static let reviewFilterEmptyAccessibilityFocusID = "image-review-filter-empty"
    private static let imageIgnoredBlocksEmptyAccessibilityFocusID = "image-ignored-blocks-empty"
    private static let imageTranslationStatusAccessibilityFocusID = "image-translation-status"
    private static let imagePreviewStatusAccessibilityFocusID = "image-preview-status"
    private static let imageEmptyAccessibilityFocusID = "image-empty-state"
    private static let imageResultEmptyAccessibilityFocusID = "image-result-empty-state"
    private static let imageRetryLanguageStatusAccessibilityFocusID = "image-retry-language-status"

    @EnvironmentObject private var store: TranslationSessionStore
    @State private var showImageImporter = false
    @State private var imageFileSelectionID: UUID?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var shareURL: URL?
    @State private var sharePresentationID = UUID()
    @State private var reviewFilter: ImageOCRReviewFilter = .all
    @State private var pendingReviewFilterFocusID: String?
    @State private var suppressNextReviewFilterResultFocus = false
    @State private var reviewAccessibilityFocusRequestID = 0
    @State private var pendingImageTranslationTerminalFocusRevision: Int?
    @State private var imageTranslationRerecognitionFocusOrigin:
        ImageTranslationRerecognitionFocusOrigin?
    @State private var imageTranslationCorrectionFocusOrigin:
        ImageTranslationCorrectionFocusOrigin?
    @State private var selectedImageTranslationBlockID: UUID?
    @State private var editingImageTranslationBlock: ImageTranslationBlock?
    @State private var restoreConfirmationBlock: ImageTranslationBlock?
    @State private var showRestoreAllIgnoredConfirmation = false
    @State private var pendingRestoreConfirmationDismissalFocusID: String?
    @State private var pendingRestoreConfirmationDismissalRevision: Int?
    @State private var pendingCorrectionSheetDismissalFocusID: String?
    @State private var pendingCorrectionSheetDismissalRevision: Int?
    @AccessibilityFocusState private var reviewAccessibilityFocusID: String?
    let revealPreview: () -> Void

    var body: some View {
        imageTranslationPanelReviewObservers
    }

    private var imageTranslationPanelPresentation: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.section) {
                imageWorkspace
                    .frame(minWidth: 440)
                inspector
                    .frame(width: AppTheme.Layout.inspectorWidth)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                imageWorkspace
                inspector
            }
        }
        .id(Self.previewScrollID)
        .fileImporter(isPresented: $showImageImporter, allowedContentTypes: [.image], onCompletion: handleImport)
        .onChange(of: selectedPhotoItem) { oldItem, newItem in
            loadSelectedPhoto(oldItem, newItem)
        }
        .sheet(item: $shareURL, onDismiss: finishSharing) { url in
            ShareSheet(activityItems: [url])
        }
        .sheet(
            item: $editingImageTranslationBlock,
            onDismiss: applyPendingCorrectionSheetDismissalFocus
        ) { block in
            ImageOCRCorrectionSheet(
                block: block,
                imageData: store.imageTranslationData,
                didSave: {
                    completeReviewAfterCorrection(block.id)
                },
                setDirectionOverride: { direction in
                    setImageTranslationBlockDirection(
                        direction,
                        for: block.id,
                        focusInPreview: imageTranslationCorrectionFocusOrigin == .preview,
                        deferFocusUntilCorrectionSheetDismissal: true
                    )
                },
                requestIgnore: {
                    ignoreImageTranslationBlock(block)
                }
            )
            .environmentObject(store)
        }
        .confirmationDialog(
            "恢复 Vision OCR？",
            isPresented: isRestoreConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("恢复 Vision OCR", role: .destructive) {
                guard let block = restoreConfirmationBlock else { return }
                confirmVisionOCRRestore(block)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会移除本次人工修正，并恢复识别时的原文和初始译文。")
        }
        .confirmationDialog(
            "恢复全部已忽略文字块？",
            isPresented: $showRestoreAllIgnoredConfirmation,
            titleVisibility: .visible
        ) {
            Button("恢复全部文字块") {
                restoreAllIgnoredImageTranslationBlocks()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会把 \(store.imageTranslationIgnoredBlocks.count) 个文字块恢复到图片预览、导出和当前转录；需要复查的文字块会重新回到待复查队列。")
        }
    }

    private var imageTranslationPanelStatusObservers: some View {
        imageTranslationPanelPresentation
        .onChange(of: store.imageTranslationExportURL) { _, exportURL in
            guard exportURL == nil else { return }
            finishSharing()
        }
        .onChange(of: store.imageTranslationShareState) { oldState, state in
            guard case .failed = state, state != oldState else { return }
            moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)
        }
        .onChange(of: store.imageTranslationExportRenderState) { oldState, state in
            guard case .failed = state, state != oldState else { return }
            moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)
        }
        .onDisappear {
            finishSharing()
        }
    }

    private var imageTranslationPanelReviewObservers: some View {
        imageTranslationPanelStatusObservers
        .onChange(of: store.imageTranslationRevision) { _, _ in
            prepareReviewFilterChange(
                to: .all,
                focusID: nil,
                suppressResultFocus: true
            )
            pendingImageTranslationTerminalFocusRevision = store.imageTranslationRevision
            imageTranslationRerecognitionFocusOrigin = nil
            imageTranslationCorrectionFocusOrigin = nil
            reviewAccessibilityFocusRequestID &+= 1
            selectedImageTranslationBlockID = nil
            editingImageTranslationBlock = nil
            restoreConfirmationBlock = nil
            showRestoreAllIgnoredConfirmation = false
            clearPendingRestoreConfirmationDismissalFocus()
            clearPendingCorrectionSheetDismissalFocus()
            reviewAccessibilityFocusID = nil
            if store.imageTranslationData == nil,
               store.imageTranslationState == .idle {
                moveReviewAccessibilityFocus(to: Self.imageEmptyAccessibilityFocusID)
            }
        }
        .onChange(of: store.imageTranslationState) { oldState, state in
            if state == .idle {
                switch oldState {
                case .loading, .recognizing, .translating:
                    pendingImageTranslationTerminalFocusRevision = nil
                    moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)
                case .idle, .translated, .failed:
                    break
                }
                return
            }
            if state == .failed,
               pendingImageTranslationTerminalFocusRevision != store.imageTranslationRevision {
                pendingImageTranslationTerminalFocusRevision = nil
                moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)
                return
            }
            guard state == .translated || state == .failed else { return }
            guard pendingImageTranslationTerminalFocusRevision == store.imageTranslationRevision else { return }
            pendingImageTranslationTerminalFocusRevision = nil
            focusImageTranslationTerminalStateIfNeeded()
        }
        .onChange(of: store.imageTranslationBlockRetryCompletionGeneration) { _, generation in
            guard generation > 0,
                  store.imageTranslationState == .translated else { return }
            focusImageTranslationRetryCompletionIfNeeded(generation)
        }
        .onChange(of: store.imageTranslationBlockRerecognitionCompletionGeneration) { _, generation in
            guard generation > 0,
                  let blockID = store.imageTranslationBlockRerecognitionCompletedBlockID,
                  store.imageTranslationState == .translated || store.imageTranslationState == .failed else {
                return
            }
            focusImageTranslationRerecognitionCompletionIfNeeded(
                generation,
                blockID: blockID
            )
        }
        .onChange(of: store.imageTranslationBlockRerecognitionFailureGeneration) { _, generation in
            guard generation > 0,
                  store.imageTranslationRerecognizingBlockID == nil,
                  store.imageTranslationState == .translated || store.imageTranslationState == .failed else {
                return
            }
            focusImageTranslationRerecognitionFailureIfNeeded(generation)
        }
        .onChange(of: store.imageTranslationRetryLanguageSummary) { oldSummary, newSummary in
            guard newSummary != nil, newSummary != oldSummary else { return }
            moveReviewAccessibilityFocus(to: Self.imageRetryLanguageStatusAccessibilityFocusID)
        }
        .onChange(of: reviewFilter) { _, _ in
            let explicitFocusID = pendingReviewFilterFocusID
            let suppressResultFocus = suppressNextReviewFilterResultFocus
            pendingReviewFilterFocusID = nil
            suppressNextReviewFilterResultFocus = false
            clearHiddenReviewSelection()
            if let explicitFocusID {
                moveReviewAccessibilityFocus(to: explicitFocusID)
            } else if !suppressResultFocus {
                focusReviewFilterResultIfNeeded()
            }
            focusEmptyReviewStateIfNeeded()
        }
    }

    private var imageWorkspace: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
            ImageCommandBar(
                selectedPhotoItem: $selectedPhotoItem,
                openImporter: {
                    imageFileSelectionID = store.beginImageFileSelection()
                    showImageImporter = true
                },
                shareResult: shareResult
            )
            ImageTranslationPreview(
                selectedBlockID: selectedImageTranslationBlockID,
                positionText: selectedBlockPositionText,
                canSelectPrevious: canSelectPreviousBlock,
                canSelectNext: canSelectNextBlock,
                reviewedBlockIDs: store.imageTranslationReviewedBlockIDs,
                canEdit: canModifyImageTranslation,
                canReview: canReviewImageTranslation,
                modificationUnavailableHint: imageModificationUnavailableDetail,
                reviewUnavailableHint: imageReviewUnavailableDetail,
                accessibilityFocus: $reviewAccessibilityFocusID,
                previewStatusAccessibilityFocusID: Self.imagePreviewStatusAccessibilityFocusID,
                focusPreviewStatus: {
                    moveReviewAccessibilityFocus(to: Self.imagePreviewStatusAccessibilityFocusID)
                },
                selectBlock: selectBlockFromPreview,
                clearSelection: closeImageTranslationFocusPreview,
                selectPrevious: { selectAdjacentBlock(offset: -1) },
                selectNext: { selectAdjacentBlock(offset: 1) },
                editBlock: { beginCorrectionFromFocusPreview(of: $0) },
                restoreVisionOCR: { requestVisionOCRRestore(for: $0) },
                setDirectionOverride: { direction in
                    guard let selectedImageTranslationBlockID else { return }
                    setImageTranslationBlockDirection(
                        direction,
                        for: selectedImageTranslationBlockID,
                        focusInPreview: true
                    )
                },
                canRetryTranslation: { store.canRetryImageTranslationBlock($0) },
                isRetryingTranslation: { store.imageTranslationRetryingBlockID == $0 },
                retryTranslation: { store.retryImageTranslationBlock($0) },
                canRerecognize: { store.canRerecognizeImageTranslationBlock($0) },
                isRerecognizing: { store.imageTranslationRerecognizingBlockID == $0 },
                rerecognize: {
                    requestImageTranslationRerecognition(
                        $0,
                        focusOrigin: .preview
                    )
                },
                toggleReviewCompletion: { blockID in
                    toggleReviewCompletion(blockID, focusInPreview: true)
                }
            )
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            AppSectionHeader(
                title: "翻译设置",
                subtitle: "识别 \(store.imageTranslationDisplayedSourceLanguage.rawValue) · 译为 \(store.imageTranslationDisplayedTargetLanguage.rawValue)",
                systemImage: "character.bubble"
            )

            ImageSourceLanguageControl()
            ImageTargetLanguageControl()

            if let retryLanguageSummary = store.imageTranslationRetryLanguageSummary {
                AppStatusRow(
                    title: "重试语言已更新",
                    detail: retryLanguageSummary,
                    tone: .warning
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("重试语言已更新")
                .accessibilityValue(retryLanguageSummary)
                .accessibilityHint("当前图片失败或取消后，下一次重试会使用这组语言；可在此状态上执行“重试当前图片”，开始重新识别和翻译")
                .accessibilityAction(named: "重试当前图片") {
                    guard store.canRetryImageTranslation else { return }
                    store.retryImageTranslation()
                }
                .accessibilityFocused(
                    $reviewAccessibilityFocusID,
                    equals: Self.imageRetryLanguageStatusAccessibilityFocusID
                )
            }

            AppSectionHeader(
                title: "识别结果",
                subtitle: store.imageTranslationSummary,
                systemImage: "viewfinder"
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("识别结果")
            .accessibilityValue(store.imageTranslationSummary)
            .accessibilityHint(imageSummaryAccessibilityHint)
            .accessibilityAddTraits(.isHeader)

            if !store.imageTranslationBlocks.isEmpty {
                Picker("识别结果筛选", selection: $reviewFilter) {
                    ForEach(ImageOCRReviewFilter.allCases) { filter in
                        Text(filterTitle(filter)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityValue(reviewFilterAccessibilityValue)
                .accessibilityHint(reviewFilterAccessibilityHint)
                .accessibilityFocused(
                    $reviewAccessibilityFocusID,
                    equals: Self.reviewFilterAccessibilityFocusID
                )

                if !allReviewRequiredBlocks.isEmpty {
                    ProgressView(
                        value: Double(reviewCompletedBlockCount),
                        total: Double(allReviewRequiredBlocks.count)
                    ) {
                        HStack {
                            Label("本次复查", systemImage: "checklist")
                            Spacer(minLength: AppTheme.Spacing.compact)
                            Text("已完成 \(reviewCompletedBlockCount) / \(allReviewRequiredBlocks.count)")
                        }
                        .font(.subheadline)
                    }
                    .tint(reviewRequiredBlocks.isEmpty ? Color.appSuccess : Color.appWarning)
                    .accessibilityLabel("本次复查进度")
                    .accessibilityValue(
                        "已完成 \(reviewCompletedBlockCount) 个，共 \(allReviewRequiredBlocks.count) 个，剩余 \(reviewRequiredBlocks.count) 个"
                    )
                }

                if !reviewRequiredBlocks.isEmpty {
                    AppSecondaryButton(
                        title: reviewQueueActionTitle,
                        systemImage: "checklist",
                        tone: .warning,
                        action: beginReviewQueue
                    )
                    .disabled(!canReviewImageTranslation)
                    .accessibilityHint(
                        canReviewImageTranslation
                            ? "显示待复查结果并定位当前或第一个文字块"
                            : imageReviewUnavailableDetail
                    )
                } else if reviewCompletedBlockCount > 0 {
                    AppSecondaryButton(
                        title: "重新复查 \(reviewCompletedBlockCount)",
                        systemImage: "arrow.counterclockwise",
                        action: restartReviewQueue
                    )
                    .disabled(!canReviewImageTranslation)
                    .accessibilityHint(
                        canReviewImageTranslation
                            ? "清除本次复查进度并定位第一个待复查文字块"
                            : imageReviewUnavailableDetail
                    )
                }
            }

            Picker("覆盖方式", selection: overlayModeBinding) {
                ForEach(ImageTranslationOverlayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!canModifyImageTranslation)
            .accessibilityHint(
                canModifyImageTranslation
                    ? "选择译文以旁贴或覆盖方式呈现"
                    : imageModificationUnavailableDetail
            )

            imageStatusAccessibilityRow(
                AppStatusRow(
                    title: statusTitle,
                    detail: statusDetail,
                    tone: statusTone
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("图片翻译状态")
                .accessibilityValue(imageStatusAccessibilityValue)
                .accessibilityHint(imageStatusAccessibilityHint)
                .accessibilityFocused(
                    $reviewAccessibilityFocusID,
                    equals: Self.imageTranslationStatusAccessibilityFocusID
                )
            )

            if let imageActionLockDetail {
                AppStatusRow(
                    title: imageActionLockTitle,
                    detail: imageActionLockDetail,
                    tone: .warning
                )
                .accessibilityLabel(imageActionLockTitle)
                .accessibilityValue(imageActionLockDetail)
            }

            if store.imageTranslationBlocks.isEmpty {
                if store.imageTranslationData == nil {
                    AppEmptyState(
                        title: "等待图片",
                        detail: "选择照片或图片文件后，本机 OCR 结果会显示在这里。",
                        systemImage: "photo.badge.plus"
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("等待图片")
                    .accessibilityValue("当前没有图片")
                    .accessibilityHint("从上方照片或文件按钮选择图片，并开始本机 OCR 与翻译")
                    .accessibilityFocused(
                        $reviewAccessibilityFocusID,
                        equals: Self.imageEmptyAccessibilityFocusID
                    )
                } else if !store.imageTranslationIgnoredBlocks.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
                        allIgnoredBlocksEmptyStateAccessibility(
                            AppEmptyState(
                                title: "当前没有保留文字块",
                                detail: "已忽略 \(store.imageTranslationIgnoredBlocks.count) 个 OCR 文字块；图片会以原图导出，可在此恢复全部。",
                                systemImage: "eye.slash"
                            )
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("当前没有保留文字块")
                            .accessibilityValue(
                                "已忽略 \(store.imageTranslationIgnoredBlocks.count) 个 OCR 文字块；图片会以原图导出"
                            )
                            .accessibilityHint(
                                canModifyImageTranslation
                                    ? "可在此执行“恢复全部”，把文字块恢复到图片预览、导出和当前转录"
                                    : imageModificationUnavailableDetail
                            )
                        )
                        .accessibilityFocused(
                            $reviewAccessibilityFocusID,
                            equals: Self.imageIgnoredBlocksEmptyAccessibilityFocusID
                        )

                        AppSecondaryButton(
                            title: "恢复全部 \(store.imageTranslationIgnoredBlocks.count)",
                            systemImage: "arrow.uturn.backward",
                            action: requestRestoreAllIgnoredImageTranslationBlocks
                        )
                        .disabled(!canModifyImageTranslation)
                        .accessibilityHint(
                            canModifyImageTranslation
                                ? "恢复全部已忽略文字块到图片预览、导出和当前转录；需要复查的文字块会重新回到待复查队列"
                                : imageModificationUnavailableDetail
                        )
                    }
                } else {
                    VStack(spacing: AppTheme.Spacing.control) {
                        imageResultEmptyStateAccessibility(
                            AppEmptyState(
                                title: imageResultEmptyStateTitle,
                                detail: imageResultEmptyStateDetail,
                                systemImage: "viewfinder"
                            )
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(imageResultEmptyStateAccessibilityLabel)
                            .accessibilityValue(store.imageTranslationMessage)
                            .accessibilityHint(imageResultEmptyStateAccessibilityHint)
                        )
                        .accessibilityFocused(
                            $reviewAccessibilityFocusID,
                            equals: Self.imageResultEmptyAccessibilityFocusID
                        )

                        if store.canRerunImageRecognition {
                            AppSecondaryButton(
                                title: "重新识别",
                                systemImage: "text.viewfinder",
                                action: store.rerunImageRecognition
                            )
                            .accessibilityHint("使用当前图片语言重新运行 Vision OCR，并重新翻译识别到的文字")
                        } else if canRetryFromImageStatus {
                            AppSecondaryButton(
                                title: "重试当前图片",
                                systemImage: "arrow.clockwise",
                                tone: .warning,
                                action: store.retryImageTranslation
                            )
                            .accessibilityHint(imageResultEmptyStateRetryHint)
                        }
                    }
                }
            } else if visibleImageTranslationBlocks.isEmpty {
                if reviewFilter == .needsReview, reviewCompletedBlockCount > 0 {
                    reviewCompletionEmptyStateAccessibility(
                        AppEmptyState(
                            title: "本次复查完成",
                            detail: "所有风险块都已标记为已复查，可随时重新开始。",
                            systemImage: "checkmark.circle.fill"
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("本次复查完成")
                        .accessibilityValue(reviewCompletionAccessibilityValue)
                        .accessibilityHint(
                            canReviewImageTranslation
                                ? "所有风险块都已完成本次复查；可在此状态上执行“重新复查”"
                                : imageReviewUnavailableDetail
                        )
                    )
                    .accessibilityFocused(
                        $reviewAccessibilityFocusID,
                        equals: Self.reviewCompletionAccessibilityFocusID
                    )
                } else if reviewFilter != .all {
                    VStack(spacing: AppTheme.Spacing.control) {
                        AppEmptyState(
                            title: "当前筛选没有结果",
                            detail: filterEmptyStateDetail,
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("当前图片筛选没有结果")
                        .accessibilityValue(reviewFilterEmptyStateAccessibilityValue)
                        .accessibilityHint("切换上方识别结果筛选，或回到全部查看当前图片的文字块；也可在此执行“显示全部结果”")
                        .accessibilityAction(named: "显示全部结果") {
                            showAllReviewResults()
                        }
                        .accessibilityFocused(
                            $reviewAccessibilityFocusID,
                            equals: Self.reviewFilterEmptyAccessibilityFocusID
                        )

                        AppSecondaryButton(
                            title: "显示全部结果",
                            systemImage: "list.bullet",
                            action: showAllReviewResults
                        )
                        .accessibilityHint("切换到全部筛选，查看当前图片的所有文字块")
                    }
                } else {
                    AppEmptyState(
                        title: "无需复查",
                        detail: "当前结果没有低置信或方向待定文字块。",
                        systemImage: "checkmark.circle"
                    )
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visibleImageTranslationBlocks) { block in
                        ImageTranslationBlockRow(
                            block: block,
                            isSelected: selectedImageTranslationBlockID == block.id,
                            isReviewCompleted: store.imageTranslationReviewedBlockIDs.contains(block.id),
                            isManuallyCorrected: store.imageTranslationCorrectedBlockIDs.contains(block.id),
                            canEdit: canModifyImageTranslation,
                            canReview: canReviewImageTranslation,
                            modificationUnavailableHint: imageModificationUnavailableDetail,
                            reviewUnavailableHint: imageReviewUnavailableDetail,
                            canRetryTranslation: store.canRetryImageTranslationBlock(block.id),
                            isRetryingTranslation: store.imageTranslationRetryingBlockID == block.id,
                            retryTranslation: { store.retryImageTranslationBlock(block.id) },
                            canRerecognize: store.canRerecognizeImageTranslationBlock(block.id),
                            isRerecognizing: store.imageTranslationRerecognizingBlockID == block.id,
                            rerecognize: {
                                requestImageTranslationRerecognition(
                                    block.id,
                                    focusOrigin: .row
                                )
                            },
                            retryUnavailableHint: imageTranslationBlockRetryUnavailableHint,
                            accessibilityFocus: $reviewAccessibilityFocusID,
                            select: { toggleSelection(of: block.id) },
                            edit: { beginCorrection(of: block) },
                            restoreVisionOCR: { requestVisionOCRRestore(for: block) },
                            setDirectionOverride: { direction in
                                setImageTranslationBlockDirection(
                                    direction,
                                    for: block.id,
                                    focusInPreview: false
                                )
                            },
                            toggleReviewCompletion: {
                                toggleReviewCompletion(block.id, focusInPreview: false)
                            }
                        )
                    }
                }
            }

            if !store.imageTranslationIgnoredBlocks.isEmpty {
                AppSectionHeader(
                    title: "已忽略的文字块",
                    subtitle: "\(store.imageTranslationIgnoredBlocks.count) 个不会出现在预览、导出或当前转录中",
                    systemImage: "eye.slash"
                )

                if !store.imageTranslationBlocks.isEmpty {
                    AppSecondaryButton(
                        title: "恢复全部 \(store.imageTranslationIgnoredBlocks.count)",
                        systemImage: "arrow.uturn.backward",
                        action: requestRestoreAllIgnoredImageTranslationBlocks
                    )
                    .disabled(!canModifyImageTranslation)
                    .accessibilityHint(
                        canModifyImageTranslation
                            ? "恢复全部已忽略文字块到图片预览、导出和当前转录；需要复查的文字块会重新回到待复查队列"
                            : imageModificationUnavailableDetail
                    )
                }

                LazyVStack(spacing: 0) {
                    ForEach(store.imageTranslationIgnoredBlocks) { block in
                        ImageTranslationIgnoredBlockRow(
                            block: block,
                            canRestore: canModifyImageTranslation,
                            modificationUnavailableHint: imageModificationUnavailableDetail,
                            accessibilityFocus: $reviewAccessibilityFocusID,
                            restore: { restoreIgnoredImageTranslationBlock(block) }
                        )
                    }
                }
            }
        }
        .appSurface()
    }

    private var overlayModeBinding: Binding<ImageTranslationOverlayMode> {
        Binding(
            get: { store.imageOverlayMode },
            set: { store.setImageOverlayMode($0) }
        )
    }

    private var isRestoreConfirmationPresented: Binding<Bool> {
        Binding(
            get: { restoreConfirmationBlock != nil },
            set: { isPresented in
                guard !isPresented else { return }
                restoreConfirmationBlock = nil
                applyPendingRestoreConfirmationDismissalFocus()
            }
        )
    }

    private var visibleImageTranslationBlocks: [ImageTranslationBlock] {
        let filteredBlocks = reviewFilter.blocks(from: store.imageTranslationBlocks)
        guard reviewFilter == .needsReview else { return filteredBlocks }
        return filteredBlocks.filter { !store.imageTranslationReviewedBlockIDs.contains($0.id) }
    }

    private var reviewRequiredBlocks: [ImageTranslationBlock] {
        ImageOCRReviewFilter.needsReview.blocks(from: store.imageTranslationBlocks)
            .filter { !store.imageTranslationReviewedBlockIDs.contains($0.id) }
    }

    private var allReviewRequiredBlocks: [ImageTranslationBlock] {
        ImageOCRReviewFilter.needsReview.blocks(from: store.imageTranslationBlocks)
    }

    private var reviewCompletedBlockCount: Int {
        allReviewRequiredBlocks.count(where: { store.imageTranslationReviewedBlockIDs.contains($0.id) })
    }

    private var reviewQueueActionTitle: String {
        let action = reviewCompletedBlockCount == 0 ? "开始复查" : "继续复查"
        return "\(action) \(reviewRequiredBlocks.count)"
    }

    private var reviewCompletionAccessibilityValue: String {
        "已完成 \(reviewCompletedBlockCount) 个风险块，共 \(allReviewRequiredBlocks.count) 个；当前筛选为 \(reviewFilter.rawValue)"
    }

    private func showAllReviewResults() {
        guard reviewFilter != .all else { return }
        prepareReviewFilterChange(to: .all, focusID: nil)
    }

    private var imageSummaryAccessibilityHint: String {
        guard !store.imageTranslationBlocks.isEmpty else {
            return "选择照片或图片文件后，本机 OCR 文字块摘要会显示在这里。"
        }
        guard canReviewImageTranslation else {
            return "下方可继续查看和定位文字块；\(imageReviewUnavailableDetail)"
        }
        if allReviewRequiredBlocks.isEmpty {
            return "下方可筛选和定位文字块；当前没有需要复查的文字块。"
        }
        return "下方可筛选、定位、修正或更新文字块复查进度。"
    }

    private var imageResultEmptyStateAccessibilityLabel: String {
        switch store.imageTranslationState {
        case .idle:
            store.imageTranslationData == nil ? "等待识别结果" : "等待重新识别"
        case .loading, .recognizing, .translating:
            "正在准备识别结果"
        case .translated:
            "没有可显示的识别结果"
        case .failed:
            "图片识别结果失败"
        }
    }

    private var imageResultEmptyStateTitle: String {
        switch store.imageTranslationState {
        case .idle:
            "等待重新识别"
        case .loading, .recognizing, .translating:
            "正在准备识别结果"
        case .translated:
            "没有可显示的识别结果"
        case .failed:
            "识别结果不可用"
        }
    }

    private var imageResultEmptyStateDetail: String {
        switch store.imageTranslationState {
        case .idle:
            "当前图片尚未完成处理；可在上方状态或重试按钮重新识别和翻译，也可选择新图片。"
        case .loading, .recognizing, .translating:
            store.imageTranslationMessage
        case .translated:
            store.canRerunImageRecognition
                ? "当前图片已完成处理，但没有可显示的 OCR 文字块；可重新识别当前图片。"
                : "当前图片已完成处理，但没有可显示的 OCR 文字块；可选择新图片重新识别。"
        case .failed:
            store.imageTranslationMessage
        }
    }

    private var imageResultEmptyStateAccessibilityHint: String {
        switch store.imageTranslationState {
        case .idle:
            if store.imageTranslationData == nil {
                return "从上方照片或文件按钮选择图片，并开始本机 OCR 与翻译"
            }
            if canRetryFromImageStatus {
                return "当前图片尚未完成处理；可在此或上方状态执行“重试当前图片”，重新识别和翻译"
            }
            if store.canRetryImageTranslation {
                return "重试语言已更新；可在上方状态执行“重试当前图片”，使用当前选择的语言重新识别和翻译"
            }
            return "当前图片尚未完成处理；可选择新图片重新识别和翻译"
        case .loading, .recognizing, .translating:
            return "图片正在读取、识别或翻译；可在上方状态取消或选择新图片"
        case .translated:
            return store.canRerunImageRecognition
                ? "当前没有可显示的 OCR 文字块；可在此执行“重新识别”，只重跑当前图片的 Vision OCR 与翻译，也可选择新图片"
                : "当前没有可显示的 OCR 文字块；可选择新图片重新识别"
        case .failed:
            if canRetryFromImageStatus {
                return "图片识别失败；可在此或上方状态执行“重试当前图片”，也可选择新图片"
            }
            if store.canRetryImageTranslation {
                return "图片识别失败且重试语言已更新；可在上方状态执行“重试当前图片”，也可选择新图片"
            }
            return "图片识别失败；请从上方照片或文件按钮选择新图片"
        }
    }

    private var imageResultEmptyStateRetryHint: String {
        "使用当前图片语言重新识别并翻译这张图片"
    }

    @ViewBuilder
    private func imageResultEmptyStateAccessibility<Content: View>(_ content: Content) -> some View {
        if store.canRerunImageRecognition {
            content
                .accessibilityAction(named: "重新识别") {
                    store.rerunImageRecognition()
                }
        } else if canRetryFromImageStatus {
            content
                .accessibilityAction(named: "重试当前图片") {
                    guard store.canRetryImageTranslation else { return }
                    store.retryImageTranslation()
                }
        } else {
            content
        }
    }

    @ViewBuilder
    private func allIgnoredBlocksEmptyStateAccessibility<Content: View>(_ content: Content) -> some View {
        if canModifyImageTranslation {
            content
                .accessibilityAction(named: "恢复全部") {
                    requestRestoreAllIgnoredImageTranslationBlocks()
                }
        } else {
            content
        }
    }

    @ViewBuilder
    private func reviewCompletionEmptyStateAccessibility<Content: View>(_ content: Content) -> some View {
        if canReviewImageTranslation {
            content
                .accessibilityAction(named: "重新复查") {
                    restartReviewQueue()
                }
        } else {
            content
        }
    }

    private var reviewFilterAccessibilityHint: String {
        switch reviewFilter {
        case .all:
            return "显示全部 OCR 文字块；可以切换到待复查、低置信、方向待定或竖排"
        case .needsReview:
            return "显示尚未完成复查的低置信或方向待定文字块"
        case .lowConfidence:
            return "只显示 OCR 置信度低于 50% 的文字块；已复查的风险块仍会保留"
        case .unknownDirection:
            return "只显示方向待定的文字块；已复查的风险块仍会保留"
        case .vertical:
            return "只显示来源方向为竖排的文字块；包含高置信度结果，方便逐列检查日语识别"
        }
    }

    private var reviewFilterAccessibilityValue: String {
        var parts = [
            "当前：\(reviewFilter.rawValue)",
            "显示 \(visibleImageTranslationBlocks.count) 个，共 \(store.imageTranslationBlocks.count) 个文字块"
        ]
        if !allReviewRequiredBlocks.isEmpty {
            parts.append(
                "复查已完成 \(reviewCompletedBlockCount) 个，剩余 \(reviewRequiredBlocks.count) 个"
            )
        }
        return parts.joined(separator: "；")
    }

    private var filterEmptyStateDetail: String {
        switch reviewFilter {
        case .all:
            return "切换到待复查、低置信、方向待定或竖排可查看对应文字块。"
        case .needsReview:
            return "当前没有尚未完成复查的风险块；可以切换到全部查看已复查结果。"
        case .lowConfidence:
            return "当前没有低于 50% 置信度的文字块；可切换到全部、方向待定或竖排。"
        case .unknownDirection:
            return "当前没有方向待定的文字块；可切换到全部、低置信或竖排。"
        case .vertical:
            return "当前没有竖排文字块；可切换到全部查看所有 OCR 结果。"
        }
    }

    private func filterTitle(_ filter: ImageOCRReviewFilter) -> String {
        switch filter {
        case .all:
            "全部 \(store.imageTranslationBlocks.count)"
        case .needsReview:
            "待复查 \(reviewRequiredBlocks.count)"
        case .lowConfidence:
            "低置信 \(ImageOCRReviewFilter.lowConfidence.blocks(from: store.imageTranslationBlocks).count)"
        case .unknownDirection:
            "方向待定 \(ImageOCRReviewFilter.unknownDirection.blocks(from: store.imageTranslationBlocks).count)"
        case .vertical:
            "竖排 \(ImageOCRReviewFilter.vertical.blocks(from: store.imageTranslationBlocks).count)"
        }
    }

    private func toggleSelection(of blockID: UUID) {
        if selectedImageTranslationBlockID == blockID {
            selectedImageTranslationBlockID = nil
            moveReviewAccessibilityFocus(to: reviewRowAccessibilityFocusID(blockID))
        } else {
            selectedImageTranslationBlockID = blockID
            revealPreview()
            moveReviewAccessibilityFocus(to: reviewPreviewAccessibilityFocusID(blockID))
        }
    }

    private func beginCorrection(of block: ImageTranslationBlock) {
        guard canModifyImageTranslation,
              store.imageTranslationBlocks.contains(where: { $0.id == block.id }) else {
            return
        }
        imageTranslationCorrectionFocusOrigin = .row
        selectedImageTranslationBlockID = block.id
        moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(
            to: reviewRowAccessibilityFocusID(block.id)
        )
        editingImageTranslationBlock = block
    }

    private func beginCorrectionFromFocusPreview(of block: ImageTranslationBlock) {
        guard canModifyImageTranslation,
              store.imageTranslationBlocks.contains(where: { $0.id == block.id }) else {
            return
        }
        imageTranslationCorrectionFocusOrigin = .preview
        selectedImageTranslationBlockID = block.id
        moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(
            to: reviewPreviewAccessibilityFocusID(block.id)
        )
        editingImageTranslationBlock = block
    }

    private func requestVisionOCRRestore(for block: ImageTranslationBlock) {
        guard store.imageTranslationCorrectedBlockIDs.contains(block.id),
              canModifyImageTranslation else {
            return
        }
        restoreConfirmationBlock = block
    }

    private func confirmVisionOCRRestore(_ block: ImageTranslationBlock) {
        guard restoreConfirmationBlock?.id == block.id,
              restoreVisionOCR(for: block.id) else { return }
        moveReviewAccessibilityFocusAfterRestoreConfirmationDismissal(
            to: reviewRowAccessibilityFocusID(block.id)
        )
    }

    @discardableResult
    private func restoreVisionOCR(for blockID: UUID) -> Bool {
        guard store.restoreImageTranslationBlockToVisionOCR(blockID) else { return false }
        selectedImageTranslationBlockID = blockID
        return true
    }

    @discardableResult
    private func setImageTranslationBlockDirection(
        _ direction: ImageTextDirection?,
        for blockID: UUID,
        focusInPreview: Bool,
        deferFocusUntilCorrectionSheetDismissal: Bool = false
    ) -> Bool {
        guard canModifyImageTranslation,
              store.setImageTranslationBlockDirectionOverride(blockID, direction: direction) else {
            return false
        }
        let focusID: String
        if visibleImageTranslationBlocks.contains(where: { $0.id == blockID }) {
            selectedImageTranslationBlockID = blockID
            focusID = focusInPreview
                ? reviewPreviewAccessibilityFocusID(blockID)
                : reviewRowAccessibilityFocusID(blockID)
        } else {
            // A direction override can immediately remove a block from the
            // active filter. Never retain a selection or VoiceOver target for
            // a row that no longer exists in the current result list.
            selectedImageTranslationBlockID = nil
            focusID = reviewFocusIDAfterHiddenDirectionBlock()
        }

        if deferFocusUntilCorrectionSheetDismissal {
            moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(to: focusID)
        } else {
            moveReviewAccessibilityFocus(to: focusID)
        }
        return true
    }

    private func reviewFocusIDAfterHiddenDirectionBlock() -> String {
        if let firstVisibleBlock = visibleImageTranslationBlocks.first {
            return reviewRowAccessibilityFocusID(firstVisibleBlock.id)
        }
        if reviewFilter == .needsReview, reviewCompletedBlockCount > 0 {
            return Self.reviewCompletionAccessibilityFocusID
        }
        if reviewFilter == .all {
            return Self.reviewFilterAccessibilityFocusID
        }
        return Self.reviewFilterEmptyAccessibilityFocusID
    }

    private func isVisibleReviewBlockFocusID(_ focusID: String) -> Bool {
        visibleImageTranslationBlocks.contains { block in
            focusID == reviewRowAccessibilityFocusID(block.id)
                || focusID == reviewPreviewAccessibilityFocusID(block.id)
        }
    }

    private func focusAfterHiddenCorrectionSheetTargetIfNeeded(_ focusID: String) -> Bool {
        guard !isVisibleReviewBlockFocusID(focusID) else { return false }
        // Completion, empty, filter, and ignored-row targets are independent
        // accessibility nodes and should pass through unchanged.
        let isReviewBlockID = focusID.hasPrefix("image-review-row-")
            || focusID.hasPrefix("image-review-preview-")
        guard isReviewBlockID else { return false }
        selectedImageTranslationBlockID = nil
        moveReviewAccessibilityFocus(to: reviewFocusIDAfterHiddenDirectionBlock())
        return true
    }

    @discardableResult
    private func ignoreImageTranslationBlock(_ block: ImageTranslationBlock) -> Bool {
        let activeBlocks = store.imageTranslationBlocks
        guard let activeIndex = activeBlocks.firstIndex(where: { $0.id == block.id }) else {
            return false
        }

        let filteredBlocksBeforeMutation = visibleImageTranslationBlocks
        let nextFilteredBlockID = filteredBlocksBeforeMutation.firstIndex(where: { $0.id == block.id }).flatMap { index in
            filteredBlocksBeforeMutation.dropFirst(index + 1).first?.id
                ?? filteredBlocksBeforeMutation[..<index].last?.id
        }

        let nextActiveBlockID = activeBlocks.dropFirst(activeIndex + 1).first?.id
            ?? activeBlocks[..<activeIndex].last?.id
        let pendingBlocks = reviewRequiredBlocks
        let nextReviewBlockID = pendingBlocks.firstIndex(where: { $0.id == block.id }).flatMap { index in
            pendingBlocks.dropFirst(index + 1).first?.id
                ?? pendingBlocks[..<index].last?.id
        }

        guard store.ignoreImageTranslationBlock(block.id) else { return false }
        imageTranslationCorrectionFocusOrigin = nil

        if store.imageTranslationBlocks.isEmpty {
            selectedImageTranslationBlockID = nil
            moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(
                to: Self.imageIgnoredBlocksEmptyAccessibilityFocusID
            )
        } else if reviewFilter == .needsReview {
            let nextBlockID = nextReviewBlockID.flatMap { candidate in
                reviewRequiredBlocks.contains(where: { $0.id == candidate }) ? candidate : nil
            } ?? reviewRequiredBlocks.first?.id
            selectedImageTranslationBlockID = nextBlockID
            moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(
                to: nextBlockID.map(reviewRowAccessibilityFocusID)
                    ?? ignoredRowAccessibilityFocusID(block.id)
            )
        } else {
            let fallbackActiveBlockID = reviewFilter == .all
                ? nextActiveBlockID.flatMap { candidate in
                    store.imageTranslationBlocks.contains(where: { $0.id == candidate }) ? candidate : nil
                }
                : nil
            let nextBlockID = nextFilteredBlockID.flatMap { candidate in
                visibleImageTranslationBlocks.contains(where: { $0.id == candidate }) ? candidate : nil
            } ?? fallbackActiveBlockID
            selectedImageTranslationBlockID = nextBlockID
            moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(
                to: nextBlockID.map(reviewRowAccessibilityFocusID)
                    ?? ignoredRowAccessibilityFocusID(block.id)
            )
        }
        return true
    }

    private func restoreIgnoredImageTranslationBlock(_ block: ImageTranslationBlock) {
        guard canModifyImageTranslation,
              store.restoreIgnoredImageTranslationBlock(block.id) else { return }
        let nextFilter = ImageOCRResultSummary.requiresReview(block) ? ImageOCRReviewFilter.needsReview : .all
        prepareReviewFilterChange(
            to: nextFilter,
            focusID: reviewRowAccessibilityFocusID(block.id)
        )
        selectedImageTranslationBlockID = block.id
        revealPreview()
        moveReviewAccessibilityFocus(to: reviewRowAccessibilityFocusID(block.id))
    }

    private func requestRestoreAllIgnoredImageTranslationBlocks() {
        guard canModifyImageTranslation,
              !store.imageTranslationIgnoredBlocks.isEmpty else { return }
        showRestoreAllIgnoredConfirmation = true
    }

    private func restoreAllIgnoredImageTranslationBlocks() {
        guard canModifyImageTranslation else { return }
        let restoredBlockIDs = store.restoreAllIgnoredImageTranslationBlocks()
        guard let firstRestoredBlockID = restoredBlockIDs.first else { return }
        let focusID = reviewRowAccessibilityFocusID(firstRestoredBlockID)
        selectedImageTranslationBlockID = firstRestoredBlockID
        prepareReviewFilterChange(to: .all, focusID: focusID)
        moveReviewAccessibilityFocus(to: focusID)
    }

    private func completeReviewAfterCorrection(_ blockID: UUID) {
        guard store.imageTranslationBlocks.contains(where: { $0.id == blockID }) else {
            imageTranslationCorrectionFocusOrigin = nil
            return
        }
        imageTranslationCorrectionFocusOrigin = nil
        let shouldAdvanceReviewQueue = reviewFilter == .needsReview
            && allReviewRequiredBlocks.contains(where: { $0.id == blockID })
            && store.imageTranslationReviewedBlockIDs.contains(blockID)
        guard shouldAdvanceReviewQueue else {
            moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(
                to: reviewRowAccessibilityFocusID(blockID)
            )
            return
        }

        let nextBlockID = reviewRequiredBlocks.first?.id
        selectedImageTranslationBlockID = nextBlockID
        moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(
            to: nextBlockID.map(reviewRowAccessibilityFocusID)
                ?? Self.reviewCompletionAccessibilityFocusID
        )
    }

    private func selectBlockFromPreview(_ blockID: UUID) {
        if selectedImageTranslationBlockID == blockID {
            selectedImageTranslationBlockID = nil
            moveReviewAccessibilityFocus(to: reviewRowAccessibilityFocusID(blockID))
            return
        }
        if !visibleImageTranslationBlocks.contains(where: { $0.id == blockID }) {
            prepareReviewFilterChange(
                to: .all,
                focusID: reviewPreviewAccessibilityFocusID(blockID)
            )
        }
        selectedImageTranslationBlockID = blockID
        moveReviewAccessibilityFocus(to: reviewPreviewAccessibilityFocusID(blockID))
    }

    private func closeImageTranslationFocusPreview() {
        guard let selectedImageTranslationBlockID else { return }
        self.selectedImageTranslationBlockID = nil
        moveReviewAccessibilityFocus(to: reviewRowAccessibilityFocusID(selectedImageTranslationBlockID))
    }

    private func beginReviewQueue() {
        guard canReviewImageTranslation,
              let firstBlockID = reviewRequiredBlocks.first?.id else { return }
        let retainedBlockID = selectedImageTranslationBlockID.flatMap { selectedBlockID in
            reviewRequiredBlocks.contains(where: { $0.id == selectedBlockID }) ? selectedBlockID : nil
        }
        let targetBlockID = retainedBlockID ?? firstBlockID
        prepareReviewFilterChange(
            to: .needsReview,
            focusID: reviewPreviewAccessibilityFocusID(targetBlockID)
        )
        selectedImageTranslationBlockID = targetBlockID
        revealPreview()
        moveReviewAccessibilityFocus(to: reviewPreviewAccessibilityFocusID(targetBlockID))
    }

    private func toggleReviewCompletion(_ blockID: UUID, focusInPreview: Bool) {
        guard canReviewImageTranslation,
              allReviewRequiredBlocks.contains(where: { $0.id == blockID }) else { return }
        if store.reopenImageTranslationBlockReview(blockID) {
            let focusID = focusInPreview
                ? reviewPreviewAccessibilityFocusID(blockID)
                : reviewRowAccessibilityFocusID(blockID)
            prepareReviewFilterChange(to: .needsReview, focusID: focusID)
            selectedImageTranslationBlockID = blockID
            moveReviewAccessibilityFocus(
                to: focusID
            )
            return
        }

        let pendingBlocks = reviewRequiredBlocks
        guard let currentIndex = pendingBlocks.firstIndex(where: { $0.id == blockID }) else { return }
        let nextBlockID = pendingBlocks.dropFirst(currentIndex + 1).first?.id
            ?? pendingBlocks[..<currentIndex].last?.id
        guard store.markImageTranslationBlockReviewed(blockID) else { return }
        let nextFocusID = nextBlockID.map {
            focusInPreview
                ? reviewPreviewAccessibilityFocusID($0)
                : reviewRowAccessibilityFocusID($0)
        } ?? Self.reviewCompletionAccessibilityFocusID
        prepareReviewFilterChange(to: .needsReview, focusID: nextFocusID)
        selectedImageTranslationBlockID = nextBlockID
        moveReviewAccessibilityFocus(to: nextFocusID)
    }

    private func restartReviewQueue() {
        guard canReviewImageTranslation,
              let firstBlockID = allReviewRequiredBlocks.first?.id else { return }
        store.resetImageTranslationReviewProgress()
        prepareReviewFilterChange(
            to: .needsReview,
            focusID: reviewPreviewAccessibilityFocusID(firstBlockID)
        )
        selectedImageTranslationBlockID = firstBlockID
        revealPreview()
        moveReviewAccessibilityFocus(to: reviewPreviewAccessibilityFocusID(firstBlockID))
    }

    private func reviewRowAccessibilityFocusID(_ blockID: UUID) -> String {
        "image-review-row-\(blockID.uuidString)"
    }

    private func reviewPreviewAccessibilityFocusID(_ blockID: UUID) -> String {
        "image-review-preview-\(blockID.uuidString)"
    }

    private func ignoredRowAccessibilityFocusID(_ blockID: UUID) -> String {
        "image-ignored-row-\(blockID.uuidString)"
    }

    private func moveReviewAccessibilityFocusAfterRestoreConfirmationDismissal(to focusID: String?) {
        pendingRestoreConfirmationDismissalFocusID = focusID
        pendingRestoreConfirmationDismissalRevision = store.imageTranslationRevision
    }

    private func applyPendingRestoreConfirmationDismissalFocus() {
        guard let focusID = pendingRestoreConfirmationDismissalFocusID,
              pendingRestoreConfirmationDismissalRevision == store.imageTranslationRevision else {
            clearPendingRestoreConfirmationDismissalFocus()
            return
        }
        clearPendingRestoreConfirmationDismissalFocus()
        moveReviewAccessibilityFocus(to: focusID)
    }

    private func clearPendingRestoreConfirmationDismissalFocus() {
        pendingRestoreConfirmationDismissalFocusID = nil
        pendingRestoreConfirmationDismissalRevision = nil
    }

    private func moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(to focusID: String?) {
        pendingCorrectionSheetDismissalFocusID = focusID
        pendingCorrectionSheetDismissalRevision = store.imageTranslationRevision
    }

    private func applyPendingCorrectionSheetDismissalFocus() {
        guard let focusID = pendingCorrectionSheetDismissalFocusID,
              pendingCorrectionSheetDismissalRevision == store.imageTranslationRevision else {
            clearPendingCorrectionSheetDismissalFocus()
            imageTranslationCorrectionFocusOrigin = nil
            return
        }
        clearPendingCorrectionSheetDismissalFocus()
        imageTranslationCorrectionFocusOrigin = nil
        if focusAfterHiddenCorrectionSheetTargetIfNeeded(focusID) {
            return
        }
        moveReviewAccessibilityFocus(to: focusID)
    }

    private func clearPendingCorrectionSheetDismissalFocus() {
        pendingCorrectionSheetDismissalFocusID = nil
        pendingCorrectionSheetDismissalRevision = nil
    }

    private func moveReviewAccessibilityFocus(to focusID: String?) {
        let revision = store.imageTranslationRevision
        reviewAccessibilityFocusRequestID &+= 1
        let requestID = reviewAccessibilityFocusRequestID
        Task { @MainActor in
            await Task.yield()
            guard revision == store.imageTranslationRevision,
                  requestID == reviewAccessibilityFocusRequestID else { return }
            reviewAccessibilityFocusID = focusID
        }
    }

    private var selectedVisibleBlockIndex: Int? {
        guard let selectedImageTranslationBlockID else { return nil }
        return visibleImageTranslationBlocks.firstIndex(where: { $0.id == selectedImageTranslationBlockID })
    }

    private var selectedBlockPositionText: String {
        guard let selectedVisibleBlockIndex else { return "" }
        return "\(selectedVisibleBlockIndex + 1) / \(visibleImageTranslationBlocks.count)"
    }

    private var canSelectPreviousBlock: Bool {
        guard let selectedVisibleBlockIndex else { return false }
        return selectedVisibleBlockIndex > visibleImageTranslationBlocks.startIndex
    }

    private var canSelectNextBlock: Bool {
        guard let selectedVisibleBlockIndex else { return false }
        return selectedVisibleBlockIndex < visibleImageTranslationBlocks.index(before: visibleImageTranslationBlocks.endIndex)
    }

    private func selectAdjacentBlock(offset: Int) {
        guard let selectedVisibleBlockIndex else { return }
        let targetIndex = selectedVisibleBlockIndex + offset
        guard visibleImageTranslationBlocks.indices.contains(targetIndex) else { return }
        let targetBlockID = visibleImageTranslationBlocks[targetIndex].id
        selectedImageTranslationBlockID = targetBlockID
        moveReviewAccessibilityFocus(to: reviewPreviewAccessibilityFocusID(targetBlockID))
    }

    private func clearHiddenReviewSelection() {
        guard let selectedImageTranslationBlockID,
              !visibleImageTranslationBlocks.contains(where: { $0.id == selectedImageTranslationBlockID }) else {
            return
        }
        self.selectedImageTranslationBlockID = nil
        let nextFocusID = visibleImageTranslationBlocks.first.map {
            reviewRowAccessibilityFocusID($0.id)
        } ?? (reviewCompletedBlockCount > 0
            ? Self.reviewCompletionAccessibilityFocusID
            : Self.reviewFilterAccessibilityFocusID)
        moveReviewAccessibilityFocus(to: nextFocusID)
    }

    private func focusEmptyReviewStateIfNeeded() {
        guard !store.imageTranslationBlocks.isEmpty,
              visibleImageTranslationBlocks.isEmpty,
              reviewFilter != .all else { return }
        let focusID = reviewFilter == .needsReview && reviewCompletedBlockCount > 0
            ? Self.reviewCompletionAccessibilityFocusID
            : Self.reviewFilterEmptyAccessibilityFocusID
        moveReviewAccessibilityFocus(to: focusID)
    }

    private func focusReviewFilterResultIfNeeded() {
        guard !store.imageTranslationBlocks.isEmpty,
              let firstVisibleBlock = visibleImageTranslationBlocks.first else {
            return
        }
        let focusID = reviewRowAccessibilityFocusID(firstVisibleBlock.id)
        moveReviewAccessibilityFocus(to: focusID)
    }

    private func focusImageTranslationRetryCompletionIfNeeded(_ generation: Int) {
        let revision = store.imageTranslationRevision
        Task { @MainActor in
            await Task.yield()
            guard revision == store.imageTranslationRevision,
                  generation == store.imageTranslationBlockRetryCompletionGeneration,
                  store.imageTranslationState == .translated else { return }
            focusImageTranslationTerminalStateIfNeeded()
        }
    }

    private func requestImageTranslationRerecognition(
        _ blockID: UUID,
        focusOrigin: ImageTranslationRerecognitionFocusOrigin
    ) {
        guard store.canRerecognizeImageTranslationBlock(blockID) else { return }
        imageTranslationRerecognitionFocusOrigin = focusOrigin
        store.rerecognizeImageTranslationBlock(blockID)
    }

    private func focusImageTranslationRerecognitionCompletionIfNeeded(
        _ generation: Int,
        blockID: UUID
    ) {
        let revision = store.imageTranslationRevision
        let focusOrigin = imageTranslationRerecognitionFocusOrigin ?? .row
        Task { @MainActor in
            await Task.yield()
            guard revision == store.imageTranslationRevision,
                  generation == store.imageTranslationBlockRerecognitionCompletionGeneration,
                  store.imageTranslationBlockRerecognitionCompletedBlockID == blockID,
                  store.imageTranslationState == .translated || store.imageTranslationState == .failed else {
                return
            }

            if visibleImageTranslationBlocks.contains(where: { $0.id == blockID }) {
                let focusID: String
                switch focusOrigin {
                case .row:
                    focusID = reviewRowAccessibilityFocusID(blockID)
                case .preview:
                    focusID = reviewPreviewAccessibilityFocusID(blockID)
                }
                imageTranslationRerecognitionFocusOrigin = nil
                moveReviewAccessibilityFocus(to: focusID)
                return
            }

            imageTranslationRerecognitionFocusOrigin = nil
            if selectedImageTranslationBlockID == blockID {
                selectedImageTranslationBlockID = nil
            }
            clearHiddenReviewSelection()
            if visibleImageTranslationBlocks.isEmpty {
                focusEmptyReviewStateIfNeeded()
            } else {
                focusReviewFilterResultIfNeeded()
            }
        }
    }

    private func focusImageTranslationRerecognitionFailureIfNeeded(_ generation: Int) {
        let revision = store.imageTranslationRevision
        Task { @MainActor in
            await Task.yield()
            guard revision == store.imageTranslationRevision,
                  generation == store.imageTranslationBlockRerecognitionFailureGeneration,
                  store.imageTranslationRerecognizingBlockID == nil,
                  store.imageTranslationState == .translated || store.imageTranslationState == .failed else {
                return
            }
            imageTranslationRerecognitionFocusOrigin = nil
            moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)
        }
    }

    private func focusImageTranslationTerminalStateIfNeeded() {
        let revision = store.imageTranslationRevision
        Task { @MainActor in
            await Task.yield()
            guard revision == store.imageTranslationRevision else { return }
            if store.imageTranslationBlocks.isEmpty {
                if store.imageTranslationState == .translated,
                   store.imageTranslationData != nil,
                   !store.imageTranslationIgnoredBlocks.isEmpty {
                    moveReviewAccessibilityFocus(to: Self.imageIgnoredBlocksEmptyAccessibilityFocusID)
                } else if store.imageTranslationState == .translated,
                          store.imageTranslationData != nil {
                    moveReviewAccessibilityFocus(to: Self.imageResultEmptyAccessibilityFocusID)
                } else {
                    moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)
                }
            } else {
                focusReviewFilterResultIfNeeded()
            }
        }
    }

    private func prepareReviewFilterChange(
        to nextFilter: ImageOCRReviewFilter,
        focusID: String?,
        suppressResultFocus: Bool = false
    ) {
        guard reviewFilter != nextFilter else {
            pendingReviewFilterFocusID = nil
            suppressNextReviewFilterResultFocus = false
            return
        }
        pendingReviewFilterFocusID = focusID
        suppressNextReviewFilterResultFocus = suppressResultFocus
        reviewFilter = nextFilter
    }

    private var reviewFilterEmptyStateAccessibilityValue: String {
        "筛选为 \(reviewFilter.rawValue)，显示 0 个，共 \(store.imageTranslationBlocks.count) 个文字块；\(filterEmptyStateDetail)"
    }

    private var statusTone: AppStatusTone {
        switch store.imageTranslationShareState {
        case .preparing: return .active
        case .failed: return .danger
        case .idle: break
        }
        switch store.imageTranslationExportRenderState {
        case .rendering: return .active
        case .failed: return .danger
        case .idle: break
        }
        switch store.imageTranslationState {
        case .idle: return .neutral
        case .loading, .recognizing, .translating: return .active
        case .translated: return .success
        case .failed: return .danger
        }
    }

    @ViewBuilder
    private func imageStatusAccessibilityRow<Content: View>(_ content: Content) -> some View {
        if hasImageShareFailure {
            content
                .accessibilityAction(named: "重试分享") {
                    shareResult()
                }
        } else if hasImageExportRenderFailure {
            content
                .accessibilityAction(named: "重试导出") {
                    store.retryImageTranslationExportRender()
                }
        } else if canRetryFromImageStatus {
            content
                .accessibilityAction(named: "重试当前图片") {
                    guard store.canRetryImageTranslation else { return }
                    store.retryImageTranslation()
                }
        } else {
            content
        }
    }

    private var hasImageShareFailure: Bool {
        if case .failed = store.imageTranslationShareState {
            return true
        }
        return false
    }

    private var hasImageExportRenderFailure: Bool {
        if case .failed = store.imageTranslationExportRenderState {
            return true
        }
        return false
    }

    private var canRetryFromImageStatus: Bool {
        store.canRetryImageTranslation && store.imageTranslationRetryLanguageSummary == nil
    }

    private var statusTitle: String {
        switch store.imageTranslationShareState {
        case .preparing: return "正在准备分享"
        case .failed: return "分享准备失败"
        case .idle: break
        }
        switch store.imageTranslationExportRenderState {
        case .rendering: return "正在更新导出图"
        case .failed: return "导出图生成失败"
        case .idle: return store.imageTranslationProgressTitle
        }
    }

    private var statusDetail: String {
        switch store.imageTranslationShareState {
        case .preparing: return "正在创建可供系统分享的图片文件"
        case .failed(let message): return message
        case .idle: break
        }
        switch store.imageTranslationExportRenderState {
        case .rendering: return "正在按所选覆盖方式重新生成图片"
        case .failed(let message): return message
        case .idle: return store.imageTranslationMessage
        }
    }

    private var imageStatusAccessibilityValue: String {
        "\(statusTitle)：\(statusDetail)"
    }

    private var imageStatusAccessibilityHint: String {
        switch store.imageTranslationShareState {
        case .preparing:
            return "正在准备分享；完成后会打开系统分享"
        case .failed:
            return "分享准备失败；可在此状态上执行“重试分享”，也可以关闭分享并重新导出"
        case .idle:
            break
        }

        switch store.imageTranslationExportRenderState {
        case .rendering:
            return "正在按所选覆盖方式更新导出图；完成后可继续修改或分享"
        case .failed:
            return "导出图生成失败；可在此状态上执行“重试导出”，不会重新识别或翻译图片"
        case .idle:
            break
        }

        switch store.imageTranslationState {
        case .idle:
            if store.imageTranslationData == nil {
                return "选择照片或图片文件后开始本机 OCR 与翻译"
            }
            return store.canRetryImageTranslation && store.imageTranslationRetryLanguageSummary == nil
                ? "当前图片尚未完成本次处理；可以在此状态上执行“重试当前图片”，也可以选择新图片"
                : "当前图片处理已停止；可以选择新图片"
        case .loading:
            return "正在读取图片；可以取消或选择新图片"
        case .recognizing:
            return "正在使用本机 OCR；可以取消或选择新图片"
        case .translating:
            return "正在逐块翻译；仍可查看和定位，完成后可修正文字或更新复查"
        case .translated:
            return "图片翻译完成；可以修正文字、更新复查、切换覆盖方式或导出"
        case .failed:
            return store.canRetryImageTranslation && store.imageTranslationRetryLanguageSummary == nil
                ? "图片翻译失败；可以在此状态上执行“重试当前图片”，也可以选择新图片"
                : "图片翻译失败；当前图片文件不可重试，请选择新图片"
        }
    }

    private var isRunning: Bool {
        switch store.imageTranslationState {
        case .loading, .recognizing, .translating: true
        case .idle, .translated, .failed: false
        }
    }

    private var isRenderingExport: Bool {
        store.imageTranslationExportRenderState == .rendering
    }

    private var canModifyImageTranslation: Bool {
        store.imageTranslationState == .translated && !isRenderingExport
    }

    private var canReviewImageTranslation: Bool {
        store.imageTranslationState == .translated
    }

    private var imageModificationUnavailableDetail: String {
        if isRenderingExport {
            return "正在按当前覆盖方式更新导出图；完成后可修正文字、恢复 OCR 结果或切换覆盖方式。"
        }
        switch store.imageTranslationState {
        case .idle:
            return "请先完成图片翻译，再修正文字、恢复 OCR 结果或切换覆盖方式。"
        case .loading, .recognizing:
            return "正在准备图片识别；翻译完成后可修正文字、恢复 OCR 结果或切换覆盖方式。"
        case .translating:
            return "正在逐块翻译；可继续查看和定位文字块，全部完成后才能修改图片结果。"
        case .translated:
            return "导出图更新完成后可修正文字、恢复 OCR 结果或切换覆盖方式。"
        case .failed:
            return "图片翻译尚未完整完成；请重试成功后再修改图片结果。"
        }
    }

    private var imageTranslationBlockRetryUnavailableHint: String {
        switch store.imageTranslationState {
        case .failed:
            return "只重新翻译此空白文字块，不会重新运行 Vision OCR；其他已完成译文会保留。"
        case .translated:
            return "只重新翻译此空白文字块，不会重新运行 Vision OCR。"
        case .loading, .recognizing, .translating:
            return "当前图片正在处理；完成后可单独重试空白译文块。"
        case .idle:
            return "请先完成图片识别，再单独重试空白译文块。"
        }
    }

    private var imageReviewUnavailableDetail: String {
        switch store.imageTranslationState {
        case .idle:
            return "请先完成图片翻译，再开始、重启或更新复查进度。"
        case .loading, .recognizing:
            return "正在准备图片识别；翻译完成后可开始、重启或更新复查进度。"
        case .translating:
            return "正在逐块翻译；可继续查看和定位文字块，全部完成后才能更新复查进度。"
        case .translated:
            return "图片翻译完成后可更新复查进度。"
        case .failed:
            return "图片翻译尚未完整完成；请重试成功后再更新复查进度。"
        }
    }

    private var imageActionLockTitle: String {
        isRenderingExport ? "图片编辑暂时锁定" : "图片操作暂时锁定"
    }

    private var imageActionLockDetail: String? {
        guard !store.imageTranslationBlocks.isEmpty else { return nil }
        if !canModifyImageTranslation && !canReviewImageTranslation {
            switch store.imageTranslationState {
            case .idle:
                return "请先完成图片翻译，再修改图片结果或更新复查进度。"
            case .loading, .recognizing:
                return "正在准备图片识别；翻译完成后可修改图片结果或更新复查进度。"
            case .translating:
                return "正在逐块翻译；可继续查看和定位文字块，全部完成后才能修改图片结果或更新复查进度。"
            case .translated:
                break
            case .failed:
                return "图片翻译尚未完整完成；请重试成功后再修改图片结果或更新复查进度。"
            }
        }
        if !canModifyImageTranslation {
            return imageModificationUnavailableDetail
        }
        if !canReviewImageTranslation {
            return imageReviewUnavailableDetail
        }
        return nil
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard let selectionID = imageFileSelectionID else { return }
        imageFileSelectionID = nil
        store.handleSelectedImageFile(result, selectionID: selectionID)
    }

    private func loadSelectedPhoto(_ oldItem: PhotosPickerItem?, _ newItem: PhotosPickerItem?) {
        guard let newItem else { return }
        imageFileSelectionID = nil
        selectedPhotoItem = nil
        store.translateImageTransfer(
            filename: "photo-library-image.png"
        ) {
            try await newItem.loadTransferable(type: Data.self)
        }
    }

    private func shareResult() {
        guard store.imageTranslationShareState != .preparing else { return }
        let presentationID = UUID()
        sharePresentationID = presentationID
        Task {
            let preparedURL = await store.prepareImageTranslationShareURL()
            guard sharePresentationID == presentationID else { return }
            shareURL = preparedURL
        }
    }

    private func finishSharing() {
        sharePresentationID = UUID()
        shareURL = nil
        store.finishImageTranslationSharing()
    }
}

private struct ImageSourceLanguageControl: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var showLockedLanguage = false

    var body: some View {
        Menu {
            ForEach(SupportedLanguage.allCases) { language in
                Button {
                    store.selectImageSourceLanguage(language)
                    if !store.isProUnlocked {
                        showLockedLanguage = true
                    }
                } label: {
                    Label(
                        language.rawValue,
                        systemImage: menuSymbol(for: language)
                    )
                }
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.control) {
                Label("输入语言", systemImage: "text.viewfinder")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text(store.imageTranslationSelectedSourceLanguage.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.appTextSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget)
            .padding(.horizontal, AppTheme.Spacing.control)
            .foregroundStyle(Color.appTextPrimary)
            .background(Color.appCanvas, in: .rect(cornerRadius: AppTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .disabled(isRunning)
        .accessibilityLabel("输入语言")
        .accessibilityValue(store.imageTranslationSelectedSourceLanguage.rawValue)
        .accessibilityHint(imageSourceLanguageAccessibilityHint)
        .alert("Pro 功能", isPresented: $showLockedLanguage) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(store.dataTransferMessage)
        }
    }

    private var isRunning: Bool {
        switch store.imageTranslationState {
        case .loading, .recognizing, .translating: true
        case .idle, .translated, .failed: false
        }
    }

    private var imageSourceLanguageAccessibilityHint: String {
        if isRunning {
            return "图片正在读取、识别或翻译；完成或取消后才能更改输入语言"
        }
        if !store.isProUnlocked {
            return "图片输入语言设置需要 Pro；不会修改当前图片或文本页语言"
        }
        if store.imageTranslationData == nil {
            return "输入语言设置已解锁；选择图片后可设置图片 OCR 输入语言"
        }
        switch store.imageTranslationState {
        case .translated:
            return "输入语言设置已解锁；已完成的图片会重新识别和翻译当前图片；选回当前内容语言会撤销待重试更改"
        case .idle, .failed:
            return "输入语言设置已解锁；失败或取消后会在重试时使用新语言；选回当前内容语言会撤销待重试更改"
        case .loading, .recognizing, .translating:
            return "图片正在读取、识别或翻译；完成或取消后才能更改输入语言"
        }
    }

    private func menuSymbol(for language: SupportedLanguage) -> String {
        if store.imageTranslationSelectedSourceLanguage == language {
            return "checkmark.circle.fill"
        }
        return store.isProUnlocked ? "circle" : "lock.fill"
    }
}

private struct ImageTargetLanguageControl: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var showLockedLanguage = false

    var body: some View {
        Menu {
            ForEach(store.availableTargetLanguages) { language in
                Button {
                    store.selectImageTargetLanguage(language)
                    if !store.canUseLanguage(language) {
                        showLockedLanguage = true
                    }
                } label: {
                    Label(language.rawValue, systemImage: menuSymbol(for: language))
                }
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.control) {
                Label("目标语言", systemImage: "character.bubble")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text(store.imageTranslationSelectedTargetLanguage.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.appTextSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget)
            .padding(.horizontal, AppTheme.Spacing.control)
            .foregroundStyle(Color.appTextPrimary)
            .background(Color.appCanvas, in: .rect(cornerRadius: AppTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .disabled(isRunning)
        .accessibilityLabel("目标语言")
        .accessibilityValue(store.imageTranslationSelectedTargetLanguage.rawValue)
        .accessibilityHint(imageTargetLanguageAccessibilityHint)
        .alert("Pro 语言", isPresented: $showLockedLanguage) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(store.dataTransferMessage)
        }
    }

    private var isRunning: Bool {
        switch store.imageTranslationState {
        case .loading, .recognizing, .translating: true
        case .idle, .translated, .failed: false
        }
    }

    private var imageTargetLanguageAccessibilityHint: String {
        if isRunning {
            return "图片正在读取、识别或翻译；完成或取消后才能更改目标语言"
        }
        if store.imageTranslationData == nil {
            return "选择图片后可设置图片翻译目标语言"
        }
        switch store.imageTranslationState {
        case .translated:
            return "已完成的图片会重新翻译当前图片；选回当前内容语言会撤销待重试更改"
        case .idle, .failed:
            return "失败或取消后会在重试时使用新目标语言；选回当前内容语言会撤销待重试更改"
        case .loading, .recognizing, .translating:
            return "图片正在读取、识别或翻译；完成或取消后才能更改目标语言"
        }
    }

    private func menuSymbol(for language: SupportedLanguage) -> String {
        if store.imageTranslationSelectedTargetLanguage == language {
            return "checkmark.circle.fill"
        }
        return store.canUseLanguage(language) ? "circle" : "lock.fill"
    }
}

private struct ImageCommandBar: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @State private var showLockedImageTranslation = false
    @State private var showClearConfirmation = false
    let openImporter: () -> Void
    let shareResult: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.Spacing.control) { commands }
            VStack(spacing: AppTheme.Spacing.control) { commands }
        }
        .alert("Pro 功能", isPresented: $showLockedImageTranslation) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(store.dataTransferMessage)
        }
        .confirmationDialog(
            "清空图片翻译？",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空图片与翻译结果", role: .destructive, action: store.clearImageTranslation)
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除当前图片、识别结果、译文和导出文件。")
        }
    }

    @ViewBuilder private var commands: some View {
        if store.isProUnlocked {
            PhotoPickerCommand(
                title: store.imageTranslationData == nil ? "选择照片" : "更换照片",
                accessibilityHint: imageSelectionAccessibilityHint,
                selection: $selectedPhotoItem
            )

            AppSecondaryButton(title: "图片文件", systemImage: "folder", action: openImporter)
                .accessibilityHint(fileSelectionAccessibilityHint)
        } else {
            AppSecondaryButton(
                title: store.imageTranslationData == nil ? "选择照片" : "更换照片",
                systemImage: "lock.fill",
                action: requestImageTranslationAccess
            )
            .accessibilityHint("图片翻译需要 Pro；不会修改当前图片或文本页语言")
            AppSecondaryButton(
                title: "图片文件",
                systemImage: "lock.fill",
                action: requestImageTranslationAccess
            )
            .accessibilityHint("图片翻译需要 Pro；不会修改当前图片或文本页语言")
        }

        if isRunning {
            AppSecondaryButton(title: "取消", systemImage: "xmark.circle.fill", tone: .danger, action: store.cancelImageTranslation)
                .accessibilityHint("取消当前图片读取、OCR 或翻译；保留已载入图片以便重试")
        } else if store.canRetryImageTranslation {
            AppSecondaryButton(title: "重试", systemImage: "arrow.clockwise", tone: .warning, action: store.retryImageTranslation)
                .accessibilityHint("使用当前重试语言重新识别并翻译这张图片")
        }

        if store.canRerunImageRecognition {
            AppSecondaryButton(
                title: "重新识别",
                systemImage: "text.viewfinder",
                action: store.rerunImageRecognition
            )
            .accessibilityHint("使用当前图片语言重新运行 Vision OCR，并重新翻译识别到的文字")
        }

        if hasRenderFailure {
            AppSecondaryButton(
                title: "重试导出",
                systemImage: "arrow.clockwise.circle",
                tone: .warning,
                action: store.retryImageTranslationExportRender
            )
            .accessibilityHint("重新生成旁贴或覆盖导出图；不会重新识别或翻译图片")
        }

        if store.imageTranslationExportURL != nil {
            AppSecondaryButton(
                title: isPreparingShare ? "准备中" : "导出",
                systemImage: isPreparingShare ? "hourglass" : "square.and.arrow.up",
                tone: .success,
                action: shareResult
            )
            .disabled(isPreparingShare)
            .accessibilityHint(
                isPreparingShare
                    ? "导出图正在准备分享"
                    : "准备当前图片导出图并打开分享"
            )
        }

        if store.imageTranslationData != nil {
            AppIconButton(
                title: "清空图片翻译",
                systemImage: "trash",
                tone: .danger,
                action: requestClearImageTranslation
            )
            .accessibilityHint("请求确认后删除当前图片、识别结果、译文和导出文件")
        }
    }

    private var imageSelectionAccessibilityHint: String {
        if isRunning {
            return "选择新图片会取消当前图片读取、OCR 或翻译，并开始新的本机 OCR 与翻译"
        }
        return store.imageTranslationData == nil
            ? "从照片图库选择图片并开始本机 OCR 与翻译"
            : "更换当前图片并开始新的本机 OCR 与翻译"
    }

    private var fileSelectionAccessibilityHint: String {
        if isRunning {
            return "从文件选择新图片会取消当前图片读取、OCR 或翻译，并开始新的本机 OCR 与翻译"
        }
        if store.imageTranslationData == nil {
            return "从文件选择图片并开始本机 OCR 与翻译"
        }
        return "更换当前图片并开始新的本机 OCR 与翻译"
    }

    private var isRunning: Bool {
        switch store.imageTranslationState {
        case .loading, .recognizing, .translating: true
        case .idle, .translated, .failed: false
        }
    }

    private var isPreparingShare: Bool {
        store.imageTranslationShareState == .preparing
    }

    private var hasRenderFailure: Bool {
        if case .failed = store.imageTranslationExportRenderState {
            return true
        }
        return false
    }

    private func requestImageTranslationAccess() {
        showLockedImageTranslation = !store.requestImageTranslationAccess()
    }

    private func requestClearImageTranslation() {
        showClearConfirmation = true
    }
}

private struct PhotoPickerCommand: View {
    let title: String
    let accessibilityHint: String
    @Binding var selection: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            Label(title, systemImage: "photo.on.rectangle")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget)
                .padding(.horizontal, AppTheme.Spacing.control)
                .foregroundStyle(Color.appCanvas)
                .background(Color.appAccent, in: .rect(cornerRadius: AppTheme.Radius.control))
        }
        .accessibilityHint(accessibilityHint)
    }
}

private struct ImagePreviewRequestID: Hashable {
    let revision: Int
    let attempt: Int
}

private enum ImagePreviewPhase: Equatable {
    case empty
    case loading(revision: Int)
    case ready(revision: Int)
    case failed(revision: Int)
}

private struct ImageTranslationPreview: View {
    @EnvironmentObject private var store: TranslationSessionStore
    let selectedBlockID: UUID?
    let positionText: String
    let canSelectPrevious: Bool
    let canSelectNext: Bool
    let reviewedBlockIDs: Set<UUID>
    let canEdit: Bool
    let canReview: Bool
    let modificationUnavailableHint: String
    let reviewUnavailableHint: String
    let accessibilityFocus: AccessibilityFocusState<String?>.Binding
    let previewStatusAccessibilityFocusID: String
    let focusPreviewStatus: () -> Void
    let selectBlock: (UUID) -> Void
    let clearSelection: () -> Void
    let selectPrevious: () -> Void
    let selectNext: () -> Void
    let editBlock: (ImageTranslationBlock) -> Void
    let restoreVisionOCR: (ImageTranslationBlock) -> Void
    let setDirectionOverride: (ImageTextDirection?) -> Void
    let canRetryTranslation: (UUID) -> Bool
    let isRetryingTranslation: (UUID) -> Bool
    let retryTranslation: (UUID) -> Void
    let canRerecognize: (UUID) -> Bool
    let isRerecognizing: (UUID) -> Bool
    let rerecognize: (UUID) -> Void
    let toggleReviewCompletion: (UUID) -> Void
    @State private var previewImage: UIImage?
    @State private var previewRevision: Int?
    @State private var previewAttempt = 0
    @State private var previewPhase: ImagePreviewPhase = .empty

    var body: some View {
        Group {
            if let previewImage,
               previewRevision == store.imageTranslationRevision {
                GeometryReader { geometry in
                    let fittedSize = fittedImageSize(imageSize: previewImage.size, containerSize: geometry.size)
                    let origin = CGPoint(
                        x: (geometry.size.width - fittedSize.width) / 2,
                        y: (geometry.size.height - fittedSize.height) / 2
                    )

                    ZStack(alignment: .topLeading) {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .accessibilityHidden(true)

                        ForEach(store.imageTranslationBlocks) { block in
                            ImageTranslationOverlayBlock(
                                block: block,
                                mode: store.imageOverlayMode,
                                imageOrigin: origin,
                                imageSize: fittedSize,
                                isSelected: selectedBlockID == block.id,
                                isReviewCompleted: reviewedBlockIDs.contains(block.id),
                                isManuallyCorrected: store.imageTranslationCorrectedBlockIDs.contains(block.id),
                                select: { selectBlock(block.id) }
                            )
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if let selectedBlock = store.imageTranslationBlocks.first(where: { $0.id == selectedBlockID }) {
                            ImageTranslationFocusPreview(
                                previewImage: previewImage,
                                block: selectedBlock,
                                positionText: positionText,
                                canSelectPrevious: canSelectPrevious,
                                canSelectNext: canSelectNext,
                                isReviewRequired: ImageOCRResultSummary.requiresReview(selectedBlock),
                                isReviewCompleted: reviewedBlockIDs.contains(selectedBlock.id),
                                isManuallyCorrected: store.imageTranslationCorrectedBlockIDs.contains(selectedBlock.id),
                                canEdit: canEdit,
                                canReview: canReview,
                                modificationUnavailableHint: modificationUnavailableHint,
                                reviewUnavailableHint: reviewUnavailableHint,
                                canRetryTranslation: canRetryTranslation(selectedBlock.id),
                                isRetryingTranslation: isRetryingTranslation(selectedBlock.id),
                                retryTranslation: { retryTranslation(selectedBlock.id) },
                                canRerecognize: canRerecognize(selectedBlock.id),
                                isRerecognizing: isRerecognizing(selectedBlock.id),
                                rerecognize: { rerecognize(selectedBlock.id) },
                                retryUnavailableHint: canRetryTranslation(selectedBlock.id)
                                    ? "只重新翻译此文字块，不会重新运行 Vision OCR"
                                    : "当前文字块没有可重试的空白译文",
                                accessibilityFocus: accessibilityFocus,
                                close: clearSelection,
                                selectPrevious: selectPrevious,
                                selectNext: selectNext,
                                edit: { editBlock(selectedBlock) },
                                restoreVisionOCR: { restoreVisionOCR(selectedBlock) },
                                setDirectionOverride: { setDirectionOverride($0) },
                                toggleReviewCompletion: { toggleReviewCompletion(selectedBlock.id) }
                            )
                            .frame(
                                width: max(180, min(320, geometry.size.width - AppTheme.Spacing.control * 2)),
                                height: 180
                            )
                            .padding(AppTheme.Spacing.control)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("图片翻译预览")
                    .accessibilityValue(previewAccessibilityValue)
                    .accessibilityHint(previewAccessibilityHint)
                }
                .frame(minHeight: 360, idealHeight: 560, maxHeight: 720)
                .background(Color.black)
                .clipShape(.rect(cornerRadius: AppTheme.Radius.surface))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.surface)
                        .stroke(Color.appBorder, lineWidth: 1)
                }
            } else if store.imageTranslationData != nil {
                previewStatus
            } else {
                AppEmptyState(
                    title: "选择图片",
                    detail: "支持照片图库和图片文件，OCR 与翻译均在本机完成。",
                    systemImage: "photo.on.rectangle.angled"
                )
                .frame(minHeight: 360)
                .background(Color.appSurface)
                .clipShape(.rect(cornerRadius: AppTheme.Radius.surface))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("图片翻译预览")
                .accessibilityValue("当前没有图片")
                .accessibilityHint("从上方照片或图片文件按钮选择图片；图片会在本机执行 OCR、翻译和屏幕预览")
            }
        }
        .task(
            id: ImagePreviewRequestID(
                revision: store.imageTranslationRevision,
                attempt: previewAttempt
            )
        ) {
            let revision = store.imageTranslationRevision
            guard let data = store.imageTranslationData else {
                previewImage = nil
                previewRevision = nil
                previewPhase = .empty
                return
            }

            previewImage = nil
            previewRevision = nil
            previewPhase = .loading(revision: revision)
            guard let preview = await ImagePreviewService.makePreview(from: data) else {
                guard !Task.isCancelled,
                      revision == store.imageTranslationRevision else { return }
                previewPhase = .failed(revision: revision)
                focusPreviewStatus()
                return
            }
            guard !Task.isCancelled,
                  revision == store.imageTranslationRevision else {
                return
            }
            previewImage = UIImage(cgImage: preview.cgImage)
            previewRevision = revision
            previewPhase = .ready(revision: revision)
        }
    }

    @ViewBuilder private var previewStatus: some View {
        previewStatusAccessibilityActions(
            VStack(spacing: AppTheme.Spacing.control) {
                if previewFailedForCurrentRevision {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color.appWarning)
                    Text("预览生成失败")
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    Text("原图仍保留用于 OCR 与导出，可单独重试屏幕预览。")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)
                    AppSecondaryButton(
                        title: "重试预览",
                        systemImage: "arrow.clockwise",
                        tone: .warning,
                        action: retryPreview
                    )
                    .frame(maxWidth: 220)
                    .accessibilityHint("重新生成屏幕预览；不会重新识别或翻译图片")
                } else {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在准备预览")
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    Text("图片已载入，正在后台生成屏幕预览。")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(AppTheme.Spacing.section)
            .frame(maxWidth: .infinity, minHeight: 360)
            .background(Color.appSurface)
            .clipShape(.rect(cornerRadius: AppTheme.Radius.surface))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.surface)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(previewStatusAccessibilityLabel)
            .accessibilityValue(previewStatusAccessibilityValue)
            .accessibilityHint(previewStatusAccessibilityHint)
            .accessibilityFocused(
                accessibilityFocus,
                equals: previewStatusAccessibilityFocusID
            )
        )
    }

    @ViewBuilder
    private func previewStatusAccessibilityActions<Content: View>(_ content: Content) -> some View {
        if previewFailedForCurrentRevision {
            content
                .accessibilityAction(named: "重试预览") {
                    retryPreview()
                }
        } else {
            content
        }
    }

    private var previewFailedForCurrentRevision: Bool {
        previewPhase == .failed(revision: store.imageTranslationRevision)
    }

    private var previewStatusAccessibilityLabel: String {
        previewFailedForCurrentRevision ? "图片预览生成失败" : "正在准备图片预览"
    }

    private var previewStatusAccessibilityValue: String {
        previewFailedForCurrentRevision
            ? "原图仍保留用于 OCR 与导出；可以重试屏幕预览"
            : "图片已载入，正在后台生成屏幕预览"
    }

    private var previewStatusAccessibilityHint: String {
        previewFailedForCurrentRevision
            ? "可执行“重试预览”重新生成屏幕预览；不会重新识别或翻译图片"
            : "屏幕预览生成中；完成后可定位文字块，若生成失败可执行“重试预览”"
    }

    private var previewAccessibilityValue: String {
        let blocks = store.imageTranslationBlocks
        guard !blocks.isEmpty else {
            return "当前没有识别到文字块"
        }

        let reviewTotal = blocks.count(where: { ImageOCRResultSummary.requiresReview($0) })
        let reviewCompleted = blocks.count {
            ImageOCRResultSummary.requiresReview($0) && reviewedBlockIDs.contains($0.id)
        }
        var parts = ["识别到 \(blocks.count) 个文字块"]
        let geometryUnavailableCount = blocks.count {
            !ImageOCRGeometryPresentation.isLocatable(for: $0)
        }
        if geometryUnavailableCount > 0 {
            parts.append("定位不可用 \(geometryUnavailableCount) 个")
        }
        if reviewTotal > 0 {
            parts.append("待复查 \(max(0, reviewTotal - reviewCompleted)) 个")
        } else {
            parts.append("没有低置信或方向待定文字块")
        }

        if selectedBlockID != nil {
            parts.append(positionText.isEmpty ? "当前已定位文字块" : "当前定位 \(positionText)")
        } else {
            parts.append("尚未定位文字块")
        }
        return parts.joined(separator: "；")
    }

    private var previewAccessibilityHint: String {
        guard !store.imageTranslationBlocks.isEmpty else {
            return "当前没有可定位的 OCR 文字块"
        }
        let geometryUnavailableCount = store.imageTranslationBlocks.count {
            !ImageOCRGeometryPresentation.isLocatable(for: $0)
        }
        let operationHint: String
        if geometryUnavailableCount > 0 {
            operationHint = "点按文字块可定位；有效文字块可打开局部放大，另有 \(geometryUnavailableCount) 个文字块局部预览不可用"
        } else {
            operationHint = "点按文字块可定位并打开局部放大"
        }
        var unavailableDetails: [String] = []
        if !canEdit {
            unavailableDetails.append(modificationUnavailableHint)
        }
        if !canReview {
            unavailableDetails.append(reviewUnavailableHint)
        }
        guard !unavailableDetails.isEmpty else {
            return "\(operationHint)；当前图片已完成翻译，可修正文字或更新复查进度"
        }
        return "\(operationHint)；\(unavailableDetails.joined(separator: " "))"
    }

    private func retryPreview() {
        previewPhase = .loading(revision: store.imageTranslationRevision)
        previewAttempt += 1
        focusPreviewStatus()
    }

    private func fittedImageSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

private struct ImageTranslationBlockFocusCrop {
    let image: CGImage
    let normalizedRect: CGRect

    static func make(
        from sourceImage: CGImage,
        block: ImageTranslationBlock
    ) -> Self? {
        guard let normalizedRect = normalizedFocusRect(for: block) else {
            return nil
        }
        let sourceBounds = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(sourceImage.width),
            height: CGFloat(sourceImage.height)
        )
        let pixelRect = CGRect(
            x: normalizedRect.minX * sourceBounds.width,
            y: normalizedRect.minY * sourceBounds.height,
            width: normalizedRect.width * sourceBounds.width,
            height: normalizedRect.height * sourceBounds.height
        )
        .integral
        .intersection(sourceBounds)
        guard !pixelRect.isEmpty,
              let croppedImage = sourceImage.cropping(to: pixelRect) else {
            return nil
        }
        let effectiveRect = CGRect(
            x: pixelRect.minX / sourceBounds.width,
            y: pixelRect.minY / sourceBounds.height,
            width: pixelRect.width / sourceBounds.width,
            height: pixelRect.height / sourceBounds.height
        )
        return Self(image: croppedImage, normalizedRect: effectiveRect)
    }

    static func normalizedFocusRect(for block: ImageTranslationBlock) -> CGRect? {
        guard let box = block.boundingBox.normalizedToUnit() else {
            return nil
        }
        let sourceRect = CGRect(
            x: CGFloat(box.x),
            y: CGFloat(box.y),
            width: CGFloat(box.width),
            height: CGFloat(box.height)
        )
            .standardized
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !sourceRect.isEmpty else {
            return nil
        }
        let targetAspectRatio: CGFloat = 16.0 / 9.0
        var width = min(1, max(sourceRect.width * 1.8, 0.16))
        var height = min(1, max(sourceRect.height * 1.8, 0.10))
        if width / height < targetAspectRatio {
            width = min(1, height * targetAspectRatio)
        } else {
            height = min(1, width / targetAspectRatio)
        }
        return CGRect(
            x: min(max(sourceRect.midX - width / 2, 0), 1 - width),
            y: min(max(sourceRect.midY - height / 2, 0), 1 - height),
            width: width,
            height: height
        )
    }

    static func relativeBlockRect(
        for block: ImageTranslationBlock,
        in cropRect: CGRect
    ) -> CGRect {
        guard let box = block.boundingBox.normalizedToUnit(),
              cropRect.width > 0,
              cropRect.height > 0 else {
            return .zero
        }
        let rect = CGRect(
            x: (CGFloat(box.x) - cropRect.minX) / cropRect.width,
            y: (CGFloat(box.y) - cropRect.minY) / cropRect.height,
            width: CGFloat(box.width) / cropRect.width,
            height: CGFloat(box.height) / cropRect.height
        )
        return rect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

private struct ImageOCRCorrectionReferenceRequestID: Hashable {
    let blockID: UUID
    let imageByteCount: Int
}

private enum ImageOCRCorrectionReferencePhase: Equatable {
    case loading
    case ready
    case unavailable
}

private struct ImageOCRCorrectionReferencePreview: View {
    let imageData: Data?
    let block: ImageTranslationBlock

    @State private var referenceImage: UIImage?
    @State private var referencePhase: ImageOCRCorrectionReferencePhase = .loading

    var body: some View {
        Group {
            if let crop = referenceCrop {
                cropPreview(crop)
            } else if referencePhase == .loading {
                loadingState
            } else {
                unavailableState
            }
        }
        .task(
            id: ImageOCRCorrectionReferenceRequestID(
                blockID: block.id,
                imageByteCount: imageData?.count ?? 0
            )
        ) {
            referenceImage = nil
            guard let imageData, !imageData.isEmpty else {
                referencePhase = .unavailable
                return
            }
            referencePhase = .loading
            guard let preview = await ImagePreviewService.makePreview(from: imageData) else {
                guard !Task.isCancelled else { return }
                referencePhase = .unavailable
                return
            }
            guard !Task.isCancelled else { return }
            referenceImage = UIImage(cgImage: preview.cgImage)
            referencePhase = .ready
        }
    }

    private var referenceCrop: ImageTranslationBlockFocusCrop? {
        guard let sourceImage = referenceImage?.cgImage else { return nil }
        return ImageTranslationBlockFocusCrop.make(from: sourceImage, block: block)
    }

    private func cropPreview(_ crop: ImageTranslationBlockFocusCrop) -> some View {
        GeometryReader { geometry in
            let fittedSize = fittedImageSize(
                imageSize: CGSize(width: CGFloat(crop.image.width), height: CGFloat(crop.image.height)),
                containerSize: geometry.size
            )
            let relativeRect = ImageTranslationBlockFocusCrop.relativeBlockRect(
                for: block,
                in: crop.normalizedRect
            )
            let origin = CGPoint(
                x: (geometry.size.width - fittedSize.width) / 2,
                y: (geometry.size.height - fittedSize.height) / 2
            )

            ZStack(alignment: .topLeading) {
                Image(decorative: crop.image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityHidden(true)

                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.appWarning, lineWidth: 4)
                    .frame(
                        width: max(fittedSize.width * relativeRect.width, 24),
                        height: max(fittedSize.height * relativeRect.height, 24)
                    )
                    .position(
                        x: origin.x + fittedSize.width * relativeRect.midX,
                        y: origin.y + fittedSize.height * relativeRect.midY
                    )
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 180)
        .background(Color.black)
        .clipShape(.rect(cornerRadius: AppTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                .stroke(Color.appBorder, lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            Label("当前文字块", systemImage: "viewfinder")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, AppTheme.Spacing.control)
                .frame(minHeight: AppTheme.Layout.minimumTarget)
                .background(Color.black.opacity(0.82), in: .rect(cornerRadius: AppTheme.Radius.control))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前文字块图片局部")
        .accessibilityValue("黄色边框为 OCR 文字区域，当前识别为 \(accessibilityOriginalText)")
        .accessibilityHint("请对照图片局部确认 OCR 原文")
    }

    private var loadingState: some View {
        HStack(spacing: AppTheme.Spacing.control) {
            ProgressView()
            Text("正在准备图片局部")
                .foregroundStyle(Color.appTextSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在准备当前文字块图片局部")
    }

    private var unavailableState: some View {
        Label("图片局部预览不可用，仍可编辑 OCR 原文", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(Color.appWarning)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .accessibilityLabel("图片局部预览不可用，仍可编辑 OCR 原文")
    }

    private var accessibilityOriginalText: String {
        block.original.isEmpty ? "空" : block.original
    }

    private func fittedImageSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

private struct ImageTranslationFocusPreview: View {
    let previewImage: UIImage
    let block: ImageTranslationBlock
    let positionText: String
    let canSelectPrevious: Bool
    let canSelectNext: Bool
    let isReviewRequired: Bool
    let isReviewCompleted: Bool
    let isManuallyCorrected: Bool
    let canEdit: Bool
    let canReview: Bool
    let modificationUnavailableHint: String
    let reviewUnavailableHint: String
    let canRetryTranslation: Bool
    let isRetryingTranslation: Bool
    let retryTranslation: () -> Void
    let canRerecognize: Bool
    let isRerecognizing: Bool
    let rerecognize: () -> Void
    let retryUnavailableHint: String
    let accessibilityFocus: AccessibilityFocusState<String?>.Binding
    let close: () -> Void
    let selectPrevious: () -> Void
    let selectNext: () -> Void
    let edit: () -> Void
    let restoreVisionOCR: () -> Void
    let setDirectionOverride: (ImageTextDirection?) -> Void
    let toggleReviewCompletion: () -> Void

    var body: some View {
        Group {
            if let crop = focusCrop {
                GeometryReader { geometry in
                    let fittedSize = fittedImageSize(
                        imageSize: CGSize(width: CGFloat(crop.image.width), height: CGFloat(crop.image.height)),
                        containerSize: geometry.size
                    )
                    let relativeRect = relativeBlockRect(in: crop.normalizedRect)
                    let origin = CGPoint(
                        x: (geometry.size.width - fittedSize.width) / 2,
                        y: (geometry.size.height - fittedSize.height) / 2
                    )

                    ZStack(alignment: .topLeading) {
                        Image(decorative: crop.image, scale: 1, orientation: .up)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .accessibilityHidden(true)

                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.appWarning, lineWidth: 4)
                            .frame(
                                width: max(fittedSize.width * relativeRect.width, 24),
                                height: max(fittedSize.height * relativeRect.height, 24)
                            )
                            .position(
                                x: origin.x + fittedSize.width * relativeRect.midX,
                                y: origin.y + fittedSize.height * relativeRect.midY
                            )
                            .accessibilityHidden(true)
                    }
                }
            } else {
                unavailableFocusState
            }
        }
        .background(Color.black)
        .clipShape(.rect(cornerRadius: AppTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                .stroke(Color.white, lineWidth: 2)
        }
        .overlay(alignment: .topLeading) {
            Label("局部放大", systemImage: "magnifyingglass")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, AppTheme.Spacing.control)
                .frame(minHeight: 44)
                .background(Color.black.opacity(0.82), in: .rect(cornerRadius: AppTheme.Radius.control))
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: AppTheme.Spacing.compact) {
                Button("关闭局部放大", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Color.black.opacity(0.82), in: Circle())
                    .accessibilityHint("关闭局部放大并返回当前文字块结果行")
                Button("修正识别文字", systemImage: "pencil", action: edit)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
                    .background(Color.black.opacity(0.82), in: Circle())
                    .disabled(!canEdit)
                    .opacity(canEdit ? 1 : 0.35)
                    .accessibilityHint(
                        canEdit
                            ? "打开当前文字块的 OCR 修正页面"
                            : modificationUnavailableHint
                    )
                ImageOCRDirectionOverrideMenu(
                    block: block,
                    canEdit: canEdit,
                    unavailableHint: modificationUnavailableHint,
                    setDirectionOverride: setDirectionOverride
                )
                .foregroundStyle(.white)
                .background(Color.black.opacity(0.82), in: Circle())
                if isManuallyCorrected {
                    Button("恢复 Vision OCR", systemImage: "arrow.counterclockwise", action: restoreVisionOCR)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.white)
                        .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
                        .background(Color.black.opacity(0.82), in: Circle())
                        .disabled(!canEdit)
                        .opacity(canEdit ? 1 : 0.35)
                        .accessibilityHint(
                            canEdit
                                ? "恢复当前文字块的 Vision OCR 原文与初始译文"
                                : modificationUnavailableHint
                        )
                }
                if canRerecognize || isRerecognizing {
                    Button(
                        isRerecognizing ? "正在重新识别" : "重新识别此文字块",
                        systemImage: isRerecognizing ? "hourglass" : "text.viewfinder",
                        action: rerecognize
                    )
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
                    .background(Color.black.opacity(0.82), in: Circle())
                    .disabled(!canRerecognize || isRerecognizing)
                    .opacity(canRerecognize && !isRerecognizing ? 1 : 0.55)
                    .accessibilityHint(
                        isRerecognizing
                            ? "正在只重新识别此文字块，不会重新运行整张图片 OCR"
                            : "只使用此文字块现有位置重新识别，成功后保留位置并刷新此块翻译"
                    )
                }
                if block.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   canRetryTranslation || isRetryingTranslation {
                    Button(
                        isRetryingTranslation ? "正在重试翻译" : "重试此文字块翻译",
                        systemImage: isRetryingTranslation ? "hourglass" : "arrow.clockwise",
                        action: retryTranslation
                    )
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
                    .background(Color.black.opacity(0.82), in: Circle())
                    .disabled(!canRetryTranslation || isRetryingTranslation)
                    .opacity(canRetryTranslation && !isRetryingTranslation ? 1 : 0.55)
                    .accessibilityHint(
                        isRetryingTranslation
                            ? "正在只翻译此文字块，不会重新识别图片"
                            : retryUnavailableHint
                    )
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text(positionText)
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(.white)
                .padding(.horizontal, AppTheme.Spacing.control)
                .frame(minHeight: AppTheme.Layout.minimumTarget)
                .background(Color.black.opacity(0.82), in: .rect(cornerRadius: AppTheme.Radius.control))
                .accessibilityHidden(true)
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: AppTheme.Spacing.compact) {
                if isReviewRequired {
                    Button(
                        isReviewCompleted ? "重新加入待复查" : "完成并继续复查",
                        systemImage: isReviewCompleted ? "arrow.uturn.backward" : "checkmark",
                        action: toggleReviewCompletion
                    )
                    .labelStyle(.iconOnly)
                    .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
                    .background(Color.black.opacity(0.82), in: Circle())
                    .disabled(!canReview)
                    .opacity(canReview ? 1 : 0.35)
                    .accessibilityHint(
                        canReview
                            ? (isReviewCompleted ? "把当前文字块放回待复查队列" : "标记完成并定位下一个待复查文字块")
                            : reviewUnavailableHint
                    )
                }
                Button("上一个文字块", systemImage: "chevron.left", action: selectPrevious)
                    .labelStyle(.iconOnly)
                    .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
                    .background(Color.black.opacity(0.82), in: Circle())
                    .disabled(!canSelectPrevious)
                    .opacity(canSelectPrevious ? 1 : 0.35)
                    .accessibilityValue(navigationPositionAccessibilityValue)
                    .accessibilityHint(
                        canSelectPrevious
                            ? "定位上一个文字块"
                            : "当前已是筛选结果中的第一个文字块"
                    )
                Button("下一个文字块", systemImage: "chevron.right", action: selectNext)
                    .labelStyle(.iconOnly)
                    .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
                    .background(Color.black.opacity(0.82), in: Circle())
                    .disabled(!canSelectNext)
                    .opacity(canSelectNext ? 1 : 0.35)
                    .accessibilityValue(navigationPositionAccessibilityValue)
                    .accessibilityHint(
                        canSelectNext
                            ? "定位下一个文字块"
                            : "当前已是筛选结果中的最后一个文字块"
                    )
            }
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("已定位文字块局部放大")
        .accessibilityValue("\(positionText)，\(accessibilityOriginalText)")
        .accessibilityHint(focusPreviewAccessibilityHint)
        .accessibilityAction(named: "关闭局部放大") {
            close()
        }
        .modifier(
            ImageFocusPreviewEditAccessibilityModifier(
                canEdit: canEdit,
                edit: edit
            )
        )
        .modifier(
            ImageFocusPreviewRestoreAccessibilityModifier(
                isManuallyCorrected: isManuallyCorrected,
                canEdit: canEdit,
                restoreVisionOCR: restoreVisionOCR
            )
        )
        .modifier(
            ImageFocusPreviewDirectionOverrideAccessibilityModifier(
                block: block,
                canEdit: canEdit,
                setDirectionOverride: setDirectionOverride
            )
        )
        .modifier(
            ImageFocusPreviewRerecognitionAccessibilityModifier(
                canRerecognize: canRerecognize,
                isRerecognizing: isRerecognizing,
                rerecognize: rerecognize
            )
        )
        .modifier(
            ImageFocusPreviewReviewAccessibilityModifier(
                isReviewRequired: isReviewRequired,
                canReview: canReview,
                isReviewCompleted: isReviewCompleted,
                toggleReviewCompletion: toggleReviewCompletion
            )
        )
        .modifier(
            ImageFocusPreviewNavigationAccessibilityModifier(
                canSelectPrevious: canSelectPrevious,
                canSelectNext: canSelectNext,
                selectPrevious: selectPrevious,
                selectNext: selectNext
            )
        )
        .accessibilityFocused(
            accessibilityFocus,
            equals: "image-review-preview-\(block.id.uuidString)"
        )
    }

    private var navigationPositionAccessibilityValue: String {
        positionText.isEmpty ? "未显示筛选位置" : "当前位置 \(positionText)"
    }

    private var accessibilityOriginalText: String {
        block.original.isEmpty ? "空" : block.original
    }

    private var focusCrop: ImageTranslationBlockFocusCrop? {
        guard let sourceImage = previewImage.cgImage else { return nil }
        return ImageTranslationBlockFocusCrop.make(from: sourceImage, block: block)
    }

    private var unavailableFocusState: some View {
        Label(
            "当前文字块局部预览不可用",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.subheadline.bold())
        .foregroundStyle(Color.appWarning)
        .multilineTextAlignment(.center)
        .padding(AppTheme.Spacing.control)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前文字块局部预览不可用")
        .accessibilityValue("仍可关闭、编辑 OCR 原文或切换文字块")
        .accessibilityHidden(true)
    }

    private var focusPreviewAccessibilityHint: String {
        let base: String
        if focusCrop == nil {
            if canEdit {
                base = "局部预览不可用；仍可关闭、修正 OCR 原文或切换文字块"
            } else {
                base = "局部预览不可用；仍可关闭或切换文字块；\(modificationUnavailableHint)"
            }
        } else if canEdit {
            base = "可执行“关闭局部放大”或“修正识别文字”，也可切换文字块"
        } else {
            base = "可关闭局部放大或切换文字块；\(modificationUnavailableHint)"
        }
        let modificationHint = focusPreviewModificationHint(appendingTo: base)
        return reviewAccessibilityHint(appendingTo: modificationHint)
    }

    private func focusPreviewModificationHint(appendingTo base: String) -> String {
        var detail = base
        if canRerecognize || isRerecognizing {
            detail += isRerecognizing
                ? "；正在重新识别此文字块"
                : "；也可执行“重新识别此文字块”"
        }
        guard isManuallyCorrected, canEdit else { return detail }
        return "\(detail)；也可执行“恢复 Vision OCR”"
    }

    private func reviewAccessibilityHint(appendingTo base: String) -> String {
        guard isReviewRequired else { return base }
        if canReview {
            return "\(base)；可执行“\(reviewActionAccessibilityName)”"
        }
        return "\(base)；\(reviewUnavailableHint)"
    }

    private var reviewActionAccessibilityName: String {
        isReviewCompleted ? "重新加入待复查" : "完成并继续复查"
    }

    private func relativeBlockRect(in cropRect: CGRect) -> CGRect {
        ImageTranslationBlockFocusCrop.relativeBlockRect(for: block, in: cropRect)
    }

    private func fittedImageSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

private struct ImageFocusPreviewEditAccessibilityModifier: ViewModifier {
    let canEdit: Bool
    let edit: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if canEdit {
            content
                .accessibilityAction(named: "修正识别文字") {
                    edit()
                }
        } else {
            content
        }
    }
}

private struct ImageFocusPreviewRestoreAccessibilityModifier: ViewModifier {
    let isManuallyCorrected: Bool
    let canEdit: Bool
    let restoreVisionOCR: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isManuallyCorrected && canEdit {
            content
                .accessibilityAction(named: "恢复 Vision OCR") {
                    restoreVisionOCR()
                }
        } else {
            content
        }
    }
}

private struct ImageFocusPreviewRerecognitionAccessibilityModifier: ViewModifier {
    let canRerecognize: Bool
    let isRerecognizing: Bool
    let rerecognize: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if canRerecognize && !isRerecognizing {
            content
                .accessibilityAction(named: "重新识别此文字块") {
                    rerecognize()
                }
        } else {
            content
        }
    }
}

private struct ImageFocusPreviewDirectionOverrideAccessibilityModifier: ViewModifier {
    let block: ImageTranslationBlock
    let canEdit: Bool
    let setDirectionOverride: (ImageTextDirection?) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if canEdit {
            content
                .accessibilityAction(named: "设为横排") {
                    setDirectionOverride(.horizontal)
                }
                .accessibilityAction(named: "设为竖排") {
                    setDirectionOverride(.vertical)
                }
                .accessibilityAction(named: "恢复自动方向") {
                    setDirectionOverride(nil)
                }
        } else {
            content
        }
    }
}

private struct ImageFocusPreviewReviewAccessibilityModifier: ViewModifier {
    let isReviewRequired: Bool
    let canReview: Bool
    let isReviewCompleted: Bool
    let toggleReviewCompletion: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isReviewRequired && canReview {
            content
                .accessibilityAction(named: isReviewCompleted ? "重新加入待复查" : "完成并继续复查") {
                    toggleReviewCompletion()
                }
        } else {
            content
        }
    }
}

private struct ImageFocusPreviewNavigationAccessibilityModifier: ViewModifier {
    let canSelectPrevious: Bool
    let canSelectNext: Bool
    let selectPrevious: () -> Void
    let selectNext: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if canSelectPrevious && canSelectNext {
            content
                .accessibilityAction(named: "上一个文字块") {
                    selectPrevious()
                }
                .accessibilityAction(named: "下一个文字块") {
                    selectNext()
                }
        } else if canSelectPrevious {
            content
                .accessibilityAction(named: "上一个文字块") {
                    selectPrevious()
                }
        } else if canSelectNext {
            content
                .accessibilityAction(named: "下一个文字块") {
                    selectNext()
                }
        } else {
            content
        }
    }
}

private struct ImageTranslationOverlayBlock: View {
    let block: ImageTranslationBlock
    let mode: ImageTranslationOverlayMode
    let imageOrigin: CGPoint
    let imageSize: CGSize
    let isSelected: Bool
    let isReviewCompleted: Bool
    let isManuallyCorrected: Bool
    let select: () -> Void

    var body: some View {
        Group {
            if let rect = displayRect {
                overlayContent(for: rect)
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func overlayContent(for rect: CGRect) -> some View {
        switch mode {
        case .adjacent:
            Button(action: select) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.translation.isEmpty ? displayOCRText : block.translation)
                        .font(.caption.bold())
                        .lineLimit(4)
                    Text(displayOCRText)
                        .font(.caption2)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
                .padding(5)
                .frame(width: bubbleWidth(for: rect), alignment: .leading)
                .background(Color.black.opacity(0.88), in: .rect(cornerRadius: 4))
                .overlay(alignment: .leading) { Rectangle().fill(Color.appAccent).frame(width: 3) }
                .overlay { selectionBorder }
            }
            .buttonStyle(.plain)
            .frame(minWidth: AppTheme.Layout.minimumTarget, minHeight: AppTheme.Layout.minimumTarget)
            .position(
                x: adjacentCenterX(for: rect, bubbleWidth: bubbleWidth(for: rect)),
                y: rect.midY
            )
            .accessibilityLabel("图片文字块 \(accessibilityOriginalText)")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(accessibilityHint)
        case .replace:
            Button(action: select) {
                let text = block.translation.isEmpty ? displayOCRText : block.translation
                Group {
                    if block.prefersVerticalWriting {
                        ImageTranslationVerticalText(text: text)
                    } else {
                        Text(text)
                            .font(.caption.bold())
                            .lineLimit(4)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(3)
                .frame(width: max(rect.width, 44), height: max(rect.height, 24))
                    .background(Color.appAccentStrong.opacity(0.94), in: .rect(cornerRadius: 4))
                    .overlay { selectionBorder }
            }
            .buttonStyle(.plain)
            .frame(minWidth: AppTheme.Layout.minimumTarget, minHeight: AppTheme.Layout.minimumTarget)
            .position(x: rect.midX, y: rect.midY)
            .accessibilityLabel("图片文字块 \(accessibilityOriginalText)")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(accessibilityHint)
        }
    }

    @ViewBuilder private var selectionBorder: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white, lineWidth: 3)
        }
    }

    private var displayRect: CGRect? {
        guard let box = block.boundingBox.normalizedToUnit(),
              imageSize.width > 0,
              imageSize.height > 0 else {
            return nil
        }
        return CGRect(
            x: imageOrigin.x + imageSize.width * box.x,
            y: imageOrigin.y + imageSize.height * box.y,
            width: imageSize.width * box.width,
            height: imageSize.height * box.height
        ).intersection(CGRect(origin: imageOrigin, size: imageSize))
    }

    private func bubbleWidth(for rect: CGRect) -> CGFloat {
        min(max(rect.width * 1.45, 78), max(imageSize.width * 0.46, 92))
    }

    private var accessibilityValue: String {
        var parts = [
            isSelected ? "已在图片中定位" : "未定位",
            "OCR 置信度 \(accessibilityConfidencePercent)%"
        ]

        if let directionContext = ImageOCRDirectionPresentation.accessibilityContext(for: block) {
            parts.append(directionContext)
        }

        if isManuallyCorrected {
            parts.append("已人工修正")
        }

        if ImageOCRResultSummary.requiresReview(block) {
            if ImageOCRResultSummary.hasLowConfidence(block) {
                parts.append("低置信")
            }
            if ImageOCRResultSummary.hasUnknownDirection(block) {
                parts.append("方向待定")
            }
            parts.append(isReviewCompleted ? "本次已复查" : "待复查")
        }

        parts.append(block.translation.isEmpty ? "等待翻译" : "译文：\(block.translation)")
        return parts.joined(separator: "；")
    }

    private var accessibilityOriginalText: String {
        block.original.isEmpty ? "空" : block.original
    }

    private var displayOCRText: String {
        block.original.isEmpty ? "空 OCR 原文" : block.original
    }

    private var accessibilityConfidencePercent: Int {
        let confidence = Double(ImageOCRResultSummary.normalizedConfidence(block.confidence))
        return Int((confidence * 100).rounded())
    }

    private var accessibilityHint: String {
        isSelected ? "取消此文字块在图片中的定位" : "在图片预览中定位此文字块"
    }

    private func adjacentCenterX(for rect: CGRect, bubbleWidth: CGFloat) -> CGFloat {
        let rightCenter = rect.maxX + 6 + bubbleWidth / 2
        let rightLimit = imageOrigin.x + imageSize.width - bubbleWidth / 2
        if rightCenter <= rightLimit { return rightCenter }
        return max(imageOrigin.x + bubbleWidth / 2, rect.minX - 6 - bubbleWidth / 2)
    }
}

/// Small, bounded VerticalRl-style preview for CJK replacement overlays.
/// Columns are emitted right-to-left while glyphs advance top-to-bottom.
private struct ImageTranslationVerticalText: View {
    let text: String

    var body: some View {
        GeometryReader { geometry in
            let characters = ImageTranslationVerticalTextLayout.normalizedCharacters(in: text)
            let rowHeight: CGFloat = 18
            let rowCapacity = max(Int(geometry.size.height / rowHeight), 1)
            let columnCapacity = max(
                Int(geometry.size.width / max(rowHeight * 0.9, 1)),
                1
            )
            let maximumCharacters = max(rowCapacity * columnCapacity, 1)
            let drawableCharacters = boundedCharacters(
                characters,
                maximumCharacters: maximumCharacters
            )
            let columns = makeColumns(drawableCharacters, rowCapacity: rowCapacity)
            let columnWidth = max(
                geometry.size.width / CGFloat(max(columns.count, 1)),
                1
            )

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(columns.indices.reversed()), id: \.self) { columnIndex in
                    VStack(spacing: 0) {
                        ForEach(Array(columns[columnIndex].indices), id: \.self) { characterIndex in
                            let character = columns[columnIndex][characterIndex]
                            let glyph = ImageTranslationVerticalTextLayout.verticalGlyph(for: character)
                            let isFullwidthPunctuation = ImageTranslationVerticalTextLayout
                                .isFullwidthPunctuation(character)
                            Text(glyph)
                                .font(.caption.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .frame(
                                    width: columnWidth,
                                    height: rowHeight,
                                    alignment: isFullwidthPunctuation ? .center : .top
                                )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .clipped()
        }
    }

    private func makeColumns(
        _ characters: [String],
        rowCapacity: Int
    ) -> [[String]] {
        guard !characters.isEmpty else { return [[]] }
        return stride(from: 0, to: characters.count, by: rowCapacity).map { start in
            Array(characters[start..<min(start + rowCapacity, characters.count)])
        }
    }

    private func boundedCharacters(
        _ characters: [String],
        maximumCharacters: Int
    ) -> [String] {
        guard characters.count > maximumCharacters else { return characters }
        let prefixCount = max(maximumCharacters - 1, 1)
        return Array(characters.prefix(prefixCount)) + ["…"]
    }
}

private struct ImageTranslationBlockRow: View {
    let block: ImageTranslationBlock
    let isSelected: Bool
    let isReviewCompleted: Bool
    let isManuallyCorrected: Bool
    let canEdit: Bool
    let canReview: Bool
    let modificationUnavailableHint: String
    let reviewUnavailableHint: String
    let canRetryTranslation: Bool
    let isRetryingTranslation: Bool
    let retryTranslation: () -> Void
    let canRerecognize: Bool
    let isRerecognizing: Bool
    let rerecognize: () -> Void
    let retryUnavailableHint: String
    let accessibilityFocus: AccessibilityFocusState<String?>.Binding
    let select: () -> Void
    let edit: () -> Void
    let restoreVisionOCR: () -> Void
    let setDirectionOverride: (ImageTextDirection?) -> Void
    let toggleReviewCompletion: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.compact) {
            Button(action: select) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.control) {
                    Text(displayConfidence, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(Color.appAccent)
                        .frame(width: 46, alignment: .leading)
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Text(block.translation.isEmpty ? "等待翻译" : block.translation)
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.appTextPrimary)
                        Text(displayOriginalText)
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                        if !ImageOCRGeometryPresentation.isLocatable(for: block) {
                            Label("图片定位不可用", systemImage: "location.slash")
                                .font(.caption)
                                .foregroundStyle(Color.appWarning)
                        }
                        if !ImageOCRResultSummary.hasUnknownDirection(block) {
                            Label(
                                ImageOCRDirectionPresentation.displayTitle(for: block),
                                systemImage: "text.alignleft"
                            )
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                        }
                        if isManuallyCorrected {
                            Label("已人工修正", systemImage: "pencil.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.appSuccess)
                        }
                        if ImageOCRResultSummary.requiresReview(block) {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                                if ImageOCRResultSummary.hasLowConfidence(block) {
                                    Label("低置信", systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Color.appWarning)
                                }
                                if ImageOCRResultSummary.hasUnknownDirection(block) {
                                    Label("方向待定", systemImage: "questionmark.diamond.fill")
                                        .foregroundStyle(Color.appWarning)
                                }
                                if isReviewCompleted {
                                    Label("本次已复查", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(Color.appSuccess)
                                }
                            }
                            .font(.caption)
                        }
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "viewfinder.circle.fill")
                            .foregroundStyle(Color.appAccent)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.control)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("图片文字块 \(accessibilityOriginalText)")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(accessibilityHint)
            .accessibilityFocused(
                accessibilityFocus,
                equals: "image-review-row-\(block.id.uuidString)"
            )
            .modifier(
                ImageReviewRowEditAccessibilityModifier(
                    canEdit: canEdit,
                    edit: edit
                )
            )
            .modifier(
                ImageReviewRowRestoreAccessibilityModifier(
                    isManuallyCorrected: isManuallyCorrected,
                    canEdit: canEdit,
                    restoreVisionOCR: restoreVisionOCR
                )
            )
            .modifier(
                ImageReviewRowDirectionOverrideAccessibilityModifier(
                    canEdit: canEdit,
                    setDirectionOverride: setDirectionOverride
                )
            )
            .modifier(
                ImageReviewRowRerecognitionAccessibilityModifier(
                    canRerecognize: canRerecognize,
                    isRerecognizing: isRerecognizing,
                    rerecognize: rerecognize
                )
            )
            .modifier(
                ImageReviewRowReviewAccessibilityModifier(
                    isReviewRequired: ImageOCRResultSummary.requiresReview(block),
                    isReviewCompleted: isReviewCompleted,
                    canReview: canReview,
                    toggleReviewCompletion: toggleReviewCompletion
                )
            )
            .modifier(
                ImageReviewRowRetryAccessibilityModifier(
                    canRetryTranslation: canRetryTranslation,
                    isRetryingTranslation: isRetryingTranslation,
                    retryTranslation: retryTranslation
                )
            )

            VStack(spacing: AppTheme.Spacing.compact) {
                Button("修正识别文字", systemImage: "pencil", action: edit)
                    .labelStyle(.iconOnly)
                    .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
                    .foregroundStyle(Color.appAccent)
                    .disabled(!canEdit)
                    .accessibilityHint(
                        canEdit
                            ? "编辑 OCR 原文并只重新翻译此文字块"
                            : modificationUnavailableHint
                    )

                if isManuallyCorrected {
                    Button("恢复 Vision OCR", systemImage: "arrow.counterclockwise", action: restoreVisionOCR)
                        .labelStyle(.iconOnly)
                        .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
                        .foregroundStyle(Color.appTextSecondary)
                        .disabled(!canEdit)
                        .accessibilityHint(
                            canEdit
                                ? "恢复此文字块的 Vision OCR 原文与初始译文"
                                : modificationUnavailableHint
                        )
                }

                ImageOCRDirectionOverrideMenu(
                    block: block,
                    canEdit: canEdit,
                    unavailableHint: modificationUnavailableHint,
                    setDirectionOverride: setDirectionOverride
                )

                if canRerecognize || isRerecognizing {
                    Button(
                        isRerecognizing ? "正在重新识别" : "重新识别此文字块",
                        systemImage: isRerecognizing ? "hourglass" : "text.viewfinder",
                        action: rerecognize
                    )
                    .labelStyle(.iconOnly)
                    .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
                    .foregroundStyle(Color.appAccent)
                    .disabled(!canRerecognize || isRerecognizing)
                    .accessibilityHint(
                        isRerecognizing
                            ? "正在只重新识别此文字块，不会重新运行整张图片 OCR"
                            : "只使用此文字块现有位置重新识别，成功后保留位置并刷新此块翻译"
                    )
                }

                if block.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   canRetryTranslation || isRetryingTranslation {
                    Button(
                        isRetryingTranslation ? "正在重试翻译" : "重试此文字块翻译",
                        systemImage: isRetryingTranslation ? "hourglass" : "arrow.clockwise",
                        action: retryTranslation
                    )
                    .labelStyle(.iconOnly)
                    .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
                    .foregroundStyle(Color.appWarning)
                    .disabled(!canRetryTranslation || isRetryingTranslation)
                    .accessibilityHint(
                        isRetryingTranslation
                            ? "正在只翻译此文字块，不会重新识别图片"
                            : retryUnavailableHint
                    )
                }

                if ImageOCRResultSummary.requiresReview(block) {
                    Button(
                        isReviewCompleted ? "撤销本次复查" : "完成并继续复查",
                        systemImage: isReviewCompleted ? "arrow.uturn.backward" : "checkmark.circle",
                        action: toggleReviewCompletion
                    )
                    .labelStyle(.iconOnly)
                    .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
                    .foregroundStyle(isReviewCompleted ? Color.appSuccess : Color.appWarning)
                    .disabled(!canReview)
                    .accessibilityHint(
                        canReview
                            ? (isReviewCompleted
                                ? "把此文字块放回待复查队列并定位"
                                : "标记完成并定位下一个待复查文字块")
                            : reviewUnavailableHint
                    )
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.compact)
        .background(isSelected ? Color.appAccent.opacity(0.12) : Color.clear)
        .overlay(alignment: .bottom) { Divider().overlay(Color.appBorder) }
    }

    private var accessibilityValue: String {
        var parts = [
            isSelected ? "已在图片中定位" : "未定位",
            "OCR 置信度 \(accessibilityConfidencePercent)%"
        ]

        if let directionContext = ImageOCRDirectionPresentation.accessibilityContext(for: block) {
            parts.append(directionContext)
        }

        if isManuallyCorrected {
            parts.append("已人工修正")
        }

        if !ImageOCRGeometryPresentation.isLocatable(for: block) {
            parts.append("图片定位不可用")
        }

        if ImageOCRResultSummary.requiresReview(block) {
            if ImageOCRResultSummary.hasLowConfidence(block) {
                parts.append("低置信")
            }
            if ImageOCRResultSummary.hasUnknownDirection(block) {
                parts.append("方向待定")
            }
            parts.append(isReviewCompleted ? "本次已复查" : "待复查")
        }

        parts.append(block.translation.isEmpty ? "等待翻译" : "译文：\(block.translation)")
        if block.translation.isEmpty, isRetryingTranslation || canRetryTranslation {
            parts.append(isRetryingTranslation ? "正在重试译文" : "可重试此块")
        }
        if isRerecognizing || canRerecognize {
            parts.append(isRerecognizing ? "正在重新识别此块" : "可重新识别此块")
        }

        return parts.joined(separator: "；")
    }

    private var accessibilityOriginalText: String {
        block.original.isEmpty ? "空" : block.original
    }

    private var displayOriginalText: String {
        block.original.isEmpty ? "空 OCR 原文" : block.original
    }

    private var accessibilityConfidencePercent: Int {
        let confidence = Double(ImageOCRResultSummary.normalizedConfidence(block.confidence))
        return Int((confidence * 100).rounded())
    }

    private var accessibilityHint: String {
        guard ImageOCRGeometryPresentation.isLocatable(for: block) else {
            var parts = ["图片局部预览不可用"]
            if canEdit {
                parts.append("仍可修正 OCR 原文")
            }
            parts.append("可切换文字块")
            return rowAccessibilityHint(appendingTo: parts.joined(separator: "；"))
        }
        let locationHint = isSelected
            ? "取消此文字块在图片中的定位"
            : "在图片预览中定位此文字块"
        return rowAccessibilityHint(appendingTo: locationHint)
    }

    private func rowAccessibilityHint(appendingTo base: String) -> String {
        var actions: [String] = []
        if canEdit {
            actions.append("修正识别文字")
        }
        if isManuallyCorrected && canEdit {
            actions.append("恢复 Vision OCR")
        }
        if ImageOCRResultSummary.requiresReview(block) && canReview {
            actions.append(isReviewCompleted ? "撤销本次复查" : "完成并继续复查")
        }
        if canRetryTranslation {
            actions.append("重试此文字块翻译")
        }
        if canRerecognize && !isRerecognizing {
            actions.append("重新识别此文字块")
        }
        guard !actions.isEmpty else { return base }
        return "\(base)；VoiceOver 可执行：\(actions.joined(separator: "、"))"
    }

    private var displayConfidence: Double {
        Double(ImageOCRResultSummary.normalizedConfidence(block.confidence))
    }
}

private struct ImageReviewRowRetryAccessibilityModifier: ViewModifier {
    let canRetryTranslation: Bool
    let isRetryingTranslation: Bool
    let retryTranslation: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if canRetryTranslation && !isRetryingTranslation {
            content
                .accessibilityAction(named: "重试此文字块翻译") {
                    retryTranslation()
                }
        } else {
            content
        }
    }
}

private struct ImageReviewRowEditAccessibilityModifier: ViewModifier {
    let canEdit: Bool
    let edit: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if canEdit {
            content
                .accessibilityAction(named: "修正识别文字") {
                    edit()
                }
        } else {
            content
        }
    }
}

private struct ImageReviewRowRestoreAccessibilityModifier: ViewModifier {
    let isManuallyCorrected: Bool
    let canEdit: Bool
    let restoreVisionOCR: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isManuallyCorrected && canEdit {
            content
                .accessibilityAction(named: "恢复 Vision OCR") {
                    restoreVisionOCR()
                }
        } else {
            content
        }
    }
}

private struct ImageReviewRowDirectionOverrideAccessibilityModifier: ViewModifier {
    let canEdit: Bool
    let setDirectionOverride: (ImageTextDirection?) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if canEdit {
            content
                .accessibilityAction(named: "设为横排") {
                    setDirectionOverride(.horizontal)
                }
                .accessibilityAction(named: "设为竖排") {
                    setDirectionOverride(.vertical)
                }
                .accessibilityAction(named: "恢复自动方向") {
                    setDirectionOverride(nil)
                }
        } else {
            content
        }
    }
}

private struct ImageReviewRowRerecognitionAccessibilityModifier: ViewModifier {
    let canRerecognize: Bool
    let isRerecognizing: Bool
    let rerecognize: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if canRerecognize && !isRerecognizing {
            content
                .accessibilityAction(named: "重新识别此文字块") {
                    rerecognize()
                }
        } else {
            content
        }
    }
}

private struct ImageReviewRowReviewAccessibilityModifier: ViewModifier {
    let isReviewRequired: Bool
    let isReviewCompleted: Bool
    let canReview: Bool
    let toggleReviewCompletion: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isReviewRequired && canReview {
            content
                .accessibilityAction(named: isReviewCompleted ? "撤销本次复查" : "完成并继续复查") {
                    toggleReviewCompletion()
                }
        } else {
            content
        }
    }
}

private struct ImageTranslationIgnoredBlockRow: View {
    let block: ImageTranslationBlock
    let canRestore: Bool
    let modificationUnavailableHint: String
    let accessibilityFocus: AccessibilityFocusState<String?>.Binding
    let restore: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.control) {
            Image(systemName: "eye.slash")
                .foregroundStyle(Color.appTextSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                Text(displayOriginalText)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.appTextPrimary)
                    .lineLimit(2)
                if !block.translation.isEmpty {
                    Text(block.translation)
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                        .lineLimit(2)
                }
                Text("已从本次图片结果中忽略")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            Spacer(minLength: 0)
            Button("恢复", systemImage: "arrow.uturn.backward", action: restore)
                .font(.subheadline.bold())
                .frame(minHeight: AppTheme.Layout.minimumTarget)
                .disabled(!canRestore)
                .accessibilityHint(
                    canRestore
                        ? "恢复到图片预览、导出和当前转录；需要复查的文字块会重新回到待复查队列"
                        : modificationUnavailableHint
                )
                .accessibilityFocused(
                    accessibilityFocus,
                    equals: "image-ignored-row-\(block.id.uuidString)"
                )
        }
        .padding(.horizontal, AppTheme.Spacing.compact)
        .padding(.vertical, AppTheme.Spacing.control)
        .overlay(alignment: .bottom) { Divider().overlay(Color.appBorder) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("已忽略 OCR 文字块 \(accessibilityOriginalText)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .modifier(
            ImageIgnoredBlockRestoreAccessibilityModifier(
                canRestore: canRestore,
                restore: restore
            )
        )
    }

    private var displayOriginalText: String {
        block.original.isEmpty ? "空 OCR 原文" : block.original
    }

    private var accessibilityOriginalText: String {
        block.original.isEmpty ? "空" : block.original
    }

    private var accessibilityValue: String {
        var parts = ["已从当前图片预览、导出和转录中移除"]
        parts.append(block.translation.isEmpty ? "没有现有译文" : "保留已有译文")
        parts.append(canRestore ? "可以恢复" : "当前不可恢复")
        return parts.joined(separator: "；")
    }

    private var accessibilityHint: String {
        canRestore
            ? "可执行“恢复”，把此文字块恢复到图片预览、导出和当前转录；需要复查时会重新回到待复查队列"
            : modificationUnavailableHint
    }
}

private struct ImageIgnoredBlockRestoreAccessibilityModifier: ViewModifier {
    let canRestore: Bool
    let restore: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if canRestore {
            content
                .accessibilityAction(named: "恢复") {
                    restore()
                }
        } else {
            content
        }
    }
}

private struct ImageOCRCorrectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TranslationSessionStore

    let block: ImageTranslationBlock
    let imageData: Data?
    let didSave: () -> Void
    let setDirectionOverride: (ImageTextDirection?) -> Bool
    let requestIgnore: () -> Bool

    @State private var correctedOriginal: String
    @State private var selectedDirectionOverride: ImageTextDirection?
    @State private var directionUpdateMessage: String?
    @State private var errorMessage: String?
    @State private var showDiscardCorrectionConfirmation = false
    @State private var showIgnoreBlockConfirmation = false
    @FocusState private var correctedOriginalFocused: Bool

    init(
        block: ImageTranslationBlock,
        imageData: Data?,
        didSave: @escaping () -> Void,
        setDirectionOverride: @escaping (ImageTextDirection?) -> Bool,
        requestIgnore: @escaping () -> Bool
    ) {
        self.block = block
        self.imageData = imageData
        self.didSave = didSave
        self.setDirectionOverride = setDirectionOverride
        self.requestIgnore = requestIgnore
        _correctedOriginal = State(initialValue: block.original)
        _selectedDirectionOverride = State(initialValue: block.sourceDirectionOverride)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("图片对照") {
                    ImageOCRCorrectionReferencePreview(imageData: imageData, block: block)
                    Text("黄色边框标出当前 OCR 文字区域；局部图只使用既有本地预览，不会重新识别图片。")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }

                if needsReview {
                    Section("复查提示") {
                        if ImageOCRResultSummary.hasLowConfidence(block) {
                            HStack {
                                Label("OCR 置信度", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.appWarning)
                                Spacer()
                                Text(displayConfidence, format: .percent.precision(.fractionLength(0)))
                                    .foregroundStyle(Color.appTextSecondary)
                            }
                            Text("置信度低于 50%，请以局部原图为准确认文字。")
                                .font(.caption)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                        if ImageOCRResultSummary.hasUnknownDirection(block) {
                            Label("文字方向待定", systemImage: "questionmark.diamond.fill")
                                .foregroundStyle(Color.appWarning)
                            Text("布局无法稳定判断横排或竖排，请按图片原文确认顺序。")
                                .font(.caption)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                        Text("保存只会重新翻译当前文字块，不会重新识别整张图片。")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }

                Section("识别文字") {
                    TextField("修正后的文字", text: $correctedOriginal, axis: .vertical)
                        .lineLimit(4...10)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($correctedOriginalFocused)
                        .disabled(isSaving)
                        .accessibilityLabel("修正后的 OCR 原文")
                        .accessibilityValue(correctedOriginal.isEmpty ? "空" : correctedOriginal)
                        .accessibilityHint(correctedOriginalAccessibilityHint)
                }

                Section("当前翻译") {
                    Text(block.translation.isEmpty ? "等待翻译" : block.translation)
                        .foregroundStyle(Color.appTextSecondary)
                }

                Section("文字方向") {
                    Picker("文字方向", selection: directionOverrideBinding) {
                        ForEach(ImageTextDirectionOverrideChoice.allCases) { choice in
                            Label(choice.rawValue, systemImage: choice.systemImage)
                                .tag(choice.direction)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isSaving)
                    .accessibilityLabel("文字方向")
                    .accessibilityValue(directionOverrideChoice.rawValue)
                    .accessibilityHint("只更新当前文字块的显示、筛选和导出方向，不会重新识别或翻译")
                    if let directionUpdateMessage {
                        Text(directionUpdateMessage)
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }

                Section("识别有误？") {
                    Button(role: .destructive, action: requestIgnoreConfirmation) {
                        Label("忽略此文字块", systemImage: "eye.slash")
                    }
                    .disabled(isSaving)
                    .accessibilityHint(ignoreActionAccessibilityHint)
                    Text("仅忽略本次图片会话中的这个文字块，不会重新识别或翻译整张图片。")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.appDanger)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("修正识别文字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成", action: dismissKeyboard)
                        .bold()
                        .accessibilityLabel("完成 OCR 原文输入并收起键盘")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: requestDismiss)
                        .disabled(isSaving)
                        .accessibilityHint(
                            hasUnsavedChanges
                                ? "有未保存的修正，取消前会要求确认"
                                : "关闭修正页面"
                        )
                        .confirmationDialog(
                            "放弃未保存的修正？",
                            isPresented: $showDiscardCorrectionConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("放弃修正", role: .destructive, action: dismiss.callAsFunction)
                            Button("继续编辑", role: .cancel) {}
                        } message: {
                            Text("这会关闭修正页面，未保存的 OCR 原文不会用于重新翻译。")
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveActionTitle, action: save)
                        .disabled(!canSave || isSaving)
                        .accessibilityHint(saveActionAccessibilityHint)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("正在重新翻译")
                        .padding(AppTheme.Spacing.section)
                        .background(.regularMaterial, in: .rect(cornerRadius: 8))
                }
            }
        }
        .interactiveDismissDisabled(isSaving || hasUnsavedChanges)
        .confirmationDialog(
            "忽略此文字块？",
            isPresented: $showIgnoreBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("忽略文字块", role: .destructive, action: ignoreCurrentBlock)
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("这会从本次图片的预览、导出和当前转录中移除此 OCR 文字块。未保存的修正不会保存；可在图片检查区恢复。")
        }
        .presentationDetents([.medium, .large])
    }

    private var isSaving: Bool {
        store.imageTranslationCorrectionBlockID == block.id
    }

    private var normalizedCorrectedOriginal: String {
        correctedOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !normalizedCorrectedOriginal.isEmpty
    }

    private var hasUnsavedChanges: Bool {
        normalizedCorrectedOriginal != block.original
    }

    private var needsReview: Bool {
        ImageOCRResultSummary.requiresReview(block)
    }

    private var displayConfidence: Double {
        Double(ImageOCRResultSummary.normalizedConfidence(block.confidence))
    }

    private var directionOverrideChoice: ImageTextDirectionOverrideChoice {
        switch selectedDirectionOverride {
        case .horizontal: .horizontal
        case .vertical: .vertical
        case .unknown, .none: .automatic
        }
    }

    private var directionOverrideBinding: Binding<ImageTextDirection?> {
        Binding(
            get: { selectedDirectionOverride },
            set: { direction in
                guard setDirectionOverride(direction) else { return }
                selectedDirectionOverride = direction
                directionUpdateMessage = direction == nil
                    ? "已恢复自动方向"
                    : (direction == .vertical
                        ? "已设置竖排，不会重新识别或翻译"
                        : "已设置横排，不会重新识别或翻译")
            }
        )
    }

    private var requiresRetranslation: Bool {
        normalizedCorrectedOriginal != block.original
    }

    private var saveActionTitle: String {
        requiresRetranslation ? "保存并重译" : "确认无误"
    }

    private var saveActionAccessibilityHint: String {
        requiresRetranslation
            ? "保存修正后的 OCR 原文，并只重新翻译此文字块"
            : "确认当前 OCR 原文无误；不会重新翻译"
    }

    private var correctedOriginalAccessibilityHint: String {
        if isSaving {
            return "正在重新翻译当前文字块；暂不能编辑或忽略"
        }
        if !canSave {
            return "请输入非空 OCR 原文；保存后只会重新翻译当前文字块，不会重新识别整张图片"
        }
        if requiresRetranslation {
            return "保存会只重新翻译当前文字块，不会重新识别整张图片"
        }
        return "当前文字与 OCR 原文相同；保存会确认无误，不会重新翻译"
    }

    private var ignoreActionAccessibilityHint: String {
        isSaving
            ? "正在重新翻译当前文字块；完成前不能忽略"
            : "从本次图片的预览、导出和当前转录中移除此 OCR 文字块；稍后可在图片检查区恢复"
    }

    private func requestDismiss() {
        guard !isSaving else { return }
        dismissKeyboard()
        guard hasUnsavedChanges else {
            dismiss()
            return
        }
        showDiscardCorrectionConfirmation = true
    }

    private func requestIgnoreConfirmation() {
        guard !isSaving else { return }
        dismissKeyboard()
        showIgnoreBlockConfirmation = true
    }

    private func ignoreCurrentBlock() {
        guard !isSaving else { return }
        errorMessage = nil
        guard requestIgnore() else {
            errorMessage = store.imageTranslationCorrectionMessage ?? "当前文字块无法忽略，请重试"
            return
        }
        dismiss()
    }

    private func save() {
        errorMessage = nil
        dismissKeyboard()
        Task {
            if await store.correctImageTranslationBlock(block.id, original: normalizedCorrectedOriginal) {
                didSave()
                dismiss()
            } else {
                errorMessage = store.imageTranslationCorrectionMessage ?? "文字修正未完成，请重试"
            }
        }
    }

    private func dismissKeyboard() {
        correctedOriginalFocused = false
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
