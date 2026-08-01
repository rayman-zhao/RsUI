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
                toggle.content = "Enter Fullscreen"
            } else {
                window.enterFullscreen(for: toggle)
                toggle.content = "Exit Fullscreen (Esc)"
            }
        }

        window.ui.navigationView.content = toggle
        try! window.activate()
    }
}
