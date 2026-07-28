import CoreGraphics
import Foundation
import ImageIO

struct ImagePreviewImage: @unchecked Sendable {
    let cgImage: CGImage
}

enum ImagePreviewService {
    static let maximumPixelSize = 2_048

    static func makePreview(
        from data: Data,
        maximumPixelSize: Int = maximumPixelSize
    ) async -> ImagePreviewImage? {
        guard !data.isEmpty, maximumPixelSize > 0 else { return nil }

        let previewTask = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return nil as ImagePreviewImage? }
            return autoreleasepool {
                makePreviewSynchronously(from: data, maximumPixelSize: maximumPixelSize)
            }
        }

        return await withTaskCancellationHandler {
            await previewTask.value
        } onCancel: {
            previewTask.cancel()
        }
    }

    static func makePreviewSynchronously(
        from data: Data,
        maximumPixelSize: Int = maximumPixelSize
    ) -> ImagePreviewImage? {
        guard !data.isEmpty, maximumPixelSize > 0, !Task.isCancelled else { return nil }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        guard !Task.isCancelled,
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  thumbnailOptions as CFDictionary
              ),
              !Task.isCancelled else {
            return nil
        }

        return ImagePreviewImage(cgImage: cgImage)
    }
}
