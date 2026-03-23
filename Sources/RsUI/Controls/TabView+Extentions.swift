import WinUI

public extension TabView {
    var canAutoCloseTabs: Bool {
        get {
            fatalError("canAutoCloseTabs getter is not implemented")
        }
        set {
            if newValue {
                tabCloseRequested.addHandler { sender, args in
                    guard let sender, let args else { return }
                    guard let closingTab = args.tab, let tabs = sender.tabItems else { return }

                    var idx: UInt32 = 0
                    if tabs.indexOf(closingTab, &idx) {
                        tabs.removeAt(idx)
                    }
                }
            } else {
                fatalError("canAutoCloseTabs disable is not implemented")
            }
        }

    }
}
