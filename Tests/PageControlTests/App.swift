import WinUI

@main
final class App: SwiftApplication {
    public required init() {
        super.init()
    }

    override func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        // 同一窗体类型按 mode 实例化 PageControl 的两种实现（PageFrame / PageTabView），
        // 验证二者已统一到 `PageControl` 协议。
        try! PageControlTestWindow(mode: .frame).activate()
        try! PageControlTestWindow(mode: .tabView).activate()

        // frame-per-tab 形态的独立手测窗口（不走 PageControl 协议；演示 WinUI
        // TabView + 每 tab 一个 PageFrame 的另一形态）。
        try! TabViewPageFrameTestWindow().activate()
    }
}
