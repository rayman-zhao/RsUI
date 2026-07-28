import UWP
import WinUI

/// 单页面栈容器：拥有一个 `MainWindowTab`（back/forward 历史）+ 一个
/// `PageTransitionHost`（转场渲染），负责把当前 Page 的 header/content 渲染进
/// 转场宿主。等同 AGENTS.md "Core UI Composition Model" 中的 RsUI.Frame。
///
/// 本类只管"一个页面栈的渲染与历史"，不涉及 tab strip、NavView 同步、窗口级
/// 偏好等 shell 职责 —— 这些仍由 MainWindow 通过 `renderCurrentPageIfNeeded`
/// 与回调驱动。首帧动画抑制也由调用方（`renderSelectedTab`）通过
/// `transitionInfoOverride` 传入，本类不持有窗口级状态。
class PageFrame: Grid {
    // `var` 而非 `let`：支持单 PageFrame 在多个 tab 间复用时通过 `rebind(to:)`
    // 重设 model；切 tab 后旧 model 仍在各自 TabContext 中独立存活（不跨 tab 共享）。
    var model: MainWindowTab
    private let transitionHost: PageTransitionHost
    private var pageViewParts = PageViewParts()

    /// 渲染完成（page 已切换/重画）后回调，shell 用来同步 NavView 选中、写
    /// `lastPageURL`、刷新 back/forward 按钮态。本回调在主线程上触发。
    var onPageChanged: ((PageFrame, Page) -> Void)?
    /// 当前 page 被清空时回调（如内容退出动画）。本回调在主线程上触发。
    var onCleared: ((PageFrame) -> Void)?

    init(model: MainWindowTab) {
        self.model = model
        self.transitionHost = PageTransitionHost()
        super.init()
        children.append(transitionHost)
    }

    var currentPage: Page? { model.currentPage }
    var canGoBack: Bool { !model.backwardPages.isEmpty }
    var canGoForward: Bool { !model.forwardPages.isEmpty }

    // MARK: - History mutations (model-only, 不渲染)
    // 渲染由调用方通过 renderCurrentPageIfNeeded 触发，以便 shell 在渲染前
    // 注入首帧抑制等 transitionInfo 决策（见 MainWindow.renderSelectedTab）。

    func navigate(
        to page: Page,
        transitionInfoOverride: NavigationTransitionInfo? = nil,
        maxHistoryPages: Int
    ) {
        model.navigate(
            to: page,
            transitionInfoOverride: transitionInfoOverride,
            maxHistoryPages: maxHistoryPages
        )
    }

    func goBack(_ transitionInfoOverride: NavigationTransitionInfo = NavigationTransitionInfo.make(slideEffect: .fromLeft)) {
        model.goBack(transitionInfoOverride)
    }

    func goForward(_ transitionInfoOverride: NavigationTransitionInfo = NavigationTransitionInfo.make(slideEffect: .fromRight)) {
        model.goForward(transitionInfoOverride)
    }

    // MARK: - Rendering

    /// 若 `model.needsRender` 为真，渲染当前 page。`transitionInfoOverride` 非 nil
    /// 时覆盖 `model.navigationTransitionInfo`（用于首帧抑制）；否则沿用 model
    /// 中记录的 transitionInfo。无待渲染时为 no-op。
    func renderCurrentPageIfNeeded(transitionInfoOverride: NavigationTransitionInfo? = nil) {
        guard model.needsRender else { return }
        let transitionInfo = transitionInfoOverride ?? model.navigationTransitionInfo
        renderCurrentPage(transitionInfo: transitionInfo)
    }

    /// 强制重画当前 page（置 needsRender=true 后立即渲染），用
    /// `SuppressNavigationTransitionInfo` 避免动画。供 tab 跨窗口迁移后
    /// （`onWindowContextChanged` 改写 page 内容后）调用。
    func rerender() {
        model.needsRender = true
        renderCurrentPage(transitionInfo: SuppressNavigationTransitionInfo())
    }

    /// 重绑 model 并即时渲染当前页（Suppress 转场）。用于单 `PageFrame` 在多 tab
    /// 间共享的形态（`PageTabView`）：切 tab 时把共享 frame 的 model 重设到目标
    /// tab 的 `MainWindowTab`，并立刻渲染其 currentPage。
    ///
    /// 必须一步完成"换 model + 渲染"：否则 `pageViewParts` 仍指向旧 tab 的
    /// `contentBorder`/`headerBorder`（包装着旧 tab 的 `page.content`），后续渲染
    /// 才在 `makePageView` 开头清掉它们，中间若被取消会留下悬空 parent 引用。
    /// 这里强制立即清既安全又显式，与 `rerender()` 策略一致。
    ///
    /// 切换 transition 恒取 `SuppressNavigationTransitionInfo`：tab 切换是"切 View"
    /// 而非栈内 Back/Forward，跨 tab 的滑动动画只会串扰（旧 content 与新 content
    /// 可能跨 tab 不连续），用即时切换最稳。tab 内 `navigate/goBack/goForward`
    /// 仍各自走 `SlideNavigationTransitionInfo`，不受影响。
    func rebind(to newModel: MainWindowTab) {
        model = newModel
        model.needsRender = true
        renderCurrentPage(transitionInfo: SuppressNavigationTransitionInfo())
    }

