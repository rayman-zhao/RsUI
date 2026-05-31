import Foundation
import WinUI
import WinAppSDK
import WinSDK
import RsHelper
import CRsUIJumpList

open class App: SwiftApplication {
    public static var context = AppContext.cli()

    let group: String
    let product: String
    let bundle: Bundle
    let moduleTypes: [Module.Type]

    // 持有单实例注册对象，保证 activated 事件订阅在 app 生命周期内不被释放。
    private var singleInstance: AppInstance?

    public required convenience init() {
        self.init("SwiftWorks", "RsUI", .main, [])
    }

    public init(_ group: String, _ product: String, _ bundle: Bundle, _ moduleTypes: [Module.Type]) {
        self.group = group
        self.product = product
        self.bundle = bundle
        self.moduleTypes = moduleTypes

        super.init()
    }

    private var appUserModelID: String {
        // Stable across releases — taskbar uses this to identify the app for
        // both pinning and jump list lookup. Don't change once shipped.
        return "\(group).\(product)"
    }

    override open func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        // 单实例：同一 app 只保留一个进程。第二次启动（含任务栏 --new-window 重启的 EXE）
        // 把激活重定向给已运行实例后退出，由已运行实例进程内开新窗口——消除多进程并发写
        // preferences/JSON 的竞争，行为对齐 VSCode。任一步失败则 fail-open 照常启动。
        let keyInstance = try? AppInstance.findOrRegisterForKey(appUserModelID)
        if let keyInstance, !keyInstance.isCurrent {
            redirectActivationAndExit(to: keyInstance)
            return
        }
        if keyInstance == nil {
            logError("single-instance: findOrRegisterForKey 失败，退回独立进程运行")
        }
        singleInstance = keyInstance

        // Need to init context after super.init() because some WinUI APIs require the application to be initialized
        App.context = AppContext.gui(group, product, bundle)
        App.context.modules = moduleTypes.map { $0.init() }

        registerTaskbarJumpList()

        let forceHome = parseForceHomeFromCommandLine(args)
        let mainWindow = forceHome ? MainWindow(forceHomeOnLaunch: true) : MainWindow()
        try! mainWindow.activate()

        observeRedirectedActivations(keyInstance, uiQueue: mainWindow.dispatcherQueue)
    }

    private func redirectActivationAndExit(to keyInstance: AppInstance) {
        // redirectActivationToAsync 异步：把本进程的激活转交给已运行实例后，本进程不创建
        // 任何窗口、直接退出。
        let activatedArgs = try? AppInstance.getCurrent().getActivatedEventArgs()
        Task {
            if let activatedArgs {
                try? await keyInstance.redirectActivationToAsync(activatedArgs).get()
            } else {
                logError("single-instance: getActivatedEventArgs 失败，重定向跳过")
            }
            ExitProcess(0)
        }
    }

    private func observeRedirectedActivations(_ keyInstance: AppInstance?, uiQueue: DispatcherQueue?) {
        // activated 在后台线程触发，进程内开窗必须回到 UI 线程。任何被重定向过来的激活都
        // 视为"开新窗口"，复用 openDetachedWindow 家族在进程内开一个 Home 窗口。
        keyInstance?.activated.addHandler { _, _ in
            _ = try? uiQueue?.tryEnqueue {
                MainWindow.openDetachedWindowAtHome()
            }
        }
    }

    private func logError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private func parseForceHomeFromCommandLine(_ args: WinUI.LaunchActivatedEventArgs) -> Bool {
        let flag = "--new-window"
        if CommandLine.arguments.contains(flag) {
            return true
        }
        // LaunchActivatedEventArgs.arguments is a space-joined string when the
        // process is activated through certain shell paths (jump list included).
        return args.arguments.split(separator: " ").contains { $0 == flag }
    }

    private func registerTaskbarJumpList() {
        // Swift String 转成以 null 结尾的宽字符数组，直接当 const wchar_t* 传给 C 桥接，
        // 省去逐参数嵌套 withCString。
        func wide(_ s: String) -> [UInt16] { Array(s.utf16) + [0] }

        let aumid = appUserModelID
        let aumidStatus = rs_set_app_user_model_id(wide(aumid))
        if aumidStatus != 0 {
            FileHandle.standardError.write(
                Data("rs_set_app_user_model_id failed: HRESULT 0x\(String(aumidStatus, radix: 16))\n".utf8))
        }

        var exeBuf = [UInt16](repeating: 0, count: 1024)
        let written = exeBuf.withUnsafeMutableBufferPointer {
            rs_get_self_exe_path($0.baseAddress, Int32($0.count))
        }
        guard written > 0 else {
            FileHandle.standardError.write(Data("rs_get_self_exe_path failed\n".utf8))
            return
        }
        let exePath = String(decoding: exeBuf[0..<Int(written)], as: UTF16.self)

        let title = App.context.tr("newWindow")
        let registerStatus = rs_register_new_window_task(
            wide(aumid), wide(exePath), wide("--new-window"), wide(title), wide(exePath), 0)
        if registerStatus != 0 {
            FileHandle.standardError.write(
                Data("rs_register_new_window_task failed: HRESULT 0x\(String(registerStatus, radix: 16))\n".utf8))
        }
    }

    override open func onShutdown(exitCode: Int32) {
        // Allow modules to deinit
        App.context.modules = []
    }
}
