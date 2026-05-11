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
    var tabDragHintBorder: Border? = nil
    var draggingTabForDrop: MainWindowTab? = nil
    var dragDroppedOutside = false

    struct DragState {
        let sourceWindowID: ObjectIdentifier
        let tabURL: URL
    }
    static var activeDrag: DragState? = nil

    // 持有 Observation Task 句柄，窗口关闭时 cancel，避免死窗口的 task 继续访问失效的 self.appWindow / self.viewModel
    var envObservationTask: Task<Void, Never>?
    var routeObservationTask: Task<Void, Never>?
    var isApplyingAppearance = false

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
        guard let self else { return }
        self.viewModel.goBack(MainWindow.makeSlideTransition(effect: .fromLeft))
        self.renderSelectedTab()
    }
    lazy var forwardButton: Button = MainWindow.makeNavButton(glyph: "\u{E72A}") { [weak self] in
        guard let self else { return }
        self.viewModel.goForward(MainWindow.makeSlideTransition(effect: .fromRight))
        self.renderSelectedTab()
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
        let toolTip = ToolTip()
        toolTip.content = MainWindow.tr("关闭其他标签")
        try? ToolTipService.setToolTip(btn, toolTip)
        return btn
    }()
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
        tabs.allowDrop = true
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
    var tabItemsByID: [ObjectIdentifier: TabViewItem] = [:]
    // Stable string name keyed to tab identity — avoids WinRT projection object identity instability
    var tabIDByName: [String: ObjectIdentifier] = [:]
    var tabFramesByID: [ObjectIdentifier: PageTransitionHost] = [:]
    var tabPageViewPartsByID: [ObjectIdentifier: PageViewParts] = [:]
    var tabStripIDs: [ObjectIdentifier] = []
    var tabTitlesByID: [ObjectIdentifier: String] = [:]
    var tabClosableByID: [ObjectIdentifier: Bool] = [:]
    var visibleTabFrameID: ObjectIdentifier?
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
        nav.isPaneOpen = viewModel.windowLayout.navigationViewPaneOpen
        nav.openPaneLength = length
        nav.isTitleBarAutoPaddingEnabled = false
        nav.content = navigationContentRoot

        return nav
    } ()

    // MARK: - 初始化
    override init() {
        super.init()

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
