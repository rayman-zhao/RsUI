import Foundation
import RsUI
import UWP
import WinUI

final class NavigationModesPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextDidChange(to context: WindowContext) {
        self.context = context
    }

    let url = URL(string: "rs://\(sampleModuleID)/navigation")!
    var title: String { tr("Navigation Modes") }

    var header: Any? {
        featurePageHeader(
            title: tr("NavigationOpenMode"),
            description: tr(
                "Each card opens this same page through context.open(_:mode:) using a different mode."
            )
        )
    }

    var content: WinUI.UIElement {
        let settingsURL = URL(string: "rs://ui/settings")!
        let cards: [UIElement] = [
            makeClickableCard(
                glyph: "\u{E72C}",
                header: ".inplace",
                description: tr("Replaces the current tab's page.")
            ) { [weak self] in
                _ = self?.context.open(settingsURL, mode: .inplace)
            },
            makeClickableCard(
                glyph: "\u{ECCD}",
                header: ".newTab",
                description: tr("Opens a new tab and switches to it.")
            ) { [weak self] in
                _ = self?.context.open(settingsURL, mode: .newTab)
            },
            makeClickableCard(
                glyph: "\u{F22C}",
                header: ".newTabNoFocus",
                description: tr("Opens a new tab without stealing focus (like Ctrl+Click).")
            ) { [weak self] in
                _ = self?.context.open(settingsURL, mode: .newTabNoFocus)
            },
            makeClickableCard(
                glyph: "\u{E78B}",
                header: ".newWindow",
                description: tr("Opens this page in a fresh MainWindow.")
            ) {
                App.context.openNewWindow(with: [settingsURL])
            },
        ]
        return featurePageContent(cards)
    }
}
