import Foundation
import UWP
import WinAppSDK
import WinUI

/// 独立的 `PageFrame` 手测窗口，抛开 MainWindow / Module / WindowContext。
///
/// 启动：`swift run SampleApp --test-frame`。该窗口只用于人工目测 PageFrame
/// 的历史栈、转场动画、header 三分支与 UIElement 单 parent 重绑定行为，
/// 不进入单元测试（GUI 无法在 swift test 下运行）。
///
/// 视觉结构：
///   Window → Grid(root, 2 行: 工具栏 auto / frame star)
///     Row0: Grid 工具栏（back / forward / 4 个加页按钮 + 计数显示）
///     Row1: PageFrame
final class PageFrameTestWindow: Window {
    private var frame: PageFrame!
    // 用 static 而非实例属性：init 里 super.init() 之前不能 dispatch self 方法，
    // static 计数器/调色板索引供静态 makePage 在构造期也能安全复用。本窗口全进程唯一。
    private static var counter = 0
    private static var colorCycle: UInt32 = 0
    // 复用按钮：同一个 Grid 实例反复被不同 Page 返回，验证 UIElement 单 parent 重绑定。
    private let reusedGrid = Grid()

    // 工具栏控件
    private var backButton: Button!
    private var forwardButton: Button!
    private var statusText: TextBlock!

    override init() {
        // 首页 Page：直接构造为 Frame 的初值，避免占位页进入 back 历史。
        let homePage = PageFrameTestWindow.makePage(
            name: "Home", headerKind: .string, effect: .fromBottom, reuseGrid: false, reusedGrid: reusedGrid
        )
        let model = MainWindowTab(page: homePage, transitionInfoOverride: SuppressNavigationTransitionInfo())
        frame = PageFrame(model: model)

        super.init()
        title = "PageFrame Test"
        extendsContentIntoTitleBar = true
        appWindow.titleBar.preferredHeightOption = .tall

        let root = Grid()
        let toolRow = RowDefinition()
        toolRow.height = GridLength(value: 0, gridUnitType: .auto)
        let contentRow = RowDefinition()
        contentRow.height = GridLength(value: 1, gridUnitType: .star)
        root.rowDefinitions.append(toolRow)
        root.rowDefinitions.append(contentRow)

        let toolbar = makeToolbar()
        root.children.append(toolbar)
        if let toolbarFE = toolbar as? FrameworkElement {
            try? Grid.setRow(toolbarFE, 0)
        }

        root.children.append(frame)
        try? Grid.setRow(frame, 1)

        content = root

        // 首帧：作隐形建帧渲染（Suppress 已记入 model），随后 UI 由按钮驱动。
        frame.renderCurrentPageIfNeeded()
        updateStatus()
    }

    // MARK: - Toolbar

    private func makeToolbar() -> UIElement {
        backButton = makeToolbarButton(glyph: "\u{E72B}") { [weak self] in
            self?.goBackTapped()
        }
        forwardButton = makeToolbarButton(glyph: "\u{E72A}") { [weak self] in
            self?.goForwardTapped()
        }

        let addString = makeToolbarButton(label: "+String") { [weak self] in
            self?.addPageTapped(headerKind: .string)
        }
        let addUIElement = makeToolbarButton(label: "+UIElem") { [weak self] in
            self?.addPageTapped(headerKind: .uiElement)
        }
        let addNil = makeToolbarButton(label: "+NilHdr") { [weak self] in
            self?.addPageTapped(headerKind: .nilHeader)
        }
        let addReuse = makeToolbarButton(label: "+Reuse") { [weak self] in
            self?.addPageTapped(headerKind: .string, reuseGrid: true)
        }

        statusText = TextBlock()
        statusText.margin = Thickness(left: 12, top: 0, right: 12, bottom: 0)
        statusText.verticalAlignment = .center

        let bar = Grid()
        let barBorder = Border()
        barBorder.background = SolidColorBrush(UWP.Color(a: 0xFF, r: 0xF3, g: 0xF3, b: 0xF3))
        barBorder.padding = Thickness(left: 8, top: 8, right: 8, bottom: 8)
        barBorder.child = bar

        let stack = StackPanel()
        stack.orientation = .horizontal
        stack.spacing = 8

        let backFwd = StackPanel()
        backFwd.orientation = .horizontal
        backFwd.spacing = 2
        backFwd.children.append(backButton)
        backFwd.children.append(forwardButton)

        stack.children.append(backFwd)
        stack.children.append(addString)
        stack.children.append(addUIElement)
        stack.children.append(addNil)
        stack.children.append(addReuse)
        stack.children.append(statusText)
        bar.children.append(stack)

        return barBorder
    }

