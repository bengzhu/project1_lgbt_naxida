#!/usr/bin/env python3
"""Focused static contract for the v3.404 manga browser shell."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class MangaBrowserUIContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.content = read("AITRANS/Views/ContentView.swift")
        cls.theme = read("AITRANS/Views/AppTheme.swift")
        cls.model = read("AITRANS/Models/BrowserModel.swift")
        cls.view = read("AITRANS/Views/MangaBrowserView.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")

    def test_manga_workspace_is_routed_from_app_navigation(self) -> None:
        self.assertIn("case manga", self.content)
        self.assertIn('case .manga: "漫画"', self.content)
        self.assertIn(".text, .image, .manga", self.content)
        self.assertIn("case .manga:\n            MangaBrowserView()", self.content)
        self.assertIn("case manga", self.theme)

    def test_browser_model_owns_required_page_state_and_intents(self) -> None:
        for needle in (
            "@Observable",
            "final class BrowserModel",
            "case start",
            "case loading",
            "case loaded",
            "case failed(String)",
            "case webContentProcessTerminated",
            "private(set) var currentURL",
            "private(set) var loadingProgress",
            "private(set) var canGoBack",
            "private(set) var canGoForward",
            "func load(address rawAddress: String)",
            "func goBack()",
            "func goForward()",
            "func reload()",
            "func retry()",
        ):
            self.assertIn(needle, self.model)

    def test_url_security_external_navigation_and_download_failures_are_explicit(self) -> None:
        for needle in (
            'return "https://\\(address)"',
            'scheme == "http" || scheme == "https"',
            "NSURLErrorAppTransportSecurityRequiresSecureConnection",
            "系统保持默认网络安全策略",
            "handleExternalNavigationIfNeeded",
            'showNotice("暂不支持此链接")',
            'showNotice("暂不支持下载此内容")',
            'disposition.contains("attachment")',
        ):
            source = self.model if needle not in self.view else self.view
            self.assertIn(needle, source)

    def test_webview_delegate_covers_navigation_process_and_new_windows(self) -> None:
        for needle in (
            "UIViewRepresentable",
            "WKWebView(frame: .zero, configuration: configuration)",
            "webView.navigationDelegate = context.coordinator",
            "webView.uiDelegate = context.coordinator",
            "webView.scrollView.delegate = context.coordinator",
            "webViewWebContentProcessDidTerminate",
            "decidePolicyFor navigationAction",
            "decidePolicyFor navigationResponse",
            "@escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void",
            "@escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void",
            "navigationAction.targetFrame == nil",
            "scrollViewDidScroll",
        ):
            self.assertIn(needle, self.view)

    def test_floating_chrome_and_translation_placeholder_match_scope(self) -> None:
        for needle in (
            ".ultraThinMaterial",
            "private let toolbarHeight: CGFloat = 80",
            "private let translationBallSize: CGFloat = 48",
            "lineWidth: 2",
            "model.phase == .loaded && model.isChromeVisible",
            'Button("翻译本页") {}',
            'Text("暂无任务")',
            'Text("日  →  中")',
            'case manual = "手动"',
            'case automatic = "自动"',
            'case original = "原文"',
            'case translated = "译文"',
            "Animation.spring(response: 0.3, dampingFraction: 0.8)",
        ):
            self.assertIn(needle, self.view)

    def test_address_input_and_failure_overlays_are_accessible(self) -> None:
        for needle in (
            '.keyboardType(.URL)',
            '.textInputAutocapitalization(.never)',
            '.autocorrectionDisabled()',
            '.submitLabel(.go)',
            'title: "无法打开页面"',
            'actionTitle: "重试"',
            'title: "网页需要恢复"',
            'actionTitle: "重新载入"',
            '.accessibilityLabel("地址栏")',
            '.accessibilityLabel("翻译菜单")',
        ):
            self.assertIn(needle, self.view)

    def test_new_sources_are_members_of_the_app_target(self) -> None:
        for filename in ("BrowserModel.swift", "MangaBrowserView.swift"):
            self.assertIn(f"{filename} in Sources", self.project)
            self.assertIn(f"/* {filename} */", self.project)

    def test_browser_does_not_enter_translation_ocr_or_persistence(self) -> None:
        combined = self.model + self.view
        for forbidden in (
            "TranslationSessionStore",
            "GemmaLocalService",
            "VisionOCRService",
            "MangaOCRService",
            "state.json",
            "AppStorage",
        ):
            self.assertNotIn(forbidden, combined)

    def test_ci_routes_browser_scope_without_unrelated_suites(self) -> None:
        for needle in (
            "browser_task_scoped=false",
            "browser_contract_required=false",
            'if [ "$browser_task_scoped" = "true" ]; then',
            "python3 -B scripts/test-v3404-manga-browser-ui-contract.py",
            "speech_contract_required=false",
            "ui_interaction_contract_required=false",
            "home_ui_contract_required=false",
            "paste_matrix_contract_required=false",
            "koharu_contract_required=false",
            "[browser-only]",
        ):
            self.assertIn(needle, self.workflow)


if __name__ == "__main__":
    unittest.main()
