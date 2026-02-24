import Foundation
import WinUI
import WinSDK

/// 模块协议，定义了模块的标准接口
public protocol Module {
    /// 模块的唯一标识符
    var id: String { get }

    func register(in context: WindowContext)

    func registerNavigationViewItems(in context: WindowContext) -> [NavigationViewItem]

    func makeNavigationTarget(for selectedItemTag: Any) -> (header: UIElement?, page: AppPage)?
    func makeSettingsCard() -> UIElement?
}

public extension Module {
    func register(in context: WindowContext) {        
    }

    func registerNavigationViewItems(in context: WindowContext) -> [NavigationViewItem] {
        return []
    }

    func makeNavigationTarget(for selectedItemTag: Any) -> (header: UIElement?, page: AppPage)? {
        return nil
    }

    func makeSettingsCard() -> UIElement? {
        return nil
    }
}
