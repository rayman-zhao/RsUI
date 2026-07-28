import Foundation
import UWP
import WinAppSDK
import WinUI

@testable import RsUI

/// 独立的 `PageTabView` 手测窗口，直接验证 "单 PageFrame + WinUI.TabView" 组合
/// 控件。两件最少样板：
///   1. 构造 `PageTabView`，`setAddTabProvider` 提供 strip "+" 的 page 来源；
///   2. 在窗口工具条按钮上调 `navigateCurrent / goBackCurrent / goForwardCurrent`
///      与 `addNewTabFromProvider` —— 全部作用于"当前选中 tab"。其余由组件内部
///      完成：单 `PageFrame` 在切换 tab 时 `rebind` 复用、`TabStrip` 单 tab 隐藏。
///
/// 与 `TabViewPageFrameTestWindow` 的两点对照：
///   - **只一个 PageFrame**（`PageTabView.sharedFrame`），多 tab 不再各持一份，
///     切 tab 靠 `rebind(to:)` 复用同一个 `PageTransitionHost`；
///   - **TabStrip 自动隐藏**：`PageTabView` 内部 `updateStripVisibility` 在 tab
///     数 ≤1 时收起 strip，内容位于共享 frame（Grid Row1）不受影响 —— 单 tab
///     完全像素等同于"单 PageFrame 窗口"。
final class PageTabViewTestWindow: Window {
    private var counter = 0
    // 工具条控件（XAML 加载后用 findName 取回）。
    private var backButton: Button!
    private var forwardButton: Button!
    private var statusText: TextBlock!
    private var tabCountText: TextBlock!
    private var pageTabView: PageTabView!

    override init() {
        pageTabView = PageTabView(maxHistoryPages: 64)
        super.init()
        title = "PageTabView Test — single shared frame"
        // 保留系统标题栏：避免再 setTitleBar 复杂度，本次重点在组件逻辑验证。
        content = makeRoot()

        // 共享 MockPages 调色板。strip "+" 按钮的 page 来源由此 provider 提供。
        pageTabView.setAddTabProvider { [weak self] in
            guard let self else {
                return (makePage(name: "Home", headerKind: .string, effect: .fromBottom), "Home")
            }
            return self.makeProviderPage()
        }
        pageTabView.onPageChanged = { [weak self] _, _, _ in
            self?.updateStatus()
        }
        pageTabView.onCleared = { [weak self] _, _ in
            self?.updateStatus()
        }

        Task { @MainActor in
            // 首帧让 PageTabView 走 Suppress 进入动画（少绕一道）；
            // effect 仅记录到 model.navigationTransitionInfo，栈内 Back 才用到。
            let homePage = makePage(name: "Home", headerKind: .string, effect: .fromBottom)
            pageTabView.addTab(
                page: homePage,
                header: "Home",
                transitionInfoOverride: NavigationTransitionInfo.make(slideEffect: .fromBottom)
            )
            updateStatus()
        }
    }

    // MARK: - Root + Toolbar (XAML-loaded)

    /// 加载 root Grid（toolbar + PageTabView 两行）+ 内嵌工具栏，并取出命名控件、
    /// 绑定 click。PageTabView 因是项目内 Swift 类不在 XAML 词汇表内，加载后挂
    /// 到 Row1。
    private func makeRoot() -> FrameworkElement {
        let root = (try? XamlReader.load(rootXAML)) as! Grid

        backButton = (try? root.findName("BackButton")) as? Button
        forwardButton = (try? root.findName("ForwardButton")) as? Button
        statusText = (try? root.findName("StatusText")) as? TextBlock
        tabCountText = (try? root.findName("TabCountText")) as? TextBlock

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

        if let newTabBtn = (try? root.findName("NewTabButton")) as? Button {
            newTabBtn.click.addHandler { [weak self] _, _ in
                self?.newTabTapped()
            }
        }

        // Row1 挂 PageTabView（Grid 子类，可直接 Grid.setRow）。
        root.children.append(pageTabView)
        try? Grid.setRow(pageTabView, 1)

        return root
    }

    /// Root Grid + 工具栏。PageTabView 由代码挂到 Row1。
    private var rootXAML: String {
        """
        <Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <!-- Row 0: toolbar (作用于当前选中 tab) -->
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
        pageTabView.goBackCurrent()
        updateStatus()
    }

    private func goForwardTapped() {
        pageTabView.goForwardCurrent()
        updateStatus()
    }

    private func addPageTapped(headerKind: HeaderKind) {
        counter += 1
        let n = counter
        let pageName = "Page #\(n)"
        // 循环改变方向以便肉眼分辨转场动画（栈内动画；tab 切换本身始终 Suppress）。
        let effect: SlideNavigationTransitionEffect
        switch n % 3 {
        case 0: effect = .fromBottom
        case 1: effect = .fromRight
        default: effect = .fromLeft
        }
        let page = makePage(name: pageName, headerKind: headerKind, effect: effect)
        pageTabView.navigateCurrent(
            to: page,
            transitionInfoOverride: NavigationTransitionInfo.make(slideEffect: effect)
        )
        updateStatus()
    }

    private func newTabTapped() {
        // strip "+" 与工具条 +NewTab 走同一入口：调 provider 加 tab。
        pageTabView.addNewTabFromProvider()
        updateStatus()
    }

    private func updateStatus() {
        let current = pageTabView.currentPage?.title ?? "(empty)"
        guard let model = pageTabView.selectedTabModel else {
            statusText?.text = "cur: \(current) | back: 0 | fwd: 0"
            backButton?.isEnabled = false
            forwardButton?.isEnabled = false
            tabCountText?.text = "tabs: \(pageTabView.tabCount)"
            return
        }
        statusText?.text =
            "cur: \(current)"
            + " | back: \(model.backwardPages.count)"
            + " | fwd: \(model.forwardPages.count)"
        backButton?.isEnabled = pageTabView.canGoBack
        forwardButton?.isEnabled = pageTabView.canGoForward
        // tabs 数 + strip 是否隐藏的状态，方便肉眼判断 strip 自动隐藏。
        let stripHidden = pageTabView.tabCount <= 1
        tabCountText?.text = stripHidden
            ? "tabs: \(pageTabView.tabCount) (strip hidden)"
            : "tabs: \(pageTabView.tabCount)"
    }

    // MARK: - Provider page

    /// strip "+" 按钮 / 工具条 +NewTab 走的 page 来源。
    private func makeProviderPage() -> (RsUI.Page, String) {
        counter += 1
        let n = counter
        let page = makePage(name: "Home \(n)", headerKind: .string, effect: .fromBottom)
        return (page, "Tab #\(n)")
    }
}
