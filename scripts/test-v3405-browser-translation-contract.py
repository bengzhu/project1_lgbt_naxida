#!/usr/bin/env python3
"""Static contract for the browser OCR/translation identity and safety boundary."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BrowserTranslationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model = (ROOT / "AITRANS/Models/BrowserModel.swift").read_text(encoding="utf-8")
        cls.store = (ROOT / "AITRANS/Services/TranslationSessionStore.swift").read_text(encoding="utf-8")
        cls.view = (ROOT / "AITRANS/Views/MangaBrowserView.swift").read_text(encoding="utf-8")
        cls.settings = (ROOT / "AITRANS/Views/SettingsView.swift").read_text(encoding="utf-8")

    def test_page_identity_and_capture_space_are_explicit(self):
        for needle in (
            "struct BrowserPageSnapshotIdentity",
            "documentID: UUID",
            "navigationGeneration: Int",
            "contentGeneration: Int",
            "layoutGeneration: Int",
            "scrollGeneration: Int",
            "isStable: Bool",
            "func captureVisibleContent(selection:",
            "captureExclusionInsets",
            "visibleDocumentRectCSS",
            "capturePixelSize",
            "boundedJPEGData",
            "maximumDimension: CGFloat = 4_096",
            "maximumPixels: CGFloat = 6_000_000",
            "captureID: UUID",
            "pageMutationObserverSource",
            "isScrollInteractionActive",
            "JavaScript and restoration can scroll without UIScrollView's drag",
            "Task.sleep(for: .milliseconds(240))",
            "Commit a fresh document UUID only after the",
            "components.port = nil",
            "components.path = \"/\"",
            "boundedThumbnail",
            "maximumDimension: CGFloat = 480",
        ):
            self.assertIn(needle, self.model)

    def test_store_rechecks_task_page_and_configuration_before_commit(self):
        for needle in (
            "func updateBrowserPageIdentity",
            "func translateBrowserCapture",
            "browserTranslationTaskID",
            "browserConfigurationRevision",
            "isCurrentBrowserTranslationTask",
            "browserTranslationRenderRevision",
            "browserTranslationOverlay = nil",
            "captureBuffer.data = nil",
            "appendBrowserDiagnostic",
            "browserModelRevision",
            "browserOCRCache",
            "browserTranslationCache",
            "request.mode = .translate",
            "request.transcriptContext = []",
            ".normalized()",
            "while browserOCRCache.count > 8",
            "while browserTranslationCache.count > 2_000",
            "16 * 1024 * 1024",
            "region-limit=256",
        ):
            self.assertIn(needle, self.store)

    def test_ui_has_one_tap_selection_overlay_and_retry(self):
        for needle in (
            "一键翻译本页",
            "Label(\"框选翻译\", systemImage: \"crop\")",
            "isSelectingRegion",
            "DragGesture(minimumDistance: 3",
            "captureAndTranslate(selection: nil)",
            ".task(id: automaticTranslationIdentity)",
            "translationMode == .automatic",
            "store.cancelBrowserTranslation()",
            "Button(\"重试\") { captureAndTranslate(selection: nil) }",
            "displayMode == .translated",
            "overlay.identity == model.pageIdentity",
        ):
            self.assertIn(needle, self.view)

    def test_security_switches_and_browser_cache_are_isolated(self):
        for key in (
            "aitrans.browser.blockAds",
            "aitrans.browser.blockPopups",
            "aitrans.browser.blockRedirects",
            "aitrans.browser.elementRemoval",
            "aitrans.browser.antiHijacking",
        ):
            self.assertIn(key, self.settings)
            self.assertIn(key, self.view)
        for needle in (
            # Legacy BrowserSecurityScript remains in BrowserModel for
            # historical contracts, while production BrowserWebView now
            # delegates live rule-list installation to AdBlockStore.
            "static let contentRuleListJSON",
            "BrowserSecurityScript.pageMutationObserverSource",
            "aitransElementRule",
            "aitransPageMutation",
            "rememberElementSelector",
            "window.open = (...args)",
            "__aitransApplySecurity",
            "navigator.clipboard",
            "navigator.userActivation.isActive",
            "coversViewport && elevated && visuallyEmpty",
            "JSONSerialization.data(withJSONObject: selectorValues)",
            "location.hostname.toLowerCase()",
            "localStorage.setItem(localRuleKey, JSON.stringify(siteSelectors))",
            'let scopedRule = "\\(host)\\n\\(clean)"',
            "handleMemoryWarning",
            "handleBrowserMemoryWarning",
            "handleApplicationDidEnterBackground",
            "didReceiveMemoryWarningNotification",
            "navigationAction.navigationType != .linkActivated",
            "isExternalNavigation(url)",
            "blockRedirects",
            "scrollViewWillBeginZooming",
        ):
            self.assertIn(needle, self.model + self.view + self.store)

    def test_diagnostics_do_not_enter_product_persistence(self):
        browser_region = self.store.split("// MARK: - Browser translation", 1)[1].split(
            "// MARK: - OCR detection workspace", 1
        )[0]
        self.assertIn("BrowserPerformanceSample", self.model + self.store)
        self.assertIn("sampleBrowserPerformance", browser_region)
        self.assertNotIn("appendImageTranslationTranscript", browser_region)
        self.assertNotIn("persist()", browser_region)


if __name__ == "__main__":
    unittest.main()
