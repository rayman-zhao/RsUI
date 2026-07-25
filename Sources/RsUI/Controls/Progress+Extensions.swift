import Foundation
import Observation
import WinUI

/// FIXME: Must inherit ProgressRing/Bar, otherwise can't be triggered the second change of the observation
public class ProgressRingEx: ProgressRing {
}
extension ProgressRingEx {
    public func startObserving<Element>(
        _ emit: @escaping @Sendable () -> Element,
        onChanged: @escaping @MainActor (ProgressRing, Element) -> Void
    ) {
        let obs = Observations(emit)

        Task { [weak self] in
            for await value in obs {
                /// NOTE: self is nil after the first change of the observation.
                /// Does the ring pointer released?
                /// Why NavigationViewItem works in this case?
                guard let self else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    onChanged(self, value)
                }
            }
        }
    }
}

/// FIXME: Must inherit ProgressBar, otherwise can't be triggered the second change of the observation
public class ProgressBarEx: ProgressBar {
}
extension ProgressBarEx {
    public func startObserving<Element>(
        _ emit: @escaping @Sendable () -> Element,
        onChanged: @escaping @MainActor (ProgressBar, Element) -> Void
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
