import Foundation
import UWP
import WinUI
import RsUI

final class OverviewPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextChanged(_ context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://arbitrary")! }
    var title: String { tr("Overview") }

    var header: Any? {
        featurePageHeader(
            title: tr("Arbitrary"),
            description: tr("SampleApp demo module. Each item in the navigation pane focuses on one public RsUI surface. Tap a card below to jump straight to it.")
        )
    }

    var content: WinUI.UIElement {
        let cards: [UIElement] = [
            makeJumpCard(
                glyph: "\u{E740}",
                header: tr("Tab Fullscreen"),
                description: tr("context.enterTabFullscreen / exitTabFullscreen, Esc to exit."),
                path: "/fullscreen"
            ),
            makeJumpCard(
                glyph: "\u{ECCD}",
                header: tr("NavigationOpenMode"),
                description: tr(".inplace, .newTab, .newTabBackground, .newWindow."),
                path: "/navigation"
            ),
            makeJumpCard(
                glyph: "\u{E8A7}",
                header: tr("Open or Focus"),
                description: tr("Focuses an existing tab if its URL matches, otherwise opens a new one."),
                path: "/openorfocus"
            ),
            makeJumpCard(
                glyph: "\u{E78B}",
                header: tr("New Window"),
                description: tr("AppContext.openNewWindow, with optional collapsed NavPane for viewer-style windows."),
                path: "/new-window"
            ),
            makeJumpCard(
                glyph: "\u{E771}",
                header: tr("Appearance"),
                description: tr("Live toggle of App.context.theme and App.context.language."),
                path: "/appearance"
            ),
            makeJumpCard(
                glyph: "\u{E8B7}",
                header: tr("Folder Picker"),
                description: tr("WindowContext.pickFolder, parented to this window."),
                path: "/folder-picker"
            ),
        ]
        return featurePageContent(cards)
    }

    private func makeJumpCard(
        glyph: String,
        header: String,
        description: String,
        path: String
    ) -> SettingsCard {
        let card = SettingsCard(
            headerIconGlyph: glyph,
            header: header,
            description: description
        )
        card.isClickEnabled = true
        let targetURL = URL(string: "rs://arbitrary\(path)")!
        card.click.addHandler { [weak self] _, _ in
            _ = self?.context.open(targetURL, mode: .inplace)
        }
        return card
    }
}
