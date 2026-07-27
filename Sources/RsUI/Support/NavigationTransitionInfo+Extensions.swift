import WinUI

extension NavigationTransitionInfo {
    public static func make(slideEffect: SlideNavigationTransitionEffect)
        -> NavigationTransitionInfo
    {
        let transition = SlideNavigationTransitionInfo()
        transition.effect = slideEffect
        return transition
    }
}
