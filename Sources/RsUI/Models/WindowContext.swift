import Foundation
import WinAppSDK
import WinSDK

/// 模块所附窗口上下文信息
public struct WindowContext {
    public let hwnd: AppWindow
    public let statusBar: StatusBarService
}
