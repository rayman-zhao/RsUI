import Foundation
import RsUI
import UWP
import WinUI

/// ItemsView / ItemsIndexView 的工作总结/使用文档页。文档主体以条目列表呈现，
/// 演示"有限高度父容器 + 组件公开 API"的实际用法；开关切换查看完整源码。
final class ItemsViewDocumentationPage: RsUI.Page {
    let url = URL(string: "rs://\(sampleModuleID)/items-view-doc")!
    var title: String { tr("Items View Documentation") }

    var content: WinUI.UIElement {
        // 文档小节按索引取（内容静态、位置即身份）——索引味的典型场景。
        let list = RsUI.ItemsIndexView { index in
            Self.makeDocumentRow(section: Self.sections[index])
        }

        // 布局是 ItemsView 原生属性，默认样式即单列 StackLayout；这里仅加 4px 间距。
        let listLayout = StackLayout()
        listLayout.spacing = 4
        list.layout = listLayout
        list.setCount(Self.sections.count)

        let sourceText = TextBlock()
        sourceText.text = Self.fullSource
        sourceText.fontFamily = FontFamily("Consolas")
        sourceText.fontSize = 12
        sourceText.textWrapping = .wrap

        let sourceScroll = ScrollView()
        sourceScroll.content = sourceText
        sourceScroll.visibility = .collapsed

        let sourceToggle = ToggleSwitch()
        sourceToggle.header = tr("Show full source")
        sourceToggle.onContent = tr("On")
        sourceToggle.offContent = tr("Off")
        sourceToggle.toggled.addHandler { _, _ in
            let showSource = sourceToggle.isOn
            sourceScroll.visibility = showSource ? .visible : .collapsed
            list.visibility = showSource ? .collapsed : .visible
        }

        // 文档列表与源码视图共用 star 行（互斥显示），开关占底部 auto 行。
        let root = Grid()
        root.padding = Thickness(left: 40, top: 24, right: 40, bottom: 32)
        let docRow = RowDefinition()
        docRow.height = GridLength(value: 1, gridUnitType: .star)
        let toggleRow = RowDefinition()
        toggleRow.height = GridLength(value: 0, gridUnitType: .auto)
        root.rowDefinitions.append(docRow)
        root.rowDefinitions.append(toggleRow)
        try? Grid.setRow(list, 0)
        try? Grid.setRow(sourceScroll, 0)
        try? Grid.setRow(sourceToggle, 1)
        root.children.append(list)
        root.children.append(sourceScroll)
        root.children.append(sourceToggle)

        return root
    }

    // MARK: - 文档内容

    /// 一个文档小节：图标 + 标题 + 要点。
    private struct Section {
        let glyph: String
        let title: String
        let points: [String]
    }

    private static func makeDocumentRow(section: Section) -> UIElement {
        let icon = FontIcon()
        icon.glyph = section.glyph
        icon.fontSize = 18
        icon.verticalAlignment = .center

        let titleBlock = TextBlock()
        titleBlock.text = section.title
        titleBlock.fontSize = 16

        let texts = StackPanel()
        texts.spacing = 2
        texts.verticalAlignment = .center
        texts.children.append(titleBlock)
        for point in section.points {
            let pointBlock = TextBlock()
            pointBlock.text = "· " + point
            pointBlock.fontSize = 12
            pointBlock.opacity = 0.75
            pointBlock.textWrapping = .wrap
            texts.children.append(pointBlock)
        }

        let row = StackPanel()
        row.orientation = .horizontal
        row.spacing = 12
        row.padding = Thickness(left: 14, top: 10, right: 14, bottom: 10)
        row.children.append(icon)
        row.children.append(texts)
        return row
    }

