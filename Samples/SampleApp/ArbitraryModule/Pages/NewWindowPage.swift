import Foundation
import UWP
import WinUI
import RsUI

final class NewWindowPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextChanged(_ context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://arbitrary/new-window")! }
    var title: String { tr("New Window") }

    var header: Any? {
        featurePageHeader(
            title: tr("AppContext.openNewWindow"),
            description: tr("App-level new window entry — used when there is no WindowContext at hand. The collapseNavigationPane flag enables a viewer-style window that does not pollute the main window's NavPane preference.")
        )
    }

    var content: WinUI.UIElement {
        let plainCard = SettingsCard(
            headerIconGlyph: "\u{E78B}",
            header: tr("openNewWindow"),
            description: tr("Uses the persisted NavPane state.")
        )
        plainCard.isClickEnabled = true
        plainCard.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            App.context.openNewWindow(with: self.url)
        }

        let viewerCard = SettingsCard(
            headerIconGlyph: "\u{E73F}",
            header: tr("openNewWindow(collapseNavigationPane: true)"),
            description: tr("Starts with NavPane collapsed and skips writeback on close.")
        )
        viewerCard.isClickEnabled = true
        viewerCard.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            App.context.openNewWindow(with: self.url, collapseNavigationPane: true)
        }

        return featurePageContent([plainCard, viewerCard])
    }
}
