import Foundation
import WinUI
import WindowsFoundation

extension NavigationView {
    public func selectFirstItem() {
        if let firstItem = self.first(where: { _ in true }) {
            self.selectedItem = firstItem
        } else {
            selectSettingsItem()
        }
    }

    public func selectItem(with url: URL) {
        if url == SettingsPage.url {
            selectSettingsItem()
        } else if let item = self.first(where: { item in item.url == url }) {
            if !item.isSelected {
                item.isSelected = true
            }
        } else if self.selectedItem != nil {
            self.selectedItem = nil
        }
    }

    public var firstItemURL: URL? {
        if let item = self.first(where: { item in item.url != nil }) {
            return item.url
        } else {
            return SettingsPage.url
        }
    }

    private func selectSettingsItem() {
        if self.isSettingsVisible, let item = (self.settingsItem as? NavigationViewItem),
            !item.isSelected
        {
            item.isSelected = true
        }
    }

    private func first(where predicate: (NavigationViewItem) -> Bool) -> NavigationViewItem? {
        return first(where: predicate, in: self.menuItems)
            ?? first(where: predicate, in: self.footerMenuItems)
    }

    private func first(where predicate: (NavigationViewItem) -> Bool, in items: AnyIVector<Any?>?)
        -> NavigationViewItem?
    {
        guard let items else { return nil }

        for item in items {
            if let navItem = item as? NavigationViewItem {
                if predicate(navItem) {
                    return navItem
                } else if let subitem = first(where: predicate, in: navItem.menuItems) {
                    return subitem
                }
            }
        }
        return nil
    }
}
