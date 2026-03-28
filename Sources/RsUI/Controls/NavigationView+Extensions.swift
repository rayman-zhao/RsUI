import WinUI

public extension NavigationView {
    func selectFirstItem() {
        for item in self.menuItems {
            if item is NavigationViewItem {
                self.selectedItem = item
                return
            }
        }
        for item in self.footerMenuItems {
            if item is NavigationViewItem {
                self.selectedItem = item
                return
            }
        }
        if self.isSettingsVisible, let item = (self.settingsItem as? NavigationViewItem) {
            item.isSelected = true
        }
    }
}
