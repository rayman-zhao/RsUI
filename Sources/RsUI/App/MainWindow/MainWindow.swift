import Foundation
import Observation
import UWP
import WinAppSDK
import WinUI
import WindowsFoundation

private func tr(_ keyAndValue: String) -> String {
    return App.context.tr(keyAndValue)
}

/// 主窗口壳：`NavigationViewWindow` + 一个 `PageControl (PageTabView)` 作为内容容器。
///
/// 本类主要功能在于处理导航URL与Page对象的映射，并协调UI元素的显示。
///
/// 提供context接口用于隔离窗口具体类型。
class MainWindow: NavigationViewWindow {
    private var context: WindowContext {
        WindowContext(owner: self)
    }
    private lazy var pageControl = PageTabView()

    // MARK: - Init

    init(url: URL? = nil, forceMinimalMode: Bool = false) {
        super.init(forceMinimalMode)
        useMicaBackdrop()
        useRestoration()

        setupUI()
        bindEvents()

        Task { @MainActor [weak self] in
            guard let self else { return }

            if let url, self.navigate(to: url) {
                return
            } else if let home = self.ui.navigationView.firstItemURL {
                self.navigate(to: home)
            }
        }
    }

    private func setupUI() {
        ui.navigationView.content = pageControl
        ui.backButton.isEnabled = false
        ui.forwardButton.isEnabled = false
    }

    private func bindEvents() {
        self.appearanceChanged.addHandler { [weak self] _ in
            guard let self else { return }

            ui.titleBarRightHeader.children.clear()
            ui.navigationView.menuItems.clear()
            ui.navigationView.footerMenuItems.clear()
            let context = self.context
            for module in App.context.modules {
                if let item = module.titleBarRightHeaderItem(in: context) {
                    ui.titleBarRightHeader.children.append(item)
                }
                for item in module.navigationViewMenuItems(in: context) {
                    ui.navigationView.menuItems.append(item)
                }
                for item in module.navigationViewFooterMenuItems(in: context) {
                    ui.navigationView.footerMenuItems.append(item)
                }
            }
            self.pageControl.updateAppearance()

            if let page = pageControl.currentPage {
                ui.navigationView.selectItem(with: page.url)
            }
        }
        fullscreenChanged.addHandler { [weak self] _, arg in
            self?.pageControl.updateFullscreen(arg)
        }

        ui.navigationView.itemInvoked.addHandler { [weak self] _, arg in
            guard let self, let arg, let url = resolveURL(for: arg) else { return }

            let ctrlState =
                (try? InputKeyboardSource.getKeyStateForCurrentThread(VirtualKey.control)) ?? .none
            let ctrlDown =
                ctrlState.rawValue & CoreVirtualKeyStates.down.rawValue
                == CoreVirtualKeyStates.down.rawValue
            guard ctrlDown || url != pageControl.currentPage?.url else { return }

            Task { @MainActor [weak self] in
                _ = self?.navigate(to: url, mode: ctrlDown ? .newTabNoFocus : .inplace)
            }
        }
        ui.backButton.click.addHandler { [weak self] _, _ in
            self?.pageControl.goBack()
        }
        ui.forwardButton.click.addHandler { [weak self] _, _ in
            self?.pageControl.goForward()
        }

        bindPageControlEvents()
    }

    private func bindPageControlEvents() {
        // PageTabView 自管 strip：selectionChanged / tabCloseRequested / addTabButtonClick
        // 已在控件内部 wire。宿主只需挂 onPageChanged / onCleared 同步 NavView 选中 +
        // 写 lastPageURL + 刷新 back/forward 按钮态，替代旧 renderSelectedTab 末尾刷新。
        pageControl.onPageChanged = { [weak self] _, _, page in
            guard let self else { return }
            self.ui.navigationView.header = nil
            self.ui.navigationView.selectItem(with: page.url)
            self.ui.backButton.isEnabled = self.pageControl.canGoBack
            self.ui.forwardButton.isEnabled = self.pageControl.canGoForward
            App.context.route.lastPageURL = page.url
        }
        pageControl.onCleared = { [weak self] _, _ in
            guard let self else { return }
            self.ui.navigationView.header = nil
            self.ui.backButton.isEnabled = false
            self.ui.forwardButton.isEnabled = false
        }

        // strip "+" 的 page 来源：返回首个 NavView 项的 URL，否则 Settings。
        pageControl.setAddTabProvider { [weak self] in
            guard let self else { return (SettingsPage(), tr("Settings")) }
            if let url = self.firstNavigationItemURL() {
                let page = self.resolvePage(for: url) ?? SettingsPage()
                return (page, page.title)
            }
            return (SettingsPage(), tr("Settings"))
        }
    }

