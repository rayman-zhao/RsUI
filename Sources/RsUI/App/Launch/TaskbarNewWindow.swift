import Foundation
import UWP
import RsFoundation

// Taskbar right-click "New Window" entry, backed by the WinRT
// Windows.UI.StartScreen.JumpList. Works for both packaged and unpackaged apps
// through the Windows App SDK runtime.
enum TaskbarNewWindow {
    static func register(title: String, argument: String = "--new-window") {
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
