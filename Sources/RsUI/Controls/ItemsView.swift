import CppWinRT
import RsFoundation
import WinUI
import WindowsFoundation

/// `ItemsView` 系列表组件的共享基座，承载与"条目身份"无关的全部机制：
/// 内部可观察向量（itemsSource 的计数与变更通知载体）、repeater 接线
/// （`elementPrepared` / `elementClearing` 分发到 `fillContainer` /
/// `clearContainer` 挂钩）、条目过渡动画、按索引增删与选择索引读取。
///
/// 两个叶类：
/// - ``ItemsView`` —— 字符串 id 味（向量元素即 id，身份稳定，内容按 id 构建）；
/// - ``ItemsIndexView`` —— 索引味（`makeView` 直接收 repeater 索引，位置即身份，
///   全程不读回向量元素值，不依赖任何装箱解箱原语）。
open class ItemsViewBase: WinUI.ItemsView {

    private var isRepeaterWired = false
    /// 视觉树内部的 ItemsRepeater（elementPrepared 订阅与索引换算用）。
    /// 事件闭包只弱引用 self，避免 repeater → 事件闭包 → repeater 的引用循环。
    internal private(set) var repeater: ItemsRepeater?
    /// itemsSource 的载体：单一可观察向量（经 C++ shim 创建，投影里没有对应工厂）。
    /// 元素含义由叶类决定——字符串味元素即 id；索引味元素为索引数字、只写不读。
    internal let items: WinUI.IVectorAny
    /// 条目过渡动画的载体（内置 `FadeSlideItemTransitionProvider`，
    /// 见 `animatesItemChanges`）。
    private let transitionProvider: FadeSlideItemTransitionProvider
    /// 当前挂在 itemTemplate 上的工厂（`rebuildViews()` 换代际时移交回收池用，
    /// 见 `RecyclableItemContainerFactory`）。
    private var activeFactory: RecyclableItemContainerFactory?

