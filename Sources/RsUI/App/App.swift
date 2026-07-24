import Foundation
import RsFoundation
import WinAppSDK
import WinUI

open class App: SwiftApplication {
    public static let context = AppContext()

    public required init() {
        super.init()
    }

    public init(group: String, product: String, resourceBundle: Bundle, moduleTypes: [Module.Type])
    {
        App.context.bootstrap(
            group: group, product: product, resourceBundle: resourceBundle, moduleTypes: moduleTypes
        )
        super.init()

        coordinateSingleInstance()
    }

    override open func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        // Application.current.requestedTheme can be used only start from launch.
        App.context.bootstrapGUI()
        App.context.initializeModules()

        TaskbarNewWindow.register(title: App.context.tr("newWindow"))

        let mainWindow =
            launchHasFlag("--new-window", args) ? MainWindow(forceHomeOnLaunch: true) : MainWindow()
        try! mainWindow.activate()
    }
    
    open func onActivated(_ args: AppActivationArguments?) {
        MainWindow.openDetachedWindowAtHome()
    }

    override open func onShutdown(exitCode: Int32) {
        App.context.releaseModules()
    }

    private func coordinateSingleInstance() {
        // Register instance.
        let key = "\(App.context.groupName)/\(App.context.productName)"
        guard let instance = try? AppInstance.findOrRegisterForKey(key)  // AppInstance can be used start from initilization.
        else {
            fatalError("Failed to findOrRegister AppInstance.")
        }

        // Single instance check.
        guard instance.isCurrent else {
            if let args = try? instance.getActivatedEventArgs(),
                let asyncResult = try? instance.redirectActivationToAsync(args)
            {
                Task {
                    try? await asyncResult.get()
                }
            }
            log.info("Exit later instance.")
            Foundation.exit(0)
        }

        // Responese to activated event.
        instance.activated.addHandler { [weak self] _, args in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onActivated(args)
            }
        }
    }

    private func launchHasFlag(_ flag: String, _ args: WinUI.LaunchActivatedEventArgs) -> Bool {
        if CommandLine.arguments.contains(flag) {
            return true
        }
        return args.arguments.split(separator: " ").contains { $0 == flag }
    }
}
