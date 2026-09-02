import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImageOCRDetectionView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var imageFileSelectionID: UUID?
    @State private var showingCamera = false
    @State private var selectedBlockID: UUID?
    @State private var lowConfidenceOnly = false
    @State private var diagnosticsExpanded = false
    @State private var editingBlock: ImageTranslationBlock?
    @State private var showingTextExporter = false
    @State private var showingJSONExporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                AppPageHeader(
                    title: "OCR 检测",
                    subtitle: "上传图片，查看识别框、原文和质量状态",
                    systemImage: "text.viewfinder",
                    status: headerStatus,
                    statusTone: headerStatusTone,
                    feature: .ocr
                )

                inputSection
                recognitionOptions

                if store.imageOCRDetectionState.isRunning {
                    if store.imageOCRDetectionRerecognizingBlockID == nil {
                        fullRecognitionProgress
                    } else {
                        scopedRecognitionProgress
                    }
                }

                if let imageData = store.imageOCRDetectionData {
                    recognitionWorkspace(imageData: imageData)
                } else if !store.imageOCRDetectionState.isRunning {
                    AppEmptyState(
                        title: "等待一张图片",
                        detail: "支持上传图片、拍照和粘贴图片。识别后会在原图上叠加文字框。",
                        systemImage: "photo.badge.plus"
                    )
                    .appSurface()
                }

                if !store.imageOCRDetectionBlocks.isEmpty {
                    diagnosticsSection
                }
            }
            .padding(.vertical, AppTheme.Spacing.section)
        }
        .scrollIndicators(.hidden)
        .enterprisePageFrame(maxWidth: AppTheme.Layout.workspaceMaxWidth)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image]
        ) { result in
            guard let selectionID = imageFileSelectionID else { return }
            imageFileSelectionID = nil
            store.handleSelectedImageOCRFile(result, selectionID: selectionID)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            loadSelectedPhoto(newItem)
        }
        .sheet(isPresented: $showingCamera) {
            ImageOCRCameraPicker(
                onImage: { data in
                    showingCamera = false
                    store.recognizeImageOCRData(data, filename: "camera-image.png")
                },
                onCancel: {
                    showingCamera = false
                }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $editingBlock) { block in
            ImageOCRDetectionEditor(block: block) { text in
                _ = store.updateImageOCRDetectionBlock(block.id, original: text)
            }
        }
        .fileExporter(
            isPresented: $showingTextExporter,
            document: OCRTextFileDocument(text: store.imageOCRDetectionTextExport()),
            contentType: .plainText,
            defaultFilename: exportBaseName + ".txt"
        ) { result in
            reportExportResult(result, kind: "TXT")
        }
        .fileExporter(
            isPresented: $showingJSONExporter,
            document: OCRJSONFileDocument(data: store.imageOCRDetectionJSONExport() ?? Data()),
            contentType: .json,
            defaultFilename: exportBaseName + ".json"
        ) { result in
            reportExportResult(result, kind: "JSON")
        }
    }

    private var headerStatus: String {
        if let rerecognizingID = store.imageOCRDetectionRerecognizingBlockID,
           let index = store.imageOCRDetectionBlocks.firstIndex(where: { $0.id == rerecognizingID }) {
            return "复查第 \(index + 1) 块"
        }
        switch store.imageOCRDetectionState {
        case .idle:
            return store.imageOCRDetectionData == nil ? "待上传" : "可开始识别"
        case .preparing, .detecting, .recognizing, .arranging:
            return store.imageOCRDetectionState.title
        case .completed:
            return "\(store.imageOCRDetectionBlocks.count) 个文字块"
        case .failed:
            return "需要重试"
        }
    }

    private var headerStatusTone: AppStatusTone {
        switch store.imageOCRDetectionState {
        case .idle: .neutral
        case .preparing, .detecting, .recognizing, .arranging: .active
        case .completed: .success
        case .failed: .danger
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
            AppSectionHeader(
                title: "图片输入",
                subtitle: store.imageOCRDetectionFilename.isEmpty
                    ? "支持本机处理"
                    : store.imageOCRDetectionFilename,
                systemImage: "photo"
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.control) {
                    inputButtons
                }
                VStack(spacing: AppTheme.Spacing.control) {
                    inputButtons
                }
            }

            if !store.imageOCRDetectionMessage.isEmpty {
                AppStatusRow(
                    title: store.imageOCRDetectionState.title,
                    detail: store.imageOCRDetectionMessage,
                    tone: headerStatusTone
                )
            }
        }
        .appSurface()
    }

    @ViewBuilder
    private var inputButtons: some View {
        OCRDetectionActionButton(
            title: "上传图片",
            systemImage: "arrow.up.doc",
            prominent: true
        ) {
            imageFileSelectionID = store.beginImageOCRFileSelection()
            showingFileImporter = true
        }

        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Label("相册", systemImage: "photo.on.rectangle")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget)
                .padding(.horizontal, AppTheme.Spacing.control)
                .foregroundStyle(Color.appTextPrimary)
                .background(Color.appSurfaceRaised, in: .rect(cornerRadius: AppTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                        .stroke(Color.appBorder, lineWidth: 1)
                }
        }
        .accessibilityHint("从照片图库选择一张图片进行 OCR 检测")

        OCRDetectionActionButton(
            title: "拍照",
            systemImage: "camera",
            disabled: !UIImagePickerController.isSourceTypeAvailable(.camera)
        ) {
            showingCamera = true
        }

        OCRDetectionActionButton(title: "粘贴图片", systemImage: "doc.on.clipboard") {
            pasteImage()
        }

        if store.imageOCRDetectionData != nil {
            OCRDetectionActionButton(title: "清空", systemImage: "trash", tone: .danger) {
                store.clearImageOCRDetection()
                selectedBlockID = nil
            }
        }
    }

    private var recognitionOptions: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
            AppSectionHeader(
                title: "识别选项",
                subtitle: "语言和版式独立选择",
                systemImage: "slider.horizontal.3"
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.section) {
                    languagePicker
                    layoutPicker
                }
                VStack(spacing: AppTheme.Spacing.control) {
                    languagePicker
                    layoutPicker
                }
            }

            if store.imageOCRDetectionDirectionRereadEnabled {
                Label(
                    "日语竖排会自动启用 90°/270° 方向复读",
                    systemImage: "rotate.3d"
                )
                .font(.footnote)
                .foregroundStyle(Color.appAccent)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("自动识别与显式日语会沿用现有质量门；显式选择日语竖排或漫画竖排时自动启用方向复读，版式偏好不改写检测框。")
                    .font(.footnote)
                    .foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appSurface()
        .disabled(store.isImageOCRDetectionRunning)
        .opacity(store.isImageOCRDetectionRunning ? 0.65 : 1)
    }

    private var languagePicker: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("语言")
                .font(.caption.bold())
                .foregroundStyle(Color.appTextSecondary)
            Picker("语言", selection: Binding(
                get: { store.imageOCRDetectionLanguage },
                set: { store.imageOCRDetectionLanguage = $0 }
            )) {
                ForEach(ImageOCRDetectionLanguage.allCases) { language in
                    Text(language.rawValue).tag(language)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var layoutPicker: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("版式")
                .font(.caption.bold())
                .foregroundStyle(Color.appTextSecondary)
            Picker("版式", selection: Binding(
                get: { store.imageOCRDetectionLayout },
                set: { store.imageOCRDetectionLayout = $0 }
            )) {
                ForEach(ImageOCRDetectionLayout.allCases) { layout in
                    Text(layout.rawValue).tag(layout)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fullRecognitionProgress: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
            AppSectionHeader(
                title: "正在识别",
                subtitle: "可随时取消，原有结果不会进入翻译流程",
                systemImage: "hourglass"
            )

            HStack(spacing: AppTheme.Spacing.control) {
                ForEach(ImageOCRDetectionProgressStage.allCases) { stage in
                    ImageOCRDetectionStageLabel(
                        stage: stage,
                        currentState: store.imageOCRDetectionState
                    )
                }
            }

            ProgressView()
                .tint(Color.appAccent)

            OCRDetectionActionButton(title: "取消 OCR", systemImage: "xmark.circle", tone: .danger) {
                store.cancelImageOCRDetection()
            }
        }
        .appSurface()
    }

    private var scopedRecognitionProgress: some View {
        HStack(spacing: AppTheme.Spacing.control) {
            ProgressView()
                .tint(Color.appAccent)
            Text(store.imageOCRDetectionMessage)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
            Spacer(minLength: 0)
            Button("取消") {
                store.cancelImageOCRDetectionBlockRerecognition()
            }
            .buttonStyle(.bordered)
        }
        .padding(AppTheme.Spacing.section)
        .background(Color.appSurface, in: .rect(cornerRadius: AppTheme.Radius.surface))
    }

    private func recognitionWorkspace(imageData: Data) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.page) {
                ImageOCRDetectionCanvas(
                    imageData: imageData,
                    revision: store.imageOCRDetectionRevision,
                    blocks: store.imageOCRDetectionBlocks,
                    selectedBlockID: selectedBlockID,
                    onSelect: { selectedBlockID = $0 }
                )
                .frame(maxWidth: 600)

                resultList
                    .frame(maxWidth: 520)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                ImageOCRDetectionCanvas(
                    imageData: imageData,
                    revision: store.imageOCRDetectionRevision,
                    blocks: store.imageOCRDetectionBlocks,
                    selectedBlockID: selectedBlockID,
                    onSelect: { selectedBlockID = $0 }
                )
                resultList
            }
        }
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.control) {
                    resultListHeader
                    Spacer(minLength: 0)
                    resultActions
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
                    resultListHeader
                    resultActions
                }
            }

            Toggle("只看低置信度（< 0.55）", isOn: $lowConfidenceOnly)
                .font(.subheadline)
                .tint(Color.appAccent)

            if indexedVisibleBlocks.isEmpty {
                AppEmptyState(
                    title: lowConfidenceOnly ? "没有低置信度块" : "暂无 OCR 结果",
                    detail: lowConfidenceOnly ? "当前所有文字块都通过了低置信度筛选。" : "识别完成后，文字块会显示在这里。",
                    systemImage: lowConfidenceOnly ? "checkmark.circle" : "text.viewfinder"
                )
            } else {
                LazyVStack(spacing: AppTheme.Spacing.control) {
                    ForEach(indexedVisibleBlocks) { item in
                        ImageOCRDetectionResultRow(
                            index: item.index,
                            block: item.block,
                            rawConfidence: store.imageOCRDetectionRawConfidence(for: item.block),
                            qualityStatus: store.imageOCRDetectionQualityStatus(for: item.block),
                            isSelected: selectedBlockID == item.block.id,
                            isRerecognizing: store.imageOCRDetectionRerecognizingBlockID == item.block.id,
                            canRerecognize: store.canRerecognizeImageOCRDetectionBlock(item.block.id),
                            onSelect: { selectedBlockID = item.block.id },
                            onRerecognize: {
                                selectedBlockID = item.block.id
                                store.rerecognizeImageOCRDetectionBlock(item.block.id)
                            },
                            onCancelRerecognize: {
                                store.cancelImageOCRDetectionBlockRerecognition()
                            },
                            onEdit: {
                                editingBlock = item.block
                            }
                        )
                    }
                }
            }
        }
        .appSurface()
    }

    private var resultListHeader: some View {
        AppSectionHeader(
            title: "识别结果",
            subtitle: "\(store.imageOCRDetectionBlocks.count) 个文字块",
            systemImage: "list.number"
        )
    }

    private var resultActions: some View {
        HStack(spacing: AppTheme.Spacing.control) {
            OCRDetectionActionButton(title: "复制全部", systemImage: "doc.on.doc") {
                _ = store.copyImageOCRDetectionAll()
            }
            .disabled(store.imageOCRDetectionTextExport().isEmpty)

            Menu {
                Button("导出 TXT", systemImage: "doc.plaintext") {
                    showingTextExporter = true
                }
                Button("导出 JSON", systemImage: "curlybraces") {
                    showingJSONExporter = true
                }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
                    .font(.subheadline.bold())
                    .frame(minHeight: AppTheme.Layout.minimumTarget)
            }
            .disabled(store.imageOCRDetectionBlocks.isEmpty)

            if store.canRetryImageOCRDetection {
                OCRDetectionActionButton(
                    title: store.imageOCRDetectionState == .failed ? "重试" : "按当前选项重新识别",
                    systemImage: "arrow.clockwise",
                    tone: .warning
                ) {
                    store.retryImageOCRDetection()
                }
            }
        }
    }

    private var indexedVisibleBlocks: [IndexedOCRBlock] {
        store.imageOCRDetectionBlocks.enumerated().compactMap { index, block in
            if lowConfidenceOnly && !ImageOCRResultSummary.hasLowConfidence(block) {
                return nil
            }
            return IndexedOCRBlock(index: index, block: block)
        }
    }

    private var diagnosticsSection: some View {
        DisclosureGroup(isExpanded: $diagnosticsExpanded) {
            OCRDetectionDiagnostics(metrics: store.imageOCRDetectionMetrics)
                .padding(.top, AppTheme.Spacing.control)
        } label: {
            AppSectionHeader(
                title: "诊断信息",
                subtitle: "默认折叠 · 原始分数与质量状态分开显示",
                systemImage: "waveform.path.ecg"
            )
        }
        .tint(Color.appTextPrimary)
        .appSurface()
    }

    private var exportBaseName: String {
        let filename = store.imageOCRDetectionFilename
        let base = filename.split(separator: ".", omittingEmptySubsequences: true).first.map(String.init)
        return "ocr-\(base?.isEmpty == false ? base! : "result")"
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        selectedPhotoItem = nil
        store.recognizeImageOCRTransfer(filename: "photo-library-image.png") {
            try await item.loadTransferable(type: Data.self)
        }
    }

    private func pasteImage() {
        guard let image = UIPasteboard.general.image,
              let data = image.pngData() ?? image.jpegData(compressionQuality: 0.95) else {
            store.reportImageOCRDetectionInputError("剪贴板中没有可读取的图片")
            return
        }
        store.recognizeImageOCRData(data, filename: "pasted-image.png")
    }

    private func reportExportResult(_ result: Result<URL, Error>, kind: String) {
        switch result {
        case .success:
            store.reportImageOCRDetectionInputError("已导出 OCR \(kind) 文件")
        case .failure(let error):
            if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled {
                return
            }
            store.reportImageOCRDetectionInputError("OCR \(kind) 导出失败：\(error.localizedDescription)")
        }
    }
}

