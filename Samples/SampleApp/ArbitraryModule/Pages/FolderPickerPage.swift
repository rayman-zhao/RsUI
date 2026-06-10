import Foundation
import UWP
import WinUI
import RsUI

final class FolderPickerPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextChanged(_ context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://arbitrary/folder-picker")! }
    var title: String { tr("Folder Picker") }

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
        resultBlock.foreground = SolidColorBrush(App.context.theme.isDark
            ? UWP.Color(a: 255, r: 160, g: 160, b: 160)
            : UWP.Color(a: 255, r: 120, g: 120, b: 120))

        let card = SettingsCard(
            headerIconGlyph: "\u{E8B7}",
            header: tr("Pick a folder"),
            description: tr("Click anywhere on this card to open the picker. Selected path appears below."),
            content: resultBlock
        )
        card.contentAlignment = .vertical
        card.isClickEnabled = true
        card.click.addHandler { [weak self] _, _ in
            self?.context.pickFolder { path in
                resultBlock.text = path
            }
        }

        return featurePageContent([card])
    }
}
