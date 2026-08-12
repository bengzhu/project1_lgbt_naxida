import CoreGraphics
import Foundation
import ImageIO

private func rgbImage(_ pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
    guard pixels.count == width * height * 4 else {
        throw NSError(
            domain: "KoharuDetectorTriangleHarness",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "invalid RGBA fixture"]
        )
    }
    let data = Data(pixels)
    guard let provider = CGDataProvider(data: data as CFData),
          let image = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: width * 4,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo(
                  rawValue: CGBitmapInfo.byteOrder32Big.rawValue
                      | CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
          ) else {
        throw NSError(
            domain: "KoharuDetectorTriangleHarness",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "cannot create RGBA fixture"]
        )
    }
    return image
}

private func fnv1a(_ bytes: [UInt8]) -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in bytes {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return hash
}

private func rgb(_ plane: [UInt8], x: Int, y: Int, width: Int) -> String {
    let offset = (y * width + x) * 3
    return "\(plane[offset]),\(plane[offset + 1]),\(plane[offset + 2])"
}

@main
enum KoharuDetectorTriangleHarness {
    static func main() async throws {
        let source = try rgbImage(
            [
                255, 0, 0, 255,
                0, 255, 0, 255,
                0, 0, 255, 255,
                255, 255, 255, 255,
            ],
            width: 2,
            height: 2
        )
        let plane = try ComicTextBubbleDetectorService.diagnosticKoharuTriangleRGB(source)
        print("preprocess=triangle+device-rgb")
        print("source=2x2 rgba target=640x640")
        print("checksum=\(String(fnv1a(plane), radix: 16))")
        print(
            "corners=\(rgb(plane, x: 0, y: 0, width: 640));"
                + "\(rgb(plane, x: 639, y: 0, width: 640));"
                + "\(rgb(plane, x: 0, y: 639, width: 640));"
                + "\(rgb(plane, x: 639, y: 639, width: 640))"
        )
        print("center=\(rgb(plane, x: 320, y: 320, width: 640))")
        guard plane.count == 640 * 640 * 3 else {
            throw NSError(
                domain: "KoharuDetectorTriangleHarness",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "triangle plane size mismatch"]
            )
        }

        if CommandLine.arguments.count > 1 {
            let url = URL(fileURLWithPath: CommandLine.arguments[1])
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw NSError(
                    domain: "KoharuDetectorTriangleHarness",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "cannot decode detector fixture"]
                )
            }
            let regions = try await ComicTextBubbleDetectorService.shared.detectTextRegions(
                in: image
            )
            print("fixture=test/jap.jpg")
            print("detectorRegions=\(regions.count)")
            guard !regions.isEmpty else {
                throw NSError(
                    domain: "KoharuDetectorTriangleHarness",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "detector returned no regions"]
                )
            }
        }
    }
}
