import Foundation
import RsFoundation
import UWP
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

        // AppInstance can be used start from app initilization.
        AppInstance.redirectOrRegister(for: "\(group)/\(product)") { [weak self] _, args in
            guard let self else { return }
            self.onActivated(args)
        }
    }

    override open func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        // Application.current.requestedTheme can be used only start from launch.
        App.context.bootstrapGUI()
        App.context.initializeModules()

        JumpList.register(
            arguments: "--new-window", displayName: App.context.tr("newWindow"),
            logo: App.context.iconAppxUri)

        if let url = App.context.route.lastPageURL {
            try? MainWindow(urls: [url]).activate()
        } else {
            try? MainWindow().activate()
        }
    }

    open func onActivated(_ args: AppActivationArguments?) {
        try? MainWindow().activate()
    }

    override open func onShutdown(exitCode: Int32) {
        App.context.releaseModules()
    }

    private func launchHasFlag(_ flag: String, _ args: WinUI.LaunchActivatedEventArgs) -> Bool {
        if CommandLine.arguments.contains(flag) {
            return true
        }
        return args.arguments.split(separator: " ").contains { $0 == flag }
    }
}
