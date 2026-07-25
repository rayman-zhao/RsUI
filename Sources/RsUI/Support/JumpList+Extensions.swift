import Foundation
import RsFoundation
import UWP
import WindowsFoundation

extension JumpList {
    public static func register(arguments: String, displayName: String, logo: Uri? = nil) {
        guard (try? JumpList.isSupported()) == true else { return }
        Task { @MainActor in
            do {
                guard let jumpList = try await JumpList.loadCurrentAsync().get() else { return }
                guard let items = jumpList.items else { return }

                if let item = existingItem(matching: arguments, in: items) {
                    let shouldUpdate = item.displayName != displayName  // Maybe check logo too later.
                    guard shouldUpdate else {
                        log.info(
                            "Reuse an existing JumpListItem with \(arguments) instead of recreating it."
                        )
                        return
                    }

                    item.displayName = displayName
                    item.logo = logo
                } else {
                    guard let item = try JumpListItem.createWithArguments(arguments, displayName)
                    else { return }
                    item.logo = logo
                    items.append(item)                    
                }

                try await jumpList.saveAsync().get()
            } catch {
                log.warning("Failed to register JumpList: \(error)")
            }
        }
    }

    private static func existingItem(
        matching arguments: String, in items: AnyIVector<JumpListItem?>
    ) -> JumpListItem? {
        for case let item? in items where item.arguments == arguments {
            return item
        }
        return nil
    }
}
