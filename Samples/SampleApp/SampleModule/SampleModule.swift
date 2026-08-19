import Foundation
import Observation
import RsFoundation
import RsUI
import UWP
import WinUI
import WindowsFoundation

func tr(_ keyAndValue: String) -> String {
    let text = App.context.tr(keyAndValue)
    return (text == keyAndValue && App.context.language == .zh_CN) ? "待翻译（\(keyAndValue)）" : text
}

@Observable
final class SampleModule: Module {
    let id = "sample"
    var state = "loading"

    init() {
        log.info("SampleModule init")
    }
    deinit {
        log.info("SampleModule deinit")
    }

    func titleBarRightHeaderItem(in context: WindowContext) -> UIElement? {
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

    func navigationViewMenuItems(in context: WindowContext) -> [NavigationViewItemBase] {
        let header = NavigationViewItemHeader()
        header.content = tr("Samples")

        let items: [NavigationViewItemBase] = [
            header,
            NavigationViewItem.build(
                iconGlyph: "\u{E80F}", label: tr("Overview"), url: "rs://\(id)"),
            NavigationViewItem.build(
                iconGlyph: "\u{E740}", label: tr("Fullscreen"), url: "rs://\(id)/fullscreen"),
            NavigationViewItem.build(
                iconGlyph: "\u{ECCD}", label: tr("Navigation Modes"), url: "rs://\(id)/navigation"),
            NavigationViewItem.build(
                iconGlyph: "\u{E8A7}", label: tr("Open or Focus"), url: "rs://\(id)/openorfocus"),
            NavigationViewItem.build(
                iconGlyph: "\u{E8FD}", label: tr("Batch Open"), url: "rs://\(id)/batch-open"),
            NavigationViewItem.build(
                iconGlyph: "\u{E78B}", label: tr("New Window"), url: "rs://\(id)/new-window"),
            NavigationViewItem.build(
                iconGlyph: "\u{E771}", label: tr("Appearance"), url: "rs://\(id)/appearance"),
            NavigationViewItem.build(
                iconGlyph: "\u{E8B7}", label: tr("Picker"), url: "rs://\(id)/picker"),
            NavigationViewItem.build(
                iconGlyph: "\u{E91B}", label: tr("Viewer"), url: "rs://\(id)/viewer"),
        ]
        return items
    }

    func navigationViewFooterMenuItems(in context: WindowContext) -> [NavigationViewItemBase] {
        let header = NavigationViewItemHeader()
        header.content = tr("Footer")
        let pickerItem = NavigationViewItem.build(
            iconGlyph: "\u{E8B7}",
            label: tr("Folder Picker"),
            url: "rs://\(id)/footer-picker",
            actionGlyph: "\u{E8F4}",
            actionTooltip: tr("Pick a folder right from the nav"),
            actionHandler: { _, _ in
                context.pickFolder {
                    print($0)
                }
            }
        )
        return [NavigationViewItemSeparator(), header, pickerItem]
    }

    func settingsGroup() -> (title: String, cards: [UIElement])? {
        let toggle = ToggleSwitch()
        toggle.isOn = true
        toggle.onContent = tr("On")
        toggle.offContent = tr("Off")
        let basicCard = SettingsCard(
            headerIconGlyph: "\u{E946}",
            header: tr("Basic SettingsCard"),
            description: tr(
                "Header icon + description + right-side control. The minimal Fluent-style settings row."
            ),
            content: toggle
        )

        let clickableCard = SettingsCard(
            headerIconGlyph: "\u{E710}",
            header: tr("Clickable SettingsCard"),
            description: tr(
                "Set isClickEnabled = true to turn the whole row into a button. Logs on click.")
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

    func navigationDidRequest(for url: URL, in context: WindowContext) -> RsUI.Page? {
        guard url.host == self.id else { return nil }
        switch url.path {
        case "", "/":
            return OverviewPage(context: context)
        case "/fullscreen":
            return FullscreenPage(context: context)
        case "/navigation":
            return NavigationModesPage(context: context)
        case "/openorfocus":
            return OpenOrFocusPage(context: context)
        case "/batch-open":
            return BatchOpenPage(context: context)
        case "/new-window":
            return NewWindowPage(context: context)
        case "/appearance":
            return AppearancePage(context: context)
        case "/picker":
            return PickerPage(context: context)
        case "/viewer":
            return ViewerPage(context: context)
        case "/footer-picker":
            return FolderPickerPage(context: context, path: url.path)
        default:
            return nil
        }
    }
}
