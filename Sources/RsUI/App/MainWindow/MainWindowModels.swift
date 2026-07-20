import Foundation
import UWP
import RsFoundation

struct WindowPosition: PreferenceValue {
    var windowWidth: Int = 1440
    var windowHeight: Int = 800
    var windowX: Int = 100
    var windowY: Int = 100
    var isMaximized: Bool = true
}

struct WindowLayout: PreferenceValue {
    var navigationViewMinPaneLength: Double = 100
    var navigationViewMaxPaneLength: Double = 400
    var navigationViewExpandedModeThresholdContentWidth: Double = 688 // MARK: 688 is from default size 1008 - 320

    var navigationViewPaneOpen: Bool = true
    var navigationViewOpenPaneLength: Double = 320
}

struct RoutePreferences: PreferenceValue {
    var maxHistoryPages: Int = 32
    var lastPageURL: URL? = nil
}

extension WindowPosition {
    var windowRect: UWP.RectInt32 {
        return UWP.RectInt32(
            x: Int32(windowX),
            y: Int32(windowY),
            width: Int32(windowWidth),
            height: Int32(windowHeight)
        )
    }
}
