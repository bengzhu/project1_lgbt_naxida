#!/usr/bin/env python3
"""Static contract for AdBlockStore-driven WKWebView runtime integration."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class AdBlockRuntimeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.store = read("AITRANS/Services/AdBlockStore.swift")
        cls.models = read("AITRANS/Models/AdBlockModels.swift")
        cls.script = read("AITRANS/Services/AdBlockWebScript.swift")
        cls.browser = read("AITRANS/Views/MangaBrowserView.swift")
        cls.settings = read("AITRANS/Views/SettingsView.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def test_store_owns_webview_attachment_and_runtime_lists(self):
        for needle in (
            "case prepareWebViewConfiguration(",
            "case attachWebView(WKWebView, attachmentID: UUID)",
            "case detachWebView(WKWebView, attachmentID: UUID)",
            "case recordBlockedNavigation(URL)",
            "private weak var attachedWebView: WKWebView?",
            "private var attachmentID: UUID?",
            "installedNetworkRuleList",
            "installedCosmeticRuleList",
            "applyProtection(to: attachedWebView, reloadIfRuleListsChange: true)",
            "controller.add(network)",
            "controller.add(cosmetic)",
            "controller.remove(installedNetworkRuleList)",
            "webView.reload()",
        ):
            self.assertIn(needle, self.store)

    def test_named_content_world_and_limited_js_fallback(self):
        for needle in (
            'contentWorldName = "AITRANS.AdBlock"',
            "WKUserScript",
            "in: contentWorld",
            "configurationJSON",
            "normalizeMedia",
            "mediaTypesRequiringUserActionForPlayback",
            "webkitbeginfullscreen",
            "fullscreenchange",
            "contextmenu",
            "selectstart",
            "copy",
            "MutationObserver",
            "blockerSelector",
            "blockerText",
            "globalThis.__aitransAdBlockRuntime",
            "aitransAdBlockElementRule",
        ):
            self.assertIn(needle, self.script + self.browser + self.store)
        self.assertNotIn("eval(", self.script)
        self.assertNotIn("document.cookie", self.script)
        self.assertNotIn("XMLHttpRequest", self.script)
        self.assertNotIn("fetch(", self.script)

    def test_view_sends_store_intents_and_no_live_adblock_appstorage(self):
        for needle in (
            "@Environment(AdBlockStore.self)",
            ".prepareWebViewConfiguration(",
            ".attachWebView(webView, attachmentID:",
            ".detachWebView(webView, attachmentID:",
            ".setEnabled($0)",
            ".setNetworkFiltering($0)",
            ".setScriptProtection($0)",
            ".setCosmeticFiltering($0)",
            ".setPopupBlocking($0)",
            ".setRedirectBlocking($0)",
            ".setElementPicker($0)",
        ):
            self.assertIn(needle, self.browser + self.settings)
        for key in (
            '@AppStorage("aitrans.browser.blockAds")',
            '@AppStorage("aitrans.browser.blockPopups")',
            '@AppStorage("aitrans.browser.blockRedirects")',
            '@AppStorage("aitrans.browser.elementRemoval")',
            '@AppStorage("aitrans.browser.antiHijacking")',
        ):
            self.assertNotIn(key, self.browser + self.settings)

    def test_runtime_path_does_not_use_legacy_broad_security_injection(self):
        browser_runtime = self.browser.split("private struct BrowserWebView", 1)[1]
        self.assertNotIn("BrowserSecurityScript.make", browser_runtime)
        self.assertNotIn("contentRuleListJSON", browser_runtime)
        self.assertIn("BrowserSecurityScript.pageMutationObserverSource", browser_runtime)
        self.assertIn("AdBlockWebScript.elementRuleMessageName", browser_runtime)
        self.assertIn("effectiveCosmeticFiltering", self.store + self.models)
        self.assertIn("effectiveScriptProtection", self.store + self.models)

    def test_project_includes_runtime_script(self):
        self.assertIn("AdBlockWebScript.swift in Sources", self.project)
        self.assertIn("AdBlockWebScript.swift */", self.project)
        self.assertIn("AdBlockStore.swift in Sources", self.project)


if __name__ == "__main__":
    unittest.main()
