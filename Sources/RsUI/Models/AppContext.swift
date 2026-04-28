import Foundation
import Observation
import UWP
import WinAppSDK
import WinUI
import RsHelper

@Observable
public class AppContext {
    public let groupName: String
    public let productName: String
    public let supportDirectory: URL
    public let preferences: Preferences
    public let resourceBundle: Bundle
    public var theme: AppTheme {
        didSet {
            guard oldValue != theme else { return }
            Application.current.requestedTheme = theme.applicationTheme
            preferences.save(theme)
        }
    }
    public var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }
            preferences.save(language)
        }
    }
    public var fontScale: Int = 100
    public var iconPath: String? {
        resourceBundle.path(forResource: productName, ofType: "ico")
    }
    public var winAppSDKVersion: String {
        switch RuntimeInfo.version {
            case PackageVersion(major: 8000, minor: 616, build: 304, revision: 0):
                return "1.8.0"
            case PackageVersion(major: 8000, minor: 806, build: 2252, revision: 0):
                return "1.8.6"
            case PackageVersion(major: 8000, minor: 836, build: 2153, revision: 0):
                return "1.8.7"
            default:
                return RuntimeInfo.asString
        }
    }
    
    var modules: [any Module] = []

    private init(_ group: String, _ product: String, _ resourceBundle: Bundle, _ loadAppearence: Bool) {
        groupName = group
        productName = product
        supportDirectory = URL.applicationSupportDirectory.reachingChild(named: "\(group)/\(product)/")!       
        preferences = JsonPreferences.makeAppStandard(group: group, product: product)
        self.resourceBundle = resourceBundle
        if loadAppearence {
            self.theme = preferences.load(for: AppTheme.self)
            self.language = preferences.load(for: AppLanguage.self)
        } else {
            self.theme = .auto 
            self.language = .en_US
        }
    }

    static func gui(_ group: String, _ product: String, _ resourceBundle: Bundle) -> AppContext {
        let ctx = AppContext(group, product, resourceBundle, true)

        if Application.current.requestedTheme != ctx.theme.applicationTheme {
            Application.current.requestedTheme = ctx.theme.applicationTheme
        }

        return ctx
    }

    static func cli() -> AppContext {
        return AppContext("SwiftWorks", "RsUI", .main, false)
    }

    public func tr(_ keyAndValue: String, _ table: String? = nil) -> String {
        return String(localized: keyAndValue, table: table, bundle: resourceBundle, locale: language.locale)
    }

    public func trxaml(_ xaml: String, _ table: String? = nil) -> String {
        // FIXME: Prior to Swift 6, need to write #/myregex/# instead of /myregex/
        let pattern = #/{x:Tr ([^}]+)}/#
        let matches = xaml.matches(of: pattern).map { $0.1 }

        var result = xaml
        for match in matches {
            result = result.replacingOccurrences(of: "{x:Tr \(match)}", with: tr(String(match), table))
        }

        return result
    }
}
