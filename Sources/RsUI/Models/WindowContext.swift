import Foundation
import WinAppSDK
import WinUI

/// Opening destination used by `WindowContext.open` and `MainWindow.navigate`.
///
/// - inplace: Open in the currently selected tab.
/// - newTab: Open in a new tab and switch to it.
/// - newTabBackground: Open in a new tab without switching to it.
/// - newWindow: Open in a new main window.
public enum NavigationOpenMode: Sendable {
    case inplace
    case newTab
    case newTabBackground
    case newWindow
}

/// Information returned when a selected tab is detached from a main window.
public struct DetachedTabInfo: Sendable {
    /// The page URL that identified the detached tab.
    public let url: URL

    /// The tab's original 0-based position in the source tab strip.
    public let index: Int
}

/// Window-scoped services exposed to RsUI modules and pages.
///
/// A `WindowContext` lets module code open pages, create tabs or windows,
/// and use window-owned UI services without exposing `MainWindow` as public API.
public struct WindowContext {
    // Modules may keep this context from a Page, so the underlying window owner is weak.
    weak var owner: MainWindow?

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
        guard let owner else { return }
        Task { @MainActor in
            let picker = FolderPicker(owner.appWindow.id)
            guard let asyncResult = try? picker.pickSingleFolderAsync() else { return }
            guard let result = try? await asyncResult.get() else { return }

            await MainActor.run {
                handler(result.path)
            }
        }
    }

    /// Opens a page with the requested mode.
    ///
    /// Use this overload when the caller already has a `Page` instance. The page is
    /// inserted directly into the selected destination and does not need to be routable
    /// from a URL.
    ///
    /// - Parameters:
    ///   - page: The page instance to display. For `.newWindow`, the page is displayed
    ///     directly in the new window and does not need to be routable from a URL. If
    ///     the page stores a `WindowContext`, make sure it is valid for the destination
    ///     window; otherwise prefer `open(mode:makePage:)`.
    ///   - mode: Where to open the page. `.inplace` replaces the selected tab content,
    ///     `.newTab` creates and selects a tab, `.newTabBackground` creates a tab
    ///     without selecting it, and `.newWindow` opens a new main window.
    ///   - transitionInfoOverride: Optional WinUI navigation transition to use when the
    ///     destination renders the page.
    ///
    /// Example:
    /// ```swift
    /// context.open(DetailsPage(itemID: id), mode: .newTab)
    /// context.open(StaticPreviewPage(model: model), mode: .newWindow)
    /// ```
    public func open(
        _ page: Page,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) {
        owner?.navigate(to: page, mode: mode, transitionInfoOverride: transitionInfoOverride)
    }

    /// Opens a URL with the requested mode.
    ///
    /// Use this overload when the target page can be reconstructed from a URL through a
    /// module's `navigationRequested(for:in:)` implementation. The URL does not need to
    /// be represented by a NavigationView item, but it must be handled by Settings or by
    /// a registered module.
    ///
    /// - Parameters:
    ///   - url: The route URL to resolve.
    ///   - mode: Where to open the resolved page. `.inplace` replaces the selected tab
    ///     content, `.newTab` creates and selects a tab, `.newTabBackground` creates a
    ///     tab without selecting it, and `.newWindow` opens a new main window.
    ///   - transitionInfoOverride: Optional WinUI navigation transition to use when the
    ///     destination renders the resolved page.
    ///
    /// - Returns: `true` if the route was accepted in the current window. For
    ///   `.newWindow`, `true` means the new window request was issued.
    ///
    /// Example:
    /// ```swift
    /// _ = context.open(
    ///     URL(string: "rs://arbitrary/window-context-result?id=42")!,
    ///     mode: .newTabBackground
    /// )
    /// ```
    @discardableResult
    public func open(
        _ url: URL,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> Bool {
        return owner?.navigate(to: url, mode: mode, transitionInfoOverride: transitionInfoOverride)
            ?? false
    }

    /// Opens several pages as tabs in one batch.
    ///
    /// Use this instead of calling `open(_:mode:)` in a loop: every page is
    /// inserted first and the tab strip is rendered a single time, so opening
    /// N tabs costs one render instead of N. There is no need to hop onto a
    /// `Task` to add tabs one by one.
    ///
    /// - Parameters:
    ///   - pages: The page instances to open, in tab order. An empty array is a
    ///     no-op. Each page is a separate tab; pass pre-built `Page` instances
    ///     bound to this window's context.
    ///   - mode: Controls selection only. `.newTab` (default) selects the last
    ///     opened tab; `.newTabBackground` keeps the current selection (or lands
    ///     on the first new tab if the window was empty). `.inplace` and
    ///     `.newWindow` are not batch modes and behave like `.newTab`.
    ///   - transitionInfoOverride: Optional WinUI navigation transition applied
    ///     when each tab first renders.
    /// - Returns: The number of tabs opened (equal to `pages.count`).
    ///
    /// Example:
    /// ```swift
    /// context.open([DetailsPage(id: 1), DetailsPage(id: 2), DetailsPage(id: 3)])
    /// ```
    @discardableResult
    public func open(
        _ pages: [Page],
        mode: NavigationOpenMode = .newTab,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> Int {
        guard let owner else { return 0 }
        let contexts = owner.addTabs(
            pages: pages,
            switchToLast: mode != .newTabBackground,
            transitionInfoOverride: transitionInfoOverride
        )
        return contexts.count
    }

    /// Opens several URLs as tabs in one batch.
    ///
    /// Each URL is resolved through Settings or a module's
    /// `navigationRequested(for:in:)`, then all resolved pages are opened with a
    /// single tab-strip render — the URL counterpart to `open(_:mode:)` for
    /// arrays. URLs that no module claims are skipped.
    ///
    /// - Parameters:
    ///   - urls: The route URLs to resolve and open, in tab order. An empty
    ///     array is a no-op.
    ///   - mode: Controls selection only, identical to the `[Page]` overload:
    ///     `.newTab` (default) selects the last opened tab, `.newTabBackground`
    ///     keeps the current selection. `.inplace` and `.newWindow` behave like
    ///     `.newTab`.
    ///   - transitionInfoOverride: Optional WinUI navigation transition applied
    ///     when each tab first renders.
    /// - Returns: The number of tabs opened — i.e. how many URLs resolved to a
    ///   page. May be fewer than `urls.count` if some were unrouted.
    ///
    /// Example:
    /// ```swift
    /// _ = context.open([
    ///     URL(string: "rs://arbitrary/navigation")!,
    ///     URL(string: "rs://arbitrary/openorfocus")!,
    /// ])
    /// ```
    @discardableResult
    public func open(
        _ urls: [URL],
        mode: NavigationOpenMode = .newTab,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> Int {
        guard let owner else { return 0 }
        let pages = urls.compactMap { owner.resolvePage(for: $0) }
        let contexts = owner.addTabs(
            pages: pages,
            switchToLast: mode != .newTabBackground,
            transitionInfoOverride: transitionInfoOverride
        )
        return contexts.count
    }

    /// Builds a page with the destination window context and opens it with the requested mode.
    ///
    /// Use this overload when the page should receive a `WindowContext` at construction
    /// time. For `.inplace`, `.newTab`, and `.newTabBackground`, the target context
    /// belongs to the current `MainWindow`. For `.newWindow`, RsUI creates the new
    /// `MainWindow` first, then calls `makePage` with that destination window context.
    ///
    /// - Parameters:
    ///   - mode: Where to open the generated page. `.inplace` replaces the selected tab
    ///     content, `.newTab` creates and selects a tab, `.newTabBackground` creates a
    ///     tab without selecting it, and `.newWindow` opens a new main window.
    ///   - transitionInfoOverride: Optional WinUI navigation transition to use when the
    ///     destination renders the page.
    ///   - makePage: A synchronous factory that receives the destination window context
    ///     and returns the page to display. The closure should create and return a
    ///     `Page`; it should not perform long-running work.
    ///
    /// Example:
    /// ```swift
    /// context.open(mode: .newWindow) { windowContext in
    ///     ViewerPage(context: windowContext, slideURL: slideURL)
    /// }
    /// ```
    public func open(
        mode: NavigationOpenMode,
        transitionInfoOverride: NavigationTransitionInfo? = nil,
        makePage: @escaping (WindowContext) -> Page
    ) {
        guard let owner else { return }
        if mode == .newWindow {
            MainWindow.openDetachedWindow(
                transitionInfoOverride: transitionInfoOverride,
                makePage: makePage
            )
            return
        }

        let context = WindowContext(owner: owner)
        owner.navigate(
            to: makePage(context),
            mode: mode,
            transitionInfoOverride: transitionInfoOverride
        )
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
    ///     `.newTabBackground` are meaningful (`.newWindow` is passed through
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
        guard let owner else { return false }
        if mode == .newWindow {
            return owner.navigate(
                to: url, mode: mode, transitionInfoOverride: transitionInfoOverride)
        }
        if owner.findTabContext(matchingURL: url) != nil {
            if focusExisting {
                _ = owner.focusTab(matchingURL: url)
            }
            return true
        }
        return owner.navigate(to: url, mode: mode, transitionInfoOverride: transitionInfoOverride)
    }

    // MARK: - Tab Fullscreen

    /// Enters immersive fullscreen for the currently selected tab.
    ///
    /// Switches the OS-level presenter to fullscreen (hiding the system title bar and
    /// taskbar) and collapses the application chrome — title bar, NavigationView,
    /// TabView strip, and splitter — so the selected page's content occupies the entire
    /// screen. The selected tab's `PageTransitionHost` is reparented to a root-level
    /// overlay for the duration of fullscreen and restored to its tab content host on
    /// exit. If the window was maximized before entering, the maximized state is
    /// restored on exit.
    ///
    /// Fullscreen is exited automatically when the user presses `Esc`. Calling this
    /// method while already in fullscreen is a no-op. There is no selected tab when the
    /// tab strip is empty; in that case this call is also a no-op.
    ///
    /// Example:
    /// ```swift
    /// // From a toolbar button on a viewer page:
    /// context.enterTabFullscreen()
    /// ```
    public func enterTabFullscreen() {
        owner?.enterTabFullscreen()
    }

    /// Exits immersive fullscreen and restores the application chrome.
    ///
    /// Restores the OS presenter to overlapped, brings back the title bar / NavigationView
    /// / TabView strip / splitter, and moves the page content back into its tab content
    /// host. If the window was maximized before entering fullscreen, it is re-maximized
    /// after exit. Calling this method while not in fullscreen is a no-op.
    ///
    /// You usually do not need to call this manually — `Esc` already exits fullscreen.
    /// Use it when a page action implies leaving fullscreen (e.g. opening a settings
    /// dialog that should not be obscured).
    ///
    /// Example:
    /// ```swift
    /// if context.isInTabFullscreen {
    ///     context.exitTabFullscreen()
    /// }
    /// ```
    public func exitTabFullscreen() {
        owner?.exitTabFullscreen()
    }

    /// Whether the owning window is currently in tab fullscreen.
    ///
    /// `true` while between `enterTabFullscreen()` and `exitTabFullscreen()`. Use this
    /// to drive UI state such as toggling a fullscreen button's icon or tooltip, or to
    /// observe fullscreen transitions via `Page.startObserving`.
    ///
    /// Returns `false` if the owner window has already been released.
    ///
    /// Example:
    /// ```swift
    /// startObserving({ context.isInTabFullscreen }) { _, isFullscreen in
    ///     viewer.setFullscreenState(isFullscreen)
    /// }
    /// ```
    public var isInTabFullscreen: Bool {
        owner?.isInTabFullscreen ?? false
    }

    // MARK: - Detach / Restore

    /// Removes the currently selected tab from this window for a caller-managed transfer.
    ///
    /// Use this after capturing any page runtime state needed by the destination host.
    /// The method allows detaching the last tab; in that case the source window remains
    /// open without a selected page until another tab is added or selected.
    ///
    /// - Returns: Information about the detached tab, or `nil` if the owner window has
    ///   been released, no tab is selected, or the selected tab has no current page.
    @discardableResult
    public func detachCurrentTab() -> DetachedTabInfo? {
        guard let owner else { return nil }
        return owner.detachCurrentTab()
    }

    /// Restores caller-managed detached content into this window as a tab.
    ///
    /// Use this for "merge back from detached window" flows. The caller creates a
    /// `Page` with restored runtime state and asks RsUI to insert it back into the tab
    /// strip, typically at the index returned by `detachCurrentTab()`.
    ///
    /// - Parameters:
    ///   - page: The page to display in the new tab.
    ///   - preferredIndex: Preferred insertion position (0-based). If `nil` or out of
    ///     range, the tab is appended to the end.
    ///   - switchToTab: Whether to select the new tab. Defaults to `true`.
    ///   - transitionInfoOverride: Optional navigation transition.
    /// - Returns: `true` if the page was inserted. `false` if the owner window has
    ///   already been released.
    ///
    @discardableResult
    public func restoreDetachedTab(
        _ page: Page,
        preferredIndex: Int? = nil,
        switchToTab: Bool = true,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> Bool {
        guard let owner else { return false }
        owner.restoreTab(
            page,
            atIndex: preferredIndex,
            switchToTab: switchToTab,
            transitionInfoOverride: transitionInfoOverride
        )
        return true
    }
}
