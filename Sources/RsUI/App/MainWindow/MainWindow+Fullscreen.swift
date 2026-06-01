import Foundation
import UWP
import WinUI
import WinAppSDK
import WindowsFoundation

/// Tab FullScreen: 选中 tab 内容全屏显示。
///
/// 全屏显示实现方法:
///     OS 级: appWindow.setPresenter(.fullScreen), 隐藏 Windows TaskBar。
///     应用级 reparent: 把当前选中 tab 的 PageTransitionHost 从 tabContentHost 重新挂载到 
///     root grid 上一个跨行的 overlay。同时把 titleBar 和 navWrapper (含 NavigationView + 
///     TabView strip + Splitter)整体 collapsed。
/// 全屏退出实现方法：
///     退出时反向操作。如果进入前 window 是 maximized, 退出时会还原 maximize 状态。
extension MainWindow {
    func enterTabFullscreen() {
        guard !isInTabFullscreen else { return }
        guard let selectedTab = viewModel?.selectedTab else { return }
        guard let root = self.content as? Grid else { return }
        let frame = self.frame(for: selectedTab)

        // setPresenter(.overlapped) 退出时不还原 maximize 状态，需要提前记录。
        if let presenter = self.appWindow.presenter as? OverlappedPresenter {
            preFullscreenMaximized = (presenter.state == .maximized)
        } else {
            preFullscreenMaximized = false
        }

        var idx: UInt32 = 0
        if tabContentHost.children.indexOf(frame, &idx) {
            tabContentHost.children.removeAt(idx)
        }

        let overlay = Border()
        overlay.child = frame
        root.children.append(overlay)
        try? Grid.setRow(overlay, 0)
        try? Grid.setRowSpan(overlay, 2)
        try? Canvas.setZIndex(overlay, 100)

        titleBar.visibility = .collapsed
        navWrapper?.visibility = .collapsed

        // setPresenter(.fullScreen) 不清除 caption 配置，顶部仍可拖动窗口，
        // 临时关掉 extendsContentIntoTitleBar，退出时恢复。
        self.extendsContentIntoTitleBar = false

        try? appWindow.setPresenter(.fullScreen)

        fullscreenOverlay = overlay
        fullscreenStashedFrame = frame
        isInTabFullscreen = true
    }

    func exitTabFullscreen() {
        guard isInTabFullscreen else { return }
        guard let overlay = fullscreenOverlay else { return }
        guard let frame = fullscreenStashedFrame else { return }
        guard let root = self.content as? Grid else { return }

        overlay.child = nil
        tabContentHost.children.append(frame)

        var idx: UInt32 = 0
        if root.children.indexOf(overlay, &idx) {
            root.children.removeAt(idx)
        }

        titleBar.visibility = .visible
        navWrapper?.visibility = .visible
        self.extendsContentIntoTitleBar = true

        try? appWindow.setPresenter(.overlapped)
        if preFullscreenMaximized, let presenter = self.appWindow.presenter as? OverlappedPresenter {
            try? presenter.maximize()
        }

        fullscreenOverlay = nil
        fullscreenStashedFrame = nil
        isInTabFullscreen = false
        preFullscreenMaximized = false
    }

    // 全屏时拦截 Esc 退出，非全屏时透传给其他处理者。
    func installFullscreenEscapeAccelerator(on root: Grid) {
        let escAccelerator = KeyboardAccelerator()
        escAccelerator.key = .escape
        escAccelerator.invoked.addHandler { [weak self] _, args in
            guard let self, self.isInTabFullscreen else { return }
            self.exitTabFullscreen()
            args?.handled = true
        }
        root.keyboardAccelerators.append(escAccelerator)

        // WinUI auto-shows an "Esc" shortcut tooltip for elements owning a
        // KeyboardAccelerator; suppress it since the accelerator is global.
        root.keyboardAcceleratorPlacementMode = .hidden
    }
}
