#!/usr/bin/env python3
"""Static contract for v3.390's OCR detection workspace and v3388 overlay receipt."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


class ImageOCRDetectionUIContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.view = read("AITRANS/Views/ImageOCRDetectionView.swift")
        cls.content = read("AITRANS/Views/ContentView.swift")
        cls.preview = read("AITRANS/Views/AppPreviewSupport.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.models = read("AITRANS/Models/TranscriptModels.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.plist = read("AITRANS/Resources/Info.plist")
        cls.capture = read("scripts/capture-bundled-image-translation-ui.sh")
        cls.workflow = read(".github/workflows/ci-results.yml")

    def test_page_is_a_separate_ocr_only_app_route(self) -> None:
        for marker in (
            "case ocr",
            "case .ocr: \"OCR 检测\"",
            "case .ocr: \"text.viewfinder\"",
            "case .ocr:",
            "ImageOCRDetectionView()",
            "imageOCRDetectionState",
            "recognizeTextBlocksWithShadowLedger",
            "never enters the image translation pipeline",
        ):
            self.assertIn(marker, self.content + self.store)

    def test_input_language_layout_and_japanese_orientation_contract(self) -> None:
        for marker in (
            "上传图片",
            "拍照",
            "粘贴图片",
            "PhotosPicker",
            "UIImagePickerController",
            "UIPasteboard.general.image",
            'case automatic = "自动（推荐）"',
            'case japanese = "日语"',
            'case chinese = "中文"',
            'case english = "英语"',
            'case horizontal = "横排"',
            'case vertical = "竖排"',
            'case mangaVertical = "漫画竖排"',
            "imageOCRDetectionDirectionRereadEnabled",
            "日语竖排会自动启用 90°/270° 方向复读",
        ):
            self.assertIn(marker, self.view + self.store + self.models)
        self.assertIn("layoutPreference: ImageOCRDetectionLayout = .automatic", self.vision)
        self.assertIn("layoutPreference: layout", self.store)
        self.assertIn(
            "case .automatic:\n                allowsVerticalText = sourceLanguage == nil",
            self.vision,
        )

    def test_overlay_review_actions_and_exports_are_present(self) -> None:
        for marker in (
            "原图与识别框",
            "boundingBox.normalizedToUnit()",
            "selectedBlockID",
            "ImageOCRDetectionBox",
            "低置信度",
            "单块重新识别",
            "手动编辑",
            "copyImageOCRDetectionAll",
            "导出 TXT",
            "导出 JSON",
            "OCRTextFileDocument",
            "OCRJSONFileDocument",
            "cancelImageOCRDetection",
            "retryImageOCRDetection",
            "按当前选项重新识别",
            "准备图片",
            "检测文字区域",
            "OCR 识别",
            "整理阅读顺序",
        ):
            self.assertIn(marker, self.view + self.store + self.models)

    def test_diagnostics_keep_stage_rates_raw_scores_and_quality_state(self) -> None:
        for marker in (
            "totalMilliseconds",
            "preprocessingMilliseconds",
            "detectionMilliseconds",
            "ocrMilliseconds",
            "layoutMilliseconds",
            "blocksPerSecond",
            "charactersPerSecond",
            "averageMillisecondsPerBlock",
            "modelRawConfidence",
            "qualityStatus",
            "confidenceDistribution",
            "Vision 与 Manga OCR 不做横向校准比较",
        ):
            self.assertIn(marker, self.view + self.store + self.models + self.vision)

    def test_ci_receipt_keeps_the_requested_v3388_overlay_name(self) -> None:
        for marker in (
            "test2-ocr-full-overlay-v3388.png",
            'cp "$ocr_screenshot_path" "$full_overlay_screenshot_path"',
            '"fullOCROverlay"',
            "scripts/test-v3390-image-ocr-detection-ui-contract.py",
            "test-v3390-image-ocr-detection-ui-contract.py",
        ):
            self.assertIn(marker, self.capture + self.workflow)

    def test_project_permissions_preview_and_version_are_routed(self) -> None:
        for marker in (
            "ImageOCRDetectionView.swift in Sources",
            "path = ImageOCRDetectionView.swift;",
            "NSCameraUsageDescription",
            "case ocrEmpty",
            "case ocrSuccess",
        ):
            self.assertIn(marker, self.project + self.plist + self.preview)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project),
            ["3.390", "3.390"],
        )

    def test_static_contract_has_no_process_entry(self) -> None:
        process_word = "sub" + "process"
        popen_word = "Po" + "pen"
        system_word = "os." + "system"
        contract = read("scripts/test-v3390-image-ocr-detection-ui-contract.py")
        for source in (contract, self.view):
            self.assertNotIn(process_word, source)
            self.assertNotIn(popen_word, source)
            self.assertNotIn(system_word, source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
