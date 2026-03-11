import Foundation
import RsHelper

/// 状态栏偏好设置，负责保存整栏显示状态和各状态项的显示配置。
public struct StatusBarPreferences: Preferable {
    /// 主窗口底部状态栏是否显示。
    public var isStatusBarVisible: Bool = true

    /// 被用户隐藏的状态项 ID 列表。
    public var hiddenItemIDs: [String] = []

    public init() {}

    public init(isStatusBarVisible: Bool = true, hiddenItemIDs: [String]) {
        self.isStatusBarVisible = isStatusBarVisible
        self.hiddenItemIDs = hiddenItemIDs
    }
}
