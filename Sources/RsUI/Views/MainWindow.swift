import Foundation
import Observation
import WindowsFoundation
import UWP
import WinUI
import WinSDK
import RsHelper

fileprivate func tr(_ keyAndValue: String) -> String {
    return App.context.tr(keyAndValue)
}

/// 主窗口界面配置，包含窗口尺寸、位置和状态
struct MainWindowPreferences: Preferable {
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
}

/// 主窗口类，管理整个应用的导航和 UI 布局
class MainWindow: Window, @unchecked Sendable {
    // MARK: - 属性
    private let viewModel = MainWindowViewModel()

    private var navigationPane: NavigationPane!
    private var hasAppliedInitialWindowSize = false

    /// UI 主要组件
    private var titleBar: TitleBar!
    private let searchBox: AutoSuggestBox? = nil
    
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

        // 确保窗口句柄已激活后再应用尺寸
        self.activated.addHandler { [weak self] _, _ in
            guard let self = self else { return }
            self._windowHandle = WinSDK.GetActiveWindow()
            guard !self.hasAppliedInitialWindowSize else { return }
            self.hasAppliedInitialWindowSize = true
            self.applyWindowSize()
        }
        
        // 注册窗口关闭事件以保存窗口大小
        self.closed.addHandler { [weak self] _, _ in
            self?.saveWindowSize()
        }

        // 应用保存的窗口大小（保持当前位置，不改变 Z 顺序）
        applyWindowSize()
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
        
        //self.searchBox = buildSearchBox()
        self.titleBar = buildTitleBar(searchBox)
        root.children.append(titleBar)
        try? Grid.setRow(titleBar, 0)
        try? setTitleBar(titleBar)

        self.navigationPane = buildNavigationPane()
        root.children.append(navigationPane.rootView)
        try? Grid.setRow(navigationPane.rootView, 1)

        self.content = root
    }

    private func buildSearchBox() -> AutoSuggestBox {
        let box = AutoSuggestBox()
        box.width = 360
        box.height = 32
        box.minWidth = 280
        box.verticalAlignment = .center

        return box
    }
    
    private func buildTitleBar(_ searchBox: AutoSuggestBox?) -> TitleBar {
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
                self.titleBar?.isBackButtonEnabled = canGoBack
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

        titleBar.title = tr(App.context.productName)
        searchBox?.placeholderText = tr("searchControlsAndSamples")
    }
    
    // MARK: - 窗口大小管理
    
    /// 应用保存的窗口大小、位置和状态
    private func applyWindowSize() {
        let prefs = App.context.preferences.load(for: MainWindowPreferences.self)
        guard prefs.windowWidth > 0, prefs.windowHeight > 0 else { return }

        let hwnd = WinSDK.GetActiveWindow()
        guard hwnd != nil else { return }

        let width = Int32(prefs.windowWidth)
        let height = Int32(prefs.windowHeight)
        let x = Int32(prefs.windowX)
        let y = Int32(prefs.windowY)
        
        _ = WinSDK.SetWindowPos(
            hwnd,
            WinSDK.HWND(bitPattern: -2), // HWND_NOTOPMOST to keep Z-order
            x,
            y,
            width,
            height,
            WinSDK.UINT(0x0010 | 0x0004) // SWP_NOACTIVATE | SWP_NOZORDER
        )
        
        // 如果上次是最大化状态，恢复最大化
        if prefs.isMaximized {
            _ = WinSDK.ShowWindow(hwnd, 3) // SW_MAXIMIZE
        }
    }
    
    /// 保存当前窗口大小、位置和状态
    private func saveWindowSize() {
        let hwnd = WinSDK.GetActiveWindow()
        guard hwnd != nil else { return }

        var rect = WinSDK.RECT()
        guard WinSDK.GetWindowRect(hwnd, &rect) else { return }

        let width = Double(rect.right - rect.left)
        let height = Double(rect.bottom - rect.top)
        let x = Double(rect.left)
        let y = Double(rect.top)
        
        guard width > 0, height > 0 else { return }
        
        // 检查窗口是否最大化
        let placement = UnsafeMutablePointer<WinSDK.WINDOWPLACEMENT>.allocate(capacity: 1)
        defer { placement.deallocate() }
        placement.pointee.length = UInt32(MemoryLayout<WinSDK.WINDOWPLACEMENT>.size)
        
        let isMaximized = WinSDK.GetWindowPlacement(hwnd, placement) ? 
            placement.pointee.showCmd == 3 : false // SW_MAXIMIZE = 3
        
        var prefs = MainWindowPreferences()
        prefs.windowWidth = Int(width)
        prefs.windowHeight = Int(height)
        prefs.windowX = Int(x)
        prefs.windowY = Int(y)
        prefs.isMaximized = isMaximized
        
        App.context.preferences.save(prefs)
    }
}
