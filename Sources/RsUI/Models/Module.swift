import Foundation
import WinUI
import WinSDK

/// 模块协议，定义了模块的标准接口
/// 注意：UI 相关的更新（如主题和语言）应由各模块的 UI 组件通过观察 Environment.shared.appearance 自行处理
public protocol Module {
    /// 模块的唯一标识符
    var id: String { get }
    
    /// 默认初始化方法
    init()

    /// 初始化模块
    /// - Parameter context: 模块上下文，提供导航和设置注册等功能
    func initialize(context: ModuleContext)

    func makeSettingsSection() -> WinUI.UIElement?
}

/// 模块初始化时提供的上下文信息
public struct ModuleContext {
    /// 导航操作接口
    public let navigationActions: NavigationActions
    
    /// 注册设置项的回调
    let registerSettingsSection: @Sendable (SettingsSection) -> Void

    /// 窗口句柄
    public let windowHandle: WinSDK.HWND?
    
    init(navigationActions: NavigationActions, registerSettingsSection: @escaping @Sendable (SettingsSection) -> Void, windowHandle: WinSDK.HWND?) {
        self.navigationActions = navigationActions
        self.registerSettingsSection = registerSettingsSection
        self.windowHandle = windowHandle
    }

    /// 注册导航节点
    @discardableResult
    public func registerNavigation(node: NavigationNode, parentId: String? = nil, section: NavigationSection = .menu) -> Bool {
        navigationActions.addNode(node, parentId, section)
    }
}

/// 表示设置页面中的一个分段内容
struct SettingsSection: Sendable {
    /// 分段标题的本地化 Key
    let titleKey: String
    /// 分段所属的模块 ID
    let moduleId: String
    /// 构建分段视图的工厂闭包
    let makeView: @Sendable (PageContext) -> WinUI.UIElement
    
    init(titleKey: String, moduleId: String, makeView: @escaping @Sendable (PageContext) -> WinUI.UIElement) {
        self.titleKey = titleKey
        self.moduleId = moduleId
        self.makeView = makeView
    }
}
