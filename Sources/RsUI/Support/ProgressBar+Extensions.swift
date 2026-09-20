import Foundation
import WinUI

/// FIXME: Must inherit ProgressBar, otherwise can't be triggered the second change of the observation
public class ProgressBarEx: ProgressBar {
}
extension ProgressBar {
    @discardableResult
    public func startObserving<Element>(
        _ emit: @escaping @Sendable () -> Element,
        onChanged: @escaping @MainActor (ProgressBar, Element) -> Void
    ) -> Task<Void, Never> {
        startObservingChanges(on: self, emitting: emit, onChanged: onChanged)
    }
}
