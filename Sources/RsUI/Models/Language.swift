import Foundation
import UWP
import RsHelper

public enum Language: String, CaseIterable, RawValuePreferable {
    case en_US
    case zh_CN
    
    public init() {
        self = (ApplicationLanguages.languages.first == "zh-Hans-CN") ? .zh_CN : .en_US
    }

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
