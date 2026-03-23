import Foundation
import Observation
import WindowsFoundation
import WinAppSDK
import WinUI

public extension NavigationViewItem {
    func startObserving<Element>(_ emit: @escaping @Sendable () -> Element, onChanged: @escaping @MainActor (NavigationViewItem, Element) -> Void) {
        let obs = Observations(emit)

        Task { [weak self] in
            for await value in obs {
                guard let self else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    onChanged(self, value)
                }
            }
        }
    }

    static func build(iconGlyph: String, label: String, url: String) -> NavigationViewItem {
        let icon = FontIcon()
        icon.glyph = iconGlyph

        let item = NavigationViewItem()
        item.icon = icon
        item.content = label
        item.tag = Uri(url)
        return item
    }

    static func build(iconGlyph: String, label: String, url: String, actionGlyph: String, actionTooltip: String, actionHandler: @escaping ((Optional<Any>, Optional<RoutedEventArgs>) throws -> ())) -> NavigationViewItem {
        let icon = FontIcon()
        icon.glyph = iconGlyph

        let grid = Grid()
        grid.horizontalAlignment = .stretch
        grid.verticalAlignment = .center
        
        // 定义列：标签(填充) | 动作按钮(自动)
        let textCol = ColumnDefinition()
        textCol.width = GridLength(value: 1, gridUnitType: .star)
        grid.columnDefinitions.append(textCol)

        let actionCol = ColumnDefinition()
        actionCol.width = GridLength(value: 0, gridUnitType: .auto)
        grid.columnDefinitions.append(actionCol)

        // 1. 标签
        let textBlock = TextBlock()
        textBlock.text = label
        try? Grid.setColumn(textBlock, 0)
        grid.children.append(textBlock)

        // 2. 动作按钮
        let actionButton = Button()
        actionButton.background = SolidColorBrush(Colors.transparent)
        actionButton.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        actionButton.padding = Thickness(left: 4, top: 4, right: 4, bottom: 4)
        actionButton.verticalAlignment = .center
        actionButton.horizontalAlignment = .center
        actionButton.width = 32
        actionButton.height = 32
        actionButton.cornerRadius = CornerRadius(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)

        let actionIcon = FontIcon()
        actionIcon.glyph = actionGlyph
        actionIcon.fontSize = 16
        actionButton.content = actionIcon

        // 设置提示文字
        try? ToolTipService.setToolTip(actionButton, actionTooltip)
        actionButton.click.addHandler(actionHandler)

        try? Grid.setColumn(actionButton, 1)
        grid.children.append(actionButton)

        let item = NavigationViewItem()
        item.icon = icon
        item.content = grid
        item.tag = Uri(url)
        return item
    }
}
