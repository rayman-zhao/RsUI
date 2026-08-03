import Foundation
import Observation
import UWP
import WinAppSDK
import WinUI
import WindowsFoundation

private func tr(_ keyAndValue: String) -> String {
    return App.context.tr(keyAndValue)
}

/// 主窗口壳：`NavigationViewWindow` 的子类，承载侧栏 + 标题栏 + 一个 `PageTabView`
/// 作为内容容器（共享单 `PageFrame` + WinUI `TabView` strip）。
///
/// 本类按 AGENTS.md "Core UI Composition Model" §5 第三态装配：内容区直接挂
/// `pageTabView`（其自身是 Grid：Row0 = tab strip，Row1 = 共享 frame），故单 tab 时
/// strip 自动隐藏、窗口看起来就是一个普通 PageFrame；多 tab 恢复 strip。Tab 生命周期
/// / strip 行为 / 可见性切换 / closable 状态 / 标题同步全部由 `PageTabView` 自管，本类
/// 只持有控件 + 通过 `PageControl` 协议多态驱动（inplace back/forward/pushPage）+ 暴露
/// `WindowContext` 所需的 tab 操作入口。
class MainWindow: NavigationViewWindow {
    // MARK: - Properties

    var viewModel: MainWindowViewModel! = MainWindowViewModel()
    // NavView 程序化选中时挂起 selectionChanged，避免递归。（TabView strip 由
    // PageTabView 自管同步，本类不再持有 isSyncingTabSelection。）
    var isSyncingSelection = false

    // When true, launch skips currentPage/lastPageURL restore and selects the
    // first NavigationView item instead.
    var forceHomeOnLaunch: Bool = false

    var openInNewTabRequested: Bool = false
    var initialNavigationURL: URL? = nil
    var initialPageFactory: ((WindowContext) -> Page)? = nil
    var initialNavigationTransitionInfoOverride: NavigationTransitionInfo? = nil

    // MARK: - Tab container

    /// 唯一的 tab 容器：共享单 `PageFrame` + WinUI `TabView` strip 的组合控件。
    /// `bootstrap()` 之前建好（`ui.navigationView.content` 赋值必须先有它），
    /// `maxHistoryPages` 取自 `viewModel.routePreferences.maxHistoryPages`。
    private(set) lazy var pageTabView: PageTabView = PageTabView(
        maxHistoryPages: viewModel.routePreferences.maxHistoryPages
    )

    // MARK: - Init

    init() {
        super.init()
        useMicaBackdrop()
        useRestoration()
        bootstrap()
    }

    // setupContent 会触发 navigationView lazy var 求值，必须在那之前赋值。
    // 用 init 参数承接，否则 openDetachedWindow 在 MainWindow() 返回后再赋值就晚了。
    init(initialNavigationViewPaneOpen: Bool?, suppressLayoutPersistence: Bool) {
        super.init(initialNavigationViewPaneOpen!)
        useMicaBackdrop()
        useRestoration()
        bootstrap()
    }

    init(forceHomeOnLaunch: Bool) {
        super.init()
        useMicaBackdrop()
        useRestoration()
        self.forceHomeOnLaunch = forceHomeOnLaunch
        bootstrap()
    }

    private func bootstrap() {
        ui.navigationView.content = pageTabView

        setupContent()
        bindEvents()
    }

    // MARK: - Lifecycle & events

    private func setupContent() {
        configureNavigationViewSelection()
        configureTabViewEvents()
    }

    private func configureNavigationViewSelection() {
        ui.navigationView.selectionChanged.addHandler { [weak self] _, args in
            guard let self, let args, !self.isSyncingSelection else { return }

            if args.isSettingsSelected {
                navigate(
                    to: SettingsPage(), transitionInfoOverride: SuppressNavigationTransitionInfo())
            } else if let item = args.selectedItem as? NavigationViewItem,
                let tag = item.tag,
                let str = tag as? HString,
                let url = URL(string: String(hString: str))
            {
                _ = navigate(to: url, transitionInfoOverride: SuppressNavigationTransitionInfo())
            }
        }
    }

