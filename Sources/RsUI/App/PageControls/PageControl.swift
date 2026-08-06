import Foundation
import WinUI

/// 一个承载"当前 Page + 单条导航栈"的可复用控件接口，统一宿主窗口对
/// `PageFrame`（单页面栈）与 `PageTabView`（共享 frame + 多 tab）的驱动入口。
///
/// 两控件在"mutate 后渲染"上语义不同：
/// - `PageFrame` 仅修改 `MainWindowTab`，渲染需调用方通过 `renderCurrentPageIfNeeded`
///   显式触发；
/// - `PageTabView` 的 `navigateCurrent/goBackCurrent/goForwardCurrent` 已自动渲染。
///
/// 本协议把两者统一到"mutate + 即时渲染"语义：`PageFrame` 的 conformance extension
/// 在 mutate 后自动调用 `renderCurrentPageIfNeeded()`，`PageTabView` 直接转发到
/// `*Current` 方法（控件内部已渲染）。宿主窗口由此可以以一个 `any PageControl`
/// 协议类型多态驱动，无需关心渲染时机差异。
///
/// **方法命名**：协议命令用 `pushPage` 而非 `navigate` —— `PageFrame` 本类已有
/// `navigate(to:transitionInfoOverride:maxHistoryPages:)`，仅 mutate 不渲染；若协议
/// 也叫 `navigate` 则 conformance extension 会与本类方法签名撞名（"invalid
/// redeclaration"）。故选用一个不与本类重名、又能表达"入栈一个新页"的命名。
///
/// **不抽回调**：两控件的原生回调签名不同（`PageFrame` 为 `(PageFrame, Page)`；
/// `PageTabView` 为 `(PageTabView, TabContext, Page)`，多一层 tab 上下文），把它们
/// 统一会改既有公共 API 表面，范围过大。宿主窗口用具体控件类型各设一次原生
/// `onPageChanged`/`onCleared`，回调内统一只做 light-weight 状态刷新。
// Internal：`MainWindowTab` 是 internal 类型（见 MainWindowViewModel.swift），
// 故协议本身不能 public。当前仅同模块内（PageControls 与 @testable import 的测试
// 可执行文件）使用即可。若未来需要跨模块暴露，需先把 MainWindowTab 提为 public。
protocol PageControl: AnyObject {
    /// 当前展示的 Page（无则 nil）。
    var currentPage: Page? { get }

    /// 当前展示页所在的导航栈 model，供宿主读取 back/forward 计数等。
    /// `PageFrame` 永远非空（持有自己的 `MainWindowTab`）；`PageTabView` 取
    /// 当前选中 tab 的 model（无选中 tab 时为 nil）。
    var currentModel: MainWindowTab? { get }

    /// 当前栈能否 Back / Forward。
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }

    /// 用于进入全屏模式显示的元素。
    var pageView: UIElement { get }

    /// 在当前栈上 navigate 一个新 Page 并即时渲染。
    ///
    /// - Parameter maxHistoryPages: `PageFrame` 路径直接转发到 model.navigate；
    ///   `PageTabView` 路径忽略此参数（其 `navigateCurrent` 用控件 init 时固化的
    ///   `maxHistoryPages`），统一窗口两种模式共用同一个值（64），无行为差异。
    func pushPage(
        to page: Page,
        transitionInfoOverride: NavigationTransitionInfo?,
        maxHistoryPages: Int
    )

    /// 当前栈内 Back —— mutate + 自动渲染。
    func goBack()

    /// 当前栈内 Forward —— mutate + 自动渲染。
    func goForward()

    func updateAppearance()
    func updateWindowContext(_ context: WindowContext)
    func navigate(
        to page: Page,
        mode: NavigationOpenMode,
        transitionInfoOverride: NavigationTransitionInfo?
    )
    func open(
        _ pages: [Page],
        mode: NavigationOpenMode,
        transitionInfoOverride: NavigationTransitionInfo?
    ) -> Int
    func focus(matchingURL url: URL) -> Bool

    var pageChanged: EventWithArgumentHandler<PageControl, Page?> { get }
}

// MARK: - PageFrame conformance

extension PageFrame: PageControl {
    var currentModel: MainWindowTab? { model }
    var pageView: UIElement { self }

    func pushPage(
        to page: Page,
        transitionInfoOverride: NavigationTransitionInfo?,
        maxHistoryPages: Int
    ) {
        // PageFrame 本类的 navigate 只 mutate model、不渲染；这里补上 render，
        // 把"mutate + render"两步收敛成一步，与 PageTabView 的 navigateCurrent
        // 语义对齐，让宿主窗口能多态驱动。命名 pushPage 以避与本类 navigate 撞名。
        navigate(
            to: page,
            transitionInfoOverride: transitionInfoOverride,
            maxHistoryPages: maxHistoryPages
        )
        renderCurrentPageIfNeeded()
    }

