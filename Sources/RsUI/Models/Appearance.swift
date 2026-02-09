import Foundation
import WinUI
import RsHelper

public struct Appearance: Preferable {
    public enum Theme: String, Codable {
        case dark = "Dark"
        case light = "Light"
        case auto = "Auto"

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

    public enum Language: String, CaseIterable, Codable {
        case en_US
        case zh_CN

        var displayName: String {
            switch self {
                case .en_US: return "English"
                case .zh_CN: return "简体中文"
            }
        }

        var locale: Locale {
            struct LocaleConstants {
                static let en = Locale(identifier: "en")
                static let zh_Hans = Locale(identifier: "zh-Hans")
            }

            switch self {
                case .en_US: return LocaleConstants.en
                case .zh_CN: return LocaleConstants.zh_Hans
            }
        }
    }

    public var theme: Theme = .dark
    public var language: Language = .en_US
    
    public init() {}
}
