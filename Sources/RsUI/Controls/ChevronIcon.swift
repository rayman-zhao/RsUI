import UWP
import WinUI
import WindowsFoundation

/// 带旋转动画的 chevron 图标控件。
/// 调用方负责触发时机，此控件只负责动画。
///
/// 用法示例：
///   // SettingsExpander（向下展开，0°→180°）
///   let chevron = ChevronIcon(glyph: "\u{E70D}", expandAngle: 180)
///
///   // 面包屑下拉按钮（向右→向下，0°→90°）
///   let chevron = ChevronIcon(glyph: "\u{E974}", expandAngle: 90)
///
///   // 展开时调用
///   chevron.expand()
///   // 收起时调用
///   chevron.collapse()
public class ChevronIcon: WinUI.FontIcon {
    private let expandAngle: Double
    private let durationMs: Int64
    private let transform = WinUI.CompositeTransform()
    private var isAnimating = false

    public init(glyph: String, expandAngle: Double, durationMs: Int64 = 150) {
        self.expandAngle = expandAngle
        self.durationMs = durationMs
        super.init()
        self.glyph = glyph
        self.renderTransform = transform
        self.renderTransformOrigin = WindowsFoundation.Point(x: 0.5, y: 0.5)
    }

    /// 旋转到展开角度
    public func expand() {
        animate(to: expandAngle)
    }

    /// 旋转回初始角度（0°）
    public func collapse() {
        animate(to: 0)
    }

    private func animate(to angle: Double) {
        guard !isAnimating else { return }
        isAnimating = true

        let anim = WinUI.DoubleAnimation()
        anim.from = transform.rotation
        anim.to = angle
        anim.duration = WinUI.Duration(
            timeSpan: WindowsFoundation.TimeSpan(duration: durationMs * 10_000),
            type: .timeSpan
        )
        let easing = WinUI.CubicEase()
        easing.easingMode = .easeOut
        anim.easingFunction = easing

        let sb = WinUI.Storyboard()
        try? WinUI.Storyboard.setTarget(anim, transform)
        try? WinUI.Storyboard.setTargetProperty(anim, "Rotation")
        sb.children.append(anim)
        sb.completed.addHandler { [weak self] _, _ in
            self?.transform.rotation = angle
            self?.isAnimating = false
        }
        try? sb.begin()
    }
}
