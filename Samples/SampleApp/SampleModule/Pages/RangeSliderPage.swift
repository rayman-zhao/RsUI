import Foundation
import RsUI
import UWP
import WinUI
import WindowsFoundation

final class RangeSliderPage: RsUI.Page {
    let context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://sample/range-slider")! }
    var title: String { tr("Range Slider") }

    var header: Any? {
        featurePageHeader(
            title: tr("Range Slider"),
            description: tr(
                "A dual-thumb slider for picking a range. Drag a thumb, click the track, or drag between the thumbs to slide both together (width kept). Tab to a thumb for keyboard: ←/→ adjust, PageUp/PageDown larger steps, Home/End to the bounds."
            )
        )
    }

    var content: WinUI.UIElement {
        let basicCard = SettingsCard(
            headerIconGlyph: "\u{E712}",
            header: tr("Basic usage"),
            description: tr("The readout shows the current lower – upper values."),
            content: makeBasicDemoPanel()
        )
        let medicalCard = SettingsCard(content: makeWindowLevelPanel())

        return featurePageContent([basicCard, medicalCard])
    }

    private func makeBasicDemoPanel() -> WinUI.StackPanel {
        let readout = TextBlock()
        readout.minWidth = 80
        readout.verticalAlignment = .center

        let slider = RangeSlider(
            minimum: 0, maximum: 100, lowerValue: 20, upperValue: 80, stepFrequency: 1)
        slider.width = 220
        slider.valueChanged.addHandler { _, change in
            readout.text = String(format: "%.0f – %.0f", change.new.lowerBound, change.new.upperBound)
        }
        readout.text = "20 - 80"

        let panel = StackPanel()
        panel.orientation = .horizontal
        panel.spacing = 12
        panel.children.append(slider)
        panel.children.append(readout)

        let toolTipToggle = ToggleSwitch()
        toolTipToggle.header = tr("Show tooltip")
        toolTipToggle.isOn = slider.isToolTipEnabled
        toolTipToggle.toggled.addHandler { _, _ in
            slider.isToolTipEnabled = toolTipToggle.isOn
        }

        let wrap = StackPanel()
        wrap.orientation = .vertical
        wrap.spacing = 8
        wrap.children.append(panel)
        wrap.children.append(toolTipToggle)
        return wrap
    }

    /// 窗宽/窗位演示：CT 的 HU 值域 [-1024, 3071]，默认软组织窗（W400 / L40）。
    private func makeWindowLevelPanel() -> WinUI.StackPanel {
        let huMin = -1024.0
        let huMax = 3071.0

        let subtitle = TextBlock()
        subtitle.text = tr(
            "Medical imaging maps the selected HU range to grayscale: Window Width = upper − lower, Window Level = (upper + lower) / 2. The bar previews the mapping. Drag between the thumbs to pan the level keeping the width."
        )
        subtitle.fontSize = 12
        subtitle.textWrapping = .wrap
        subtitle.foreground = SolidColorBrush(
            App.context.theme.isDark
                ? Color(a: 255, r: 174, g: 178, b: 190)
                : Color(a: 255, r: 96, g: 104, b: 112))

        let wwLabel = TextBlock()
        let wlLabel = TextBlock()
        let lowerHU = TextBlock()
        let upperHU = TextBlock()

        let slider = RangeSlider(
            minimum: huMin, maximum: huMax,
            lowerValue: -160, upperValue: 240,
            stepFrequency: 1, minGap: 1)

        // 灰阶预览：选区内黑→白线性过渡，区间外裁剪为纯黑/纯白。
        let black = Color(a: 255, r: 0, g: 0, b: 0)
        let white = Color(a: 255, r: 255, g: 255, b: 255)
        let blackAtLower = GradientStop()
        blackAtLower.color = black
        let whiteAtUpper = GradientStop()
        whiteAtUpper.color = white
        let whiteToEnd = GradientStop()
        whiteToEnd.color = white
        whiteToEnd.offset = 1

        let stops = GradientStopCollection()
        stops.append(blackAtLower)
        stops.append(whiteAtUpper)
        stops.append(whiteToEnd)
        let brush = LinearGradientBrush()
        brush.startPoint = Point(x: 0, y: 0)
        brush.endPoint = Point(x: 1, y: 0)
        brush.gradientStops = stops

        let bar = Border()
        bar.height = 12
        bar.cornerRadius = CornerRadius(topLeft: 2, topRight: 2, bottomRight: 2, bottomLeft: 2)
        bar.background = brush

        func update(_ range: ClosedRange<Double>) {
            let width = range.upperBound - range.lowerBound
            let level = (range.upperBound + range.lowerBound) / 2
            wwLabel.text = String(format: "%@: %.0f", tr("Window Width (WW)"), width)
            wlLabel.text = String(format: "%@: %.0f", tr("Window Level (WL)"), level)
            lowerHU.text = String(format: "%.0f HU", range.lowerBound)
            upperHU.text = String(format: "%.0f HU", range.upperBound)

            let span = huMax - huMin
            blackAtLower.offset = (range.lowerBound - huMin) / span
            whiteAtUpper.offset = (range.upperBound - huMin) / span
        }
        slider.valueChanged.addHandler { _, change in update(change.new) }
        update(slider.range)

        let labelsRow = StackPanel()
        labelsRow.orientation = .horizontal
        labelsRow.spacing = 24
        labelsRow.children.append(wwLabel)
        labelsRow.children.append(wlLabel)

        let leftColumn = ColumnDefinition()
        leftColumn.width = GridLength(value: 1, gridUnitType: .star)
        let rightColumn = ColumnDefinition()
        rightColumn.width = GridLength(value: 1, gridUnitType: .star)
        let huRow = Grid()
        huRow.columnDefinitions.append(leftColumn)
        huRow.columnDefinitions.append(rightColumn)
        lowerHU.horizontalAlignment = .left
        huRow.children.append(lowerHU)
        try? Grid.setColumn(lowerHU, 0)
        upperHU.horizontalAlignment = .right
        huRow.children.append(upperHU)
        try? Grid.setColumn(upperHU, 1)

        let panel = StackPanel()
        panel.orientation = .vertical
        panel.spacing = 12
        panel.width = 320
        panel.children.append(makeSectionTitle(tr("Window / Level (CT)")))
        panel.children.append(subtitle)
        panel.children.append(slider)
        panel.children.append(bar)
        panel.children.append(labelsRow)
        panel.children.append(huRow)
        return panel
    }

    private func makeSectionTitle(_ text: String) -> TextBlock {
        let title = TextBlock()
        title.text = text
        title.fontSize = 14
        return title
    }
}
