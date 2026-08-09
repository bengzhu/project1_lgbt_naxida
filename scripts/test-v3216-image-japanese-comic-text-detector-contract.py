#!/usr/bin/env python3
"""Contract for the bundled Koharu comic TextRegion detector path."""

from hashlib import sha256
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def digest(relative_path: str) -> str:
    return sha256((ROOT / relative_path).read_bytes()).hexdigest()


def braced_body(source: str, marker: str) -> str:
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace : index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class JapaneseComicTextDetectorContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.detector = read(
            "AITRANS/Services/ComicTextBubbleDetectorService.swift"
        )
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.converter = read(
            "scripts/convert-comic-text-bubble-detector-coreml.py"
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.runtime = read(
            "scripts/test-v3214-image-japanese-manga-ocr-runtime.sh"
        )

    def test_exact_int8_detector_artifact_is_bundled(self) -> None:
        weight = (
            "AITRANS/Resources/ComicTextDetector/"
            "ComicTextBubbleDetectorINT8.mlpackage/"
            "Data/com.apple.CoreML/weights/weight.bin"
        )
        artifact = ROOT / weight
        self.assertTrue(artifact.is_file())
        self.assertEqual(artifact.stat().st_size, 43_185_600)
        self.assertEqual(
            digest(weight),
            "952e9a455664a37fe0c197695a5f799ace748866bad3b3591408f0eaa88b8e48",
        )

    def test_license_notice_and_pinned_provenance_are_present(self) -> None:
        notice = read(
            "AITRANS/Resources/ComicTextDetector/ComicTextDetector-NOTICE.md"
        )
        license_text = read(
            "AITRANS/Resources/ComicTextDetector/"
            "ComicTextDetector-LICENSE-APACHE"
        )
        metadata = read(
            "AITRANS/Resources/ComicTextDetector/conversion.json"
        )
        for marker in [
            "ogkalu/comic-text-and-bubble-detector",
            "16e8a622f91fabc6b5b65c96d32d1183f8843546",
            "RT-DETR-v2 R50",
            "text_bubble",
            "text_free",
        ]:
            self.assertIn(marker, notice + metadata)
        self.assertIn("Apache License", license_text)
        self.assertIn("Version 2.0", license_text)

    def test_runtime_is_cached_cpu_only_and_matches_model_contract(self) -> None:
        for marker in [
            "actor ComicTextBubbleDetectorService",
            "static let shared = ComicTextBubbleDetectorService()",
            "private var runtime: ComicTextBubbleDetectorRuntime?",
            "configuration.computeUnits = .cpuOnly",
            "private static let imageSize = 640",
            "private static let queryCount = 300",
            "private static let labelCount = 3",
            "private static let confidenceThreshold: Float = 0.30",
            "private static let textLabelIDs = Set([1, 2])",
            'featureValue(for: "logits")',
            'featureValue(for: "pred_boxes")',
            "Task.checkCancellation()",
        ]:
            self.assertIn(marker, self.detector)

    def test_koharu_topk_filter_and_text_region_merge_are_preserved(self) -> None:
        detect = self.detector
        for marker in [
            "scored.prefix(Self.queryCount)",
            "prediction.score >= Self.confidenceThreshold",
            "Self.textLabelIDs.contains(prediction.labelID)",
            "rect.width > minimumWidth",
            "rect.height > minimumHeight",
            "Self.mergeTextRegions(detections)",
        ]:
            self.assertIn(marker, detect)
        merge = braced_body(self.detector, "private static func mergeTextRegions(")
        for marker in [
            "intersectionOverUnion(candidate.rect, other.rect) >= 0.50",
            "threshold: 0.30",
            "candidate.rect.union(other.rect)",
            "max(candidate.confidence, other.confidence)",
        ]:
            self.assertIn(marker, merge)

    def test_dedicated_regions_are_primary_and_vision_remains_fallback(self) -> None:
        manga = braced_body(
            self.vision,
            "private static func recognizeJapaneseMangaOCR(",
        )
        combine = braced_body(
            self.vision,
            "private static func japaneseMangaOCRRegions(",
        )
        self.assertLess(
            manga.index("ComicTextBubbleDetectorService.shared.detectTextRegions("),
            manga.index("detectJapanesePixelFirstVerticalRegions("),
        )
        for marker in [
            ")) ?? []",
            "detectorRegions: detectorRegions",
            "visionRegions: visionRegions",
            "regions.prefix(12)",
        ]:
            self.assertIn(marker, manga)
        for marker in [
            "detector: .comicTextBubble",
            "let supplemental = visionRegions.filter",
            "overlapRatio($0.rect, candidate.rect) >= 0.60",
            "intersectionOverUnion($0.rect, candidate.rect) >= 0.50",
            "primary + supplemental",
        ]:
            self.assertIn(marker, combine)

    def test_conversion_is_pinned_functional_and_int8(self) -> None:
        for marker in [
            'MODEL_ID = "ogkalu/comic-text-and-bubble-detector"',
            'MODEL_REVISION = "16e8a622f91fabc6b5b65c96d32d1183f8843546"',
            "def functional_generate_anchors(",
            "(grid_x + 0.5) / width",
            "(grid_y + 0.5) / height",
            "RTDetrV2Model.generate_anchors = functional_generate_anchors",
            "ct.ImageType(",
            "scale=1 / 255",
            "compute_precision=ct.precision.FLOAT16",
            'dtype="int8"',
        ]:
            self.assertIn(marker, self.converter)
        self.assertNotIn("grid_xy[..., 0] /= width", self.converter)

    def test_real_runtime_requires_complete_detector_grouped_text(self) -> None:
        for marker in [
            "ComicTextBubbleDetectorINT8.mlpackage",
            "ComicTextBubbleDetectorService.swift",
            "int(match.group(1)) != 5",
            '"前は生意気に俺の誘い断りやがって..."',
            '"今度こそこの爆乳を持ち帰る！"',
            '"そのせいでつまんねー女に絡まれるし..."',
            '"監督より挨拶をお願いします"',
        ]:
            self.assertIn(marker, self.runtime)

    def test_project_version_and_ci_route_follow_v3215(self) -> None:
        for marker in [
            "ComicTextBubbleDetectorService.swift in Sources",
            "ComicTextBubbleDetectorINT8.mlpackage in Resources",
            "ComicTextDetector-LICENSE-APACHE in Resources",
            "ComicTextDetector-NOTICE.md in Resources",
        ]:
            self.assertIn(marker, self.project)
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(versions, ["3.216", "3.216"])
        previous = (
            "python3 -B "
            "scripts/test-v3215-image-japanese-manga-column-ownership-contract.py"
        )
        current = (
            "python3 -B "
            "scripts/test-v3216-image-japanese-comic-text-detector-contract.py"
        )
        runtime = "bash scripts/test-v3214-image-japanese-manga-ocr-runtime.sh"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertIn(runtime, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertLess(self.workflow.index(current), self.workflow.index(runtime))
        self.assertIn(
            "if grep -Fx "
            "'scripts/test-v3216-image-japanese-comic-text-detector-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
