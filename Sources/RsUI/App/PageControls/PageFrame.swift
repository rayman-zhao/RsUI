import Foundation
import UWP
import WinUI

/// 单页面栈容器：拥有一个 `PageModel`（back/forward 历史）+ 一个
/// `PageTransitionHost`（转场渲染），负责把当前 Page 的 header/content 渲染进
/// 转场宿主。
class PageFrame: PageTransitionHost, PageControl {
    private var model: PageModel

    init(model: PageModel = PageModel()) {
        self.model = model
        super.init()

        transition(to: currentPage?.view)
        Task { @MainActor in
            pageChanged.invoke(self, currentPage)
        }
    }

    /// 重绑 model 并即时渲染当前页（Suppress 转场）。用于单 `PageFrame` 在多 tab
    /// 间共享的形态（`PageTabView`）：切 tab 时把共享 frame 的 model 重设到目标
    /// tab 的 `PageModel`，并立刻渲染其 currentPage。
    func rebind(to newModel: PageModel) {
        model = newModel

        transition(to: currentPage?.view)
        Task { @MainActor in
            pageChanged.invoke(self, currentPage)
        }
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

        transition(
            to: currentPage?.view,
            transitionInfo: NavigationTransitionInfo.make(slideEffect: .fromLeft))
        Task { @MainActor in
            pageChanged.invoke(self, currentPage)
        }
    }

    func goForward() {
        model.goForward()

        transition(
            to: currentPage?.view,
            transitionInfo: NavigationTransitionInfo.make(slideEffect: .fromRight))
        Task { @MainActor in
            pageChanged.invoke(self, currentPage)
        }
    }

    func navigate(
        to page: Page,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo
    ) {
        model.navigate(to: page)

        transition(to: currentPage?.view, transitionInfo: transitionInfoOverride)
        Task { @MainActor in
            pageChanged.invoke(self, currentPage)
        }
    }

    func navigate(
        to pages: [Page],
        mode: NavigationOpenMode = .newTab,
        transitionInfoOverride: NavigationTransitionInfo
    ) -> Int {
        for page in pages {
            model.navigate(to: page)
        }

        transition(to: currentPage?.view, transitionInfo: transitionInfoOverride)
        Task { @MainActor in
            pageChanged.invoke(self, currentPage)
        }
        return pages.count
    }

    func selectPage(matchingURL url: URL) -> Bool {
        return model.currentPage?.url == url
    }

    func updateAppearance() {
        transition(to: currentPage?.view)
    }

    func updateWindowContext(_ context: WindowContext) {
        model.currentPage?.windowContextDidChange(to: context)
        for page in model.backwardPages + model.forwardPages {
            page.windowContextDidChange(to: context)
        }
    }
}
