import Foundation
import Observation
import WindowsFoundation
import UWP
import WinAppSDK
import WinUI

class MainWindow: Window {
    // MARK: - 属性
    var viewModel: MainWindowViewModel! = MainWindowViewModel()
    var isSyncingSelection = false
    var isSyncingTabSelection = false

    // Splitter state
    var splitterBorder: Border!
    var isDraggingSplitter = false
    var dragStartX: Double = 0
    var dragStartPaneLength: Double = 0
    let splitterWidth: Double = 6

    var openInNewTabRequested: Bool = false
    var initialNavigationURL: URL? = nil
    var initialPageFactory: ((WindowContext) -> Page)? = nil
    var initialNavigationTransitionInfoOverride: NavigationTransitionInfo? = nil
    // nil → 使用 windowLayout 中持久化的 NavPane 状态；否则强制覆盖初始展开/折叠
    var initialNavigationViewPaneOpen: Bool? = nil
    // true → 关窗时不把本窗口的 NavPane 状态写回全局 windowLayout，
    // 避免一次性 viewer 窗口污染主窗口的下次启动状态
    var suppressLayoutPersistence: Bool = false
    // When true, launch skips currentPage/lastPageURL restore and selects the
    // first NavigationView item instead.
    var forceHomeOnLaunch: Bool = false
    // An empty window created to receive a tab torn out into a new window. It
    // comes up with no tab (startup navigation is skipped) and waits for
    // tabTearOutRequested to inject the torn tab; it also skips position restore.
    var awaitTransferredTab: Bool = false
    var isTearOutWindow: Bool = false

    // Keep native TabView tear-out disabled for now. CanTearOutTabs currently
    // has two blocking issues for this shell:
    // - TabTearOutWindowRequested can make the receiver window visible briefly,
    //   causing flicker and taskbar animation.
    //   https://github.com/microsoft/microsoft-ui-xaml/issues/10155
    // - With a custom title bar, switching tabs can corrupt the drag region so
    //   dragging the title bar tears out a tab instead of moving the window.
    //   https://github.com/microsoft/microsoft-ui-xaml/issues/11170
    // Keep the tear-out handlers behind this same gate so the native path can
    // be restored when the WinUI behavior is fixed.
    static let tabTearOutEnabled = false
    
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

    // 持有 Observation Task 句柄，窗口关闭时 cancel，避免死窗口的 task 继续访问失效的 self.appWindow / self.viewModel
    var envObservationTask: Task<Void, Never>?
    var isApplyingAppearance = false

    // 全屏时整体 collapse，含 NavigationView + Splitter
    var navWrapper: Grid?
    // 全屏时挂到 root 的临时 overlay，退出时需摘除
    var fullscreenOverlay: Border?
    // reparent 出去的 frame，退出时挂回 tabContentHost
    var fullscreenStashedFrame: PageTransitionHost?
    var isInTabFullscreen = false
    // setPresenter(.overlapped) 退出时不还原 maximize
    var preFullscreenMaximized = false

    /// UI 主要组件
    static func tr(_ keyAndValue: String) -> String {
        return App.context.tr(keyAndValue)
    }

    private static func makeNavButton(glyph: String, action: @escaping () -> Void) -> Button {
        let icon = FontIcon()
        icon.glyph = glyph
        icon.fontSize = 12
        let btn = Button()
        btn.content = icon
        btn.width = 28
        btn.height = 28
        btn.minWidth = 0
        btn.minHeight = 0
        btn.verticalAlignment = .center
        btn.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        btn.isEnabled = false
        btn.allowFocusOnInteraction = false

        let transparent = SolidColorBrush(Colors.transparent)
        let hoverBrush = SolidColorBrush(UWP.Color(a: 0x18, r: 0x80, g: 0x80, b: 0x80))
        let pressedBrush = SolidColorBrush(UWP.Color(a: 0x30, r: 0x80, g: 0x80, b: 0x80))
        for key in ["ButtonBackground", "ButtonBackgroundDisabled"] {
            _ = btn.resources.insert(key, transparent)
        }
        _ = btn.resources.insert("ButtonBackgroundPointerOver", hoverBrush)
        _ = btn.resources.insert("ButtonBackgroundPressed", pressedBrush)
        for key in ["ButtonBorderBrush", "ButtonBorderBrushPointerOver",
                     "ButtonBorderBrushPressed", "ButtonBorderBrushDisabled"] {
            _ = btn.resources.insert(key, transparent)
        }

        btn.click.addHandler { _, _ in action() }
        return btn
    }

