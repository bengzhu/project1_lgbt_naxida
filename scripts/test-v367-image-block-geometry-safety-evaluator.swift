import Foundation

// TranscriptModels references service-owned diagnostics. These lightweight stubs
// keep this model-only contract independent from UIKit/Vision probe services.
struct MangaOverlayBubbleGeometryDiagnostics: Equatable, Codable, Sendable {}
struct MangaOverlaySliceOCRDiagnostics: Equatable, Codable, Sendable {}
struct MangaOverlayCropFallbackSelfTest: Equatable, Codable, Sendable {}

private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> NormalizedImageRect {
    NormalizedImageRect(x: x, y: y, width: width, height: height)
}

private func requireRect(_ actual: NormalizedImageRect?, _ expected: NormalizedImageRect, _ message: String) {
    guard let actual else { fatalError(message) }
    let values = [actual.x, actual.y, actual.width, actual.height]
    let expectedValues = [expected.x, expected.y, expected.width, expected.height]
    guard zip(values, expectedValues).allSatisfy({ abs($0 - $1) < 0.000_001 }) else {
        fatalError(message)
    }
}

@main
private enum ImageBlockGeometrySafetyEvaluator {
    static func main() {
        let inBounds = rect(0.2, 0.3, 0.25, 0.12)
        requireRect(inBounds.normalizedToUnit(), inBounds, "in-bounds block geometry must remain unchanged")

        requireRect(
            rect(0.9, 0.8, 0.5, 0.5).normalizedToUnit(),
            rect(0.9, 0.8, 0.1, 0.2),
            "oversized block geometry must clip as a whole"
        )
        requireRect(
            rect(-0.2, -0.1, 0.3, 0.4).normalizedToUnit(),
            rect(0, 0, 0.1, 0.3),
            "partially visible block geometry must preserve visible area"
        )
        guard rect(0, 0, 0, 0.1).normalizedToUnit() == nil,
              rect(.nan, 0.1, 0.2, 0.2).normalizedToUnit() == nil,
              rect(0.1, 0.1, .infinity, 0.2).normalizedToUnit() == nil else {
            fatalError("invalid block geometry must be rejected")
        }

        print("v3.67 image block geometry safety evaluator passed")
    }
}
