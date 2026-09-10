import Foundation
import RsUI
import UWP
import WinUI
import WindowsFoundation

final class ToggleButtonsPage: RsUI.Page {
    let context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://sample/toggle-buttons")! }
    var title: String { tr("Toggle Buttons") }

    var header: Any? {
        featurePageHeader(
            title: tr("Toggle Buttons"),
            description: tr(
                "A RadioButtons-like single-select group built from AppBarToggleButtons laid out by a VariableSizedWrapGrid. Only one item stays checked; tapping the checked item does not uncheck it. Items are identified by their tag string."
            )
        )
    }

    var content: WinUI.UIElement {
        // SettingsCard 的 content 列是 auto 宽，VariableSizedWrapGrid 在其窄测量约束下
        // 会收缩成单列，故这里用 SettingsCard(content:) 全宽形态（同 RangeSliderPage 的
        // 窗宽/窗位卡片），说明文字由面板自带。
        let basicCard = SettingsCard(content: makeViewModePanel())
        let wrapCard = SettingsCard(content: makeWrapPanel())

        return featurePageContent([basicCard, wrapCard])
    }

    private func makeViewModePanel() -> WinUI.StackPanel {
        let readout = TextBlock()
        readout.minWidth = 110
        readout.verticalAlignment = .center

        let group = ToggleButtons()
        group.addItem(iconGlyph: "\u{E790}", label: nil, tag: "day", tooltip: tr("Day view"))
        group.addItem(iconGlyph: "\u{E787}", label: nil, tag: "week", tooltip: tr("Week view"))
        group.addItem(iconGlyph: "\u{E71D}", label: nil, tag: "month", tooltip: tr("Month view"))
        group.addItem(iconGlyph: "\u{E771}", label: nil, tag: "year", tooltip: tr("Year view"))
        group.addItem(iconGlyph: "\u{E8FD}", label: nil, tag: "all", tooltip: tr("All items"))

        let selectMonthButton = Button()
        selectMonthButton.content = tr("Select Month")

        let enableToggle = ToggleSwitch()
        enableToggle.header = tr("Enable group")
        enableToggle.isOn = group.isEnabled
        enableToggle.toggled.addHandler { _, _ in
            group.isEnabled = enableToggle.isOn
        }

        let row = StackPanel()
        row.orientation = .horizontal
        row.spacing = 12
        row.children.append(readout)
        row.children.append(selectMonthButton)
        row.children.append(enableToggle)

        let panel = StackPanel()
        panel.orientation = .vertical
        panel.spacing = 12
        panel.children.append(makeSectionTitle(tr("View mode")))
        panel.children.append(
            makeSectionSubtitle(
                tr(
                    "selectionChanged reports the tag of the newly checked item. The button sets selectedTag programmatically — same commit path, same event."))
        )
        panel.children.append(group)
        panel.children.append(row)

        // 事件先行挂接，初始选中与程序化设置都走同一条 commit 路径驱动 readout。
        group.selectionChanged.addHandler { _, tag in
            readout.text = "\(tr("Selected tag:")) \(tag)"
        }
        selectMonthButton.click.addHandler { _, _ in
            group.selectedTag = "month"
        }
        group.selectedTag = "week"

        return panel
    }

    private func makeWrapPanel() -> WinUI.StackPanel {
        let group = ToggleButtons()
        group.maxWidth = 300
        for (label, tag) in [
            ("XS", "xs"), ("S", "s"), ("M", "m"), ("L", "l"),
            ("XL", "xl"), ("2XL", "2xl"), ("3XL", "3xl"),
        ] {
            group.addItem(iconGlyph: "\u{E8E9}", label: label, tag: tag)
        }
        group.selectedTag = "m"

        let panel = StackPanel()
        panel.orientation = .vertical
        panel.spacing = 12
        panel.width = 320
        panel.children.append(makeSectionTitle(tr("Wrapping and spacing")))
        panel.children.append(
            makeSectionSubtitle(
                tr(
                    "Icon-less items with spacing 8 inside a width-constrained group, so the wrap grid flows them onto new rows.")))
        panel.children.append(group)
        return panel
    }

    private func makeSectionTitle(_ text: String) -> TextBlock {
        let title = TextBlock()
        title.text = text
        title.fontSize = 14
        return title
    }

    private func makeSectionSubtitle(_ text: String) -> TextBlock {
        let subtitle = TextBlock()
        subtitle.text = text
        subtitle.fontSize = 12
        subtitle.textWrapping = .wrap
        subtitle.foreground = SolidColorBrush(
            App.context.theme.isDark
                ? Color(a: 255, r: 174, g: 178, b: 190)
                : Color(a: 255, r: 96, g: 104, b: 112))
        return subtitle
    }
}
