#!/usr/bin/env python3
"""Focused static contract for the manga browser shell and tab lifecycle."""

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
        self.assertIn("case .manga:\n            MangaBrowserView(selectedTab: $selectedTab)", self.content)
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
            "var currentURL: URL?",
            "var loadingProgress: Double",
            "var canGoBack: Bool",
            "var canGoForward: Bool",
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

    def test_webview_uses_safe_top_inset_and_safari_light_page_surface(self) -> None:
        for needle in (
            ".ignoresSafeArea(.container, edges: .all)",
            "topSafeAreaInset: proxy.safeAreaInsets.top",
            "webView.scrollView.contentInset.top = topInset",
            "webView.backgroundColor = .white",
            "webView.underPageBackgroundColor = .white",
            "webView.scrollView.backgroundColor = .white",
            "webView.overrideUserInterfaceStyle = .light",
            ".preferredColorScheme(.light)",
        ):
            self.assertIn(needle, self.view)

    def test_safari_capsules_compact_to_host_only_and_hide_root_tab_bar(self) -> None:
        for needle in (
            "case expanded",
            "case compact",
            "chromeMode = isScrollingDown ? .compact : .expanded",
            "private let compactToolbarHeight: CGFloat = 36",
            "expandedBrowserControls",
            "compactAddressCapsule",
            "model.displayHost",
            'Image(systemName: "square.on.square")',
            '.toolbar(.hidden, for: .tabBar)',
            'accessibilityLabel("退出漫画浏览器")',
        ):
            source = self.model if needle in self.model else self.view
            self.assertIn(needle, source)

    def test_tabs_keep_value_snapshots_while_only_active_tab_owns_webview(self) -> None:
        for needle in (
            "struct BrowserTab: Identifiable",
            "private(set) var tabs: [BrowserTab]",
            "private(set) var activeTabID: UUID",
            "var scrollOffsetY: CGFloat",
            "var thumbnail: UIImage?",
            "@ObservationIgnored private weak var webView: WKWebView?",
            "func activateTab(_ tabID: UUID)",
            "func newTab()",
            "func closeTab(_ tabID: UUID)",
            "takeSnapshot(of: webView",
            "captureSessionState(from: webView",
        ):
            self.assertIn(needle, self.model)
        self.assertNotIn("var webView: WKWebView", self.model.split("struct BrowserTab", 1)[1].split("private(set) var tabs", 1)[0])
        self.assertIn(".id(model.activeTabID)", self.view)

    def test_tab_switcher_is_two_column_grid_with_new_switch_and_close_actions(self) -> None:
        for needle in (
            "isTabSwitcherPresented",
            "LazyVGrid(columns: columns",
            "GridItem(.flexible(), spacing: 14)",
            'Label("新建标签", systemImage: "plus")',
            "model.activateTab(tab.id)",
            "model.closeTab(tab.id)",
            "model.newTab()",
        ):
            self.assertIn(needle, self.view)

    def test_floating_chrome_and_translation_placeholder_match_scope(self) -> None:
        for needle in (
            ".ultraThinMaterial",
            "private let translationBallSize: CGFloat = 48",
            "lineWidth: 2",
            "model.phase == .loaded && model.showsExpandedChrome",
            'captureAndTranslate(selection: nil)',
            'Label("框选翻译", systemImage: "crop")',
            'ProgressView(value: store.browserTranslationStatus.fractionCompleted)',
            'Text("\\(browserSourceLanguage.shortName)  →  \\(browserTargetLanguage.shortName)")',
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

    def test_browser_translation_is_store_owned_and_not_persisted_to_image_history(self) -> None:
        self.assertIn("TranslationSessionStore", self.view)
        self.assertNotIn("TranslationSessionStore", self.model)
        self.assertIn("translateBrowserCapture", read("AITRANS/Services/TranslationSessionStore.swift"))
        self.assertIn("browserTranslationOverlay", read("AITRANS/Services/TranslationSessionStore.swift"))
        self.assertNotIn("appendImageTranslationTranscript", read("AITRANS/Services/TranslationSessionStore.swift").split("// MARK: - Browser translation", 1)[1].split("// MARK: - OCR detection workspace", 1)[0])
        self.assertIn("AppStorage", self.view)

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
            'steps.ci_scope.outputs.validation_profile }}" = "fast"',
            'steps.ci_scope.outputs.reused_full_validation_state }}" = "success"',
            "contains(github.event.head_commit.message, '[browser-only]')",
            "contains(github.event.pull_request.title, '[browser-only]')",
            "browser_task_scoped=true",
        ):
            self.assertIn(needle, self.workflow)


if __name__ == "__main__":
    unittest.main()