    private func renderCurrentPage(transitionInfo: NavigationTransitionInfo?) {
        if let page = model.currentPage {
            let view = makePageView(page)
            transitionHost.transition(to: view, transitionInfo: transitionInfo)
            model.needsRender = false
            onPageChanged?(self, page)
        } else {
            transitionHost.transition(to: nil, transitionInfo: transitionInfo)
            model.needsRender = false
            onCleared?(self)
        }
    }

    // MARK: - Page view layout (header + content)
    // 迁自 MainWindow+PageRendering.swift。PageViewParts 持有上一次渲染的
    // header/content Border，重画前先 nil 其 child，防御 UIElement 单 parent
    // 重绑定引发的 WinRT 异常（COM callback 路径异常传不到主线程）。

    private func makePageView(_ page: Page) -> UIElement {
        let parts = pageViewParts
        parts.contentBorder?.child = nil
        parts.headerBorder?.child = nil
        parts.contentBorder = nil
        parts.headerBorder = nil

        // String header: 渲染为页面顶部标题
        // UIElement header: 直接渲染到页面顶部
        // nil header: 不渲染 header 区域，content 占满整个页面
        let headerView: UIElement
        if let text = page.header as? String {
            let tb = TextBlock()
            tb.text = text
            tb.fontSize = 28
            tb.fontWeight = FontWeights.semiBold
            tb.textWrapping = .wrap
            headerView = tb
        } else if let view = page.header as? UIElement {
            headerView = view
        } else {
            return page.content
        }

        let grid = Grid()
        let autoRow = RowDefinition()
        autoRow.height = GridLength(value: 0, gridUnitType: .auto)
        let starRow = RowDefinition()
        starRow.height = GridLength(value: 1, gridUnitType: .star)
        grid.rowDefinitions.append(autoRow)
        grid.rowDefinitions.append(starRow)

        // Row 0: header — WinUI default NavigationViewHeaderMargin (56,44,0,0) is too large, use Photos app's (32,28,0,28) instead.
        let headerBorder = Border()
        headerBorder.margin = Thickness(left: 32, top: 28, right: 0, bottom: 28)
        PageFrame.safelyAssignChild(headerView, toBorder: headerBorder)
        parts.headerBorder = headerBorder

        // Row 1: content
        let contentBorder = Border()
        let pageContent = page.content
        PageFrame.safelyAssignChild(pageContent, toBorder: contentBorder)
        parts.contentBorder = contentBorder

        try? Grid.setRow(headerBorder, 0)
        try? Grid.setRow(contentBorder, 1)
        grid.children.append(headerBorder)
        grid.children.append(contentBorder)
        return grid
    }

    /// 把 `child` 赋值给 `border.child` 之前先显式从原 parent 断开，
    /// 防御 Page 把 UIElement 作为存储属性返回导致的
    /// "Element is already the child of another element" WinRT 异常 ——
    /// 这种异常发生在 COM callback 路径里，会从 `try!` 抛出但传不到 Swift 主线程，
    /// 进程不会真正终止，但相关 UI 操作会失败、日志会污染。
    private static func safelyAssignChild(_ child: UIElement, toBorder border: Border) {
        detachFromVisualParent(child)
        border.child = child
    }

    /// 把 element 从其当前 visual parent 上断开。覆盖 Border / Panel / ContentControl /
    /// ContentPresenter 这几种最常见的 parent 类型。其他类型（如 ItemsControl 直接挂载
    /// arbitrary UIElement，理论上不应该出现）打日志方便排查。
    private static func detachFromVisualParent(_ element: UIElement) {
        guard let parent = try? VisualTreeHelper.getParent(element) else { return }
        if let parentBorder = parent as? Border {
            parentBorder.child = nil
        } else if let parentPanel = parent as? Panel {
            var idx: UInt32 = 0
            if parentPanel.children.indexOf(element, &idx) {
                parentPanel.children.removeAt(idx)
            }
        } else if let parentContent = parent as? ContentControl {
            parentContent.content = nil
        } else if let parentPresenter = parent as? ContentPresenter {
            parentPresenter.content = nil
        } else {
            print("[RsUI] detachFromVisualParent: unsupported parent type \(type(of: parent)) for child \(type(of: element)) — 'Element is already the child of another element' may follow")
        }
    }
}

private final class PageViewParts {
    var contentBorder: Border?
    var headerBorder: Border?
}
