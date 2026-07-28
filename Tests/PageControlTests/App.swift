import WinUI

@main
final class App: SwiftApplication {
    public required init() {
        super.init()
    }

    override func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        let window = PageFrameTestWindow()
        try! window.activate()

        let window2 = TabViewPageFrameTestWindow()
        try! window2.activate()
    }
}
