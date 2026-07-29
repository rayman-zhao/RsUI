import Foundation
import RsFoundation
import UWP
import WinAppSDK
import WinUI

private struct WindowPosition: PreferenceValue {
    var windowWidth: Int = 1440
    var windowHeight: Int = 800
    var windowX: Int = 100
    var windowY: Int = 100
    var isMaximized: Bool = true

    var windowRect: UWP.RectInt32 {
        return UWP.RectInt32(
            x: Int32(windowX),
            y: Int32(windowY),
            width: Int32(windowWidth),
            height: Int32(windowHeight)
        )
    }
}

class RestorableWindow: MicaWindow {
    private var windowPosition: WindowPosition

    init(_ restore: Bool = true) {
        windowPosition = App.context.preferences.load(for: WindowPosition.self)
        super.init()

        self.sizeChanged.addHandler { [weak self] _, _ in
            guard let self else { return }

            self.trackWindowSize()
        }
        self.closed.addHandler { [weak self] _, _ in
            guard let self else { return }

            // FIXME: appWindow.changed事件不工作，此处窗口最大化时记录有缺陷。其实也可以不保存，恢复窗口在中间即可。
            self.trackWindowPosition()
            App.context.preferences.save(windowPosition)
        }
        
        if restore {
            restoreWindowRect()
        }
    }

    private func restoreWindowRect() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter
        else { return }

        let maximized = windowPosition.isMaximized  //moveAndResize will cause pref changed in event, so need to reserve here
        try? hwnd.moveAndResize(windowPosition.windowRect)
        if maximized {
            try? presenter.maximize()
        }
    }

    private func trackWindowSize() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter
        else { return }

        if presenter.state == .restored {
            windowPosition.windowWidth = Int(hwnd.size.width)
            windowPosition.windowHeight = Int(hwnd.size.height)
            windowPosition.isMaximized = false
        } else if presenter.state == .maximized {
            windowPosition.isMaximized = true
        }
    }

    private func trackWindowPosition() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter
        else { return }

        if presenter.state == .restored {
            windowPosition.windowX = Int(hwnd.position.x)
            windowPosition.windowY = Int(hwnd.position.y)
        }
    }
}
