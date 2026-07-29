import Foundation
import UWP
import RsFoundation

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
