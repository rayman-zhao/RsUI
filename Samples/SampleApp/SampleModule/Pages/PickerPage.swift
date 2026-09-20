import Foundation
import RsUI
import UWP
import WinUI

final class PickerPage: RsUI.Page {
    var context: WindowContext
    // 主导航项用默认 "/picker"；footer 导航项传 "/footer-picker"，
    // 使其 URL 与导航项匹配（openOrFocus 去重、选中态高亮依赖该 URL）。
    let path: String

    init(context: WindowContext, path: String = "/picker") {
        self.context = context
        self.path = path
    }

    func windowContextDidChange(to context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://sample\(path)")! }
    var title: String { tr("Picker") }

    var header: Any? {
        featurePageHeader(
            title: tr("WindowContext.pickFolder"),
            description: tr("System folder picker parented to the owning MainWindow.")
        )
    }

    var content: WinUI.UIElement {
        let resultBlock = makeCaption(tr("No folder selected yet."))

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
                if let path {
                    resultBlock.text = path
                }
            }
        }

        let resultBlock2 = makeCaption(tr("No save file selected yet."))

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
                    tr("Text files"): [".txt"], tr("Image files"): [".jpg", ".jpeg", ".png"],
                ],
                suggestedFileName: "sample",
                defaultFileExtension: ".txt",
            ) { path in
                if let path {
                    resultBlock2.text = path
                }
            }
        }

        return featurePageContent([card, card2])
    }
}
