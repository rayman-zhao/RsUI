import Foundation
import Observation
import RsFoundation
import UWP
import WinUI

@Observable
public final class AppContext {
    public private(set) var groupName: String
    public private(set) var productName: String
    public private(set) var supportDirectory: URL
    public private(set) var preferences: Preferences
    public private(set) var resourceBundle: Bundle
    public var iconPath: String? {
        resourceBundle.path(forResource: productName, ofType: "ico")
    }

    public var theme: AppTheme = .undefined {
        didSet {
            guard oldValue != theme else { return }
            Application.current.requestedTheme = theme.applicationTheme
            preferences.save(theme)
        }
    }
    public var language: AppLanguage = .undefined {
        didSet {
            guard oldValue != language else { return }
            preferences.save(language)
        }
    }

    private var moduleTypes: [Module.Type] = []
    private(set) var modules: [any Module] = []

    init() {
        let group = "Swift Works"
        let product = "RsUI"

        groupName = group
        productName = product
        supportDirectory = URL.applicationSupportDirectory.ensuringChild(
            named: "\(group)/\(product)/")!
        preferences = JSONPreferences.makeStandard(group: group, product: product)
        self.resourceBundle = .main
    }

    func bootstrap(
        _ group: String, _ product: String, _ resourceBundle: Bundle, _ moduleTypes: [Module.Type]
    ) {
        groupName = group
        productName = product
        supportDirectory = URL.applicationSupportDirectory.ensuringChild(
            named: "\(group)/\(product)/")!
        preferences = JSONPreferences.makeStandard(group: group, product: product)
        self.resourceBundle = resourceBundle
        self.moduleTypes = moduleTypes
    }

    func bootstrapGUI() {
        theme = preferences.load(for: AppTheme.self)
        if case .undefined = theme {
            theme = (Application.current.requestedTheme == .dark) ? .dark : .light
        }
        language = preferences.load(for: AppLanguage.self)
        if case .undefined = language {
            language = (ApplicationLanguages.languages.first == "zh-Hans-CN") ? .zh_CN : .en_US
        }
    }

    func initializeModules() {
        modules = moduleTypes.map { $0.init() }
    }

    func releaseModules() {
        modules = []
    }

    public func tr(_ keyAndValue: String, _ table: String? = nil) -> String {
        return String(
            localized: keyAndValue, table: table, bundle: resourceBundle, locale: language.locale)
    }

    public func trxaml(_ xaml: String, _ table: String? = nil) -> String {
        // FIXME: Prior to Swift 6, need to write #/myregex/# instead of /myregex/
        let pattern = #/{x:Tr ([^}]+)}/#
        let matches = xaml.matches(of: pattern).map { $0.1 }

        var result = xaml
        for match in matches {
            result = result.replacingOccurrences(
                of: "{x:Tr \(match)}", with: tr(String(match), table))
        }

        return result
    }

    /// Opens a brand-new `MainWindow` and navigates it to the given URL.
    ///
    /// Use this when there is no `WindowContext` at hand (background work,
    /// global callbacks, app-level shortcuts). For module code that already
    /// holds a `WindowContext`, prefer `WindowContext.open(_:mode:.newWindow)`
    /// so the route goes through the module's `navigationRequested`.
    ///
    /// - Parameters:
    ///   - url: The route URL to resolve in the new window.
    ///   - collapseNavigationPane: When `true`, the new window starts with
    ///     the NavigationView pane collapsed and its closing handler skips
    ///     persisting the layout, so the collapsed chrome does not leak into
    ///     subsequent windows. Use for viewer-style windows (e.g. slide
    ///     presenters) where chrome would distract from content.
    public func openNewWindow(
        with url: URL,
        collapseNavigationPane: Bool = false
    ) {
        MainWindow.openDetachedWindow(
            navigatingTo: url,
            collapseNavigationPane: collapseNavigationPane
        )
    }
}
