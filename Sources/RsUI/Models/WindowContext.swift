import Foundation
import WinAppSDK
import WinUI

protocol FullscreenableWindow {
    var isInFullscreen: Bool { get }
    func enterFullscreen(for element: UIElement)
    func exitFullscreen()
}

protocol WindowContextHost: AnyObject, FullscreenableWindow {
    var hwnd: WindowId { get }
    var currentPageControl: PageControl { get }
}

/// Destination when opening a URL or Page.
///
/// - inplace: Open in the current page control.
/// - newTab: Open in a new tab and switch to it.
/// - newTabNoFocus: Open in a new tab without switching to it.
public enum NavigationOpenMode: Sendable {
    case inplace
    case newTab
    case newTabNoFocus
}

/// Window-scoped services exposed to RsUI modules and pages.
///
/// A `WindowContext` lets module works with main windows without knowing `MainWindow` specific type.
public struct WindowContext {
    // Modules may keep this context from a Page, so the underlying window owner is weak.
    weak var host: WindowContextHost?

    /// Opens the system folder picker owned by this window.
    ///
    /// Use this when module UI needs a folder path selected by the user. The picker is
    /// associated with the current `MainWindow`, so the dialog is parented to the right
    /// WinUI window.
    ///
    /// - Parameter handler: Called on the main actor with the selected folder path.
    ///
    /// Example:
    /// ```swift
    /// context.pickFolder { path in
    ///     print("Selected folder: \(path)")
    /// }
    /// ```
    public func pickFolder(_ handler: @escaping (String) -> Void) {
        guard let host else { return }

        Task { @MainActor in
            let picker = FolderPicker(host.hwnd)
            guard let asyncResult = try? picker.pickSingleFolderAsync() else { return }
            guard let result = try? await asyncResult.get() else { return }

            await MainActor.run {
                handler(result.path)
            }
        }
    }

    public func open(
        _ page: Page,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) {
        host?.currentPageControl.navigate(
            to: page, mode: mode, transitionInfoOverride: transitionInfoOverride)
    }

    @discardableResult
    public func open(
        _ url: URL,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> Bool {
        guard let page = resolvePage(from: url) else { return false }
        open(page, mode: mode, transitionInfoOverride: transitionInfoOverride)
        return true
    }

    @discardableResult
    public func open(
        _ pages: [Page],
        mode: NavigationOpenMode = .newTab,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> Int {
        return host?.currentPageControl.open(
            pages, mode: mode, transitionInfoOverride: transitionInfoOverride) ?? 0
    }

    @discardableResult
    public func open(
        _ urls: [URL],
        mode: NavigationOpenMode = .newTab,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> Int {
        let pages = urls.compactMap { resolvePage(from: $0) }
        return open(pages, mode: mode, transitionInfoOverride: transitionInfoOverride)
    }

    // MARK: - Open or Focus

    /// Opens a URL in a new tab, or focuses the existing tab if one is already
    /// displaying that URL.
    ///
    /// This is the primary "navigate-to-content" method for module code that
    /// wants deduplication: slides, documents, detail views, etc. When a tab
    /// with `url` already exists, it is selected and `true` is returned without
    /// creating a duplicate. Otherwise a new tab is opened via the module's
    /// `navigationRequested(for:in:)`.
    ///
    /// - Parameters:
    ///   - url: The route URL to resolve.
    ///   - mode: The fallback open mode when no existing tab is found.
    ///     Defaults to `.newTab`. Only `.inplace`, `.newTab`, and
    ///     `.newTabNoFocus` are meaningful (`.newWindow` is passed through
    ///     to `open(_:mode:)` without deduplication).
    ///   - focusExisting: Whether an existing matching tab should be selected.
    ///     Pass `false` for background-open gestures that should avoid stealing focus.
    ///   - transitionInfoOverride: Optional navigation transition for newly
    ///     created tabs.

    /// - Returns: `true` if an existing tab was focused or a new navigation
    ///   was accepted.
    @discardableResult
    public func openOrFocus(
        _ url: URL,
        mode: NavigationOpenMode = .newTab,
        focusExisting: Bool = true,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> Bool {
        guard let owner = host as? MainWindow else { return false }
        if owner.findTabContext(matchingURL: url) != nil {
            if focusExisting {
                _ = owner.focusTab(matchingURL: url)
            }
            return true
        }
        return open(url, mode: mode, transitionInfoOverride: transitionInfoOverride)
    }

    public var isInTabFullscreen: Bool {
        host?.isInFullscreen ?? false
    }

    public func enterTabFullscreen() {
        guard let host else { return }
        host.enterFullscreen(for: host.currentPageControl.pageView)
    }

    public func exitTabFullscreen() {
        host?.exitFullscreen()
    }

    func resolvePage(from url: URL) -> Page? {
        if url == SettingsPage.url {
            return SettingsPage()
        }

        for module in App.context.modules {
            if let page = module.onNavigationRequested(for: url, in: self) {
                return page
            }
        }

        return nil
    }
}
