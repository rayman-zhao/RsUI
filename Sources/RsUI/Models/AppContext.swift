import Foundation
import Observation
import WinUI
import RsHelper

@Observable
public class AppContext {
    public let productName: String
    public let supportDirectory: URL
    public let preferences: Preferences
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
    public var isStatusBarVisible: Bool {
        didSet {
            guard oldValue != isStatusBarVisible else { return }
            preferences.save(
                StatusBarPreferences(
                    isStatusBarVisible: isStatusBarVisible,
                    hiddenItemIDs: Array(statusBar.hiddenItemIDs).sorted()
                )
            )
        }
    }
    public let bundle: Bundle
    public let statusBar: StatusBarService
    
    var modules: [any Module] = []

    init(_ group: String, _ product: String, _ bundle: Bundle) {
        productName = product
        supportDirectory = URL.applicationSupportDirectory.reachingChild(named: "\(group)/\(product)/")!       
        let store = JsonPreferences.makeAppStandard(group: group, product: product)
        preferences = store
        theme = store.load(for: AppTheme.self)
        language = store.load(for: AppLanguage.self)
        let statusBarPreferences = store.load(for: StatusBarPreferences.self)
        isStatusBarVisible = statusBarPreferences.isStatusBarVisible
        statusBar = StatusBarService(preferences: statusBarPreferences)
        self.bundle = bundle
        statusBar.onPreferencesChanged = { [weak self] updated in
            guard let self else { return }
            self.preferences.save(
                StatusBarPreferences(
                    isStatusBarVisible: self.isStatusBarVisible,
                    hiddenItemIDs: updated.hiddenItemIDs
                )
            )
        }

        if Application.current.requestedTheme != theme.applicationTheme {
            Application.current.requestedTheme = theme.applicationTheme
        }
    }

    public func tr(_ keyAndValue: String, _ table: String? = nil) -> String {
        return String(localized: keyAndValue, table: table, bundle: bundle, locale: language.locale)
    }
}
