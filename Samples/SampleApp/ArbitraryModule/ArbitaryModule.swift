import Foundation
import Observation
import WindowsFoundation
import UWP
import WinUI
import RsUI
import RsHelper

func tr(_ keyAndValue: String) -> String {
    return App.context.language == .zh_CN ? "翻译\(keyAndValue)" : keyAndValue
}

@Observable
final class ArbitaryModule: Module {
    let id = "arbitrary"
    var state = "loading"

    init() {
        log.info("ArbitaryModule init")
    }
    deinit {
        log.info("ArbitaryModule deinit")
    }

    func titleBarRightHeaderItemRequired(in context: WindowContext) -> UIElement? {
        let ring = ProgressRingEx()
        ring.startObserving { [weak self] in
            self?.state
        } onChanged: { ring, value in
            ring.isActive = value == "loading"
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.state = ""
        }

        return ring
    }

    func navigationViewMenuItemsRequired(in context: WindowContext) -> [NavigationViewItemBase] {
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

    func navigationViewFooterMenuItemsRequired(in context: WindowContext) -> [NavigationViewItemBase] {
        let header = NavigationViewItemHeader()
        header.content = tr("Footer")
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
        return [sep, header, navigationViewItem]
    }

    func settingsGroupRequired() -> (title: String, cards: [UIElement])? {
        let toggle = ToggleSwitch()
        toggle.isOn = true
        toggle.onContent = tr("On")
        toggle.offContent = tr("Off")
        let basicCard = SettingsCard(
            headerIconGlyph: "\u{E946}",
            header: tr("Basic SettingsCard"),
            description: tr("Header icon + description + right-side control. The minimal Fluent-style settings row."),
            content: toggle
        )

        let clickableCard = SettingsCard(
            headerIconGlyph: "\u{E710}",
            header: tr("Clickable SettingsCard"),
            description: tr("Set isClickEnabled = true to turn the whole row into a button. Logs on click.")
        )
        clickableCard.isClickEnabled = true
        clickableCard.click.addHandler { _, _ in
            log.info("Clickable settings card tapped")
        }

        let childA = SettingsCard(
            headerIconGlyph: "\u{E712}",
            header: tr("Nested item A"),
            description: tr("Child rows live inside the expander's animated panel.")
        )
        let childB = SettingsCard(
            headerIconGlyph: "\u{E712}",
            header: tr("Nested item B"),
            description: tr("Use itemsHeader / itemsFooter for static content around the list.")
        )
        let expander = SettingsExpander(
            headerIconGlyph: "\u{E7C3}",
            header: tr("SettingsExpander"),
            description: tr("Click to reveal child SettingsCard items with the WCTK animation.")
        )
        expander.itemsSource = [childA, childB]

        return (tr("Settings Controls Demo"), [basicCard, clickableCard, expander])
    }

    func navigationRequested(for url: URL, in context: WindowContext) -> RsUI.Page? {
        guard url.host == self.id else { return nil }
        return ArbitaryPage(context: context)
    }
}
