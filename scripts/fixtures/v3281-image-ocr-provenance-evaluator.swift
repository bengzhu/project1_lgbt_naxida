import Foundation

// TranscriptModels.swift references these probe-only payloads, but this
// standalone evaluator intentionally does not compile MangaOverlayProbeService.
struct MangaOverlayBubbleGeometryDiagnostics: Equatable, Codable, Sendable {}
struct MangaOverlaySliceOCRDiagnostics: Equatable, Codable, Sendable {}
struct MangaOverlayCropFallbackSelfTest: Equatable, Codable, Sendable {}

@main
struct ImageOCRProvenanceEvaluator {
    static func main() throws {
        let verticalProvenance = ImageOCRCandidateProvenance(
            engine: .bundledMangaOCR,
            role: .verticalLine,
            cropVariant: .lineQuad,
            geometrySource: .lineQuad,
            regionID: ImageOCRRegionID("detector-region-1"),
            lineID: ImageOCRLineID("line-1"),
            rawConfidence: 0.91,
            detectorConfidence: 0.84,
            rotationApplied: 270,
            verticalTextRegionOwner: 1
        )
        let provenanceData = try JSONEncoder().encode(verticalProvenance)
        let decodedProvenance = try JSONDecoder().decode(
            ImageOCRCandidateProvenance.self,
            from: provenanceData
        )
        precondition(decodedProvenance == verticalProvenance)

        let shadowCandidate = ImageOCRCandidate(
            candidateID: "candidate-1",
            text: "今度こそ",
            confidence: 0.91,
            rect: ImageOCRLayoutRect(x: 0.1, y: 0.1, width: 0.08, height: 0.22),
            provenance: verticalProvenance,
            selectionReason: .selectedByExistingFusion
        )
        let ledger = ImageOCRShadowLedger(
            candidates: [shadowCandidate],
            selectedCandidateIDs: [shadowCandidate.candidateID]
        )
        precondition(ledger.selectedCandidateIDs == ["candidate-1"])
        let decodedLedger = try JSONDecoder().decode(
            ImageOCRShadowLedger.self,
            from: try JSONEncoder().encode(ledger)
        )
        precondition(decodedLedger == ledger)

        let baseline = ImageOCRLayoutEngine.layout(
            makeObservations(withProvenance: false),
            allowsVerticalText: true,
            prefersMangaReadingOrder: true
        )
        let enriched = ImageOCRLayoutEngine.layout(
            makeObservations(withProvenance: true),
            allowsVerticalText: true,
            prefersMangaReadingOrder: true
        )
        precondition(project(baseline) == project(enriched), "provenance changed layout output")
        precondition(enriched.allSatisfy { $0.provenance != nil })
        precondition(enriched.filter { $0.verticalTextRegionOwner == 1 }.count == 1)
        precondition(enriched.filter { $0.verticalTextRegionOwner == 2 }.count == 1)

        let oldBlockFixture = """
        {
          "id": "00000000-0000-0000-0000-000000000281",
          "original": "旧字",
          "translation": "",
          "confidence": 0.75,
          "boundingBox": {
            "x": 0.1,
            "y": 0.2,
            "width": 0.1,
            "height": 0.2
          }
        }
        """
        let oldBlock = try JSONDecoder().decode(
            ImageTranslationBlock.self,
            from: Data(oldBlockFixture.utf8)
        )
        precondition(oldBlock.ocrProvenance == nil, "old Codable fixture did not decode as legacy")

        print("v3.281 image OCR provenance evaluator passed")
    }

    private static func makeObservations(
        withProvenance: Bool
    ) -> [ImageOCRLayoutObservation] {
        let rows: [(String, ImageOCRLayoutRect, Int?)] = [
            ("今度", ImageOCRLayoutRect(x: 0.10, y: 0.10, width: 0.08, height: 0.22), 1),
            ("こそ", ImageOCRLayoutRect(x: 0.10, y: 0.36, width: 0.08, height: 0.22), 1),
            ("持ち", ImageOCRLayoutRect(x: 0.55, y: 0.10, width: 0.08, height: 0.22), 2),
            ("帰る", ImageOCRLayoutRect(x: 0.55, y: 0.36, width: 0.08, height: 0.22), 2),
            ("caption", ImageOCRLayoutRect(x: 0.22, y: 0.78, width: 0.34, height: 0.08), nil)
        ]
        return rows.enumerated().map { index, row in
            let provenance: ImageOCRCandidateProvenance?
            if withProvenance {
                let owner = row.2
                provenance = ImageOCRCandidateProvenance(
                    engine: owner == nil ? .vision : .bundledMangaOCR,
                    role: owner == nil ? .page : .verticalLine,
                    cropVariant: owner == nil ? .page : .lineQuad,
                    geometrySource: owner == nil ? .none : .lineQuad,
                    regionID: owner.map { ImageOCRRegionID("detector-region-\($0)") },
                    lineID: owner.map { ImageOCRLineID("line-\($0)-\(index)") },
                    rawConfidence: 0.8 + Float(index) * 0.01,
                    detectorConfidence: owner.map { _ in 0.87 },
                    rotationApplied: owner == nil ? 0 : 270,
                    verticalTextRegionOwner: owner
                )
            } else {
                provenance = nil
            }
            return ImageOCRLayoutObservation(
                text: row.0,
                confidence: 0.8 + Float(index) * 0.01,
                rect: row.1,
                sourceDirectionHint: row.2 == nil ? nil : .vertical,
                verticalTextRegionOwner: row.2,
                provenance: provenance
            )
        }
    }

    private static func project(_ blocks: [ImageOCRLayoutBlock]) -> [String] {
        blocks.map { block in
            [
                block.text,
                String(block.confidence),
                String(block.rect.x),
                String(block.rect.y),
                String(block.rect.width),
                String(block.rect.height),
                block.direction.rawValue,
                String(block.directionConfidence),
                block.directionReason,
                String(describing: block.verticalTextRegionOwner)
            ].joined(separator: "|")
        }
    }
}
