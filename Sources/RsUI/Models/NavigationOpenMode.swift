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
