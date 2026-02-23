import Foundation
import WinUI
import WinSDK

/// 所有页面必须遵循的协议，用于在 MainWindow 框架内显示页面
public protocol AppPage: AnyObject {
    /// 页面的根视图元素，将被附加到框架中
    var rootView: WinUI.UIElement { get }

    func onAppearanceChanged()
}