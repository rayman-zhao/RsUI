import Foundation
import UWP
import WinUI
import RsUI
import RsHelper

fileprivate func tr(_ keyAndValue: String) -> String {
    return App.context.tr(keyAndValue, "SettingsPage")
}

final class ArbitaryModule: Module {
    let id = "arbitrary"
    
    init() {
        log.info("ArbitaryModule init")
    }
    deinit {
        log.info("ArbitaryModule deinit")
    }
    
    func initialize(context: WindowContext) {
        let items = makeNavigationViewItems()
        for item in items {
            context.registerNavigation(node: .leaf(
                id: "arbitrary",
                labelKey: "arbitrary_module_title",
                literalLabel: "Arbitrary",
                pageFactory: { ArbitaryPage(context: $0) },
                createNavigationViewItem: {
                    // 初始化在注册模块的时候调用，要求完成创建NavigationViewItem
                    return item
                },
                useCustomItem: true
            ))
        }
    }

    func makeNavigationViewItems() -> [NavigationViewItem] {
        return [makeNavItemContent()]
    }

    func makeSettingsSection() -> UIElement? {
        let toggle = WinUI.ToggleSwitch()
        toggle.isOn = true
        toggle.onContent = tr("toggleOn")
        toggle.offContent = tr("toggleOff")

        let metadataRow = buildSettingsRow(
                iconGlyph: "\u{E70A}",
                title: tr("metadataTitle"),
                description: tr("metadataDescription"),
                control: toggle
            )

        return buildSettingsCard(title: "Arbitrary Settings", content: [metadataRow])
    }

    /// 根据节点生成可复用的内容视图（含动作按钮和图标）
    private func makeNavItemContent() -> NavigationViewItem {
        let navigationViewItem = NavigationViewItem()
        let grid = Grid()
        grid.horizontalAlignment = .stretch
        grid.verticalAlignment = .center
        
        // 定义列：标签(填充) | 动作按钮(自动)
        let textCol = ColumnDefinition()
        textCol.width = GridLength(value: 1, gridUnitType: .star)
        grid.columnDefinitions.append(textCol)

        let textBlock = TextBlock()
        textBlock.text = "Arbitrary"
        textBlock.verticalAlignment = .center
        textBlock.horizontalAlignment = .left
        textBlock.textTrimming = .characterEllipsis
        try? Grid.setColumn(textBlock, 0)
        grid.children.append(textBlock)

        navigationViewItem.content = grid
        let icon = FontIcon()
        icon.glyph = "\u{E7C3}"
        icon.fontSize = 16
        navigationViewItem.icon = icon

        return navigationViewItem
    }
}
