import Foundation
import RsFoundation
import UWP

extension JumpList {
    public static func register(title: String, argument: String = "--new-window") {
        guard (try? JumpList.isSupported()) == true else { return }
        Task {
            do {
                guard let jumpList = try await JumpList.loadCurrentAsync().get() else { return }
                jumpList.items.clear()
                jumpList.items.append(try JumpListItem.createWithArguments(argument, title))
                try await jumpList.saveAsync().get()
            } catch {
                log.warning("WinRT JumpList register failed: \(error)")
            }
        }
    }
}
