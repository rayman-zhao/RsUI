import Foundation
import WinUI
import RsUI

@main
class SampleApp: App {
    public required init() {
        super.init(group: "SampleCompany", product: "SampleApp", resourceBundle: Bundle.module, moduleTypes: [ArbitaryModule.self])
    }
}
