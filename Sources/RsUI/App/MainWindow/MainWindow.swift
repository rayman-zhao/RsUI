import Foundation
import Observation
import UWP
import WinAppSDK
import WinUI
import WindowsFoundation

class MainWindow: NavigationViewWindow {
    // MARK: - 属性
    var viewModel: MainWindowViewModel! = MainWindowViewModel()
    var isSyncingSelection = false
    var isSyncingTabSelection = false

    var openInNewTabRequested: Bool = false
    var initialNavigationURL: URL? = nil
    var initialPageFactory: ((WindowContext) -> Page)? = nil
    var initialNavigationTransitionInfoOverride: NavigationTransitionInfo? = nil

    // When true, launch skips currentPage/lastPageURL restore and selects the
    // first NavigationView item instead.
    var forceHomeOnLaunch: Bool = false
    // An empty window created to receive a tab torn out into a new window. It
    // comes up with no tab (startup navigation is skipped) and waits for
    // tabTearOutRequested to inject the torn tab; it also skips position restore.
    var awaitTransferredTab: Bool = false

    // Native tear-out gate moved to PageTabView.tabTearOutEnabled (the single
    // place controlling `canTearOutTabs`). The cross-window tear-out handlers /
    // pending state below remain gated on it; see the comment there for the
    // blocking WinUI bugs.

    // Tracks the single tab being torn out across windows. Drag is single-pointer
    // on the UI thread, so at most one is ever in flight. `holder` follows the tab
    // as it moves between windows during the drag; `receiver` is the floating
    // window the native flow asked us to create.
    // The receiver is resolved from HERE, not from args.newWindowId — that property
    // reads back 0 in the tabTearOutRequested event, so we remember it ourselves.
    struct PendingTearOut {
        let tab: MainWindowTab
        var holder: MainWindow
        let receiver: MainWindow
    }
    static var pendingTearOut: PendingTearOut? = nil
    // Reused so the framework's repeated windowRequested calls within one drag
    // (it over-fires, incl. speculative tears it never commits) don't leak empty
    // windows.
    static var spareReceiver: MainWindow? = nil

    // 全屏时挂到 root 的临时 overlay，退出时需摘除
    var fullscreenOverlay: Border?
    // reparent 出去的 frame，退出时挂回 tabContentHost
    var fullscreenStashedFrame: PageFrame?
    var isInTabFullscreen = false
    // setPresenter(.overlapped) 退出时不还原 maximize
    var preFullscreenMaximized = false

    /// UI 主要组件
    static func tr(_ keyAndValue: String) -> String {
        return App.context.tr(keyAndValue)
    }

    lazy var closeOtherTabsButton: Button = {
        let icon = FontIcon()
        icon.glyph = "\u{F166}"
        icon.fontSize = 12
        let btn = Button()
        btn.content = icon
        btn.minWidth = 0
        btn.minHeight = 0
        // Match TabViewItem: OverlayCornerRadius=8, padding matching TabViewItemHeaderPadding
        btn.cornerRadius = CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
        btn.padding = Thickness(left: 10, top: 0, right: 10, bottom: 0)
        // 4px top/bottom margin to sit within strip like tab items; 2px right keeps it tight to first tab
        btn.margin = Thickness(left: 4, top: 4, right: 2, bottom: 4)
        btn.verticalAlignment = .stretch
        btn.allowFocusOnInteraction = false
        let transparent = SolidColorBrush(Colors.transparent)
        let hoverBrush = SolidColorBrush(UWP.Color(a: 0x18, r: 0x80, g: 0x80, b: 0x80))
        let pressedBrush = SolidColorBrush(UWP.Color(a: 0x30, r: 0x80, g: 0x80, b: 0x80))
        for key in ["ButtonBackground", "ButtonBackgroundDisabled"] {
            _ = btn.resources.insert(key, transparent)
        }
        _ = btn.resources.insert("ButtonBackgroundPointerOver", hoverBrush)
        _ = btn.resources.insert("ButtonBackgroundPressed", pressedBrush)
        for key in [
            "ButtonBorderBrush", "ButtonBorderBrushPointerOver",
            "ButtonBorderBrushPressed", "ButtonBorderBrushDisabled",
        ] {
            _ = btn.resources.insert(key, transparent)
        }
        btn.click.addHandler { [weak self] _, _ in
            self?.closeOtherTabs()
        }
        self.applyCloseOthersTooltip(to: btn)
        return btn
    }()

