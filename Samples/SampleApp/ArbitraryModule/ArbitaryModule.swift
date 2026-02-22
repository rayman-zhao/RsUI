import Foundation
import WindowsFoundation
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

    func registerNavigationViewItems(in context: WindowContext) -> [NavigationViewItem] {
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

        navigationViewItem.tag = Uri("rs://\(id)")

        return [navigationViewItem]
    }

    func makeNavigationTarget(for selectedItemTag: Any) -> (header: String, page: AppPage)? {
        guard let tag = selectedItemTag as? Uri, tag.host == self.id else { return nil }
        return ("Arbitrary Page", ArbitaryPage())
    }

    func makeSettingsCard() -> UIElement? {
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
}
