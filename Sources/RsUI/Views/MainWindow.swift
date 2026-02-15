import Foundation
import Observation
import WinAppSDK
import WindowsFoundation
import WinUI
import UWP
import WinSDK
import RsHelper

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
    
    private let viewModel: MainWindowViewModel

    private var navigationPane: NavigationPane!
    private var appWindowTitleBar: WinAppSDK.AppWindowTitleBar?
    private var hasAppliedInitialWindowSize = false

    /// UI 主要组件
    private var rootGrid: Grid!
    private var titleBar: TitleBar!
    private var themeToggleIcon: FontIcon?
    private var themeToggleLabel: TextBlock?
    private var searchBox: AutoSuggestBox?
    
    private var _windowHandle: WinSDK.HWND?

    // MARK: - 初始化
    
    override init() {
        self.viewModel = MainWindowViewModel()
        super.init()
        self._windowHandle = WinSDK.GetActiveWindow()
        
        setupWindow()
        setupModules()
        setupUI()
        registerViewModelCallbacks()
        applyTheme(App.context.theme)
        refreshLocalizationUI()
    }

    /// 初始化并注册应用模块
    private func setupModules() {
        // 模块上下文是模块和主引用的通信桥梁，通过提供navigationActions来供各个模块在NavigationPane中注册自己的导航节点
        let context: ModuleContext = ModuleContext(
            navigationActions: makeNavigationActions(),
            windowHandle: self._windowHandle
        )
        
        // 自动注册所有在 ModuleRegistry 中定义的模块
        for module in App.context.modules {
            AppShared.moduleManager.register(module, context: context)
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
        self.title = "Ruslan"
        self.extendsContentIntoTitleBar = true
        
        // 设置 Mica 背景
        let micaBackdrop = MicaBackdrop()
        micaBackdrop.kind = .base
        self.systemBackdrop = micaBackdrop

        appWindowTitleBar = self.appWindow?.titleBar
        appWindowTitleBar?.extendsContentIntoTitleBar = true
        appWindowTitleBar?.preferredHeightOption = .tall
        
        // 设置任务栏图标
        if let appWindow = self.appWindow {
            if let iconPath = App.context.resourcesBundle.path(forResource: "GalleryIcon", ofType: "ico") {
                do {
                    try appWindow.setIcon(iconPath)
                } catch {
                    debugPrint("Failed to set app icon: \(error)")
                }
            }
        }

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
    private func setupUI() {
        rootGrid = Grid()
        rootGrid.name = "RootGrid"
        
        // 设置行定义
        let titleRowDef = RowDefinition()
        titleRowDef.height = GridLength(value: 1, gridUnitType: .auto)
        rootGrid.rowDefinitions.append(titleRowDef)
        
        let contentRowDef = RowDefinition()
        contentRowDef.height = GridLength(value: 1, gridUnitType: .star)
        rootGrid.rowDefinitions.append(contentRowDef)
        
        self.content = rootGrid

        setupTitleBar()
        setupNavigationPane()
    }
    
    /// 配置标题栏
    private func setupTitleBar() {
        titleBar = TitleBar()
        titleBar.height = 48
        titleBar.title = "WinUI Gallery"
        titleBar.subtitle = "Preview"
        titleBar.isBackButtonVisible = false
        titleBar.isPaneToggleButtonVisible = false

        if let iconPath = App.context.resourcesBundle.path(forResource: "GalleryIcon", ofType: "ico") {
            let bitmap = BitmapImage()
            bitmap.uriSource = Uri(iconPath)

            let iconSource = ImageIconSource()
            iconSource.imageSource = bitmap
            titleBar.iconSource = iconSource
        }

        let searchBox = AutoSuggestBox()
        searchBox.width = 360
        searchBox.height = 32
        searchBox.minWidth = 280
        searchBox.verticalAlignment = .center
        searchBox.placeholderText = App.context.tr("searchControlsAndSamples")
        self.searchBox = searchBox
        titleBar.content = searchBox

        // 创建右侧按钮容器
        let rightButtonsPanel = StackPanel()
        rightButtonsPanel.orientation = .horizontal
        rightButtonsPanel.verticalAlignment = .center
        rightButtonsPanel.spacing = 10
        rightButtonsPanel.margin = Thickness(left: 0, top: 0, right: 12, bottom: 0)

        // 添加主题切换按钮
        let themeButton = Button()
        themeButton.minWidth = 88
        themeButton.height = 32
        themeButton.verticalAlignment = .center
        themeButton.horizontalAlignment = .center

        let themeContent = StackPanel()
        themeContent.orientation = .horizontal
        themeContent.spacing = 6
        themeContent.verticalAlignment = .center

        let themeIcon = FontIcon()
        themeIcon.fontSize = 14
        themeIcon.glyph = "\u{E708}"  // 月亮图标
        themeToggleIcon = themeIcon

        let themeLabel = TextBlock()
        themeLabel.verticalAlignment = .center
        themeLabel.fontSize = 13
        themeLabel.text = themeDisplayName(for: App.context.theme)
        themeToggleLabel = themeLabel

        themeContent.children.append(themeIcon)
        themeContent.children.append(themeLabel)
        themeButton.content = themeContent

        themeButton.click.addHandler { _, _ in
            App.context.theme.toggle()
        }

        // 添加用户头像
        let profilePicture = PersonPicture()
        profilePicture.width = 32
        profilePicture.height = 32
        profilePicture.verticalAlignment = .center
        profilePicture.horizontalAlignment = .center
        profilePicture.margin = Thickness(left: 0, top: 0, right: 6, bottom: 0)

        rightButtonsPanel.children.append(themeButton)
        rightButtonsPanel.children.append(profilePicture)

        titleBar.rightHeader = rightButtonsPanel
        updateThemeToggleAppearance(for: App.context.theme)

        titleBar.backRequested.addHandler { [weak self] _, _ in
            guard let self = self, let navigationPane = self.navigationPane else { return }
            navigationPane.goBack()
            self.titleBar?.isBackButtonVisible = navigationPane.canGoBack
            self.titleBar?.isBackButtonEnabled = navigationPane.canGoBack
        }

        rootGrid.children.append(titleBar)
        try? Grid.setRow(titleBar, 0)
        try? setTitleBar(titleBar)
    }
    
    /// 配置导航视图组件
    private func setupNavigationPane() {
        let viewModel = self.viewModel
        navigationPane = NavigationPane(
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
                self.updateTitle(with: title)
                let canGoBack = self.navigationPane?.canGoBack ?? false
                self.titleBar?.isBackButtonVisible = canGoBack
                self.titleBar?.isBackButtonEnabled = canGoBack
            }
        )

        rootGrid.children.append(navigationPane.rootView)
        try? Grid.setRow(navigationPane.rootView, 1)
        let canGoBack = navigationPane.canGoBack
        titleBar?.isBackButtonVisible = canGoBack
        titleBar?.isBackButtonEnabled = canGoBack
    }
    
    /// 注册 ViewModel 的回调处理
    private func registerViewModelCallbacks() { 
        let env = Observations {
            (App.context.theme, App.context.language)
        }
        Task { [weak self] in
            for await ctx in env {
                guard let self else { break }
                await MainActor.run {
                    self.applyTheme(ctx.0)
                    self.handleLanguageChanged(ctx.1)
                }
            }
        }
    }

    // MARK: - 主题管理
    
    /// 应用主题到整个应用和所有页面
    private func applyTheme(_ theme: AppTheme) {
        let appTheme = theme.applicationTheme
        WinUI.Application.current?.requestedTheme = appTheme
        updateTitleBarButtonColors(for: appTheme)

        let elementTheme = theme.elementTheme
        rootGrid?.requestedTheme = elementTheme
        titleBar?.requestedTheme = elementTheme
        updateThemeToggleAppearance(for: theme)
    }


    // MARK: - 本地化管理
    
    /// 刷新所有 UI 元素的本地化文本
    private func refreshLocalizationUI() {
        updateTitle(with: navigationPane?.currentTitle ?? "Ruslan")
    }

    /// 根据文本更新窗口标题
    private func updateTitle(with title: String) {
        titleBar?.title = title
        self.title = title
    }

    /// 根据主题更新标题栏按钮颜色，确保深色模式下对比度合适
    private func updateTitleBarButtonColors(for theme: WinUI.ApplicationTheme) {
        guard let titleBar = appWindowTitleBar else { return }

        let isDark = theme == .dark
        titleBar.preferredTheme = isDark ? .dark : .light
        titleBar.backgroundColor = nil
        titleBar.inactiveBackgroundColor = nil

        if isDark {
            let white = UWP.Color(a: 255, r: 255, g: 255, b: 255)
            let hover = UWP.Color(a: 255, r: 60, g: 60, b: 68)
            let pressed = UWP.Color(a: 255, r: 80, g: 80, b: 92)
            let inactive = UWP.Color(a: 255, r: 180, g: 180, b: 188)

            titleBar.buttonForegroundColor = white
            titleBar.buttonHoverForegroundColor = white
            titleBar.buttonPressedForegroundColor = white
            titleBar.buttonInactiveForegroundColor = inactive
            titleBar.buttonBackgroundColor = UWP.Color(a: 0, r: 0, g: 0, b: 0)
            titleBar.buttonHoverBackgroundColor = hover
            titleBar.buttonPressedBackgroundColor = pressed
            titleBar.buttonInactiveBackgroundColor = UWP.Color(a: 0, r: 0, g: 0, b: 0)
        } else {
            let black = UWP.Color(a: 255, r: 30, g: 30, b: 34)
            let hover = UWP.Color(a: 255, r: 230, g: 232, b: 238)
            let pressed = UWP.Color(a: 255, r: 210, g: 212, b: 220)
            let inactive = UWP.Color(a: 255, r: 120, g: 120, b: 126)

            titleBar.buttonForegroundColor = black
            titleBar.buttonHoverForegroundColor = black
            titleBar.buttonPressedForegroundColor = black
            titleBar.buttonInactiveForegroundColor = inactive
            titleBar.buttonBackgroundColor = UWP.Color(a: 0, r: 0, g: 0, b: 0)
            titleBar.buttonHoverBackgroundColor = hover
            titleBar.buttonPressedBackgroundColor = pressed
            titleBar.buttonInactiveBackgroundColor = UWP.Color(a: 0, r: 0, g: 0, b: 0)
        }
    }
    
    /// 处理语言变更事件
    private func handleLanguageChanged(_: AppLanguage) {
        refreshLocalizationUI()
        // 更新搜索框的 placeholder 文本
        if let searchBox = searchBox {
            searchBox.placeholderText = App.context.tr("searchControlsAndSamples")
        }
        // 更新主题按钮的文本（语言改变时需要重新翻译）
        updateThemeToggleAppearance(for: App.context.theme)
    }

    private func themeDisplayName(for theme: AppTheme) -> String {
        return App.context.tr(theme.isDark ? "darkMode" : "lightMode")
    }

    private func updateThemeToggleAppearance(for theme: AppTheme) {
        guard let icon = themeToggleIcon, let label = themeToggleLabel else { return }
        let isDark = theme.isDark
        icon.glyph = isDark ? "\u{E706}" : "\u{E708}"  // 太阳或月亮
        label.text = App.context.tr(isDark ? "darkMode" : "lightMode")
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
