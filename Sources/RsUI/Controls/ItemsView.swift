import CppWinRT
import RsFoundation
import WinUI
import WindowsFoundation

/// 基于 `WinUI.ItemsView` 的"代码填充"列表组件，以字符串 id 标识条目。
///
/// ItemsView 没有 `Items` 集合（只能走 `itemsSource`），loose XAML 模板又无法
/// `{Binding}` Swift 对象的具名属性，因此富内容条目需要订阅内部 ItemsRepeater
/// 的 `elementPrepared`、在代码里构建视图填入 `ItemContainer.child`。
/// 本组件封装该模式，调用方提供 id 列表与构建闭包：
///
/// ```swift
/// let list = ItemsView { id in
///     makeRow(for: model[id])          // 条目内容按 id 构建，身份稳定
/// }
/// list.selectionMode = .extended       // 需要多选时
/// list.layout = makeGridLayout()       // 默认单列 StackLayout，可换 UniformGridLayout 等
/// list.setIds(model.keys)              // 整体重置（选择、滚动位置重置）
/// list.appendIds(newIds)                // 增量追加：已实现条目与选择、滚动位置保留
/// ```
///
/// 使用守则：
/// - 条目以字符串 id 标识，需在列表内唯一（重复 id 的选择/移除行为未定义）；
///   id 只做身份，插入/移除导致的索引顺移不会改变既有条目的内容。
/// - 条目内容在容器（含虚拟化回收复用）就绪时按 id 重建，闭包应返回全新视图、
///   不要缓存复用旧元素。
/// - `itemsSource` 由内部一个可观察向量驱动（元素即 id 字符串；计数、按索引
///   取 id 与增删都直接走它，不维护 Swift 侧镜像），增删走 `appendIds` /
///   `insertIds` / `removeIds(_:)` 等增量接口，原生 `VectorChanged` 驱动
///   repeater 增量实现化，选择随条目保留。
/// - 条目增删/顺移默认播放过渡动画（`animatesItemChanges` 可关）：内置
///   `FadeSlideItemTransitionProvider` —— 新增淡入上滑、移除淡出、索引顺移
///   平滑位移；`setIds` 整体重置按新增动画整体重新入场。需要其他风格时直接
///   改赋继承的 `itemTransitionProvider`（如原生缩放风格的
///   `LinedFlowLayoutItemCollectionTransitionProvider`，或继承
///   `ItemCollectionTransitionProvider` 自写子类）。
/// - 布局沿用 ItemsView 原生 `layout` 属性（默认样式即单列 StackLayout），
///   需要条目间距或网格布局时由调用方自行设置。
/// - 选择沿用 ItemsView 原生语义（`selectionMode` / `select` / `deselect`，按索引），
///   id 维度的便捷读取走 `selectedIds`（`selectionChanged` 事件参数是空壳）。
/// - 列表需要有限高度的父容器（如 Grid 星型行）才能在内部滚动；
///   放进无限高的垂直 StackPanel 会导致内部滚动失效。
open class ItemsView: WinUI.ItemsView {

    /// 按 id 构建条目视图。容器因虚拟化被回收复用时会再次调用，需返回新实例。
    public var makeIdView: (String) -> UIElement

    private var isRepeaterWired = false
    /// 视觉树内部的 ItemsRepeater（elementPrepared 订阅与索引换算用）。
    /// 事件闭包只弱引用 self，避免 repeater → 事件闭包 → repeater 的引用循环。
    private var repeater: ItemsRepeater?
    /// itemsSource 的载体：单一可观察向量（经 C++ shim 创建，投影里没有对应工厂）。
    /// 元素即 id 字符串；计数、按索引取 id 与增删都直接走它，不维护 Swift 侧镜像。
    private let items: WinUI.IVectorAny
    /// 条目过渡动画的载体（内置 `FadeSlideItemTransitionProvider`，
    /// 见 `animatesItemChanges`）。
    private let transitionProvider: FadeSlideItemTransitionProvider

