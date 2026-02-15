import Foundation
import WinUI
import RsHelper

public enum Theme: String, RawValuePreferable {
    case dark = "Dark"
    case light = "Light"
    case auto = "Auto"

    public init() {
        self = (Application.current?.requestedTheme == .dark) ? .dark : .light
    }
    
    public var isDark: Bool {
        switch self {
            case .dark: return true
            case .light: return false
            case .auto: return true /// Todo: should retrive system theme
        }
    }
    var applicationTheme: WinUI.ApplicationTheme {
        return isDark ? .dark : .light
    }
    var elementTheme: WinUI.ElementTheme {
        return isDark ? .dark : .light
    }

    mutating func toggle() {
        self = isDark ? .light : .dark
    }
}
