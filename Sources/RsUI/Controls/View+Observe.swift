import Foundation
import Observation

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
