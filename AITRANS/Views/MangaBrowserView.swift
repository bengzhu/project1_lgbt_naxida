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
    private let translationBallSize: CGFloat = 48
    private let translationMenuHeight: CGFloat = 284
    private let expandedToolbarHeight: CGFloat = 48
    private let compactToolbarHeight: CGFloat = 36

    @Binding private var selectedTab: AppTab
    @State private var model = BrowserModel()
    @State private var addressDraft = ""
    @State private var isEditingAddress = false
    @State private var isTabSwitcherPresented = false
    @State private var isTranslationMenuPresented = false
    @State private var translationMode = TranslationMode.manual
    @State private var displayMode = DisplayMode.original
    @State private var translationBallY: CGFloat?
    @State private var translationBallDragOriginY: CGFloat?
    @State private var translationBallDragX: CGFloat = 0
    @FocusState private var isAddressFieldFocused: Bool

    init(selectedTab: Binding<AppTab>) {
        _selectedTab = selectedTab
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BrowserWebView(
                    model: model,
                    tabID: model.activeTabID,
                    topSafeAreaInset: proxy.safeAreaInsets.top
                )
                .id(model.activeTabID)
                .ignoresSafeArea(.container, edges: .all)

                phaseOverlay

                if isTranslationMenuPresented && model.phase == .loaded && model.showsExpandedChrome && !isTabSwitcherPresented {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { dismissTranslationMenu() }
                        .ignoresSafeArea()
                        .zIndex(3)

                    translationMenu(in: proxy)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                        .zIndex(4)
                }

                if model.phase == .loaded && model.showsExpandedChrome && !isTabSwitcherPresented {
                    translationBall(in: proxy)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(5)
                }

                if !isTabSwitcherPresented {
                    browserToolbar(in: proxy)
                        .zIndex(6)

                    if model.showsExpandedChrome {
                        exitButton(in: proxy)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .zIndex(7)
                    }
                }

                if isTabSwitcherPresented {
                    tabSwitcher(in: proxy)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(10)
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
                        .zIndex(12)
                }
            }
            .animation(panelAnimation, value: model.chromeMode)
            .animation(panelAnimation, value: isTranslationMenuPresented)
            .animation(panelAnimation, value: isTabSwitcherPresented)
            .animation(panelAnimation, value: model.noticeRevision)
        }
        .background(Color.white)
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: model.phase) { _, phase in
            guard phase == .loaded else {
                isTranslationMenuPresented = false
                return
            }
        }
        .onChange(of: model.showsExpandedChrome) { _, expanded in
            if !expanded { isTranslationMenuPresented = false }
        }
        .onChange(of: model.activeTabID) { _, _ in
            addressDraft = model.currentURL?.absoluteString ?? ""
            isAddressFieldFocused = false
            isEditingAddress = false
            isTranslationMenuPresented = false
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
        Color.white
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                addressEntryField(isStartPage: true)
                    .frame(maxWidth: 620)
                    .padding(.horizontal, 24)
                    .padding(.top, 120)
            }
    }

    private func browserToolbar(in proxy: GeometryProxy) -> some View {
        VStack {
            Spacer(minLength: 0)

            if isEditingAddress {
                addressEntryField(isStartPage: false)
                    .frame(maxWidth: 760)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if model.chromeMode == .compact {
                compactAddressCapsule
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            } else {
                expandedBrowserControls
                    .frame(maxWidth: 760)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, max(proxy.safeAreaInsets.bottom, 8) + 6)
        .allowsHitTesting(!model.isSwitchingTabs)
    }

    private var expandedBrowserControls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                chromeButton("chevron.backward", label: "后退", enabled: model.canGoBack, action: model.goBack)
                chromeButton("chevron.forward", label: "前进", enabled: model.canGoForward, action: model.goForward)
            }
            .padding(.horizontal, 4)
            .frame(height: expandedToolbarHeight)
            .browserCapsule()

            HStack(spacing: 4) {
                Button(action: beginAddressEditing) {
                    HStack(spacing: 7) {
                        Image(systemName: model.currentURL?.scheme == "https" ? "lock.fill" : "globe")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(model.displayHost)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("地址栏")
                .accessibilityValue(model.displayHost)
                .accessibilityHint("双击编辑完整网址")

                Button(action: model.reload) {
                    ZStack {
                        Image(systemName: "arrow.clockwise")
                            .opacity(model.phase == .loading ? 0 : 1)
                        if model.phase == .loading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(width: 38, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.phase == .loading ? "正在载入" : "刷新")
            }
            .padding(.leading, 14)
            .padding(.trailing, 5)
            .frame(maxWidth: .infinity, minHeight: expandedToolbarHeight)
            .browserCapsule()

            Button(action: presentTabSwitcher) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 40, height: 40)
                    Text("\(model.tabCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Color.blue, in: Circle())
                        .offset(x: 4, y: -2)
                }
                .frame(width: 48, height: expandedToolbarHeight)
            }
            .buttonStyle(.plain)
            .browserCapsule()
            .accessibilityLabel("标签")
            .accessibilityValue("\(model.tabCount) 个标签")
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }

    private var compactAddressCapsule: some View {
        Button(action: beginAddressEditing) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(model.displayHost)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 14)
            .frame(minWidth: 132, maxWidth: 220, minHeight: compactToolbarHeight)
        }
        .buttonStyle(.plain)
        .browserCapsule()
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        .accessibilityLabel("收起的地址栏")
        .accessibilityValue(model.displayHost)
    }

    private func exitButton(in proxy: GeometryProxy) -> some View {
        Button {
            isAddressFieldFocused = false
            selectedTab = .text
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .browserCapsule()
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, max(proxy.safeAreaInsets.leading, 12) + 4)
        .padding(.top, max(proxy.safeAreaInsets.top, 8) + 8)
        .accessibilityLabel("退出漫画浏览器")
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
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(model.addressError == nil ? Color.secondary.opacity(0.2) : Color.red.opacity(0.75), lineWidth: 1)
                }
                .shadow(color: .black.opacity(isStartPage ? 0.08 : 0.16), radius: 14, y: 5)

                if let error = model.addressError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            if !isStartPage {
                Button("取消", action: cancelAddressEditing)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .browserCapsule()
                    .accessibilityHint("关闭地址编辑")
            }
        }
        .animation(panelAnimation, value: model.addressError)
    }

    private func tabSwitcher(in proxy: GeometryProxy) -> some View {
        let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

        return ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Text("标签")
                        .font(.largeTitle.bold())
                    Spacer()
                    Button("完成", action: dismissTabSwitcher)
                        .font(.headline)
                }

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.tabs) { tab in
                            tabCard(tab)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)

                Button(action: createNewTab) {
                    Label("新建标签", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(model.isSwitchingTabs)
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 18)
            .padding(.top, max(proxy.safeAreaInsets.top, 12) + 12)
            .padding(.bottom, max(proxy.safeAreaInsets.bottom, 12) + 8)
        }
    }

    private func tabCard(_ tab: BrowserModel.BrowserTab) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Color.white
                if let thumbnail = tab.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "globe.asia.australia.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.blue.opacity(0.65))
                        Text(tab.displayHost)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(0.82, contentMode: .fit)
            .clipped()

            HStack(spacing: 8) {
                Image(systemName: tab.currentURL?.scheme == "https" ? "lock.fill" : "globe")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(tab.displayHost)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    model.closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭 \(tab.displayHost)")
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tab.id == model.activeTabID ? Color.blue : Color.secondary.opacity(0.18), lineWidth: tab.id == model.activeTabID ? 2 : 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 12, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            guard tab.id != model.activeTabID else {
                dismissTabSwitcher()
                return
            }
            model.activateTab(tab.id)
            dismissTabSwitcher()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(tab.id == model.activeTabID ? .isSelected : [])
    }

    private func browserMessage(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Color.white
            .opacity(0.97)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 14) {
                    Image(systemName: systemImage)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(title).font(.title3.bold())
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
                .frame(width: 36, height: 40)
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
            Circle().fill(.ultraThinMaterial)
            Circle().stroke(Color.secondary.opacity(0.7), lineWidth: 2)
            Text("译")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)
        }
        .frame(width: translationBallSize, height: translationBallSize)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        .contentShape(Circle())
        .position(x: centerX + translationBallDragX, y: centerY)
        .onTapGesture {
            withAnimation(panelAnimation) { isTranslationMenuPresented.toggle() }
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
        let menuCenterX = max(proxy.safeAreaInsets.leading + width / 2 + 10, ballCenterX - translationBallSize / 2 - 12 - width / 2)
        let availableHeight = max(180, proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom - 20)
        let menuHeight = min(translationMenuHeight, availableHeight)
        let minCenterY = proxy.safeAreaInsets.top + menuHeight / 2 + 10
        let maxCenterY = proxy.size.height - proxy.safeAreaInsets.bottom - menuHeight / 2 - 10
        let centerY = maxCenterY >= minCenterY
            ? min(max(resolvedTranslationBallY(in: proxy), minCenterY), maxCenterY)
            : proxy.size.height / 2

        return ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                Button("翻译本页") {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("界面占位，当前不会开始翻译")

                HStack {
                    Text("翻译进度").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("暂无任务").font(.caption).foregroundStyle(.secondary)
                }

                Picker("翻译模式", selection: $translationMode) {
                    ForEach(TranslationMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)

                Button(action: {}) {
                    HStack {
                        Text("语言对")
                        Spacer()
                        Text("日  →  中").fontWeight(.semibold)
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("界面占位，当前不可更改")

                Picker("显示内容", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .frame(width: width, height: menuHeight)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.secondary.opacity(0.24), lineWidth: 0.5) }
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
        let maximum = proxy.size.height - proxy.safeAreaInsets.bottom - expandedToolbarHeight - radius - 28
        guard maximum >= minimum else { return proxy.size.height / 2 }
        return min(max(value, minimum), maximum)
    }

    private func beginAddressEditing() {
        addressDraft = model.currentURL?.absoluteString ?? ""
        model.clearAddressError()
        model.setChromeAutoHideSuspended(true)
        withAnimation(panelAnimation) { isEditingAddress = true }
        Task { @MainActor in isAddressFieldFocused = true }
    }

    private func cancelAddressEditing() {
        addressDraft = model.currentURL?.absoluteString ?? ""
        model.clearAddressError()
        isAddressFieldFocused = false
        model.setChromeAutoHideSuspended(false)
        withAnimation(panelAnimation) { isEditingAddress = false }
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

    private func presentTabSwitcher() {
        isAddressFieldFocused = false
        isTranslationMenuPresented = false
        model.setChromeAutoHideSuspended(true)
        model.captureActiveThumbnail()
        withAnimation(panelAnimation) { isTabSwitcherPresented = true }
    }

    private func dismissTabSwitcher() {
        withAnimation(panelAnimation) { isTabSwitcherPresented = false }
        model.setChromeAutoHideSuspended(false)
    }

    private func createNewTab() {
        model.newTab()
        dismissTabSwitcher()
    }

    private func dismissTranslationMenu() {
        withAnimation(panelAnimation) { isTranslationMenuPresented = false }
    }
}

private extension View {
    func browserCapsule() -> some View {
        background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.34), lineWidth: 0.5) }
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let model: BrowserModel
    let tabID: UUID
    let topSafeAreaInset: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, tabID: tabID)
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
        webView.isOpaque = true
        webView.backgroundColor = .white
        webView.underPageBackgroundColor = .white
        webView.scrollView.backgroundColor = .white
        webView.overrideUserInterfaceStyle = .light

        context.coordinator.updateTopSafeAreaInset(topSafeAreaInset, in: webView)
        context.coordinator.observe(webView)
        model.attach(webView: webView, to: tabID)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateTopSafeAreaInset(topSafeAreaInset, in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.model.detach(webView: webView, from: coordinator.tabID)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.scrollView.delegate = nil
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, UIScrollViewDelegate {
        fileprivate let model: BrowserModel
        fileprivate let tabID: UUID
        private var observations: [NSKeyValueObservation] = []
        private var lastScrollOffsetY: CGFloat?
        private weak var observedWebView: WKWebView?

        init(model: BrowserModel, tabID: UUID) {
            self.model = model
            self.tabID = tabID
        }

        func updateTopSafeAreaInset(_ inset: CGFloat, in webView: WKWebView) {
            let topInset = max(0, inset)
            guard abs(webView.scrollView.contentInset.top - topInset) > 0.5 else { return }
            let wasAtTop = webView.scrollView.contentOffset.y <= -webView.scrollView.contentInset.top + 1
            webView.scrollView.contentInset.top = topInset
            webView.scrollView.verticalScrollIndicatorInsets.top = topInset
            if wasAtTop {
                webView.scrollView.setContentOffset(CGPoint(x: 0, y: -topInset), animated: false)
            }
        }

        func observe(_ webView: WKWebView) {
            observedWebView = webView
            observations = [
                webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.model.updateProgress(webView.estimatedProgress, webView: webView, tabID: self.tabID)
                    }
                },
                webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.model.updateCurrentURL(webView.url, webView: webView, tabID: self.tabID)
                    }
                },
                webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.model.refreshNavigationState(from: webView, tabID: self.tabID)
                    }
                },
                webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.model.refreshNavigationState(from: webView, tabID: self.tabID)
                    }
                }
            ]
        }

        func stopObserving() {
            observations.forEach { $0.invalidate() }
            observations.removeAll()
            observedWebView = nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.navigationDidStart(url: webView.url, webView: webView, tabID: tabID)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.navigationDidFinish(url: webView.url, webView: webView, tabID: tabID)
            guard let offset = model.restorationScrollOffset(for: tabID) else { return }
            DispatchQueue.main.async { [weak webView] in
                webView?.scrollView.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model.navigationDidFail(error, webView: webView, tabID: tabID)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            model.navigationDidFail(error, webView: webView, tabID: tabID)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            model.webContentProcessDidTerminate(webView: webView, tabID: tabID)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(model.handleExternalNavigationIfNeeded(url) ? .cancel : .allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
        ) {
            let disposition = (navigationResponse.response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Disposition")?
                .lowercased() ?? ""
            if !navigationResponse.canShowMIMEType || disposition.contains("attachment") {
                model.reportUnsupportedDownload(webView: webView, tabID: tabID)
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
            if !model.handleExternalNavigationIfNeeded(url) { model.load(url: url) }
            return nil
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            lastScrollOffsetY = scrollView.contentOffset.y
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let offsetY = scrollView.contentOffset.y
            if let observedWebView {
                model.updateScrollOffset(offsetY, webView: observedWebView, tabID: tabID)
            }
            let topOffset = -scrollView.adjustedContentInset.top
            let isAtTop = offsetY <= topOffset + 1
            defer { lastScrollOffsetY = offsetY }

            guard let previousOffsetY = lastScrollOffsetY else {
                model.updateChromePresentation(isScrollingDown: nil, isAtTop: isAtTop)
                return
            }
            let delta = offsetY - previousOffsetY
            guard abs(delta) >= 4 else {
                if isAtTop { model.updateChromePresentation(isScrollingDown: nil, isAtTop: true) }
                return
            }
            model.updateChromePresentation(isScrollingDown: delta > 0, isAtTop: isAtTop)
        }
    }
}

#Preview {
    MangaBrowserView(selectedTab: .constant(.manga))
}
