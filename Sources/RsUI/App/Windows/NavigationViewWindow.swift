import RsFoundation
import UWP
import WinAppSDK
import WinUI
import WindowsFoundation

private func tr(_ keyAndValue: String) -> String {
    return App.context.tr(keyAndValue)
}

private struct WindowLayout: PreferenceValue {
    var navigationViewMinPaneLength: Double = 100
    var navigationViewMaxPaneLength: Double = 400
    var navigationViewExpandedModeThresholdContentWidth: Double = 688  // MARK: 688 is from default size 1008 - 320

    var navigationViewPaneOpen: Bool = true
    var navigationViewOpenPaneLength: Double = 320
}

class NavigationViewWindow: AppearanceWindow {
    private(set) var ui:
        (
            root: Grid,
            titleBar: TitleBar,
            backButton: Button,
            forwardButton: Button,
            searchBox: AutoSuggestBox,
            titleBarRightHeader: StackPanel,
            navWrapper: Grid,
            navigationView: NavigationView,
            splitterBorder: Border,
            fullscreenOverlay: Border,
        )! = nil
    private var splitterState = (
        isDraggingSplitter: false,
        dragStartX: Double(0),
        dragStartPaneLength: Double(0),
        splitterWidth: Double(6),
    )

    let fullscreenChanged = EventHandler<NavigationViewWindow>()
    private(set) var isInFullscreen = false
    private var fullscreen = (
        preParent: UIElement?(nil),
        preIndex: UInt32?(nil),
        preWindowMaximized: false,
        installedEscapeAccelerator: false,
    )

    private var windowLayout = App.context.preferences.load(for: WindowLayout.self)
    private var saveWindowLayoutPreferences: Bool = true  // false → 关窗时不把本窗口的 NavPane 状态写回全局 windowLayout，避免一次性 viewer 窗口污染主窗口的下次启动状态

    init(_ forceMinimalMode: Bool = false) {
        super.init()

        setupUI()
        if forceMinimalMode {
            ui.navigationView.paneDisplayMode = .leftMinimal
            saveWindowLayoutPreferences = false
        }

        bindEvents()
    }

    private func setupUI() {
        let xaml = xmalUI.replacingOccurrences(
            of: "{x:IconPath}", with: App.context.iconPath ?? "")
        let loaded = (try? XamlReader.load(xaml)) as! Grid

        self.ui = (
            root: loaded,
            titleBar: (try? loaded.findName("TitleBar")) as! TitleBar,
            backButton: (try? loaded.findName("BackButton")) as! Button,
            forwardButton: (try? loaded.findName("ForwardButton")) as! Button,
            searchBox: (try? loaded.findName("SearchBox")) as! AutoSuggestBox,
            titleBarRightHeader: (try? loaded.findName("RightHeader")) as! StackPanel,
            navWrapper: (try? loaded.findName("NavWrapper")) as! Grid,
            navigationView: (try? loaded.findName("NavigationView")) as! NavigationView,
            splitterBorder: (try? loaded.findName("SplitterBorder")) as! Border,
            fullscreenOverlay: (try? loaded.findName("FullscreenOverlay")) as! Border,
        )

        let paneOpen = windowLayout.navigationViewPaneOpen
        ui.navigationView.isPaneOpen = paneOpen
        ui.splitterBorder.protectedCursor = try? InputSystemCursor.create(.sizeWestEast)
        ui.splitterBorder.visibility = paneOpen ? .visible : .collapsed
        applyPaneLength(windowLayout.navigationViewOpenPaneLength)

        self.content = ui.root
        try? setTitleBar(ui.titleBar)
    }

    private func bindEvents() {
        ui.titleBar.paneToggleRequested.addHandler { [weak self] _, _ in
            guard let self else { return }

            // 强制最小化导航栏启动后，如果用户手工展开，即认为希望保存窗口布局。
            if self.ui.navigationView.paneDisplayMode != .auto {
                self.ui.navigationView.paneDisplayMode = .auto
                self.ui.navigationView.isPaneOpen = true
                self.saveWindowLayoutPreferences = true
            } else {
                self.ui.navigationView.isPaneOpen.toggle()
            }
        }
        ui.navigationView.paneClosed.addHandler { [weak self] _, _ in
            self?.ui.splitterBorder.visibility = .collapsed
        }
        ui.navigationView.paneOpened.addHandler { [weak self] _, _ in
            self?.ui.splitterBorder.visibility = .visible
        }

        bindSplitterEvents()
        bindWindowEvents()
    }

