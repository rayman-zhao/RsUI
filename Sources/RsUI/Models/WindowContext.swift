import Foundation
import WinUI
import WinSDK
import RsHelper

/// 模块初始化时提供的上下文信息
public class WindowContext {
    /// 导航操作接口
    public let navigationActions: NavigationActions

    /// 窗口句柄
    public let windowHandle: WinSDK.HWND?
    
    init(navigationActions: NavigationActions, windowHandle: WinSDK.HWND?) {
        self.navigationActions = navigationActions
        self.windowHandle = windowHandle
    }

    /// 注册导航节点
    @discardableResult
    public func registerNavigation(node: NavigationNode, parentId: String? = nil, section: NavigationSection = .menu) -> Bool {
        navigationActions.addNode(node, parentId, section)
    }
}
