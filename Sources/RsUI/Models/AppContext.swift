import Foundation
import Observation
import RsHelper

@Observable
public class AppContext {
    public let productGroup: String
    public let productName: String
    public let productSupportDirectory: URL
    public let moduleBundle: Bundle
    public let preferences: Preferences
    public var appearance: Appearance

    init(_ group: String, _ product: String, _ bundle: Bundle) {
        productGroup = group
        productName = product
        productSupportDirectory = URL.applicationSupportDirectory.reachingChild(named: "\(productGroup)/\(productName)/")!
        moduleBundle = bundle
        preferences = JsonPreferences.makeAppStandard(group: productGroup, product: productName)
        appearance = preferences.load(for: Appearance.self)
    }

    public func tr(_ keyAndValue: String, _ table: String? = nil) -> String {
        return String(localized: keyAndValue, table: table, bundle: moduleBundle, locale: appearance.language.locale)
    }
}