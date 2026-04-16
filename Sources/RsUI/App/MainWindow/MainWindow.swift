import Foundation
import Observation
import WindowsFoundation
import UWP
import WinAppSDK
import WinUI
import WinSDK
import RsHelper

fileprivate func tr(_ keyAndValue: String) -> String {
    return App.context.tr(keyAndValue)
}

fileprivate extension WindowPosition {
    var windowRect: RectInt32 {
        return RectInt32(
            x: Int32(windowX),
            y: Int32(windowY),
            width: Int32(windowWidth),
            height: Int32(windowHeight)
        )
    }
}

/// 主窗口类，管理整个应用的导航和 UI 布局
class MainWindow: Window {
    // MARK: - 属性
    private var viewModel: MainWindowViewModel! = MainWindowViewModel()
    private var isSyncingSelection = false

    // Splitter state
    private var splitterBorder: Border!
    private var isDraggingSplitter = false
    private var dragStartX: Double = 0
    private var dragStartPaneLength: Double = 0
    private let splitterWidth: Double = 6

    /// UI 主要组件
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

    private lazy var backButton: Button = MainWindow.makeNavButton(glyph: "\u{E72B}") { [weak self] in
        self?.viewModel.goBack(MainWindow.makeSlideTransition(effect: .fromLeft))
    }
    private lazy var forwardButton: Button = MainWindow.makeNavButton(glyph: "\u{E72A}") { [weak self] in
        self?.viewModel.goForward(MainWindow.makeSlideTransition(effect: .fromRight))
    }
    private lazy var searchBox: AutoSuggestBox? = {
        // let box = AutoSuggestBox()
        // box.width = 360
        // box.height = 32
        // box.minWidth = 280
        // box.verticalAlignment = .center
        // return box
        return nil
    } ()
    private lazy var titleBarRightHeader = {
        let panel = StackPanel()
        panel.orientation = .horizontal
        return panel
    } ()
    private lazy var titleBar = {
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
    private lazy var navigationContentFrame = PageTransitionHost()
    private lazy var navigationView = {
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
        nav.content = navigationContentFrame

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

    func navigate(to page: Page, transitionInfoOverride: NavigationTransitionInfo? = nil) {
        viewModel.navigate(to: page, transitionInfoOverride: transitionInfoOverride)
    }

    func navigate(to url: URL, transitionInfoOverride: NavigationTransitionInfo? = nil) -> Bool {
        if url == SettingsPage.url {
            navigate(to: SettingsPage(), transitionInfoOverride: transitionInfoOverride)
            return true
        } else {
            let context = WindowContext(owner: self)
            for module in App.context.modules {
                if let page = module.navigationRequested(for: url, in: context) {
                    navigate(to: page, transitionInfoOverride: transitionInfoOverride)
                    return true
                }
            }
        }
        return false
    }
 
    /// 配置窗口基本属性
    private func setupWindow() {
        self.extendsContentIntoTitleBar = true
        self.appWindow.titleBar.preferredHeightOption = .tall
                
        // 设置 Mica 背景
        let micaBackdrop = MicaBackdrop()
        micaBackdrop.kind = .base
        self.systemBackdrop = micaBackdrop

        self.sizeChanged.addHandler { [weak self] _, _ in
            self?.trackWindowSize()
        }
        self.closed.addHandler { [weak self] _, _ in
            guard let self else { return }

            // TODO: appWindow.changed事件不工作，此处窗口最大化时记录有缺陷。其实也可以不保存，恢复窗口在中间即可。
            self.trackWindowPosition()
            self.viewModel.windowLayout.navigationViewPaneOpen = self.navigationView.isPaneOpen
            self.viewModel.windowLayout.navigationViewOpenPaneLength = self.navigationView.openPaneLength
            self.viewModel = nil
        }
        restoreWindowRect()
    }

    /// 初始化主要的 UI 布局
    private func setupContent() {
        let root = Grid()

        // 设置行定义
        let titleRowDef = RowDefinition()
        titleRowDef.height = GridLength(value: 1, gridUnitType: .auto)
        root.rowDefinitions.append(titleRowDef)
        
        let contentRowDef = RowDefinition()
        contentRowDef.height = GridLength(value: 1, gridUnitType: .star)
        root.rowDefinitions.append(contentRowDef)
        
        root.children.append(titleBar)
        try? Grid.setRow(titleBar, 0)
        try? setTitleBar(titleBar)
        
        navigationView.selectionChanged.addHandler { [weak self] _, args in
            guard let self, let args, !self.isSyncingSelection else { return }

            if args.isSettingsSelected {
                navigate(to: SettingsPage(), transitionInfoOverride: args.recommendedNavigationTransitionInfo)
            } else if
                let item = args.selectedItem as? NavigationViewItem,
                let tag = item.tag,
                let str = tag as? HString,
                let url = URL(string: String(hString: str)) {
                _ = navigate(to: url, transitionInfoOverride: args.recommendedNavigationTransitionInfo)
            }
        }

        navigationView.paneClosed.addHandler { [weak self] _, _ in
            self?.splitterBorder.visibility = .collapsed
        }
        navigationView.paneOpened.addHandler { [weak self] _, _ in
            self?.splitterBorder.visibility = .visible
        }

        // Wrap NavigationView with splitter overlay
        let navWrapper = Grid()
        navWrapper.children.append(navigationView)
        splitterBorder = makeSplitterBorder()
        navWrapper.children.append(splitterBorder)
        try? Canvas.setZIndex(splitterBorder, 10)

        root.children.append(navWrapper)
        try? Grid.setRow(navWrapper, 1)

        self.content = root
    }

    private func startObserving() { 
        let env = Observations {
            (App.context.theme, App.context.language)
        }
        Task { [weak self] in
            for await _ in env {
                await MainActor.run { [weak self] in
                    self?.applyAppearance()
                }
            }
        }

        let route = Observations {
            self.viewModel.currentPage
        }
        Task { [weak self] in
            for await _ in route {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    
                    if let page = self.viewModel.currentPage {
                        self.navigationView.header = page.header
                        self.navigationContentFrame.transition(
                            to: page.content,
                            transitionInfo: self.viewModel.navigationTransitionInfo
                        )
                        self.syncNavigationSelection(for: page.url)
                    } else {
                        self.navigationView.header = nil
                        self.navigationContentFrame.transition(
                            to: nil,
                            transitionInfo: self.viewModel.navigationTransitionInfo
                        )
                        self.navigationView.selectedItem = nil
                    }
                    
                    self.backButton.isEnabled = !self.viewModel.backwardPages.isEmpty
                    self.forwardButton.isEnabled = !self.viewModel.forwardPages.isEmpty
                }
            }
        }
    }

    private func syncNavigationSelection(for url: URL) {
        isSyncingSelection = true
        defer { isSyncingSelection = false }
        
        navigationView.selectItem(with: url)
    }

    private func applyAppearance() {
        // For min/max/close buttons. 目前不支持材质效果，但比逐个设置按钮颜色简单，并且容易由框架修正。
        self.appWindow.titleBar.preferredTheme = App.context.theme.titleBarTheme

        self.title = tr(App.context.productName)
        titleBar.title = self.title
        searchBox?.placeholderText = tr("searchControlsAndSamples")

        let context = WindowContext(owner: self)
        titleBarRightHeader.children.clear()
        navigationView.menuItems.clear()
        navigationView.footerMenuItems.clear()
        for module in App.context.modules {
            if let item = module.titleBarRightHeaderItemRequired(in: context) {
                titleBarRightHeader.children.append(item)
            }
            for item in module.navigationViewMenuItemsRequired(in: context) {
                navigationView.menuItems.append(item)
            }
            for item in module.navigationViewFooterMenuItemsRequired(in: context) {
                navigationView.footerMenuItems.append(item)
            }
        }

        if let page = viewModel.currentPage {
            navigate(to: page)
        } else if let lastURL = viewModel.routePreferences.lastPageURL, navigate(to: lastURL) {
            return
        } else {
            navigationView.selectFirstItem()
        }
    }
    
    private func restoreWindowRect() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter
        else { return }

        let maximized = viewModel.windowPosition.isMaximized //moveAndResize will cause pref changed in event, so need to reserve here
        try? hwnd.moveAndResize(viewModel.windowPosition.windowRect)
        if maximized {
            try? presenter.maximize()
        }
    }

