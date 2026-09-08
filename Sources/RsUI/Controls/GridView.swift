import CppWinRT
import RsFoundation
import WinUI
import WindowsFoundation

/// 基于 `ItemsView` 组合的多选增强网格视图。
///
/// 结构:`GridView: Grid`,内含一个铺满的 `ItemsView`(UniformGridLayout)与一个
/// 顶层选框 overlay(框选用,阶段 3 启用)。相比继承 `WinUI.GridView`(ListViewBase):
/// - 选择走 ItemsView 的 `select/deselect` 族 —— 官方文档明确其无视
///   `SelectionMode`、始终生效(实测每次调用都触发 `SelectionChanged`);
///   ListViewBase 的程序化选择在本环境实测静默失效(`selectRange` 空操作、
///   容器 `isSelected` 无效、`selectedItems` 向量修改不落选择模型)。
/// - Extended 模式下单击/双击已选中条目不会坍缩多选(实测,资源管理器语义),
///   因此 `itemDoubleTapped` 直接携带当前完整选择,无需记录-恢复。
///
/// 使用守则:
/// - 条目当前仅支持字符串,经 `setItems(_:)` 设置(CppWinRT 把 `[String]` 封装
///   成真正的 WinRT `IVector<IInspectable>`;Swift 原生集合无法直接封送)。
/// - 不拦截条目上的指针事件,Ctrl/Shift 原生多选、键盘导航保持 ItemsView 默认。
open class GridView: WinUI.Grid {

    /// `itemDoubleTapped` 事件的负载。
    public struct ItemDoubleTap {
        /// 被双击的条目。
        public let tappedItem: Any?
        /// 双击时刻的有效选择(多选时为完整集合,单选时为被双击条目本身)。
        public let items: [Any?]
    }

    /// 双击条目时触发。多选场景下 `items` 是双击后保留的完整多选集合。
    public let itemDoubleTapped = EventWithArgumentHandler<GridView, ItemDoubleTap>()

    /// 选择变化对外转发(ItemsView 的 selectionChanged 事件参数无成员,
    /// 这里以控件自身为 sender 重新分发)。
    public let selectionChanged = EventHandler<GridView>()

    /// Win11 资源管理器式复选框选择:仅鼠标悬停的条目浮现标准 CheckBox;
    /// 点击复选框切换该项勾选(CheckBox 自身处理点击,不会触发条目的原生
    /// 点击选择)。默认关闭。
    public var isCheckBoxSelectionEnabled = false {
        didSet { refreshCheckBoxes() }
    }

    // MARK: - 内部构成

    let itemsView = WinUI.ItemsView()
    private let uniformGridLayout = WinUI.UniformGridLayout()
    /// 框选矩形 overlay(阶段 3 启用;先挂载占位)。
    private let marqueeOverlay = WinUI.Border()
    /// 视觉树里 ItemsView 内部的 ItemsRepeater,双击/框选命中测试用。
    private var repeater: WinUI.ItemsRepeater?
    /// 已布线过事件的条目容器(防虚拟化回收复用时重复布线)。
    private var wiredContainers: [WinUI.ItemContainer] = []
    private var isRepeaterWired = false
    /// 悬停中的条目容器(复选框浮现用)。
    private var hoveredContainer: WinUI.ItemContainer?
    /// 程序化同步复选框状态时的重入守卫(设置 isChecked 也会触发 toggled)。
    private var isSyncingCheckBoxes = false

    // MARK: - 数据与选择状态

    private var titles: [String] = []
    /// 选择快照。ItemsView 的 selectionChanged 参数是空壳,增删集合靠自行 diff。
    private var selectedIndexesSnapshot: Set<Int32> = []

    // MARK: - Init

    override public init() {
        super.init()

        uniformGridLayout.minItemWidth = 140
        uniformGridLayout.minItemHeight = 56
        uniformGridLayout.minRowSpacing = 8
        uniformGridLayout.minColumnSpacing = 8

        itemsView.layout = uniformGridLayout
        itemsView.selectionMode = .extended
        itemsView.itemTemplate = App.context.requireXaml(withString: itemTemplateXaml)
        children.append(itemsView)

        marqueeOverlay.visibility = .collapsed
        marqueeOverlay.isHitTestVisible = false
        try? WinUI.Canvas.setZIndex(marqueeOverlay, 100)
        children.append(marqueeOverlay)

        bindEvents()
    }

    // MARK: - 公开配置

    /// 设置条目(字符串)。重复调用会整体替换并清空选择。
    public func setItems(_ items: [String]) {
        titles = items
        selectedIndexesSnapshot = []
        itemsView.itemsSource = single_threaded_vector_inspectable(items)
    }

    /// 网格项最小宽度。
    public var minItemWidth: Double {
        get { uniformGridLayout.minItemWidth }
        set { uniformGridLayout.minItemWidth = newValue }
    }

    /// 网格项最小高度。
    public var minItemHeight: Double {
        get { uniformGridLayout.minItemHeight }
        set { uniformGridLayout.minItemHeight = newValue }
    }

