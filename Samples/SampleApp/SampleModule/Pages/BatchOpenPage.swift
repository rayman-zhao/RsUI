import Foundation
import RsUI
import UWP
import WinUI

final class BatchOpenPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func onWindowContextChanged(to context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://sample/batch-open")! }
    var title: String { tr("Batch Open") }

    // The routes opened by the batch demo, in tab order.
    private var routes: [URL] {
        [
            "rs://sample/navigation",
            "rs://sample/openorfocus",
            "rs://sample/appearance",
            "rs://sample/fullscreen",
        ].compactMap { URL(string: $0) }
    }

    var header: Any? {
        featurePageHeader(
            title: tr("Batch Open"),
            description: tr(
                "context.open([URL]) opens many tabs in one render instead of looping over open(_:mode:)."
            )
        )
    }

    var content: WinUI.UIElement {
        let cards: [UIElement] = [
            makeCard(
                glyph: "\u{ECCD}",
                header: tr("Open all in foreground"),
                description: tr(
                    "context.open(routes) — opens every route as a tab and selects the last one."),
                mode: .newTab
            ),
            makeCard(
                glyph: "\u{F22C}",
                header: tr("Open all in background"),
                description: tr(
                    "context.open(routes, mode: .newTabBackground) — opens the same tabs without leaving this page."
                ),
                mode: .newTabNoFocus
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
            _ = self.context.open(self.routes, mode: mode)
        }
        return card
    }
}