    func enterPageFullscreen() {
        enterFullscreen(for: pageControl.pageView)
    }

    // MARK: - Tab accessors

    var selectedTabContext: PageTabView.TabContext? { pageControl.selectedTabContext }
    var selectedTabModel: MainWindowTab? { pageControl.selectedTabModel }
    var currentPage: Page? { pageControl.currentPage }
    var tabCount: Int { pageControl.tabCount }
    var orderedTabContexts: [PageTabView.TabContext] { pageControl.orderedTabContexts }

    // True once the window has no tabs, or after teardown nilled the viewModel.
    var hasNoTabs: Bool { pageControl.tabCount == 0 }

    func context(for model: MainWindowTab) -> PageTabView.TabContext? {
        pageControl.orderedTabContexts.first { $0.model === model }
    }

    // MARK: - Tab lifecycle

    /// 新建一个 tab 并（默认）切过去。WindowContext.open / 模块路由的 newTab /
    /// newTabBackground 共用本入口。`switchToTab=false` 用于背景加 tab；背景 tab 的
    /// 渲染由 `PageTabView` 延迟到首次选中时触发，匹配原 frame-per-tab 的批处理语义。
    @discardableResult
    func addTab(
        page: Page,
        at index: Int? = nil,
        switchToTab: Bool = true,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> PageTabView.TabContext {
        pageControl.addTab(
            page: page,
            header: page.title,
            transitionInfoOverride: transitionInfoOverride,
            at: index,
            switchToTab: switchToTab
        )
    }

    /// 批量加 tab：循环 `addTab`、只切一次选中。`PageTabView.addTab` 自带单 tab 自动
    /// Suppress + strip 可见性刷新，整体 O(N)；最后一次性落地选中（与原 addTabs 同）。
    @discardableResult
    func addTabs(
        pages: [Page],
        switchToLast: Bool = true,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> [PageTabView.TabContext] {
        guard !pages.isEmpty else { return [] }
        let hadSelection = selectedTabContext != nil

        var contexts: [PageTabView.TabContext] = []
        contexts.reserveCapacity(pages.count)
        for page in pages {
            // 背景 add：switchToTab=false，让最后一个再统一选中。
            let ctx = pageControl.addTab(
                page: page,
                header: page.title,
                transitionInfoOverride: transitionInfoOverride,
                at: nil,
                switchToTab: false
            )
            contexts.append(ctx)
        }

        // Mirror the looped-addTab selection: foreground lands on the last tab;
        // a background batch into an empty window still needs a selection, so it
        // lands on the first; an existing selection is otherwise preserved.
        let selection: PageTabView.TabContext?
        if switchToLast {
            selection = contexts.last
        } else if !hadSelection {
            selection = contexts.first
        } else {
            selection = nil
        }
        if let selection {
            pageControl.selectTab(selection)
        }
        return contexts
    }

    func closeTab(for item: TabViewItem) {
        guard
            let ctx = pageControl.orderedTabContexts.first(where: { $0.item === item })
                ?? {
                    // WinRT identity unstable：再按 name 兜一次。
                    pageControl.orderedTabContexts.first { $0.item.name == item.name }
                }()
        else { return }
        pageControl.closeTab(ctx)
    }

    func closeOtherTabs() {
        pageControl.closeOtherTabs()
    }

    func focusTab(matchingURL url: URL) -> Bool {
        guard let ctx = findTabContext(matchingURL: url) else { return false }
        pageControl.selectTab(ctx)
        return true
    }

    func findTabContext(matchingURL url: URL) -> PageTabView.TabContext? {
        pageControl.orderedTabContexts.first { $0.model.currentPage?.url == url }
    }

    func openNewTabFromTabStrip() {
        if let url = firstNavigationItemURL() {
            _ = navigate(
                to: url, mode: .newTab, transitionInfoOverride: SuppressNavigationTransitionInfo())
        } else {
            navigate(
                to: SettingsPage(), mode: .newTab,
                transitionInfoOverride: SuppressNavigationTransitionInfo())
        }
    }

    // MARK: - Navigation

    func navigate(
        to page: Page,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) {
        performNavigate(to: page, mode: mode, transitionInfoOverride: transitionInfoOverride)
    }

    @discardableResult
    func navigate(
        to url: URL,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> Bool {
        return performNavigate(
            to: url, mode: mode, transitionInfoOverride: transitionInfoOverride)
    }

    private func performNavigate(
        to page: Page,
        mode: NavigationOpenMode,
        transitionInfoOverride: NavigationTransitionInfo?
    ) {
        switch mode {
        case .inplace:
            navigateInSelectedTab(to: page, transitionInfoOverride: transitionInfoOverride)
        case .newTab:
            addTab(page: page, switchToTab: true, transitionInfoOverride: transitionInfoOverride)
        case .newTabNoFocus:
            addTab(page: page, switchToTab: false, transitionInfoOverride: transitionInfoOverride)
        }
    }

    // In-place navigation: push onto the selected tab's history via PageControl
    // 协议（mutate + 即时渲染）。无 tab 时（首次导航 / restore）开一个新 tab。
    private func navigateInSelectedTab(
        to page: Page,
        transitionInfoOverride: NavigationTransitionInfo?
    ) {
        guard selectedTabContext != nil else {
            addTab(page: page, switchToTab: true, transitionInfoOverride: transitionInfoOverride)
            return
        }
        pageControl.navigateCurrent(to: page, transitionInfoOverride: transitionInfoOverride)
    }

    @discardableResult
    private func performNavigate(
        to url: URL,
        mode: NavigationOpenMode,
        transitionInfoOverride: NavigationTransitionInfo?
    ) -> Bool {
        // 仅在 inplace 模式下短路；其他模式（newTab / newTabBackground）允许重复打开同 URL
        if mode == .inplace, currentPage?.url == url {
            return true
        }

        guard let page = resolvePage(for: url) else { return false }
        performNavigate(to: page, mode: mode, transitionInfoOverride: transitionInfoOverride)
        return true
    }

    // Resolves a route URL to a Page via Settings or a registered module, without
    // performing any navigation. Returns nil when no module claims the URL.
    func resolvePage(for url: URL) -> Page? {
        if url == SettingsPage.url {
            return SettingsPage()
        }
        let context = WindowContext(owner: self)
        for module in App.context.modules {
            if let page = module.onNavigationRequested(for: url, in: context) {
                return page
            }
        }
        return nil
    }

    func firstNavigationItemURL() -> URL? {
        return firstNavigationItemURL(in: ui.navigationView.menuItems)
            ?? firstNavigationItemURL(in: ui.navigationView.footerMenuItems)
    }

    private func firstNavigationItemURL(in items: AnyIVector<Any?>?) -> URL? {
        guard let items else { return nil }

        for item in items {
            guard let navItem = item as? NavigationViewItem else { continue }
            if let tag = navItem.tag,
                let str = tag as? HString,
                let url = URL(string: String(hString: str))
            {
                return url
            }
            if let url = firstNavigationItemURL(in: navItem.menuItems) {
                return url
            }
        }

        return nil
    }

    private func url(for item: NavigationViewItemBase) -> URL? {
        guard
            let navItem = item as? NavigationViewItem,
            let tag = navItem.tag,
            let str = tag as? HString
        else {
            return nil
        }

        return URL(string: String(hString: str))
    }

    private func resolveURL(for arg: NavigationViewItemInvokedEventArgs) -> URL? {
        if arg.isSettingsInvoked {
            return SettingsPage.url
        } else if let item = arg.invokedItemContainer,
            let tag = item.tag,
            let str = tag as? HString
        {
            return URL(string: String(hString: str))
        }

        return nil
    }

    // MARK: - Strip primitives (match items by stable name, not by ===)

    /// strip 顺序中按 name 找 index；tear-out 合并 / detach 用到。WinRT 投影 `===` 不
    /// 稳，故按 name。
    func indexOfItem(name: String) -> Int? {
        guard let items = pageControl.tearOutTabView.tabItems else { return nil }
        var i: UInt32 = 0
        while i < items.size {
            if let it = items.getAt(i) as? TabViewItem, it.name == name {
                return Int(i)
            }
            i += 1
        }
        return nil
    }
}
