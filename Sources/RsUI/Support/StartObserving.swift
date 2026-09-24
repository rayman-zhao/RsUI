import Foundation
import Observation

/// `Page` / `NavigationViewItem` / `ProgressBar` / `ProgressRing` / `Window` 各自
/// `startObserving(_:onChanged:)` 镜像的共用实现：`Observations` 异步序列 +
/// MainActor 回调，owner 释放即停。
///
/// 返回观察 Task —— 需要提前终止观察的调用方（如窗口 `closed` 时）可 cancel；
/// 忽略返回值则观察随 owner 生命周期自然结束。回调内终止则交给 `onChanged` 的
/// 返回值：返回 `false` 表示停止观察（true = 继续，同 `takeWhile` 的极性）。
@discardableResult
func startObservingChanges<Owner: AnyObject, Element>(
    on owner: Owner,
    emitting: @escaping @Sendable () -> Element,
    onChanged: @escaping @MainActor (Owner, Element) -> Bool
) -> Task<Void, Never> {
    let obs = Observations(emitting)

    return Task { [weak owner] in
        for await value in obs {
            guard let owner else { return }
            let keepObserving = await MainActor.run { [weak owner] () -> Bool in
                guard let owner else { return false }
                return onChanged(owner, value)
            }
            if !keepObserving { return }
        }
    }
}
