import WinUI

class TabViewWindow: AppearanceWindow, FullscreenableWindow {
    private(set) var isInFullscreen = false
    func enterFullscreen(for element: UIElement) {}
    func exitFullscreen() {}
}
