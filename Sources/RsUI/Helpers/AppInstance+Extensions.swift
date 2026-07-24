import Foundation
import RsFoundation
import WinAppSDK

extension AppInstance {
    static func coordinateSingleInstance(
        for key: String, onActivated: @escaping @MainActor (Any?, AppActivationArguments?) -> Void
    ) {
        guard let instance = try? AppInstance.findOrRegisterForKey(key)
        else {
            fatalError("Failed to findOrRegister AppInstance.")
        }

        // Single instance check.
        guard instance.isCurrent else {
            if let args = try? instance.getActivatedEventArgs(),
                let asyncResult = try? instance.redirectActivationToAsync(args)
            {
                Task {
                    try? await asyncResult.get()
                }
            }
            log.info("Exit later instance.")
            exit(0)
        }

        // Responese to activated event.
        instance.activated.addHandler { sender, args in
            Task { @MainActor in
                onActivated(sender, args)
            }
        }
    }
}
