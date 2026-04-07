import WindowsFoundation
import UWP
import WinAppSDK
import WinUI

public class SettingsCard: Button {
    public var isClickEnabled = false

    private override init() {
        super.init()

        self.horizontalAlignment = .stretch
        self.verticalAlignment = .stretch
        self.horizontalContentAlignment = .stretch
        self.verticalContentAlignment = .stretch
        self.padding = WinUI.Thickness(left: 10, top: 10, right: 10, bottom: 10)
    }

    public convenience init(_ headerIconGlyph: String, _ header: String, _ description: String, _ content: FrameworkElement, _ actionIcon: FontIcon? = nil) {
        self.init()

        let icon = WinUI.FontIcon()
        icon.glyph = headerIconGlyph
        let textBlock = TextBlock()
        textBlock.text = description

        self.content = build(
            headerIcon: icon,
            header: header,
            description: textBlock,
            content: content,
            actionIcon: actionIcon
        )
    }

    public convenience init(_ headerIconPath: String, _ header: String, _ description: String, _ content: String, _ actionIcon: FontIcon) {
        self.init()

        let bitmap = BitmapImage()
        bitmap.uriSource = Uri(headerIconPath)
        let icon = ImageIcon()
        icon.source = bitmap
        let descTextBlock = TextBlock()
        descTextBlock.text = description
        let contentTextBlock = TextBlock()
        contentTextBlock.text = content

        self.content = build(
            headerIcon: icon,
            header: header,
            description: descTextBlock,
            content: contentTextBlock,
            actionIcon: actionIcon
        )
    }

    public convenience init(_ header: String, _ description: FrameworkElement) {
        self.init()

        self.content = build(
            header: header,
            description: description
        )
    }

    private func build(headerIcon: IconElement? = nil, header: String, description: FrameworkElement, content: FrameworkElement? = nil, actionIcon: FontIcon? = nil) -> WinUI.Grid {
        let isDark = App.context.theme.isDark
        let secondaryForeground = WinUI.SolidColorBrush(isDark
            ? UWP.Color(a: 255, r: 169, g: 173, b: 189)
            : UWP.Color(a: 255, r: 96, g: 104, b: 112))

        let container = WinUI.Grid()

        let iconColumn = WinUI.ColumnDefinition()
        iconColumn.width = WinUI.GridLength(value: 40, gridUnitType: .pixel)
        container.columnDefinitions.append(iconColumn)

        let textColumn = WinUI.ColumnDefinition()
        textColumn.width = WinUI.GridLength(value: 1, gridUnitType: .star)
        container.columnDefinitions.append(textColumn)

        let controlColumn = WinUI.ColumnDefinition()
        controlColumn.width = WinUI.GridLength(value: 1, gridUnitType: .auto)
        container.columnDefinitions.append(controlColumn)

        let actionIconColumn = WinUI.ColumnDefinition()
        actionIconColumn.width = WinUI.GridLength(value: 1, gridUnitType: .auto)
        container.columnDefinitions.append(actionIconColumn)

        let titleRow = WinUI.RowDefinition()
        titleRow.height = WinUI.GridLength(value: 1, gridUnitType: .auto)
        container.rowDefinitions.append(titleRow)

        let descRow = WinUI.RowDefinition()
        descRow.height = WinUI.GridLength(value: 1, gridUnitType: .auto)
        container.rowDefinitions.append(descRow)

        if let icon = headerIcon {
            if let fontIcon = icon as? WinUI.FontIcon {
                fontIcon.fontSize = 20
            } else if let imageIcon = icon as? ImageIcon {
                imageIcon.width = 24
                imageIcon.height = 24
            }

            container.children.append(icon)
            try? WinUI.Grid.setRow(icon, 0)
            try? WinUI.Grid.setColumn(icon, 0)
            try? WinUI.Grid.setRowSpan(icon, 2)
        }

        let titleLabel = WinUI.TextBlock()
        titleLabel.text = header
        titleLabel.fontSize = 14
        titleLabel.margin = WinUI.Thickness(left: 16, top: 0, right: 0, bottom: 2)
        container.children.append(titleLabel)
        try? WinUI.Grid.setRow(titleLabel, 0)
        try? WinUI.Grid.setColumn(titleLabel, 1)

        if let description = description as? TextBlock {
            description.foreground = secondaryForeground
            description.fontSize = 12
            description.margin = WinUI.Thickness(left: 16, top: 0, right: 0, bottom: 0)
            description.textWrapping = .wrap
        } else {
            description.margin = Thickness(left: 4, top: 0, right: 0, bottom: 0)
        }
        container.children.append(description)
        try? WinUI.Grid.setRow(description, 1)
        try? WinUI.Grid.setColumn(description, 1)

        if let content {
            content.verticalAlignment = .center
            container.children.append(content)
            try? WinUI.Grid.setRow(content, 0)
            try? WinUI.Grid.setColumn(content, 2)
            try? WinUI.Grid.setRowSpan(content, 2)
        }

        if let actionIcon = actionIcon {
            actionIcon.fontSize = 16
            actionIcon.margin = WinUI.Thickness(left: 16, top: 0, right: 8, bottom: 0)
            container.children.append(actionIcon)
            try? WinUI.Grid.setRow(actionIcon, 0)
            try? WinUI.Grid.setColumn(actionIcon, 3)
            try? WinUI.Grid.setRowSpan(actionIcon, 2)
        }

        return container
    }
}
