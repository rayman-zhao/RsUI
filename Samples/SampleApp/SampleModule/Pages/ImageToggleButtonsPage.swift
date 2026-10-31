import Foundation
import RsUI
import UWP
import WinUI
import WindowsFoundation

/// 标准 WinUI 开关按钮承载 PNG 图片的对照演示（不涉及 RsUI 自定义控件）：
/// - `ToggleButton` 是 `ContentControl`，图片直接作为 `content`（可与其他元素组合）；
/// - `AppBarToggleButton` 有图标槽，同一张位图分别以 `ImageIcon`（原样彩色）与
///   `BitmapIcon`（`showAsMonochrome` 重染为前景色）接入。
final class ImageToggleButtonsPage: RsUI.Page {
    let url = URL(string: "rs://\(sampleModuleID)/image-toggle-buttons")!
    var title: String { tr("Image Toggle Buttons") }

    private let shapes: [(name: String, tag: String)] = [
        ("Circle", "circle"), ("Square", "square"), ("Triangle", "triangle"),
        ("Diamond", "diamond"), ("Ring", "ring"), ("Hexagon", "hexagon"),
    ]

    /// 由一张带文字标注的细胞大图（3 行 × 5 列）切出的 15 个图标。
    private let cells: [(name: String, tag: String)] = [
        ("Monocyte", "cell-monocyte"), ("Lymphocyte", "cell-lymphocyte"),
        ("Basophil", "cell-basophil"), ("Eosinophil", "cell-eosinophil"),
        ("Neutrophil", "cell-neutrophil"),
        ("Resting macrophage", "cell-macrophage-resting"),
        ("Activated macrophage", "cell-macrophage-activated"),
        ("T cell", "cell-t-cell"), ("B cell", "cell-b-cell"),
        ("B cell with antibodies", "cell-b-cell-antibodies"),
        ("Mast cell", "cell-mast-cell"), ("Natural killer cell", "cell-nk-cell"),
        ("Dendritic cell", "cell-dendritic-cell"), ("Erythrocytes", "cell-erythrocytes"),
        ("Platelets", "cell-platelets"),
    ]

    /// 免疫荧光染色与 marker 池（专有名词，无需本地化）；页面构建时为每个细胞
    /// 随机抽选一次，两卡共用同一份分配，保证对照内容一致。
    private static let stainingNames = [
        "DAPI", "TRITC", "FITC", "Cy3", "Cy5", "PE", "APC", "PerCP",
        "Texas Red", "Alexa Fluor 488", "Alexa Fluor 594", "Rhodamine",
    ]
    private static let markerNames = [
        "Ki-67", "PD-L1", "CD3", "CD4", "CD8", "CD20", "CD68", "CD31", "CD34",
        "CD45", "CK AE1/AE3", "EMA", "HER2", "p53", "TTF-1", "PAX5", "MPO",
        "BCL-2", "BCL-6", "Synaptophysin",
    ]

    private lazy var cellStainings: [String] = cells.map { _ in
        Self.stainingNames.randomElement()!
    }
    private lazy var cellMarkers: [String] = cells.map { _ in
        Self.markerNames.randomElement()!
    }

    /// 图标下方色条的色池（红/绿/蓝/黄/灰/橙/紫/青），同样按细胞抽选一次。
    private static let barColors: [Color] = [
        Color(a: 0xFF, r: 0xE1, g: 0x11, b: 0x23),  // red
        Color(a: 0xFF, r: 0x10, g: 0x7C, b: 0x10),  // green
        Color(a: 0xFF, r: 0x00, g: 0x78, b: 0xD4),  // blue
        Color(a: 0xFF, r: 0xFF, g: 0xB9, b: 0x00),  // yellow
        Color(a: 0xFF, r: 0x82, g: 0x82, b: 0x82),  // gray
        Color(a: 0xFF, r: 0xF7, g: 0x63, b: 0x0C),  // orange
        Color(a: 0xFF, r: 0x88, g: 0x17, b: 0x98),  // purple
        Color(a: 0xFF, r: 0x00, g: 0xB7, b: 0xC3),  // cyan
    ]
    private lazy var cellBarColors: [Color] = cells.map { _ in
        Self.barColors.randomElement()!
    }

