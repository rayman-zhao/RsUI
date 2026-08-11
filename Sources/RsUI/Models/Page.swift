import Foundation
import Observation
import WinUI

public protocol Page: AnyObject {
    var url: URL { get }
    var header: Any? { get }
    var title: String { get }
    var content: UIElement { get }

    /// Callback when the page is moved to another window (tab tear-out or
    /// merge), or the window enter/exit fullscreen state.
    ///
    /// A page that caches WindowContext should update it here, and change button
    /// text or icon for fullscreen state.
    func windowContextDidChange(to context: WindowContext)
}

extension Page {
    public var header: Any? { nil }

    public func windowContextDidChange(to context: WindowContext) {}

    public func startObserving<Element>(
        _ emit: @escaping @Sendable () -> Element,
        onChanged: @escaping @MainActor (Page, Element) -> Void
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
}
