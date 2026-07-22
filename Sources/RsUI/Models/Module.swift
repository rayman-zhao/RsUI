import Foundation
import RsFoundation
import WinUI

/// 模块协议，定义了模块的标准接口
public protocol Module: ExpressibleByEmptyLiteral {
    /// 模块的唯一标识符
    var id: String { get }

    func titleBarRightHeaderItemRequired(in context: WindowContext) -> UIElement?
    func navigationViewMenuItemsRequired(in context: WindowContext) -> [NavigationViewItemBase]
    func navigationViewFooterMenuItemsRequired(in context: WindowContext)
        -> [NavigationViewItemBase]
    func settingsGroupRequired() -> (title: String, cards: [UIElement])?

    func navigationRequested(for url: URL, in context: WindowContext) -> Page?
}

extension Module {
    public func titleBarRightHeaderItemRequired(in context: WindowContext) -> UIElement? {
        return nil
    }
    public func navigationViewMenuItemsRequired(in context: WindowContext)
        -> [NavigationViewItemBase]
    {
        return []
    }
    public func navigationViewFooterMenuItemsRequired(in context: WindowContext)
        -> [NavigationViewItemBase]
    {
        return []
    }
    public func settingsGroupRequired() -> (title: String, cards: [UIElement])? {
        return nil
    }

    public func navigationRequested(for url: URL, in context: WindowContext) -> Page? {
        return nil
    }
}
