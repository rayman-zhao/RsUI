import Foundation
import WinUI

protocol PageControl {
    var currentPage: Page? { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }

    var rootView: FrameworkElement { get }
    var fullscreenView: UIElement { get }

    var pageChanged: EventWithArgumentHandler<PageControl, Page?> { get }

    func goBack()
    func goForward()
    func navigate(
        to page: Page,
        mode: NavigationOpenMode,
        transitionInfoOverride: NavigationTransitionInfo?
    )
    func navigate(
        to pages: [Page],
        mode: NavigationOpenMode,
        transitionInfoOverride: NavigationTransitionInfo?
    ) -> Int
    func selectPage(matchingURL url: URL) -> Bool

    func updateAppearance()
    func updateWindowContext(_ context: WindowContext)
}
