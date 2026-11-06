import Foundation
import Observation
import RsFoundation
import UWP
import WinAppSDK
import WinSDK
import WinUI

// 事件回调为 @Sendable 闭包；本类只在 XAML UI 线程的事件处理器中读写，跨域安全
private class WindowPosition: PreferenceValue {
    var windowWidth: Int = 1440
    var windowHeight: Int = 800
    var windowX: Int = 100
    var windowY: Int = 100
    var isMaximized: Bool = true

    required init() {
    }

    var windowRect: UWP.RectInt32 {
        return UWP.RectInt32(
            x: Int32(windowX),
            y: Int32(windowY),
            width: Int32(windowWidth),
            height: Int32(windowHeight)
        )
    }
}

extension Window {
    /// `activate()` 不越过 Windows 前台锁——进程不在前台时新窗止步于任务栏闪烁
    /// (重定向激活、文件关联启动均如此)。先以原生 SetForegroundWindow 兑现重定向
    /// 链路授予的前台权;该授权会被授权后的下一次用户输入撤销(激活到开窗的间隙
    /// 里有输入即失效),被撤销时退回 AttachThreadInput 配方——把本线程短暂并入
    /// 前台线程的输入队列,以前台身份 BringWindowToTop,不受前台锁约束。
    public func bringToForeground() {
        guard let appWindow else { return }
        // 桌面投影中 WindowId.value 即顶层 HWND(Win32Interop.GetWindowIdFromHWND 的恒等包装)
        let hwnd = HWND(bitPattern: UInt(appWindow.id.value))
        if SetForegroundWindow(hwnd) { return }

        guard let foreground = GetForegroundWindow() else {
            log.warning("bringToForeground: no foreground window to attach to")
            return
        }
        let foregroundThread = GetWindowThreadProcessId(foreground, nil)
        let currentThread = GetCurrentThreadId()
        guard foregroundThread != 0, foregroundThread != currentThread,
            AttachThreadInput(currentThread, foregroundThread, true)
        else {
            log.warning("bringToForeground: SetForegroundWindow denied for hwnd \(appWindow.id.value)")
            return
        }
        defer { AttachThreadInput(currentThread, foregroundThread, false) }
        BringWindowToTop(hwnd)
        _ = SetForegroundWindow(hwnd)
    }

    public func useMicaBackdrop() {
        self.extendsContentIntoTitleBar = true
        self.appWindow.titleBar.preferredHeightOption = .tall

        // 设置 Mica 背景
        let micaBackdrop = MicaBackdrop()
        micaBackdrop.kind = .base
        self.systemBackdrop = micaBackdrop
    }

    public func useRestoration(_ restore: Bool = true) {
        let windowPosition = App.context.preferences.load(for: WindowPosition.self)

        // weak 捕获：强捕获会形成 原生 window → 事件表 → 闭包 → Swift 窗口实例
        // 的自持环，多窗口会话里关掉的窗口整簇滞留内存（RLT 回归测试覆盖）。
        // 子类实例上这两个事件触发时 weak 可正常解析（重构前的 RestorableWindow
        // 即此写法；「extension 里必须 strong 捕获」的旧结论不成立）。
        self.sizeChanged.addHandler { [weak self] _, _ in
            guard let self else { return }
            // FIXME: appWindow.changed事件不工作，窗口单纯移动不会触发此事件。
            self.trackWindowRect(with: windowPosition)
        }
        self.closed.addHandler { [weak self] _, _ in
            guard let self else { return }
            // FIXME: appWindow.changed事件不工作，窗口移动-最大化-关闭时，无法记录到此前的恢复位置。不过其实也可以不保存，恢复窗口在中间即可。
            self.trackWindowRect(with: windowPosition)
            App.context.preferences.save(windowPosition)
        }

        if restore {
            restoreWindowRect(with: windowPosition)
        }
    }

    private func restoreWindowRect(with windowPosition: WindowPosition) {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter
        else { return }

        let maximized = windowPosition.isMaximized  // moveAndResize will cause pref changed in event, so need to reserve here
        try? hwnd.moveAndResize(windowPosition.windowRect)
        if maximized {
            try? presenter.maximize()
        }
    }

    private func trackWindowRect(with windowPosition: WindowPosition) {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter
        else { return }

        if presenter.state == .restored {
            windowPosition.windowX = Int(hwnd.position.x)
            windowPosition.windowY = Int(hwnd.position.y)
            windowPosition.windowWidth = Int(hwnd.size.width)
            windowPosition.windowHeight = Int(hwnd.size.height)
            windowPosition.isMaximized = false
        } else if presenter.state == .maximized {
            windowPosition.isMaximized = true
        }
    }
}
