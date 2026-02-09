import Foundation
import WinUI

open class App: SwiftApplication {
    public static var context: AppContext!

    public required convenience init() {
        self.init("SwiftWorks", "RsUI", .main)
    }

    public init(_ group: String, _ product: String, _ bundle: Bundle) {
        App.context = AppContext(group, product, bundle)
        
        super.init()
    }
    
    override open func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        let mainWindow = MainWindow()
        try! mainWindow.activate()
    }
}

