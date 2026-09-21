import Foundation
import RsUI
import UWP
import WinUI

final class RevealPage: RsUI.Page {
    let url = URL(string: "rs://\(sampleModuleID)/reveal")!
    var title: String { tr("Reveal in File Explorer") }

    private lazy var demoFileURL: URL = App.context.supportDirectory.appending(
        component: "Reveal Demo.txt")
    private lazy var missingURL: URL = App.context.supportDirectory.appending(
        component: "Missing Item.txt")

    var header: Any? {
        featurePageHeader(
            title: tr("AppContext.revealInFileExplorer"),
            description: tr(
                "Opens File Explorer with LaunchFolderPathAsync and selects the item via FolderLauncherOptions."
            )
        )
    }

    var content: WinUI.UIElement {
        let statusBlock = makeCaption(tr("Nothing revealed yet."))

        let statusCard = SettingsCard(
            headerIconGlyph: "\u{E946}",
            header: tr("Last request"),
            description: tr("Each card below triggers one reveal call."),
            content: statusBlock
        )
        statusCard.contentAlignment = .vertical

        let directoryCard = SettingsCard(
            headerIconGlyph: "\u{E838}",
            header: tr("Reveal the support directory"),
            description: tr("Directory case: selects the app support directory in its parent folder."),
            content: makeCaption(App.context.supportDirectory.filePath)
        )
        directoryCard.isClickEnabled = true
        directoryCard.click.addHandler { _, _ in
            App.context.revealInFileExplorer(App.context.supportDirectory)
            statusBlock.text = String(
                format: tr("Requested reveal: %@"), App.context.supportDirectory.filePath)
        }

        let fileCard = SettingsCard(
            headerIconGlyph: "\u{E8A5}",
            header: tr("Reveal a demo file"),
            description: tr(
                "File case with spaces in the name: creates Reveal Demo.txt under the support directory, then selects it."
            ),
            content: makeCaption(demoFileURL.filePath)
        )
        fileCard.isClickEnabled = true
        fileCard.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            let url = self.ensureDemoFile()
            App.context.revealInFileExplorer(url)
            statusBlock.text = String(format: tr("Requested reveal: %@"), url.filePath)
        }

        let missingCard = SettingsCard(
            headerIconGlyph: "\u{E7BA}",
            header: tr("Reveal a missing path"),
            description: tr(
                "Guard case: unreachable paths are skipped with a log warning; no File Explorer window opens."
            ),
            content: makeCaption(missingURL.filePath)
        )
        missingCard.isClickEnabled = true
        missingCard.click.addHandler { [weak self] _, _ in
            guard let url = self?.missingURL else { return }
            App.context.revealInFileExplorer(url)
            statusBlock.text = String(format: tr("Requested reveal: %@"), url.filePath)
        }

        return featurePageContent([statusCard, directoryCard, fileCard, missingCard])
    }

    private func ensureDemoFile() -> URL {
        if !demoFileURL.reachable {
            try? Data("RsUI reveal demo".utf8).write(to: demoFileURL)
        }
        return demoFileURL
    }
}