    private func makeToolbarButton(glyph: String, action: @escaping () -> Void) -> Button {
        let icon = FontIcon()
        icon.glyph = glyph
        icon.fontSize = 12
        let btn = Button()
        btn.content = icon
        btn.width = 28
        btn.height = 28
        btn.minWidth = 0
        btn.minHeight = 0
        btn.verticalAlignment = .center
        btn.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        btn.click.addHandler { _, _ in action() }
        return btn
    }

    private func makeToolbarButton(label: String, action: @escaping () -> Void) -> Button {
        let btn = Button()
        let tb = TextBlock()
        tb.text = label
        btn.content = tb
        btn.minHeight = 28
        btn.verticalAlignment = .center
        btn.padding = Thickness(left: 10, top: 4, right: 10, bottom: 4)
        btn.click.addHandler { _, _ in action() }
        return btn
    }

    // MARK: - Actions

    private func goBackTapped() {
        guard frame.canGoBack else { return }
        frame.goBack(PageFrameTestWindow.makeSlideTransition(effect: .fromLeft))
        frame.renderCurrentPageIfNeeded()
        updateStatus()
    }

    private func goForwardTapped() {
        guard frame.canGoForward else { return }
        frame.goForward(PageFrameTestWindow.makeSlideTransition(effect: .fromRight))
        frame.renderCurrentPageIfNeeded()
        updateStatus()
    }

    private func addPageTapped(headerKind: HeaderKind, reuseGrid: Bool = false) {
        PageFrameTestWindow.counter += 1
        let n = PageFrameTestWindow.counter
        let name = "Page #\(n)"
        // 循环改变方向以便肉眼分辨转场动画
        let effect: SlideNavigationTransitionEffect
        switch n % 3 {
        case 0: effect = .fromBottom
        case 1: effect = .fromRight
        default: effect = .fromLeft
        }
        let page = PageFrameTestWindow.makePage(
            name: name, headerKind: headerKind, effect: effect, reuseGrid: reuseGrid, reusedGrid: reusedGrid
        )
        frame.navigate(
            to: page,
            transitionInfoOverride: PageFrameTestWindow.makeSlideTransition(effect: effect),
            maxHistoryPages: 64
        )
        frame.renderCurrentPageIfNeeded()
        updateStatus()
    }

    private func updateStatus() {
        let current = frame.currentPage?.title ?? "(empty)"
        statusText.text = "current: \(current) | back: \(frame.model.backwardPages.count) | fwd: \(frame.model.forwardPages.count)"
        backButton.isEnabled = frame.canGoBack
        forwardButton.isEnabled = frame.canGoForward
    }

    private static func makeSlideTransition(effect: SlideNavigationTransitionEffect) -> NavigationTransitionInfo {
        let transition = SlideNavigationTransitionInfo()
        transition.effect = effect
        return transition
    }

    // MARK: - Test Page factory

    private enum HeaderKind { case string, uiElement, nilHeader }

