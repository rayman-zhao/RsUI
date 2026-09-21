import Foundation
import RsFoundation
import WinUI

public protocol Module: ExpressibleByEmptyLiteral {
    var id: String { get }

    func titleBarRightHeaderItem(in context: WindowContext) -> UIElement?
    func navigationViewMenuItems(in context: WindowContext) -> [NavigationViewItemBase]
    func navigationViewFooterMenuItems(in context: WindowContext) -> [NavigationViewItemBase]
    func settingsGroup() -> SettingsGroup?

    func navigationDidRequest(for url: URL, in context: WindowContext) -> Page?
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
    public func settingsGroup() -> SettingsGroup? {
        return nil
    }

    public func navigationDidRequest(for url: URL, in context: WindowContext) -> Page? {
        return nil
    }
}
