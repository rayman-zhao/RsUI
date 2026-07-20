import Foundation
import WinAppSDK
import WinUI
import RsFoundation

public enum AppTheme: String, Sendable, RawPreferenceValue {
    case undefined
    case dark = "Dark"
    case light = "Light"
    case auto = "Auto"

    public init() {
        self = .undefined
    }
    
    public var isDark: Bool {
        switch self {
            case .dark: return true
            case .light: return false
            default: return true
        }
    }
    var applicationTheme: WinUI.ApplicationTheme {
        return isDark ? .dark : .light
    }
    var elementTheme: WinUI.ElementTheme {
        return isDark ? .dark : .light
    }
    var titleBarTheme: WinAppSDK.TitleBarTheme {
        return isDark ? .dark : .light
    } 

    mutating func toggle() {
        self = isDark ? .light : .dark
    }
}
