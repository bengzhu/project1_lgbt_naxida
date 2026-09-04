#!/usr/bin/env python3
"""Static contract for DEBUG-only metadata recording from the manga WKWebView."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class BrowserDebugLogContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.store = read("AITRANS/Services/BrowserDebugLogStore.swift")
        cls.view = read("AITRANS/Views/BrowserDebugLogView.swift")
        cls.browser = read("AITRANS/Views/MangaBrowserView.swift")
        cls.library = read("AITRANS/Views/ContentView.swift")
        cls.app = read("AITRANS/App/AITRANSApp.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")

    def test_bounded_state_machine_supports_record_stop_export_delete(self):
        for needle in (
            "enum Intent",
            "case start(tabID: UUID)",
            "case stop",
            "case clearAll",
            "case delete(UUID)",
            "private(set) var sessions",
            "private(set) var currentEntries",
            "private(set) var isRecording",
            "func exportData(for sessionID: UUID) -> Data?",
            "maximumEntries = 2_000",
            "maximumSessions = 20",
            "func send(_ intent: Intent)",
            "persist()",
        ):
            self.assertIn(needle, self.store)

    def test_metadata_only_script_covers_resource_dom_media_and_subframes(self):
        for needle in (
            "WKContentWorld.world(name: \"com.aitrans.browser.debug\")",
            'messageName = "aitransBrowserDebug"',
            "performance.getEntriesByType(\"resource\")",
            "MutationObserver",
            "resourceError",
            "domInsertion",
            "isTrackingPixel",
            "fullscreenchange",
            "postMessage(payload)",
            "forMainFrameOnly: false",
        ):
            self.assertIn(needle, self.store + self.browser)
        for forbidden in ("document.cookie", "innerHTML", "fetch(", "XMLHttpRequest", "response.body"):
            self.assertNotIn(forbidden, self.store)

    def test_browser_attachment_routes_navigation_and_subframe_messages(self):
        for needle in (
            "debugLogStore: BrowserDebugLogStore",
            "BrowserDebugLogStore.userScriptSource",
            "BrowserDebugLogStore.messageName",
            "recordScriptMessage(",
            "message.frameInfo.isMainFrame",
            "recordNavigation(",
            ".blockedNavigation",
            ".popup",
        ):
            self.assertIn(needle, self.browser)
        self.assertNotIn("guard message.frameInfo.isMainFrame else { return }\n            switch message.name", self.browser)

    def test_debug_ui_and_library_entry_are_isolated(self):
        for source in (self.view, self.library):
            self.assertIn("#if DEBUG", source)
        for needle in (
            "BrowserDebugLogView()",
            "browserDebugLogs",
            "开始 Debug 日志",
            "停止 Debug 日志",
            "ShareLink(",
            ".delete(session.id)",
        ):
            self.assertIn(needle, self.view + self.browser + self.library)
        self.assertIn(".environment(browserDebugLogStore)", self.app)

    def test_project_and_workflow_include_contract(self):
        for needle in (
            "BrowserDebugLogStore.swift in Sources",
            "BrowserDebugLogStore.swift */",
            "BrowserDebugLogView.swift in Sources",
            "BrowserDebugLogView.swift */",
            "test-v3409-browser-debug-log-contract.py",
        ):
            self.assertIn(needle, self.project + self.workflow)


if __name__ == "__main__":
    unittest.main()