    // 已满足 currentPage / canGoBack / canGoForward（本类直接提供）。

    // 本类的 goBack(_:)/goForward(_:) 只 mutate model、不渲染，且带一个 transitionInfo
    // 标签参数（与本协议的无参 goBack()/goForward() 非同签名，故不撞名）。这里在协议
    // 层面补 render，与 pushPage 对称；调用本类方法走 fromLeft / fromRight 默认转场。
    func goBack() {
        goBack(NavigationTransitionInfo.make(slideEffect: .fromLeft))
        renderCurrentPageIfNeeded()
    }

    func goForward() {
        goForward(NavigationTransitionInfo.make(slideEffect: .fromRight))
        renderCurrentPageIfNeeded()
    }

    func updateAppearance() {
    }
    func updateWindowContext(_ context: WindowContext) {
    }
    func navigate(
        to page: Page,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) {
    }
    func open(
        _ pages: [Page],
        mode: NavigationOpenMode = .newTab,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> Int { return 0 }
    func focus(matchingURL url: URL) -> Bool {
        return false
    }
}

// MARK: - PageTabView conformance

extension PageTabView: PageControl {
    var currentModel: MainWindowTab? { selectedTabModel }
    var pageView: UIElement { self.sharedFrame.pageView }

    func pushPage(
        to page: Page,
        transitionInfoOverride: NavigationTransitionInfo?,
        maxHistoryPages: Int
    ) {
        // navigateCurrent 内部用控件 init 时固化的 maxHistoryPages，外层传入的
        // maxHistoryPages 在此路径上被忽略（统一窗口两种模式共用 64，无行为差异）。
        _ = maxHistoryPages
        navigateCurrent(to: page, transitionInfoOverride: transitionInfoOverride)
    }

    func goBack() { goBackCurrent() }
    func goForward() { goForwardCurrent() }

    func updateAppearance() {
        reapplyCloseOthersTooltip()
    }
    func updateWindowContext(_ context: WindowContext) {
        currentPage?.onWindowContextChanged(to: context)
    }

    func navigate(
        to page: Page,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) {
        switch mode {
        case .inplace:
            guard self.selectedTabContext != nil else {
                addTab(
                    page: page, header: page.title, transitionInfoOverride: transitionInfoOverride,
                    at: nil, switchToTab: true)
                return
            }
            navigateCurrent(to: page, transitionInfoOverride: transitionInfoOverride)
            return
        case .newTab:
            addTab(
                page: page, header: page.title, transitionInfoOverride: transitionInfoOverride,
                at: nil, switchToTab: true)
        case .newTabNoFocus:
            addTab(
                page: page, header: page.title, transitionInfoOverride: transitionInfoOverride,
                at: nil, switchToTab: false)
        }
    }

    func open(
        _ pages: [Page],
        mode: NavigationOpenMode = .newTab,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> Int {
        let contexts = addTabs(
            pages: pages,
            switchToLast: mode != .newTabNoFocus,
            transitionInfoOverride: transitionInfoOverride
        )
        return contexts.count
    }

    func focus(matchingURL url: URL) -> Bool {
        guard let ctx = findTabContext(matchingURL: url) else { return false }
        selectTab(ctx)
        return true
    }

    private func findTabContext(matchingURL url: URL) -> TabContext? {
        orderedTabContexts.first { $0.model.currentPage?.url == url }
    }

    private func addTabs(
        pages: [Page],
        switchToLast: Bool = true,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> [PageTabView.TabContext] {
        guard !pages.isEmpty else { return [] }
        let hadSelection = selectedTabContext != nil

        var contexts: [PageTabView.TabContext] = []
        contexts.reserveCapacity(pages.count)
        for page in pages {
            // 背景 add：switchToTab=false，让最后一个再统一选中。
            let ctx = addTab(
                page: page,
                header: page.title,
                transitionInfoOverride: transitionInfoOverride,
                at: nil,
                switchToTab: false
            )
            contexts.append(ctx)
        }

        // Mirror the looped-addTab selection: foreground lands on the last tab;
        // a background batch into an empty window still needs a selection, so it
        // lands on the first; an existing selection is otherwise preserved.
        let selection: PageTabView.TabContext?
        if switchToLast {
            selection = contexts.last
        } else if !hadSelection {
            selection = contexts.first
        } else {
            selection = nil
        }
        if let selection {
            selectTab(selection)
        }
        return contexts
    }
}