    var header: Any? {
        featurePageHeader(
            title: tr("Image Toggle Buttons"),
            description: tr(
                "Plain WinUI ToggleButton and AppBarToggleButton carrying PNG images, no custom control. ToggleButton takes the image as its content; AppBarToggleButton takes a BitmapIcon or ImageIcon in its icon slot."
            )
        )
    }

    var content: WinUI.UIElement {
        let contentCard = SettingsCard(content: makeToggleButtonPanel())
        let iconCard = SettingsCard(content: makeAppBarToggleButtonPanel())
        let cellCard = SettingsCard(content: makeCellIconsPanel())
        let gridCard = SettingsCard(content: makeCellGridViewPanel())
        // ItemsView 卡不能套 SettingsCard:SettingsCard 是 ButtonBase 子类,press
        // 未被 ItemContainer 置 handled(其点击选择只在 PointerReleased 触发),冒泡
        // 到卡片后被 ButtonBase 捕获并消费 release——条目点击选择因此全灭(hover、
        // 键盘、程序化不受影响)。此卡直接以裸面板进页流。
        let itemsPanel = makeCellItemsViewPanel()
        return featurePageContent([contentCard, iconCard, cellCard, gridCard, itemsPanel])
    }

    // MARK: - ToggleButton (image as content)

    private func makeToggleButtonPanel() -> WinUI.StackPanel {
        let row = StackPanel()
        row.orientation = .horizontal
        row.spacing = 8

        var buttons: [ToggleButton] = []
        for (name, tag) in shapes {
            let button = ToggleButton()
            button.content = makeShapeImage(tag, size: 20)
            try? ToolTipService.setToolTip(button, tr(name))
            try? AutomationProperties.setName(button, tr(name))
            buttons.append(button)
            row.children.append(button)
        }

        buttons[0].isChecked = true
        let readout = wireCheckedReadout(names: shapes.map(\.name), buttons: buttons)

        let composedRow = StackPanel()
        composedRow.orientation = .horizontal
        composedRow.spacing = 8
        for (name, tag) in [shapes[0], shapes[5]] {
            let stack = StackPanel()
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.children.append(makeShapeImage(tag, size: 16))
            let caption = TextBlock()
            caption.text = tr(name)
            caption.verticalAlignment = .center
            stack.children.append(caption)

            let button = ToggleButton()
            button.content = stack
            composedRow.children.append(button)
        }

        let panel = StackPanel()
        panel.orientation = .vertical
        panel.spacing = 12
        panel.children.append(makeSectionTitle(tr("ToggleButton — image as content")))
        panel.children.append(
            makeCaption(tr("Each button toggles independently; the checked state keeps the pressed background.")))
        panel.children.append(row)
        panel.children.append(readout)
        panel.children.append(
            makeCaption(tr("Content accepts any element — an image and a caption can be composed into one button.")))
        panel.children.append(composedRow)
        return panel
    }

    // MARK: - AppBarToggleButton (image as icon)

    private func makeAppBarToggleButtonPanel() -> WinUI.StackPanel {
        let colorRow = StackPanel()
        colorRow.orientation = .horizontal
        colorRow.spacing = 8

        let monoRow = StackPanel()
        monoRow.orientation = .horizontal
        monoRow.spacing = 8

        for (name, tag) in shapes {
            let uri = shapeImageUri(tag)

            let source = BitmapImage()
            source.uriSource = uri
            let image = ImageIcon()
            image.source = source
            let colorButton = AppBarToggleButton()
            colorButton.icon = image
            colorButton.label = tr(name)

            let bitmap = BitmapIcon()
            bitmap.uriSource = uri
            bitmap.showAsMonochrome = true
            let monoButton = AppBarToggleButton()
            monoButton.icon = bitmap
            monoButton.labelPosition = .collapsed
            monoButton.width = 44
            try? ToolTipService.setToolTip(monoButton, tr(name))

            colorRow.children.append(colorButton)
            monoRow.children.append(monoButton)
        }

        let panel = StackPanel()
        panel.orientation = .vertical
        panel.spacing = 12
        panel.children.append(makeSectionTitle(tr("AppBarToggleButton — image as icon")))
        panel.children.append(makeCaption(tr("ImageIcon — the bitmap is drawn in full color, unaffected by checked state.")))
        panel.children.append(colorRow)
        panel.children.append(
            makeCaption(
                tr("BitmapIcon — showAsMonochrome recolors the bitmap to the theme foreground, so it tracks hover, checked and theme states.")))
        panel.children.append(monoRow)
        return panel
    }

