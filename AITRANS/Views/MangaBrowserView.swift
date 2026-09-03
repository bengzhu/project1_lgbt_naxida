import SwiftUI
import WebKit

struct MangaBrowserView: View {
    private enum TranslationMode: String, CaseIterable, Hashable, Identifiable {
        case manual = "手动"
        case automatic = "自动"

        var id: Self { self }
    }

    private enum DisplayMode: String, CaseIterable, Hashable, Identifiable {
        case original = "原文"
        case translated = "译文"

        var id: Self { self }
    }

    private let panelAnimation = Animation.spring(response: 0.3, dampingFraction: 0.8)
    private let toolbarHeight: CGFloat = 80
    private let translationBallSize: CGFloat = 48
    private let translationMenuHeight: CGFloat = 284

    @State private var model = BrowserModel()
    @State private var addressDraft = ""
    @State private var isEditingAddress = false
    @State private var isTranslationMenuPresented = false
    @State private var translationMode = TranslationMode.manual
    @State private var displayMode = DisplayMode.original
    @State private var translationBallY: CGFloat?
    @State private var translationBallDragOriginY: CGFloat?
    @State private var translationBallDragX: CGFloat = 0
    @FocusState private var isAddressFieldFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BrowserWebView(model: model)
                    .ignoresSafeArea(.container, edges: .all)

                phaseOverlay

                if isTranslationMenuPresented && model.phase == .loaded && model.isChromeVisible {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { dismissTranslationMenu() }
                        .ignoresSafeArea()
                        .zIndex(3)

                    translationMenu(in: proxy)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                        .zIndex(4)
                }

                if model.phase == .loaded && model.isChromeVisible {
                    translationBall(in: proxy)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(5)
                }

                if model.phase != .start {
                    browserToolbar
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .offset(y: model.isChromeVisible ? 0 : toolbarHeight + 28)
                        .allowsHitTesting(model.isChromeVisible)
                        .zIndex(6)
                }

