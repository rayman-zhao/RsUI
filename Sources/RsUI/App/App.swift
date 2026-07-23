import Foundation
import WinUI
import RsFoundation

open class App: SwiftApplication {
    public static let context = AppContext()

    // Stable across releases — the taskbar uses this to identify the app
    // (pinning, jump list lookup) and it doubles as the single-instance key.
    // Don't change once shipped.
    private var appUserModelID: String { "\(App.context.groupName).\(App.context.productName)" }
    private let appInstanceCoordinator = AppInstanceCoordinator()

    public required init() {
        super.init()
    }

    public init(group: String, product: String, resourceBundle: Bundle, moduleTypes: [Module.Type]) {
        App.context.bootstrap(group: group, product: product, resourceBundle: resourceBundle, moduleTypes: moduleTypes)
        super.init()
    }

    override open func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        if appInstanceCoordinator.redirectIfSecondary(key: appUserModelID) { return }

        // Need to bootstrap context to GUI after super.init() because some WinUI APIs require the application to be initialized
        App.context.bootstrapGUI()
        App.context.initializeModules()

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
        App.context.releaseModules()
    }
}
