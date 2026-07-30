import RsFoundation
import UWP
import WinAppSDK
import WinUI
import WindowsFoundation

private struct WindowLayout: PreferenceValue {
    var navigationViewMinPaneLength: Double = 100
    var navigationViewMaxPaneLength: Double = 400
    var navigationViewExpandedModeThresholdContentWidth: Double = 688  // MARK: 688 is from default size 1008 - 320

    var navigationViewPaneOpen: Bool = true
    var navigationViewOpenPaneLength: Double = 320
}

class NavigatableWindow: AppearanceWindow {
    // nil → 使用 windowLayout 中持久化的 NavPane 状态；否则强制覆盖初始展开/折叠
    var initialNavigationViewPaneOpen: Bool? = nil
    // true → 关窗时不把本窗口的 NavPane 状态写回全局 windowLayout，
    // 避免一次性 viewer 窗口污染主窗口的下次启动状态
    var suppressLayoutPersistence: Bool = false

    // Splitter state
    private var splitterBorder: Border!
    private var isDraggingSplitter = false
    private var dragStartX: Double = 0
    private var dragStartPaneLength: Double = 0
    private let splitterWidth: Double = 6

    private var windowLayout: WindowLayout
    let root = Grid()

    lazy var backButton: Button = NavigatableWindow.makeNavButton(glyph: "\u{E72B}") {
        [weak self] in
        self?.onGoBack()
    }
    lazy var forwardButton: Button = NavigatableWindow.makeNavButton(glyph: "\u{E72A}") {
        [weak self] in
        self?.onGoForward()
    }
    lazy var searchBox: AutoSuggestBox? = {
        // let box = AutoSuggestBox()
        // box.width = 360
        // box.height = 32
        // box.minWidth = 280
        // box.verticalAlignment = .center
        // return box
        return nil
    }()
    lazy var titleBarRightHeader = {
        let panel = StackPanel()
        panel.orientation = .horizontal
        return panel
    }()
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
    }()

    lazy var navigationView = {
        let nav = NavigationView()
        nav.paneDisplayMode = .left
        nav.isSettingsVisible = true
        nav.isBackButtonVisible = .collapsed
        nav.isPaneToggleButtonVisible = false
        nav.paneDisplayMode = .auto

        let length = windowLayout.navigationViewOpenPaneLength
        nav.compactModeThresholdWidth = 0
        nav.expandedModeThresholdWidth =
            length + windowLayout.navigationViewExpandedModeThresholdContentWidth
        nav.isPaneOpen =
            initialNavigationViewPaneOpen ?? windowLayout.navigationViewPaneOpen
        nav.openPaneLength = length
        nav.isTitleBarAutoPaddingEnabled = false

        return nav
    }()

    // 全屏时整体 collapse，含 NavigationView + Splitter
    var navWrapper: Grid?

    override init() {
        windowLayout = App.context.preferences.load(for: WindowLayout.self)
        super.init()

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

        configurePaneEvents()

        let navWrapper = makeNavigationWrapper()
        self.navWrapper = navWrapper
        root.children.append(navWrapper)
        try? Grid.setRow(navWrapper, 1)

        self.content = root

        self.closed.addHandler { [weak self] _, _ in
            guard let self else { return }

            if !self.suppressLayoutPersistence {
                self.windowLayout.navigationViewPaneOpen = self.navigationView.isPaneOpen
                self.windowLayout.navigationViewOpenPaneLength = self.navigationView.openPaneLength
            }

            App.context.preferences.save(windowLayout)
        }
    }

    func onGoBack() {}
    func onGoForward() {}

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
        for key in [
            "ButtonBorderBrush", "ButtonBorderBrushPointerOver",
            "ButtonBorderBrushPressed", "ButtonBorderBrushDisabled",
        ] {
            _ = btn.resources.insert(key, transparent)
        }

        btn.click.addHandler { _, _ in action() }
        return btn
    }

    func makeSplitterBorder() -> Border {
        let b = Border()
        b.width = splitterWidth
        b.verticalAlignment = .stretch
        b.horizontalAlignment = .left
        b.background = SolidColorBrush(UWP.Color(a: 0, r: 0, g: 0, b: 0))  // transparent hit area
        b.margin = Thickness(
            left: navigationView.openPaneLength - splitterWidth / 2,
            top: 0, right: 0, bottom: 0
        )
        let paneOpen = initialNavigationViewPaneOpen ?? windowLayout.navigationViewPaneOpen
        b.visibility = paneOpen ? .visible : .collapsed
        b.protectedCursor = try? InputSystemCursor.create(.sizeWestEast)

        setupSplitterPointerEvents(b)
        return b
    }

    private func setupSplitterPointerEvents(_ splitter: Border) {
        splitter.pointerPressed.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            let point = try? args.getCurrentPoint(nil)  // window-relative
            self.isDraggingSplitter = true
            self.dragStartX = Double(point?.position.x ?? 0)
            self.dragStartPaneLength = self.navigationView.openPaneLength
            _ = try? self.splitterBorder.capturePointer(args.pointer)
            args.handled = true
        }

        splitter.pointerMoved.addHandler { [weak self] _, args in
            guard let self, self.isDraggingSplitter, let args else { return }
            let point = try? args.getCurrentPoint(nil)  // window-relative
            let currentX = Double(point?.position.x ?? 0)
            let delta = currentX - self.dragStartX
            let newLength = min(
                self.windowLayout.navigationViewMaxPaneLength,
                max(self.windowLayout.navigationViewMinPaneLength, self.dragStartPaneLength + delta)
            )
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
        navigationView.expandedModeThresholdWidth =
            length + windowLayout.navigationViewExpandedModeThresholdContentWidth
        splitterBorder.margin = Thickness(
            left: length - splitterWidth / 2,
            top: 0, right: 0, bottom: 0
        )
    }

    private func configurePaneEvents() {
        navigationView.paneClosed.addHandler { [weak self] _, _ in
            self?.splitterBorder.visibility = .collapsed
        }
        navigationView.paneOpened.addHandler { [weak self] _, _ in
            self?.splitterBorder.visibility = .visible
        }
    }

    private func makeNavigationWrapper() -> Grid {
        let navWrapper = Grid()
        navWrapper.children.append(navigationView)
        splitterBorder = makeSplitterBorder()
        navWrapper.children.append(splitterBorder)
        try? Canvas.setZIndex(splitterBorder, 10)
        return navWrapper
    }
}
