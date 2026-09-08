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

    // MARK: - 内部构成

    let itemsView = WinUI.ItemsView()
    private let uniformGridLayout = WinUI.UniformGridLayout()
    /// 框选矩形 overlay(阶段 3 启用;先挂载占位)。
    private let marqueeOverlay = WinUI.Border()
    /// 视觉树里 ItemsView 内部的 ItemsRepeater,双击/框选命中测试用。
    private var repeater: WinUI.ItemsRepeater?

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
    }

    // MARK: - 选择同步

    private func handleSelectionChanged() {
        selectedIndexesSnapshot = currentSelectionIndexes()
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
}

// MARK: - ItemTemplate

private var itemTemplateXaml: String {
    """
    <DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <ItemContainer>
            <Grid Padding="12,8">
                <StackPanel Orientation="Horizontal" Spacing="10" VerticalAlignment="Center">
                    <FontIcon Glyph="&#xE7B8;" FontSize="18"/>
                    <TextBlock Text="{Binding}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
                </StackPanel>
            </Grid>
        </ItemContainer>
    </DataTemplate>
    """
}
