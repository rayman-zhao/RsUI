import Foundation
import Observation
import WinUI

public protocol Page: AnyObject {
    var url: URL { get }
    var header: Any? { get }
    var title: String { get }
    var content: UIElement { get }

    /// Callback when the page is moved to another window (tab tear-out or
    /// merge), or the window enter/exit fullscreen state.
    ///
    /// A page that caches WindowContext should update it here, and change button
    /// text or icon for fullscreen state.
    func windowContextDidChange(to context: WindowContext)
}

extension Page {
    public var header: Any? { nil }

    public func windowContextDidChange(to context: WindowContext) {}

    /// 观察 ViewModel 状态并驱动 UI。返回观察 Task，需要提前终止观察时可 cancel。
    @discardableResult
    public func startObserving<Element>(
        _ emit: @escaping @Sendable () -> Element,
        onChanged: @escaping @MainActor (Page, Element) -> Void
    ) -> Task<Void, Never> {
        startObservingChanges(on: self, emitting: emit, onChanged: onChanged)
    }
}
