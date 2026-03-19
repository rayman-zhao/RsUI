import Foundation
import Observation
import WinUI

public protocol View: AnyObject {
    var body: UIElement { get }
}

public extension View {
    func startObserving<Element>(_ emit: @escaping @Sendable () -> Element, onChanged: @escaping @MainActor (View, Element) -> Void) {
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
