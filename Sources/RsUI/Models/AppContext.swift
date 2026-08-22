import Foundation
import Observation
import RsFoundation
import UWP
import WinUI
import WindowsFoundation

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
    public var iconAppxUri: Uri? {
        guard let path = iconPath else { return nil }
        let relativePath = path.trimmingPrefix(Bundle.main.bundlePath)
        return Uri("ms-appx://\(relativePath)")
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
    public var route = AppRoute()

    private var moduleTypes: [Module.Type] = []
    internal private(set) var modules: [any Module] = []

    init() {
        let group = "SwiftWorks"
        let product = "RsUI"

        groupName = group
        productName = product
        supportDirectory = URL.applicationSupportDirectory.ensuringChild(
            named: "\(group)/\(product)/")!
        preferences = JSONPreferences.makeStandard(group: group, product: product)
        self.resourceBundle = .main
    }

    func bootstrap(
        group: String, product: String, resourceBundle: Bundle, moduleTypes: [Module.Type]
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
        route = preferences.load(for: AppRoute.self)
    }

    func initializeModules() {
        modules = moduleTypes.map { $0.init() }
    }

    func releaseModules() {
        modules = []

        preferences.save(route)
    }

    public func tr(_ keyAndValue: String, table: String? = nil) -> String {
        return String(
            localized: keyAndValue, table: table, bundle: resourceBundle, locale: language.locale)
    }

    public func tr(xaml: String, table: String? = nil) -> String {
        // FIXME: Prior to Swift 6, need to write #/myregex/# instead of /myregex/
        let pattern = #/{x:Tr ([^}]+)}/#
        let matches = xaml.matches(of: pattern).map { $0.1 }

        var result = xaml
        for match in matches {
            result = result.replacingOccurrences(
                of: "{x:Tr \(match)}", with: tr(String(match), table: table))
        }

        if let iconPath {
            result = result.replacingOccurrences(of: "{x:AppIconPath}", with: iconPath)
        }

        return result
    }

    public func requireXaml<T>(string xaml: String, trTable: String? = nil) -> T {
        do {
            let trXaml = tr(xaml: xaml, table: trTable)
            guard let root = try XamlReader.load(trXaml) as? T else {
                fatalError("The root element of \(xaml) is not \(T.self)")
            }
            return root
        } catch {
            fatalError("XamlReader \(xaml) failed with error: \(error)")
        }
    }

    public func requireXaml<T>(resource name: String, trTable: String? = nil) -> T {
        guard let path = resourceBundle.path(forResource: name, ofType: "xaml") else {
            fatalError("Can't find \(name).xaml in bundle \(resourceBundle)")
        }

        do {
            let xaml = try String(contentsOfFile: path, encoding: .utf8)
            return requireXaml(string: xaml, trTable: trTable)
        } catch {
            fatalError("Load \(name).xaml failed with error: \(error)")
        }
    }

    /// Opens a brand-new `MainWindow` and navigates it to the given URL.
    ///
    /// - Parameters:
    ///   - urls: The route URL to resolve in the new window.
    ///   - forceMinimalMode: When `true`, the new window starts with
    ///     the NavigationView pane minimized and its closing handler skips
    ///     persisting the layout unless user expended it. Use for viewer-style
    ///     windows (e.g. slide presenters) where chrome would distract from content.
    public func openNewWindow(
        with urls: [URL],
        forceMinimalMode: Bool = false
    ) {
        try? MainWindow(urls: urls, forceMinimalMode: forceMinimalMode).activate()
    }
}
