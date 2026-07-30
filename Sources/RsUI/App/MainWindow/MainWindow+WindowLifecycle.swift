import Foundation
import Observation
import WinAppSDK
import WinUI

extension MainWindow {
    func setupWindow() {
        self.closed.addHandler { [weak self] _, _ in
            guard let self else { return }

            // A speculative tear-out can create an empty spare window that never
            // gets a tab. The process exits only when all windows close, so a
            // lingering spare keeps it alive after the user closes the real
            // windows. Drop the empty spare and stale tear state on any close.
            if MainWindow.spareReceiver === self {
                MainWindow.spareReceiver = nil
                MainWindow.pendingTearOut = nil
            } else if let spare = MainWindow.spareReceiver, spare.hasNoTabs {
                MainWindow.spareReceiver = nil
                MainWindow.pendingTearOut = nil
                try? spare.close()
            }

            self.viewModel = nil
        }
    }
}