    // tooltip 在按钮 lazy 求值时定格，语言切换后需重新应用本地化文案
    func applyCloseOthersTooltip(to button: Button) {
        let toolTip = ToolTip()
        toolTip.content = MainWindow.tr("CloseOthers")
        try? ToolTipService.setToolTip(button, toolTip)
    }

    lazy var tabView: TabView = {
        let tabs = TabView()
        tabs.isAddTabButtonVisible = true
        tabs.tabWidthMode = .sizeToContent
        tabs.closeButtonOverlayMode = .onPointerOver
        tabs.tabStripHeader = closeOtherTabsButton
        tabs.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        tabs.margin = Thickness(left: 0, top: -1, right: 0, bottom: 0)
        tabs.canDragTabs = true
        tabs.canReorderTabs = true
        // Mirrors the PageTabView-hosted native tear-out gate; tear-out itself
        // is disabled for now. See PageTabView.tabTearOutEnabled above its
        // inner strip for the WinUI bugs blocking it.
        tabs.canTearOutTabs = PageTabView.tabTearOutEnabled
        return tabs
    }()
    lazy var tabContentHost = Grid()
    lazy var navigationContentRoot: Grid = {
        let grid = Grid()

        let tabRow = RowDefinition()
        tabRow.height = GridLength(value: 1, gridUnitType: .auto)
        let contentRow = RowDefinition()
        contentRow.height = GridLength(value: 1, gridUnitType: .star)
        grid.rowDefinitions.append(tabRow)
        grid.rowDefinitions.append(contentRow)

        grid.children.append(tabView)
        try? Grid.setRow(tabView, 0)

        grid.children.append(tabContentHost)
        try? Grid.setRow(tabContentHost, 1)

        return grid
    }()
    // TabView owns the tab strip — order, selection, add/remove/reorder all live
    // in tabView.tabItems. Each strip item is bridged to its navigation model and
    // content frame by a TabContext, keyed by the item's stable `name` (WinRT
    // projection identity for TabViewItem is unstable, so items are matched by
    // name, never by ===).
    var tabContextsByName: [String: TabContext] = [:]
    // Caches the visible tab frame to avoid reapplying visibility on every render.
    var visibleTabFrameName: String?
    var isFirstNavigation = true

    // MARK: - 初始化
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

    // Empty receiver window for a tear-out. Comes up with no tab and skips
    // position restore; the torn tab is injected by tabTearOutRequested.
    init(tearOutReceiver: Bool) {
        // A tear-out receiver is positioned by the OS as it follows the cursor —
        // don't restore the saved main-window rect over it.
        super.init()
        useMicaBackdrop()
        useRestoration(!tearOutReceiver)
        self.awaitTransferredTab = tearOutReceiver
        bootstrap()
    }

    private func bootstrap() {
        ui.navigationView.content = navigationContentRoot

        setupWindow()
        setupContent()
    }

    override func onGoBack() {
        guard let ctx = selectedTabContext, ctx.frame.canGoBack else { return }
        ctx.frame.goBack()
        renderSelectedTab()
    }

    override func onGoForward() {
        guard let ctx = selectedTabContext, ctx.frame.canGoForward else { return }
        ctx.frame.goForward()
        renderSelectedTab()
    }

    override func onAppearanceChanged() {
        super.onAppearanceChanged()
        /*
        // 死窗口防御：closed handler 把 viewModel 置为 nil，此时 appWindow 也已失效（IUO → nil）
        guard viewModel != nil, appWindow != nil else { return }

        // For min/max/close buttons. 目前不支持材质效果，但比逐个设置按钮颜色简单，并且容易由框架修正。
        self.appWindow.titleBar.preferredTheme = App.context.theme.titleBarTheme

        self.title = MainWindow.tr(App.context.productName)
        titleBar.title = self.title
        searchBox?.placeholderText = MainWindow.tr("searchControlsAndSamples")
        */
        applyCloseOthersTooltip(to: closeOtherTabsButton)

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

        // An empty tear-out receiver: the torn tab is injected later by
        // tabTearOutRequested, so skip all startup navigation and come up blank.
        if awaitTransferredTab {
            return
        }

        if let makeInitialPage = initialPageFactory {
            initialPageFactory = nil
            let transitionInfoOverride = initialNavigationTransitionInfoOverride ?? SuppressNavigationTransitionInfo()
            initialNavigationTransitionInfoOverride = nil
            navigate(to: makeInitialPage(context), transitionInfoOverride: transitionInfoOverride)
            return
        }

        if let url = initialNavigationURL {
            initialNavigationURL = nil
            let transitionInfoOverride = initialNavigationTransitionInfoOverride ?? SuppressNavigationTransitionInfo()
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
}
