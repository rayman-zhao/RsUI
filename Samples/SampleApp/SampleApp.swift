import Foundation
import WinUI
import RsUI

@main
class SampleApp: App {
    public required init() {
        super.init("SampleCompany", "SampleApp", Bundle.module)
    }

    override func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        AppShared.allModuleTypes = [
            ArbitaryModule.self
        ]

        super.onLaunched(args)
    }
}
