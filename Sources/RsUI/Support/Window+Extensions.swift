import Foundation
import Observation
import RsFoundation
import UWP
import WinAppSDK
import WinUI

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
