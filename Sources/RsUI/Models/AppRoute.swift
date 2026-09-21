import Foundation
import RsFoundation

public struct AppRoute: PreferenceValue {
    /// 单 tab 导航历史上限。运行时赋值小于 1 时钳制为 1（持久化解码路径的
    /// 兜底钳制在 `AppContext.bootstrapGUI` 加载后做）。
    var maxHistoryPages: Int = 32 {
        didSet {
            if maxHistoryPages < 1 { maxHistoryPages = 1 }
        }
    }
    var lastPageURL: URL?

    public init() {
    }
}
