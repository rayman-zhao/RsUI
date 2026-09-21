import Foundation
import RsUI
import UWP
import WinUI

/// ItemsView 的工作总结/使用文档页。文档主体以条目列表呈现，
/// 演示"有限高度父容器 + 组件公开 API"的实际用法；开关切换查看完整源码。
final class ItemsViewDocumentationPage: RsUI.Page {
    let url = URL(string: "rs://\(sampleModuleID)/items-view-doc")!
    var title: String { tr("Items View Documentation") }

    var content: WinUI.UIElement {
        // 文档小节以序号字符串为 id（内容本就静态，id 仅保持接口一致）。
        let list = RsUI.ItemsView { id in
            Self.makeDocumentRow(section: Self.sections[Int(id) ?? 0])
        }

        // 布局是 ItemsView 原生属性，默认样式即单列 StackLayout；这里仅加 4px 间距。
        let listLayout = StackLayout()
        listLayout.spacing = 4
        list.layout = listLayout
        list.setIds(Self.sections.indices.map(String.init))

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
                    "ItemsView wraps that pattern: callers provide a string id list and a build closure; item content is derived from the id, so it stays stable while indexes shift on insert/remove."
                ),
            ]),
        Section(
            glyph: "\u{E8E5}",
            title: tr("Public API"),
            points: [
                tr(
                    "init(makeIdView:) — the only initializer parameter (view build closure, keyed by string id)."
                ),
                tr("setIds(_:) — full reset with a new id list (selection and scroll position reset)."),
                tr(
                    "appendIds(_:) / insertIds(_:at:) / removeIds(_:) / removeIndexes(_:) — incremental updates over the internal observable vector; realized items, selection and scroll position are preserved. Positions are expressed by index, identity by id (ids must be unique)."
                ),
                tr(
                    "selectedIds — id-based selection readout built on selectedIndexes + string(at:), the same reading primitive as ids (ItemsView exposes no native selection set; its selectionChanged args are an empty shell)."
                ),
                tr(
                    "animatesItemChanges — item add/remove/move transition animations, on by default. Built on the code subclass FadeSlideItemTransitionProvider (fade+slide in, fade out, smooth reflows); other styles — e.g. the native LinedFlowLayoutItemCollectionTransitionProvider (scale in/out) — can be assigned via the inherited itemTransitionProvider."
                ),
                tr(
                    "Everything else (layout, selectionMode, select/deselect, events) is inherited from ItemsView unchanged."
                ),
            ]),
        Section(
            glyph: "\u{E713}",
            title: tr("Usage rules"),
            points: [
                tr(
                    "Item views are rebuilt by id when containers are realized (virtualization included); return fresh views and never cache old elements."
                ),
                tr(
                    "itemsSource is driven by one internal observable vector whose elements are the id strings (count, order and virtualization only); callers never touch it."
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
                    "The projection lets Swift types implement WinRT interfaces: ItemContainerFactory returns a new ItemContainer() per getElement and no-ops recycleElement, replacing the former XAML string template."
                ),
                tr(
                    "The control no longer depends on XamlReader or App.context; verified at runtime via UI Automation — items render and selection reads back correctly."
                ),
                tr(
                    "The internal itemsSource is a single observable vector created by the typed factory single_threaded_observable_vector (C++ shim underneath; the projection has no such factory); in-place mutations fire native VectorChanged, which drives the repeater's incremental realization."
                ),
            ]),
        Section(
            glyph: "\u{E713}",
            title: tr("Layout switching demo"),
            points: [
                tr(
                    "This page sets its own StackLayout(spacing: 4) via list.layout — the standard way clients configure layouts; the interactive demo (selection modes, add/remove items, UniformGridLayout switch) lives in the Item List View page."
                ),
            ]),
    ]

    /// `ItemsView` 源码节选 —— 手维护快照（非构建生成），随控件演进可能过期，
    /// 以 `Sources/RsUI/Controls/ItemsView.swift` 为准；已略去 `ids` / `selectedIds`
    /// 等简单转发属性。
    private static var fullSource: String {
        """
        // 节选自 Sources/RsUI/Controls/ItemsView.swift —— 手维护快照，以源文件为准。
        open class ItemsView: WinUI.ItemsView {

            public var makeIdView: (String) -> UIElement

            private var isRepeaterWired = false
            private var repeater: ItemsRepeater?
            /// itemsSource 载体：单一可观察向量；计数、按索引取 id 与增删都
            /// 直接走它，不维护 Swift 侧镜像。
            private let items: WinUI.IVectorAny
            /// 条目过渡动画载体（内置 FadeSlide，见 animatesItemChanges）。
            private let transitionProvider: FadeSlideItemTransitionProvider

            public init(makeIdView: @escaping (String) -> UIElement) {
                self.makeIdView = makeIdView
                guard let vector = single_threaded_observable_vector([]) else {
                    fatalError("ItemsView: failed to create the observable items vector")
                }
                items = vector
                transitionProvider = FadeSlideItemTransitionProvider()
                super.init()
                itemTemplate = ItemContainerFactory()
                itemsSource = vector
                // StackLayout / UniformGridLayout 都不带默认 transition provider
                // （Layout 基类返回空），这里显式接入，见 animatesItemChanges。
                itemTransitionProvider = transitionProvider

                loaded.addHandler { [weak self] _, _ in
                    self?.wireRepeater()
                }
                layoutUpdated.addHandler { [weak self] _, _ in
                    self?.wireRepeater()
                }
            }

            /// 条目增删/顺移过渡动画开关（默认 true；自定义风格可改赋
            /// itemTransitionProvider，置 nil 完全关闭）。
            public var animatesItemChanges = true {
                didSet {
                    guard animatesItemChanges != oldValue else { return }
                    itemTransitionProvider = animatesItemChanges ? transitionProvider : nil
                }
            }

            public var count: Int {
                Int((try? items.get_Size()) ?? 0)
            }

            /// 显示顺序下的 id 快照（ids 逐项读取同理，略）。
            /// 向量元素是装箱字符串，string(at:)（cppwinrt 扩展）在原生侧
            /// 一次往返完成 GetAt + 解箱。

            /// 整体重置（选择与滚动位置重置）；增删走增量接口。
            /// 注：不使用 ReplaceAll —— 投影对 [Any?] 数组的封送（AnyBridge）会崩溃。
            public func setIds(_ newIds: [String]) {
                try? items.Clear()
                for id in newIds {
                    try? items.Append(id)
                }
                wireRepeater()
            }

            /// 增量追加：已实现条目与选择、滚动位置保留。
            public func appendIds(_ newIds: [String]) {
                for id in newIds {
                    try? items.Append(id)
                }
            }

            /// 增量插入：其后条目索引顺移，内容按 id 保持不变。
            public func insertIds(_ newIds: [String], at index: Int) {
                guard !newIds.isEmpty else { return }
                let at = min(max(0, index), count)
                for id in newIds {
                    try? items.InsertAt(UInt32(at), id)
                }
            }

            /// 按 id 增量移除（顺序无关）：在 ids 快照上做纯 Swift 匹配，
            /// 换算成索引后委托 removeIndexes；未匹配的 id 告警并跳过。
            public func removeIds(_ idsToRemove: [String]) {
                let removeSet = Set(idsToRemove)
                let matched = ids.enumerated()
                    .filter { removeSet.contains($0.element) }
                removeIndexes(matched.map { $0.offset })
            }

            /// 按索引移除（对称 removeIds）：越界告警跳过，倒序删除。
            public func removeIndexes(_ indexes: [Int]) {
                let valid = Set(indexes.filter { $0 >= 0 && $0 < count })
                for index in valid.sorted(by: >) {
                    try? items.RemoveAt(UInt32(index))
                }
            }

            /// id 维度的选择读取：桥接原生 selectedItems 只读视图，
            /// 经 string(at:)（与 ids 同一读取 API 家族）逐项解箱。
            public var selectedIds: [String] {
                guard let selected = selectedItems else { return [] }
                return (0..<selected.count).compactMap { selected.string(at: $0) }
            }

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

            private func wireRepeater() {
                guard !isRepeaterWired,
                    let found = Self.findDescendant(ItemsRepeater.self, from: self)
                else { return }
                isRepeaterWired = true
                repeater = found
                found.elementPrepared.addHandler { [weak self] _, args in
                    guard let self, let args,
                        let container = args.element as? ItemContainer
                    else { return }
                    self.fillContainer(container)
                }
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
        }

        private final class ItemContainerFactory: IElementFactory {
            func getElement(_ args: ElementFactoryGetArgs!) throws -> UIElement! {
                ItemContainer()
            }
            func recycleElement(_ args: ElementFactoryRecycleArgs!) throws {}
        }
        """
    }
}
