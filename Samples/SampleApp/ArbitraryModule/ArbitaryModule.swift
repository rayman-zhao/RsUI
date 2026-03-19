import Foundation
import WindowsFoundation
import UWP
import WinUI
import RsUI
import RsHelper

fileprivate func tr(_ keyAndValue: String) -> String {
    return App.context.language == .zh_CN ? "翻译\(keyAndValue)" : keyAndValue
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
        textBlock.text = tr("Arbitrary")
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

    func makeNavigationTarget(for selectedItemTag: Any, in context: WindowContext) -> (header: UIElement?, page: View)? {
        guard let tag = selectedItemTag as? Uri, tag.host == self.id else { return nil }

        let container = StackPanel()
        container.padding = Thickness(left: 0, top: 0, right: 0, bottom: 32)
        
        // 欢迎标题
        let titleBlock = TextBlock()
        titleBlock.text = tr("Arbitrary Page")
        container.children.append(titleBlock)
        
        // 副标题
        let subtitleBlock = TextBlock()
        subtitleBlock.text = tr("A demonstration page with various UI components")
        subtitleBlock.fontSize = 14
        subtitleBlock.foreground = SolidColorBrush(App.context.theme.isDark ? 
            UWP.Color(a: 255, r: 180, g: 180, b: 180) : 
            UWP.Color(a: 255, r: 100, g: 100, b: 100))
        container.children.append(subtitleBlock)

        return (container, ArbitaryPage())
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
