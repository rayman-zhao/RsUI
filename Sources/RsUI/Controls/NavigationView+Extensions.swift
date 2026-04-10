
import Foundation
import WindowsFoundation
import WinUI

public extension NavigationView {
    func selectFirstItem() {
        if let firstItem = self.first(where: { _ in true }) {
            self.selectedItem = firstItem
        } else {
            selectSettingsItem()
        }
    }

    func selectItem(with url: URL) {
        if url == SettingsPage.url {
            selectSettingsItem()
        } else {
            let urlString = url.absoluteString
            let firstItem = self.first(where: { item in
                if let tag = item.tag, let str = tag as? HString {
                    return String(hString: str) == urlString
                }
                return false
            })
            self.selectedItem = firstItem
        }
    }

    private func selectSettingsItem() {
        if self.isSettingsVisible, let item = (self.settingsItem as? NavigationViewItem) {
            item.isSelected = true
        }
    }

    private func first(where predicate: (NavigationViewItem) -> Bool) -> NavigationViewItem? {
        return first(where: predicate, in: self.menuItems) ?? first(where: predicate, in: self.footerMenuItems)
    }

    private func first(where predicate: (NavigationViewItem) -> Bool, in items: AnyIVector<Any?>?) -> NavigationViewItem? {
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
