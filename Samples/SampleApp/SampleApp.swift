import Foundation
import RsUI
// @main 的 main() 见证方法在 WinUI.SwiftApplication，不导入则 Swift 6.4 起告警
import WinUI

@main
class SampleApp: App {
    nonisolated convenience required init() {
        // Module 协议是 @MainActor，元类型数组需在主 actor 上下文取用
        let moduleTypes = MainActor.assumeIsolated { () -> [Module.Type] in [SampleModule.self] }
        self.init(
            group: "SampleCompany", product: "SampleApp", resourceBundle: Bundle.module,
            moduleTypes: moduleTypes)
    }

    // defaultIsolation 会为未覆写的 nonisolated 指定构造器合成 MainActor 覆写（冲突），
    // 显式转发一份以保持隔离一致
    nonisolated override init(group: String, product: String, resourceBundle: Bundle, moduleTypes: [Module.Type]) {
        super.init(group: group, product: product, resourceBundle: resourceBundle, moduleTypes: moduleTypes)
    }
}