    // MARK: - Cell icons sliced from a sprite sheet

    /// 列表项形态：图标在左（40px），右侧三行文字——名称 / 描述 / 分类·序号。
    /// ToggleButton 卡与 ItemsView 卡共用同一行形态，形成两种选择机制的对照。
    private func makeCellIconsPanel() -> WinUI.StackPanel {
        let wrapGrid = VariableSizedWrapGrid()
        wrapGrid.orientation = .horizontal
        wrapGrid.itemWidth = 158
        wrapGrid.itemHeight = 88

        var buttons: [ToggleButton] = []
        func refreshCell(_ index: Int) {
            buttons[index].content = makeCellRow(
                index: index, name: cells[index].name, tag: cells[index].tag, rebuild: refreshCell)
        }
        for (index, entry) in cells.enumerated() {
            let button = ToggleButton()
            button.content = makeCellRow(
                index: index, name: entry.name, tag: entry.tag, rebuild: refreshCell)
            button.width = 154
            button.height = 84
            // 按钮自带内边距与行的 padding 叠加会令图标离左边过远，置零只留行的。
            button.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
            try? ToolTipService.setToolTip(button, tr(entry.name))
            try? AutomationProperties.setName(button, tr(entry.name))
            buttons.append(button)
            wrapGrid.children.append(button)
        }

        let readout = wireCheckedReadout(names: cells.map(\.name), buttons: buttons)

        let panel = StackPanel()
        panel.orientation = .vertical
        panel.spacing = 12
        panel.children.append(makeSectionTitle(tr("Cell icons sliced from a sprite sheet")))
        panel.children.append(
            makeCaption(
                tr("15 PNGs sliced from a single labeled illustration — border-flood background removal, content trim, square pad, natural source resolution."))
        )
        panel.children.append(wrapGrid)
        panel.children.append(readout)
        panel.children.append(
            makeCaption(tr("Right-click any row for a context menu to re-roll its random picks.")))
        return panel
    }

    /// 集合控件对照：同样的条目行直接作为 items 塞进原生 `GridView`
    /// （`SelectionMode = Multiple` + `ItemsWrapGrid` 均匀网格，面板参数经 XAML 定义）。
    /// 选中条目元素读回是装箱 `Any?`（不可解箱），选择读取走 `selectedRanges` 的索引。
    private func makeCellGridViewPanel() -> WinUI.StackPanel {
        // 不设高度：经典 ScrollViewer 在无限高父容器里按内容全展开（宽度受限时
        // ItemsWrapGrid 换行），整页交给外层页面滚动——这与 ItemsView 的新架构
        // ScrollView 行为相反（后者必须有限高度，见 AGENTS.md 坑清单）。
        let grid: GridView = App.context.requireXaml(withString: """
            <GridView SelectionMode="Multiple"
                      xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
                <GridView.ItemsPanel>
                    <ItemsPanelTemplate>
                        <ItemsWrapGrid Orientation="Horizontal" ItemWidth="158" ItemHeight="88"/>
                    </ItemsPanelTemplate>
                </GridView.ItemsPanel>
            </GridView>
            """)

        func refreshCell(_ index: Int) {
            try? grid.items.setAt(
                UInt32(index),
                makeCellRow(
                    index: index, name: cells[index].name, tag: cells[index].tag,
                    rebuild: refreshCell))
        }
        for (index, entry) in cells.enumerated() {
            grid.items.append(
                makeCellRow(index: index, name: entry.name, tag: entry.tag, rebuild: refreshCell))
        }

        let readout = makeCaption("")
        let update = {
            var names: [String] = []
            if let ranges = grid.selectedRanges {
                for i in 0..<Int(ranges.count) {
                    guard let range = try? ranges.getAt(UInt32(i)) else { continue }
                    for index in range.firstIndex...range.lastIndex where self.cells.indices.contains(Int(index)) {
                        names.append(tr(self.cells[Int(index)].name))
                    }
                }
            }
            readout.text = "\(tr("Selected:")) \(names.isEmpty ? tr("None") : names.joined(separator: ", "))"
        }
        grid.selectionChanged.addHandler { _, _ in update() }
        update()

        let panel = StackPanel()
        panel.orientation = .vertical
        panel.spacing = 12
        panel.children.append(makeSectionTitle(tr("Same cells on GridView — multi-select")))
        panel.children.append(
            makeCaption(
                tr("The native collection control for comparison: GridView (SelectionMode = Multiple, uniform ItemsWrapGrid) over the same rows. Clicks select via the GridViewItem containers; reads go through selectedRanges.")))
        panel.children.append(grid)
        panel.children.append(readout)
        return panel
    }

