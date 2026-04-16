import Foundation
import RsHelper

struct WindowPosition: Preferable {
    var windowWidth: Int = 1440
    var windowHeight: Int = 800
    var windowX: Int = 100
    var windowY: Int = 100
    var isMaximized: Bool = true
}

struct WindowLayout: Preferable {
    var navigationViewMinPaneLength: Double = 100
    var navigationViewMaxPaneLength: Double = 400
    var navigationViewExpandedModeThresholdContentWidth: Double = 688 // MARK: 688 is from default size 1008 - 320

    var navigationViewPaneOpen: Bool = true
    var navigationViewOpenPaneLength: Double = 320
}

struct RoutePreferences: Preferable {
    var maxHistoryPages: Int = 32
    var lastPageURL: URL? = nil
}
