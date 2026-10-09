import CppWinRT
import Foundation
import RsUI
import UWP
import WinUI
import WindowsFoundation

final class ItemsViewPage: RsUI.Page {
    let url = URL(string: "rs://\(sampleModuleID)/items-view")!
    var title: String { tr("Items View") }

    var header: Any? {
        featurePageHeader(
            title: tr("Items View"),
            description: tr(
                "A code-filled list over ItemsView in two flavors: string ids (identity stays stable while indexes shift) and pure indexes (content follows position). Toggle the item identity and drive the same incremental actions — inserting at the top keeps row content in the id flavor but renumbers it in the index flavor; Reset rebuilds the whole list."
            )
        )
    }

    var content: WinUI.UIElement {
        var nextNumber = 100
        var useIndexFlavor = false

        let countText = TextBlock()
        let selectionText = TextBlock()
        let tappedText = TextBlock()
        for text in [countText, selectionText, tappedText] {
            text.textWrapping = .wrap
        }

        // 双味各持一个实例：同一套按钮作用于当前激活的味，切换开关换显示。
        let idList = RsUI.ItemsView { id in
            Self.makeItemRow(id: id)
        }
        idList.selectionMode = .single

        let indexList = RsUI.ItemsIndexView { index in
            Self.makeIndexRow(index: index)
        }
        indexList.selectionMode = .single
        indexList.visibility = .collapsed

        let lists = [idList, indexList]

        // 布局是 ItemsView 原生属性（默认样式即单列 StackLayout、间距 0），按需自行设置：
        // 这里给列表布局加 4px 间距，并另备网格布局供开关切换。
        let listLayout = StackLayout()
        listLayout.spacing = 4

        let gridLayout = UniformGridLayout()
        gridLayout.minItemWidth = 240
        gridLayout.minItemHeight = 64
        gridLayout.minRowSpacing = 8
        gridLayout.minColumnSpacing = 8

        func updateCountText() {
            let count = useIndexFlavor ? indexList.count : idList.count
            countText.text = String(format: tr("Items: %d"), Int32(count))
        }

        func updateSelectionText() {
            let titles: [String]
            if useIndexFlavor {
                titles = indexList.selectedIndexes.map(Self.indexTitle)
            } else {
                titles = idList.selectedIds.map(Self.itemTitle(id:))
            }
            selectionText.text = tr("Selected") + " (" + String(titles.count) + "): "
                + titles.joined(separator: ", ")
        }

        // selectionChanged 事件参数是空壳，读取选择走 selectedIds / selectedIndexes。
        // 两个实例都订阅：只有当前显示的味会实际触发。
        idList.selectionChanged.addHandler { _, _ in
            if !useIndexFlavor { updateSelectionText() }
        }
        indexList.selectionChanged.addHandler { _, _ in
            if useIndexFlavor { updateSelectionText() }
        }
        // 双击第一下会把 currentItemIndex 移到被点条目：字符串味按索引换回 id，
        // 索引味的身份就是索引本身。
        idList.doubleTapped.addHandler { [weak idList] _, _ in
            guard let idList, idList.currentItemIndex >= 0,
                idList.ids.indices.contains(Int(idList.currentItemIndex))
            else { return }
            tappedText.text = tr("Double-tapped") + ": "
                + Self.itemTitle(id: idList.ids[Int(idList.currentItemIndex)])
        }
        indexList.doubleTapped.addHandler { [weak indexList] _, _ in
            guard let indexList, indexList.currentItemIndex >= 0 else { return }
            tappedText.text = tr("Double-tapped") + ": "
                + Self.indexTitle(Int(indexList.currentItemIndex))
        }

        func makeNewIds(_ n: Int) -> [String] {
            let new = (nextNumber..<(nextNumber + n)).map {
                String(format: "%03d", Int32($0))
            }
            nextNumber += n
            return new
        }

        // —— 味切换：换显示实例并刷新状态行 ——
        let identityLabel = TextBlock()
        identityLabel.text = tr("Item identity")
        identityLabel.verticalAlignment = .center

        let identityButtons = ToggleButtons()
        identityButtons.addItem(iconGlyph: "\u{E8B7}", label: tr("String id"), tag: "string")
        identityButtons.addItem(iconGlyph: "\u{E712}", label: tr("Index"), tag: "index")
        identityButtons.selectionChanged.addHandler { _, tag in
            useIndexFlavor = tag == "index"
            idList.visibility = useIndexFlavor ? .collapsed : .visible
            indexList.visibility = useIndexFlavor ? .visible : .collapsed
            tappedText.text = ""
            updateCountText()
            updateSelectionText()
        }
        identityButtons.selectedTag = "string"

        let identityPanel = StackPanel()
        identityPanel.orientation = .horizontal
        identityPanel.spacing = 8
        identityPanel.children.append(identityLabel)
        identityPanel.children.append(identityButtons)

        // 增量增删：原生 VectorChanged 驱动 repeater 增量实现化，
        // 已实现条目、选择与滚动位置都保留（与"重置"按钮的整建形成对比）。
        // 索引味的对照看点：insert at top 后字符串味行内容不动（id 身份），
        // 索引味整段重新编号（位置身份）。
        let addButton = Button()
        addButton.content = tr("Add 10 items")
        addButton.click.addHandler { _, _ in
            if useIndexFlavor {
                indexList.append(10)
            } else {
                idList.appendIds(makeNewIds(10))
            }
            updateCountText()
            updateSelectionText()
        }

        let insertButton = Button()
        insertButton.content = tr("Insert 10 at top")
        insertButton.click.addHandler { _, _ in
            if useIndexFlavor {
                indexList.insert(10, at: 0)
            } else {
                idList.insertIds(makeNewIds(10), at: 0)
            }
            updateCountText()
            updateSelectionText()
        }

        let removeButton = Button()
        removeButton.content = tr("Remove 10 items")
        removeButton.click.addHandler { _, _ in
            // 移除取当前列表末尾 10 条：字符串味按 id（顺序无关），索引味按索引。
            if useIndexFlavor {
                let count = indexList.count
                indexList.removeIndexes(Array(Swift.max(0, count - 10)..<count))
            } else {
                idList.removeIds(Array(idList.ids.suffix(10)))
            }
            updateCountText()
            updateSelectionText()
        }

        let resetButton = Button()
        resetButton.content = tr("Reset")
        resetButton.click.addHandler { _, _ in
            if useIndexFlavor {
                indexList.setCount(indexList.count)
            } else {
                idList.setIds(idList.ids)
            }
            updateCountText()
            updateSelectionText()
        }

        let modeLabel = TextBlock()
        modeLabel.text = tr("Selection mode")
        modeLabel.verticalAlignment = .center

        let modeButtons = ToggleButtons()
        modeButtons.addItem(iconGlyph: "\u{E711}", label: tr("None"), tag: "none")
        modeButtons.addItem(iconGlyph: "\u{E73E}", label: tr("Single"), tag: "single")
        modeButtons.addItem(iconGlyph: "\u{E8FD}", label: tr("Extended"), tag: "extended")
        modeButtons.selectionChanged.addHandler { _, tag in
            let mode: WinUI.ItemsViewSelectionMode
            switch tag {
            case "none": mode = .none
            case "extended": mode = .extended
            default: mode = .single
            }
            for list in lists {
                list.selectionMode = mode
            }
            updateSelectionText()
        }
        modeButtons.selectedTag = "single"

        let modePanel = StackPanel()
        modePanel.orientation = .horizontal
        modePanel.spacing = 8
        modePanel.children.append(modeLabel)
        modePanel.children.append(modeButtons)

        // 布局与过渡风格对两个实例同时生效，切换味时无需同步。
        for list in lists {
            list.layout = listLayout
        }

        let layoutToggle = ToggleSwitch()
        layoutToggle.header = tr("Grid layout")
        layoutToggle.onContent = tr("On")
        layoutToggle.offContent = tr("Off")
        layoutToggle.toggled.addHandler { _, _ in
            let layout = layoutToggle.isOn ? gridLayout : listLayout
            for list in lists {
                list.layout = layout
            }
        }

        // 过渡动画风格三选：内置 FadeSlide（默认）、原生 LinedFlowLayout 的缩放
        // 洗牌风格、关闭。直接改赋 itemTransitionProvider，演示进阶出口。
        let transitionButtons = ToggleButtons()
        transitionButtons.addItem(iconGlyph: "\u{E711}", label: tr("None"), tag: "none")
        transitionButtons.addItem(iconGlyph: "\u{E70D}", label: tr("Fade & slide"), tag: "fadeSlide")
        transitionButtons.addItem(iconGlyph: "\u{E8E9}", label: tr("Scale"), tag: "scale")
        transitionButtons.selectionChanged.addHandler { _, tag in
            let provider: WinUI.ItemCollectionTransitionProvider?
            switch tag {
            case "none": provider = nil
            case "scale": provider = LinedFlowLayoutItemCollectionTransitionProvider()
            default: provider = FadeSlideItemTransitionProvider()
            }
            for list in lists {
                list.itemTransitionProvider = provider
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
        controls.children.append(identityPanel)
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
        // 两个列表实例同占该行，按当前味互斥显示。
        let root = Grid()
        root.padding = Thickness(left: 40, top: 0, right: 40, bottom: 32)
        let infoRow = RowDefinition()
        infoRow.height = GridLength(value: 0, gridUnitType: .auto)
        let listRow = RowDefinition()
        listRow.height = GridLength(value: 1, gridUnitType: .star)
        root.rowDefinitions.append(infoRow)
        root.rowDefinitions.append(listRow)
        try? Grid.setRow(topPanel, 0)
        try? Grid.setRow(idList, 1)
        try? Grid.setRow(indexList, 1)
        root.children.append(topPanel)
        root.children.append(idList)
        root.children.append(indexList)

        idList.setIds((0..<100).map { String(format: "%03d", Int32($0)) })
        indexList.setCount(100)
        updateCountText()
        updateSelectionText()

        return root
    }

    /// 条目标题从字符串 id 派生（本演示 id 即零填充序号），保证索引顺移后行内容不变。
    private static func itemTitle(id: String) -> String {
        String(format: tr("Item %02d"), Int32(id) ?? 0)
    }

    /// 索引味条目标题：身份就是索引，顺移后内容随位置重新编号。
    private static func indexTitle(_ index: Int) -> String {
        String(format: tr("Item %02d"), Int32(index))
    }

    /// 字符串味条目内容按 id 构建：图标 + 标题 + 副行直接显示 id，演示 id 身份。
    private static func makeItemRow(id: String) -> UIElement {
        makeRow(title: itemTitle(id: id), subtitle: "id: " + id, seed: Int(id) ?? 0)
    }

    /// 索引味条目内容按索引构建：副行显示索引，与字符串味形成顺移行为对照。
    private static func makeIndexRow(index: Int) -> UIElement {
        makeRow(title: indexTitle(index), subtitle: "index: \(index)", seed: index)
    }

    private static func makeRow(title: String, subtitle: String, seed: Int) -> UIElement {
        let icon = FontIcon()
        icon.glyph = itemGlyphs[seed % itemGlyphs.count]
        icon.fontSize = 18
        icon.verticalAlignment = .center

        let titleBlock = TextBlock()
        titleBlock.text = title
        titleBlock.textTrimming = .characterEllipsis

        let subtitleBlock = TextBlock()
        subtitleBlock.text = subtitle
        subtitleBlock.fontSize = 12
        subtitleBlock.opacity = 0.7
        subtitleBlock.textTrimming = .characterEllipsis

        let texts = StackPanel()
        texts.spacing = 2
        texts.verticalAlignment = .center
        texts.children.append(titleBlock)
        texts.children.append(subtitleBlock)

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