    private static let sections: [Section] = [
        Section(
            glyph: "\u{E946}",
            title: tr("Why ItemsView"),
            points: [
                tr(
                    "ItemsView has no Items collection; it only accepts itemsSource. Loose XAML templates cannot {Binding} named properties of Swift objects, so rich items must subscribe to the inner ItemsRepeater's elementPrepared event and fill ItemContainer.child in code."
                ),
                tr(
                    "The components wrap that pattern in two flavors sharing one base (ItemsViewBase): ItemsView keys items by string id (content stable across index shifts), ItemsIndexView feeds the repeater index straight into makeView (position is the identity)."
                ),
                tr(
                    "The index flavor never reads itemsSource element values back — the internal vector is only a count-and-change-notification carrier — so it needs no unboxing primitives at all."
                ),
            ]),
        Section(
            glyph: "\u{E8E5}",
            title: tr("Public API"),
            points: [
                tr(
                    "init(makeIdView:) / init(makeView:) — the only initializer parameter of each flavor: the view build closure, keyed by string id or by index."
                ),
                tr(
                    "setIds(_:) / setCount(_:) — full reset of the id list / item count (selection and scroll position reset)."
                ),
                tr(
                    "appendIds(_:) / insertIds(_:at:) / removeIds(_:) — incremental updates of the id flavor; the index flavor does the same with append(_:), insert(_:at:) and the inherited removeIndexes(_:). Realized items, selection and scroll position are preserved."
                ),
                tr(
                    "selectedIds / selectedIndexes — selection readouts. The index flavor has no id dimension (identity is the index), so selectedIndexes is its native readout; ItemsView exposes no native selection set and its selectionChanged args are an empty shell."
                ),
                tr(
                    "animatesItemChanges — item add/remove/move transition animations, on by default. Built on the code subclass FadeSlideItemTransitionProvider (fade+slide in, fade out, smooth reflows); other styles — e.g. the native LinedFlowLayoutItemCollectionTransitionProvider (scale in/out) — can be assigned via the inherited itemTransitionProvider."
                ),
                tr(
                    "Everything else (layout, selectionMode, select/deselect, events, rebuildViews, verticalCacheLength) lives on ItemsViewBase and is inherited by both flavors unchanged."
                ),
            ]),
        Section(
            glyph: "\u{E71B}",
            title: tr("String id or index"),
            points: [
                tr(
                    "Pick the id flavor when items have an identity that must survive insert/remove (model keys, URLs): content derives from the id and stays put while indexes shift."
                ),
                tr(
                    "Pick the index flavor when data is naturally positional (array rows, snapshot pages): no id bookkeeping, no stringify/parse round-trips, zero unboxing dependencies."
                ),
                tr(
                    "After insert/remove the index flavor re-numbers content by position; realized containers not re-prepared by the repeater are reconciled on the next layout pass (displayedIndex vs getElementIndex)."
                ),
                tr(
                    "A stable-integer-id flavor (database primary keys) is deliberately not provided: reading a boxed integer back returns an opaque IInspectable (as? Int always fails), so it would need an unboxing shim in the projection fork first."
                ),
            ]),
        Section(
            glyph: "\u{E713}",
            title: tr("Usage rules"),
            points: [
                tr(
                    "Item views are rebuilt when containers are realized (virtualization included); return fresh views and never cache old elements."
                ),
                tr(
                    "itemsSource is one internal observable vector callers never touch: its elements are the id strings in the id flavor, or write-only index numbers in the index flavor (count, order and change notification only)."
                ),
                tr(
                    "Layout stays the native ItemsView property; the default style is already a single-column StackLayout — set your own for spacing or grids."
                ),
                tr(
                    "The list needs a parent of finite height (e.g. a star Grid row) to scroll inside; an infinite StackPanel breaks scrolling."
                ),
            ]),
        Section(
            glyph: "\u{E713}",
            title: tr("Code-built itemTemplate"),
            points: [
                tr(
                    "DataTemplate content cannot be defined in pure code (WinUI has no FrameworkElementFactory), but ItemsView.itemTemplate actually accepts any IElementFactory."
                ),
                tr(
                    "The projection lets Swift types implement WinRT interfaces: the container factory pools cleared containers in recycleElement and reuses them in getElement (mirroring WinUI's ItemTemplateWrapper + RecyclePool), replacing the former XAML string template."
                ),
                tr(
                    "The internal itemsSource is a single observable vector created by the typed factory single_threaded_observable_vector (C++ shim underneath; the projection has no such factory); in-place mutations fire native VectorChanged, which drives the repeater's incremental realization."
                ),
            ]),
        Section(
            glyph: "\u{E713}",
            title: tr("Layout configuration"),
            points: [
                tr(
                    "This page sets its own StackLayout(spacing: 4) via list.layout — the standard way clients configure layouts; the interactive demo (both flavors, selection modes, add/remove items, UniformGridLayout switch) lives in the Item List View page."
                ),
            ]),
    ]

