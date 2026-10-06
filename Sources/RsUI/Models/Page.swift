import Foundation
import Observation
import WinUI

public protocol Page: AnyObject {
    var url: URL { get }
    var header: Any? { get }
    var title: String { get }
    var content: UIElement { get }

    /// Callback when the page is attached to a window (before its content is
    /// first rendered), when the page is moved to another window (tab tear-out
    /// or merge), or when the window enter/exit fullscreen state.
    ///
    /// This is the single entry point for obtaining the WindowContext: a page
    /// that needs it should store it here — do not take it from the module
    /// factory / init. A page that changes fullscreen-derived UI (button text
    /// or icon) should also refresh it here; note the callback may fire before
    /// the page's content is first built.
    func windowContextDidChange(to context: WindowContext)
}

extension Page {
    public var header: Any? { nil }

    public func windowContextDidChange(to context: WindowContext) {}
}
