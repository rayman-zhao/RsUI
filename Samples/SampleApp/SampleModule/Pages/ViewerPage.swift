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

    var content: WinUI.UIElement {
        let viewer = Viewer()
        let centerText = TextBlock()
        centerText.text = tr("Viewer center content")
        centerText.horizontalAlignment = .center
        centerText.verticalAlignment = .center
        viewer.centerContent = centerText

        let topText = TextBlock()
        topText.text = tr("Viewer toolbar")
        topText.horizontalAlignment = .center
        topText.verticalAlignment = .center
        viewer.topContent = topText
        viewer.setPaneState(.expanded, for: .top)

        let leftText = TextBlock()
        leftText.text = tr("Viewer left pane")
        leftText.horizontalAlignment = .center
        leftText.verticalAlignment = .center
        viewer.leftContent = leftText
        viewer.setPaneState(.expanded, for: .left)

        let rightText = TextBlock()
        rightText.text = tr("Viewer right pane")
        rightText.horizontalAlignment = .center
        rightText.verticalAlignment = .center
        viewer.rightContent = rightText
        viewer.setPaneState(.expanded, for: .right)

        let bottomText = TextBlock()
        bottomText.text = tr("Viewer bottom pane")
        bottomText.horizontalAlignment = .center
        bottomText.verticalAlignment = .center
        viewer.bottomContent = bottomText
        viewer.setPaneState(.expanded, for: .bottom)

        viewer.showsLeftPaneButton = true
        viewer.showsRightPaneButton = true
        viewer.showsChromeModeButton = true
        viewer.showsFullscreenButton = true
        viewer.onFullscreenRequested = { [weak self] in
            guard let self = self else { return }
            if self.context.isInFullscreen {
                self.context.exitFullscreen()
            } else {
                self.context.enterFullscreen()
            }
        }

        return viewer
    }
}
