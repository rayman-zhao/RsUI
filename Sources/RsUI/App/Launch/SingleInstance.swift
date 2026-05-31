import Foundation
import WinAppSDK
import WinSDK
import RsHelper

// Keeps the app to a single process. The first launch becomes the primary
// instance; later launches (including the taskbar --new-window relaunch)
// redirect their activation to the primary and exit, so the primary opens the
// new window in-process. Avoids cross-process races on the preferences JSON
// and matches VSCode's behavior.
final class SingleInstance {
    // Retained to keep the activated subscription alive for the app lifetime.
    private var keyInstance: AppInstance?

    // Returns true for a redundant secondary instance that handed its
    // activation to the primary and is about to exit — the caller should
    // return. Fails open: any failure returns false and the caller starts
    // normally.
    func redirectIfSecondary(key: String) -> Bool {
        guard let instance = try? AppInstance.findOrRegisterForKey(key) else {
            log.warning("single-instance: findOrRegisterForKey failed, running standalone")
            return false
        }
        keyInstance = instance
        guard !instance.isCurrent else { return false }
        redirectAndExit(to: instance)
        return true
    }

    // Primary instance subscribes to later redirected activations. activated
    // fires on a background thread, so onActivated is hopped to the UI thread
    // via uiQueue.
    func observe(uiQueue: DispatcherQueue?, onActivated: @escaping () -> Void) {
        keyInstance?.activated.addHandler { _, _ in
            _ = try? uiQueue?.tryEnqueue { onActivated() }
        }
    }

    private func redirectAndExit(to instance: AppInstance) {
        // Hand this process's activation to the primary, then exit without
        // creating any window.
        let activatedArgs = try? AppInstance.getCurrent().getActivatedEventArgs()
        Task {
            if let activatedArgs {
                try? await instance.redirectActivationToAsync(activatedArgs).get()
            } else {
                log.warning("single-instance: getActivatedEventArgs failed, redirect skipped")
            }
            ExitProcess(0)
        }
    }
}
