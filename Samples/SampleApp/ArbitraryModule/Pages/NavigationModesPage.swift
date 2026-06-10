import Foundation
import UWP
import WinUI
import RsUI

final class NavigationModesPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextChanged(_ context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://arbitrary/navigation")! }
    var title: String { tr("Navigation Modes") }

    var header: Any? {
        featurePageHeader(
            title: tr("NavigationOpenMode"),
            description: tr("Each card opens this same page through context.open(_:mode:) using a different mode.")
        )
    }

    var content: WinUI.UIElement {
        let cards: [UIElement] = [
            makeCard(
                glyph: "\u{E72C}",
                header: ".inplace",
                description: tr("Replaces the current tab's page."),
                mode: .inplace
            ),
            makeCard(
                glyph: "\u{ECCD}",
                header: ".newTab",
                description: tr("Opens a new tab and switches to it."),
                mode: .newTab
            ),
            makeCard(
                glyph: "\u{F22C}",
                header: ".newTabBackground",
                description: tr("Opens a new tab without stealing focus (like Ctrl+Click)."),
                mode: .newTabBackground
            ),
            makeCard(
                glyph: "\u{E78B}",
                header: ".newWindow",
                description: tr("Opens this page in a fresh MainWindow."),
                mode: .newWindow
            ),
        ]
        return featurePageContent(cards)
    }

    private func makeCard(
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
}