private struct IndexedOCRBlock: Identifiable {
    let index: Int
    let block: ImageTranslationBlock

    var id: UUID { block.id }
}

private struct OCRDetectionActionButton: View {
    let title: String
    let systemImage: String
    var tone: AppStatusTone = .neutral
    var prominent = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget)
                .padding(.horizontal, AppTheme.Spacing.control)
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? Color.appCanvas : (tone == .neutral ? Color.appTextPrimary : tone.color))
        .background(
            prominent ? Color.appAccent : Color.appSurfaceRaised,
            in: .rect(cornerRadius: AppTheme.Radius.control)
        )
        .overlay {
            if !prominent {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .opacity(disabled ? 0.45 : 1)
        .disabled(disabled)
    }
}

private struct ImageOCRDetectionCanvas: View {
    let imageData: Data
    let revision: Int
    let blocks: [ImageTranslationBlock]
    let selectedBlockID: UUID?
    let onSelect: (UUID) -> Void
    @State private var preview: ImagePreviewImage?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
            AppSectionHeader(
                title: "原图与识别框",
                subtitle: blocks.isEmpty ? "识别中…" : "点击文字块可高亮原图区域",
                systemImage: "viewfinder"
            )

            Group {
                if let preview {
                    GeometryReader { geometry in
                        let imageWidth = CGFloat(preview.cgImage.width)
                        let imageHeight = CGFloat(preview.cgImage.height)
                        let aspectRatio = imageWidth / max(imageHeight, 1)
                        let displayWidth = min(geometry.size.width, geometry.size.height * aspectRatio)
                        let displayHeight = displayWidth / max(aspectRatio, 0.01)
                        let originX = (geometry.size.width - displayWidth) / 2
                        let originY = (geometry.size.height - displayHeight) / 2

                        ZStack(alignment: .topLeading) {
                            Image(decorative: preview.cgImage, scale: 1, orientation: .up)
                            .resizable()
                            .accessibilityLabel("OCR 原图")
                            .frame(width: displayWidth, height: displayHeight)
                            .position(
                                x: originX + displayWidth / 2,
                                y: originY + displayHeight / 2
                            )

                            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                                if let box = block.boundingBox.normalizedToUnit() {
                                    ImageOCRDetectionBox(
                                        index: index,
                                        block: block,
                                        rect: CGRect(
                                            x: originX + CGFloat(box.x) * displayWidth,
                                            y: originY + CGFloat(box.y) * displayHeight,
                                            width: CGFloat(box.width) * displayWidth,
                                            height: CGFloat(box.height) * displayHeight
                                        ),
                                        isSelected: selectedBlockID == block.id,
                                        onSelect: { onSelect(block.id) }
                                    )
                                }
                            }
                        }
                    }
                    .frame(minHeight: 320, idealHeight: 480)
                } else {
                    ContentUnavailableView(
                        "图片准备中",
                        systemImage: "photo",
                        description: Text("原图载入后会显示 OCR 框选结果")
                    )
                    .frame(minHeight: 320)
                }
            }
            .background(Color.black.opacity(0.06), in: .rect(cornerRadius: AppTheme.Radius.surface))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.surface)
                    .stroke(Color.appBorder, lineWidth: 1)
            }

            HStack(spacing: AppTheme.Spacing.section) {
                OCRLegendSwatch(color: .green, title: "≥ 0.90")
                OCRLegendSwatch(color: .yellow, title: "0.60–0.89")
                OCRLegendSwatch(color: .red, title: "< 0.60")
                Spacer(minLength: 0)
            }
            .font(.caption)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("框线颜色：绿色通过，黄色中等置信度，红色需复核")
        }
        .appSurface()
        .task(id: revision) {
            preview = await ImagePreviewService.makePreview(from: imageData)
        }
    }
}

