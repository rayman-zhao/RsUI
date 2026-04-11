import Foundation
import WinAppSDK

/// 模块所附窗口上下文信息
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

    public func navigate(to page: Page) {
        owner.navigate(to: page)
    }

    public func navigate(to url: URL) -> Bool {
        return owner.navigate(to: url)
    }
}
