#!/usr/bin/env python3
"""Static contract for WebView-local to SwiftUI-root overlay coordinates."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class BrowserOverlayCoordinateContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.browser = read("AITRANS/Views/MangaBrowserView.swift")
        cls.model = read("AITRANS/Models/BrowserModel.swift")

    def test_named_root_space_tracks_actual_webview_frame(self):
        for needle in (
            'coordinateSpace(name: "browserRoot")',
            "BrowserWebViewFramePreferenceKey",
            "frame(in: .named(\"browserRoot\"))",
            "@State private var webViewFrameInRoot: CGRect = .zero",
            "onPreferenceChange(BrowserWebViewFramePreferenceKey.self)",
        ):
            self.assertIn(needle, self.browser)

    def test_overlay_maps_capture_rect_once_at_render_boundary(self):
        for needle in (
            "let captureRectInRoot = webViewRectInRoot(snapshot.captureRectInView)",
            "captureRect: captureRectInRoot",
            "private func webViewRectInRoot(_ rect: CGRect)",
            "rect.offsetBy(dx: webViewFrameInRoot.minX, dy: webViewFrameInRoot.minY)",
        ):
            self.assertIn(needle, self.browser)
        self.assertNotIn("captureRect: snapshot.captureRectInView", self.browser)

    def test_selection_reverse_maps_before_capture(self):
        for needle in (
            "BrowserCaptureSelection(rectInView: rootRectToWebView($0))",
            "private func rootRectToWebView(_ rect: CGRect)",
            "rect.offsetBy(dx: -webViewFrameInRoot.minX, dy: -webViewFrameInRoot.minY)",
        ):
            self.assertIn(needle, self.browser)

    def test_model_contract_documents_local_coordinates(self):
        for needle in (
            "WKWebView bounds-local point space",
            "reverse-maps its SwiftUI root selection",
            "without the frame-origin transform owned by MangaBrowserView",
            "visibleDocumentRectCSS",
        ):
            self.assertIn(needle, self.model)

    def test_mapping_is_translation_only_and_does_not_touch_ocr_geometry(self):
        mapping = self.browser.split("private func webViewRectInRoot", 1)[1].split("private func beginRegionSelection", 1)[0]
        self.assertIn("offsetBy", mapping)
        self.assertNotIn("boundingBox", mapping)
        self.assertNotIn("scale", mapping)


if __name__ == "__main__":
    unittest.main()
