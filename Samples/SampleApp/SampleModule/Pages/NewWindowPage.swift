import Foundation
import RsUI
import UWP
import WinUI

final class NewWindowPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextDidChange(to context: WindowContext) {
        self.context = context
    }

    let url = URL(string: "rs://\(sampleModuleID)/new-window")!
    var title: String { tr("New Window") }

    var header: Any? {
        featurePageHeader(
            title: tr("AppContext.openNewWindow"),
            description: tr(
                "App-level new window entry — used when there is no WindowContext at hand. The forceMinimalMode flag enables a viewer-style window that does not pollute the main window's NavPane preference."
            )
        )
    }

    var content: WinUI.UIElement {
        let plainCard = makeClickableCard(
            glyph: "\u{E78B}",
            header: tr("App.context.openNewWindow"),
            description: tr("Uses the persisted NavPane state.")
        ) { [weak self] in
            guard let self else { return }
            App.context.openNewWindow(with: [self.url])
        }

        let viewerCard = makeClickableCard(
            glyph: "\u{E73F}",
            header: tr("App.context.openNewWindow(forceMinimalMode: true)"),
            description: tr("Starts with NavPane collapsed and skips writeback on close.")
        ) { [weak self] in
            guard let self else { return }
            App.context.openNewWindow(with: [self.url], forceMinimalMode: true)
        }

        return featurePageContent([plainCard, viewerCard])
    }
}
