import Foundation
import RsFoundation
import UWP
import WinAppSDK
import WinUI

open class App: SwiftApplication, @unchecked Sendable {
    public nonisolated static let context = AppContext()

    /// App identity — support directories, preferences and the single-instance key
    /// all derive from it. Override to declare your app's identity; the default keeps
    /// the framework's own. Read once in `init`, before anything else.
    open class var groupName: String { "SwiftWorks" }
    open class var productName: String { "RsUI" }
    open class var resourceBundle: Bundle { .main }
    /// Modules constructed by the app subclass. Read once in `onLaunched` (MainActor,
    /// context ready) — modules may depend on `App.context` at construction. Each
    /// access constructs fresh instances; the framework reads it exactly once.
    open class var modules: [any Module] { [] }

    public nonisolated required init() {
        // App 构造发生在主线程（SwiftApplication 启动链，同 SettingsCard 构造器
        // 兑换先例）；@MainActor 的身份 class var 在闭包内读取并消费，子类由此
        // 免写任何隔离关键字
        MainActor.assumeIsolated {
            App.context.bootstrap(group: Self.groupName, product: Self.productName, resourceBundle: Self.resourceBundle)
        }
        super.init()

        // AppInstance can be used start from app initilization.
        AppInstance.redirectOrRegister(
            for: "\(App.context.groupName)/\(App.context.productName)"
        ) { [weak self] args in
            guard let self else { return }
            self.onActivated(args)
        }
    }

    override open func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        // Application.current.requestedTheme can be used only start from launch.
        App.context.bootstrapGUI()
        App.context.loadModules(Self.modules)

        JumpList.register(
            arguments: "--new-window", displayName: App.context.tr("newWindow"),
            logo: App.context.iconAppxUri)

        try? MainWindow(urls: App.context.route.lastPageURL.map { [$0] } ?? []).activate()
    }

    override open func onShutdown(exitCode: Int32) {
        App.context.releaseModules()
    }

    open func onActivated(_ args: AppActivationArguments?) {
        try? MainWindow().activate()
    }
}
