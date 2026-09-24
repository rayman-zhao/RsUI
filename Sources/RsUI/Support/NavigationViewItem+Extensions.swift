import Foundation
import Observation
import WinAppSDK
import WinUI
import WindowsFoundation

extension NavigationViewItem {
    /// `onChanged` 返回 `false` 则停止观察（true = 继续）。
    @discardableResult
    public func startObserving<Element>(
        _ emit: @escaping @Sendable () -> Element,
        onChanged: @escaping @MainActor (NavigationViewItem, Element) -> Bool
    ) -> Task<Void, Never> {
        startObservingChanges(on: self, emitting: emit, onChanged: onChanged)
    }

    public static func build(iconGlyph: String, label: String, url: String) -> NavigationViewItem {
        let icon = FontIcon()
        icon.glyph = iconGlyph

        let item = NavigationViewItem()
        item.icon = icon
        item.content = label
        item.tag = try? HString(url)
        return item
    }
}
