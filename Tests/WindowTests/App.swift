import WinUI
@testable import RsUI

@main
final class App: SwiftApplication {
    public required init() {
        super.init()
    }

    override func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        try! NavigatableWindow().activate()
    }
}