    private func configureTabViewEvents() {
        // PageTabView 自管 strip：selectionChanged / tabCloseRequested / addTabButtonClick
        // 已在控件内部 wire。宿主只需挂 onPageChanged / onCleared 同步 NavView 选中 +
        // 写 lastPageURL + 刷新 back/forward 按钮态，替代旧 renderSelectedTab 末尾刷新。
        pageTabView.onPageChanged = { [weak self] _, _, page in
            guard let self, self.viewModel != nil else { return }
            self.ui.navigationView.header = nil
            self.syncNavigationSelection(for: page.url)
            self.ui.backButton.isEnabled = self.pageTabView.canGoBack
            self.ui.forwardButton.isEnabled = self.pageTabView.canGoForward
            self.viewModel.routePreferences.lastPageURL = page.url
        }
        pageTabView.onCleared = { [weak self] _, _ in
            guard let self, self.viewModel != nil else { return }
            self.ui.navigationView.header = nil
            self.ui.backButton.isEnabled = false
            self.ui.forwardButton.isEnabled = false
        }

        // strip "+" 的 page 来源：返回首个 NavView 项的 URL，否则 Settings。
        pageTabView.setAddTabProvider { [weak self] in
            guard let self else { return (SettingsPage(), tr("Settings")) }
            if let url = self.firstNavigationItemURL() {
                let page = self.resolvePage(for: url) ?? SettingsPage()
                return (page, page.title)
            }
            return (SettingsPage(), tr("Settings"))
        }
    }