private struct ImageOCRDetectionBox: View {
    let index: Int
    let block: ImageTranslationBlock
    let rect: CGRect
    let isSelected: Bool
    let onSelect: () -> Void

    private var color: Color {
        let confidence = ImageOCRResultSummary.normalizedConfidence(block.confidence)
        if confidence >= 0.90 { return .green }
        if confidence >= 0.60 { return .yellow }
        return .red
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(color.opacity(isSelected ? 0.24 : 0.10))
                    .overlay {
                        Rectangle()
                            .stroke(color, lineWidth: isSelected ? 4 : 2)
                    }

                Text(String(format: "%02d", index + 1))
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(color, in: Circle())
                    .offset(x: -8, y: -8)
            }
            .frame(width: max(rect.width, 12), height: max(rect.height, 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(width: max(rect.width, 12), height: max(rect.height, 12))
        .position(x: rect.midX, y: rect.midY)
        .accessibilityLabel("第 \(index + 1) 个文字块，\(block.original)，\(ImageOCRDetectionFormatting.direction(block))")
        .accessibilityHint("点击后在结果列表中定位并高亮此文字块")
    }
}

private struct OCRLegendSwatch: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(title)
                .foregroundStyle(Color.appTextSecondary)
        }
    }
}

private struct ImageOCRDetectionResultRow: View {
    let index: Int
    let block: ImageTranslationBlock
    let rawConfidence: Float
    let qualityStatus: String
    let isSelected: Bool
    let isRerecognizing: Bool
    let canRerecognize: Bool
    let onSelect: () -> Void
    let onRerecognize: () -> Void
    let onCancelRerecognize: () -> Void
    let onEdit: () -> Void

