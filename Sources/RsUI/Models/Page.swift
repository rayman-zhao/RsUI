import Foundation
import Observation
import WinUI

public protocol Page: AnyObject {
    var url: URL { get }
    var header: Any? { get }
    var title: String { get }
    var content: UIElement { get }

    // Called when the page's tab is moved to another window (tab tear-out or
    // merge). A page that caches window-scoped state from its WindowContext
    // should rebind it here, else calls like fullscreen act on the old window.
    func windowContextChanged(_ context: WindowContext)
}

public extension Page {
    var header: Any? { nil }

    func windowContextChanged(_ context: WindowContext) {}

    func startObserving<Element>(_ emit: @escaping @Sendable () -> Element, onChanged: @escaping @MainActor (Page, Element) -> Void) {
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
