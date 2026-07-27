import Foundation
import WinUI

extension MainWindow {
    // Makes the selected tab's frame visible and collapses the rest. Frames are
    // created with their TabContext (see makeTab) and torn down in removeTab, so
    // there is no lazy creation or separate GC pass here anymore.
    func showFrame(for ctx: TabContext) -> PageFrame {
        let name = ctx.item.name
        guard visibleTabFrameName != name else {
            return ctx.frame
        }

        for context in tabContextsByName.values {
            context.frame.visibility = context.item.name == name ? .visible : .collapsed
        }
        visibleTabFrameName = name
        return ctx.frame
    }

    func hideAllTabFrames() {
        for context in tabContextsByName.values {
            context.frame.visibility = .collapsed
        }
        visibleTabFrameName = nil
    }

    func removeFrame(_ frame: PageFrame) {
        var idx: UInt32 = 0
        if tabContentHost.children.indexOf(frame, &idx) {
            tabContentHost.children.removeAt(idx)
        }
    }
}
