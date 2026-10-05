import Foundation
import UWP
import WinUI

/// 单页面栈容器：拥有一个 `PageModel`（back/forward 历史）+ 一个
/// `PageTransitionHost`（转场渲染），负责把当前 Page 的 header/content 渲染进
/// 转场宿主。
class PageFrame: PageTransitionHost, PageControl {
    private var model: PageModel
    /// 上次渲染时的外观值。`updateAppearance` 在值未变时整体跳过：启动期
    /// `AppearanceWindow` 的初始发射会对每个窗口触发一次 updateAppearance
    ///（其消费端还承担导航菜单与窗口 chrome 的首次构建，不能跳过发射本身），
    /// 若外观未变仍整页重建，会无谓释放刚构建的页面控件——对带有挂起原生
    /// 回调（防抖定时器等）的 COM 聚合子类控件是实测崩溃源（0xC0000005）。
    private var renderedTheme: AppTheme?
    private var renderedLanguage: AppLanguage?

    init(model: PageModel = PageModel()) {
        self.model = model
        super.init()

        render()
    }

    /// 重绑 model 并即时渲染当前页（Suppress 转场）。用于单 `PageFrame` 在多 tab
    /// 间共享的形态（`PageTabView`）：切 tab 时把共享 frame 的 model 重设到目标
    /// tab 的 `PageModel`，并立刻渲染其 currentPage。
    func rebind(to newModel: PageModel) {
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

        render(transitionInfo: transitionInfoOverride)
    }

    func navigate(
        to pages: [Page],
        mode: NavigationOpenMode = .newTab,
        transitionInfoOverride: NavigationTransitionInfo
    ) -> Int {
        for page in pages {
            model.navigate(to: page)
        }

        render(transitionInfo: transitionInfoOverride)
        return pages.count
    }

    func selectPage(matchingURL url: URL) -> Bool {
        return model.currentPage?.url == url
    }

    func updateAppearance() {
        guard App.context.theme != renderedTheme
            || App.context.language != renderedLanguage else { return }
        /// NOTE: A page inplace transition will have problem if some UI Elements been referenced in the Page object.
        /// So that, must remove the page view from visual tree first, then release COM references in event loop,
        /// then add to new visual tree node.
        transition(to: nil)
        Task { @MainActor in
            transition(to: currentPage?.view)
        }
    }

    func updateWindowContext(_ context: WindowContext) {
        model.currentPage?.windowContextDidChange(to: context)
        for page in model.backwardPages + model.forwardPages {
            page.windowContextDidChange(to: context)
        }
    }

    /// mutate model 后的统一尾部：渲染当前页 + 异步触发 pageChanged。
    private func render(transitionInfo: NavigationTransitionInfo = SuppressNavigationTransitionInfo()) {
        renderedTheme = App.context.theme
        renderedLanguage = App.context.language
        transition(to: currentPage?.view, transitionInfo: transitionInfo)
        Task { @MainActor in
            pageChanged.invoke(self, currentPage)
        }
    }
}
