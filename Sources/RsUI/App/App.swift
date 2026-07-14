import Foundation
import WinUI
import RsFoundation

open class App: SwiftApplication {
    public static var context = AppContext.cli()

    let group: String
    let product: String
    let bundle: Bundle
    let moduleTypes: [Module.Type]

    private let appInstanceCoordinator = AppInstanceCoordinator()

    public required convenience init() {
        self.init("SwiftWorks", "RsUI", .main, [])
    }

    public init(_ group: String, _ product: String, _ bundle: Bundle, _ moduleTypes: [Module.Type]) {
        self.group = group
        self.product = product
        self.bundle = bundle
        self.moduleTypes = moduleTypes

        super.init()
    }

    // Stable across releases — the taskbar uses this to identify the app
    // (pinning, jump list lookup) and it doubles as the single-instance key.
    // Don't change once shipped.
    private var appUserModelID: String { "\(group).\(product)" }

    override open func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        if appInstanceCoordinator.redirectIfSecondary(key: appUserModelID) { return }

        // Need to init context after super.init() because some WinUI APIs require the application to be initialized
        App.context = AppContext.gui(group, product, bundle)
        App.context.modules = moduleTypes.map { $0.init() }

        TaskbarNewWindow.register(title: App.context.tr("newWindow"))

        let mainWindow = launchHasFlag("--new-window", args) ? MainWindow(forceHomeOnLaunch: true) : MainWindow()
        try! mainWindow.activate()

        // Primary instance: open a Home window in-process for each redirected launch.
        appInstanceCoordinator.observe(uiQueue: mainWindow.dispatcherQueue) {
            MainWindow.openDetachedWindowAtHome()
        }
    }

    private func launchHasFlag(_ flag: String, _ args: WinUI.LaunchActivatedEventArgs) -> Bool {
        if CommandLine.arguments.contains(flag) {
            return true
        }
        return args.arguments.split(separator: " ").contains { $0 == flag }
    }

    override open func onShutdown(exitCode: Int32) {
        // Allow modules to deinit
        App.context.modules = []
    }
}
