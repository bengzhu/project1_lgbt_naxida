import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImageTranslationView: View {
    @EnvironmentObject private var store: TranslationSessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                AppPageHeader(
                    title: "图片翻译",
                    subtitle: "Vision OCR 与本地翻译",
                    systemImage: "photo.on.rectangle",
                    status: statusTitle,
                    statusTone: statusTone
                )
                ImageTranslationPanel()
            }
            .enterprisePageFrame(maxWidth: AppTheme.Layout.workspaceMaxWidth)
            .padding(.vertical, AppTheme.Spacing.section)
            .padding(.bottom, 72)
        }
        .background(Color.appCanvas)
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
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var showImageImporter = false
    @State private var imageFileSelectionID: UUID?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var shareURL: URL?
    @State private var sharePresentationID = UUID()
    @State private var reviewFilter: ImageOCRReviewFilter = .all

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
            ImageTranslationPreview()
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
                        ImageTranslationBlockRow(block: block)
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

    var body: some View {
        Menu {
            ForEach(SupportedLanguage.allCases) { language in
                Button {
                    store.selectImageSourceLanguage(language)
                } label: {
                    Label(
                        language.rawValue,
                        systemImage: store.imageTranslationDisplayedSourceLanguage == language
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                }
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.control) {
                Label("输入语言", systemImage: "text.viewfinder")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text(store.imageTranslationDisplayedSourceLanguage.rawValue)
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
        .accessibilityValue(store.imageTranslationDisplayedSourceLanguage.rawValue)
        .accessibilityHint("选择图片 OCR 的输入语言；已完成的图片会重新识别和翻译")
    }

    private var isRunning: Bool {
        switch store.imageTranslationState {
        case .loading, .recognizing, .translating: true
        case .idle, .translated, .failed: false
        }
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
                Text(store.imageTranslationDisplayedTargetLanguage.rawValue)
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
        .accessibilityValue(store.imageTranslationDisplayedTargetLanguage.rawValue)
        .accessibilityHint("选择图片翻译的目标语言；已完成的图片会重新翻译，失败或取消的图片会在重试时使用新语言")
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
        if store.imageTranslationDisplayedTargetLanguage == language {
            return "checkmark.circle.fill"
        }
        return store.canUseLanguage(language) ? "circle" : "lock.fill"
    }
}

private struct ImageCommandBar: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let openImporter: () -> Void
    let shareResult: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.Spacing.control) { commands }
            VStack(spacing: AppTheme.Spacing.control) { commands }
        }
    }

    @ViewBuilder private var commands: some View {
        PhotoPickerCommand(
            title: store.imageTranslationData == nil ? "选择照片" : "更换照片",
            selection: $selectedPhotoItem
        )

        AppSecondaryButton(title: "图片文件", systemImage: "folder", action: openImporter)

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
            AppIconButton(title: "清空图片翻译", systemImage: "trash", tone: .danger, action: store.clearImageTranslation)
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

private struct ImageTranslationPreview: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var previewImage: UIImage?

    var body: some View {
        Group {
            if let previewImage {
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
                                imageSize: fittedSize
                            )
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
        .task(id: store.imageTranslationRevision) {
            previewImage = store.imageTranslationData.flatMap(UIImage.init(data:))
        }
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
                .position(x: adjacentCenterX(for: rect), y: rect.midY)
            case .replace:
                Text(block.translation.isEmpty ? block.original : block.translation)
                    .font(.caption.bold())
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .padding(3)
                    .frame(width: max(rect.width, 44), height: max(rect.height, 24))
                    .background(Color.appAccentStrong.opacity(0.94), in: .rect(cornerRadius: 4))
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .foregroundStyle(.white)
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

    var body: some View {
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
        }
        .padding(.vertical, AppTheme.Spacing.control)
        .overlay(alignment: .bottom) { Divider().overlay(Color.appBorder) }
        .accessibilityElement(children: .combine)
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