    private func trackWindowSize() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter else { return }

        if presenter.state == .restored {
            viewModel.windowPosition.windowWidth = Int(hwnd.size.width)
            viewModel.windowPosition.windowHeight = Int(hwnd.size.height)
            viewModel.windowPosition.isMaximized = false
        } else if presenter.state == .maximized {
            viewModel.windowPosition.isMaximized = true
        }
    }

    private func trackWindowPosition() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter
        else { return }

        if presenter.state == .restored {
            viewModel.windowPosition.windowX = Int(hwnd.position.x)
            viewModel.windowPosition.windowY = Int(hwnd.position.y)
        }
    }

    // MARK: - Splitter Methods

    private func makeSplitterBorder() -> Border {
        let b = Border()
        b.width = splitterWidth
        b.verticalAlignment = .stretch
        b.horizontalAlignment = .left
        b.background = SolidColorBrush(UWP.Color(a: 0, r: 0, g: 0, b: 0)) // transparent hit area
        b.margin = Thickness(
            left: navigationView.openPaneLength - splitterWidth / 2,
            top: 0, right: 0, bottom: 0
        )
        b.visibility = viewModel.windowLayout.navigationViewPaneOpen ? .visible : .collapsed
        b.protectedCursor = try? InputSystemCursor.create(.sizeWestEast)

        setupSplitterPointerEvents(b)
        return b
    }

    private func setupSplitterPointerEvents(_ splitter: Border) {
        splitter.pointerPressed.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            let point = try? args.getCurrentPoint(nil) // window-relative
            self.isDraggingSplitter = true
            self.dragStartX = Double(point?.position.x ?? 0)
            self.dragStartPaneLength = self.navigationView.openPaneLength
            _ = try? self.splitterBorder.capturePointer(args.pointer)
            args.handled = true
        }

        splitter.pointerMoved.addHandler { [weak self] _, args in
            guard let self, self.isDraggingSplitter, let args else { return }
            let point = try? args.getCurrentPoint(nil) // window-relative
            let currentX = Double(point?.position.x ?? 0)
            let delta = currentX - self.dragStartX
            let newLength = min(self.viewModel.windowLayout.navigationViewMaxPaneLength, max(self.viewModel.windowLayout.navigationViewMinPaneLength, self.dragStartPaneLength + delta))
            self.applyPaneLength(newLength)
            args.handled = true
        }

        splitter.pointerReleased.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            self.isDraggingSplitter = false
            try? self.splitterBorder.releasePointerCapture(args.pointer)
            args.handled = true
        }

        splitter.pointerCaptureLost.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.isDraggingSplitter = false
        }
    }

    private func applyPaneLength(_ length: Double) {
        navigationView.openPaneLength = length
        navigationView.expandedModeThresholdWidth = length + viewModel.windowLayout.navigationViewExpandedModeThresholdContentWidth
        splitterBorder.margin = Thickness(
            left: length - splitterWidth / 2,
            top: 0, right: 0, bottom: 0
        )
    }
}
