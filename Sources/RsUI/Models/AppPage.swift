import Foundation
import WinUI
import WinSDK

/// 所有页面必须遵循的协议，用于在 MainWindow 框架内显示页面
public protocol AppPage: AnyObject {
    /// 页面的根视图元素，将被附加到框架中
    var rootView: WinUI.UIElement { get }

    func onAppearanceChanged()
}

extension AppPage {
    func onAppearanceChanged() {}
}

/// 页面初始化时需要的依赖项集合
public struct PageContext: @unchecked Sendable {
    let viewModel: MainWindowViewModel
    public let currentTheme: AppTheme
    public let currentLanguage: AppLanguage
    public let navigationActions: NavigationActions
    public let windowHandle: WinSDK.HWND?
}

/// 提供给页面的导航操作封装
public struct NavigationActions: Sendable {
    public typealias AddNodeHandler = @Sendable (_ node: NavigationNode, _ parentId: String?, _ section: NavigationSection) -> Bool
    public typealias RemoveNodeHandler = @Sendable (_ nodeId: String, _ section: NavigationSection?) -> Bool
    public typealias RebuildHandler = @Sendable () -> Void

    /// 添加导航节点
    public let addNode: AddNodeHandler
    /// 删除导航节点
    public let removeNode: RemoveNodeHandler
    /// 重建导航栏 UI
    public let rebuild: RebuildHandler

    /// 空操作，用于上下文不可用的情况
    static let noop = NavigationActions(
        addNode: { _, _, _ in false },
        removeNode: { _, _ in false },
        rebuild: {}
    )
}
