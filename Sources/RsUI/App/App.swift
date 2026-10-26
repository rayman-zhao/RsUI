import Foundation
import RsFoundation
import UWP
import WinAppSDK
import WinUI

open class App: SwiftApplication {
    public nonisolated static let context = AppContext()

    /// App identity consumed before anything else — support directories, preferences
    /// and the single-instance key all derive from it. Overridden by the app subclass;
    /// `nil` keeps the framework defaults.
    nonisolated open class func makeConfiguration() -> AppConfiguration? { nil }

    public nonisolated required init() {
        if let config = Self.makeConfiguration() {
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
