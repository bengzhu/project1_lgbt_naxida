import CoreGraphics
import Foundation

struct ImageOCRLayoutPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

struct ImageOCRLayoutQuad: Equatable, Sendable {
    var points: [ImageOCRLayoutPoint]

    func normalized() -> Self? {
        guard points.count == 4,
              points.allSatisfy({
                  $0.x.isFinite && $0.y.isFinite
                      && $0.x >= 0 && $0.x <= 1
                      && $0.y >= 0 && $0.y <= 1
              }) else {
            return nil
        }
        return self
    }
}

private func rgbImage(_ pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
    guard pixels.count == width * height * 4 else {
        throw NSError(
            domain: "KoharuRGBLumaHarness",
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
            domain: "KoharuRGBLumaHarness",
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

@main
enum KoharuMangaOCRRGBLumaHarness {
    static func main() throws {
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
        let plane = try MangaOCRService.diagnosticKoharuNearestGrayscale(source)
        let topLeft = 0
        let topRight = 223
        let bottomLeft = 223 * 224
        let bottomRight = plane.count - 1
        print("preprocess=nearest+luma-floor")
        print("source=2x2 rgba target=224x224")
        print("rgbLuma=\(plane[topLeft]),\(plane[topRight]),\(plane[bottomLeft]),\(plane[bottomRight])")
        print("checksum=\(String(fnv1a(plane), radix: 16))")

        guard plane.count == 224 * 224,
              plane[topLeft] == 54,
              plane[topRight] == 182,
              plane[bottomLeft] == 18,
              plane[bottomRight] == 255 else {
            throw NSError(
                domain: "KoharuRGBLumaHarness",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "RGB luma mismatch samples="
                        + "\(plane[topLeft]),\(plane[topRight]),"
                        + "\(plane[bottomLeft]),\(plane[bottomRight])"
                ]
            )
        }

        let floorProbe = try rgbImage([0, 1, 0, 255], width: 1, height: 1)
        let floorPlane = try MangaOCRService.diagnosticKoharuNearestGrayscale(floorProbe)
        print("floorProbe=\(floorPlane[0])")
        guard floorPlane[0] == 0 else {
            throw NSError(
                domain: "KoharuRGBLumaHarness",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "luma conversion rounded instead of flooring"]
            )
        }
    }
}
