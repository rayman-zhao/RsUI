import Foundation
import Observation
import WinUI

/// FIXME: Must inherit ProgressBar, otherwise can't be triggered the second change of the observation
public class ProgressBarEx: ProgressBar {
}
extension ProgressBar {
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
