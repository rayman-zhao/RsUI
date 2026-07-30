import WinUI
@testable import RsUI

@main
final class App: SwiftApplication {
    public required init() {
        super.init()
    }

    override func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        let window = NavigatableWindow()
        window.useMicaBackdrop()
        window.useRestoration()
        try! window.activate()
    }
}