    private static func makePage(
        name: String,
        headerKind: HeaderKind,
        effect: SlideNavigationTransitionEffect,
        reuseGrid: Bool,
        reusedGrid: Grid
    ) -> Page {
        // 循环颜色用肉眼分辨转场
        let palette: [(r: UInt8, g: UInt8, b: UInt8)] = [
            (0xE6, 0xF2, 0xFB), (0xFB, 0xF3, 0xE6), (0xF3, 0xE6, 0xFB),
            (0xE6, 0xFB, 0xF3), (0xFB, 0xE6, 0xF3), (0xF3, 0xFB, 0xE6)
        ]
        let rgb = palette[Int(colorCycle % UInt32(palette.count))]
        colorCycle += 1
        let bg = SolidColorBrush(UWP.Color(a: 0xFF, r: rgb.r, g: rgb.g, b: rgb.b))
        let reused: Grid? = reuseGrid ? reusedGrid : nil

        switch headerKind {
        case .string:
            return StringHeaderPage(name: name, bg: bg, reusedGrid: reused)
        case .uiElement:
            return UIElementHeaderPage(name: name, bg: bg, reusedGrid: reused)
        case .nilHeader:
            return NilHeaderPage(name: name, bg: bg, reusedGrid: reused)
        }
    }
}

// MARK: - Concrete test pages

private final class StringHeaderPage: Page {
    let name: String
    let bg: SolidColorBrush
    let reusedGrid: Grid?

    init(name: String, bg: SolidColorBrush, reusedGrid: Grid?) {
        self.name = name
        self.bg = bg
        self.reusedGrid = reusedGrid
    }

    var url: URL { URL(string: "rs://test-frame/string/\(name)")! }
    var title: String { name }
    var header: Any? { "String Header — \(name)" }

    var content: UIElement {
        if let reusedGrid { return reusedGrid }
        return PageFrameTestContent.make(name: name, subtitle: "header.kind = String", bg: bg)
    }
}

private final class UIElementHeaderPage: Page {
    let name: String
    let bg: SolidColorBrush
    let reusedGrid: Grid?

    init(name: String, bg: SolidColorBrush, reusedGrid: Grid?) {
        self.name = name
        self.bg = bg
        self.reusedGrid = reusedGrid
    }

    var url: URL { URL(string: "rs://test-frame/uielem/\(name)")! }
    var title: String { name }

    var header: Any? {
        let panel = StackPanel()
        panel.orientation = .horizontal
        panel.spacing = 12
        let title = TextBlock()
        title.text = "UIElement Header"
        title.fontWeight = FontWeights.semiBold
        let subtitle = TextBlock()
        subtitle.text = name
        subtitle.opacity = 0.7
        panel.children.append(title)
        panel.children.append(subtitle)
        return panel
    }

    var content: UIElement {
        if let reusedGrid { return reusedGrid }
        return PageFrameTestContent.make(name: name, subtitle: "header.kind = UIElement", bg: bg)
    }
}

private final class NilHeaderPage: Page {
    let name: String
    let bg: SolidColorBrush
    let reusedGrid: Grid?

    init(name: String, bg: SolidColorBrush, reusedGrid: Grid?) {
        self.name = name
        self.bg = bg
        self.reusedGrid = reusedGrid
    }

    var url: URL { URL(string: "rs://test-frame/nil/\(name)")! }
    var title: String { name }
    var header: Any? { nil }

    var content: UIElement {
        if let reusedGrid { return reusedGrid }
        return PageFrameTestContent.make(name: name, subtitle: "header.kind = nil (content fills)", bg: bg)
    }
}

private enum PageFrameTestContent {
    static func make(name: String, subtitle: String, bg: SolidColorBrush) -> UIElement {
        let grid = Grid()
        let border = Border()
        border.background = bg
        border.margin = Thickness(left: 16, top: 0, right: 16, bottom: 16)
        border.padding = Thickness(left: 24, top: 24, right: 24, bottom: 24)
        border.cornerRadius = CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)

        let stack = StackPanel()
        stack.spacing = 6
        let title = TextBlock()
        title.text = name
        title.fontSize = 24
        title.fontWeight = FontWeights.semiBold
        let sub = TextBlock()
        sub.text = subtitle
        sub.opacity = 0.7
        stack.children.append(title)
        stack.children.append(sub)
        border.child = stack
        grid.children.append(border)
        return grid
    }
}