    private func bindSplitterEvents() {
        ui.splitterBorder.pointerPressed.addHandler { [weak self] _, args in
            guard let self, let args else { return }

            let point = try? args.getCurrentPoint(nil)  // window-relative
            self.splitterState.isDraggingSplitter = true
            self.splitterState.dragStartX = Double(point?.position.x ?? 0)
            self.splitterState.dragStartPaneLength = self.ui.navigationView.openPaneLength
            _ = try? self.ui.splitterBorder.capturePointer(args.pointer)

            args.handled = true
        }
        ui.splitterBorder.pointerMoved.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            guard self.splitterState.isDraggingSplitter else { return }

            let point = try? args.getCurrentPoint(nil)  // window-relative
            let currentX = Double(point?.position.x ?? 0)
            let delta = currentX - self.splitterState.dragStartX
            let newLength = min(
                self.windowLayout.navigationViewMaxPaneLength,
                max(
                    self.windowLayout.navigationViewMinPaneLength,
                    self.splitterState.dragStartPaneLength + delta)
            )
            self.applyPaneLength(newLength)

            args.handled = true
        }
        ui.splitterBorder.pointerReleased.addHandler { [weak self] _, args in
            guard let self, let args else { return }

            self.splitterState.isDraggingSplitter = false
            try? self.ui.splitterBorder.releasePointerCapture(args.pointer)

            args.handled = true
        }
        ui.splitterBorder.pointerCaptureLost.addHandler { [weak self] _, _ in
            self?.splitterState.isDraggingSplitter = false
        }
    }

    private func applyPaneLength(_ length: Double) {
        ui.navigationView.openPaneLength = length
        ui.navigationView.expandedModeThresholdWidth =
            length + windowLayout.navigationViewExpandedModeThresholdContentWidth
        ui.splitterBorder.margin = Thickness(
            left: length - splitterState.splitterWidth / 2,
            top: 0, right: 0, bottom: 0
        )
    }

    private func bindWindowEvents() {
        self.appearanceChanged.addHandler { [weak self] _ in
            guard let self else { return }
            // 死窗口防御：closed handler 把 viewModel 置为 nil，此时 appWindow 也已失效（IUO → nil）
            guard let hwnd = self.appWindow else { return }

            // For min/max/close buttons. 目前不支持材质效果，但比逐个设置按钮颜色简单，并且容易由框架修正。
            hwnd.titleBar.preferredTheme = App.context.theme.titleBarTheme

            let str = App.context.tr(App.context.productName)
            self.title = str
            self.ui.titleBar.title = str
            try? ToolTipService.setToolTip(self.ui.backButton, tr("Back"))
            try? ToolTipService.setToolTip(self.ui.forwardButton, tr("Forward"))
            self.ui.searchBox.placeholderText = App.context.tr("Search ...")
        }

        self.closed.addHandler { [weak self] _, _ in
            guard let self else { return }

            // 关窗时若是全屏，先退出，避免把窗口留在 .fullScreen presenter 上
            if self.isInFullscreen {
                self.exitFullscreen()
            }

            guard self.saveWindowLayoutPreferences else { return }
            self.windowLayout.navigationViewPaneOpen = self.ui.navigationView.isPaneOpen
            self.windowLayout.navigationViewOpenPaneLength = self.ui.navigationView.openPaneLength
            App.context.preferences.save(windowLayout)
        }
    }

    // MARK: - Generic fullscreen (any UIElement)

    /// 把任意 UIElement 临时设为窗口全屏内容。
    ///
    /// 实现方法：
    ///     OS 级: `appWindow.setPresenter(.fullScreen)`（隐藏 Windows TaskBar）。
    ///     应用级: 从该 element 的当前 visual parent 上 detach（同时记录 parent + index），
    ///     reparent 到窗口壳 XAML 中预声明的 `FullscreenOverlay`（跨行、ZIndex 100 的
    ///     Border）并把 overlay 置可见；同时 collapsed 掉 titleBar 与 navWrapper，关掉
    ///     `extendsContentIntoTitleBar`。
    /// 退出：反向。Reparent 回原 parent 的原位置，overlay 收为 collapsed，还原
    ///     titleBar/navWrapper/`extendsContentIntoTitleBar`/`.overlapped`；若进入前 window
    ///     是 maximized，退出后还原 maximize 状态。
    /// Esc 退出：内置 KeyboardAccelerator，仅 `isInFullscreen` 为真时拦截 + handled。
    /// 已在全屏、或 element 已经无 parent（如已在 overlay 上），均为 no-op。
    func enterFullscreen(for element: UIElement) {
        guard !isInFullscreen else { return }
        guard let hwnd = self.appWindow else { return }
        guard let pre = element.detachFromVisualParent() else { return }

        isInFullscreen = true
        fullscreen.preParent = pre.parent
        fullscreen.preIndex = pre.index
        // setPresenter(.overlapped) 退出时不还原 maximize 状态，需要提前记录。
        if let presenter = hwnd.presenter as? OverlappedPresenter {
            fullscreen.preWindowMaximized = (presenter.state == .maximized)
        } else {
            fullscreen.preWindowMaximized = false
        }
        installEscapeAcceleratorIfNeeded()

        ui.fullscreenOverlay.child = element
        ui.fullscreenOverlay.visibility = .visible
        ui.titleBar.visibility = .collapsed
        ui.navWrapper.visibility = .collapsed
        // setPresenter(.fullScreen) 不清除 caption 配置，顶部仍可拖动窗口，
        // 临时关掉 extendsContentIntoTitleBar，退出时恢复。
        self.extendsContentIntoTitleBar = false

        try? hwnd.setPresenter(.fullScreen)
        fullscreenChanged.invoke(self)
    }

    /// 退出 element 全屏，把 element reparent 回退出前的原 parent 原位置。
    /// 未在全屏时为 no-op。
    func exitFullscreen() {
        guard
            isInFullscreen,
            let element = ui.fullscreenOverlay.child,
            let parent = fullscreen.preParent
        else { return }

        ui.fullscreenOverlay.child = nil
        element.attachToParent(parent, index: fullscreen.preIndex)
        ui.fullscreenOverlay.visibility = .collapsed
        ui.titleBar.visibility = .visible
        ui.navWrapper.visibility = .visible
        self.extendsContentIntoTitleBar = true

        // 已关窗口时 appWindow 为 nil（IUO）—— 此时只清理本地状态，跳过 setPresenter。
        if let hwnd = self.appWindow {
            try? hwnd.setPresenter(.overlapped)
            if fullscreen.preWindowMaximized, let presenter = hwnd.presenter as? OverlappedPresenter
            {
                try? presenter.maximize()
            }
        }

        isInFullscreen = false
        fullscreen.preParent = nil
        fullscreen.preIndex = nil
        fullscreen.preWindowMaximized = false
        fullscreenChanged.invoke(self)
    }

    /// 首次进全屏时装一个 Esc accelerator；未在全屏时透传给其他处理者。
    /// 用 `installedEscapeAccelerator` 守护，每个窗口最多装一次。
    private func installEscapeAcceleratorIfNeeded() {
        guard !fullscreen.installedEscapeAccelerator else { return }

        let esc = KeyboardAccelerator()
        esc.key = .escape
        esc.invoked.addHandler { [weak self] _, args in
            guard let self, self.isInFullscreen else { return }
            self.exitFullscreen()
            args?.handled = true
        }
        ui.root.keyboardAccelerators.append(esc)

        // Can't see the problem. Keep for later check.
        // WinUI auto-shows an "Esc" shortcut tooltip for elements owning a
        // KeyboardAccelerator; suppress it since the accelerator is global.
        // ui.root.keyboardAcceleratorPlacementMode = .hidden

        fullscreen.installedEscapeAccelerator = true
    }

    // MARK: - XAML UI

    /// 窗口壳静态结构。对照 WinUI Gallery "End to end TitleBar sample"：
    /// `Grid(Row0=Auto TitleBar, Row1=* NavigationView)`，标题栏内容 + 右标题头 +
    /// 面板开关按钮都在这里声明。Splitter 仅声明透明占位 Border，几何与事件由 Swift 回填。
    private var xmalUI: String {
        """
        <Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <!-- Row 0: custom TitleBar (registered as window drag region) -->
            <TitleBar Name="TitleBar" Grid.Row="0"
                      IsBackButtonVisible="False"
                      IsPaneToggleButtonVisible="True">
                <TitleBar.IconSource>
                    <ImageIconSource ImageSource="{x:IconPath}" />
                </TitleBar.IconSource>
                <TitleBar.Content>
                    <StackPanel Orientation="Horizontal" Spacing="20">
                        <StackPanel Orientation="Horizontal" Spacing="0">
                            <AppBarButton Name="BackButton" Icon="Back" Width="44" />
                            <AppBarButton Name="ForwardButton" Icon="Forward" Width="44" />
                        </StackPanel>
                        <AutoSuggestBox Name="SearchBox"
                                        Width="360"
                                        VerticalAlignment="Center"
                                        Visibility="Visible"
                                        QueryIcon="Find"/>
                    </StackPanel>
                </TitleBar.Content>
                <TitleBar.RightHeader>
                    <StackPanel Name="RightHeader" Orientation="Horizontal"/>
                </TitleBar.RightHeader>
            </TitleBar>

            <!-- Row 1: nav pane + splitter overlay in the same Grid cell -->
            <Grid Name="NavWrapper" Grid.Row="1">
                <NavigationView Name="NavigationView"
                                PaneDisplayMode="Auto"
                                IsSettingsVisible="True"
                                IsBackButtonVisible="Collapsed"
                                IsPaneToggleButtonVisible="False"
                                IsTitleBarAutoPaddingEnabled="False"
                                CompactModeThresholdWidth="0"/>
                <Border Name="SplitterBorder" Width="6"
                        HorizontalAlignment="Left"
                        VerticalAlignment="Stretch"
                        Background="Transparent"/>
            </Grid>

            <!-- Fullscreen overlay: spans the whole window above TitleBar +
                 NavWrapper. Declared collapsed; fullscreen reparents a UIElement
                 into it and flips this to Visible, exit does the reverse. -->
            <Border Name="FullscreenOverlay" Grid.Row="0" Grid.RowSpan="2"
                    Visibility="Collapsed"/>
        </Grid>
        """
    }
}
