import Foundation
import Observation
import WinAppSDK
import WinUI
import WindowsFoundation

extension NavigationViewItem {
    public func startObserving<Element>(
        _ emit: @escaping @Sendable () -> Element,
        onChanged: @escaping @MainActor (NavigationViewItem, Element) -> Void
    ) {
        let obs = Observations(emit)

        Task { [weak self] in
            for await value in obs {
                guard let self else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    onChanged(self, value)
                }
            }
        }
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
