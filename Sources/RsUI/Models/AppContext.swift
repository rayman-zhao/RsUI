import Foundation
import Observation
import RsHelper

@Observable
public class AppContext {
    public let productName: String
    public let supportDirectory: URL
    public let preferences: Preferences
    public var theme: AppTheme {
        didSet {
            guard oldValue != theme else { return }
            preferences.save(theme)
        }
    }
    public var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }
            preferences.save(language)
        }
    }

    let bundle: Bundle
    let modules: [any Module]

    init(_ group: String, _ product: String, _ bundle: Bundle, _ modules: [any Module]) {
        productName = product
        supportDirectory = URL.applicationSupportDirectory.reachingChild(named: "\(group)/\(product)/")!       
        preferences = JsonPreferences.makeAppStandard(group: group, product: product)
        theme = preferences.load(for: AppTheme.self)
        language = preferences.load(for: AppLanguage.self)
    
        self.bundle = bundle
        self.modules = modules
    }

    public func tr(_ keyAndValue: String, _ table: String? = nil) -> String {
        return String(localized: keyAndValue, table: table, bundle: bundle, locale: language.locale)
    }
}