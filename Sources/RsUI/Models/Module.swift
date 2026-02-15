import Foundation
import WinUI
import WinSDK

/// 模块协议，定义了模块的标准接口
/// 注意：UI 相关的更新（如主题和语言）应由各模块的 UI 组件通过观察 Environment.shared.appearance 自行处理
public protocol Module {
    /// 模块的唯一标识符
    var id: String { get }

    /// 初始化模块
    /// - Parameter context: 模块上下文，提供导航和设置注册等功能
    func initialize(context: WindowContext)

    func makeNavigationViewItems() -> [NavigationViewItem]
    func makeSettingsSection() -> UIElement?
}
