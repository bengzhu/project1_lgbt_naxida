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

    @EnvironmentObject private var store: TranslationSessionStore
    @State private var showImageImporter = false
    @State private var imageFileSelectionID: UUID?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var shareURL: URL?
    @State private var sharePresentationID = UUID()
    @State private var reviewFilter: ImageOCRReviewFilter = .all
    @State private var selectedImageTranslationBlockID: UUID?
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
        .onChange(of: store.imageTranslationExportURL) { _, exportURL in
            guard exportURL == nil else { return }
            finishSharing()
        }
        .onDisappear {
            finishSharing()
        }
        .onChange(of: store.imageTranslationRevision) { _, _ in
            selectedImageTranslationBlockID = nil
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
                clearSelection: { selectedImageTranslationBlockID = nil },
                selectPrevious: { selectAdjacentBlock(offset: -1) },
                selectNext: { selectAdjacentBlock(offset: 1) }
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
            }

            Picker("覆盖方式", selection: overlayModeBinding) {
                ForEach(ImageTranslationOverlayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(store.imageTranslationData == nil || isRunning || isRenderingExport)

            AppStatusRow(
                title: statusTitle,
                detail: statusDetail,
                tone: statusTone
            )

            if store.imageTranslationBlocks.isEmpty {
                AppEmptyState(
                    title: "等待图片",
                    detail: "选择照片或图片文件后，本机 OCR 结果会显示在这里。",
                    systemImage: "photo.badge.plus"
                )
            } else if visibleImageTranslationBlocks.isEmpty {
                AppEmptyState(
                    title: "无需复查",
                    detail: "当前结果没有低置信或方向待定文字块。",
                    systemImage: "checkmark.circle"
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visibleImageTranslationBlocks) { block in
                        ImageTranslationBlockRow(
                            block: block,
                            isSelected: selectedImageTranslationBlockID == block.id,
                            select: { toggleSelection(of: block.id) }
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

    private var visibleImageTranslationBlocks: [ImageTranslationBlock] {
        reviewFilter.blocks(from: store.imageTranslationBlocks)
    }

    private func filterTitle(_ filter: ImageOCRReviewFilter) -> String {
        switch filter {
        case .all:
            "全部 \(store.imageTranslationBlocks.count)"
        case .needsReview:
            "待复查 \(ImageOCRResultSummary(blocks: store.imageTranslationBlocks).reviewRequiredBlockCount)"
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
    let clearSelection: () -> Void
    let selectPrevious: () -> Void
    let selectNext: () -> Void
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
                                isSelected: selectedBlockID == block.id
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
                                close: clearSelection,
                                selectPrevious: selectPrevious,
                                selectNext: selectNext
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

private struct ImageTranslationFocusPreview: View {
    let previewImage: UIImage
    let block: ImageTranslationBlock
    let positionText: String
    let canSelectPrevious: Bool
    let canSelectNext: Bool
    let close: () -> Void
    let selectPrevious: () -> Void
    let selectNext: () -> Void

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
            Button("关闭局部放大", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 44)
                .background(Color.black.opacity(0.82), in: Circle())
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
                Button("上一个文字块", systemImage: "chevron.left", action: selectPrevious)
                    .labelStyle(.iconOnly)
                    .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
                    .background(Color.black.opacity(0.82), in: Circle())
                    .disabled(!canSelectPrevious)
                    .opacity(canSelectPrevious ? 1 : 0.35)
                Button("下一个文字块", systemImage: "chevron.right", action: selectNext)
                    .labelStyle(.iconOnly)
                    .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
                    .background(Color.black.opacity(0.82), in: Circle())
                    .disabled(!canSelectNext)
                    .opacity(canSelectNext ? 1 : 0.35)
            }
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("已定位文字块局部放大")
        .accessibilityValue("\(positionText)，\(block.original)")
    }

    private var focusCrop: (image: CGImage, normalizedRect: CGRect)? {
        guard let sourceImage = previewImage.cgImage else { return nil }
        let normalizedRect = normalizedFocusRect
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
        return (croppedImage, effectiveRect)
    }

    private var normalizedFocusRect: CGRect {
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

    private func relativeBlockRect(in cropRect: CGRect) -> CGRect {
        let box = block.boundingBox
        let rect = CGRect(
            x: (CGFloat(box.x) - cropRect.minX) / cropRect.width,
            y: (CGFloat(box.y) - cropRect.minY) / cropRect.height,
            width: CGFloat(box.width) / cropRect.width,
            height: CGFloat(box.height) / cropRect.height
        )
        return rect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
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

    var body: some View {
        let rect = displayRect
        Group {
            switch mode {
            case .adjacent:
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
                .position(x: adjacentCenterX(for: rect), y: rect.midY)
            case .replace:
                Text(block.translation.isEmpty ? block.original : block.translation)
                    .font(.caption.bold())
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .padding(3)
                    .frame(width: max(rect.width, 44), height: max(rect.height, 24))
                    .background(Color.appAccentStrong.opacity(0.94), in: .rect(cornerRadius: 4))
                    .overlay { selectionBorder }
                    .position(x: rect.midX, y: rect.midY)
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
    let select: () -> Void

    var body: some View {
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
                    if ImageOCRResultSummary.requiresReview(block) {
                        HStack(spacing: AppTheme.Spacing.control) {
                            if ImageOCRResultSummary.hasLowConfidence(block) {
                                Label("低置信", systemImage: "exclamationmark.triangle.fill")
                            }
                            if ImageOCRResultSummary.hasUnknownDirection(block) {
                                Label("方向待定", systemImage: "questionmark.diamond.fill")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(Color.appWarning)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "viewfinder.circle.fill")
                        .foregroundStyle(Color.appAccent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.control)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.appAccent.opacity(0.12) : Color.clear)
        .overlay(alignment: .bottom) { Divider().overlay(Color.appBorder) }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected ? "已在图片中定位" : "未定位")
        .accessibilityHint("在图片预览中定位此文字块")
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
