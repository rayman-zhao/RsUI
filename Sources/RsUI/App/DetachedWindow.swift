import Foundation
import WinAppSDK
import WinUI

/// Presentation mode used when showing a detached content window.
public enum DetachedWindowPresentation: Sendable, Equatable {
    /// Show as a normal overlapped window.
    case windowed

    /// Show as a fullscreen window.
    case fullscreen
}

/// A shell-free RsUI window for hosting standalone content.
///
/// `DetachedWindow` is intended for content such as viewers, previews, or tools that
/// need a plain WinUI `Window` without the RsUI `MainWindow` shell, NavigationView, or
/// top-level TabView. The caller owns any domain state and can use `onClosed` to restore
/// content back into an application tab. Keep a strong reference to the window for as
/// long as it should remain available.
public final class DetachedWindow: Window {
    private let onClosed: (() -> Void)?
    private var didNotifyClosed = false
    private var fullscreenPresentation = false

    /// Indicates whether this window was most recently put into fullscreen presentation.
    public var isFullscreenPresentation: Bool {
        fullscreenPresentation
    }

    /// Creates a shell-free window that hosts the supplied content.
    ///
    /// - Parameters:
    ///   - title: Optional window title.
    ///   - content: The content to assign to `Window.content`.
    ///   - onClosed: Optional callback invoked exactly once when the window closes.
    public init(
        title: String? = nil,
        content: UIElement,
        onClosed: (() -> Void)? = nil
    ) {
        self.onClosed = onClosed
        super.init()

        self.content = content
        if let title {
            appWindow.title = title
        }
        closed.addHandler { [weak self] _, _ in
            self?.notifyClosedIfNeeded()
        }
    }

    /// Activates the window without changing its current presentation kind.
    public func activateWindow() {
        try? activate()
    }

    /// Opens the window using the requested presentation.
    public func open(_ presentation: DetachedWindowPresentation = .windowed) {
        switch presentation {
        case .windowed:
            openWindowed()
        case .fullscreen:
            openFullscreen()
        }
    }

    /// Opens the window as a normal overlapped window.
    public func openWindowed() {
        try? activate()
        restoreWindowed()
    }

    /// Opens the window as a fullscreen window.
    public func openFullscreen() {
        try? activate()
        enterFullscreen()
    }

    /// Switches the window into fullscreen presentation.
    public func enterFullscreen() {
        try? appWindow.setPresenter(.fullScreen)
        fullscreenPresentation = true
    }

    /// Switches the window back to normal overlapped presentation.
    public func restoreWindowed() {
        try? appWindow.setPresenter(.overlapped)
        fullscreenPresentation = false
    }

    /// Closes the window. `onClosed` will be invoked from the closed event.
    public func closeWindow() {
        try? close()
    }

    private func notifyClosedIfNeeded() {
        guard !didNotifyClosed else { return }
        didNotifyClosed = true
        onClosed?()
    }
}
