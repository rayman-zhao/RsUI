import Foundation
import RsFoundation
import WinUI

public protocol Module: ExpressibleByEmptyLiteral {
    var id: String { get }

    func titleBarRightHeaderItem(in context: WindowContext) -> UIElement?
    func navigationViewMenuItems(in context: WindowContext) -> [NavigationViewItemBase]
    func navigationViewFooterMenuItems(in context: WindowContext) -> [NavigationViewItemBase]
    func settingsGroup() -> (title: String, cards: [UIElement])?

    func onNavigationRequested(for url: URL, in context: WindowContext) -> Page?
}

extension Module {
    public func titleBarRightHeaderItem(in context: WindowContext) -> UIElement? {
        return nil
    }
    public func navigationViewMenuItems(in context: WindowContext)
        -> [NavigationViewItemBase]
    {
        return []
    }
    public func navigationViewFooterMenuItems(in context: WindowContext)
        -> [NavigationViewItemBase]
    {
        return []
    }
    public func settingsGroup() -> (title: String, cards: [UIElement])? {
        return nil
    }

    public func onNavigationRequested(for url: URL, in context: WindowContext) -> Page? {
        return nil
    }
}
