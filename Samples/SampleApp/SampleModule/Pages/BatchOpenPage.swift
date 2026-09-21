import Foundation
import RsUI
import UWP
import WinUI

final class BatchOpenPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextDidChange(to context: WindowContext) {
        self.context = context
    }

    let url = URL(string: "rs://\(sampleModuleID)/batch-open")!
    var title: String { tr("Batch Open") }

    // The routes opened by the batch demo, in tab order.
    private var routes: [URL] {
        [
            "rs://\(sampleModuleID)/navigation",
            "rs://\(sampleModuleID)/openorfocus",
            "rs://\(sampleModuleID)/appearance",
            "rs://\(sampleModuleID)/fullscreen",
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
                    "context.open(routes, mode: .newTabNoFocus) — opens the same tabs without leaving this page."
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
        makeClickableCard(glyph: glyph, header: header, description: description) {
            [weak self] in
            guard let self else { return }
            _ = self.context.open(self.routes, mode: mode)
        }
    }
}
