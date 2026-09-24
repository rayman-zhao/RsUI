import Foundation
import WinUI

/// FIXME: Must inherit ProgressRing, otherwise can't be triggered the second change of the observation
public class ProgressRingEx: ProgressRing {
}
extension ProgressRing {
    /// `onChanged` 返回 `false` 则停止观察（true = 继续）。
    @discardableResult
    public func startObserving<Element>(
        _ emit: @escaping @Sendable () -> Element,
        onChanged: @escaping @MainActor (ProgressRing, Element) -> Bool
    ) -> Task<Void, Never> {
        startObservingChanges(on: self, emitting: emit, onChanged: onChanged)
    }
}
