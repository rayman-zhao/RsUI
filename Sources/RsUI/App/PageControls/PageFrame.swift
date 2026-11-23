import Foundation
import UWP
import WinUI

/// 单页面栈容器：拥有一个 `PageModel`（back/forward 历史）+ 一个
/// `PageTransitionHost`（转场渲染），负责把当前 Page 的 header/content 渲染进
/// 转场宿主。
class PageFrame: PageTransitionHost, PageControl, @unchecked Sendable {
    private var model: PageModel
    let windowContext: WindowContext
    /// 上次渲染时的外观值。`updateAppearance` 在值未变时整体跳过：启动期
    /// `AppearanceWindow` 的初始发射会对每个窗口触发一次 updateAppearance
    /// (其消费端还承担导航菜单与窗口 chrome 的首次构建，不能跳过发射本身)，
    /// 若外观未变仍整页重建，会无谓释放刚构建的页面控件——对带有挂起原生
    /// 回调（防抖定时器等）的 COM 聚合子类控件是实测崩溃源（0xC0000005）。
    private var renderedTheme: AppTheme?
    private var renderedLanguage: AppLanguage?

    init(model: PageModel = PageModel(), windowContext: WindowContext) {
        self.model = model
        self.windowContext = windowContext
        super.init()

        render()
    }

    /// 重绑 model 并即时渲染当前页（Suppress 转场）。用于单 `PageFrame` 在多 tab
    /// 间共享的形态（`PageTabView`）：切 tab 时把共享 frame 的 model 重设到目标
    /// tab 的 `PageModel`，并立刻渲染其 currentPage。
    func rebind(to newModel: PageModel) {
        // 同 model 直接跳过：TabView 条带折叠→可见的实现中途会重发 selectionChanged
        // （选中项未变），此时同步重渲染会在 XAML 处理中途改视觉树，put_Child 抛
        // E_INVALIDARG（Ctrl+点击 nav item 的 .newTabNoFocus 路径）
        guard newModel !== model else { return }
        model = newModel
        render()
    }

    // MARK: - PageControl conformance

    var currentPage: Page? { model.currentPage }
    var canGoBack: Bool { !model.backwardPages.isEmpty }
    var canGoForward: Bool { !model.forwardPages.isEmpty }

    var rootView: FrameworkElement { self }
    var fullscreenView: UIElement { self }

    let pageChanged: EventWithArgumentHandler<PageControl, Page?> = EventWithArgumentHandler<
        PageControl, Page?
    >()

    func goBack() {
        model.goBack()

        render(transitionInfo: NavigationTransitionInfo.make(slideEffect: .fromLeft))
    }

    func goForward() {
        model.goForward()

        render(transitionInfo: NavigationTransitionInfo.make(slideEffect: .fromRight))
    }

    func navigate(
        to page: Page,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo
    ) {
        model.navigate(to: page)
        page.windowContextDidChange(to: windowContext)

        render(transitionInfo: transitionInfoOverride)
    }

    func navigate(
        to pages: [Page],
        mode: NavigationOpenMode = .newTab,
        transitionInfoOverride: NavigationTransitionInfo
    ) -> Int {
        for page in pages {
            model.navigate(to: page)
            page.windowContextDidChange(to: windowContext)
        }

        render(transitionInfo: transitionInfoOverride)
        return pages.count
    }

    func selectPage(matchingURL url: URL) -> Bool {
        return model.currentPage?.url == url
    }

    func updateAppearance() {
        guard
            App.context.theme != renderedTheme
                || App.context.language != renderedLanguage
        else { return }
        renderedTheme = App.context.theme
        renderedLanguage = App.context.language
        // 本 model 的页视图缓存清空(其它 tab 的由 PageTabView 清);
        // 懒重建——被再次访问时才 makeView
        model.invalidateAllViews()
        redisplay()
    }

    /// 页面形态更新请求(失效+按需重挂一步完成):清该页视图缓存,
    /// 正在展示才重挂,非当前页无视觉动作待下次展示懒重建
    func updateView(of page: Page) {
        page.view = nil
        guard page === currentPage else { return }
        redisplay()
    }

    /// NOTE: A page inplace transition will have problem if some UI Elements been referenced in the Page object.
    /// So that, must remove the page view from visual tree first, then release COM references in event loop,
    /// then add to new visual tree node.
    func redisplay() {
        transition(to: nil)
        Task {
            transition(to: currentView)
        }
    }

    func updateWindowContext() {
        for page in model.allPages {
            page.windowContextDidChange(to: windowContext)
        }
    }

    /// 当前页视图:页自身 view 槽位为缓存(nil = 待建,构建后回填)
    private var currentView: UIElement? {
        guard let page = currentPage else { return nil }
        if let view = page.view { return view }
        let view = page.makeView()
        page.view = view
        return view
    }

    /// mutate model 后的统一尾部：渲染当前页 + 异步触发 pageChanged。
    private func render(transitionInfo: NavigationTransitionInfo = SuppressNavigationTransitionInfo()) {
        renderedTheme = App.context.theme
        renderedLanguage = App.context.language
        transition(to: currentView, transitionInfo: transitionInfo)
        Task {
            pageChanged.invoke(self, currentPage)
        }
    }
}
