import Foundation
import UWP
import RsFoundation

struct RoutePreferences: PreferenceValue {
    var maxHistoryPages: Int = 32
    var lastPageURL: URL? = nil
}
