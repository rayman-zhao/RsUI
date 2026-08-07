import Foundation
import RsUI
import UWP
import WinUI

final class FullscreenPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func onWindowContextChanged(to context: WindowContext) {
        self.context = context
        (self.statusCard.headerIcon as! FontIcon).glyph =
            context.isInFullscreen ? "\u{E922}" : "\u{E93A}"
    }

    var url: URL { URL(string: "rs://sample/fullscreen")! }
    var title: String { tr("Fullscreen") }

    var header: Any? {
        featurePageHeader(
            title: tr("Fullscreen"),
            description: tr(
                "Hides chrome and reparents the selected tab content to a root overlay. Press Esc to exit."
            )
        )
    }

    var statusCard = SettingsCard(
        headerIconGlyph: "\u{E93A}",
        header: tr("Fullscreen status"),
        description: tr("Updated when window context changed.")
    )

    var content: WinUI.UIElement {
        let enterCard = SettingsCard(
            headerIconGlyph: "\u{E740}",
            header: tr("Enter tab fullscreen"),
            description: tr("Calls context.enterTabFullscreen().")
        )
        enterCard.isClickEnabled = true
        enterCard.click.addHandler { [weak self] _, _ in
            self?.context.enterFullscreen()
        }

        let exitCard = SettingsCard(
            headerIconGlyph: "\u{E73F}",
            header: tr("Exit tab fullscreen"),
            description: tr("Calls context.exitTabFullscreen(). No-op when not in fullscreen.")
        )
        exitCard.isClickEnabled = true
        exitCard.click.addHandler { [weak self] _, _ in
            self?.context.exitFullscreen()
        }

        return featurePageContent([statusCard, enterCard, exitCard])
    }
}
