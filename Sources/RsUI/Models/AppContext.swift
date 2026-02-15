import Foundation
import Observation
import RsHelper

@Observable
public class AppContext {
    public let productGroup: String
    public let productName: String
    public let productSupportDirectory: URL
    public let resourcesBundle: Bundle
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

    public let modules: [any Module]

    init(_ group: String, _ product: String, _ bundle: Bundle, _ modules: [any Module]) {
        productGroup = group
        productName = product
        productSupportDirectory = URL.applicationSupportDirectory.reachingChild(named: "\(productGroup)/\(productName)/")!
        resourcesBundle = bundle
        preferences = JsonPreferences.makeAppStandard(group: productGroup, product: productName)

        theme = preferences.load(for: AppTheme.self)
        language = preferences.load(for: AppLanguage.self)

        self.modules = modules
    }

    public func tr(_ keyAndValue: String, _ table: String? = nil) -> String {
        return String(localized: keyAndValue, table: table, bundle: resourcesBundle, locale: language.locale)
    }
}