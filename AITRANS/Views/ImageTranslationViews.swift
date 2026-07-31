import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

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
    static let previewScrollID = "imageTranslationPreview"
    private static let reviewCompletionAccessibilityFocusID = "image-review-complete"

    @EnvironmentObject private var store: TranslationSessionStore
    @State private var showImageImporter = false
    @State private var imageFileSelectionID: UUID?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var shareURL: URL?
    @State private var sharePresentationID = UUID()
    @State private var reviewFilter: ImageOCRReviewFilter = .all
    @State private var selectedImageTranslationBlockID: UUID?
    @State private var editingImageTranslationBlock: ImageTranslationBlock?
    @State private var restoreConfirmationBlock: ImageTranslationBlock?
    @State private var pendingRestoreConfirmationDismissalFocusID: String?
    @State private var pendingRestoreConfirmationDismissalRevision: Int?
    @State private var pendingCorrectionSheetDismissalFocusID: String?
    @State private var pendingCorrectionSheetDismissalRevision: Int?
    @AccessibilityFocusState private var reviewAccessibilityFocusID: String?
    let revealPreview: () -> Void

    var body: some View {
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
        .onChange(of: store.imageTranslationExportURL) { _, exportURL in
            guard exportURL == nil else { return }
            finishSharing()
        }
        .onDisappear {
            finishSharing()
        }
        .onChange(of: store.imageTranslationRevision) { _, _ in
            selectedImageTranslationBlockID = nil
            editingImageTranslationBlock = nil
            restoreConfirmationBlock = nil
            clearPendingRestoreConfirmationDismissalFocus()
            clearPendingCorrectionSheetDismissalFocus()
            reviewAccessibilityFocusID = nil
        }
        .onChange(of: reviewFilter) { _, _ in
            clearHiddenReviewSelection()
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
                selectBlock: selectBlockFromPreview,
                clearSelection: { selectedImageTranslationBlockID = nil },
                selectPrevious: { selectAdjacentBlock(offset: -1) },
                selectNext: { selectAdjacentBlock(offset: 1) },
                editBlock: { beginCorrectionFromFocusPreview(of: $0) },
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
            }

            AppSectionHeader(
                title: "识别结果",
                subtitle: store.imageTranslationSummary,
                systemImage: "viewfinder"
            )

            if !store.imageTranslationBlocks.isEmpty {
                Picker("识别结果筛选", selection: $reviewFilter) {
                    ForEach(ImageOCRReviewFilter.allCases) { filter in
                        Text(filterTitle(filter)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

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

            AppStatusRow(
                title: statusTitle,
                detail: statusDetail,
                tone: statusTone
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
                } else if !store.imageTranslationIgnoredBlocks.isEmpty {
                    AppEmptyState(
                        title: "当前没有保留文字块",
                        detail: "已忽略 \(store.imageTranslationIgnoredBlocks.count) 个 OCR 文字块；图片会以原图导出，可在下方恢复。",
                        systemImage: "eye.slash"
                    )
                } else {
                    AppEmptyState(
                        title: "正在准备识别结果",
                        detail: store.imageTranslationMessage,
                        systemImage: "viewfinder"
                    )
                }
            } else if visibleImageTranslationBlocks.isEmpty {
                if reviewCompletedBlockCount > 0 {
                    AppEmptyState(
                        title: "本次复查完成",
                        detail: "所有风险块都已标记为已复查，可随时重新开始。",
                        systemImage: "checkmark.circle.fill"
                    )
                    .accessibilityFocused(
                        $reviewAccessibilityFocusID,
                        equals: Self.reviewCompletionAccessibilityFocusID
                    )
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
                            accessibilityFocus: $reviewAccessibilityFocusID,
                            select: { toggleSelection(of: block.id) },
                            edit: { beginCorrection(of: block) },
                            restoreVisionOCR: { requestVisionOCRRestore(for: block) },
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

    private func filterTitle(_ filter: ImageOCRReviewFilter) -> String {
        switch filter {
        case .all:
            "全部 \(store.imageTranslationBlocks.count)"
        case .needsReview:
            "待复查 \(reviewRequiredBlocks.count)"
        }
    }

    private func toggleSelection(of blockID: UUID) {
        if selectedImageTranslationBlockID == blockID {
            selectedImageTranslationBlockID = nil
        } else {
            selectedImageTranslationBlockID = blockID
            revealPreview()
        }
    }

    private func beginCorrection(of block: ImageTranslationBlock) {
        guard canModifyImageTranslation,
              store.imageTranslationBlocks.contains(where: { $0.id == block.id }) else {
            return
        }
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
    private func ignoreImageTranslationBlock(_ block: ImageTranslationBlock) -> Bool {
        let activeBlocks = store.imageTranslationBlocks
        guard let activeIndex = activeBlocks.firstIndex(where: { $0.id == block.id }) else {
            return false
        }

        let nextActiveBlockID = activeBlocks.dropFirst(activeIndex + 1).first?.id
            ?? activeBlocks[..<activeIndex].last?.id
        let pendingBlocks = reviewRequiredBlocks
        let nextReviewBlockID = pendingBlocks.firstIndex(where: { $0.id == block.id }).flatMap { index in
            pendingBlocks.dropFirst(index + 1).first?.id
                ?? pendingBlocks[..<index].last?.id
        }

        guard store.ignoreImageTranslationBlock(block.id) else { return false }

        if reviewFilter == .needsReview {
            let nextBlockID = nextReviewBlockID.flatMap { candidate in
                reviewRequiredBlocks.contains(where: { $0.id == candidate }) ? candidate : nil
            } ?? reviewRequiredBlocks.first?.id
            selectedImageTranslationBlockID = nextBlockID
            moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(
                to: nextBlockID.map(reviewRowAccessibilityFocusID)
                    ?? ignoredRowAccessibilityFocusID(block.id)
            )
        } else {
            let nextBlockID = nextActiveBlockID.flatMap { candidate in
                store.imageTranslationBlocks.contains(where: { $0.id == candidate }) ? candidate : nil
            }
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
        reviewFilter = ImageOCRResultSummary.requiresReview(block) ? .needsReview : .all
        selectedImageTranslationBlockID = block.id
        revealPreview()
        moveReviewAccessibilityFocus(to: reviewRowAccessibilityFocusID(block.id))
    }

    private func completeReviewAfterCorrection(_ blockID: UUID) {
        guard store.imageTranslationBlocks.contains(where: { $0.id == blockID }) else { return }
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
            return
        }
        if !visibleImageTranslationBlocks.contains(where: { $0.id == blockID }) {
            reviewFilter = .all
        }
        selectedImageTranslationBlockID = blockID
    }

    private func beginReviewQueue() {
        guard canReviewImageTranslation,
              let firstBlockID = reviewRequiredBlocks.first?.id else { return }
        let retainedBlockID = selectedImageTranslationBlockID.flatMap { selectedBlockID in
            reviewRequiredBlocks.contains(where: { $0.id == selectedBlockID }) ? selectedBlockID : nil
        }
        reviewFilter = .needsReview
        let targetBlockID = retainedBlockID ?? firstBlockID
        selectedImageTranslationBlockID = targetBlockID
        revealPreview()
        moveReviewAccessibilityFocus(to: reviewPreviewAccessibilityFocusID(targetBlockID))
    }

    private func toggleReviewCompletion(_ blockID: UUID, focusInPreview: Bool) {
        guard canReviewImageTranslation,
              allReviewRequiredBlocks.contains(where: { $0.id == blockID }) else { return }
        if store.reopenImageTranslationBlockReview(blockID) {
            reviewFilter = .needsReview
            selectedImageTranslationBlockID = blockID
            moveReviewAccessibilityFocus(
                to: focusInPreview
                    ? reviewPreviewAccessibilityFocusID(blockID)
                    : reviewRowAccessibilityFocusID(blockID)
            )
            return
        }

        let pendingBlocks = reviewRequiredBlocks
        guard let currentIndex = pendingBlocks.firstIndex(where: { $0.id == blockID }) else { return }
        let nextBlockID = pendingBlocks.dropFirst(currentIndex + 1).first?.id
            ?? pendingBlocks[..<currentIndex].last?.id
        guard store.markImageTranslationBlockReviewed(blockID) else { return }
        reviewFilter = .needsReview
        selectedImageTranslationBlockID = nextBlockID
        let nextFocusID = nextBlockID.map {
            focusInPreview
                ? reviewPreviewAccessibilityFocusID($0)
                : reviewRowAccessibilityFocusID($0)
        } ?? Self.reviewCompletionAccessibilityFocusID
        moveReviewAccessibilityFocus(to: nextFocusID)
    }

    private func restartReviewQueue() {
        guard canReviewImageTranslation,
              let firstBlockID = allReviewRequiredBlocks.first?.id else { return }
        store.resetImageTranslationReviewProgress()
        reviewFilter = .needsReview
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
            return
        }
        clearPendingCorrectionSheetDismissalFocus()
        moveReviewAccessibilityFocus(to: focusID)
    }

    private func clearPendingCorrectionSheetDismissalFocus() {
        pendingCorrectionSheetDismissalFocusID = nil
        pendingCorrectionSheetDismissalRevision = nil
    }

    private func moveReviewAccessibilityFocus(to focusID: String?) {
        let revision = store.imageTranslationRevision
        Task { @MainActor in
            await Task.yield()
            guard revision == store.imageTranslationRevision else { return }
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
        selectedImageTranslationBlockID = visibleImageTranslationBlocks[targetIndex].id
    }

    private func clearHiddenReviewSelection() {
        guard let selectedImageTranslationBlockID,
              !visibleImageTranslationBlocks.contains(where: { $0.id == selectedImageTranslationBlockID }) else {
            return
        }
        self.selectedImageTranslationBlockID = nil
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
        .accessibilityHint("图片输入语言设置需要 Pro；已完成的图片会重新识别和翻译；失败或取消后选回当前内容语言会撤销待重试更改")
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
        .accessibilityHint("选择图片翻译的目标语言；已完成的图片会重新翻译，失败或取消的图片会在重试时使用新语言；选回当前内容语言会撤销待重试更改")
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
                selection: $selectedPhotoItem
            )

            AppSecondaryButton(title: "图片文件", systemImage: "folder", action: openImporter)
        } else {
            AppSecondaryButton(
                title: store.imageTranslationData == nil ? "选择照片" : "更换照片",
                systemImage: "lock.fill",
                action: requestImageTranslationAccess
            )
            AppSecondaryButton(
                title: "图片文件",
                systemImage: "lock.fill",
                action: requestImageTranslationAccess
            )
        }

        if isRunning {
            AppSecondaryButton(title: "取消", systemImage: "xmark.circle.fill", tone: .danger, action: store.cancelImageTranslation)
        } else if store.canRetryImageTranslation {
            AppSecondaryButton(title: "重试", systemImage: "arrow.clockwise", tone: .warning, action: store.retryImageTranslation)
        }

        if store.canRerunImageRecognition {
            AppSecondaryButton(
                title: "重新识别",
                systemImage: "text.viewfinder",
                action: store.rerunImageRecognition
            )
        }

        if hasRenderFailure {
            AppSecondaryButton(
                title: "重试导出",
                systemImage: "arrow.clockwise.circle",
                tone: .warning,
                action: store.retryImageTranslationExportRender
            )
        }

        if store.imageTranslationExportURL != nil {
            AppSecondaryButton(
                title: isPreparingShare ? "准备中" : "导出",
                systemImage: isPreparingShare ? "hourglass" : "square.and.arrow.up",
                tone: .success,
                action: shareResult
            )
            .disabled(isPreparingShare)
        }

        if store.imageTranslationData != nil {
            AppIconButton(
                title: "清空图片翻译",
                systemImage: "trash",
                tone: .danger,
                action: requestClearImageTranslation
            )
        }
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
    let selectBlock: (UUID) -> Void
    let clearSelection: () -> Void
    let selectPrevious: () -> Void
    let selectNext: () -> Void
    let editBlock: (ImageTranslationBlock) -> Void
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

                        ForEach(store.imageTranslationBlocks) { block in
                            ImageTranslationOverlayBlock(
                                block: block,
                                mode: store.imageOverlayMode,
                                imageOrigin: origin,
                                imageSize: fittedSize,
                                isSelected: selectedBlockID == block.id,
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
                                canEdit: canEdit,
                                canReview: canReview,
                                modificationUnavailableHint: modificationUnavailableHint,
                                reviewUnavailableHint: reviewUnavailableHint,
                                accessibilityFocus: accessibilityFocus,
                                close: clearSelection,
                                selectPrevious: selectPrevious,
                                selectNext: selectNext,
                                edit: { editBlock(selectedBlock) },
                                toggleReviewCompletion: { toggleReviewCompletion(selectedBlock.id) }
                            )
                            .frame(
                                width: max(180, min(320, geometry.size.width - AppTheme.Spacing.control * 2)),
                                height: 180
                            )
                            .padding(AppTheme.Spacing.control)
                        }
                    }
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
    }

    private var previewFailedForCurrentRevision: Bool {
        previewPhase == .failed(revision: store.imageTranslationRevision)
    }

    private func retryPreview() {
        previewPhase = .loading(revision: store.imageTranslationRevision)
        previewAttempt += 1
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
        let normalizedRect = normalizedFocusRect(for: block)
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

    static func normalizedFocusRect(for block: ImageTranslationBlock) -> CGRect {
        let box = block.boundingBox
        let sourceRect = CGRect(
            x: CGFloat(box.x),
            y: CGFloat(box.y),
            width: CGFloat(box.width),
            height: CGFloat(box.height)
        )
            .standardized
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !sourceRect.isEmpty else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
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
        let box = block.boundingBox
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
        .accessibilityValue("黄色边框为 OCR 文字区域，当前识别为 \(block.original)")
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
    let canEdit: Bool
    let canReview: Bool
    let modificationUnavailableHint: String
    let reviewUnavailableHint: String
    let accessibilityFocus: AccessibilityFocusState<String?>.Binding
    let close: () -> Void
    let selectPrevious: () -> Void
    let selectNext: () -> Void
    let edit: () -> Void
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
                Color.black
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
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: AppTheme.Spacing.compact) {
                Button("关闭局部放大", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Color.black.opacity(0.82), in: Circle())
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
        .accessibilityValue("\(positionText)，\(block.original)")
        .accessibilityFocused(
            accessibilityFocus,
            equals: "image-review-preview-\(block.id.uuidString)"
        )
    }

    private var focusCrop: ImageTranslationBlockFocusCrop? {
        guard let sourceImage = previewImage.cgImage else { return nil }
        return ImageTranslationBlockFocusCrop.make(from: sourceImage, block: block)
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

private struct ImageTranslationOverlayBlock: View {
    let block: ImageTranslationBlock
    let mode: ImageTranslationOverlayMode
    let imageOrigin: CGPoint
    let imageSize: CGSize
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        let rect = displayRect
        Group {
            switch mode {
            case .adjacent:
                Button(action: select) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.translation.isEmpty ? block.original : block.translation)
                            .font(.caption.bold())
                            .lineLimit(4)
                        Text(block.original)
                            .font(.caption2)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(5)
                    .frame(width: bubbleWidth, alignment: .leading)
                    .background(Color.black.opacity(0.88), in: .rect(cornerRadius: 4))
                    .overlay(alignment: .leading) { Rectangle().fill(Color.appAccent).frame(width: 3) }
                    .overlay { selectionBorder }
                }
                .buttonStyle(.plain)
                .frame(minWidth: AppTheme.Layout.minimumTarget, minHeight: AppTheme.Layout.minimumTarget)
                .position(x: adjacentCenterX(for: rect), y: rect.midY)
                .accessibilityLabel("文字块 \(block.original)")
                .accessibilityValue(accessibilityValue)
                .accessibilityHint(accessibilityHint)
            case .replace:
                Button(action: select) {
                    Text(block.translation.isEmpty ? block.original : block.translation)
                        .font(.caption.bold())
                        .lineLimit(4)
                        .multilineTextAlignment(.center)
                        .padding(3)
                        .frame(width: max(rect.width, 44), height: max(rect.height, 24))
                        .background(Color.appAccentStrong.opacity(0.94), in: .rect(cornerRadius: 4))
                        .overlay { selectionBorder }
                }
                .buttonStyle(.plain)
                .frame(minWidth: AppTheme.Layout.minimumTarget, minHeight: AppTheme.Layout.minimumTarget)
                .position(x: rect.midX, y: rect.midY)
                .accessibilityLabel("文字块 \(block.original)")
                .accessibilityValue(accessibilityValue)
                .accessibilityHint(accessibilityHint)
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private var selectionBorder: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white, lineWidth: 3)
        }
    }

    private var displayRect: CGRect {
        let box = block.boundingBox
        return CGRect(
            x: imageOrigin.x + imageSize.width * box.x,
            y: imageOrigin.y + imageSize.height * box.y,
            width: imageSize.width * box.width,
            height: imageSize.height * box.height
        )
    }

    private var bubbleWidth: CGFloat {
        min(max(displayRect.width * 1.45, 78), max(imageSize.width * 0.46, 92))
    }

    private var accessibilityValue: String {
        let translation = block.translation.isEmpty ? "等待翻译" : block.translation
        return isSelected ? "已定位，\(translation)" : "未定位，\(translation)"
    }

    private var accessibilityHint: String {
        isSelected ? "取消图片中的定位" : "在图片中定位并打开局部放大"
    }

    private func adjacentCenterX(for rect: CGRect) -> CGFloat {
        let rightCenter = rect.maxX + 6 + bubbleWidth / 2
        let rightLimit = imageOrigin.x + imageSize.width - bubbleWidth / 2
        if rightCenter <= rightLimit { return rightCenter }
        return max(imageOrigin.x + bubbleWidth / 2, rect.minX - 6 - bubbleWidth / 2)
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
    let accessibilityFocus: AccessibilityFocusState<String?>.Binding
    let select: () -> Void
    let edit: () -> Void
    let restoreVisionOCR: () -> Void
    let toggleReviewCompletion: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.compact) {
            Button(action: select) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.control) {
                    Text(block.confidence, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(Color.appAccent)
                        .frame(width: 46, alignment: .leading)
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Text(block.translation.isEmpty ? "等待翻译" : block.translation)
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.appTextPrimary)
                        Text(block.original)
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
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
            .accessibilityValue(isSelected ? "已在图片中定位" : "未定位")
            .accessibilityHint(
                isSelected
                    ? "取消此文字块在图片中的定位"
                    : "在图片预览中定位此文字块"
            )
            .accessibilityFocused(
                accessibilityFocus,
                equals: "image-review-row-\(block.id.uuidString)"
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
                Text(block.original)
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
    }
}

private struct ImageOCRCorrectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TranslationSessionStore

    let block: ImageTranslationBlock
    let imageData: Data?
    let didSave: () -> Void
    let requestIgnore: () -> Bool

    @State private var correctedOriginal: String
    @State private var errorMessage: String?
    @State private var showDiscardCorrectionConfirmation = false
    @State private var showIgnoreBlockConfirmation = false
    @FocusState private var correctedOriginalFocused: Bool

    init(
        block: ImageTranslationBlock,
        imageData: Data?,
        didSave: @escaping () -> Void,
        requestIgnore: @escaping () -> Bool
    ) {
        self.block = block
        self.imageData = imageData
        self.didSave = didSave
        self.requestIgnore = requestIgnore
        _correctedOriginal = State(initialValue: block.original)
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
                                Text(block.confidence, format: .percent.precision(.fractionLength(0)))
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
                }

                Section("当前翻译") {
                    Text(block.translation.isEmpty ? "等待翻译" : block.translation)
                        .foregroundStyle(Color.appTextSecondary)
                }

                Section("识别有误？") {
                    Button(role: .destructive, action: requestIgnoreConfirmation) {
                        Label("忽略此文字块", systemImage: "eye.slash")
                    }
                    .disabled(isSaving)
                    .accessibilityHint("从本次图片的预览、导出和当前转录中移除此 OCR 文字块；稍后可在图片检查区恢复")
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
