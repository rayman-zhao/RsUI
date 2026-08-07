import Foundation
import WinAppSDK
import WinUI

protocol WindowContextHost: AnyObject {
    var hwnd: WindowId { get }

    var isInFullscreenPage: Bool { get }
    func enterFullscreenPage()
    func exitFullscreenPage()

    func open(
        _ page: Page,
        mode: NavigationOpenMode,
        transitionInfoOverride: NavigationTransitionInfo?
    )
    @discardableResult func open(
        _ pages: [Page],
        mode: NavigationOpenMode,
        transitionInfoOverride: NavigationTransitionInfo?
    ) -> Int
    func selectPage(matchingURL url: URL) -> Bool
}
