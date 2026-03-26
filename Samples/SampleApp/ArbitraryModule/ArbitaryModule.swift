import Foundation
import WindowsFoundation
import UWP
import WinUI
import RsUI
import RsHelper

func tr(_ keyAndValue: String) -> String {
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

    func registerNavigationViewItems(in context: WindowContext) -> [NavigationViewItemBase] {
        let header = NavigationViewItemHeader()
        header.content = tr("Header")
        let navigationViewItem = NavigationViewItem.build(
            iconGlyph: "\u{E7C3}",
            label: tr("Arbitrary"),
            url: "rs://\(id)",
            actionGlyph: "\u{E8F4}",
            actionTooltip: tr("actionTooltip"),
            actionHandler: { _, _ in
                context.pickFolder {
                    print($0)
                }
            }
        )
        let sep = NavigationViewItemSeparator()
        return [header, navigationViewItem, sep]
    }

    func navigationRequested(for url: URL, in context: WindowContext) -> RsUI.Page? {
        guard url.host == self.id else { return nil }
        return ArbitaryPage()
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
