import Foundation
import Observation

/// `Page` / `NavigationViewItem` / `ProgressBar` / `ProgressRing` / `Window` 各自
/// `startObserving(_:onChanged:)` 镜像的共用实现：`Observations` 异步序列 +
/// MainActor 回调，owner 释放即停。
///
/// 返回观察 Task —— 需要提前终止观察的调用方（如窗口 `closed` 时）可 cancel；
/// 忽略返回值则观察随 owner 生命周期自然结束。
@discardableResult
func startObservingChanges<Owner: AnyObject, Element>(
    on owner: Owner,
    emitting: @escaping @Sendable () -> Element,
    onChanged: @escaping @MainActor (Owner, Element) -> Void
) -> Task<Void, Never> {
    let obs = Observations(emitting)

    return Task { [weak owner] in
        for await value in obs {
            guard let owner else { return }
            await MainActor.run { [weak owner] in
                guard let owner else { return }
                onChanged(owner, value)
            }
        }
    }
}