    private var qualityTone: AppStatusTone {
        qualityStatus == "通过" ? .success : .warning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.control) {
                        Text(String(format: "%02d", index + 1))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(Color.appAccent)
                        Text(block.original)
                            .font(.body.bold())
                            .foregroundStyle(Color.appTextPrimary)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        AppStatusLabel(text: qualityStatus, tone: qualityTone)
                    }

                    HStack(spacing: AppTheme.Spacing.section) {
                        Label(
                            ImageOCRDetectionFormatting.direction(block),
                            systemImage: ImageOCRDetectionFormatting.directionSymbol(block)
                        )
                        Label(
                            "模型原始分数 \(String(format: "%.3f", Double(rawConfidence)))",
                            systemImage: "gauge.with.dots.needle.33percent"
                        )
                        .accessibilityLabel("模型原始分数 \(String(format: "%.3f", Double(rawConfidence)))")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)

                    Text(ImageOCRDetectionFormatting.position(block.boundingBox))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.appTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            HStack(spacing: AppTheme.Spacing.control) {
                if isRerecognizing {
                    Button("取消复读", systemImage: "xmark.circle", action: onCancelRerecognize)
                        .buttonStyle(.bordered)
                        .tint(Color.appDanger)
                } else {
                    Button("单块重新识别", systemImage: "arrow.clockwise", action: onRerecognize)
                        .buttonStyle(.bordered)
                        .disabled(!canRerecognize)
                }

                Button("手动编辑", systemImage: "pencil", action: onEdit)
                    .buttonStyle(.bordered)
            }
            .font(.caption.bold())
        }
        .padding(AppTheme.Spacing.section)
        .background(
            isSelected ? Color.appAccent.opacity(0.12) : Color.appSurfaceRaised,
            in: .rect(cornerRadius: AppTheme.Radius.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.surface)
                .stroke(isSelected ? Color.appAccent : Color.appBorder, lineWidth: isSelected ? 2 : 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ImageOCRDetectionProgressStage: Identifiable, CaseIterable {
    let state: ImageOCRDetectionState

    static let allCases = [
        Self(state: .preparing),
        Self(state: .detecting),
        Self(state: .recognizing),
        Self(state: .arranging)
    ]

    var id: ImageOCRDetectionState { state }
}

private struct ImageOCRDetectionStageLabel: View {
    let stage: ImageOCRDetectionProgressStage
    let currentState: ImageOCRDetectionState

    private var isCompleted: Bool {
        if currentState == .completed {
            return true
        }
        guard let currentIndex = ImageOCRDetectionProgressStage.allCases.firstIndex(where: { $0.state == currentState }),
              let stageIndex = ImageOCRDetectionProgressStage.allCases.firstIndex(where: { $0.state == stage.state }) else {
            return false
        }
        return stageIndex < currentIndex
    }

    private var isCurrent: Bool { currentState == stage.state }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : (isCurrent ? "arrow.triangle.2.circlepath" : "circle"))
                .foregroundStyle(isCompleted ? Color.appSuccess : (isCurrent ? Color.appAccent : Color.appTextSecondary))
            Text(stage.state.title)
                .font(.caption2)
                .foregroundStyle(isCurrent ? Color.appTextPrimary : Color.appTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct OCRDetectionDiagnostics: View {
    let metrics: ImageOCRDetectionMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: AppTheme.Spacing.control
            ) {
                OCRDiagnosticValue(title: "总耗时", value: milliseconds(metrics.totalMilliseconds), systemImage: "timer")
                OCRDiagnosticValue(title: "图片分辨率", value: resolution, systemImage: "rectangle.dashed")
                OCRDiagnosticValue(title: "识别块数量", value: "\(metrics.blockCount)", systemImage: "square.stack.3d.up")
                OCRDiagnosticValue(title: "字符数量", value: "\(metrics.characterCount)", systemImage: "textformat")
                OCRDiagnosticValue(title: "引擎", value: metrics.engine, systemImage: "cpu")
                OCRDiagnosticValue(title: "模型", value: metrics.model, systemImage: "shippingbox")
                OCRDiagnosticValue(title: "语言", value: metrics.language.rawValue, systemImage: "character.book.closed")
                OCRDiagnosticValue(title: "版式", value: metrics.layout.rawValue, systemImage: "rectangle.3.group")
            }

            Divider().overlay(Color.appBorder)

            Text("阶段耗时")
                .font(.subheadline.bold())
                .foregroundStyle(Color.appTextPrimary)
            HStack(spacing: AppTheme.Spacing.section) {
                OCRDiagnosticValue(title: "预处理", value: milliseconds(metrics.preprocessingMilliseconds), systemImage: "wand.and.stars")
                OCRDiagnosticValue(title: "检测", value: milliseconds(metrics.detectionMilliseconds), systemImage: "viewfinder")
                OCRDiagnosticValue(title: "OCR", value: milliseconds(metrics.ocrMilliseconds), systemImage: "text.viewfinder")
                OCRDiagnosticValue(title: "布局", value: milliseconds(metrics.layoutMilliseconds), systemImage: "list.number")
            }

            Divider().overlay(Color.appBorder)

            Text("置信度与质量")
                .font(.subheadline.bold())
                .foregroundStyle(Color.appTextPrimary)
            HStack(spacing: AppTheme.Spacing.section) {
                OCRDiagnosticValue(
                    title: "平均模型分数",
                    value: metrics.averageConfidence.map { String(format: "%.3f", $0) } ?? "—",
                    systemImage: "chart.bar"
                )
                OCRDiagnosticValue(
                    title: "低置信比例",
                    value: String(format: "%.1f%%", metrics.lowConfidenceRatio * 100),
                    systemImage: "exclamationmark.triangle"
                )
            }
            HStack(spacing: AppTheme.Spacing.section) {
                ForEach(["≥ 0.90", "0.60–0.89", "< 0.60"], id: \.self) { bucket in
                    OCRDiagnosticValue(
                        title: bucket,
                        value: "\(metrics.confidenceDistribution[bucket, default: 0]) 块",
                        systemImage: "circle.fill"
                    )
                }
            }
            Text("模型原始分数仅在同一引擎内用于复查门控；Vision 与 Manga OCR 不做横向校准比较。")
                .font(.footnote)
                .foregroundStyle(Color.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Color.appBorder)

            Text("速度")
                .font(.subheadline.bold())
                .foregroundStyle(Color.appTextPrimary)
            HStack(spacing: AppTheme.Spacing.section) {
                OCRDiagnosticValue(title: "块/秒", value: rate(metrics.blocksPerSecond), systemImage: "square.stack")
                OCRDiagnosticValue(title: "字符/秒", value: rate(metrics.charactersPerSecond), systemImage: "textformat.size")
                OCRDiagnosticValue(title: "平均毫秒/块", value: milliseconds(metrics.averageMillisecondsPerBlock ?? 0), systemImage: "speedometer")
            }
        }
    }

    private var resolution: String {
        metrics.imageWidth > 0 && metrics.imageHeight > 0
            ? "\(metrics.imageWidth) × \(metrics.imageHeight)"
            : "—"
    }

    private func milliseconds(_ value: Double) -> String {
        value > 0 ? String(format: "%.1f ms", value) : "—"
    }

    private func rate(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "—"
    }
}

