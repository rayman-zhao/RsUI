import Foundation
import WinAppSDK
import WinUI

/// Window context exposed to modules.
public struct WindowContext {
    let owner: MainWindow

    public func pickFolder(_ handler: @escaping (String) -> Void) {
        Task { @MainActor in
            let picker = FolderPicker(owner.appWindow.id)
            guard let asyncResult = try? picker.pickSingleFolderAsync() else { return }
            guard let result = try? await asyncResult.get() else { return }

            await MainActor.run {
                handler(result.path)
            }
        }
    }

    public func navigate(to page: Page, transitionInfoOverride: NavigationTransitionInfo? = nil) {
        owner.navigate(to: page, transitionInfoOverride: transitionInfoOverride)
    }

    public func navigate(to url: URL, transitionInfoOverride: NavigationTransitionInfo? = nil) -> Bool {
        return owner.navigate(to: url, transitionInfoOverride: transitionInfoOverride)
    }
}
