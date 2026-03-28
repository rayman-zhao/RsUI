import Foundation
import WinUI
import RsHelper

/// 模块协议，定义了模块的标准接口
public protocol Module : ExpressibleByEmptyLiteral {
    /// 模块的唯一标识符
    var id: String { get }

    func titleBarRightHeaderItemRequired(in context: WindowContext) -> UIElement?
    func navigationViewMenuItemsRequired(in context: WindowContext) -> [NavigationViewItemBase]
    func navigationViewFooterMenuItemsRequired(in context: WindowContext) -> [NavigationViewItemBase]
    func settingsGroupRequired() -> (label: String, cards: [UIElement])?

    func navigationRequested(for url: URL, in context: WindowContext) -> Page?
}

public extension Module {
    func titleBarRightHeaderItemRequired(in context: WindowContext) -> UIElement? {
        return nil
    }
    func navigationViewMenuItemsRequired(in context: WindowContext) -> [NavigationViewItemBase] {
        return []
    }
    func navigationViewFooterMenuItemsRequired(in context: WindowContext) -> [NavigationViewItemBase] {
        return []
    }
    func settingsGroupRequired() -> (label: String, cards: [UIElement])? {
        return nil
    }

    func navigationRequested(for url: URL, in context: WindowContext) -> Page? {
        return nil
    }
}
