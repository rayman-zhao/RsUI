import Foundation
import RsUI
// @main 的 main() 见证方法在 WinUI.SwiftApplication，不导入则 Swift 6.4 起告警
import WinUI

@main
class SampleApp: App, @unchecked Sendable {
    // defaultIsolation 会为继承的 nonisolated required 构造器合成 MainActor 覆写
    // （隔离冲突），显式转发一份保持一致；配置与模块均不经构造器传递
    nonisolated required init() {
        super.init()
    }

    override class var configuration: AppConfiguration {
        AppConfiguration(
            group: "SampleCompany", product: "SampleApp", resourceBundle: Bundle.module)
    }

    override class var modules: [any Module] {
        [SampleModule()]
    }
}
