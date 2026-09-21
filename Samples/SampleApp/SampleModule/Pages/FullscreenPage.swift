import Foundation
import RsUI
import UWP
import WinUI

final class FullscreenPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    /// 当前挂载中的状态卡。每次 content 重建都新建一张（文案/画刷随之刷新），
    /// 这里只持有「当前这一张」供全屏切换时原地翻转图标，不跨重建复用旧元素。
    private var statusCard: SettingsCard?

    func windowContextDidChange(to context: WindowContext) {
        self.context = context
        if let icon = statusCard?.headerIcon as? FontIcon {
            icon.glyph = context.isInFullscreen ? "\u{E922}" : "\u{E93A}"
        }
    }

    let url = URL(string: "rs://\(sampleModuleID)/fullscreen")!
    var title: String { tr("Fullscreen") }

    var header: Any? {
        featurePageHeader(
            title: tr("Fullscreen"),
            description: tr(
                "Hides chrome and reparents the selected tab content to a root overlay. Press Esc to exit."
            )
        )
    }

    var content: WinUI.UIElement {
        let status = SettingsCard(
            headerIconGlyph: context.isInFullscreen ? "\u{E922}" : "\u{E93A}",
            header: tr("Fullscreen status"),
            description: tr("Updated when window context changed.")
        )
        statusCard = status

        let enterCard = makeClickableCard(
            glyph: "\u{E740}",
            header: tr("Enter tab fullscreen"),
            description: tr("Calls context.enterFullscreen().")
        ) { [weak self] in
            self?.context.enterFullscreen()
        }

        let exitCard = makeClickableCard(
            glyph: "\u{E73F}",
            header: tr("Exit tab fullscreen"),
            description: tr("Calls context.exitFullscreen(). No-op when not in fullscreen.")
        ) { [weak self] in
            self?.context.exitFullscreen()
        }

        return featurePageContent([status, enterCard, exitCard])
    }
}
