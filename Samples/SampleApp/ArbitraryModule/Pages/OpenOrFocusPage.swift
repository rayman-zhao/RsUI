import Foundation
import UWP
import WinUI
import RsUI

final class OpenOrFocusPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextChanged(_ context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://arbitrary/openorfocus")! }
    var title: String { tr("Open or Focus") }

    var header: Any? {
        featurePageHeader(
            title: tr("openOrFocus"),
            description: tr("Opens the URL in a new tab, or focuses the existing tab matching the URL. Open this page a few times via Navigation Modes → .newTab first to see the dedup effect.")
        )
    }

    var content: WinUI.UIElement {
        let card = SettingsCard(
            headerIconGlyph: "\u{E8A7}",
            header: tr("openOrFocus this page"),
            description: tr("Calls context.openOrFocus(url). If a duplicate tab exists, it gets focused instead of opening another one.")
        )
        card.isClickEnabled = true
        card.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            _ = self.context.openOrFocus(self.url)
        }
        return featurePageContent([card])
    }
}
