import Foundation
import WinUI
import RsHelper

open class App: SwiftApplication {
    public static var context: AppContext!

    let group: String
    let product: String
    let bundle: Bundle
    let modules: [Module.Type]

    public required convenience init() {
        self.init("SwiftWorks", "RsUI", .main, [])
    }

    public init(_ group: String, _ product: String, _ bundle: Bundle, _ modules: [Module.Type]) {
        self.group = group
        self.product = product
        self.bundle = bundle
        self.modules = modules

        super.init()
    }
    
    override open func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        // Need to init context after super.init() because some WinUI APIs require the application to be initialized
        App.context = AppContext(group, product, bundle)
        
        AppShared.allModuleTypes = modules

        let mainWindow = MainWindow()
        try! mainWindow.activate()
    }
}