    lazy var backButton: Button = MainWindow.makeNavButton(glyph: "\u{E72B}") { [weak self] in
        self?.goBack(MainWindow.makeSlideTransition(effect: .fromLeft))
    }
    lazy var forwardButton: Button = MainWindow.makeNavButton(glyph: "\u{E72A}") { [weak self] in
        self?.goForward(MainWindow.makeSlideTransition(effect: .fromRight))
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
        for key in ["ButtonBorderBrush", "ButtonBorderBrushPointerOver",
                    "ButtonBorderBrushPressed", "ButtonBorderBrushDisabled"] {
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

    lazy var searchBox: AutoSuggestBox? = {
        // let box = AutoSuggestBox()
        // box.width = 360
        // box.height = 32
        // box.minWidth = 280
        // box.verticalAlignment = .center
        // return box
        return nil
    } ()
    lazy var titleBarRightHeader = {
        let panel = StackPanel()
        panel.orientation = .horizontal
        return panel
    } ()
    lazy var titleBar = {
        let bar = TitleBar()
        bar.height = 48
        bar.isBackButtonVisible = false
        bar.isPaneToggleButtonVisible = true

        if let iconPath = App.context.iconPath {
            let bitmap = BitmapImage()
            bitmap.uriSource = Uri(iconPath)

            let iconSource = ImageIconSource()
            iconSource.imageSource = bitmap
            bar.iconSource = iconSource
        }

        let barContentStackPanel = StackPanel()
        barContentStackPanel.orientation = .horizontal
        barContentStackPanel.spacing = 20
        let navButtons = StackPanel()
        navButtons.orientation = .horizontal
        navButtons.spacing = 2
        navButtons.children.append(self.backButton)
        navButtons.children.append(self.forwardButton)
        barContentStackPanel.children.append(navButtons)
        bar.content = barContentStackPanel

        if let searchBox {
            barContentStackPanel.children.append(searchBox)
        }

        bar.rightHeader = titleBarRightHeader

        bar.paneToggleRequested.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.navigationView.isPaneOpen.toggle()
        }

        return bar
    } ()
    lazy var tabView: TabView = {
        let tabs = TabView()
        tabs.isAddTabButtonVisible = true
        tabs.tabWidthMode = .equal
        tabs.closeButtonOverlayMode = .onPointerOver
        tabs.tabStripHeader = closeOtherTabsButton
        tabs.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        tabs.margin = Thickness(left: 0, top: -1, right: 0, bottom: 0)
        tabs.canDragTabs = true
        tabs.canReorderTabs = true
        // Mirrors tabTearOutEnabled; see the flag comment for why native
        // tear-out is currently off.
        tabs.canTearOutTabs = MainWindow.tabTearOutEnabled
        return tabs
    } ()
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
    } ()
    // TabView owns the tab strip — order, selection, add/remove/reorder all live
    // in tabView.tabItems. Each strip item is bridged to its navigation model and
    // content frame by a TabContext, keyed by the item's stable `name` (WinRT
    // projection identity for TabViewItem is unstable, so items are matched by
    // name, never by ===).
    var tabContextsByName: [String: TabContext] = [:]
    // Caches the visible tab frame to avoid reapplying visibility on every render.
    var visibleTabFrameName: String?
    var isFirstNavigation = true
    lazy var navigationView = {
        let nav = NavigationView()
        nav.paneDisplayMode = .left
        nav.isSettingsVisible = true
        nav.isBackButtonVisible = .collapsed
        nav.isPaneToggleButtonVisible = false
        nav.paneDisplayMode = .auto

        let length = viewModel.windowLayout.navigationViewOpenPaneLength
        nav.compactModeThresholdWidth = 0
        nav.expandedModeThresholdWidth = length + viewModel.windowLayout.navigationViewExpandedModeThresholdContentWidth
        nav.isPaneOpen = initialNavigationViewPaneOpen ?? viewModel.windowLayout.navigationViewPaneOpen
        nav.openPaneLength = length
        nav.isTitleBarAutoPaddingEnabled = false
        nav.content = navigationContentRoot

        return nav
    } ()

    // MARK: - 初始化
    override init() {
        super.init()
        bootstrap()
    }

    // setupContent 会触发 navigationView lazy var 求值，必须在那之前赋值。
    // 用 init 参数承接，否则 openDetachedWindow 在 MainWindow() 返回后再赋值就晚了。
    init(initialNavigationViewPaneOpen: Bool?, suppressLayoutPersistence: Bool) {
        super.init()
        self.initialNavigationViewPaneOpen = initialNavigationViewPaneOpen
        self.suppressLayoutPersistence = suppressLayoutPersistence
        bootstrap()
    }

    init(forceHomeOnLaunch: Bool) {
        super.init()
        self.forceHomeOnLaunch = forceHomeOnLaunch
        bootstrap()
    }

    // Empty receiver window for a tear-out. Comes up with no tab and skips
    // position restore; the torn tab is injected by tabTearOutRequested.
    init(tearOutReceiver: Bool) {
        super.init()
        self.awaitTransferredTab = tearOutReceiver
        self.isTearOutWindow = tearOutReceiver
        bootstrap()
    }

    private func bootstrap() {
        setupWindow()
        setupContent()
        startObserving()
    }

    private static func makeSlideTransition(effect: SlideNavigationTransitionEffect) -> NavigationTransitionInfo {
        let transition = SlideNavigationTransitionInfo()
        transition.effect = effect
        return transition
    }
}
