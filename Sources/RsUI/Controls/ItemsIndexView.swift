import CppWinRT
import WinUI

/// 索引味"代码填充"列表组件：`makeView` 直接收条目索引（repeater 的位置），
/// 无 id 概念，位置即身份。条目需要稳定字符串 id 时用 ``ItemsView``。
///
/// ```swift
/// let list = ItemsIndexView { index in
///     makeRow(for: snapshots[index])      // 条目内容按索引构建
/// }
/// list.selectionMode = .extended          // 需要多选时
/// list.setCount(snapshots.count)          // 整体重置（选择、滚动位置重置）
/// list.append(pageSize)                   // 增量追加：已实现条目与选择、滚动位置保留
/// list.unloadView = { index in            // 条目卸载时清理（可空，按需设置）
///     cancelPendingLoads(for: index)
/// }
/// ```
///
/// 与字符串味的差异与边界：
/// - itemsSource 向量在这里只是计数与变更通知的载体（元素为索引数字、只写
///   不读），全程不读回任何元素值，因此不依赖装箱解箱原语；字符串味因
///   "向量元素即 id"才需要 fork 的 `string(at:)` 读回。
/// - 位置身份语义下不存在 removeIds(by id) / selectedIds——身份即索引，
///   对应能力由继承的 `removeIndexes` / `selectedIndexes` 提供。
/// - 若未来需要"稳定整数 id"语义（如数据库主键，插入/移除后身份不变），
///   需先为 swift-cppwinrt 补整数解箱原语（镜像 `boxedString` 先例：读回的
///   装箱整数是不透明 IInspectable，`as? Int` 恒失败），再按字符串味同构
///   实现整数味叶类；本类不承载该形态。
open class ItemsIndexView: ItemsViewBase {

    /// 按索引构建条目视图。容器因虚拟化被回收复用时会再次调用，需返回新实例。
    public var makeView: (Int) -> UIElement

    /// 条目视图被卸载时回调，参数为该容器最后展示的索引；可空，默认无操作。
    ///
    /// `makeView` 的对应清理钩子：容器因滚动离开实现区被回收、或 `setCount`
    /// 整体重置而被丢弃时触发，此时容器即将被丢弃、视图不再复用。
    /// 闭包里启动的异步工作（如图片加载）应在此取消，避免继续更新已脱离
    /// 视觉树的视图。增量增删接口只移动容器不卸载它们，不触发本回调。
    /// 参数是填充时的索引——顺移发生后即"最后展示的索引"，与字符串味
    /// `unloadView` 携带填充时 id 的语义一致。
    public var unloadView: ((Int) -> Void)?

    /// - Parameter makeView: 条目视图构建闭包（按索引）。
    public init(makeView: @escaping (Int) -> UIElement) {
        self.makeView = makeView
        super.init()
        // 索引顺移对账挂 layoutUpdated（见 scheduleReconcile），与基座的
        // repeater 接线重试共用同一事件源。
        layoutUpdated.addHandler { [weak self] _, _ in
            self?.reconcileIfNeeded()
        }
    }

    // MARK: - 条目增删

    /// 整体重设条目数（已实现条目、选择与滚动位置随之重置）。
    /// 数据整体替换时用；增删场景请走增量接口。
    public func setCount(_ count: Int) {
        guard count >= 0 else { return }
        // 注：不使用 ReplaceAll —— 投影对 `[Any?]` 数组的封送（AnyBridge）目前会崩溃。
        try? items.Clear()
        for index in 0..<count {
            try? items.Append(index)
        }
        wireRepeater()
    }

    /// 末尾追加条目。增量更新：已实现条目与选择、滚动位置保留。
    public func append(_ count: Int) {
        guard count > 0 else { return }
        let start = self.count
        for offset in 0..<count {
            try? items.Append(start + offset)
        }
    }

    /// 在 index 处插入条目。增量更新：其后条目索引顺移，已选条目由选择模型
    /// 自动换算到新索引。
    public func insert(_ count: Int, at index: Int) {
        guard count > 0 else { return }
        let start = min(max(0, index), self.count)
        for offset in 0..<count {
            try? items.InsertAt(UInt32(start + offset), start + offset)
        }
        scheduleReconcile()
    }

    /// 按索引移除（继承自基座）。覆写以补索引顺移对账。
    public override func removeIndexes(_ indexes: [Int]) {
        guard !indexes.isEmpty, count > 0 else { return }
        super.removeIndexes(indexes)
        scheduleReconcile()
    }

    // MARK: - 索引顺移对账

    /// 是否有待消化的顺移对账（insert/remove 后置位，下一次 layoutUpdated 消化）。
    private var reconcilePending = false

    /// 计划一次顺移对账：insert/remove 会移动其后条目的索引，已实现容器若
    /// 未被 repeater 重发 elementPrepared，内容会停留在旧索引的数据上。
    /// repeater 在下一次布局才消化向量变更，故对账挂在变更后的首个
    /// layoutUpdated（此时容器↔索引映射已更新），按
    /// `displayedIndex ≠ getElementIndex` 差量重填，与原生重发路径幂等共存。
    private func scheduleReconcile() {
        reconcilePending = true
    }

    private func reconcileIfNeeded() {
        guard reconcilePending else { return }
        reconcilePending = false
        guard let repeater else {
            // repeater 尚未接线（未进树）：此时无已实现容器，且首次接线后
            // elementPrepared 会按新索引填充，无需补账。
            return
        }
        for container in Self.descendants(ofType: ItemContainer.self, from: self) {
            guard let indexed = container as? IndexedItemContainer,
                let index = try? repeater.getElementIndex(container),
                index >= 0
            else { continue }
            if indexed.displayedIndex != Int(index) {
                indexed.displayedIndex = Int(index)
                indexed.child = makeView(Int(index))
            }
        }
    }

    // MARK: - 容器填充

    override func fillContainer(_ container: ItemContainer) {
        guard let repeater,
            let index = try? repeater.getElementIndex(container),
            index >= 0,
            let indexed = container as? IndexedItemContainer
        else { return }
        indexed.displayedIndex = Int(index)
        indexed.child = makeView(Int(index))
    }

    override func clearContainer(_ container: ItemContainer) {
        guard let indexed = container as? IndexedItemContainer,
            let index = indexed.displayedIndex
        else { return }
        // 注意：不能置 container.child = nil —— ItemContainer.Child 拒绝 null。
        // 容器本身会被工厂丢弃（无回收池），child 引用随容器一并释放。
        indexed.displayedIndex = nil
        unloadView?(index)
    }

    override func makeContainerFactory() -> RecyclableItemContainerFactory {
        RecyclableItemContainerFactory { IndexedItemContainer() }
    }
}

/// 携带"最后展示的索引"的条目容器：elementClearing 时实时索引已失效，
/// 靠该 Swift 属性反查，免 tag 装箱解箱往返（读回装箱 Int 是不透明
/// IInspectable，`as? Int` 恒失败，见类头"差异与边界"）。
private final class IndexedItemContainer: ItemContainer {
    var displayedIndex: Int?
}