    override internal init() {
        guard let vector = single_threaded_observable_vector([]) else {
            fatalError("ItemsViewBase: failed to create the observable items vector")
        }
        items = vector
        transitionProvider = FadeSlideItemTransitionProvider()
        super.init()

        // 模板只需产出 ItemContainer 根（选择/复选框视觉挂在容器上），条目内容
        // 经 elementPrepared 在代码里填 child，见 makeContainerFactory 与文件尾工厂。
        let factory = makeContainerFactory()
        activeFactory = factory
        itemTemplate = factory
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

    /// 产出 itemTemplate 的代码工厂。`rebuildViews()` 依赖换入新实例触发
    /// ItemsRepeater 的整体 Reset；叶类可覆写以产出自己的容器子类
    /// （见 `ItemsIndexView` 的 `IndexedItemContainer`）。
    func makeContainerFactory() -> RecyclableItemContainerFactory {
        RecyclableItemContainerFactory { ItemContainer() }
    }

    /// 条目增删/顺移是否播放过渡动画（默认 `true`）。
    ///
    /// 内置 `FadeSlideItemTransitionProvider`：新增淡入上滑、移除淡出、索引
    /// 顺移平滑位移；整体重置（`ItemsView.setIds` / `ItemsIndexView.setCount`）
    /// 按新增动画整体重新入场。需要其他风格时，直接改赋继承自 `WinUI.ItemsView`
    /// 的 `itemTransitionProvider`（如原生缩放风格的
    /// `LinedFlowLayoutItemCollectionTransitionProvider`；置 `nil` 即完全关闭）。
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

    /// 按索引移除条目（增量更新：选择与滚动位置保留）。索引基于当前状态，
    /// 顺序无关；越界索引告警并跳过。
    ///
    /// 注意：索引顺移后的已实现容器内容一致性由叶类负责——字符串味天然成立
    /// （id 不随顺移变化），索引味覆写本方法补顺移对账（见 `ItemsIndexView`）。
    public func removeIndexes(_ indexes: [Int]) {
        guard !indexes.isEmpty, count > 0 else { return }
        let valid = Set(indexes.filter { $0 >= 0 && $0 < count })
        let invalid = Set(indexes).subtracting(valid)
        if !invalid.isEmpty {
            log.warning("ItemsViewBase: removeIndexes skips out-of-range indexes: \(invalid.sorted())")
        }
        for index in valid.sorted(by: >) {
            try? items.RemoveAt(UInt32(index))
        }
    }

    /// 内部 ItemsRepeater 的垂直实现缓存长度(视口倍数,视口上下各按此倍数
    /// 预实现条目;WinUI 默认 2)。repeater 接线前赋值会先暂存,接线时落上。
    ///
    /// 用途:UniformGridLayout 恒以 index 0 校准条目尺寸——0 离开实现窗口后
    /// 布局每趟走 ForceCreate(0)→测量→Recycle 的昂贵路径,其记账进出使
    /// 未实现区估高翻转一行(视口被锚点补偿拨动、贴底时滚动条 thumb 停不到
    /// 底的根源)。把缓存加宽到盖住整个内容即可让 0 恒在实现窗口内。
    public var verticalCacheLength: Double {
        get { repeater?.verticalCacheLength ?? pendingVerticalCacheLength ?? 2.0 }
        set {
            pendingVerticalCacheLength = newValue
            repeater?.verticalCacheLength = newValue
        }
    }

    private var pendingVerticalCacheLength: Double?

    /// 丢弃并重建全部已实现条目的视图，条目集合本身不变。
    ///
    /// 通过换一个新的 ItemTemplate 工厂实例实现：ItemsRepeater 对模板变更做
    /// 整体 Reset——已实现容器先卸载（回调 `unloadView`），下次布局经
    /// 新工厂重新实现化（`makeIdView` / `makeView` 重建）。itemsSource 不动，
    /// 选择与滚动位置全部保留，适合“条目不变、视图需要按新参数重造”的场景
    /// （如布局档位切换）；条目集合有变化时仍应整体重设。
    /// 注意模板变更不允许发生在 repeater 自身布局进行中（WinUI 会抛错），
    /// 在 sizeChanged 等布局完成后的事件里调用是安全的。
    public func rebuildViews() {
        let fresh = makeContainerFactory()
        // 旧池移交：换工厂实例触发 Reset 后，清除的容器经 recycleElement 进的是
        // 新代际（清除走当前 shim），旧代际池里的停放容器若不移交即成孤儿
        // （repeater 的 Children 非公开 API，无法事后摘离）。
        activeFactory?.transferPool(to: fresh)
        activeFactory = fresh
        itemTemplate = fresh
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

    /// 在视觉树内定位内部 ItemsRepeater 并订阅 elementPrepared/elementClearing。
    /// 已接线后为空操作；条目整体重设后调用可重试（repeater 尚未进树的早期窗口）。
    func wireRepeater() {
        guard !isRepeaterWired,
            let found = Self.findDescendant(ItemsRepeater.self, from: self)
        else { return }
        isRepeaterWired = true
        repeater = found
        if let pending = pendingVerticalCacheLength {
            found.verticalCacheLength = pending
        }
        found.elementPrepared.addHandler { [weak self] _, args in
            guard let self, let args, let container = args.element as? ItemContainer
            else { return }
            self.fillContainer(container)
        }
        found.elementClearing.addHandler { [weak self] _, args in
            guard let self, let args, let container = args.element as? ItemContainer
            else { return }
            self.clearContainer(container)
        }
        // 兜底：订阅前已实现的容器不会再触发 elementPrepared。
        for container in Self.descendants(ofType: ItemContainer.self, from: self) {
            fillContainer(container)
        }
    }

    /// 容器就绪（elementPrepared 或兜底填充）时填入条目内容，叶类覆写。
    func fillContainer(_ container: ItemContainer) {}

    /// 容器卸载（elementClearing）时清理，叶类覆写。
    func clearContainer(_ container: ItemContainer) {}

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

    /// 收集指定类型的全部后代（订阅前已实现容器的兜底填充、顺移对账用）。
    static func descendants<T: FrameworkElement>(
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

/// 基于 `WinUI.ItemsView` 的"代码填充"列表组件（字符串 id 味），以字符串 id
/// 标识条目。条目数据天然按位置组织、无需稳定字符串身份时用 ``ItemsIndexView``。
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
/// list.unloadView = { id in            // 条目卸载时清理（可空，按需设置）
///     cancelPendingLoads(for: id)
/// }
/// ```
///
/// 使用守则：
/// - 条目以字符串 id 标识，需在列表内唯一（重复 id 的选择/移除行为未定义）；
///   id 只做身份，插入/移除导致的索引顺移不会改变既有条目的内容。
/// - 条目内容在容器（含虚拟化回收复用）就绪时按 id 重建，闭包应返回全新视图、
///   不要缓存复用旧元素。
/// - 容器卸载（滚动离开实现区被回收、或 `setIds` 重置丢弃旧容器）时回调
///   `unloadView`（携带条目 id）：容器即将被丢弃、视图不再复用，
///   `makeIdView` 里启动的异步内容构建（如图片加载）应在此取消。
/// - `itemsSource` 由内部一个可观察向量驱动（元素即 id 字符串；计数、按索引
///   取 id 与增删都直接走它，不维护 Swift 侧镜像），增删走 `appendIds` /
///   `insertIds` / `removeIds(_:)` 等增量接口，原生 `VectorChanged` 驱动
///   repeater 增量实现化，选择随条目保留。
/// - 条目增删/顺移默认播放过渡动画（`animatesItemChanges` 可关）：内置
///   `FadeSlideItemTransitionProvider` —— 新增淡入上滑、移除淡出、索引顺移
///   平滑位移；`setIds` 整体重置按新增动画整体重新入场。需要其他风格时直接
///   改赋继承的 `itemTransitionProvider`。
/// - 布局沿用 ItemsView 原生 `layout` 属性（默认样式即单列 StackLayout），
///   需要条目间距或网格布局时由调用方自行设置。
/// - 选择沿用 ItemsView 原生语义（`selectionMode` / `select` / `deselect`，按索引），
///   id 维度的便捷读取走 `selectedIds`（`selectionChanged` 事件参数是空壳）。
/// - 列表需要有限高度的父容器（如 Grid 星型行）才能在内部滚动；
///   放进无限高的垂直 StackPanel 会导致内部滚动失效。
open class ItemsView: ItemsViewBase {

    /// 按 id 构建条目视图。容器因虚拟化被回收复用时会再次调用，需返回新实例。
    public var makeIdView: (String) -> UIElement

    /// 条目视图被卸载时回调，参数为条目 id；可空，默认无操作。
    ///
    /// `makeIdView` 的对应清理钩子：容器因滚动离开实现区被回收、或 `setIds`
    /// 整体重置而被丢弃时触发，此时容器即将被丢弃、视图不再复用。
    /// 闭包里启动的异步工作（如图片加载）应在此取消，避免继续更新已脱离
    /// 视觉树的视图。增量增删接口只移动容器不卸载它们，不触发本回调。
    public var unloadView: ((String) -> Void)?

    /// - Parameter makeIdView: 条目视图构建闭包（按 id）。
    public init(makeIdView: @escaping (String) -> UIElement) {
        self.makeIdView = makeIdView
        super.init()
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

    // MARK: - 选择便捷读取

    /// 当前选中条目 id（按视图顺序）。桥接 ItemsView 原生 `selectedItems`
    /// 只读视图，经 `string(at:)` 逐项读取（与 `ids` 同一读取 API 家族），
    /// O(选中数)。
    public var selectedIds: [String] {
        guard let selected = selectedItems else { return [] }
        return (0..<selected.count).compactMap { selected.string(at: $0) }
    }

    // MARK: - 容器填充

    override func fillContainer(_ container: ItemContainer) {
        guard let repeater,
            let index = try? repeater.getElementIndex(container),
            index >= 0, let id = items.string(at: Int(index))
        else { return }
        // id 记入 tag：elementClearing 时索引已失效，只能靠 tag 反查。
        container.tag = id
        container.child = makeIdView(id)
    }

    override func clearContainer(_ container: ItemContainer) {
        guard let id = Self.tagString(container.tag) else { return }
        // 注意：不能置 container.child = nil —— ItemContainer.Child 拒绝 null
        // （put 抛 E_INVALIDARG，经 try! 投影直接致命崩溃）。容器本身会被
        // 工厂丢弃（无回收池），child 引用随容器一并释放。
        container.tag = nil
        unloadView?(id)
    }

    /// 从 `FrameworkElement.tag`（Any!）取出装箱字符串。投影的 Any 解包
    /// 不直接产出 String，可能拿到 IInspectable 包装，需经 `boxedString`
    /// 原生解箱兜底（同 `IVectorAny.string(at:)` 的处理）。
    private static func tagString(_ tag: Any?) -> String? {
        (tag as? String) ?? (tag as? WindowsFoundation.IInspectable)?.boxedString
    }
}

/// `itemTemplate` 的代码工厂：按需新建 `ItemContainer`，经 `recycleElement`
/// 入池、`getElement` 取池复用（对齐 WinUI `ItemTemplateWrapper` + `RecyclePool`
/// 官方模式）。`DataTemplate` 的内容无法纯代码定义（WinUI 没有 WPF 的
/// `FrameworkElementFactory`），而 ItemsView 的 `itemTemplate` 收的是
/// `IElementFactory` —— 投影允许 Swift 类型直接实现该接口，借此免去为这么个
/// 空模板走 `XamlReader`。
///
/// 回收契约（microsoft-ui-xaml ViewManager/RecyclePool 源码核实）：清除容器时
/// repeater 不将其摘离子集合，而是经 `recycleElement` 交还工厂；`getElement`
/// 返回仍挂树的池元素是官方支持的快路径（ViewManager 对 parent 已是自身子的
/// 元素跳过重复 Append）。无池工厂会导致停放的容器单调累积（IVLT 实测只增
/// 不减）。`rebuildViews()` 换新工厂代际时由基座把旧池移交新工厂——repeater 的
/// Children 非公开 API，工厂侧无法主动摘离，弃池即孤儿。
internal final class RecyclableItemContainerFactory: IElementFactory {

    private let makeContainer: () -> ItemContainer
    private var pool: [ItemContainer] = []

    init(makeContainer: @escaping () -> ItemContainer) {
        self.makeContainer = makeContainer
    }

    func getElement(_ args: ElementFactoryGetArgs!) throws -> UIElement! {
        pool.popLast() ?? makeContainer()
    }

    func recycleElement(_ args: ElementFactoryRecycleArgs!) throws {
        guard let container = args.element as? ItemContainer else { return }
        pool.append(container)
    }

    /// 把旧代际的池移交继任工厂（`rebuildViews()` 换代际时调用）。容器外壳
    /// 无参数、跨代际复用安全，条目内容经 elementPrepared 重建。
    func transferPool(to successor: RecyclableItemContainerFactory) {
        successor.pool.append(contentsOf: pool)
        pool.removeAll()
    }
}
