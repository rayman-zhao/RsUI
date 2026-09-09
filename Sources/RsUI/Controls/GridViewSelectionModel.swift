import Foundation

/// `GridView` 选择交互的纯逻辑(无 WinRT 依赖,供 RsUITests 单元测试)。
struct GridViewSelectionModel {

    /// 框选几何:归一化后的矩形(向任意方向拖拽均正确)。
    struct MarqueeRect: Equatable {
        let x: Float
        let y: Float
        let width: Float
        let height: Float
    }

    /// 框选启动阈值:拖拽边长小于该值不启动,避免与空白单击混淆。
    static let marqueeEngageThreshold: Float = 4

    /// 起点 + 当前点 → 归一化矩形。
    static func marqueeRect(
        start: (x: Float, y: Float), current: (x: Float, y: Float)
    ) -> MarqueeRect {
        MarqueeRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y))
    }

    /// 矩形是否达到框选启动阈值。
    static func marqueeEngaged(_ rect: MarqueeRect) -> Bool {
        max(rect.width, rect.height) >= marqueeEngageThreshold
    }

    /// 应用框选目标的增量:target 与上次已应用集合的差集
    /// (select = 新进矩形者,deselect = 移出矩形者)。
    static func marqueeDelta(
        applied: Set<Int32>, target: Set<Int32>
    ) -> (select: Set<Int32>, deselect: Set<Int32>) {
        (target.subtracting(applied), applied.subtracting(target))
    }

    /// 复选框可见性:功能开启且该条目悬停中(资源管理器式,只浮现在鼠标
    /// 当前条目上)。
    static func isCheckBoxVisible(isEnabled: Bool, isHovered: Bool) -> Bool {
        isEnabled && isHovered
    }
}
