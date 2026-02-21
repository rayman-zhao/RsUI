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

    var rectInt32: RectInt32 {
        return RectInt32(
            x: Int32(windowX),
            y: Int32(windowY),
            width: Int32(windowWidth),
            height: Int32(windowHeight)
        )
    }
}

/// 主窗口类，管理整个应用的导航和 UI 布局
class MainWindow: Window, @unchecked Sendable {
    // MARK: - 属性
    private let viewModel = MainWindowViewModel()

    private var navigationPane: NavigationPane!
    private var hasAppliedInitialWindowSize = false

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

        // bar.backRequested.addHandler { [weak self] _, _ in
            // guard let self = self, let navigationPane = self.navigationPane else { return }
            // navigationPane.goBack()
            // titleBar.isBackButtonEnabled = navigationPane.canGoBack
        // }

        return bar
    } ()
    
    private var _windowHandle: WinSDK.HWND?

    // MARK: - 初始化
    override init() {
        super.init()
        self._windowHandle = WinSDK.GetActiveWindow()
        
        setupWindow()
        setupModules()      
        setupContent()
        applyAppearance()

        startObserving()
    }

    /// 初始化并注册应用模块
    private func setupModules() {
        // 模块上下文是模块和主引用的通信桥梁，通过提供navigationActions来供各个模块在NavigationPane中注册自己的导航节点
        let context = WindowContext(
            navigationActions: makeNavigationActions(),
            windowHandle: self._windowHandle
        )
        
        // 自动注册所有在 ModuleRegistry 中定义的模块
        for module in App.context.modules {
            module.initialize(context: context)
        }
    }

    /// 构建页面初始化所需的上下文
    private var pageContext: PageContext {
        return PageContext(
            viewModel: viewModel,
            currentTheme: App.context.theme,
            currentLanguage: App.context.language,
            navigationActions: makeNavigationActions(),
            windowHandle: self._windowHandle
        )
    }
    
    private func makeNavigationActions() -> NavigationActions {
        return NavigationActions(
            addNode: { node, parentId, section in
                NavigationCatalog.addNode(node, toParent: parentId, in: section)
            },
            removeNode: { nodeId, section in
                NavigationCatalog.removeNode(withId: nodeId, in: section)
            },
            rebuild: { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    self?.navigationPane?.rebuildNavigation()
                }
            }
        )
    }
    
    // MARK: - UI 设置
    
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

        self.navigationPane = buildNavigationPane()
        root.children.append(navigationPane.rootView)
        try? Grid.setRow(navigationPane.rootView, 1)

        self.content = root
    }
    
    /// 配置导航视图组件
    private func buildNavigationPane() -> NavigationPane {
        let viewModel = self.viewModel
        return NavigationPane(
            viewModel: viewModel,
            makePageContext: { [weak self] in
                guard let self = self else {
                    return PageContext(
                        viewModel: viewModel,
                        currentTheme: App.context.theme,
                        currentLanguage: App.context.language,
                        navigationActions: NavigationActions.noop,
                        windowHandle: nil
                    )
                }
                return self.pageContext
            },
            selectionChanged: { [weak self] _, title in
                guard let self = self else { return }
                let canGoBack = self.navigationPane?.canGoBack ?? false
                self.titleBar.isBackButtonEnabled = canGoBack
            }
        )
    }

    private func startObserving() { 
        let env = Observations {
            (App.context.theme, App.context.language)
        }
        Task { [weak self] in
            for await _ in env {
                guard let self else { break }
                await MainActor.run {
                    self.applyAppearance()
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
    }
    
    private func restoreWindowRect() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter
        else { return }

        let maximized = preference.isMaximized //moveAndResize will cause pref changed in event, so need to reserve here
        try? hwnd.moveAndResize(preference.rectInt32)
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
