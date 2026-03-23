import Foundation
import WinUI
import RsHelper

open class App: SwiftApplication {
    public static var context: AppContext!

    let group: String
    let product: String
    let bundle: Bundle
    let moduleTypes: [Module.Type]

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
    
    override open func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        // Need to init context after super.init() because some WinUI APIs require the application to be initialized
        App.context = AppContext(group, product, bundle)
        App.context.modules = moduleTypes.map { $0.init() }

        let mainWindow = MainWindow()
        try! mainWindow.activate()
    }

    override open func onShutdown(exitCode: Int32) {
        App.context = nil
    }
}
