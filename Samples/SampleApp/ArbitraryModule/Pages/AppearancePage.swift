import Foundation
import UWP
import WinUI
import RsUI

final class AppearancePage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextChanged(_ context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://arbitrary/appearance")! }
    var title: String { tr("Appearance") }

    var header: Any? {
        featurePageHeader(
            title: tr("Theme & Language"),
            description: tr("App.context.theme and App.context.language are @Observable. Setting them rebuilds the chrome of every open window and persists to preferences.")
        )
    }

    var content: WinUI.UIElement {
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
            description: tr("Sets App.context.theme."),
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
            description: tr("Sets App.context.language; the tr() helper prefixes \"翻译\" when in zh_CN."),
            content: langToggle
        )

        return featurePageContent([themeCard, langCard])
    }
}
