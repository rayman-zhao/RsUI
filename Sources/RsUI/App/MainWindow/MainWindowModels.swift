import Foundation
import RsHelper

struct WindowPosition: Preferable {
    var windowWidth: Int = 1280
    var windowHeight: Int = 800
    var windowX: Int = 100
    var windowY: Int = 100
    var isMaximized: Bool = false
}

struct WindowLayout: Preferable {
    var navigationViewPaneWidth: Int = 300
}

struct RoutePreferences: Preferable {
    var maxHistoryPages: Int = 32
    var lastPageURL: URL? = nil
}