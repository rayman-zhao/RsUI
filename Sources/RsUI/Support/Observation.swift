import Observation

/// 观察 `@Observable` 状态并驱动 UI 的统一入口：`Observations` 异步序列 + MainActor 回调。
///
/// 没有弱引用 owner：闭包强引用什么（ViewModel、WinUI 控件）由调用方决定 —— 对
/// swift-winrt 投影包装类而言强引用是必要的（包装对象缺少稳定 Swift 侧引用时会被释放，
/// 同 `NavigationViewItemWithAction` 的情况）。因此终止观察的责任完全在调用方：要么在
/// `onChanged` 返回 `false`（in-band 停止），要么持住返回的 Task 在 UI 卸载时 `cancel()`
/// （页面 deinit、content 重建、窗口 closed）；两者都不做，闭包强引用的对象将随 Task 常驻。
@discardableResult
public func startObserving<Element>(
    emitting: @escaping @Sendable () -> Element,
    onChanged: @escaping @MainActor (Element) async -> Bool
) -> Task<Void, Never> {
    let obs = Observations(emitting)

    return Task {
        for await value in obs {
            let keepObserving = await onChanged(value)
            guard keepObserving else { return }
        }
    }
}
