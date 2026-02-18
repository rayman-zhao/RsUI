import UWP
import WinUI

public func buildSettingsRow(iconGlyph: String, title: String, description: String, control: WinUI.UIElement) -> WinUI.Grid {
    let isDark = App.context.theme.isDark
    // let titleForeground = WinUI.SolidColorBrush(isDark``
    //         ? UWP.Color(a: 255, r: 232, g: 234, b: 242)
    //         : UWP.Color(a: 255, r: 23, g: 26, b: 32))
    let secondaryForeground = WinUI.SolidColorBrush(isDark
            ? UWP.Color(a: 255, r: 169, g: 173, b: 189)
            : UWP.Color(a: 255, r: 96, g: 104, b: 112))
    let accentColor = UWP.Color(a: 255, r: 90, g: 104, b: 255)

    let container = WinUI.Grid()

    let iconColumn = WinUI.ColumnDefinition()
    iconColumn.width = WinUI.GridLength(value: 56, gridUnitType: .auto)
    container.columnDefinitions.append(iconColumn)

    let textColumn = WinUI.ColumnDefinition()
    textColumn.width = WinUI.GridLength(value: 1, gridUnitType: .star)
    container.columnDefinitions.append(textColumn)

    let controlColumn = WinUI.ColumnDefinition()
    controlColumn.width = WinUI.GridLength(value: 1, gridUnitType: .auto)
    container.columnDefinitions.append(controlColumn)

    let titleRow = WinUI.RowDefinition()
    titleRow.height = WinUI.GridLength(value: 1, gridUnitType: .auto)
    container.rowDefinitions.append(titleRow)

    let descRow = WinUI.RowDefinition()
    descRow.height = WinUI.GridLength(value: 1, gridUnitType: .auto)
    container.rowDefinitions.append(descRow)

    let iconBadge = WinUI.Border()
    iconBadge.width = 44
    iconBadge.height = 44
    iconBadge.cornerRadius = WinUI.CornerRadius(topLeft: 14, topRight: 14, bottomRight: 14, bottomLeft: 14)
    iconBadge.background = WinUI.SolidColorBrush(accentColor)
    iconBadge.verticalAlignment = .center
    iconBadge.horizontalAlignment = .center

    let icon = WinUI.FontIcon()
    icon.glyph = iconGlyph
    icon.fontSize = 20
    icon.foreground = WinUI.SolidColorBrush(UWP.Color(a: 255, r: 255, g: 255, b: 255))
    iconBadge.child = icon

    container.children.append(iconBadge)
    try? WinUI.Grid.setRow(iconBadge, 0)
    try? WinUI.Grid.setColumn(iconBadge, 0)
    try? WinUI.Grid.setRowSpan(iconBadge, 2)

    let titleLabel = WinUI.TextBlock()
    titleLabel.text = title
    //titleLabel.foreground = titleForeground
    titleLabel.fontSize = 16
    titleLabel.fontWeight = UWP.FontWeights.semiBold
    titleLabel.margin = WinUI.Thickness(left: 16, top: 2, right: 12, bottom: 4)
    container.children.append(titleLabel)
    try? WinUI.Grid.setRow(titleLabel, 0)
    try? WinUI.Grid.setColumn(titleLabel, 1)

    let descriptionLabel = WinUI.TextBlock()
    descriptionLabel.text = description
    descriptionLabel.foreground = secondaryForeground
    descriptionLabel.fontSize = 13
    descriptionLabel.margin = WinUI.Thickness(left: 16, top: 0, right: 12, bottom: 0)
    descriptionLabel.textWrapping = .wrap
    container.children.append(descriptionLabel)
    try? WinUI.Grid.setRow(descriptionLabel, 1)
    try? WinUI.Grid.setColumn(descriptionLabel, 1)

    let controlHost = WinUI.StackPanel()
    controlHost.orientation = .horizontal
    controlHost.verticalAlignment = .center
    controlHost.spacing = 8
    controlHost.children.append(control)
    container.children.append(controlHost)
    try? WinUI.Grid.setRow(controlHost, 0)
    try? WinUI.Grid.setColumn(controlHost, 2)
    try? WinUI.Grid.setRowSpan(controlHost, 2)

    return container
}
