import Foundation
import UWP
import WinUI

/// 主窗口底部状态栏组件，负责渲染状态文本和右键显示控制菜单。
final class StatusBar {
    let root = WinUI.Border()

    private let service: StatusBarService
    private let tr: (String) -> String
    private let isBarVisible: () -> Bool
    private let setBarVisible: (Bool) -> Void

    private let contentGrid = WinUI.Grid()
    private let leftText = WinUI.TextBlock()
    private let centerText = WinUI.TextBlock()
    private let rightText = WinUI.TextBlock()

    init(
        service: StatusBarService,
        tr: @escaping (String) -> String,
        isBarVisible: @escaping () -> Bool,
        setBarVisible: @escaping (Bool) -> Void
    ) {
        self.service = service
        self.tr = tr
        self.isBarVisible = isBarVisible
        self.setBarVisible = setBarVisible

        buildLayout()
    }

    func render() {
        leftText.text = service.text(for: .left, fallback: "Ready")
        centerText.text = service.text(for: .center, fallback: "Status")
        rightText.text = service.text(for: .right, fallback: "Logs \(service.logs.count)")
        rebuildContextMenu()
    }

    func applyTheme(_ theme: AppTheme) {
        let bg = theme.isDark
            ? UWP.Color(a: 204, r: 23, g: 27, b: 33)
            : UWP.Color(a: 214, r: 248, g: 249, b: 251)
        let divider = theme.isDark
            ? UWP.Color(a: 255, r: 50, g: 56, b: 68)
            : UWP.Color(a: 255, r: 220, g: 224, b: 230)
        let primary = theme.isDark
            ? UWP.Color(a: 255, r: 226, g: 232, b: 241)
            : UWP.Color(a: 255, r: 49, g: 57, b: 72)
        let secondary = theme.isDark
            ? UWP.Color(a: 255, r: 168, g: 176, b: 191)
            : UWP.Color(a: 255, r: 106, g: 114, b: 128)

        root.background = WinUI.SolidColorBrush(bg)
        root.borderBrush = WinUI.SolidColorBrush(divider)
        root.borderThickness = WinUI.Thickness(left: 0, top: 1, right: 0, bottom: 0)

        leftText.foreground = WinUI.SolidColorBrush(primary)
        centerText.foreground = WinUI.SolidColorBrush(secondary)
        rightText.foreground = WinUI.SolidColorBrush(secondary)
    }

    private func buildLayout() {
        root.height = 30
        root.verticalAlignment = .bottom
        root.padding = WinUI.Thickness(left: 14, top: 0, right: 14, bottom: 0)
        root.isHoldingEnabled = true

        let colLeft = WinUI.ColumnDefinition()
        colLeft.width = WinUI.GridLength(value: 0, gridUnitType: .auto)
        let colCenter = WinUI.ColumnDefinition()
        colCenter.width = WinUI.GridLength(value: 1, gridUnitType: .star)
        let colRight = WinUI.ColumnDefinition()
        colRight.width = WinUI.GridLength(value: 0, gridUnitType: .auto)
        contentGrid.columnDefinitions.append(colLeft)
        contentGrid.columnDefinitions.append(colCenter)
        contentGrid.columnDefinitions.append(colRight)

        configure(text: leftText, alignment: .left, opacity: 1)
        configure(text: centerText, alignment: .center, opacity: 0.78)
        configure(text: rightText, alignment: .right, opacity: 0.88)

        contentGrid.children.append(leftText)
        contentGrid.children.append(centerText)
        contentGrid.children.append(rightText)
        try? WinUI.Grid.setColumn(leftText, 0)
        try? WinUI.Grid.setColumn(centerText, 1)
        try? WinUI.Grid.setColumn(rightText, 2)

        root.child = contentGrid
    }

    private func configure(text block: WinUI.TextBlock, alignment: WinUI.HorizontalAlignment, opacity: Double) {
        block.fontSize = 11
        block.verticalAlignment = .center
        block.horizontalAlignment = alignment
        block.opacity = opacity
        block.textTrimming = .characterEllipsis
    }

    private func rebuildContextMenu() {
        let menu = WinUI.MenuFlyout()

        let showBarItem = WinUI.ToggleMenuFlyoutItem()
        showBarItem.text = tr("statusBarTitle")
        showBarItem.isChecked = isBarVisible()
        showBarItem.click.addHandler { _, _ in
            self.setBarVisible(showBarItem.isChecked)
        }
        menu.items.append(showBarItem)

        if !service.availableDescriptors().isEmpty {
            menu.items.append(WinUI.MenuFlyoutSeparator())
        }

        for descriptor in service.availableDescriptors() {
            let item = WinUI.ToggleMenuFlyoutItem()
            item.text = descriptor.title
            item.isChecked = service.isVisible(id: descriptor.id)
            item.click.addHandler { _, _ in
                self.service.setVisibility(id: descriptor.id, isVisible: item.isChecked)
            }
            menu.items.append(item)
        }

        root.contextFlyout = menu
    }
}
