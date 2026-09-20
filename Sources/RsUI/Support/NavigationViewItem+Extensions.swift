import Foundation
import Observation
import WinAppSDK
import WinUI
import WindowsFoundation

extension NavigationViewItem {
    @discardableResult
    public func startObserving<Element>(
        _ emit: @escaping @Sendable () -> Element,
        onChanged: @escaping @MainActor (NavigationViewItem, Element) -> Void
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