    private func bindEvents() {
        self.appearanceChanged.addHandler { [weak self] _ in
            guard let self else { return }
            // PageTabView 内部的 closeOthers tooltip 在语言切换后由它自己再应用。
            self.pageTabView.reapplyCloseOthersTooltip()

            let context = WindowContext(owner: self)
            ui.titleBarRightHeader.children.clear()
            ui.navigationView.menuItems.clear()
            ui.navigationView.footerMenuItems.clear()
            for module in App.context.modules {
                if let item = module.titleBarRightHeaderItem(in: context) {
                    ui.titleBarRightHeader.children.append(item)
                }
                for item in module.navigationViewMenuItems(in: context) {
                    appendNavigationItem(item, false)
                }
                for item in module.navigationViewFooterMenuItems(in: context) {
                    appendNavigationItem(item, true)
                }
            }

            if let makeInitialPage = initialPageFactory {
                initialPageFactory = nil
                let transitionInfoOverride =
                    initialNavigationTransitionInfoOverride ?? SuppressNavigationTransitionInfo()
                initialNavigationTransitionInfoOverride = nil
                navigate(
                    to: makeInitialPage(context), transitionInfoOverride: transitionInfoOverride)
                return
            }

            if let url = initialNavigationURL {
                initialNavigationURL = nil
                let transitionInfoOverride =
                    initialNavigationTransitionInfoOverride ?? SuppressNavigationTransitionInfo()
                initialNavigationTransitionInfoOverride = nil
                _ = navigate(to: url, transitionInfoOverride: transitionInfoOverride)
                return
            }

            // Taskbar "New Window" / --new-window: skip currentPage/lastPageURL,
            // force-select the first NavigationView item (Home) without polluting
            // routePreferences.
            if forceHomeOnLaunch {
                forceHomeOnLaunch = false
                ui.navigationView.selectFirstItem()
                return
            }

            if let page = currentPage {
                navigate(to: page)
            } else if let lastURL = viewModel.routePreferences.lastPageURL, navigate(to: lastURL) {
                return
            } else {
                ui.navigationView.selectFirstItem()
            }
        }

        ui.backButton.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.pageTabView.goBack()
        }
        ui.forwardButton.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.pageTabView.goForward()
        }
        fullscreenChanged.addHandler { _ in
            // Fullscreen lifecycle hook: reserved for future "broadcast window
            // context to all pages of the selected tab" work. The old frame-per-tab
            // implementation had this commented-out body too; kept as a no-op for
            // API/observer continuity.
        }
    }

    // MARK: - Tab accessors

    var selectedTabContext: PageTabView.TabContext? { pageTabView.selectedTabContext }
    var selectedTabModel: MainWindowTab? { pageTabView.selectedTabModel }
    var currentPage: Page? { pageTabView.currentPage }
    var tabCount: Int { pageTabView.tabCount }
    var orderedTabContexts: [PageTabView.TabContext] { pageTabView.orderedTabContexts }

    // True once the window has no tabs, or after teardown nilled the viewModel.
    var hasNoTabs: Bool { viewModel == nil || pageTabView.tabCount == 0 }

    func context(for model: MainWindowTab) -> PageTabView.TabContext? {
        pageTabView.orderedTabContexts.first { $0.model === model }
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
        pageTabView.addTab(
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
            let ctx = pageTabView.addTab(
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
            pageTabView.selectTab(selection)
        }
        return contexts
    }

    func closeTab(for item: TabViewItem) {
        guard
            let ctx = pageTabView.orderedTabContexts.first(where: { $0.item === item })
                ?? {
                    // WinRT identity unstable：再按 name 兜一次。
                    pageTabView.orderedTabContexts.first { $0.item.name == item.name }
                }()
        else { return }
        pageTabView.closeTab(ctx)
    }

    func closeOtherTabs() {
        pageTabView.closeOtherTabs()
    }

    func focusTab(matchingURL url: URL) -> Bool {
        guard let ctx = findTabContext(matchingURL: url) else { return false }
        pageTabView.selectTab(ctx)
        return true
    }

    func findTabContext(matchingURL url: URL) -> PageTabView.TabContext? {
        pageTabView.orderedTabContexts.first { $0.model.currentPage?.url == url }
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

    // MARK: - Tab Fullscreen
    // Tab 全屏 = 把当前共享 frame（pageTabView.sharedFrame，private）整页铺满窗口。
    // 底层复用父类 `NavigationViewWindow.enterFullscreen(for:)` 的 element-reparent
    // 全屏路径，由 PageTabView 把 sharedFrame detach / reparent 进 FullscreenOverlay；
    // 退出按 detach 时记录的 Row1 索引插回 PageTabView.children。`WindowContext` 的
    // enterTabFullscreen / exitTabFullscreen / isInTabFullscreen 转发到此处。

    func enterTabFullscreen() {
        pageTabView.enterFullscreen(in: self)
    }

    func exitTabFullscreen() {
        pageTabView.exitFullscreen(in: self)
    }

    var isInTabFullscreen: Bool { isInFullscreen }

    // MARK: - Navigation

    func navigate(
        to page: Page,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) {
        let effective = resolveOpenMode(mode)
        performNavigate(to: page, mode: effective, transitionInfoOverride: transitionInfoOverride)
    }

    @discardableResult
    func navigate(
        to url: URL,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> Bool {
        let effective = resolveOpenMode(mode)
        return performNavigate(
            to: url, mode: effective, transitionInfoOverride: transitionInfoOverride)
    }

    /// NavigationViewItem 上 Ctrl+click 设置的 `openInNewTabRequested` 标记会把
    /// `.inplace` 升级为 `.newTab`；调用者显式指定的非 inplace 模式不被覆盖。
    private func resolveOpenMode(_ requested: NavigationOpenMode) -> NavigationOpenMode {
        let flag = openInNewTabRequested
        openInNewTabRequested = false
        if requested == .inplace && flag {
            return .newTab
        }
        return requested
    }

    private func performNavigate(
        to page: Page,
        mode: NavigationOpenMode,
        transitionInfoOverride: NavigationTransitionInfo?
    ) {
        switch mode {
        case .newWindow:
            MainWindow.openDetachedWindow(
                opening: page, transitionInfoOverride: transitionInfoOverride)
        case .inplace:
            navigateInSelectedTab(to: page, transitionInfoOverride: transitionInfoOverride)
        case .newTab:
            addTab(page: page, switchToTab: true, transitionInfoOverride: transitionInfoOverride)
        case .newTabBackground:
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
        pageTabView.navigateCurrent(to: page, transitionInfoOverride: transitionInfoOverride)
    }

    @discardableResult
    private func performNavigate(
        to url: URL,
        mode: NavigationOpenMode,
        transitionInfoOverride: NavigationTransitionInfo?
    ) -> Bool {
        if mode == .newWindow {
            MainWindow.openDetachedWindow(
                navigatingTo: url, transitionInfoOverride: transitionInfoOverride)
            return true
        }
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

    func syncNavigationSelection(for url: URL) {
        // isSyncingSelection = true
        // defer { isSyncingSelection = false }

        ui.navigationView.selectItem(with: url)
    }

    private func captureOpenInNewTabRequested(_ args: PointerRoutedEventArgs?) {
        guard let args = args else { return }
        let rawValue = Int(args.keyModifiers.rawValue)
        openInNewTabRequested = (rawValue & 0x1) != 0
    }

    func appendNavigationItem(_ item: NavigationViewItemBase, _ isFooter: Bool) {
        item.pointerPressed.addHandler { [weak self, weak item] _, args in
            guard let self else { return }
            self.captureOpenInNewTabRequested(args)
            guard self.openInNewTabRequested, let item else { return }
            self.openSelectedNavigationItemInNewTabIfNeeded(item, args)
        }
        if isFooter {
            ui.navigationView.footerMenuItems.append(item)
        } else {
            ui.navigationView.menuItems.append(item)
        }
    }

    private func openSelectedNavigationItemInNewTabIfNeeded(
        _ item: NavigationViewItemBase, _ args: PointerRoutedEventArgs?
    ) {
        guard isNavigationItemSelected(item), let url = url(for: item) else { return }

        args?.handled = true
        openInNewTabRequested = false

        let queued =
            (try? dispatcherQueue?.tryEnqueue { [weak self] in
                guard let self else { return }
                _ = self.navigate(
                    to: url,
                    mode: .newTab,
                    transitionInfoOverride: SuppressNavigationTransitionInfo()
                )
            }) ?? false

        if !queued {
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = self.navigate(
                    to: url,
                    mode: .newTab,
                    transitionInfoOverride: SuppressNavigationTransitionInfo()
                )
            }
        }
    }

    private func isNavigationItemSelected(_ item: NavigationViewItemBase) -> Bool {
        guard let selectedItem = ui.navigationView.selectedItem as? NavigationViewItemBase else {
            return false
        }
        return selectedItem === item
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

    // MARK: - Strip primitives (match items by stable name, not by ===)

    /// strip 顺序中按 name 找 index；tear-out 合并 / detach 用到。WinRT 投影 `===` 不
    /// 稳，故按 name。
    func indexOfItem(name: String) -> Int? {
        guard let items = pageTabView.tearOutTabView.tabItems else { return nil }
        var i: UInt32 = 0
        while i < items.size {
            if let it = items.getAt(i) as? TabViewItem, it.name == name {
                return Int(i)
            }
            i += 1
        }
        return nil
    }

    // MARK: - Window factory

    static func openDetachedWindow(
        navigatingTo url: URL,
        transitionInfoOverride: NavigationTransitionInfo? = nil,
        collapseNavigationPane: Bool = false
    ) {
        // 一次性 viewer 窗口：初始折叠 NavPane，且不把折叠状态回写到全局 windowLayout。
        // 必须经 init 参数路径，因为 setupContent 一旦跑完 lazy navigationView 就定型了。
        let window =
            collapseNavigationPane
            ? MainWindow(initialNavigationViewPaneOpen: false, suppressLayoutPersistence: true)
            : MainWindow()
        window.initialNavigationURL = url
        window.initialNavigationTransitionInfoOverride = transitionInfoOverride
        try? window.activate()
    }

    static func openDetachedWindow(
        opening page: Page,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) {
        openDetachedWindow(transitionInfoOverride: transitionInfoOverride) { _ in page }
    }

    static func openDetachedWindow(
        transitionInfoOverride: NavigationTransitionInfo? = nil,
        makePage: @escaping (WindowContext) -> Page
    ) {
        let window = MainWindow()
        window.initialPageFactory = makePage
        window.initialNavigationTransitionInfoOverride = transitionInfoOverride
        try? window.activate()
    }

    // Opens a new top-level window in-process showing Home, skipping last-view
    // restore. The taskbar "New Window" reaches this after being redirected to
    // the primary instance.
    static func openDetachedWindowAtHome() {
        let window = MainWindow(forceHomeOnLaunch: true)
        try? window.activate()
    }
}
