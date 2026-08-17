import Foundation
import RsUI
import UWP
import WinUI

final class PickerPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextDidChange(to context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://sample/picker")! }
    var title: String { tr("Picker") }

    var header: Any? {
        featurePageHeader(
            title: tr("WindowContext.pickFolder"),
            description: tr("System folder picker parented to the owning MainWindow.")
        )
    }

    var content: WinUI.UIElement {
        let resultBlock = TextBlock()
        resultBlock.text = tr("No folder selected yet.")
        resultBlock.fontSize = 12
        resultBlock.textWrapping = .wrap
        resultBlock.foreground = SolidColorBrush(
            App.context.theme.isDark
                ? UWP.Color(a: 255, r: 160, g: 160, b: 160)
                : UWP.Color(a: 255, r: 120, g: 120, b: 120))

        let card = SettingsCard(
            headerIconGlyph: "\u{E8B7}",
            header: tr("Pick a folder"),
            description: tr(
                "Click anywhere on this card to open the picker. Selected path appears below."),
            content: resultBlock
        )
        card.contentAlignment = .vertical
        card.isClickEnabled = true
        card.click.addHandler { [weak self] _, _ in
            self?.context.pickFolder { path in
                resultBlock.text = path
            }
        }

        let resultBlock2 = TextBlock()
        resultBlock2.text = tr("No save file selected yet.")
        resultBlock2.fontSize = 12
        resultBlock2.textWrapping = .wrap
        resultBlock2.foreground = SolidColorBrush(
            App.context.theme.isDark
                ? UWP.Color(a: 255, r: 160, g: 160, b: 160)
                : UWP.Color(a: 255, r: 120, g: 120, b: 120))

        let card2 = SettingsCard(
            headerIconGlyph: "\u{E8B7}",
            header: tr("Pick a save file"),
            description: tr(
                "Click anywhere on this card to open the picker. Selected path appears below."),
            content: resultBlock2
        )
        card2.contentAlignment = .vertical
        card2.isClickEnabled = true
        card2.click.addHandler { [weak self] _, _ in
            self?.context.pickSaveFile(
                suggestedStartLocation: .documentsLibrary,
                fileTypeChoices: [
                    "Text files": [".txt"], "Image files": [".jpg", ".jpeg", ".png"],
                ],
                suggestedFileName: "sample",
                defaultFileExtension: ".txt",
            ) { path in
                resultBlock2.text = path
            }
        }

        return featurePageContent([card, card2])
    }
}
