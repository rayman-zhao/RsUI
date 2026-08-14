import Foundation
import RsFoundation

public struct AppRoute: PreferenceValue {
    var maxHistoryPages: Int = 32
    var lastPageURL: URL?

    public init() {
    }
}
