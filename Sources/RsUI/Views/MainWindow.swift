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

/// 主窗口界面配置，包含窗口尺寸、位置和状态
fileprivate struct MainWindowPreferences: Preferable {
    /// 窗口宽度
    var windowWidth: Int = 1280
    /// 窗口高度
    var windowHeight: Int = 800
    /// 窗口左上角 X 坐标
    var windowX: Int = 100
    /// 窗口左上角 Y 坐标
    var windowY: Int = 100
    /// 窗口是否最大化
    var isMaximized: Bool = false

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
    private let viewModel = MainWindowViewModel()
    private lazy var statusBar = StatusBar(
        service: App.context.statusBar,
        tr: { App.context.tr($0, "SettingsPage") },
        isBarVisible: { App.context.isStatusBarVisible },
        setBarVisible: { App.context.isStatusBarVisible = $0 }
    )

    /// UI 主要组件
    private lazy var preference = App.context.preferences.load(for: MainWindowPreferences.self)
    private lazy var searchBox: AutoSuggestBox? = {
        // let box = AutoSuggestBox()
        // box.width = 360
        // box.height = 32
        // box.minWidth = 280
        // box.verticalAlignment = .center

        // return box
        return nil
    } ()
    private lazy var titleBar = {
        let bar = TitleBar()
        bar.height = 48
        bar.isBackButtonVisible = false
        bar.isPaneToggleButtonVisible = true

        if let iconPath = App.context.bundle.path(forResource: App.context.productName, ofType: "ico") {
            let bitmap = BitmapImage()
            bitmap.uriSource = Uri(iconPath)

            let iconSource = ImageIconSource()
            iconSource.imageSource = bitmap
            bar.iconSource = iconSource
        }

        if let searchBox {
            bar.content = searchBox
        }

        bar.paneToggleRequested.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.navigationView.isPaneOpen.toggle()
        }

        return bar
    } ()
    private lazy var navigationContentFrame = Frame()
    private lazy var navigationView = {
        let nav = NavigationView()
        nav.paneDisplayMode = .left
        nav.isSettingsVisible = true
        nav.isBackButtonVisible = .collapsed
        nav.isPaneToggleButtonVisible = false
        nav.paneDisplayMode = .auto
        nav.compactModeThresholdWidth = 0
        //nav.openPaneLength = Double(pref.sidebarWidth)
        //nav.expandedModeThresholdWidth = 800

        let scrollViewer = ScrollViewer()
        scrollViewer.content = navigationContentFrame
        nav.content = scrollViewer

        return nav
    } ()
    private lazy var rootGrid = WinUI.Grid()
    private var displayingPage: AppPage? = nil

    // MARK: - 初始化
    override init() {
        super.init()

        setupWindow()
        setupContent()
        setupModules()

        startObserving()
        applyAppearance()
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
            App.context.preferences.save(self.preference)
        }
        restoreWindowRect()
    }

    /// 初始化主要的 UI 布局
    private func setupContent() {
        // 设置行定义
        let titleRowDef = RowDefinition()
        titleRowDef.height = GridLength(value: 1, gridUnitType: .auto)
        rootGrid.rowDefinitions.append(titleRowDef)
        
        let contentRowDef = RowDefinition()
        contentRowDef.height = GridLength(value: 1, gridUnitType: .star)
        rootGrid.rowDefinitions.append(contentRowDef)

        let statusRowDef = RowDefinition()
        statusRowDef.height = GridLength(value: 1, gridUnitType: .auto)
        rootGrid.rowDefinitions.append(statusRowDef)
        
        rootGrid.children.append(titleBar)
        try? Grid.setRow(titleBar, 0)
        try? setTitleBar(titleBar)
        
        navigationView.selectionChanged.addHandler { [weak self] view, args in
            guard let self, let view, let args else { return }

            if args.isSettingsSelected {
                view.header = App.context.tr("title", "SettingsPage")
                let page = SettingsPage()
                self.navigationContentFrame.content = page.rootView
                self.displayingPage = page
            } else if let item = args.selectedItem as? NavigationViewItem, let tag = item.tag {
                let context = WindowContext(hwnd: self.appWindow, statusBar: App.context.statusBar)
                for module in App.context.modules {
                    if let target = module.makeNavigationTarget(for: tag, in: context) {
                        view.header = target.header
                        self.navigationContentFrame.content = target.page.rootView
                        self.displayingPage = target.page
                        break
                    }
                }
            }
        }
        rootGrid.children.append(navigationView)
        try? Grid.setRow(navigationView, 1)

        rootGrid.children.append(statusBar.root)
        try? Grid.setRow(statusBar.root, 2)

        self.content = rootGrid
    }

    private func setupModules() {
        let context = WindowContext(hwnd: self.appWindow, statusBar: App.context.statusBar)
        for module in App.context.modules {
            module.register(in: context)
        }
    }

    private func startObserving() { 
        let env = Observations {
            (App.context.theme, App.context.language, App.context.isStatusBarVisible)
        }
        Task { [weak self] in
            for await _ in env {
                await MainActor.run { [weak self] in
                    self?.applyAppearance()
                }
            }
        }

        let statusBarState = Observations {
            (
                App.context.statusBar.items,
                App.context.statusBar.logs,
                App.context.statusBar.hiddenItemIDs,
                App.context.statusBar.descriptors
            )
        }
        Task { [weak self] in
            for await _ in statusBarState {
                await MainActor.run { [weak self] in
                    self?.statusBar.render()
                }
            }
        }
    }

    private func applyAppearance() {
        // For min/max/close buttons. 目前不支持材质效果，但比逐个设置按钮颜色简单，并且容易由框架修正。
        self.appWindow.titleBar.preferredTheme = App.context.theme.titleBarTheme

        self.title = tr(App.context.productName)
        titleBar.title = self.title
        searchBox?.placeholderText = tr("searchControlsAndSamples")

        let context = WindowContext(hwnd: self.appWindow, statusBar: App.context.statusBar)
        navigationView.menuItems.clear()
        for module in App.context.modules {
            for item in module.registerNavigationViewItems(in: context) {
                navigationView.menuItems.append(item)
            }
        }
        if navigationContentFrame.content == nil && navigationView.menuItems.count > 0 {
            navigationView.selectedItem = navigationView.menuItems[0]
        }

        displayingPage?.onAppearanceChanged()
        statusBar.applyTheme(App.context.theme)
        statusBar.root.visibility = App.context.isStatusBarVisible ? WinUI.Visibility.visible : WinUI.Visibility.collapsed
        registerSystemStatusBarItems()
        statusBar.render()
    }

    private func registerSystemStatusBarItems() {
        App.context.statusBar.register(
            moduleId: "system",
            itemId: "logs",
            title: App.context.language == .zh_CN ? "日志入口" : "Log entry",
            slot: .right,
            priority: 90
        )
        App.context.statusBar.upsert(
            moduleId: "system",
            itemId: "logs",
            slot: .right,
            text: App.context.language == .zh_CN ? "日志 \(App.context.statusBar.logs.count)" : "Logs \(App.context.statusBar.logs.count)",
            priority: 90
        )
    }
    
    private func restoreWindowRect() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter
        else { return }

        let maximized = preference.isMaximized //moveAndResize will cause pref changed in event, so need to reserve here
        try? hwnd.moveAndResize(preference.windowRect)
        if maximized {
            try? presenter.maximize()
        }
    }

    private func trackWindowSize() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter
        else { return }

        if presenter.state == .restored {
            self.preference.windowWidth = Int(hwnd.size.width)
            self.preference.windowHeight = Int(hwnd.size.height)
            self.preference.isMaximized = false
        } else if presenter.state == .maximized {
            self.preference.isMaximized = true
        }
    }

    private func trackWindowPosition() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter
        else { return }

        if presenter.state == .restored {
            self.preference.windowX = Int(hwnd.position.x)
            self.preference.windowY = Int(hwnd.position.y)
        }
    }
}
