import Foundation
import UWP
import WinUI
import RsUI

final class FullscreenPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextChanged(_ context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://arbitrary/fullscreen")! }
    var title: String { tr("Fullscreen") }

    var header: Any? {
        featurePageHeader(
            title: tr("Tab Fullscreen"),
            description: tr("Hides chrome and reparents the selected tab content to a root overlay. Press Esc to exit.")
        )
    }

    var content: WinUI.UIElement {
        let enterCard = SettingsCard(
            headerIconGlyph: "\u{E740}",
            header: tr("Enter tab fullscreen"),
            description: tr("Calls context.enterTabFullscreen().")
        )
        enterCard.isClickEnabled = true
        enterCard.click.addHandler { [weak self] _, _ in
            self?.context.enterTabFullscreen()
        }

        let exitCard = SettingsCard(
            headerIconGlyph: "\u{E73F}",
            header: tr("Exit tab fullscreen"),
            description: tr("Calls context.exitTabFullscreen(). No-op when not in fullscreen.")
        )
        exitCard.isClickEnabled = true
        exitCard.click.addHandler { [weak self] _, _ in
            self?.context.exitTabFullscreen()
        }

        return featurePageContent([enterCard, exitCard])
    }
}
