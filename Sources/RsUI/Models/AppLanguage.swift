import Foundation
import RsFoundation

public enum AppLanguage: String, CaseIterable, Sendable, RawPreferenceValue {
    case undefined
    case en_US
    case zh_CN
    case auto

    static var availableCases: [AppLanguage] {
        return allCases.compactMap {
            switch $0 {
            case undefined, auto: return nil
            default: return $0
            }
        }
    }

    var displayName: String {
        switch self {
        case .en_US: return "English"
        case .zh_CN: return "简体中文"
        default: return ""
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
        default: return LocaleConstants.en
        }
    }

    public init() {
        self = .undefined
    }
}
