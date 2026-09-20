import WinAppSDK
import WinUI
import WindowsFoundation

/// 条目增删/顺移的「淡入滑动」过渡动画 provider（标准列表观感）。
///
/// `ItemCollectionTransitionProvider` 的代码子类，节奏对齐 `PageTransitionHost`
/// 的 200ms / 40px 房风：
/// - 新增（含首次实现化）：淡入 + 自下方 40px 上滑入位；
/// - 移除：原地淡出（旧元素由框架保留至动画完成再回收）；
/// - 顺移（插入/移除导致的索引位移）：视觉偏移从旧位置平滑过渡到新位置，
///   布局切换（`layoutTransition`）触发的位移同样平滑过渡；
/// - `setIds` 式「重置 + 重建」会同时触发重置移除与批量新增，为避免先整体
///   淡出再逐个滑入的双重闪动，同批存在新增时跳过重置触发的移除（与原生
///   `LinedFlowLayoutItemCollectionTransitionProvider` 同策略）。
///
/// 用法：赋给 `ItemsView.itemTransitionProvider`（`RsUI.ItemsView` 默认即本类）：
///
/// ```swift
/// list.itemTransitionProvider = FadeSlideItemTransitionProvider()
/// ```
public final class FadeSlideItemTransitionProvider: ItemCollectionTransitionProvider {

    /// 入场与顺移动画时长（默认 200ms，对齐 `PageTransitionHost`）。
    public var duration: TimeSpan
    /// 移除淡出时长（默认 150ms，离场略轻快）。
    public var fadeOutDuration: TimeSpan
    /// 入场上滑距离（DIP，默认 40）。
    public var slideDistance: Float

    public init(
        duration: TimeSpan = TimeSpan(duration: 200 * 10_000),
        fadeOutDuration: TimeSpan = TimeSpan(duration: 150 * 10_000),
        slideDistance: Float = 40
    ) {
        self.duration = duration
        self.fadeOutDuration = fadeOutDuration
        self.slideDistance = slideDistance
        super.init()
    }

    /// 基类默认恒返回 `false`（不动画），这里放开为全部参与（未实现的屏幕外
    /// 条目本就不会产生 transition）。
    public override func shouldAnimateCore(_ transition: ItemCollectionTransition!) throws -> Bool {
        true
    }

    public override func startTransitions(_ transitions: AnyIVector<ItemCollectionTransition?>!) throws {
        guard let transitions, !transitions.isEmpty else { return }
        // 本方法经 CompositionTarget.Rendering（COM 回调路径）调用，Swift 异常
        // 不可逃逸 —— 所有 WinRT 调用一律 try?。

        // setIds 式重置同批携带移除与新增：有新增时跳过重置移除，只播整体重新入场。
        let hasAdds = transitions.contains { $0?.operation == .add }

        var batch: CompositionScopedBatch?
        var progresses: [ItemCollectionTransitionProgress] = []
        var easing: CubicBezierEasingFunction?

        for case let transition? in transitions {
            if hasAdds, transition.operation == .remove,
                Self.triggers(transition.triggers, contain: .collectionChangeReset)
            { continue }
            // start() 即向框架承诺"我来动画这个 transition"（element 要经返回的
            // progress 读取）；此后任何失败都必须补 complete()，否则框架会一直等。
            guard let progress = try? transition.start() else { continue }
            guard let element = progress.element,
                let visual = try? ElementCompositionPreview.getElementVisual(element),
                let compositor = visual.compositor
            else {
                try? progress.complete()
                continue
            }

            if batch == nil {
                batch = try? compositor.createScopedBatch(CompositionBatchTypes.animation)
                // CubicEase easeOut 的 composition 等价（easeOutCubic 控制点）。
                easing = try? compositor.createCubicBezierEasingFunction(
                    Vector2(x: 0.215, y: 0.61), Vector2(x: 0.355, y: 1))
            }
            guard let batch else {
                try? progress.complete()
                continue
            }
            progresses.append(progress)
            startAnimations(for: transition, visual: visual, compositor: compositor, easing: easing)
        }

        guard let batch else { return }
        try? batch.end()
        // 批次完成（批内动画全部结束）后才 complete，框架随之回收移除的旧元素。
        batch.completed.addHandler { _, _ in
            for progress in progresses { try? progress.complete() }
        }
    }

    // MARK: - 动画搭建

    private func startAnimations(
        for transition: ItemCollectionTransition,
        visual: Visual,
        compositor: Compositor,
        easing: CubicBezierEasingFunction?
    ) {
        switch transition.operation {
        case .add:
            // 淡入 + 上滑入位：布局已把元素放到最终位置，offset 从「当前位置 +
            // slideDistance」动画回「当前位置」（动画结束回到布局基准值）。
            let offset = visual.offset
            if let fade = try? compositor.createScalarKeyFrameAnimation() {
                try? fade.insertKeyFrame(0, 0, easing)
                try? fade.insertKeyFrame(1, 1, easing)
                fade.duration = duration
                try? visual.startAnimation("Opacity", fade)
            }
            if let slide = try? compositor.createVector3KeyFrameAnimation() {
                try? slide.insertKeyFrame(
                    0, Vector3(x: offset.x, y: offset.y + slideDistance, z: offset.z), easing)
                try? slide.insertKeyFrame(1, offset, easing)
                slide.duration = duration
                try? visual.startAnimation("Offset", slide)
            }
        case .remove:
            // 原地淡出；不动 offset，避免与顺移条目的补间互相干扰。
            if let fade = try? compositor.createScalarKeyFrameAnimation() {
                try? fade.insertKeyFrame(0, 1, easing)
                try? fade.insertKeyFrame(1, 0, easing)
                fade.duration = fadeOutDuration
                try? visual.startAnimation("Opacity", fade)
            }
        case .move:
            // 平滑顺移：元素已被排到新位置，offset 从「新位置 - 位移量」（即旧
            // 位置）动画到「新位置」。
            let delta = Vector3(
                x: transition.newBounds.x - transition.oldBounds.x,
                y: transition.newBounds.y - transition.oldBounds.y,
                z: 0)
            guard delta.x != 0 || delta.y != 0 else { return }
            let offset = visual.offset
            if let slide = try? compositor.createVector3KeyFrameAnimation() {
                try? slide.insertKeyFrame(
                    0, Vector3(x: offset.x - delta.x, y: offset.y - delta.y, z: offset.z), easing)
                try? slide.insertKeyFrame(1, offset, easing)
                slide.duration = duration
                try? visual.startAnimation("Offset", slide)
            }
        default:
            // 枚举目前仅 add/remove/move；未来新增的 case 默认不动画。
            break
        }
    }

    /// 位测试 triggers 是否包含某标志（C flags 枚举，投影暴露 rawValue）。
    private static func triggers(
        _ triggers: ItemCollectionTransitionTriggers,
        contain flag: ItemCollectionTransitionTriggers
    ) -> Bool {
        (triggers.rawValue & flag.rawValue) != 0
    }
}
