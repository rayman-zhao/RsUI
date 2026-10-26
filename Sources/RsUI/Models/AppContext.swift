import Foundation
import Observation
import RsFoundation
import UWP
import WinUI
import WindowsFoundation

// 进程级单例（App.context）：读写全部发生在主线程。@unchecked Sendable 仅为满足
// App 的 nonisolated 构造器链——App.context 是 nonisolated static let（类型须 Sendable），
// 构造只能留在 nonisolated 上下文完成；模块实例不经过 bootstrap，见 loadModules(_:)。
@Observable
public final class AppContext: @unchecked Sendable {
    public private(set) var groupName: String
    public private(set) var productName: String
    public private(set) var resourceBundle: Bundle

    /// 支持目录与偏好存储由 group/product 推导、首次访问才落盘：static 构造看不见
    /// 子类配置（App.init 两段式），默认阶段若急切 ensure 会先建出框架默认身份的
    /// stray 目录。真实 app 首次访问必然发生在 bootstrap 之后。
    public var supportDirectory: URL {
        guard let support = URL.applicationSupportDirectory.ensuringChild(
            named: "\(groupName)/\(productName)/")
        else {
            fatalError("AppContext: failed to ensure support directory for \(groupName)/\(productName)")
        }
        return support
    }

    public var preferences: Preferences {
        JSONPreferences.makeStandard(group: groupName, product: productName)
    }

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
            // mutations happen on the UI thread; the WinRT side is main-actor projected
            MainActor.assumeIsolated {
                Application.current.requestedTheme = theme.applicationTheme
            }
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

    internal private(set) var modules: [any Module] = []

    init() {
        groupName = "SwiftWorks"
        productName = "RsUI"
        resourceBundle = .main
    }

    func bootstrap(group: String, product: String, resourceBundle: Bundle) {
        groupName = group
        productName = product
        self.resourceBundle = resourceBundle
    }

    @MainActor func bootstrapGUI() {
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

    /// 模块实例由 App 子类在主 actor 上构造后传入（App.makeModules()）——模块
    /// 构造可依赖 context 就绪；@MainActor Module 实例不经 nonisolated 的
    /// bootstrap 传递。
    @MainActor func loadModules(_ modules: [any Module]) {
        self.modules = modules
    }

    @MainActor func releaseModules() {
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

    @MainActor public func requireXaml<T>(withString xaml: String, trTable: String? = nil) -> T {
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

    @MainActor public func requireXaml<T>(withResource name: String, trTable: String? = nil) -> T {
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
    @MainActor public func openNewWindow(
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
    @MainActor public func revealInFileExplorer(_ url: URL) {
        Task {
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
