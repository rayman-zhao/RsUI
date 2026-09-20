import CppWinRT
import Foundation
import RsUI
import UWP
import WinUI
import WindowsFoundation

final class ItemsViewPage: RsUI.Page {
    var url: URL { URL(string: "rs://sample/items-view")! }
    var title: String { tr("Items View") }

    var header: Any? {
        featurePageHeader(
            title: tr("Items View"),
            description: tr(
                "A reusable list built over ItemsView, driven by string item ids. Item views are built by a Swift closure from the id, so content stays stable while indexes shift. Add, insert and remove items incrementally — realized items, selection and scroll position are preserved; Reset goes through setIds and rebuilds the whole list."
            )
        )
    }

    var content: WinUI.UIElement {
        var nextNumber = 100

        let countText = TextBlock()
        let selectionText = TextBlock()
        let tappedText = TextBlock()
        for text in [countText, selectionText, tappedText] {
            text.textWrapping = .wrap
        }

        let list = RsUI.ItemsView { id in
            Self.makeItemRow(id: id)
        }
        list.selectionMode = .single

        // 布局是 ItemsView 原生属性（默认样式即单列 StackLayout、间距 0），按需自行设置：
        // 这里给列表布局加 4px 间距，并另备网格布局供开关切换。
        let listLayout = StackLayout()
        listLayout.spacing = 4
        list.layout = listLayout

        let gridLayout = UniformGridLayout()
        gridLayout.minItemWidth = 240
        gridLayout.minItemHeight = 64
        gridLayout.minRowSpacing = 8
        gridLayout.minColumnSpacing = 8

        func updateCountText() {
            countText.text = String(format: tr("Items: %d"), Int32(list.count))
        }

        func updateSelectionText(_ list: RsUI.ItemsView) {
            let selected = list.selectedIds
            selectionText.text = tr("Selected") + " (" + String(selected.count) + "): "
                + selected.map(Self.itemTitle(id:)).joined(separator: ", ")
        }

        // ItemsView 的 selectionChanged 事件参数是空壳，读取选择走 selectedIds。
        list.selectionChanged.addHandler { [weak list] _, _ in
            if let list { updateSelectionText(list) }
        }
        // 双击第一下会把 currentItemIndex 移到被点条目，这里按索引换回 id。
        list.doubleTapped.addHandler { [weak list] _, _ in
            guard let list, list.currentItemIndex >= 0,
                list.ids.indices.contains(Int(list.currentItemIndex))
            else { return }
            tappedText.text = tr("Double-tapped") + ": "
                + Self.itemTitle(id: list.ids[Int(list.currentItemIndex)])
        }

        func makeNewIds(_ n: Int) -> [String] {
            let new = (nextNumber..<(nextNumber + n)).map {
                String(format: "%03d", Int32($0))
            }
            nextNumber += n
            return new
        }

        // 增量增删：原生 VectorChanged 驱动 repeater 增量实现化，
        // 已实现条目、选择与滚动位置都保留（与"重置"按钮的整建形成对比）。
        let addButton = Button()
        addButton.content = tr("Add 10 items")
        addButton.click.addHandler { _, _ in
            list.appendIds(makeNewIds(10))
            updateCountText()
            updateSelectionText(list)
        }

        let insertButton = Button()
        insertButton.content = tr("Insert 10 at top")
        insertButton.click.addHandler { _, _ in
            list.insertIds(makeNewIds(10), at: 0)
            updateCountText()
            updateSelectionText(list)
        }

        let removeButton = Button()
        removeButton.content = tr("Remove 10 items")
        removeButton.click.addHandler { _, _ in
            // 移除按 id、顺序无关：这里取当前列表末尾 10 个 id。
            list.removeIds(Array(list.ids.suffix(10)))
            updateCountText()
            updateSelectionText(list)
        }

        let resetButton = Button()
        resetButton.content = tr("Reset")
        resetButton.click.addHandler { _, _ in
            list.setIds(list.ids)
            updateCountText()
            updateSelectionText(list)
        }

        let modeLabel = TextBlock()
        modeLabel.text = tr("Selection mode")
        modeLabel.verticalAlignment = .center

        let modeButtons = ToggleButtons()
        modeButtons.addItem(iconGlyph: "\u{E711}", label: tr("None"), tag: "none")
        modeButtons.addItem(iconGlyph: "\u{E73E}", label: tr("Single"), tag: "single")
        modeButtons.addItem(iconGlyph: "\u{E8FD}", label: tr("Extended"), tag: "extended")
        modeButtons.selectionChanged.addHandler { _, tag in
            switch tag {
            case "none": list.selectionMode = .none
            case "extended": list.selectionMode = .extended
            default: list.selectionMode = .single
            }
            updateSelectionText(list)
        }
        modeButtons.selectedTag = "single"

        let modePanel = StackPanel()
        modePanel.orientation = .horizontal
        modePanel.spacing = 8
        modePanel.children.append(modeLabel)
        modePanel.children.append(modeButtons)

        let layoutToggle = ToggleSwitch()
        layoutToggle.header = tr("Grid layout")
        layoutToggle.onContent = tr("On")
        layoutToggle.offContent = tr("Off")
        layoutToggle.toggled.addHandler { _, _ in
            list.layout = layoutToggle.isOn ? gridLayout : listLayout
        }

        // 过渡动画风格三选：内置 FadeSlide（默认）、原生 LinedFlowLayout 的缩放
        // 洗牌风格、关闭。直接改赋 itemTransitionProvider，演示进阶出口。
        let transitionButtons = ToggleButtons()
        transitionButtons.addItem(iconGlyph: "\u{E711}", label: tr("None"), tag: "none")
        transitionButtons.addItem(iconGlyph: "\u{E70D}", label: tr("Fade & slide"), tag: "fadeSlide")
        transitionButtons.addItem(iconGlyph: "\u{E8E9}", label: tr("Scale"), tag: "scale")
        transitionButtons.selectionChanged.addHandler { _, tag in
            switch tag {
            case "none": list.itemTransitionProvider = nil
            case "scale": list.itemTransitionProvider = LinedFlowLayoutItemCollectionTransitionProvider()
            default: list.itemTransitionProvider = FadeSlideItemTransitionProvider()
            }
        }
        transitionButtons.selectedTag = "fadeSlide"

        let transitionLabel = TextBlock()
        transitionLabel.text = tr("Item animations")
        transitionLabel.verticalAlignment = .center

        let transitionPanel = StackPanel()
        transitionPanel.orientation = .horizontal
        transitionPanel.spacing = 8
        transitionPanel.children.append(transitionLabel)
        transitionPanel.children.append(transitionButtons)

        let controls = StackPanel()
        controls.orientation = .horizontal
        controls.spacing = 16
        controls.children.append(modePanel)
        controls.children.append(layoutToggle)
        controls.children.append(transitionPanel)
        controls.children.append(addButton)
        controls.children.append(insertButton)
        controls.children.append(removeButton)
        controls.children.append(resetButton)

        let topPanel = StackPanel()
        topPanel.spacing = 8
        topPanel.children.append(countText)
        topPanel.children.append(selectionText)
        topPanel.children.append(tappedText)
        topPanel.children.append(controls)

        // 列表需要有限高度才能内部滚动，放 star 行铺满剩余空间。
        let root = Grid()
        root.padding = Thickness(left: 40, top: 0, right: 40, bottom: 32)
        let infoRow = RowDefinition()
        infoRow.height = GridLength(value: 0, gridUnitType: .auto)
        let listRow = RowDefinition()
        listRow.height = GridLength(value: 1, gridUnitType: .star)
        root.rowDefinitions.append(infoRow)
        root.rowDefinitions.append(listRow)
        try? Grid.setRow(topPanel, 0)
        try? Grid.setRow(list, 1)
        root.children.append(topPanel)
        root.children.append(list)

        list.setIds((0..<100).map { String(format: "%03d", Int32($0)) })
        updateCountText()
        updateSelectionText(list)

        return root
    }