private struct OCRDiagnosticValue: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(Color.appTextPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ImageOCRDetectionFormatting {
    static func direction(_ block: ImageTranslationBlock) -> String {
        switch block.effectiveSourceDirection {
        case .horizontal: "横排"
        case .vertical: "竖排"
        case .unknown, .none: "方向待定"
        }
    }

    static func directionSymbol(_ block: ImageTranslationBlock) -> String {
        switch block.effectiveSourceDirection {
        case .horizontal: "text.alignleft"
        case .vertical: "text.alignright"
        case .unknown, .none: "questionmark"
        }
    }

    static func position(_ box: NormalizedImageRect) -> String {
        guard let normalized = box.normalizedToUnit() else { return "框选位置：无效" }
        return String(
            format: "框选位置 x %.3f · y %.3f · w %.3f · h %.3f",
            normalized.x,
            normalized.y,
            normalized.width,
            normalized.height
        )
    }
}

private struct ImageOCRDetectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let block: ImageTranslationBlock
    let onSave: (String) -> Void
    @State private var text: String

    init(block: ImageTranslationBlock, onSave: @escaping (String) -> Void) {
        self.block = block
        self.onSave = onSave
        _text = State(initialValue: block.original)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                Text("OCR 原文可编辑；保存后会更新复制和导出内容")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
                TextEditor(text: $text)
                    .font(.body)
                    .padding(AppTheme.Spacing.control)
                    .background(Color.appSurfaceRaised, in: .rect(cornerRadius: AppTheme.Radius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                            .stroke(Color.appBorder, lineWidth: 1)
                    }
                    .frame(minHeight: 180)
            }
            .padding(AppTheme.Spacing.page)
            .navigationTitle("手动编辑 OCR 原文")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct ImageOCRCameraPicker: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (Data) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.pngData() ?? image.jpegData(compressionQuality: 0.95) else {
                onCancel()
                return
            }
            onImage(data)
        }
    }
}

private struct OCRTextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(
            data: configuration.file.regularFileContents ?? Data(),
            encoding: .utf8
        ) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct OCRJSONFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview("OCR 检测 · 结果") {
    ImageOCRDetectionView()
        .environmentObject(AppPreviewScenario.ocrSuccess.makeStore())
}
