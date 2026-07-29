import Foundation
import UWP
import WinAppSDK
import WinUI

@testable import RsUI

/// 统一的 `PageControl` 手测窗口：一个窗体类型，依据 `mode` 实例化 `PageFrame`
/// 或 `PageTabView`，验证二者对外接口已收敛到一个公共 `PageControl` 协议。
///
/// 通用动作（Back / Forward / 批量 +Page）走 `any PageControl` 多态入口；仅
/// `PageTabView` 才有的 strip 行为（+NewTab、strip "+" provider、tab 计数）走窗口
/// 保留的 `pageTabView` 具体引用。这样可以验证协议足够通用、又能看见 PageTabView
/// 特性的差异。
///
/// 视觉结构（root + 工具栏用 XAML 字符串加载，控件因是项目内 Swift 类、不在 WinUI
/// XAML 词汇表内，故加载后用 children.append 挂入 Row1）：
///   Window → Grid(root, 2 行: 工具栏 auto / 控件 star)
///     Row0: Border 工具栏（back / forward / 3 个加页按钮 + +NewTab + 计数显示）
///     Row1: PageFrame | PageTabView
final class PageControlTestWindow: Window {
    enum Mode {
        case frame
        case tabView
    }

    private let mode: Mode
    private var counter = 0

    /// 统一驱动入口——Back/Forward/+Page 全在此调多态方法。在 super.init 之前定型，
    /// 故为 `let` 非可选，避免 IUO 在 Swift 6 严格可选规则下仍被当作 Optional 而需解包。
    private let control: any PageControl
    /// 仅在 `tabView` 模式下持有，用于 strip "+" provider、+NewTab、tabCount 显示等
    /// PageTabView 特有行为。
    private let pageTabView: PageTabView?

    // 工具栏控件（XAML 加载后用 findName 取回）。
    private var backButton: Button!
    private var forwardButton: Button!
    private var statusText: TextBlock!
    private var tabCountText: TextBlock!
    private var newTabButton: Button!

    init(mode: Mode) {
        self.mode = mode
        // 仅构造控件并赋值送到存储属性；不在此闭包里捕获 self —— super.init() 之前
        // 捕获 self（即便 [weak self]）属 "self used before super.init" 错误。回调
        // 在 super.init() 之后再挂。
        switch mode {
        case .frame:
            let frame = PageFrame(model: MainWindowTab())
            self.control = frame
            self.pageTabView = nil
        case .tabView:
            let tv = PageTabView(maxHistoryPages: 64)
            self.control = tv
            self.pageTabView = tv
        }

        super.init()

        switch mode {
        case .frame:
            title = "PageFrame Test"
        case .tabView:
            title = "PageTabView Test — shared frame"
        }
        extendsContentIntoTitleBar = true
        appWindow.titleBar.preferredHeightOption = .tall
        content = makeRoot()

        // 回调捕获 self，必须在 super.init() 之后赋值，把 page 渲染后状态刷新挂上。
        switch control {
        case let frame as PageFrame:
            frame.onPageChanged = { [weak self] _, _ in self?.updateStatus() }
            frame.onCleared = { [weak self] _ in self?.updateStatus() }
        case let tv as PageTabView:
            tv.onPageChanged = { [weak self] _, _, _ in self?.updateStatus() }
            tv.onCleared = { [weak self] _, _ in self?.updateStatus() }
        default:
            break
        }

        // strip "+" 的 page 来源（仅 tabView 模式有意义）。
        pageTabView?.setAddTabProvider { [weak self] in
            guard let self else {
                return (makePage(name: "Home", headerKind: .string, effect: .fromBottom), "Home")
            }
            return self.makeProviderPage()
        }

        Task { @MainActor in
            let homePage = makePage(name: "Home", headerKind: .string, effect: .fromBottom)
            switch mode {
            case .frame:
                // 首帧抑制进入动画，与原 PageFrameTestWindow 一致。
                control.pushPage(
                    to: homePage,
                    transitionInfoOverride: SuppressNavigationTransitionInfo(),
                    maxHistoryPages: 64
                )
            case .tabView:
                // PageTabView 首个 tab 走 addTab（内部首个 tab 用 Suppress 进场）。
                pageTabView?.addTab(
                    page: homePage,
                    header: "Home",
                    transitionInfoOverride: NavigationTransitionInfo.make(slideEffect: .fromBottom)
                )
            }
            updateStatus()
        }
    }

    // MARK: - Root + Toolbar (XAML-loaded)

    /// 加载 root Grid（2 行：工具栏 auto / 控件 star）+ 内嵌工具栏，并取出命名控件、
    /// 绑定 click。control 因是项目内 Swift 类不在 XAML 词汇表内，加载后挂到 Row1。
    /// frame 模式下 NewTab 与 tabCountText 无意义，在 makeRoot 末尾折叠它们。
    private func makeRoot() -> FrameworkElement {
        let root = (try? XamlReader.load(rootXAML)) as! Grid

        // 命名控件：findName 在 XamlReader.Load 返回的根上调用即可访问该 namescope。
        backButton = (try? root.findName("BackButton")) as? Button
        forwardButton = (try? root.findName("ForwardButton")) as? Button
        statusText = (try? root.findName("StatusText")) as? TextBlock
        tabCountText = (try? root.findName("TabCountText")) as? TextBlock
        newTabButton = (try? root.findName("NewTabButton")) as? Button

        // 事件处理必须在代码里绑（XAML 不能写 XAML-defined 事件处理器）。
        backButton.click.addHandler { [weak self] _, _ in self?.goBackTapped() }
        forwardButton.click.addHandler { [weak self] _, _ in self?.goForwardTapped() }

        for (name, kind) in [
            ("AddStringButton", HeaderKind.string),
            ("AddUIElemButton", HeaderKind.uiElement),
            ("AddNilHdrButton", HeaderKind.nilHeader),
        ] as [(String, HeaderKind)] {
            guard let btn = (try? root.findName(name)) as? Button else { continue }
            btn.click.addHandler { [weak self] _, _ in
                self?.addPageTapped(headerKind: kind)
            }
        }

        newTabButton?.click.addHandler { [weak self] _, _ in self?.newTabTapped() }

        // Row1 挂 control（rootView 是 Grid 子类的 FrameworkElement，可直接 Grid.setRow）。
        root.children.append(control.rootView)
        try? Grid.setRow(control.rootView, 1)

        // frame 模式下 tab 专属控件收起：无 strip 也无 +NewTab 语义。
        if mode != .tabView {
            newTabButton?.visibility = .collapsed
            tabCountText?.visibility = .collapsed
        }

        return root
    }

