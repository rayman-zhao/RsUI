import Foundation
import UWP
import WinUI
import RsUI

/// 演示页面，按 section 分块展示 RsUI 暴露给 module 的核心能力。
/// 每个 SettingsGroup 对应一个能力点，便于手动 smoke test。
final class ArbitaryPage: RsUI.Page {
    let context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    var url: URL {
        return URL(string: "rs://arbitrary")!
    }

    var title: String { tr("Arbitrary Page") }

    var header: Any? {
        let container = StackPanel()
        container.padding = Thickness(left: 0, top: 0, right: 0, bottom: 16)

        let titleBlock = TextBlock()
        titleBlock.text = tr("Arbitrary Page")
        container.children.append(titleBlock)

        let subtitleBlock = TextBlock()
        subtitleBlock.text = tr("RsUI feature showcase — each section exercises a public API")
        subtitleBlock.fontSize = 14
        subtitleBlock.foreground = SolidColorBrush(App.context.theme.isDark
            ? UWP.Color(a: 255, r: 180, g: 180, b: 180)
            : UWP.Color(a: 255, r: 100, g: 100, b: 100))
        container.children.append(subtitleBlock)

        return container
    }

    var content: WinUI.UIElement {
        let stack = StackPanel()
        stack.spacing = 24

        stack.children.append(makeFullscreenSection())
        stack.children.append(makeNavigationModesSection())
        stack.children.append(makeOpenOrFocusSection())
        stack.children.append(makeAppearanceSection())
        stack.children.append(makeFolderPickerSection())

        let scrollViewer = ScrollViewer()
        scrollViewer.verticalScrollBarVisibility = .auto
        scrollViewer.content = stack

        let root = Grid()
        root.padding = Thickness(left: 40, top: 0, right: 40, bottom: 32)
        root.children.append(scrollViewer)
        return root
    }

    private func makeFullscreenSection() -> UIElement {
        let enterCard = SettingsCard(
            headerIconGlyph: "\u{E740}",
            header: tr("Enter tab fullscreen"),
            description: tr("Calls context.enterTabFullscreen(). Press Esc to exit.")
        )
        enterCard.isClickEnabled = true
        enterCard.click.addHandler { [weak self] _, _ in
            self?.context.enterTabFullscreen()
        }

        let exitCard = SettingsCard(
            headerIconGlyph: "\u{E73F}",
            header: tr("Exit tab fullscreen"),
            description: tr("Calls context.exitTabFullscreen(). No-op when not in fullscreen.")
        )
        exitCard.isClickEnabled = true
        exitCard.click.addHandler { [weak self] _, _ in
            self?.context.exitTabFullscreen()
        }

        return SettingsGroup(tr("Tab Fullscreen"), [enterCard, exitCard])
    }

    private func makeNavigationModesSection() -> UIElement {
        let inplaceCard = makeNavModeCard(
            glyph: "\u{E72C}",
            header: tr(".inplace"),
            description: tr("Replaces the current tab's page."),
            mode: .inplace
        )
        let newTabCard = makeNavModeCard(
            glyph: "\u{ECCD}",
            header: tr(".newTab"),
            description: tr("Opens a new tab and switches to it."),
            mode: .newTab
        )
        let newTabBackgroundCard = makeNavModeCard(
            glyph: "\u{F22C}",
            header: tr(".newTabBackground"),
            description: tr("Opens a new tab without stealing focus (like Ctrl+Click)."),
            mode: .newTabBackground
        )
        let newWindowCard = makeNavModeCard(
            glyph: "\u{E78B}",
            header: tr(".newWindow"),
            description: tr("Opens the page in a fresh MainWindow."),
            mode: .newWindow
        )

        return SettingsGroup(
            tr("NavigationOpenMode"),
            [inplaceCard, newTabCard, newTabBackgroundCard, newWindowCard]
        )
    }

    private func makeNavModeCard(
        glyph: String,
        header: String,
        description: String,
        mode: NavigationOpenMode
    ) -> SettingsCard {
        let card = SettingsCard(
            headerIconGlyph: glyph,
            header: header,
            description: description
        )
        card.isClickEnabled = true
        card.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            _ = self.context.open(self.url, mode: mode)
        }
        return card
    }

    private func makeOpenOrFocusSection() -> UIElement {
        let card = SettingsCard(
            headerIconGlyph: "\u{E8A7}",
            header: tr("openOrFocus"),
            description: tr("If a tab with this URL already exists, focuses it instead of creating a duplicate. Open a few via .newTab first to see the effect.")
        )
        card.isClickEnabled = true
        card.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            _ = self.context.openOrFocus(self.url)
        }
        return SettingsGroup(tr("Open or Focus"), [card])
    }

    private func makeAppearanceSection() -> UIElement {
        let themeToggle = ToggleSwitch()
        themeToggle.isOn = App.context.theme.isDark
        themeToggle.onContent = tr("Dark")
        themeToggle.offContent = tr("Light")
        themeToggle.toggled.addHandler { sender, _ in
            guard let toggle = sender as? ToggleSwitch else { return }
            App.context.theme = toggle.isOn ? .dark : .light
        }
        let themeCard = SettingsCard(
            headerIconGlyph: "\u{E771}",
            header: tr("Theme"),
            description: tr("Sets App.context.theme; persisted to preferences."),
            content: themeToggle
        )

        let langToggle = ToggleSwitch()
        langToggle.isOn = App.context.language == .zh_CN
        langToggle.onContent = "中文"
        langToggle.offContent = "EN"
        langToggle.toggled.addHandler { sender, _ in
            guard let toggle = sender as? ToggleSwitch else { return }
            App.context.language = toggle.isOn ? .zh_CN : .en_US
        }
        let langCard = SettingsCard(
            headerIconGlyph: "\u{F2B7}",
            header: tr("Language"),
            description: tr("Sets App.context.language; triggers chrome rebuild via Observation."),
            content: langToggle
        )

        return SettingsGroup(tr("Appearance"), [themeCard, langCard])
    }

    private func makeFolderPickerSection() -> UIElement {
        let resultBlock = TextBlock()
        resultBlock.text = tr("No folder selected yet.")
        resultBlock.fontSize = 12
        resultBlock.textWrapping = .wrap
        resultBlock.foreground = SolidColorBrush(App.context.theme.isDark
            ? UWP.Color(a: 255, r: 160, g: 160, b: 160)
            : UWP.Color(a: 255, r: 120, g: 120, b: 120))

        let card = SettingsCard(
            headerIconGlyph: "\u{E8B7}",
            header: tr("Folder Picker"),
            description: tr("Click to open the system folder picker. Selected path appears below."),
            content: resultBlock
        )
        card.contentAlignment = .vertical
        card.isClickEnabled = true
        card.click.addHandler { [weak self] _, _ in
            self?.context.pickFolder { path in
                resultBlock.text = path
            }
        }
        return SettingsGroup(tr("WindowContext.pickFolder"), [card])
    }
}
