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
    private let translationMenuHeight: CGFloat = 430
    private let expandedToolbarHeight: CGFloat = 48
    private let compactToolbarHeight: CGFloat = 36

    @Binding private var selectedTab: AppTab
    @EnvironmentObject private var store: TranslationSessionStore
    @Environment(AdBlockStore.self) private var adBlockStore
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
    @State private var isSelectingRegion = false
    @State private var selectionStart: CGPoint?
    @State private var selectionRect: CGRect?
    @AppStorage("aitrans.browser.sourceLanguage") private var browserSourceLanguageRaw = SupportedLanguage.japanese.rawValue
    @AppStorage("aitrans.browser.targetLanguage") private var browserTargetLanguageRaw = SupportedLanguage.simplifiedChinese.rawValue
    @AppStorage("aitrans.browser.fontName") private var browserFontName = "system"
    @AppStorage("aitrans.browser.fontScale") private var browserFontScale = 1.0
    // Legacy key names remain documented for migration/diagnostic contracts;
    // all live security writes go through AdBlockStore intents.
    private let legacySecurityPreferenceKeys = [
        "aitrans.browser.blockAds",
        "aitrans.browser.blockPopups",
        "aitrans.browser.blockRedirects",
        "aitrans.browser.elementRemoval",
        "aitrans.browser.antiHijacking"
    ]
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
                    topSafeAreaInset: proxy.safeAreaInsets.top,
                    captureExclusionInsets: captureExclusionInsets(in: proxy),
                    adBlockStore: adBlockStore
                )
                .id(model.activeTabID)
                .ignoresSafeArea(.container, edges: .all)

                if isSelectingRegion {
                    selectionOverlay(in: proxy)
                        .zIndex(8)
                }

                if displayMode == .translated,
                   let overlay = store.browserTranslationOverlay,
                   overlay.identity == model.pageIdentity,
                   model.phase == .loaded {
                    browserTranslationOverlays(overlay)
                        .zIndex(2)
                }

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
        .onAppear { syncBrowserIdentity() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            model.handleMemoryWarning()
            store.handleBrowserMemoryWarning()
        }
        .onChange(of: model.pageIdentityRevision) { _, _ in syncBrowserIdentity() }
        .onChange(of: model.pageIdentity) { _, _ in syncBrowserIdentity() }
        .onChange(of: browserSourceLanguageRaw) { _, _ in
            store.browserTranslationConfigurationDidChange()
        }
        .onChange(of: browserTargetLanguageRaw) { _, _ in
            store.browserTranslationConfigurationDidChange()
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
        .task(id: automaticTranslationIdentity) {
            guard let identity = automaticTranslationIdentity else { return }
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  automaticTranslationIdentity == identity,
                  !store.browserTranslationStatus.phase.isRunning else { return }
            captureAndTranslate(selection: nil)
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
            .overlay {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("漫画阅读器")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("一键翻译 · 沉浸阅读 · 本地安全")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        addressEntryField(isStartPage: true)
                        if !model.bookmarks.isEmpty {
                            Text("我的收藏").font(.headline)
                            ForEach(model.bookmarks.prefix(8)) { bookmark in
                                startPageBookmark(bookmark)
                            }
                        }
                        Text("漫画站点快捷入口")
                            .font(.headline)
                            .padding(.top, 4)
                        HStack(spacing: 10) {
                            ForEach(BrowserModel.recommendedBookmarks) { bookmark in
                                Button { model.openBookmark(bookmark) } label: {
                                    Text(bookmark.title)
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .frame(maxWidth: 620)
                    .padding(.horizontal, 24)
                    .padding(.top, 90)
                    .padding(.bottom, 24)
                }
            }
    }

    private func startPageBookmark(_ bookmark: BrowserBookmark) -> some View {
        HStack(spacing: 10) {
            Button { model.openBookmark(bookmark) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bookmark.fill").foregroundStyle(.blue)
                    Text(bookmark.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(bookmark.url?.host ?? "").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button {
                model.removeBookmark(bookmark)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除收藏")
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

                Button(action: model.toggleActiveBookmark) {
                    Image(systemName: model.isActivePageBookmarked ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(model.isActivePageBookmarked ? .blue : .primary)
                        .frame(width: 34, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isActivePageBookmarked ? "取消收藏" : "收藏此页面")
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
                Button {
                    captureAndTranslate(selection: nil)
                } label: {
                    Label(
                        store.browserTranslationStatus.phase.isRunning ? "翻译中…" : "一键翻译本页",
                        systemImage: store.browserTranslationStatus.phase.isRunning
                            ? "hourglass"
                            : "text.viewfinder"
                    )
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(store.browserTranslationStatus.phase.isRunning)
                    .accessibilityHint("截取当前可视内容区并翻译，浏览器导航栏不会进入识别")

                Button {
                    beginRegionSelection()
                } label: {
                    Label("框选翻译", systemImage: "crop")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(store.browserTranslationStatus.phase.isRunning)

                HStack {
                    Text("翻译进度").font(.subheadline.weight(.semibold))
                    Spacer()
                    if store.browserTranslationStatus.phase.isRunning {
                        Text("\(Int(store.browserTranslationStatus.fractionCompleted * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text(store.browserTranslationStatus.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if store.browserTranslationStatus.phase.isRunning {
                    ProgressView(value: store.browserTranslationStatus.fractionCompleted)
                        .tint(.blue)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(browserTranslationETA)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if store.browserTranslationStatus.phase == .failed
                    || store.browserTranslationStatus.phase == .partial {
                    Button("重试") { captureAndTranslate(selection: nil) }
                        .buttonStyle(.bordered)
                }
                if store.browserTranslationStatus.phase.isRunning {
                    Button("取消翻译") { store.cancelBrowserTranslation() }
                        .buttonStyle(.bordered)
                }

                Picker("翻译模式", selection: $translationMode) {
                    ForEach(TranslationMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)

                Menu {
                    BrowserLanguageMenuContent(
                        sourceLanguageRaw: $browserSourceLanguageRaw,
                        targetLanguageRaw: $browserTargetLanguageRaw
                    )
                } label: {
                    HStack {
                        Text("语言对")
                        Spacer()
                        Text("\(browserSourceLanguage.shortName)  →  \(browserTargetLanguage.shortName)")
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .accessibilityHint("直接选择浏览器翻译的源语言与目标语言")

                Picker("显示内容", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)

                Divider()

                Toggle("广告防护", isOn: adBlockMasterBinding)
                    .font(.subheadline.weight(.semibold))
                Toggle("网络拦截", isOn: adBlockNetworkBinding)
                    .disabled(!adBlockStore.state.preferences.isEnabled)
                Toggle("页面脚本保护", isOn: adBlockScriptBinding)
                    .disabled(!adBlockStore.state.preferences.isEnabled)
                Toggle("精准元素隐藏", isOn: adBlockCosmeticBinding)
                    .disabled(!adBlockStore.state.preferences.isEnabled)

                Label(
                    "防护 \(enabledSecurityFeatureCount)/6 已开启",
                    systemImage: "shield.lefthalf.filled"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text(adBlockStore.state.message)
                    .font(.caption2)
                    .foregroundStyle(adBlockStore.state.lastError == nil ? Color.secondary : Color.orange)
                    .lineLimit(2)

                if let performance = store.browserPerformanceSample {
                    Label(
                        "诊断：温度 \(performance.thermalState) · CPU \(performance.activeProcessorCount)/\(performance.processorCount) · 内存 \(formattedBytes(performance.residentMemoryBytes))",
                        systemImage: "gauge.with.dots.needle.67percent"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
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

    private func formattedBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    private func resolvedTranslationBallY(in proxy: GeometryProxy) -> CGFloat {
        clampedTranslationBallY(translationBallY ?? proxy.size.height / 2, in: proxy)
    }

    private var browserSourceLanguage: SupportedLanguage {
        SupportedLanguage(rawValue: browserSourceLanguageRaw) ?? .japanese
    }

    private var browserTargetLanguage: SupportedLanguage {
        SupportedLanguage(rawValue: browserTargetLanguageRaw) ?? .simplifiedChinese
    }

    private var enabledSecurityFeatureCount: Int {
        let preferences = adBlockStore.state.preferences
        return [
            preferences.effectiveNetworkFiltering,
            preferences.effectiveScriptProtection,
            preferences.effectiveCosmeticFiltering,
            preferences.effectivePopupBlocking,
            preferences.effectiveRedirectBlocking,
            preferences.effectiveElementPicker
        ]
            .count(where: { $0 })
    }

    private var adBlockMasterBinding: Binding<Bool> {
        Binding(
            get: { adBlockStore.state.preferences.isEnabled },
            set: { adBlockStore.send(.setEnabled($0)) }
        )
    }

    private var adBlockNetworkBinding: Binding<Bool> {
        Binding(
            get: { adBlockStore.state.preferences.networkFilteringEnabled },
            set: { adBlockStore.send(.setNetworkFiltering($0)) }
        )
    }

    private var adBlockScriptBinding: Binding<Bool> {
        Binding(
            get: { adBlockStore.state.preferences.scriptProtectionEnabled },
            set: { adBlockStore.send(.setScriptProtection($0)) }
        )
    }

    private var adBlockCosmeticBinding: Binding<Bool> {
        Binding(
            get: { adBlockStore.state.preferences.cosmeticFilteringEnabled },
            set: { adBlockStore.send(.setCosmeticFiltering($0)) }
        )
    }

    private var browserTranslationETA: String {
        guard let startedAt = store.browserTranslationStatus.startedAt,
              let estimate = store.browserTranslationStatus.estimatedDurationMilliseconds else {
            return "正在估算剩余时间…"
        }
        let elapsed = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let remaining = max(0, estimate - elapsed)
        if remaining < 1_000 { return "即将完成" }
        return "预计还需约 \(max(1, remaining / 1_000)) 秒"
    }

    private var automaticTranslationIdentity: BrowserPageSnapshotIdentity? {
        guard translationMode == .automatic,
              model.phase == .loaded,
              model.pageIdentity.isStable else { return nil }
        return model.pageIdentity
    }

    private func captureExclusionInsets(in proxy: GeometryProxy) -> UIEdgeInsets {
        let bottomChrome = model.showsExpandedChrome ? expandedToolbarHeight : compactToolbarHeight
        return UIEdgeInsets(
            top: max(proxy.safeAreaInsets.top, 0),
            left: max(proxy.safeAreaInsets.leading, 0),
            bottom: max(proxy.safeAreaInsets.bottom, 8) + bottomChrome + 6,
            right: max(proxy.safeAreaInsets.trailing, 0)
        )
    }

    private func syncBrowserIdentity() {
        store.updateBrowserPageIdentity(model.pageIdentity)
    }

    private func captureAndTranslate(selection: CGRect?) {
        isTranslationMenuPresented = false
        let requestedSelection = selection.map(BrowserCaptureSelection.init(rectInView:))
        Task { @MainActor in
            do {
                let capture = try await model.captureVisibleContent(selection: requestedSelection)
                store.updateBrowserPageIdentity(capture.identity)
                store.translateBrowserCapture(
                    capture,
                    sourceLanguage: browserSourceLanguage,
                    targetLanguage: browserTargetLanguage
                )
                displayMode = .translated
            } catch {
                store.reportBrowserTranslationFailure(error.localizedDescription)
            }
        }
    }

    private func beginRegionSelection() {
        isTranslationMenuPresented = false
        isSelectingRegion = true
        selectionStart = nil
        selectionRect = nil
        model.setChromeAutoHideSuspended(true)
    }

    private func finishRegionSelection() {
        guard let selectionRect,
              selectionRect.width >= 24,
              selectionRect.height >= 24 else {
            store.reportBrowserTranslationFailure("框选区域太小，请重新拖动选择文字")
            isSelectingRegion = false
            model.setChromeAutoHideSuspended(false)
            return
        }
        isSelectingRegion = false
        selectionStart = nil
        model.setChromeAutoHideSuspended(false)
        captureAndTranslate(selection: selectionRect)
    }

    private func selectionOverlay(in proxy: GeometryProxy) -> some View {
        ZStack {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if let selectionRect {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [7, 4]))
                    }
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)
                    .allowsHitTesting(false)
            }
            VStack {
                HStack {
                    Label("拖动框选文字区域", systemImage: "viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    Button("取消") {
                        isSelectingRegion = false
                        selectionStart = nil
                        selectionRect = nil
                        model.setChromeAutoHideSuspended(false)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, max(proxy.safeAreaInsets.top, 10) + 8)
                .padding(.horizontal, 14)
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .local)
                .onChanged { value in
                    let start = selectionStart ?? value.startLocation
                    selectionStart = start
                    let rect = CGRect(
                        x: min(start.x, value.location.x),
                        y: min(start.y, value.location.y),
                        width: abs(value.location.x - start.x),
                        height: abs(value.location.y - start.y)
                    )
                    selectionRect = rect
                }
                .onEnded { _ in finishRegionSelection() }
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func browserTranslationOverlays(_ snapshot: BrowserTranslationOverlaySnapshot) -> some View {
        ForEach(snapshot.regions) { region in
            BrowserTranslationOverlay(
                region: region,
                captureRect: snapshot.captureRectInView,
                fontName: browserFontName,
                fontScale: browserFontScale
            )
        }
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

private struct BrowserTranslationOverlay: View {
    let region: BrowserTranslationRegion
    let captureRect: CGRect
    let fontName: String
    let fontScale: Double

    var body: some View {
        let rect = CGRect(
            x: captureRect.minX + captureRect.width * CGFloat(region.boundingBox.x),
            y: captureRect.minY + captureRect.height * CGFloat(region.boundingBox.y),
            width: captureRect.width * CGFloat(region.boundingBox.width),
            height: captureRect.height * CGFloat(region.boundingBox.height)
        )
        let text = region.translation.isEmpty ? region.original : region.translation
        let vertical = region.sourceDirection == .vertical && textContainsCJK(text)
        let plan = ImageTranslationTextFitter.fit(text: text, in: rect.size, vertical: vertical)
        // The slider is a readable-size preference, not permission to escape
        // the authenticated OCR rectangle. The fitter remains the hard upper
        // bound while roomy bubbles can grow up to the selected cap.
        let preferredFontCap = CGFloat(18 * min(max(fontScale, 0.75), 1.35))
        let adjustedFontSize = min(plan.fontSize, preferredFontCap)

        Group {
            if vertical {
                verticalText(text: text, plan: plan, fontSize: adjustedFontSize)
            } else {
                Text(text)
                    .font(resolvedFont(size: adjustedFontSize))
                    .foregroundStyle(.black)
                    .lineLimit(plan.lineLimit)
                    .multilineTextAlignment(.center)
                    .allowsTightening(true)
                    .tracking(textContainsCJK(text) ? 0 : -0.12)
                    .lineSpacing(textContainsCJK(text) ? 0 : max(0, adjustedFontSize * 0.04))
                    .minimumScaleFactor(0.65)
                    .frame(width: plan.contentSize.width, height: plan.contentSize.height)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .background(.white.opacity(region.translationError == nil ? 0.96 : 0.90), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 3)
                .stroke(
                    region.translationError == nil ? .black.opacity(0.08) : .orange.opacity(0.82),
                    lineWidth: region.translationError == nil ? 0.5 : 1
                )
        }
        .clipped()
        .position(x: rect.midX, y: rect.midY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            region.translationError == nil
                ? "译文：\(region.translation.isEmpty ? region.original : region.translation)"
                : "翻译失败，保留原文：\(region.original)"
        )
    }

    @ViewBuilder
    private func verticalText(text: String, plan: ImageTranslationTextFitter.Plan, fontSize: CGFloat) -> some View {
        let characters = ImageTranslationVerticalTextLayout.normalizedCharacters(in: text)
        let drawableCharacters = boundedVerticalCharacters(
            characters,
            maximumCharacters: plan.maximumCharacterCount
        )
        let columns = verticalColumns(drawableCharacters, rowCapacity: plan.rowCapacity)
        let cellScale = plan.fontSize > 0 ? fontSize / plan.fontSize : 1
        let cellWidth = plan.cellWidth * cellScale
        let cellHeight = plan.cellHeight * cellScale
        HStack(alignment: .top, spacing: 0) {
            ForEach(columns.indices.reversed(), id: \.self) { columnIndex in
                VStack(spacing: 0) {
                    ForEach(columns[columnIndex].indices, id: \.self) { characterIndex in
                        let character = columns[columnIndex][characterIndex]
                        let glyph = ImageTranslationVerticalTextLayout.verticalGlyph(for: character)
                        let isPunctuation = ImageTranslationVerticalTextLayout
                            .isFullwidthPunctuation(character)
                        Text(glyph)
                            .font(resolvedFont(size: fontSize))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                            .frame(
                                width: cellWidth,
                                height: cellHeight,
                                alignment: isPunctuation ? .center : .top
                            )
                    }
                }
            }
        }
        .frame(width: plan.contentSize.width, height: plan.contentSize.height, alignment: .topTrailing)
        .clipped()
    }

    private func verticalColumns(_ characters: [String], rowCapacity: Int) -> [[String]] {
        guard !characters.isEmpty else { return [[]] }
        return stride(from: 0, to: characters.count, by: rowCapacity).map { start in
            Array(characters[start..<min(start + rowCapacity, characters.count)])
        }
    }

    private func boundedVerticalCharacters(
        _ characters: [String],
        maximumCharacters: Int
    ) -> [String] {
        guard characters.count > maximumCharacters else { return characters }
        return Array(characters.prefix(max(maximumCharacters - 1, 1))) + ["…"]
    }

    private func resolvedFont(size: CGFloat) -> Font {
        switch fontName {
        case "kaiti": return .custom("STKaitiSC-Regular", size: size, relativeTo: .body)
        case "rounded": return .system(size: size, weight: .semibold, design: .rounded)
        default: return .system(size: size, weight: .semibold, design: .default)
        }
    }

    private func textContainsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
        }
    }
}

private extension View {
    func browserCapsule() -> some View {
        background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.34), lineWidth: 0.5) }
    }
}

private struct BrowserLanguageMenuRow: View {
    let language: SupportedLanguage
    let isSelected: Bool

    var body: some View {
        Group {
            if isSelected {
                Label(language.rawValue, systemImage: "checkmark")
            } else {
                Text(language.rawValue)
            }
        }
    }
}

private struct BrowserLanguageMenuContent: View {
    @Binding var sourceLanguageRaw: String
    @Binding var targetLanguageRaw: String

    var body: some View {
        Section("源语言") {
            ForEach(SupportedLanguage.allCases) { language in
                Button {
                    sourceLanguageRaw = language.rawValue
                } label: {
                    BrowserLanguageMenuRow(
                        language: language,
                        isSelected: language.rawValue == sourceLanguageRaw
                    )
                }
            }
        }
        Section("目标语言") {
            ForEach(SupportedLanguage.allCases) { language in
                Button {
                    targetLanguageRaw = language.rawValue
                } label: {
                    BrowserLanguageMenuRow(
                        language: language,
                        isSelected: language.rawValue == targetLanguageRaw
                    )
                }
            }
        }
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let model: BrowserModel
    let tabID: UUID
    let topSafeAreaInset: CGFloat
    let captureExclusionInsets: UIEdgeInsets
    let adBlockStore: AdBlockStore

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, adBlockStore: adBlockStore, tabID: tabID)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = [.all]
        let securityController = configuration.userContentController
        securityController.add(context.coordinator, name: "aitransPageMutation")
        securityController.addUserScript(
            WKUserScript(
                source: BrowserSecurityScript.pageMutationObserverSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        adBlockStore.send(
            .prepareWebViewConfiguration(
                configuration,
                messageHandler: context.coordinator
            )
        )

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
        model.updateCaptureExclusionInsets(captureExclusionInsets)
        context.coordinator.observe(webView)
        adBlockStore.send(.attachWebView(webView, attachmentID: context.coordinator.attachmentID))
        model.attach(webView: webView, to: tabID)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateTopSafeAreaInset(topSafeAreaInset, in: webView)
        model.updateCaptureExclusionInsets(captureExclusionInsets)
        model.updateViewport(size: webView.bounds.size, webView: webView, tabID: tabID)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.model.detach(webView: webView, from: coordinator.tabID)
        coordinator.adBlockStore.send(
            .detachWebView(webView, attachmentID: coordinator.attachmentID)
        )
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.scrollView.delegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "aitransPageMutation")
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, UIScrollViewDelegate, WKScriptMessageHandler {
        fileprivate let model: BrowserModel
        fileprivate let adBlockStore: AdBlockStore
        fileprivate let tabID: UUID
        fileprivate let attachmentID = UUID()
        private var observations: [NSKeyValueObservation] = []
        private var lastScrollOffsetY: CGFloat?
        private weak var observedWebView: WKWebView?

        init(model: BrowserModel, adBlockStore: AdBlockStore, tabID: UUID) {
            self.model = model
            self.adBlockStore = adBlockStore
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
            if !allows(navigationAction: navigationAction, url: url, in: webView) {
                adBlockStore.send(.recordBlockedNavigation(url))
                decisionHandler(.cancel)
                return
            }
            if adBlockStore.state.preferences.effectiveScriptProtection,
               isExternalNavigation(url),
               navigationAction.navigationType != .linkActivated {
                adBlockStore.send(.recordBlockedNavigation(url))
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
            if adBlockStore.state.preferences.effectivePopupBlocking {
                adBlockStore.send(.recordBlockedNavigation(url))
                return nil
            }
            if !model.handleExternalNavigationIfNeeded(url) { model.load(url: url) }
            return nil
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.frameInfo.isMainFrame else { return }
            switch message.name {
            case AdBlockWebScript.elementRuleMessageName:
                guard let selector = message.body as? String else { return }
                adBlockStore.send(.rememberElementSelector(selector))
            case "aitransPageMutation":
                model.pageContentDidChange(layoutChanged: message.body as? String == "layout")
            default:
                break
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            lastScrollOffsetY = scrollView.contentOffset.y
            model.scrollViewWillBeginInteraction()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { model.scrollViewDidEndInteraction() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            model.scrollViewDidEndInteraction()
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            model.scrollViewWillBeginInteraction()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with scale: CGFloat) {
            model.scrollViewDidEndInteraction()
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

        private func allows(navigationAction: WKNavigationAction, url: URL, in webView: WKWebView) -> Bool {
            guard adBlockStore.state.preferences.effectiveRedirectBlocking,
                  model.phase == .loaded,
                  let current = webView.url,
                  current != url,
                  navigationAction.navigationType == .other else { return true }
            // A URL entered by the user or requested by BrowserModel is
            // already reflected in its intent state; do not misclassify that
            // deliberate cross-site load as a hostile redirect.
            if model.currentURL == url { return true }
            return current.host?.lowercased() == url.host?.lowercased()
        }

        private func isExternalNavigation(_ url: URL) -> Bool {
            let scheme = url.scheme?.lowercased() ?? ""
            if scheme != "http" && scheme != "https" { return true }
            return url.host?.lowercased() == "apps.apple.com"
        }
    }
}

#Preview {
    MangaBrowserView(selectedTab: .constant(.manga))
        .environment(AdBlockStore())
        .environmentObject(
            TranslationSessionStore(
                modelService: MockGemmaService(),
                persistenceURL: FileManager.default.temporaryDirectory
                    .appending(path: "aitrans-browser-preview.json"),
                performsStartupWork: false
            )
        )
}
