import Foundation
import WinUI

/// FIXME: Must inherit ProgressRing, otherwise can't be triggered the second change of the observation
public class ProgressRingEx: ProgressRing {
}
extension ProgressRing {
    @discardableResult
    public func startObserving<Element>(
        _ emit: @escaping @Sendable () -> Element,
        onChanged: @escaping @MainActor (ProgressRing, Element) -> Void
    ) -> Task<Void, Never> {
        startObservingChanges(on: self, emitting: emit, onChanged: onChanged)
    }
}
