import Foundation
import Observation
import WinUI

public protocol Page: AnyObject {
    var url: URL { get }
    var header: Any? { get }
    var content: UIElement { get }
}

public extension Page {
    var header: Any? { nil }

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
