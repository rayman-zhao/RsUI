import Foundation
import RsFoundation
import WinUI

#if DEBUG
    @testable import RsUI
#else
    import RsUI
#endif

@main
final class App: SwiftApplication {
    public required init() {
        super.init()
    }

    override func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        // IVLT=1 时运行 ItemsView 生命周期自驱动测试（跑完自动 exit()，
        // 不与其他手测窗口共存），用于 crash 隔离与回归验证。
        if ProcessInfo.processInfo.environment["IVLT"] == "1" {
            activate(ItemsViewLifecycleTestWindow())
            return
        }
        // RLT=1 时运行 useRestoration 窗口生命周期自驱动测试（同上自动 exit()），
        // 验证关窗后窗口可回收。
        #if DEBUG
            if ProcessInfo.processInfo.environment["RLT"] == "1" {
                RestorationLifecycleTestWindow.run()
                return
            }
        #endif
        testWindow()
        testFullScreen()
    }

    private func activate(_ window: some WinUI.Window) {
        do {
            try window.activate()
        } catch {
            log.error("failed to activate \(type(of: window)): \(error)")
        }
    }

    private func testWindow() {
        #if DEBUG
            let window = NavigationViewWindow()
            window.useMicaBackdrop()
            window.useRestoration()
            activate(window)
        #endif
    }

    private func testFullScreen() {
        #if DEBUG
            let window = NavigationViewWindow()
            window.title = "WindowTests — Element Fullscreen"

            let toggle = Button()
            toggle.content = "Enter Fullscreen"
            toggle.horizontalAlignment = .center
            toggle.verticalAlignment = .center

            toggle.click.addHandler { [weak window] _, _ in
                guard let window else { return }
                if window.isInFullscreen {
                    window.exitFullscreen()
                } else {
                    window.enterFullscreen(for: toggle)
                }
            }

            window.ui.navigationView.content = toggle
            window.fullscreenChanged.addHandler { _, isInFullscreen in
                if isInFullscreen {
                    toggle.content = "Exit Fullscreen (Esc)"
                } else {
                    toggle.content = "Enter Fullscreen"
                }
            }
            activate(window)
        #endif
    }
}