    /// 条目标题从 id 派生（本演示 id 即零填充序号），保证索引顺移后行内容不变。
    private static func itemTitle(id: String) -> String {
        String(format: tr("Item %02d"), Int32(id) ?? 0)
    }

    /// 条目内容按 id 构建：图标 + 标题 + 副行直接显示 id，演示 id 身份。
    private static func makeItemRow(id: String) -> UIElement {
        let number = Int(id) ?? 0

        let icon = FontIcon()
        icon.glyph = itemGlyphs[number % itemGlyphs.count]
        icon.fontSize = 18
        icon.verticalAlignment = .center

        let title = TextBlock()
        title.text = itemTitle(id: id)
        title.textTrimming = .characterEllipsis

        let subtitle = TextBlock()
        subtitle.text = "id: " + id
        subtitle.fontSize = 12
        subtitle.opacity = 0.7
        subtitle.textTrimming = .characterEllipsis

        let texts = StackPanel()
        texts.spacing = 2
        texts.verticalAlignment = .center
        texts.children.append(title)
        texts.children.append(subtitle)

        let row = StackPanel()
        row.orientation = .horizontal
        row.spacing = 12
        row.padding = Thickness(left: 14, top: 10, right: 14, bottom: 10)
        row.children.append(icon)
        row.children.append(texts)
        return row
    }

    private static let itemGlyphs = [
        "\u{E7B8}", "\u{E7C3}", "\u{E8B7}", "\u{E8FD}", "\u{E790}",
    ]
}
