import Foundation
import RsUI
// @main 的 main() 见证方法在 WinUI.SwiftApplication，不导入则 Swift 6.4 起告警
import WinUI

@main
class SampleApp: App {
    required init() {
        super.init(
            group: "SampleCompany", product: "SampleApp", resourceBundle: Bundle.module,
            moduleTypes: [SampleModule.self])
    }
}
