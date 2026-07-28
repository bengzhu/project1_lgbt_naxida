import CoreGraphics
import Foundation
import ImageIO

enum PreviewEvaluatorError: Error {
    case bitmapCreationFailed
    case imageCreationFailed
    case destinationCreationFailed
    case destinationFinalizeFailed
    case previewCreationFailed
    case assertionFailed(String)
}

private func makeJPEG(width: Int, height: Int, orientation: Int) throws -> Data {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw PreviewEvaluatorError.bitmapCreationFailed
    }
    context.setFillColor(red: 0.15, green: 0.45, blue: 0.75, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else {
        throw PreviewEvaluatorError.imageCreationFailed
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        "public.jpeg" as CFString,
        1,
        nil
    ) else {
        throw PreviewEvaluatorError.destinationCreationFailed
    }
    CGImageDestinationAddImage(
        destination,
        image,
        [kCGImagePropertyOrientation: orientation] as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
        throw PreviewEvaluatorError.destinationFinalizeFailed
    }
    return data as Data
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw PreviewEvaluatorError.assertionFailed(message) }
}

@main
struct ImagePreviewDownsampleEvaluator {
    static func main() async throws {
        let landscapeData = try makeJPEG(width: 400, height: 200, orientation: 1)
        guard let landscape = ImagePreviewService.makePreviewSynchronously(
            from: landscapeData,
            maximumPixelSize: 100
        ) else {
            throw PreviewEvaluatorError.previewCreationFailed
        }
        try require(landscape.cgImage.width == 100, "landscape width must be capped")
        try require(landscape.cgImage.height == 50, "landscape aspect ratio must be preserved")

        let rotatedData = try makeJPEG(width: 400, height: 200, orientation: 6)
        guard let rotated = await ImagePreviewService.makePreview(
            from: rotatedData,
            maximumPixelSize: 100
        ) else {
            throw PreviewEvaluatorError.previewCreationFailed
        }
        try require(rotated.cgImage.width == 50, "EXIF rotation must swap preview width")
        try require(rotated.cgImage.height == 100, "EXIF rotation must swap preview height")
        try require(max(rotated.cgImage.width, rotated.cgImage.height) <= 100, "preview exceeds cap")

        try require(
            ImagePreviewService.makePreviewSynchronously(from: Data(), maximumPixelSize: 100) == nil,
            "empty input must be rejected"
        )
        try require(
            ImagePreviewService.makePreviewSynchronously(from: Data("not-an-image".utf8)) == nil,
            "invalid image data must be rejected"
        )
        try require(
            ImagePreviewService.makePreviewSynchronously(from: landscapeData, maximumPixelSize: 0) == nil,
            "non-positive cap must be rejected"
        )

        print("v3.10 image preview downsample evaluator passed")
    }
}