    /// 选择模式,转发给内部 ItemsView。默认 `.extended`(Ctrl/Shift 原生多选)。
    public var selectionMode: WinUI.ItemsViewSelectionMode {
        get { itemsView.selectionMode }
        set { itemsView.selectionMode = newValue }
    }

    /// 当前选择数量。
    public var selectedCount: Int { selectedIndexesSnapshot.count }

    /// 当前选中条目的文本,按索引升序。
    public var selectedItemTitles: [String] {
        selectedIndexesSnapshot.sorted().compactMap { index in
            let i = Int(index)
            return i < titles.count ? titles[i] : nil
        }
    }

    // MARK: - 事件绑定

    private func bindEvents() {
        itemsView.selectionChanged.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.handleSelectionChanged()
        }
        itemsView.doubleTapped.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            self.handleDoubleTapped(args)
        }
        // 悬停跟踪:pointerEntered 在合成输入下不可靠,统一用 itemsView 级
        // pointerMoved + 坐标命中测试;离开网格时清除。
        itemsView.pointerMoved.addHandler { [weak self] _, args in
            guard let self, self.isCheckBoxSelectionEnabled, let args else { return }
            self.ensureRepeaterWired()
            guard let hostPoint = (try? args.getCurrentPoint(nil))?.position else { return }
            let container = self.itemContainer(atHostPoint: hostPoint)
            if self.hoveredContainer != container {
                self.hoveredContainer = container
                self.refreshCheckBoxes()
            }
        }
        itemsView.pointerExited.addHandler { [weak self] _, _ in
            guard let self, self.isCheckBoxSelectionEnabled else { return }
            if self.hoveredContainer != nil {
                self.hoveredContainer = nil
                self.refreshCheckBoxes()
            }
        }

        // 条目容器就绪后布线(复选框联动)。
        itemsView.loaded.addHandler { [weak self] _, _ in
            self?.ensureRepeaterWired()
        }
    }

    /// 订阅内部 ItemsRepeater 的 elementPrepared 并给已实现的容器补布线。
    /// loaded 时 repeater 可能尚未进入视觉树,由 pointerMoved 路径兜底重试。
    private func ensureRepeaterWired() {
        guard !isRepeaterWired, let repeater = findRepeater() else { return }
        isRepeaterWired = true
        repeater.elementPrepared.addHandler { [weak self] _, args in
            guard let self, let args, let container = args.element as? WinUI.ItemContainer else { return }
            self.wireContainer(container)
        }
        for container in Self.descendants(ofType: WinUI.ItemContainer.self, from: itemsView) {
            wireContainer(container)
        }
        refreshCheckBoxes()
    }

    // MARK: - 选择同步

    private func handleSelectionChanged() {
        selectedIndexesSnapshot = currentSelectionIndexes()
        refreshCheckBoxes()
        selectionChanged.invoke(self)
    }

    /// 全量扫描当前选择(ItemsView 未暴露选中索引集,事件参数亦为空壳)。
    private func currentSelectionIndexes() -> Set<Int32> {
        var result: Set<Int32> = []
        var index: Int32 = 0
        let count = Int32(titles.count)
        while index < count {
            if (try? itemsView.isSelected(index)) == true {
                result.insert(index)
            }
            index += 1
        }
        return result
    }

    // MARK: - 双击处理

    private func handleDoubleTapped(_ args: WinUI.DoubleTappedRoutedEventArgs) {
        // 解析被双击的条目索引:优先命中测试(坐标反查条目容器),失败时退回
        // currentItemIndex(双击第一下点击会把 current 移到被点条目)。
        let tappedIndex = tappedItemIndex(of: args)

        let tappedItem: Any?
        if let tappedIndex, Int(tappedIndex) < titles.count {
            tappedItem = titles[Int(tappedIndex)]
        } else {
            tappedItem = nil
        }

        let effectiveItems: [Any?]
        if selectedIndexesSnapshot.count > 1 {
            effectiveItems = selectedItemTitles
        } else {
            effectiveItems = [tappedItem]
        }

        itemDoubleTapped.invoke(
            self,
            ItemDoubleTap(tappedItem: tappedItem, items: effectiveItems))
    }

    private func tappedItemIndex(of args: WinUI.DoubleTappedRoutedEventArgs) -> Int32? {
        if let hostPoint = try? args.getPosition(nil),
            let container = itemContainer(atHostPoint: hostPoint),
            let index = findRepeater().flatMap({ try? $0.getElementIndex(container) })
        {
            return index
        }
        let current = itemsView.currentItemIndex
        return current >= 0 ? current : nil
    }

    // MARK: - 复选框选择

    /// 给条目容器布线:复选框 checked/unchecked 联动条目选择。悬停跟踪在
    /// ItemsView 级 pointerMoved 统一处理(见 bindEvents)。CheckBox 自身处理
    /// 点击(ToggleButton 语义),不会把点击冒泡成条目的原生选择。
    private func wireContainer(_ container: WinUI.ItemContainer) {
        if wiredContainers.contains(container) { return }
        wiredContainers.append(container)

        guard let checkBox = (try? container.findName("ItemCheckBox")) as? WinUI.CheckBox else { return }
        // CheckBox 无 toggled 事件,checked/unchecked 各自订阅(RoutedEventHandler)。
        let handleToggle: (Any?, WinUI.RoutedEventArgs?) -> Void = { [weak self] _, _ in
            guard let self, self.isCheckBoxSelectionEnabled, !self.isSyncingCheckBoxes else { return }
            guard let repeater = self.findRepeater(),
                let index = try? repeater.getElementIndex(container)
            else { return }
            if checkBox.isChecked == true {
                try? self.itemsView.select(index)
            } else {
                try? self.itemsView.deselect(index)
            }
        }
        checkBox.checked.addHandler(handleToggle)
        checkBox.unchecked.addHandler(handleToggle)
    }

    /// 刷新所有已实现条目的复选框:可见 = 功能开启 且 该条目悬停中(资源管理器
    /// 式,只浮现在鼠标当前条目上);勾选态按选择快照。
    private func refreshCheckBoxes() {
        guard let repeater = findRepeater() else { return }
        isSyncingCheckBoxes = true
        defer { isSyncingCheckBoxes = false }
        for container in Self.descendants(ofType: WinUI.ItemContainer.self, from: itemsView) {
            guard let checkBox = (try? container.findName("ItemCheckBox")) as? WinUI.CheckBox else { continue }
            checkBox.visibility = isCheckBoxSelectionEnabled && hoveredContainer == container ? .visible : .collapsed
            if let index = try? repeater.getElementIndex(container) {
                checkBox.isChecked = selectedIndexesSnapshot.contains(index)
            }
        }
    }

    // MARK: - 视觉树辅助

    /// 用宿主坐标命中测试找到条目容器。`originalSource` 祖先上溯在 ItemsView 上
    /// 不可靠(实测 pointerPressed/doubleTapped 的 originalSource 上溯不到
    /// ItemContainer),改为按坐标反查。
    private func itemContainer(atHostPoint point: WindowsFoundation.Point) -> WinUI.ItemContainer? {
        guard let hits = try? WinUI.VisualTreeHelper.findElementsInHostCoordinates(point, itemsView) else {
            return nil
        }
        // AnyIIterable 不能直接 for-in,走 IIterator 手动迭代。
        guard var iterator = hits.first() else { return nil }
        while iterator.hasCurrent {
            if let element = iterator.current {
                var current = element as? WinUI.FrameworkElement
                while let node = current {
                    if let container = node as? WinUI.ItemContainer { return container }
                    current = node.parent as? WinUI.FrameworkElement
                }
            }
            if !iterator.moveNext() { break }
        }
        return nil
    }

    /// 找到 ItemsView 视觉树内部的 ItemsRepeater(命中测试要把元素换算成索引)。
    private func findRepeater() -> WinUI.ItemsRepeater? {
        if let repeater { return repeater }
        let found = Self.findDescendant(WinUI.ItemsRepeater.self, from: itemsView)
        repeater = found
        return found
    }

    private static func findDescendant<T: WinUI.FrameworkElement>(
        _ type: T.Type, from root: WinUI.DependencyObject
    ) -> T? {
        let count = (try? WinUI.VisualTreeHelper.getChildrenCount(root)) ?? 0
        var index: Int32 = 0
        while index < count {
            if let child = try? WinUI.VisualTreeHelper.getChild(root, index) {
                if let match = child as? T { return match }
                if let found = findDescendant(type, from: child) { return found }
            }
            index += 1
        }
        return nil
    }

    /// 收集视觉树中指定类型的全部后代(复选框状态刷新用)。
    private static func descendants<T: WinUI.FrameworkElement>(
        ofType type: T.Type, from root: WinUI.DependencyObject
    ) -> [T] {
        var result: [T] = []
        let count = (try? WinUI.VisualTreeHelper.getChildrenCount(root)) ?? 0
        var index: Int32 = 0
        while index < count {
            if let child = try? WinUI.VisualTreeHelper.getChild(root, index) {
                if let match = child as? T { result.append(match) }
                result.append(contentsOf: descendants(ofType: type, from: child))
            }
            index += 1
        }
        return result
    }
}

// MARK: - ItemTemplate

private var itemTemplateXaml: String {
    """
    <DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <ItemContainer>
            <Grid>
                <StackPanel Orientation="Horizontal" Spacing="10" VerticalAlignment="Center" Margin="16,10,12,10">
                    <FontIcon Glyph="&#xE7B8;" FontSize="18"/>
                    <TextBlock Text="{Binding}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
                </StackPanel>
                <CheckBox Name="ItemCheckBox" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="4,4,0,0" Visibility="Collapsed"/>
            </Grid>
        </ItemContainer>
    </DataTemplate>
    """
}
