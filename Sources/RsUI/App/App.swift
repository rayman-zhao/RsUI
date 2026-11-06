import Foundation
import RsFoundation
import UWP
import WinAppSDK
import WinSDK
import WinUI

open class App: SwiftApplication, @unchecked Sendable {
    public nonisolated static let context = AppContext()

    /// App identity — support directories, preferences and the single-instance key
    /// all derive from it. Override to declare your app's identity; the default keeps
    /// the framework's own. Read once in `init`, before anything else.
    open class var groupName: String { "SwiftWorks" }
    open class var productName: String { "RsUI" }
    open class var resourceBundle: Bundle { .main }
    /// Modules constructed by the app subclass. Read once in `onLaunched` (MainActor,
    /// context ready) — modules may depend on `App.context` at construction. Each
    /// access constructs fresh instances; the framework reads it exactly once.
    open class var modules: [any Module] { [] }

    public nonisolated required init() {
        // App 构造发生在主线程（SwiftApplication 启动链，同 SettingsCard 构造器
        // 兑换先例）；@MainActor 的身份 class var 在闭包内读取并消费，子类由此
        // 免写任何隔离关键字
        MainActor.assumeIsolated {
            App.context.bootstrap(group: Self.groupName, product: Self.productName, resourceBundle: Self.resourceBundle)
        }
        super.init()

        // AppInstance can be used start from app initilization.
        AppInstance.redirectOrRegister(
            for: "\(App.context.groupName)/\(App.context.productName)"
        ) { [weak self] args in
            guard let self else { return }
            self.onActivated(args)
        }
    }

    override open func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        // Application.current.requestedTheme can be used only start from launch.
        App.context.bootstrapGUI()
        App.context.loadModules(Self.modules)

        JumpList.register(
            arguments: "--new-window", displayName: App.context.tr("newWindow"),
            logo: App.context.iconAppxUri)

        // 桌面应用（含 full-trust 打包）的激活参数走进程命令行；WinUI 的
        // LaunchActivatedEventArgs.arguments 是 UWP 激活字符串通道，恒不含内容。
        // 携带文件路径时文件意图优先于上次页面恢复，且与热启动同样以最小模式
        // 开查看器窗口（冷热行为等价）
        if let openedURLs = Self.openedFileURLs(in: ProcessInfo.processInfo.arguments.dropFirst()) {
            App.context.openNewWindow(with: openedURLs, forceMinimalMode: true)
        } else {
            let window = MainWindow(urls: App.context.route.lastPageURL.map { [$0] } ?? [])
            try? window.activate()
            window.bringToForeground()
        }
    }

    override open func onShutdown(exitCode: Int32) {
        App.context.releaseModules()
    }

    /// 热启动入口：仅接收其他进程重定向来的激活；冷启动走 `onLaunched`，一次
    /// 激活只经其一，两条路径须保持行为等价
    open func onActivated(_ args: AppActivationArguments?) {
        if let urls = Self.redirectedFileURLs(args) {
            App.context.openNewWindow(with: urls, forceMinimalMode: true)
        } else if Self.completeOAuthAuthRequest(args) {
            return
        } else {
            let window = MainWindow()
            try? window.activate()
            window.bringToForeground()
        }
    }

    private static func openedFileURLs(in arguments: some Sequence<String>) -> [URL]? {
        // 重定向激活的参数串是含 argv[0] 的完整命令行，本进程 exe 须排除
        let ownExecutable = ProcessInfo.processInfo.arguments.first?.lowercased()
        var urls: [URL] = []
        var seen = Set<String>()
        for token in arguments {
            let key = token.lowercased()
            guard key != ownExecutable, seen.insert(key).inserted else { continue }
            // 目录路径通常不带尾分隔符，目录性必须由这次 stat 落进 directoryHint，
            // 否则下游 hasDirectoryPath 纯词法判断会把目录当文件分流
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: token, isDirectory: &isDirectory) else { continue }
            urls.append(URL(filePath: token, directoryHint: isDirectory.boolValue ? .isDirectory : .notDirectory))
        }
        return urls.isEmpty ? nil : urls
    }

    /// 热启动重定向的两种形态：FTA 双击是 `.file`（full-trust 打包同样走此通道，
    /// MSIX 实测主实例收到 IFileActivatedEventArgs）；命令行激活（RsShell verb/CLI）
    /// 是 `.launch` + 含 argv[0] 的完整命令行。冷启动不走重定向——argv 直读。
    /// 其余形态落 default 哨兵日志。
    private static func redirectedFileURLs(_ args: AppActivationArguments?) -> [URL]? {
        guard let args else { return nil }
        switch args.kind {
        case .launch:
            guard let launch = args.data as? ILaunchActivatedEventArgs else {
                log.warning("onActivated: launch data is \(type(of: args.data))")
                return nil
            }
            log.debug("onActivated: arguments=\(launch.arguments.debugDescription)")

            // CommandLineToArgvW 即 CRT argv 解析规则本体；非路径 token（`--new-window`
            // 等旗标）经存在性检查自然淘汰，格式知识留在模块层
            var argc: Int32 = 0
            guard let argv = CommandLineToArgvW(launch.arguments.wideString, &argc), argc > 0 else { return nil }
            defer { _ = LocalFree(HLOCAL(argv)) }
            let tokens = (0..<Int(argc)).compactMap { argv[$0].map { String(decodingCString: $0, as: UTF16.self) } }
            return openedFileURLs(in: tokens)
        case .file:
            guard let file = args.data as? IFileActivatedEventArgs else {
                log.warning("onActivated: file data is \(type(of: args.data))")
                return nil
            }
            return openedFileURLs(in: file.files?.compactMap { $0?.path } ?? [])
        default:
            log.warning("onActivated: unhandled activation kind \(String(describing: args.kind))")
            return nil
        }
    }

    /// 协议激活形态的 OAuth 回调认领：授权码流程由系统浏览器重定向到应用注册的
    /// 自定义 scheme，经重定向激活送达主实例（授权请求必然由本实例发起，
    /// state/PKCE 同进程保存），`completeAuthRequest` 配对成功即解除
    /// RequestAuthWithParamsAsync 的等待，无窗口动作。未配对（非回调 URI 或无
    /// 挂起请求）返回 false 走默认开窗路径。
    private static func completeOAuthAuthRequest(_ args: AppActivationArguments?) -> Bool {
        guard let args, args.kind == .`protocol`, let protocolArgs = args.data as? IProtocolActivatedEventArgs else { return false }

        do {
            return try OAuth2Manager.completeAuthRequest(protocolArgs.uri)
        } catch {
            log.warning("onActivated: completeAuthRequest threw: \(error)")
        }
        return false
    }
}