    /// 条目行本体：图标（40px，下方随机色条）在左，右侧名称（可折两行）/
    /// 随机染色名 / 随机 marker 名。行自带透明背景与内边距：整行参与命中测试
    /// （空隙不穿透），内容与容器的选中高亮边框拉开距离。
    /// 右键弹出重抽菜单，动作改完随机数组后经 `rebuild` 让宿主卡刷新该行
    /// （ToggleButton 换 content / GridView setAt）。
    private func makeCellRow(
        index: Int, name: String, tag: String, rebuild: @escaping (Int) -> Void
    ) -> StackPanel {
        let fill = Border()
        fill.background = SolidColorBrush(cellBarColors[index])
        fill.cornerRadius = CornerRadius(topLeft: 3, topRight: 3, bottomRight: 3, bottomLeft: 3)

        // 灰底轨道 + 彩色填充：选中态的强调色背景与明暗主题下，色条都有轮廓可辨。
        let track = Border()
        track.height = 8
        track.padding = Thickness(left: 1, top: 1, right: 1, bottom: 1)
        track.cornerRadius = CornerRadius(topLeft: 4, topRight: 4, bottomRight: 4, bottomLeft: 4)
        track.background = SolidColorBrush(Color(a: 0x59, r: 0x80, g: 0x80, b: 0x80))
        track.child = fill

        let iconColumn = StackPanel()
        iconColumn.spacing = 6
        iconColumn.verticalAlignment = .center
        iconColumn.children.append(makeShapeImage(tag, size: 40))
        iconColumn.children.append(track)

        let title = TextBlock()
        title.text = tr(name)
        title.textWrapping = .wrap
        title.maxWidth = 90

        let staining = TextBlock()
        staining.text = cellStainings[index]
        staining.fontSize = 12

        let marker = TextBlock()
        marker.text = cellMarkers[index]
        marker.fontSize = 12

        let textColumn = StackPanel()
        textColumn.spacing = 2
        textColumn.verticalAlignment = .center
        textColumn.children.append(title)
        textColumn.children.append(staining)
        textColumn.children.append(marker)

        let row = StackPanel()
        row.orientation = .horizontal
        row.spacing = 8
        row.padding = Thickness(left: 8, top: 4, right: 8, bottom: 4)
        row.width = 154
        row.background = SolidColorBrush(Color(a: 0x00, r: 0x00, g: 0x00, b: 0x00))
        row.children.append(iconColumn)
        row.children.append(textColumn)

        let menu = MenuFlyout()
        let actions: [(String, () -> Void)] = [
            (tr("Re-roll staining"), {
                self.cellStainings[index] = Self.stainingNames.randomElement()!
            }),
            (tr("Re-roll marker"), {
                self.cellMarkers[index] = Self.markerNames.randomElement()!
            }),
            (tr("Re-roll bar color"), {
                self.cellBarColors[index] = Self.barColors.randomElement()!
            }),
            (tr("Re-roll all"), {
                self.cellStainings[index] = Self.stainingNames.randomElement()!
                self.cellMarkers[index] = Self.markerNames.randomElement()!
                self.cellBarColors[index] = Self.barColors.randomElement()!
            }),
        ]
        for (label, action) in actions {
            let item = MenuFlyoutItem()
            item.text = label
            item.click.addHandler { _, _ in
                action()
                rebuild(index)
            }
            menu.items.append(item)
        }
        row.contextFlyout = menu
        return row
    }