    /// - Parameter makeIdView: 条目视图构建闭包（按 id）。
    public init(makeIdView: @escaping (String) -> UIElement) {
        self.makeIdView = makeIdView
        guard let vector = single_threaded_observable_vector([]) else {
            fatalError("ItemsView: failed to create the observable items vector")
        }
        items = vector
        transitionProvider = FadeSlideItemTransitionProvider()
        super.init()

        // 模板只需产出 ItemContainer 根（选择/复选框视觉挂在容器上），条目内容
        // 经 elementPrepared 在代码里填 child，见文件尾的 ItemContainerFactory。
        itemTemplate = ItemContainerFactory()
        itemsSource = vector
        // StackLayout / UniformGridLayout 都不带默认 transition provider
        // （Layout 基类返回空），这里显式接入，见 animatesItemChanges。
        itemTransitionProvider = transitionProvider

        // elementPrepared 挂在内部 ItemsRepeater 上。loaded 时 repeater 可能尚未
        // 进视觉树（模板应用时序），layoutUpdated 重试到成功为止。
        loaded.addHandler { [weak self] _, _ in
            self?.wireRepeater()
        }
        layoutUpdated.addHandler { [weak self] _, _ in
            self?.wireRepeater()
        }
    }

    /// 条目增删/顺移是否播放过渡动画（默认 `true`）。
    ///
    /// 内置 `FadeSlideItemTransitionProvider`：新增淡入上滑、移除淡出、索引
    /// 顺移平滑位移；`setIds` 整体重置按新增动画整体重新入场。需要其他风格时，
    /// 直接改赋继承自 `WinUI.ItemsView` 的 `itemTransitionProvider`（如原生
    /// 缩放风格的 `LinedFlowLayoutItemCollectionTransitionProvider`；置 `nil`
    /// 即完全关闭）。
    public var animatesItemChanges = true {
        didSet {
            guard animatesItemChanges != oldValue else { return }
            itemTransitionProvider = animatesItemChanges ? transitionProvider : nil
        }
    }

    /// 当前条目数。
    public var count: Int {
        Int((try? items.get_Size()) ?? 0)
    }

    /// 显示顺序下的 id 快照（升序）。按索引逐项读取向量（GetMany 的数组
    /// 封送路径目前会崩溃，string(at:) 每项一次原生往返），偶发调用可接受。
    public var ids: [String] {
        (0..<count).compactMap { items.string(at: $0) }
    }

    // MARK: - 条目增删

    /// 整体重设 id（已实现条目、选择与滚动位置随之重置）。
    /// 数据整体替换时用；增删场景请走增量接口。
    public func setIds(_ newIds: [String]) {
        // 注：不使用 ReplaceAll —— 投影对 `[Any?]` 数组的封送（AnyBridge）目前会崩溃。
        try? items.Clear()
        for id in newIds {
            try? items.Append(id)
        }
        wireRepeater()
    }

    /// 末尾追加条目。增量更新：已实现条目与选择、滚动位置保留。
    public func appendIds(_ newIds: [String]) {
        for id in newIds {
            try? items.Append(id)
        }
    }

    /// 在 index 处插入条目。增量更新：其后条目索引顺移，已选条目由选择模型
    /// 自动换算到新索引（按 id 的内容不变）。
    public func insertIds(_ newIds: [String], at index: Int) {
        guard !newIds.isEmpty else { return }
        let at = min(max(0, index), count)
        for id in newIds {
            try? items.InsertAt(UInt32(at), id)
        }
    }

    /// 按 id 移除条目（顺序无关）。增量更新：选择与滚动位置保留。
    /// 未匹配的 id 记告警并跳过。
    public func removeIds(_ idsToRemove: [String]) {
        let removeSet = Set(idsToRemove)
        let matchedPairs = ids.enumerated().filter { removeSet.contains($0.element) }
        let unknown = removeSet.subtracting(matchedPairs.map { $0.element })
        if !unknown.isEmpty {
            log.warning("ItemsView: removeIds skips unknown ids: \(Array(unknown))")
        }
        removeIndexes(matchedPairs.map { $0.offset })
    }

