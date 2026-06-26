import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ImageTranslationPanel: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var showImageImporter = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var shareURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                Text("图片翻译")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(store.imageTranslationProgressTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
            }

            Text(store.imageTranslationMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            actionBar

            if store.imageTranslationData != nil {
                HStack(spacing: 8) {
                    ForEach(ImageTranslationOverlayMode.allCases) { mode in
                        Button {
                            store.setImageOverlayMode(mode)
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(store.imageOverlayMode == mode ? .white : .white.opacity(0.58))
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(
                                    store.imageOverlayMode == mode ? Color.appAccent : Color.white.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        store.clearImageTranslation()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .heavy))
                            .frame(width: 34, height: 30)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.72))
                    .accessibilityLabel("清空图片翻译")
                }
            }

            ImageTranslationPreview()

            if !store.imageTranslationBlocks.isEmpty {
                Text(store.imageTranslationSummary)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.50))

                LazyVStack(spacing: 7) {
                    ForEach(store.imageTranslationBlocks.prefix(4)) { block in
                        ImageTranslationBlockRow(block: block)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .fileImporter(isPresented: $showImageImporter, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                store.translateImage(from: url)
            case .failure(let error):
                store.imageTranslationState = .failed
                store.imageTranslationMessage = "图片文件选择失败：\(error.localizedDescription)"
                store.dataTransferMessage = store.imageTranslationMessage
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            store.translateImageData(data, filename: item.itemIdentifier ?? "photo-library-image.png")
                            selectedPhotoItem = nil
                        }
                    }
                } catch {
                    await MainActor.run {
                        store.imageTranslationState = .failed
                        store.imageTranslationMessage = "照片读取失败：\(error.localizedDescription)"
                        store.dataTransferMessage = store.imageTranslationMessage
                        selectedPhotoItem = nil
                    }
                }
            }
        }
        .sheet(item: $shareURL) { url in
            ShareSheet(activityItems: [url])
        }
    }

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                actionButtons
            }

            VStack(spacing: 8) {
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        photoPickerButton(title: store.imageTranslationData == nil ? "选择照片" : "换照片")

        Button {
            showImageImporter = true
        } label: {
            Label("文件", systemImage: "folder")
                .font(.system(size: 12, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .disabled(isRunning)
        .opacity(isRunning ? 0.55 : 1)

        if isRunning {
            Button {
                store.cancelImageTranslation()
            } label: {
                Label("取消", systemImage: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.warning)
        } else if store.imageTranslationState == .failed {
            Button {
                store.retryImageTranslation()
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }

        if let exportURL = store.imageTranslationExportURL {
            Button {
                shareURL = exportURL
            } label: {
                Label("分享结果", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
    }

    private var isRunning: Bool {
        switch store.imageTranslationState {
        case .loading, .recognizing, .translating:
            true
        case .idle, .translated, .failed:
            false
        }
    }

    private func photoPickerButton(title: String) -> some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Label(title, systemImage: "photo.on.rectangle")
                .font(.system(size: 12, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .foregroundStyle(.white)
        .disabled(isRunning)
        .opacity(isRunning ? 0.55 : 1)
    }

    private var icon: String {
        switch store.imageTranslationState {
        case .idle: "photo"
        case .loading: "photo.badge.arrow.down"
        case .recognizing: "viewfinder"
        case .translating: "character.book.closed"
        case .translated: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch store.imageTranslationState {
        case .idle: .white.opacity(0.58)
        case .loading, .recognizing, .translating: Color.warning
        case .translated: Color.success
        case .failed: Color.danger
        }
    }
}

private struct ImageTranslationPreview: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var previewImage: UIImage?

    var body: some View {
        Group {
            if let image = previewImage {
                GeometryReader { geometry in
                    let containerSize = geometry.size
                    let imageSize = image.size
                    let fittedSize = fittedImageSize(imageSize: imageSize, containerSize: containerSize)
                    let origin = CGPoint(
                        x: (containerSize.width - fittedSize.width) / 2,
                        y: (containerSize.height - fittedSize.height) / 2
                    )

                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: containerSize.width, height: containerSize.height)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                .frame(height: previewHeight(for: image.size))
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white.opacity(0.42))
                    Text("选择图片后显示 OCR 定位覆盖层")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.50))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 122)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .onAppear(perform: refreshPreviewImage)
        .onChange(of: store.imageTranslationRevision) { _, _ in
            refreshPreviewImage()
        }
    }

    private func refreshPreviewImage() {
        guard let data = store.imageTranslationData else {
            previewImage = nil
            return
        }

        previewImage = UIImage(data: data)
    }

    private func fittedImageSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func previewHeight(for imageSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return 300
        }

        let aspectRatio = imageSize.height / imageSize.width
        return min(max(320 * aspectRatio, 260), 520)
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(block.translation.isEmpty ? block.original : block.translation)
                        .font(.system(size: 10, weight: .heavy))
                        .lineLimit(4)
                        .minimumScaleFactor(0.70)
                    Text(block.original)
                        .font(.system(size: 8, weight: .bold))
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(0.66))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(width: bubbleWidth, alignment: .leading)
                .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.appAccent)
                        .frame(width: 3)
                }
                .position(x: adjacentCenterX(for: rect), y: rect.midY)

            case .replace:
                Text(block.translation.isEmpty ? block.original : block.translation)
                    .font(.system(size: 10, weight: .heavy))
                    .lineLimit(4)
                    .minimumScaleFactor(0.64)
                    .multilineTextAlignment(.center)
                    .padding(4)
                    .frame(width: max(rect.width, 44), height: max(rect.height, 24))
                    .background(Color.appAccent.opacity(0.82), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
        if rightCenter <= rightLimit {
            return rightCenter
        }

        return max(imageOrigin.x + bubbleWidth / 2, rect.minX - 6 - bubbleWidth / 2)
    }
}

private struct ImageTranslationBlockRow: View {
    let block: ImageTranslationBlock

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(Int(block.confidence * 100))%")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.appAccent)
                .frame(width: 36, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(block.original)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(2)
                Text(block.translation.isEmpty ? "等待翻译..." : block.translation)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
