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

/// 模块 id 的唯一来源：页面 URL 与导航项统一用它拼 `rs://` 路由。
let sampleModuleID = "sample"

@Observable
final class SampleModule: Module {
    let id = sampleModuleID
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
            return true
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

        // Action-icon demos: the glyph is hidden until the row is hovered (or focused) and
        // reveals itself like the TabView close button. Each one exercises a different
        // action surface: theme toggle, new window, and batch tab opening.
        let newWindowActionURL = URL(string: "rs://\(id)/new-window")!
        let batchActionURLs: [URL] = [
            URL(string: "rs://\(id)")!,
            URL(string: "rs://\(id)/navigation")!,
            URL(string: "rs://\(id)/openorfocus")!,
        ]

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
            NavigationViewItemWithAction(
                iconGlyph: "\u{E8FD}", label: tr("Batch Open"), url: "rs://\(id)/batch-open",
                actionGlyph: "\u{E710}",
                actionTooltip: tr("Open three sample pages as tabs"),
                actionHandler: { _, _ in
                    _ = context.open(batchActionURLs, mode: .newTab)
                }
            ),
            NavigationViewItemWithAction(
                iconGlyph: "\u{E78B}", label: tr("New Window"), url: "rs://\(id)/new-window",
                actionGlyph: "\u{E8F4}",
                actionTooltip: tr("Open this page in a new window"),
                actionHandler: { _, _ in
                    App.context.openNewWindow(with: [newWindowActionURL])
                }
            ),
            NavigationViewItemWithAction(
                iconGlyph: "\u{E771}", label: tr("Appearance"), url: "rs://\(id)/appearance",
                actionGlyph: "\u{E706}",
                actionTooltip: tr("Toggle light / dark theme"),
                actionHandler: { _, _ in
                    App.context.theme = App.context.theme == .dark ? .light : .dark
                }
            ),
            NavigationViewItem.build(
                iconGlyph: "\u{E8B7}", label: tr("Picker"), url: "rs://\(id)/picker"),
            NavigationViewItem.build(
                iconGlyph: "\u{E838}", label: tr("Reveal in File Explorer"),
                url: "rs://\(id)/reveal"),
            NavigationViewItem.build(
                iconGlyph: "\u{E91B}", label: tr("Viewer"), url: "rs://\(id)/viewer"),
            NavigationViewItem.build(
                iconGlyph: "\u{E946}", label: tr("Range Slider"), url: "rs://\(id)/range-slider"),
            NavigationViewItem.build(
                iconGlyph: "\u{E71D}", label: tr("Grid View"), url: "rs://\(id)/grid-view"),
            itemsViewNavItem(id: id),
            NavigationViewItem.build(
                iconGlyph: "\u{E73E}", label: tr("Toggle Buttons"), url: "rs://\(id)/toggle-buttons"),
        ]
        return items
    }

    /// “条目视图”导航项：交互演示页 + 文档页作为嵌套子项。
    private func itemsViewNavItem(id: String) -> NavigationViewItemBase {
        let item = NavigationViewItem.build(
            iconGlyph: "\u{E8E5}", label: tr("Items View"), url: "rs://\(id)/items-view")
        item.menuItems.append(
            NavigationViewItem.build(
                iconGlyph: "\u{E70F}", label: tr("Documentation"), url: "rs://\(id)/items-view-doc"))
        return item
    }

    func navigationViewFooterMenuItems(in context: WindowContext) -> [NavigationViewItemBase] {
        let header = NavigationViewItemHeader()
        header.content = tr("Footer")
        let pickerItem = NavigationViewItemWithAction(
            iconGlyph: "\u{E8B7}",
            label: tr("Folder Picker"),
            url: "rs://\(id)/footer-picker",
            actionGlyph: "\u{E8B7}",
            actionTooltip: tr("Pick a folder right from the nav"),
            actionHandler: { _, _ in
                context.pickFolder { path in
                    log.info("picked folder: \(String(describing: path))")
                }
            }
        )
        return [NavigationViewItemSeparator(), header, pickerItem]
    }

    func settingsGroup() -> SettingsGroup? {
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

        return SettingsGroup(title: tr("Settings Controls Demo"), cards: [basicCard, clickableCard, expander])
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
        case "/reveal":
            return RevealPage()
        case "/viewer":
            return ViewerPage(context: context)
        case "/range-slider":
            return RangeSliderPage()
        case "/grid-view":
            return GridViewPage()
        case "/items-view":
            return ItemsViewPage()
        case "/items-view-doc":
            return ItemsViewDocumentationPage()
        case "/toggle-buttons":
            return ToggleButtonsPage()
        case "/footer-picker":
            return PickerPage(context: context, path: url.path)
        default:
            return nil
        }
    }
}