    /// 按索引移除条目（增量更新：选择与滚动位置保留）。索引基于当前状态，
    /// 顺序无关；越界索引告警并跳过。
    public func removeIndexes(_ indexes: [Int]) {
        guard !indexes.isEmpty, count > 0 else { return }
        let valid = Set(indexes.filter { $0 >= 0 && $0 < count })
        let invalid = Set(indexes).subtracting(valid)
        if !invalid.isEmpty {
            log.warning("ItemsView: removeIndexes skips out-of-range indexes: \(invalid.sorted())")
        }
        for index in valid.sorted(by: >) {
            try? items.RemoveAt(UInt32(index))
        }
    }

    // MARK: - 选择便捷读取

    /// 当前选中条目 id（按视图顺序）。桥接 ItemsView 原生 `selectedItems`
    /// 只读视图，经 `string(at:)` 逐项读取（与 `ids` 同一读取 API 家族），
    /// O(选中数)。
    public var selectedIds: [String] {
        guard let selected = selectedItems else { return [] }
        return (0..<selected.count).compactMap { selected.string(at: $0) }
    }

    /// 当前选中条目索引（升序）。ItemsView 不暴露选中索引集（`selectedItems`
    /// 只有值），按 `isSelected` 全量扫描。
    public var selectedIndexes: [Int] {
        var indexes: [Int] = []
        var index: Int32 = 0
        let total = Int32(count)
        while index < total {
            if (try? isSelected(index)) == true { indexes.append(Int(index)) }
            index += 1
        }
        return indexes
    }

    // MARK: - 内部布线

    private func wireRepeater() {
        guard !isRepeaterWired,
            let found = Self.findDescendant(ItemsRepeater.self, from: self)
        else { return }
        isRepeaterWired = true
        repeater = found
        found.elementPrepared.addHandler { [weak self] _, args in
            guard let self, let args, let container = args.element as? ItemContainer
            else { return }
            self.fillContainer(container)
        }
        // 兜底：订阅前已实现的容器不会再触发 elementPrepared。
        for container in Self.descendants(ofType: ItemContainer.self, from: self) {
            fillContainer(container)
        }
    }

    private func fillContainer(_ container: ItemContainer) {
        guard let repeater,
            let index = try? repeater.getElementIndex(container),
            index >= 0, let id = items.string(at: Int(index))
        else { return }
        container.child = makeIdView(id)
    }

    /// 深度优先查找指定类型的后代元素（取内部 ItemsRepeater 用）。
    private static func findDescendant<T: FrameworkElement>(
        _ type: T.Type, from root: DependencyObject
    ) -> T? {
        let count = (try? VisualTreeHelper.getChildrenCount(root)) ?? 0
        var index: Int32 = 0
        while index < count {
            if let child = try? VisualTreeHelper.getChild(root, index) {
                if let match = child as? T { return match }
                if let found = findDescendant(type, from: child) { return found }
            }
            index += 1
        }
        return nil
    }

    /// 收集指定类型的全部后代（订阅前已实现容器的兜底填充用）。
    private static func descendants<T: FrameworkElement>(
        ofType type: T.Type, from root: DependencyObject
    ) -> [T] {
        var result: [T] = []
        let count = (try? VisualTreeHelper.getChildrenCount(root)) ?? 0
        var index: Int32 = 0
        while index < count {
            if let child = try? VisualTreeHelper.getChild(root, index) {
                if let match = child as? T { result.append(match) }
                result.append(contentsOf: descendants(ofType: type, from: child))
            }
            index += 1
        }
        return result
    }
}

/// `itemTemplate` 的代码工厂：每次产出新的 `ItemContainer`。`DataTemplate` 的内容
/// 无法纯代码定义（WinUI 没有 WPF 的 `FrameworkElementFactory`），而 ItemsView 的
/// `itemTemplate` 收的是 `IElementFactory` —— 投影允许 Swift 类型直接实现该接口，
/// 借此免去为这么个空模板走 `XamlReader`。
private final class ItemContainerFactory: IElementFactory {

    func getElement(_ args: ElementFactoryGetArgs!) throws -> UIElement! {
        ItemContainer()
    }

    func recycleElement(_ args: ElementFactoryRecycleArgs!) throws {
        // 无回收池：容器交给 repeater 丢弃，下次 get 新实例。
    }
}
