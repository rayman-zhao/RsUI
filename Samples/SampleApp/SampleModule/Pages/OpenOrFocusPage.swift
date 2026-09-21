import Foundation
import RsUI
import UWP
import WinUI

final class OpenOrFocusPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextDidChange(to context: WindowContext) {
        self.context = context
    }

    let url = URL(string: "rs://\(sampleModuleID)/openorfocus")!
    var title: String { tr("Open or Focus") }

    var header: Any? {
        featurePageHeader(
            title: tr("openOrFocus"),
            description: tr(
                """
                Opens the URL in a new tab, or focuses the existing tab matching the URL. \
                Open this page a few times via Navigation Modes → .newTab first to see the dedup effect.
                """
            )
        )
    }

    var content: WinUI.UIElement {
        let targetURL = URL(string: "rs://ui/settings")!
        let card = makeClickableCard(
            glyph: "\u{E8A7}",
            header: tr("openOrFocus this page"),
            description: tr(
                "Calls context.openOrFocus(url). If a duplicate tab exists, it gets focused instead of opening another one."
            )
        ) { [weak self] in
            _ = self?.context.openOrFocus(targetURL)
        }
        return featurePageContent([card])
    }
}
