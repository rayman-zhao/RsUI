import UWP
import WinUI
import WindowsFoundation

/// 页面切换动画容器。
/// 用 Grid 叠加新旧内容，通过 Opacity + TranslateX 动画实现方向性过渡。
class PageTransitionHost: Grid {
    // MARK: - 配置
    private let animationDurationMs: Int64 = 200
    private let slideDistance: Double = 40.0

    // MARK: - 状态
    private var isAnimating = false
    private var currentWrapper: Border?
    private var pendingTransition: (content: UIElement?, direction: NavigationDirection)?

    // MARK: - 公开接口

    func transition(to newContent: UIElement?, direction: NavigationDirection) {
        if isAnimating {
            pendingTransition = (newContent, direction)
            return
        }

        let oldWrapper = currentWrapper

        guard let newContent else {
            currentWrapper = nil
            if let oldWrapper {
                runExitAnimation(wrapper: oldWrapper, direction: direction)
            }
            return
        }

        let wrapper = Border()
        let transform = CompositeTransform()
        wrapper.child = newContent
        wrapper.renderTransform = transform
        wrapper.opacity = 0

        switch direction {
        case .forward:  transform.translateX = slideDistance
        case .backward: transform.translateX = -slideDistance
        case .none:     transform.translateX = 0
        }

        self.children.append(wrapper)
        currentWrapper = wrapper

        runTransition(oldWrapper: oldWrapper, newWrapper: wrapper, newTransform: transform, direction: direction)
    }

    // MARK: - 动画实现

    private func runTransition(
        oldWrapper: Border?,
        newWrapper: Border,
        newTransform: CompositeTransform,
        direction: NavigationDirection
    ) {
        isAnimating = true
        let storyboard = Storyboard()
        let duration = makeDuration(milliseconds: animationDurationMs)
        let easing = CubicEase()
        easing.easingMode = .easeOut

        // 新内容：淡入 + 滑入
        let newOpacity = DoubleAnimation()
        newOpacity.from = 0.0
        newOpacity.to = 1.0
        newOpacity.duration = duration
        newOpacity.easingFunction = easing
        try? Storyboard.setTarget(newOpacity, newWrapper)
        try? Storyboard.setTargetProperty(newOpacity, "Opacity")
        storyboard.children.append(newOpacity)

        if direction != .none {
            let newSlide = DoubleAnimation()
            newSlide.from = direction == .forward ? slideDistance : -slideDistance
            newSlide.to = 0.0
            newSlide.duration = duration
            newSlide.easingFunction = easing
            try? Storyboard.setTarget(newSlide, newTransform)
            try? Storyboard.setTargetProperty(newSlide, "TranslateX")
            storyboard.children.append(newSlide)
        }

        // 旧内容：淡出 + 滑出
        if let oldWrapper {
            let oldTransform = oldWrapper.renderTransform as? CompositeTransform

            let oldOpacity = DoubleAnimation()
            oldOpacity.from = 1.0
            oldOpacity.to = 0.0
            oldOpacity.duration = duration
            oldOpacity.easingFunction = easing
            try? Storyboard.setTarget(oldOpacity, oldWrapper)
            try? Storyboard.setTargetProperty(oldOpacity, "Opacity")
            storyboard.children.append(oldOpacity)

            if direction != .none, let oldTransform {
                let oldSlide = DoubleAnimation()
                oldSlide.from = 0.0
                oldSlide.to = direction == .forward ? -slideDistance : slideDistance
                oldSlide.duration = duration
                oldSlide.easingFunction = easing
                try? Storyboard.setTarget(oldSlide, oldTransform)
                try? Storyboard.setTargetProperty(oldSlide, "TranslateX")
                storyboard.children.append(oldSlide)
            }
        }

        storyboard.completed.addHandler { [weak self] _, _ in
            guard let self else { return }
            if let oldWrapper {
                oldWrapper.child = nil
                self.removeChild(oldWrapper)
            }
            self.isAnimating = false

            if let pending = self.pendingTransition {
                self.pendingTransition = nil
                self.transition(to: pending.content, direction: pending.direction)
            }
        }

        try? storyboard.begin()
    }

    private func runExitAnimation(wrapper: Border, direction: NavigationDirection) {
        isAnimating = true
        let storyboard = Storyboard()
        let duration = makeDuration(milliseconds: animationDurationMs)
        let easing = CubicEase()
        easing.easingMode = .easeOut

        let opacity = DoubleAnimation()
        opacity.from = 1.0
        opacity.to = 0.0
        opacity.duration = duration
        opacity.easingFunction = easing
        try? Storyboard.setTarget(opacity, wrapper)
        try? Storyboard.setTargetProperty(opacity, "Opacity")
        storyboard.children.append(opacity)

        storyboard.completed.addHandler { [weak self] _, _ in
            guard let self else { return }
            wrapper.child = nil
            self.removeChild(wrapper)
            self.isAnimating = false

            if let pending = self.pendingTransition {
                self.pendingTransition = nil
                self.transition(to: pending.content, direction: pending.direction)
            }
        }

        try? storyboard.begin()
    }

    private func removeChild(_ element: UIElement) {
        var idx: UInt32 = 0
        if self.children.indexOf(element, &idx) {
            self.children.removeAt(idx)
        }
    }

    private func makeDuration(milliseconds: Int64) -> Duration {
        Duration(
            timeSpan: TimeSpan(duration: milliseconds * 10_000),
            type: .timeSpan
        )
    }
}
