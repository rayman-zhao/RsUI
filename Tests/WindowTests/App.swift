import WinUI
@testable import RsUI

@main
final class App: SwiftApplication {
    public required init() {
        super.init()
    }

    override func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        testWindow()
        testFullScreen()
    }

    private func testWindow() {
        let window = NavigationViewWindow()
        window.useMicaBackdrop()
        window.useRestoration()
        try! window.activate()
    }

    private func testFullScreen() {
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
        window.fullscreenChanged.addHandler { window in
            if window.isInFullscreen {
                toggle.content = "Exit Fullscreen (Esc)"
            } else {
                toggle.content = "Enter Fullscreen"
            }
        }
        try! window.activate()
    }
}