                if let notice = model.notice {
                    Text(notice)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, max(proxy.safeAreaInsets.top, 12) + 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(8)
                }
            }
            .animation(panelAnimation, value: model.isChromeVisible)
            .animation(panelAnimation, value: isTranslationMenuPresented)
            .animation(panelAnimation, value: model.noticeRevision)
        }
        .background(Color(uiColor: .systemBackground))
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: model.phase) { _, phase in
            guard phase == .loaded else {
                isTranslationMenuPresented = false
                return
            }
        }
        .onChange(of: model.isChromeVisible) { _, visible in
            if !visible {
                isTranslationMenuPresented = false
            }
        }
        .onChange(of: isAddressFieldFocused) { _, focused in
            if !focused && isEditingAddress {
                model.setChromeAutoHideSuspended(true)
            }
        }
        .task(id: model.noticeRevision) {
            let revision = model.noticeRevision
            guard revision > 0 else { return }
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            model.clearNotice(revision: revision)
        }
    }

    @ViewBuilder
    private var phaseOverlay: some View {
        switch model.phase {
        case .start:
            startPage
        case .loading, .loaded:
            EmptyView()
        case let .failed(reason):
            browserMessage(
                systemImage: "exclamationmark.triangle.fill",
                title: "无法打开页面",
                message: reason,
                actionTitle: "重试",
                action: model.retry
            )
        case .webContentProcessTerminated:
            browserMessage(
                systemImage: "arrow.clockwise.icloud.fill",
                title: "网页需要恢复",
                message: "网页内容进程已被系统终止，重新载入即可继续。",
                actionTitle: "重新载入",
                action: model.reload
            )
        }
    }

    private var startPage: some View {
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                addressEntryField(isStartPage: true)
                    .frame(maxWidth: 620)
                    .padding(.horizontal, 24)
                    .padding(.top, 120)
            }
    }

    private var browserToolbar: some View {
        VStack(spacing: 0) {
            if model.phase == .loading {
                ProgressView(value: model.loadingProgress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .padding(.horizontal, 12)
            }

            Group {
                if isEditingAddress {
                    addressEntryField(isStartPage: false)
                } else {
                    browserControls
                }
            }
            .frame(maxWidth: .infinity, minHeight: toolbarHeight)
        }
        .padding(.horizontal, 8)
        .background(
            .ultraThinMaterial,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 22,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 8,
                topTrailingRadius: 22,
                style: .continuous
            )
        )
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: -4)
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    private var browserControls: some View {
        HStack(spacing: 4) {
            chromeButton("chevron.backward", label: "后退", enabled: model.canGoBack, action: model.goBack)
            chromeButton("chevron.forward", label: "前进", enabled: model.canGoForward, action: model.goForward)
            chromeButton("arrow.clockwise", label: "刷新", action: model.reload)

            Button(action: beginAddressEditing) {
                HStack(spacing: 6) {
                    Image(systemName: model.currentURL?.scheme == "https" ? "lock.fill" : "globe")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(model.currentURL?.absoluteString ?? "输入网址…")
                        .font(.subheadline)
                        .foregroundStyle(model.currentURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("地址栏")
            .accessibilityValue(model.currentURL?.absoluteString ?? "空")
            .accessibilityHint("双击编辑网址")

            chromeButton("bookmark", label: "收藏，暂未开放", action: {})
        }
        .padding(.horizontal, 4)
    }

    private func addressEntryField(isStartPage: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("输入网址…", text: $addressDraft)
                        .focused($isAddressFieldFocused)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(submitAddress)
                        .accessibilityLabel("网址")

                    Button("前往", action: submitAddress)
                        .font(.subheadline.weight(.semibold))
                        .disabled(addressDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(
                    isStartPage ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(model.addressError == nil ? Color.secondary.opacity(0.2) : Color.red.opacity(0.75), lineWidth: 1)
                }

                if let error = model.addressError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            if !isStartPage {
                Button("取消", action: cancelAddressEditing)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 48)
                    .accessibilityHint("关闭地址编辑")
            }
        }
        .padding(.horizontal, isStartPage ? 0 : 8)
        .padding(.vertical, isStartPage ? 0 : 7)
        .animation(panelAnimation, value: model.addressError)
    }

    private func browserMessage(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Color(uiColor: .systemBackground)
            .opacity(0.96)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 14) {
                    Image(systemName: systemImage)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.title3.bold())
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                .padding(28)
            }
    }

    private func chromeButton(
        _ systemImage: String,
        label: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.42))
        .accessibilityLabel(label)
    }

    private func translationBall(in proxy: GeometryProxy) -> some View {
        let centerY = resolvedTranslationBallY(in: proxy)
        let centerX = proxy.size.width - proxy.safeAreaInsets.trailing - 14 - translationBallSize / 2

        return ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .stroke(Color.secondary.opacity(0.7), lineWidth: 2)
            Text("译")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)
        }
        .frame(width: translationBallSize, height: translationBallSize)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        .contentShape(Circle())
        .position(x: centerX + translationBallDragX, y: centerY)
        .onTapGesture {
            withAnimation(panelAnimation) {
                isTranslationMenuPresented.toggle()
            }
        }
        .gesture(translationBallDragGesture(in: proxy))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("翻译菜单")
        .accessibilityHint(isTranslationMenuPresented ? "双击收起" : "双击展开")
        .accessibilityAddTraits(.isButton)
    }

    private func translationBallDragGesture(in proxy: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if translationBallDragOriginY == nil {
                    translationBallDragOriginY = resolvedTranslationBallY(in: proxy)
                    isTranslationMenuPresented = false
                }
                let originY = translationBallDragOriginY ?? resolvedTranslationBallY(in: proxy)
                translationBallY = clampedTranslationBallY(originY + value.translation.height, in: proxy)
                translationBallDragX = min(0, max(-96, value.translation.width))
            }
            .onEnded { value in
                let originY = translationBallDragOriginY ?? resolvedTranslationBallY(in: proxy)
                withAnimation(panelAnimation) {
                    translationBallY = clampedTranslationBallY(originY + value.translation.height, in: proxy)
                    translationBallDragX = 0
                }
                translationBallDragOriginY = nil
            }
    }

    private func translationMenu(in proxy: GeometryProxy) -> some View {
        let safeHorizontalWidth = proxy.size.width - proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing
        let width = min(292, max(220, safeHorizontalWidth - 92))
        let ballCenterX = proxy.size.width - proxy.safeAreaInsets.trailing - 14 - translationBallSize / 2
        let menuCenterX = max(
            proxy.safeAreaInsets.leading + width / 2 + 10,
            ballCenterX - translationBallSize / 2 - 12 - width / 2
        )
        let availableHeight = max(180, proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom - 20)
        let menuHeight = min(translationMenuHeight, availableHeight)
        let minCenterY = proxy.safeAreaInsets.top + menuHeight / 2 + 10
        let maxCenterY = proxy.size.height - proxy.safeAreaInsets.bottom - menuHeight / 2 - 10
        let fallbackCenterY = proxy.size.height / 2
        let centerY = maxCenterY >= minCenterY
            ? min(max(resolvedTranslationBallY(in: proxy), minCenterY), maxCenterY)
            : fallbackCenterY

        return ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                Button("翻译本页") {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("界面占位，当前不会开始翻译")

                HStack {
                    Text("翻译进度")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("暂无任务")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("翻译模式", selection: $translationMode) {
                    ForEach(TranslationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Button(action: {}) {
                    HStack {
                        Text("语言对")
                        Spacer()
                        Text("日  →  中")
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("界面占位，当前不可更改")

                Picker("显示内容", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .frame(width: width, height: menuHeight)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.secondary.opacity(0.24), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
        .position(x: menuCenterX, y: centerY)
        .accessibilityElement(children: .contain)
    }

    private func resolvedTranslationBallY(in proxy: GeometryProxy) -> CGFloat {
        clampedTranslationBallY(translationBallY ?? proxy.size.height / 2, in: proxy)
    }

    private func clampedTranslationBallY(_ value: CGFloat, in proxy: GeometryProxy) -> CGFloat {
        let radius = translationBallSize / 2
        let minimum = proxy.safeAreaInsets.top + radius + 12
        let maximum = proxy.size.height - proxy.safeAreaInsets.bottom - toolbarHeight - radius - 14
        guard maximum >= minimum else { return proxy.size.height / 2 }
        return min(max(value, minimum), maximum)
    }

    private func beginAddressEditing() {
        addressDraft = model.currentURL?.absoluteString ?? ""
        model.clearAddressError()
        model.setChromeAutoHideSuspended(true)
        withAnimation(panelAnimation) {
            isEditingAddress = true
        }
        Task { @MainActor in
            isAddressFieldFocused = true
        }
    }

    private func cancelAddressEditing() {
        addressDraft = model.currentURL?.absoluteString ?? ""
        model.clearAddressError()
        isAddressFieldFocused = false
        model.setChromeAutoHideSuspended(false)
        withAnimation(panelAnimation) {
            isEditingAddress = false
        }
    }

    private func submitAddress() {
        guard model.load(address: addressDraft) else { return }
        addressDraft = model.currentURL?.absoluteString ?? addressDraft
        isAddressFieldFocused = false
        model.setChromeAutoHideSuspended(false)
        withAnimation(panelAnimation) {
            isEditingAddress = false
            isTranslationMenuPresented = false
        }
    }

    private func dismissTranslationMenu() {
        withAnimation(panelAnimation) {
            isTranslationMenuPresented = false
        }
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let model: BrowserModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.delegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        context.coordinator.observe(webView)
        model.attach(webView: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.scrollView.delegate = nil
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, UIScrollViewDelegate {
        private let model: BrowserModel
        private var observations: [NSKeyValueObservation] = []
        private var lastScrollOffsetY: CGFloat?

        init(model: BrowserModel) {
            self.model = model
        }

        func observe(_ webView: WKWebView) {
            observations = [
                webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.model.updateProgress(webView.estimatedProgress)
                    }
                },
                webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.model.updateCurrentURL(webView.url)
                    }
                },
                webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.model.refreshNavigationState(from: webView)
                    }
                },
                webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.model.refreshNavigationState(from: webView)
                    }
                }
            ]
        }

        func stopObserving() {
            observations.forEach { $0.invalidate() }
            observations.removeAll()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.navigationDidStart(url: webView.url, webView: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.navigationDidFinish(url: webView.url, webView: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model.navigationDidFail(error, webView: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            model.navigationDidFail(error, webView: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            model.webContentProcessDidTerminate(webView: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if model.handleExternalNavigationIfNeeded(url) {
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            let disposition = (navigationResponse.response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Disposition")?
                .lowercased() ?? ""
            if !navigationResponse.canShowMIMEType || disposition.contains("attachment") {
                model.reportUnsupportedDownload(webView: webView)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil,
                  let url = navigationAction.request.url else { return nil }
            if !model.handleExternalNavigationIfNeeded(url) {
                model.load(url: url)
            }
            return nil
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            lastScrollOffsetY = scrollView.contentOffset.y
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let offsetY = scrollView.contentOffset.y
            let topOffset = -scrollView.adjustedContentInset.top
            let isAtTop = offsetY <= topOffset + 1
            defer { lastScrollOffsetY = offsetY }

            guard let previousOffsetY = lastScrollOffsetY else {
                model.updateChromeVisibility(isScrollingDown: nil, isAtTop: isAtTop)
                return
            }
            let delta = offsetY - previousOffsetY
            guard abs(delta) >= 3 else {
                if isAtTop {
                    model.updateChromeVisibility(isScrollingDown: nil, isAtTop: true)
                }
                return
            }
            model.updateChromeVisibility(isScrollingDown: delta > 0, isAtTop: isAtTop)
        }
    }
}

#Preview {
    MangaBrowserView()
}