    // MARK: - Image sources

    /// 集合控件对照(RsUI ItemsView 版):与上卡原生 GridView 同样的行,
    /// `selectionMode = .multiple`,读取走 `selectedIds`。
    /// 右键重抽后经 `rebuildViews()` 重造条目视图——itemsSource 与选择保持。
    /// 本面板不套 SettingsCard(ButtonBase 会吞掉 release,见 `content` 处注释)。
    private func makeCellItemsViewPanel() -> WinUI.StackPanel {
        var refreshList: (() -> Void)?
        let list = ItemsView { id in
            guard let index = self.cells.firstIndex(where: { $0.tag == id }) else {
                return TextBlock()
            }
            return self.makeCellRow(
                index: index, name: self.cells[index].name, tag: id, rebuild: { _ in
                    refreshList?()
                })
        }
        refreshList = { [weak list] in
            list?.rebuildViews()
        }
        list.selectionMode = .multiple

        let gridLayout = UniformGridLayout()
        gridLayout.minItemWidth = 158
        gridLayout.minRowSpacing = 8
        gridLayout.minColumnSpacing = 8
        list.layout = gridLayout
        list.setIds(cells.map(\.tag))

        let readout = makeCaption("")
        let update = {
            let names = list.selectedIds.compactMap { tag in
                self.cells.first(where: { $0.tag == tag })?.name
            }.map { tr($0) }
            readout.text = "\(tr("Selected:")) \(names.isEmpty ? tr("None") : names.joined(separator: ", "))"
        }
        // selectionChanged 的事件参数是空壳，选择读取一律走 selectedIds。
        list.selectionChanged.addHandler { _, _ in update() }
        update()

        let panel = StackPanel()
        panel.orientation = .vertical
        panel.spacing = 12
        panel.children.append(makeSectionTitle(tr("Same cells on ItemsView — multi-select")))
        panel.children.append(
            makeCaption(
                tr("The RsUI ItemsView flavor over the same rows (selectionMode = .multiple, reads via selectedIds), next to the native GridView card above.")))
        panel.children.append(list)
        panel.children.append(readout)
        return panel
    }

    /// checked 回显。投影没有 checked/unchecked 事件；click 在状态翻转之后触发，读
    /// isChecked 即新态（初始先跑一次，覆盖程序化置位）。
    private func wireCheckedReadout(names: [String], buttons: [ToggleButton]) -> TextBlock {
        let readout = makeCaption("")
        let update = {
            let checked = zip(names, buttons).filter { $1.isChecked == true }.map { tr($0.0) }
            readout.text = "\(tr("Checked:")) \(checked.isEmpty ? tr("None") : checked.joined(separator: ", "))"
        }
        for button in buttons {
            button.click.addHandler { _, _ in update() }
        }
        update()
        return readout
    }

    private func makeShapeImage(_ tag: String, size: Double) -> Image {
        let source = BitmapImage()
        source.uriSource = shapeImageUri(tag)
        let image = Image()
        image.source = source
        image.width = size
        image.height = size
        return image
    }

    /// 形状 PNG 由 `.process(Assets)` 扁平化到 resource bundle 根（同 SampleApp.ico），
    /// 以 `file:///` URI 提给 BitmapImage / BitmapIcon。
    private func shapeImageUri(_ name: String) -> Uri {
        guard let path = App.context.resourceBundle.path(forResource: name, ofType: "png") else {
            fatalError("ImageToggleButtonsPage: \(name).png not found in bundle \(App.context.resourceBundle)")
        }
        return Uri(URL(fileURLWithPath: path).absoluteString)
    }
}
