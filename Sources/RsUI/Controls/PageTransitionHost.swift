import UWP
import WinUI
import WindowsFoundation

/// Hosts page content and applies WinUI-style navigation transition overrides.
class PageTransitionHost: Grid {
    private let animationDurationMs: Int64 = 200
    private let slideDistance: Double = 40.0

    private var isAnimating = false
    private var currentWrapper: Border?
    private var pendingTransition: (content: UIElement?, transitionInfo: NavigationTransitionInfo?)?

    func transition(to newContent: UIElement?, transitionInfo: NavigationTransitionInfo? = nil) {
        if isAnimating {
            pendingTransition = (newContent, transitionInfo)
            return
        }

        let oldWrapper = currentWrapper

        guard let newContent else {
            currentWrapper = nil
            if let oldWrapper {
                runExitAnimation(wrapper: oldWrapper, transitionInfo: transitionInfo)
            }
            return
        }

        let wrapper = Border()
        let transform = CompositeTransform()
        let offset = transitionOffset(for: transitionInfo)
        transform.translateX = offset.x
        transform.translateY = offset.y

        wrapper.child = newContent
        wrapper.renderTransform = transform
        wrapper.opacity = 0

        children.append(wrapper)
        currentWrapper = wrapper

        if transitionInfo is SuppressNavigationTransitionInfo {
            oldWrapper?.child = nil
            if let oldWrapper {
                removeChild(oldWrapper)
            }
            wrapper.opacity = 1
            transform.translateX = 0
            transform.translateY = 0
            return
        }

        runTransition(
            oldWrapper: oldWrapper,
            newWrapper: wrapper,
            newTransform: transform,
            offset: offset
        )
    }

    private func runTransition(
        oldWrapper: Border?,
        newWrapper: Border,
        newTransform: CompositeTransform,
        offset: (x: Double, y: Double)
    ) {
        isAnimating = true

        let storyboard = Storyboard()
        let duration = makeDuration(milliseconds: animationDurationMs)
        let easing = CubicEase()
        easing.easingMode = .easeOut

        addOpacityAnimation(to: storyboard, target: newWrapper, from: 0, to: 1, duration: duration, easing: easing)
        addSlideAnimation(to: storyboard, target: newTransform, property: "TranslateX", from: offset.x, to: 0, duration: duration, easing: easing)
        addSlideAnimation(to: storyboard, target: newTransform, property: "TranslateY", from: offset.y, to: 0, duration: duration, easing: easing)

        if let oldWrapper {
            addOpacityAnimation(to: storyboard, target: oldWrapper, from: 1, to: 0, duration: duration, easing: easing)

            if let oldTransform = oldWrapper.renderTransform as? CompositeTransform {
                addSlideAnimation(to: storyboard, target: oldTransform, property: "TranslateX", from: 0, to: -offset.x, duration: duration, easing: easing)
                addSlideAnimation(to: storyboard, target: oldTransform, property: "TranslateY", from: 0, to: -offset.y, duration: duration, easing: easing)
            }
        }

        storyboard.completed.addHandler { [weak self] _, _ in
            guard let self else { return }

            if let oldWrapper {
                oldWrapper.child = nil
                self.removeChild(oldWrapper)
            }

            self.isAnimating = false
            self.runPendingTransitionIfNeeded()
        }

        try? storyboard.begin()
    }

    private func runExitAnimation(wrapper: Border, transitionInfo: NavigationTransitionInfo?) {
        if transitionInfo is SuppressNavigationTransitionInfo {
            wrapper.child = nil
            removeChild(wrapper)
            return
        }

        isAnimating = true

        let storyboard = Storyboard()
        let duration = makeDuration(milliseconds: animationDurationMs)
        let easing = CubicEase()
        easing.easingMode = .easeOut

        addOpacityAnimation(to: storyboard, target: wrapper, from: 1, to: 0, duration: duration, easing: easing)

        storyboard.completed.addHandler { [weak self] _, _ in
            guard let self else { return }

            wrapper.child = nil
            self.removeChild(wrapper)
            self.isAnimating = false
            self.runPendingTransitionIfNeeded()
        }

        try? storyboard.begin()
    }

    private func runPendingTransitionIfNeeded() {
        guard let pending = pendingTransition else { return }

        pendingTransition = nil
        transition(to: pending.content, transitionInfo: pending.transitionInfo)
    }

    private func transitionOffset(for transitionInfo: NavigationTransitionInfo?) -> (x: Double, y: Double) {
        guard let slide = transitionInfo as? SlideNavigationTransitionInfo else {
            return (0, 0)
        }

        switch slide.effect {
        case .fromLeft:
            return (-slideDistance, 0)
        case .fromRight:
            return (slideDistance, 0)
        case .fromBottom:
            return (0, slideDistance)
        default:
            return (0, 0)
        }
    }

    private func addOpacityAnimation(
        to storyboard: Storyboard,
        target: UIElement,
        from: Double,
        to: Double,
        duration: Duration,
        easing: CubicEase
    ) {
        let animation = DoubleAnimation()
        animation.from = from
        animation.to = to
        animation.duration = duration
        animation.easingFunction = easing
        try? Storyboard.setTarget(animation, target)
        try? Storyboard.setTargetProperty(animation, "Opacity")
        storyboard.children.append(animation)
    }

    private func addSlideAnimation(
        to storyboard: Storyboard,
        target: CompositeTransform,
        property: String,
        from: Double,
        to: Double,
        duration: Duration,
        easing: CubicEase
    ) {
        guard from != to else { return }

        let animation = DoubleAnimation()
        animation.from = from
        animation.to = to
        animation.duration = duration
        animation.easingFunction = easing
        try? Storyboard.setTarget(animation, target)
        try? Storyboard.setTargetProperty(animation, property)
        storyboard.children.append(animation)
    }

    private func removeChild(_ element: UIElement) {
        var idx: UInt32 = 0
        if children.indexOf(element, &idx) {
            children.removeAt(idx)
        }
    }

    private func makeDuration(milliseconds: Int64) -> Duration {
        Duration(
            timeSpan: TimeSpan(duration: milliseconds * 10_000),
            type: .timeSpan
        )
    }
}
