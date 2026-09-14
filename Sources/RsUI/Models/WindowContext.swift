import Foundation
import WinAppSDK
import WinUI

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
    private weak var host: WindowContextHost?

    init(host: WindowContextHost) {
        self.host = host
    }

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

        let picker = FolderPicker(host.hwnd)
        Task { @MainActor in
            guard let result = try? await picker.pickSingleFolderAsync().get() else { return }

            await MainActor.run {
                handler(result.path)
            }
        }
    }

    public func pickSaveFile(
        suggestedStartLocation: PickerLocationId = .documentsLibrary,
        fileTypeChoices: [String: [String]] = [:],
        suggestedFileName: String? = nil,
        defaultFileExtension: String? = nil,
        handler: @escaping (String) -> Void
    ) {
        guard let host else { return }

        let picker = FileSavePicker(host.hwnd)
        picker.suggestedStartLocation = suggestedStartLocation
        for (fileTypeDescription, extensions) in fileTypeChoices {
            _ = picker.fileTypeChoices.insert(fileTypeDescription, extensions.toVector())
        }
        if let suggestedFileName {
            picker.suggestedFileName = suggestedFileName
        }
        if let defaultFileExtension {
            picker.defaultFileExtension = defaultFileExtension
        }

        Task { @MainActor in
            guard let result = try? await picker.pickSaveFileAsync().get() else { return }

            await MainActor.run {
                handler(result.path)
            }
        }
    }

    /// Shows a modal message dialog parented to the owning `MainWindow`.
    ///
    /// The `ContentDialog` is built here so every dialog in the app shares one
    /// style. Provide the texts of the buttons you need (`nil` hides the button);
    /// the pressed one is reported to `handler` as a `ContentDialogResult`
    /// (`.none` means dismissed). When no button text is given at all, a single
    /// localized "OK" close button is used.
    ///
    /// - Parameters:
    ///   - title: The dialog title.
    ///   - message: The dialog body text.
    ///   - primaryButtonText: Text of the primary button; `nil` hides it.
    ///   - secondaryButtonText: Text of the secondary button; `nil` hides it.
    ///   - closeButtonText: Text of the close (Esc) button; `nil` hides it.
    ///   - handler: Called on the main actor with the pressed button's result.
    ///
    /// Example:
    /// ```swift
    /// context.showDialog(
    ///     title: "Delete item",
    ///     message: "This cannot be undone.",
    ///     primaryButtonText: "Delete",
    ///     closeButtonText: "Cancel"
    /// ) { result in
    ///     if result == .primary { /* perform deletion */ }
    /// }
    /// ```
    public func showDialog(
        title: String,
        message: String,
        primaryButtonText: String? = nil,
        secondaryButtonText: String? = nil,
        closeButtonText: String? = nil,
        handler: @escaping (ContentDialogResult) -> Void = { _ in }
    ) {
        guard let host else { return }

        let dialog = ContentDialog()
        dialog.title = title
        dialog.content = message
        if let primaryButtonText { dialog.primaryButtonText = primaryButtonText }
        if let secondaryButtonText { dialog.secondaryButtonText = secondaryButtonText }
        if let closeButtonText {
            dialog.closeButtonText = closeButtonText
        } else if primaryButtonText == nil && secondaryButtonText == nil {
            dialog.closeButtonText = App.context.tr("OK")
        }

        dialog.xamlRoot = host.xamlRoot

        Task { @MainActor in
            guard let result = try? await dialog.showAsync().get() else { return }

            await MainActor.run {
                handler(result)
            }
        }
    }

    public func open(
        _ page: Page,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo = SuppressNavigationTransitionInfo()
    ) {
        host?.open(page, mode: mode, transitionInfoOverride: transitionInfoOverride)
    }

    @discardableResult public func open(
        _ pages: [Page],
        mode: NavigationOpenMode = .newTab,
        transitionInfoOverride: NavigationTransitionInfo = SuppressNavigationTransitionInfo()
    ) -> Int {
        return host?.open(pages, mode: mode, transitionInfoOverride: transitionInfoOverride) ?? 0
    }

    @discardableResult
    public func open(
        _ url: URL,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo = SuppressNavigationTransitionInfo()
    ) -> Bool {
        guard let page = resolvePage(from: url) else { return false }
        open(page, mode: mode, transitionInfoOverride: transitionInfoOverride)
        return true
    }

    @discardableResult
    public func open(
        _ urls: [URL],
        mode: NavigationOpenMode = .newTab,
        transitionInfoOverride: NavigationTransitionInfo = SuppressNavigationTransitionInfo()
    ) -> Int {
        guard !urls.isEmpty else { return 0 }
        guard urls.count > 1 else {
            return open(urls[0], mode: mode, transitionInfoOverride: transitionInfoOverride)
                ? 1 : 0
        }
        let pages = urls.compactMap { resolvePage(from: $0) }
        return open(pages, mode: mode, transitionInfoOverride: transitionInfoOverride)
    }

    /// Opens a URL in a new tab, or focuses the existing tab if one is already
    /// displaying that URL.
    ///
    /// This is the primary "navigate-to-content" method for module code that
    /// wants deduplication: slides, documents, detail views, etc. When a tab
    /// with `url` already exists, it is selected and `true` is returned without
    /// creating a duplicate. Otherwise a new tab is opened.
    ///
    /// - Parameters:
    ///   - url: The route URL to resolve.
    /// - Returns: `true` if an existing tab was focused or a new navigation
    ///   was accepted.
    @discardableResult
    public func openOrFocus(_ url: URL) -> Bool {
        if host?.selectPage(matchingURL: url) == true {
            return true
        } else {
            return open(url, mode: .newTab)
        }
    }

    public var isInFullscreen: Bool {
        host?.isInFullscreenPage ?? false
    }

    public func enterFullscreen() {
        host?.enterFullscreenPage()
    }

    public func exitFullscreen() {
        host?.exitFullscreenPage()
    }

    func resolvePage(from url: URL) -> Page? {
        if url == SettingsPage.url {
            return SettingsPage()
        }

        for module in App.context.modules {
            if let page = module.navigationDidRequest(for: url, in: self) {
                return page
            }
        }

        return nil
    }
}
