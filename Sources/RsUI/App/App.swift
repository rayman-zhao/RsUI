import Foundation
import RsFoundation
import UWP
import WinAppSDK
import WinUI

open class App: SwiftApplication {
    public nonisolated static let context = AppContext()

    /// App identity — support directories, preferences and the single-instance key
    /// all derive from it. Override to declare your app's identity; the default keeps
    /// the framework's own. Read once in `init`, before anything else.
    open class var configuration: AppConfiguration {
        AppConfiguration(group: "SwiftWorks", product: "RsUI", resourceBundle: .main)
    }

    public nonisolated required init() {
        // App 构造发生在主线程（SwiftApplication 启动链，同 SettingsCard 构造器
        // 兑换先例）；@MainActor 的 configuration 在闭包内读取并消费，子类由此
        // 免写任何隔离关键字
        MainActor.assumeIsolated {
            let config = Self.configuration
            App.context.bootstrap(
                group: config.group, product: config.product,
                resourceBundle: config.resourceBundle)
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

    /// Modules constructed by the app subclass. Called in `onLaunched` (MainActor,
    /// context ready) — modules may depend on `App.context` at construction, so the
    /// framework asks for instances only once the context is bootstrapped.
    open func makeModules() -> [any Module] { [] }

    override open func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        // Application.current.requestedTheme can be used only start from launch.
        App.context.bootstrapGUI()
        App.context.loadModules(makeModules())

        JumpList.register(
            arguments: "--new-window", displayName: App.context.tr("newWindow"),
            logo: App.context.iconAppxUri)

        try? MainWindow(urls: App.context.route.lastPageURL.map { [$0] } ?? []).activate()
    }

    open func onActivated(_ args: AppActivationArguments?) {
        try? MainWindow().activate()
    }

    override open func onShutdown(exitCode: Int32) {
        App.context.releaseModules()
    }
}
