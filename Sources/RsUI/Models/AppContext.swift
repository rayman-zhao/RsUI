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
        // ms-appx:// URI 必须是包根（exe 目录）相对路径。icon 不在包根下时无法
        // 推导，返回 nil 让调用方走无 logo 回退，而不是拼出畸形 URI 静默失败。
        guard path.hasPrefix(Bundle.main.bundlePath) else {
            log.warning(
                "iconAppxUri: icon path \(path) is not under the package root \(Bundle.main.bundlePath)"
            )
            return nil
        }
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
        let defaults = Self.makeConfiguration(
            group: "SwiftWorks", product: "RsUI", resourceBundle: .main, moduleTypes: [])
        groupName = defaults.group
        productName = defaults.product
        supportDirectory = defaults.supportDirectory
        preferences = defaults.preferences
        resourceBundle = defaults.resourceBundle
        moduleTypes = defaults.moduleTypes
    }

    func bootstrap(
        group: String, product: String, resourceBundle: Bundle, moduleTypes: [Module.Type]
    ) {
        let config = Self.makeConfiguration(
            group: group, product: product, resourceBundle: resourceBundle, moduleTypes: moduleTypes)
        groupName = config.group
        productName = config.product
        supportDirectory = config.supportDirectory
        preferences = config.preferences
        self.resourceBundle = config.resourceBundle
        self.moduleTypes = config.moduleTypes
    }

    /// init 默认配置与 bootstrap 覆盖共用的目录/偏好构建逻辑。
    private static func makeConfiguration(
        group: String, product: String, resourceBundle: Bundle, moduleTypes: [Module.Type]
    ) -> (
        group: String, product: String, supportDirectory: URL, preferences: Preferences,
        resourceBundle: Bundle, moduleTypes: [Module.Type]
    ) {
        guard let support = URL.applicationSupportDirectory.ensuringChild(
            named: "\(group)/\(product)/")
        else {
            fatalError("AppContext: failed to ensure support directory for \(group)/\(product)")
        }
        return (
            group: group,
            product: product,
            supportDirectory: support,
            preferences: JSONPreferences.makeStandard(group: group, product: product),
            resourceBundle: resourceBundle,
            moduleTypes: moduleTypes
        )
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
        if route.maxHistoryPages < 1 { route.maxHistoryPages = 1 }
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
                of: "{x:Tr \(match)}", with: tr(String(match), table: table).xmlEscaped())
        }

        if let iconPath {
            result = result.replacingOccurrences(of: "{x:AppIconPath}", with: iconPath.xmlEscaped())
        }

        return result
    }

    public func requireXaml<T>(withString xaml: String, trTable: String? = nil) -> T {
        let trXaml = tr(xaml: xaml, table: trTable)
        do {
            guard let root = try XamlReader.load(trXaml) as? T else {
                fatalError("The root element of \(trXaml) is not \(T.self)")
            }
            return root
        } catch {
            fatalError("XamlReader \(trXaml) failed with error: \(error)")
        }
    }

    public func requireXaml<T>(withResource name: String, trTable: String? = nil) -> T {
        guard let path = resourceBundle.path(forResource: name, ofType: "xaml") else {
            fatalError("Can't find \(name).xaml in bundle \(resourceBundle)")
        }

        do {
            let xaml = try String(contentsOfFile: path, encoding: .utf8)
            return requireXaml(withString: xaml, trTable: trTable)
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
        do {
            try MainWindow(urls: urls, forceMinimalMode: forceMinimalMode).activate()
        } catch {
            log.warning("openNewWindow: failed to activate new window: \(error)")
        }
    }

    /// Reveals a file or directory in File Explorer with the item selected in its parent folder.
    public func revealInFileExplorer(_ url: URL) {
        Task { @MainActor in
            let options = FolderLauncherOptions()
            let folder: URL

            if url.hasDirectoryPath {
                folder = url
            } else {
                folder = url.deletingLastPathComponent()

                let filePath = url.filePath.replacingOccurrences(of: "/", with: "\\")
                if let fileItem = try? await StorageFile.getFileFromPathAsync(filePath).get() {
                    options.itemsToSelect?.append(fileItem)
                }
            }

            // The WinRT path APIs and explorer.exe /select both take native separators.
            let folderPath = folder.filePath.replacingOccurrences(of: "/", with: "\\")
            _ = try? await Launcher.launchFolderPathAsync(folderPath, options).get()
        }
    }
}
