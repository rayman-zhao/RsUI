import Foundation
import WinAppSDK
import WinUI

@MainActor protocol WindowContextHost: AnyObject {
    /// 窗口已关闭（appWindow 释放）后为 nil —— 调用方应放弃依赖窗口句柄的操作。
    var hwnd: WindowId? { get }
    var xamlRoot: XamlRoot { get }

    var isInFullscreenPage: Bool { get }
    func enterFullscreenPage()
    func exitFullscreenPage()

    func open(
        _ page: Page,
        mode: NavigationOpenMode,
        transitionInfoOverride: NavigationTransitionInfo
    )
    @discardableResult func open(
        _ pages: [Page],
        mode: NavigationOpenMode,
        transitionInfoOverride: NavigationTransitionInfo
    ) -> Int
    func selectPage(matchingURL url: URL) -> Bool

    /// 页面主动请求重读视图(header/content 形态翻转);按页路由
    func updateView(of page: Page)
}