    /// Root Grid + 工具栏。control 由代码挂到 Row1，故该处仅留空承载位置。
    private var rootXAML: String {
        """
        <Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <!-- Row 0: toolbar -->
            <Border Padding="8,8,8,8" Grid.Row="0">
                <StackPanel Orientation="Horizontal" Spacing="8">
                    <StackPanel Orientation="Horizontal" Spacing="2">
                        <Button Name="BackButton" Width="28" Height="28"
                                MinWidth="0" MinHeight="0" Padding="0,0,0,0"
                                VerticalAlignment="Center">
                            <FontIcon Glyph="&#xE72B;" FontSize="12"/>
                        </Button>
                        <Button Name="ForwardButton" Width="28" Height="28"
                                MinWidth="0" MinHeight="0" Padding="0,0,0,0"
                                VerticalAlignment="Center">
                            <FontIcon Glyph="&#xE72A;" FontSize="12"/>
                        </Button>
                    </StackPanel>
                    <Button Name="AddStringButton" MinHeight="28" Padding="10,4,10,4"
                            VerticalAlignment="Center">
                        <TextBlock Text="+String"/>
                    </Button>
                    <Button Name="AddUIElemButton" MinHeight="28" Padding="10,4,10,4"
                            VerticalAlignment="Center">
                        <TextBlock Text="+UIElem"/>
                    </Button>
                    <Button Name="AddNilHdrButton" MinHeight="28" Padding="10,4,10,4"
                            VerticalAlignment="Center">
                        <TextBlock Text="+NilHdr"/>
                    </Button>
                    <Button Name="NewTabButton" MinHeight="28" Padding="10,4,10,4"
                            VerticalAlignment="Center">
                        <TextBlock Text="+NewTab"/>
                    </Button>
                    <TextBlock Name="StatusText" Margin="12,0,12,0" VerticalAlignment="Center"/>
                    <TextBlock Name="TabCountText" Margin="4,0,0,0" VerticalAlignment="Center"
                               Opacity="0.7"/>
                </StackPanel>
            </Border>
        </Grid>
        """
    }

    // MARK: - Actions

    private func goBackTapped() {
        guard control.canGoBack else { return }
        control.goBack()
        updateStatus()
    }

    private func goForwardTapped() {
        guard control.canGoForward else { return }
        control.goForward()
        updateStatus()
    }

    private func addPageTapped(headerKind: HeaderKind) {
        counter += 1
        let n = counter
        let name = "Page #\(n)"
        // 循环改变方向以便肉眼分辨转场动画（栈内动画）。
        let effect: SlideNavigationTransitionEffect
        switch n % 3 {
        case 0: effect = .fromBottom
        case 1: effect = .fromRight
        default: effect = .fromLeft
        }
        let page = makePage(name: name, headerKind: headerKind, effect: effect)
        control.pushPage(
            to: page,
            transitionInfoOverride: NavigationTransitionInfo.make(slideEffect: effect),
            maxHistoryPages: 64
        )
        updateStatus()
    }

    private func newTabTapped() {
        // 仅 tabView 模式有意义：走 strip "+" 与 +NewTab 同一入口（provider 提供页）。
        pageTabView?.addNewTabFromProvider()
        updateStatus()
    }

    private func updateStatus() {
        let current = control.currentPage?.title ?? "(empty)"
        // currentModel 在 PageFrame 恒非空；PageTabView 取当前选中 tab 的 model。
        // 两侧统一走协议读取 back/forward 计数。
        let backCount = control.currentModel?.backwardPages.count ?? 0
        let fwdCount = control.currentModel?.forwardPages.count ?? 0
        statusText?.text = "cur: \(current) | back: \(backCount) | fwd: \(fwdCount)"
        backButton?.isEnabled = control.canGoBack
        forwardButton?.isEnabled = control.canGoForward

        guard mode == .tabView, let tv = pageTabView else { return }
        // tabs 数 + strip 是否隐藏的状态，方便肉眼判断 strip 自动隐藏。
        let stripHidden = tv.tabCount <= 1
        tabCountText?.text = stripHidden
            ? "tabs: \(tv.tabCount) (strip hidden)"
            : "tabs: \(tv.tabCount)"
    }

    // MARK: - Provider page (PageTabView +NewTab 专用)

    /// strip "+" 按钮 / 工具条 +NewTab 走的 page 来源（仅 tabView 模式）。
    private func makeProviderPage() -> (RsUI.Page, String) {
        counter += 1
        let n = counter
        let page = makePage(name: "Home \(n)", headerKind: .string, effect: .fromBottom)
        return (page, "Tab #\(n)")
    }
}
