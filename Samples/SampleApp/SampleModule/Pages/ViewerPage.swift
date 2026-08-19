import Foundation
import RsUI
import UWP
import WinUI

final class ViewerPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextDidChange(to context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://sample/viewer")! }
    var title: String { tr("Viewer") }

    var header: Any? {
        featurePageHeader(
            title: tr("Viewer"),
            description: tr(
                "Viewer is a component that displays a content with toolbar/statusbar/navigationpanel/operationpanel."
            )
        )
    }

    var content: WinUI.UIElement {
        let viewer = Viewer()
        viewer.showsRightPaneButton = true
        viewer.showsChromeModeButton = true
        return viewer
    }
}
