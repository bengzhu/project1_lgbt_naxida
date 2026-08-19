import CoreGraphics
import Foundation

struct ImageOCRLayoutPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

struct ImageOCRLayoutRect: Equatable, Codable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    func normalizedToUnit() -> Self? {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0 else {
            return nil
        }
        let left = min(max(x, 0), 1)
        let top = min(max(y, 0), 1)
        let right = min(max(x + width, 0), 1)
        let bottom = min(max(y + height, 0), 1)
        guard right > left, bottom > top else { return nil }
        return Self(
            x: left,
            y: top,
            width: right - left,
            height: bottom - top
        )
    }
}

struct ImageOCRLayoutQuad: Equatable, Sendable {
    var points: [ImageOCRLayoutPoint]

    func normalized() -> Self? {
        guard points.count == 4,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return nil
        }
        let safe = points.map {
            ImageOCRLayoutPoint(
                x: min(max($0.x, 0), 1),
                y: min(max($0.y, 0), 1)
            )
        }
        return Self(points: safe)
    }
}

private func fixtureImage() throws -> CGImage {
    let width = 4
    let height = 4
    var pixels: [UInt8] = []
    pixels.reserveCapacity(width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            pixels.append(UInt8(x * 50 + 10))
            pixels.append(UInt8(y * 60 + 20))
            pixels.append(UInt8((x + y) * 20 + 30))
            pixels.append(255)
        }
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
                  rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
          ) else {
        throw NSError(
            domain: "KoharuVerticalQuadWarpHarness",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "cannot create fixture image"]
        )
    }
    return image
}

private func rgbaBytes(_ image: CGImage) -> [UInt8]? {
    let bytesPerRow = image.width * 4
    var bytes = [UInt8](repeating: 0, count: bytesPerRow * image.height)
    let rendered = bytes.withUnsafeMutableBytes { storage -> Bool in
        guard let context = CGContext(
            data: storage.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        ) else {
            return false
        }
        context.interpolationQuality = .none
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        return true
    }
    return rendered ? bytes : nil
}

private func fnv1a(_ bytes: [UInt8]) -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in bytes {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return hash
}

private func rgba(_ bytes: [UInt8], x: Int, y: Int, width: Int) -> String {
    let offset = (y * width + x) * 4
    return "\(bytes[offset]),\(bytes[offset + 1]),\(bytes[offset + 2]),\(bytes[offset + 3])"
}

@main
enum KoharuVerticalQuadWarpHarness {
    static func main() throws {
        let image = try fixtureImage()
        let quad = ImageOCRLayoutQuad(points: [
            ImageOCRLayoutPoint(x: 0.125 / 4, y: 0.25 / 4),
            ImageOCRLayoutPoint(x: 3.25 / 4, y: 0.0 / 4),
            ImageOCRLayoutPoint(x: 3.5 / 4, y: 3.5 / 4),
            ImageOCRLayoutPoint(x: 0.0 / 4, y: 3.25 / 4),
        ])
        guard let warped = MangaOCRService.diagnosticKoharuVerticalQuadWarp(
            image,
            quad: quad,
            targetWidth: 5,
            targetHeight: 7
        ),
        let bytes = rgbaBytes(warped) else {
            throw NSError(
                domain: "KoharuVerticalQuadWarpHarness",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "vertical quad warp failed"]
            )
        }
        print("warp=projective+bilinear")
        print("source=4x4 rgba target=5x7")
        print("size=\(warped.width)x\(warped.height)")
        print("checksum=\(String(fnv1a(bytes), radix: 16))")
        print(
            "pixels=\(rgba(bytes, x: 0, y: 0, width: warped.width));"
                + "\(rgba(bytes, x: 4, y: 0, width: warped.width));"
                + "\(rgba(bytes, x: 0, y: 6, width: warped.width));"
                + "\(rgba(bytes, x: 4, y: 6, width: warped.width));"
        )
        print("center=\(rgba(bytes, x: 2, y: 3, width: warped.width))")
    }
}
