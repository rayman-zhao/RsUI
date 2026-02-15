import Foundation
import WinUI
import RsUI

@main
class SampleApp: App {
    public required init() {
        super.init("SampleCompany", "SampleApp", Bundle.module, [ArbitaryModule()])
    }
}
