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

    /// UI 主要组件
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

        if let iconPath = App.context.resourceBundle.path(forResource: App.context.productName, ofType: "ico") {
            let bitmap = BitmapImage()
            bitmap.uriSource = Uri(iconPath)

            let iconSource = ImageIconSource()
            iconSource.imageSource = bitmap
            bar.iconSource = iconSource
        }

        if let searchBox {
            bar.content = searchBox
        }

        bar.rightHeader = titleBarRightHeader

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

    func navigate(to page: Page) {
        viewModel.navigate(to: page)
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
            // TODO: appWindow.changed事件不工作，此处窗口最大化时记录有缺陷。其实也可以不保存，恢复窗口在中间即可。
            self?.trackWindowPosition()
            self?.viewModel = nil
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
            guard let self, let args else { return }

            if args.isSettingsSelected {
                navigate(to: SettingsPage())
            } else if
                let item = args.selectedItem as? NavigationViewItem,
                let tag = item.tag,
                let str = tag as? HString,
                let url = URL(string: String(hString: str)) {
                let context = WindowContext(owner: self)
                for module in App.context.modules {
                    if let view = module.navigationRequested(for: url, in: context) {
                        navigate(to: view)
                        break
                    }
                }
            }
        }
        root.children.append(navigationView)
        try? Grid.setRow(navigationView, 1)

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
            for await page in route {
                await MainActor.run { [weak self, weak page] in
                    guard let self, let page else { return }
                    self.navigationView.header = page.header
                    self.navigationContentFrame.content = page.content
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

        let context = WindowContext(owner: self)
        titleBarRightHeader.children.clear()
        navigationView.menuItems.clear()
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
}
