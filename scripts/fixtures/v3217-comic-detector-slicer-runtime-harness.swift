import CoreGraphics
import Foundation
import ImageIO

@main
enum ComicDetectorSlicerRuntimeHarness {
    private static let sourceCopies = 4

    static func main() async throws {
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw HarnessError.imageDecodeFailed
        }
        let tallHeight = image.height * sourceCopies
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: tallHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw HarnessError.imageRenderFailed
        }
        context.interpolationQuality = .none
        for copy in 0..<sourceCopies {
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: copy * image.height,
                    width: image.width,
                    height: image.height
                )
            )
        }
        guard let tallImage = context.makeImage() else {
            throw HarnessError.imageRenderFailed
        }

        let regions = try await ComicTextBubbleDetectorService.shared.detectTextRegions(
            in: tallImage
        )
        print("copies=\(sourceCopies)")
        print("image=\(tallImage.width)x\(tallImage.height)")
        print("regions=\(regions.count)")
        for region in regions.sorted(by: regionOrder) {
            print(
                String(
                    format: "region=%.6f,%.6f,%.6f,%.6f confidence=%.6f",
                    region.rect.x,
                    region.rect.y,
                    region.rect.width,
                    region.rect.height,
                    region.confidence
                )
            )
        }
    }

    private static func regionOrder(
        _ left: ComicTextDetectorRegion,
        _ right: ComicTextDetectorRegion
    ) -> Bool {
        if left.rect.y != right.rect.y { return left.rect.y < right.rect.y }
        return left.rect.x > right.rect.x
    }
}

private enum HarnessError: Error {
    case imageDecodeFailed
    case imageRenderFailed
}