    /// `ItemsView` / `ItemsIndexView` 源码节选 —— 手维护快照（非构建生成），随控件
    /// 演进可能过期，以 `Sources/RsUI/Controls/ItemsView.swift` 与
    /// `Sources/RsUI/Controls/ItemsIndexView.swift` 为准；已略去 doc 注释与
    /// 视觉树遍历辅助。
    private static var fullSource: String {
        """
        // 节选自 Sources/RsUI/Controls —— 手维护快照，以源文件为准。
        // 共享基座：向量载体 + repeater 接线 + 过渡动画 + 按索引增删与选择读取。
        open class ItemsViewBase: WinUI.ItemsView {
            internal private(set) var repeater: ItemsRepeater?
            internal let items: WinUI.IVectorAny

            // init：创建可观察向量，itemTemplate = makeContainerFactory()，
            // itemsSource = 向量；loaded/layoutUpdated 重试 wireRepeater()，
            // elementPrepared/elementClearing 分发到下方两个挂钩。
            func fillContainer(_ container: ItemContainer) {}   // 叶类覆写
            func clearContainer(_ container: ItemContainer) {}  // 叶类覆写
            // 池复用工厂：recycleElement 入池、getElement 取池（repeater 清除
            // 容器时不摘离子集合，靠工厂复用消化，见 RecyclableItemContainerFactory）。
            func makeContainerFactory() -> RecyclableItemContainerFactory { /* ... */ }

            public var animatesItemChanges = true { /* 接入/摘除过渡 provider */ }
            public var count: Int { Int((try? items.get_Size()) ?? 0) }

            /// 按索引移除（增量）：越界告警跳过，倒序删除。
            public func removeIndexes(_ indexes: [Int]) { /* ... */ }

            public var verticalCacheLength: Double { /* 接线前暂存 */ get { 2.0 } set {} }
            public func rebuildViews() { itemTemplate = makeContainerFactory() }
            public var selectedIndexes: [Int] { /* 按 isSelected 全量扫描 */ [] }
        }

        // —— 字符串 id 味：向量元素即 id，身份稳定 ——
        open class ItemsView: ItemsViewBase {
            public var makeIdView: (String) -> UIElement
            public var unloadView: ((String) -> Void)?

            public init(makeIdView: @escaping (String) -> UIElement) { /* ... */ }
            public var ids: [String] { /* string(at:) 逐项解箱快照 */ [] }
            public func setIds(_ newIds: [String]) { /* Clear + Append + wireRepeater */ }
            public func appendIds(_ newIds: [String]) { /* 逐项 Append */ }
            public func insertIds(_ newIds: [String], at index: Int) { /* 逐项 InsertAt */ }
            public func removeIds(_ idsToRemove: [String]) { /* id 匹配换算索引 → removeIndexes */ }
            public var selectedIds: [String] { /* 桥接原生 selectedItems，逐项解箱 */ [] }

            override func fillContainer(_ container: ItemContainer) {
                // getElementIndex → items.string(at:) 取 id → tag 记 id（clearing
                // 时索引失效靠 tag 反查）→ makeIdView(id) 填 child。
            }
            override func clearContainer(_ container: ItemContainer) { /* tag 解箱 → unloadView */ }
        }

        // —— 索引味：makeView 直收 repeater 索引，位置即身份，全程不读回元素值 ——
        open class ItemsIndexView: ItemsViewBase {
            public var makeView: (Int) -> UIElement
            public var unloadView: ((Int) -> Void)?   // 容器最后展示的索引

            public init(makeView: @escaping (Int) -> UIElement) { /* ... */ }
            public func setCount(_ count: Int) { /* Clear + Append(索引数字) + wireRepeater */ }
            public func append(_ count: Int) { /* 逐项 Append */ }
            public func insert(_ count: Int, at index: Int) { /* 逐项 InsertAt + scheduleReconcile() */ }
            public override func removeIndexes(_ indexes: [Int]) {
                super.removeIndexes(indexes)
                scheduleReconcile()
            }

            // 顺移对账：repeater 在下一次布局才消化向量变更，挂在 layoutUpdated
            // 上差量重填 displayedIndex ≠ getElementIndex 的容器（幂等，与原生
            // elementPrepared 重发共存）。
            private func scheduleReconcile() { reconcilePending = true }
            private func reconcileIfNeeded() { /* 差量重填 */ }

            override func fillContainer(_ container: ItemContainer) {
                // getElementIndex → 容器子类的 displayedIndex 属性记索引（免 tag
                // 装箱解箱）→ makeView(index) 填 child。
            }
            override func clearContainer(_ container: ItemContainer) { /* displayedIndex → unloadView */ }
            override func makeContainerFactory() -> IElementFactory { IndexedItemContainerFactory() }
        }

        // 索引味的条目容器：Swift 属性携带"最后展示的索引"（读回装箱 Int 是
        // 不透明 IInspectable，as? Int 恒失败，故不走 tag）。
        private final class IndexedItemContainer: ItemContainer {
            var displayedIndex: Int?
        }
        """
    }
}
