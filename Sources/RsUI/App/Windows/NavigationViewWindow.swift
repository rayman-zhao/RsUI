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
        )! = nil
    private var windowLayout = App.context.preferences.load(for: WindowLayout.self)
    private var splitterState = (
        isDraggingSplitter: false,
        dragStartX: Double(0),
        dragStartPaneLength: Double(0),
        splitterWidth: Double(6),
    )
    var saveLayoutPreferences: Bool = true  // false → 关窗时不把本窗口的 NavPane 状态写回全局 windowLayout，避免一次性 viewer 窗口污染主窗口的下次启动状态

    init(_ forceMinimalMode: Bool = false) {
        super.init()

        setupUI()
        if forceMinimalMode {
            ui.navigationView.paneDisplayMode = .leftMinimal
            saveLayoutPreferences = false
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
                self.saveLayoutPreferences = true
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
            guard self.saveLayoutPreferences else { return }

            self.windowLayout.navigationViewPaneOpen = self.ui.navigationView.isPaneOpen
            self.windowLayout.navigationViewOpenPaneLength = self.ui.navigationView.openPaneLength

            App.context.preferences.save(windowLayout)
        }
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
        </Grid>
        """
    }
}
