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

private func grayImage(_ pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
    guard pixels.count == width * height else {
        throw NSError(
            domain: "KoharuNearestPreprocessHarness",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "invalid grayscale fixture"]
        )
    }
    let data = Data(pixels)
    guard let provider = CGDataProvider(data: data as CFData),
          let image = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 8,
              bytesPerRow: width,
              space: CGColorSpaceCreateDeviceGray(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
          ) else {
        throw NSError(
            domain: "KoharuNearestPreprocessHarness",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "cannot create grayscale fixture"]
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
enum KoharuNearestMangaPreprocessHarness {
    static func main() throws {
        let source = try grayImage([1, 2, 3, 4, 5, 6], width: 3, height: 2)
        let plane = try MangaOCRService.diagnosticKoharuNearestGrayscale(source)
        let row0 = 0
        let row111 = 111 * 224
        let row112 = 112 * 224
        print("preprocess=nearest")
        print("source=3x2 target=224x224")
        print("checksum=\(String(fnv1a(plane), radix: 16))")
        print(
            "samples=\(plane[row0]),\(plane[row0 + 74]),\(plane[row0 + 75]),"
                + "\(plane[row0 + 148]),\(plane[row0 + 149]),\(plane[row0 + 223]),"
                + "\(plane[row111]),\(plane[row112]),\(plane[row112 + 223])"
        )

        guard plane.count == 224 * 224,
              plane[row0] == 1,
              plane[row0 + 74] == 1,
              plane[row0 + 75] == 2,
              plane[row0 + 148] == 2,
              plane[row0 + 149] == 2,
              plane[row0 + 223] == 3,
              plane[row111] == 1,
              plane[row112] == 4,
              plane[row112 + 223] == 6 else {
            throw NSError(
                domain: "KoharuNearestPreprocessHarness",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "nearest coordinate mapping mismatch samples="
                        + "\(plane[row0]),\(plane[row0 + 74]),\(plane[row0 + 75]),"
                        + "\(plane[row0 + 148]),\(plane[row0 + 149]),\(plane[row0 + 223]),"
                        + "\(plane[row111]),\(plane[row112]),\(plane[row112 + 223])"
                ]
            )
        }

        let quadrants = try grayImage([16, 32, 64, 128], width: 2, height: 2)
        let quadrantPlane = try MangaOCRService.diagnosticKoharuNearestGrayscale(quadrants)
        guard quadrantPlane[0] == 16,
              quadrantPlane[111] == 16,
              quadrantPlane[112] == 32,
              quadrantPlane[111 * 224] == 16,
              quadrantPlane[112 * 224] == 64,
              quadrantPlane.last == 128 else {
            throw NSError(
                domain: "KoharuNearestPreprocessHarness",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "quadrant orientation mismatch"]
            )
        }
        print("quadrants=16,32,64,128")
    }
}
