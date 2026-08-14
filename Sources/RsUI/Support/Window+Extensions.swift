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

    public func startObserving<Element>(
        _ emit: @escaping @Sendable () -> Element,
        onChanged: @escaping @MainActor (Window, Element) -> Void
    ) -> Task<Void, Never> {
        let obs = Observations(emit)

        return Task { [weak self] in
            for await value in obs {
                guard let self else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    onChanged(self, value)
                }
            }
        }
    }

    public func useRestoration(_ restore: Bool = true) {
        let windowPosition = App.context.preferences.load(for: WindowPosition.self)

        // Must strong capture the self. Otherwise it's nil in extension, not like in sub-class.
        self.sizeChanged.addHandler { [self] _, _ in
            // FIXME: appWindow.changed事件不工作，窗口单纯移动不会触发此事件。
            self.trackWindowRect(with: windowPosition)
        }
        self.closed.addHandler { [self] _, _ in
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
