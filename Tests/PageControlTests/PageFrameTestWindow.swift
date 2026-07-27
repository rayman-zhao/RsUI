import Foundation
import UWP
import WinAppSDK
import WinUI

@testable import RsUI

/// 独立的 `PageFrame` 手测窗口，抛开 MainWindow / Module / WindowContext。
///
/// 视觉结构（root + 工具栏用 XAML 字符串加载，frame 子节点因是项目内 Swift 类、
/// 不在 WinUI XAML 词汇表内，故加载后用 children.append 挂入 Row1）：
///   Window → Grid(root, 2 行: 工具栏 auto / frame star)
///     Row0: Border 工具栏（back / forward / 4 个加页按钮 + 计数显示）
///     Row1: PageFrame
final class PageFrameTestWindow: Window {
    private var counter = 0

    // 工具栏控件（XAML 加载后用 findName 取回）
    private var backButton: Button!
    private var forwardButton: Button!
    private var statusText: TextBlock!
    private var frame: PageFrame!

    override init() {
        let model = MainWindowTab()
        frame = PageFrame(model: model)

        super.init()
        title = "PageFrame Test"
        extendsContentIntoTitleBar = true
        appWindow.titleBar.preferredHeightOption = .tall
        content = makeRoot()

        Task { @MainActor in
            let homePage = makePage(
                name: "Home", headerKind: .string, effect: .fromBottom
            )

            frame.navigate(to: homePage, maxHistoryPages: 30)
            frame.renderCurrentPageIfNeeded()
            updateStatus()
        }
    }

    // MARK: - Root + Toolbar (XAML-loaded)

    /// 加载 root Grid（2 行：工具栏 auto / frame star）+ 内嵌工具栏，并取出
    /// 命名控件、绑定 click。frame 因是项目内 Swift 类不在 XAML 词汇表内，
    /// 加载后挂到 Row1。
    private func makeRoot() -> FrameworkElement {
        let root = (try? XamlReader.load(rootXAML)) as! Grid

        // 命名控件：findName 在 XamlReader.Load 返回的根上调用即可访问该 namescope。
        backButton = (try? root.findName("BackButton")) as? Button
        forwardButton = (try? root.findName("ForwardButton")) as? Button
        statusText = (try? root.findName("StatusText")) as? TextBlock

        // 事件处理必须在代码里绑（XAML 不能写 XAML-defined 事件处理器）。
        backButton.click.addHandler { [weak self] _, _ in self?.goBackTapped() }
        forwardButton.click.addHandler { [weak self] _, _ in self?.goForwardTapped() }

        for (name, kind, reuse) in [
            ("AddStringButton", HeaderKind.string, false),
            ("AddUIElemButton", HeaderKind.uiElement, false),
            ("AddNilHdrButton", HeaderKind.nilHeader, false),
        ] as [(String, HeaderKind, Bool)] {
            guard let btn = (try? root.findName(name)) as? Button else { continue }
            btn.click.addHandler { [weak self] _, _ in
                self?.addPageTapped(headerKind: kind, reuseGrid: reuse)
            }
        }

        // Row1 挂 frame。frame 已经是 FrameworkElement 子类（Grid），可直接 Grid.setRow。
        root.children.append(frame)
        try? Grid.setRow(frame, 1)

        return root
    }

    /// Root Grid + 工具栏。frame 由代码挂到 Row1，故该处仅留空承载位
    /// 置。
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
                    <TextBlock Name="StatusText" Margin="12,0,12,0" VerticalAlignment="Center"/>
                </StackPanel>
            </Border>
        </Grid>
        """
    }

    // MARK: - Actions

    private func goBackTapped() {
        guard frame.canGoBack else { return }
        frame.goBack()
        frame.renderCurrentPageIfNeeded()
        updateStatus()
    }

    private func goForwardTapped() {
        guard frame.canGoForward else { return }
        frame.goForward()
        frame.renderCurrentPageIfNeeded()
        updateStatus()
    }

    private func addPageTapped(headerKind: HeaderKind, reuseGrid: Bool = false) {
        counter += 1
        let n = counter
        let name = "Page #\(n)"
        // 循环改变方向以便肉眼分辨转场动画
        let effect: SlideNavigationTransitionEffect
        switch n % 3 {
        case 0: effect = .fromBottom
        case 1: effect = .fromRight
        default: effect = .fromLeft
        }
        let page = makePage(
            name: name, headerKind: headerKind, effect: effect
        )
        frame.navigate(
            to: page,
            transitionInfoOverride: NavigationTransitionInfo.make(slideEffect: effect),
            maxHistoryPages: 64
        )
        frame.renderCurrentPageIfNeeded()
        updateStatus()
    }

    private func updateStatus() {
        let current = frame.currentPage?.title ?? "(empty)"
        statusText?.text =
            "current: \(current) | back: \(frame.model.backwardPages.count) | fwd: \(frame.model.forwardPages.count)"
        backButton?.isEnabled = frame.canGoBack
        forwardButton?.isEnabled = frame.canGoForward
    }
}
