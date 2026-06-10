import Foundation
import WindowsFoundation
import UWP
import WinUI

extension MainWindow {
    func tab(for item: TabViewItem) -> MainWindowTab? {
        // Primary: stable name-based lookup (avoids WinRT projection identity instability)
        if let id = tabIDByName[item.name], let tab = viewModel.tabs.first(where: { ObjectIdentifier($0) == id }) {
            return tab
        }
        // Fallback: identity comparison
        for tab in viewModel.tabs {
            if tabItemsByID[ObjectIdentifier(tab)] === item {
                return tab
            }
        }
        return nil
    }

    func selectedTabViewItem(sender: Any?, args: SelectionChangedEventArgs?) -> TabViewItem? {
        if
            let args,
            let addedItems = args.addedItems,
            addedItems.size > 0,
            let item = addedItems.getAt(0) as? TabViewItem {
            return item
        }

        if let tabView = sender as? TabView {
            return tabView.selectedItem as? TabViewItem
        }

        return tabView.selectedItem as? TabViewItem
    }

    func switchToTab(_ tab: MainWindowTab) {
        guard viewModel.selectedTab !== tab else { return }
        viewModel.select(tab: tab)
        renderSelectedTab()
    }

    func closeTab(for item: TabViewItem) {
        guard let tab = tab(for: item) else { return }
        viewModel.close(tab: tab)
        renderSelectedTab()
    }

    func closeOtherTabs() {
        viewModel.closeOtherTabs()
        renderSelectedTab()
    }

    // MARK: - Native tear-out helpers

    // Returns a window for the native tear-out to drop a tab into. Reuses the
    // current empty spare if one exists (the framework asks repeatedly during a
    // drag); otherwise creates and activates a fresh one so it owns a valid
    // AppWindow.Id. The OS positions it as it follows the cursor.
    static func tearOutReceiver() -> MainWindow {
        if let spare = MainWindow.spareReceiver, spare.viewModel?.tabs.isEmpty ?? false {
            return spare
        }
        let window = MainWindow(tearOutReceiver: true)
        try? window.activate()
        MainWindow.spareReceiver = window
        return window
    }

    // Removes a tab from this window's model (its strip item is reconciled away
    // by renderSelectedTab); the MainWindowTab object — with its history — lives
    // on to be adopted elsewhere.
    func releaseTab(_ tab: MainWindowTab) {
        guard viewModel != nil else { return }
        viewModel.detachTab(tab)
        renderSelectedTab()
    }

    // Adopts a torn tab into this window's model, building a fresh strip item for
    // it. `at` is the merge drop position; nil appends (the empty-receiver case).
    func adoptTornTab(_ tab: MainWindowTab, at index: Int? = nil) {
        guard viewModel != nil else { return }
        awaitTransferredTab = false
        // The same Page instances travel with the tab; rebind their context to
        // this window so window-scoped calls hit the new owner, not the creator.
        let context = WindowContext(owner: self)
        for page in tab.allPages {
            page.windowContextChanged(context)
        }
        viewModel.adoptTab(tab, at: index, transitionInfoOverride: SuppressNavigationTransitionInfo())
        renderSelectedTab()
    }

    // Closes this window once its last tab has been torn/merged away, so an
    // emptied floating receiver doesn't linger.
    func closeIfEmpty() {
        guard viewModel?.tabs.isEmpty ?? false else { return }
        try? close()
    }

    func focusTab(matchingURL url: URL) -> Bool {
        guard let tab = viewModel.findTab(matchingURL: url) else { return false }
        switchToTab(tab)
        return true
    }

    func detachCurrentTab() -> DetachedTabInfo? {
        guard let currentTab = viewModel.selectedTab else { return nil }
        guard let index = viewModel.tabs.firstIndex(where: { $0 === currentTab }) else { return nil }
        guard let url = currentTab.currentPage?.url else { return nil }
        viewModel.detachTab(currentTab)
        renderSelectedTab()
        return DetachedTabInfo(url: url, index: index)
    }

    func insertTab(
        _ page: Page,
        atIndex index: Int? = nil,
        switchToTab: Bool = true,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) {
        viewModel.addTab(
            at: index,
            for: page,
            transitionInfoOverride: transitionInfoOverride,
            switchToTab: switchToTab
        )
        renderSelectedTab()
    }

    static func openDetachedWindow(
        navigatingTo url: URL,
        transitionInfoOverride: NavigationTransitionInfo? = nil,
        collapseNavigationPane: Bool = false
    ) {
        // 一次性 viewer 窗口：初始折叠 NavPane，且不把折叠状态回写到全局 windowLayout。
        // 必须经 init 参数路径，因为 setupContent 一旦跑完 lazy navigationView 就定型了。
        let window = collapseNavigationPane
            ? MainWindow(initialNavigationViewPaneOpen: false, suppressLayoutPersistence: true)
            : MainWindow()
        window.initialNavigationURL = url
        window.initialNavigationTransitionInfoOverride = transitionInfoOverride
        try? window.activate()
    }

    static func openDetachedWindow(
        opening page: Page,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) {
        openDetachedWindow(transitionInfoOverride: transitionInfoOverride) { _ in page }
    }

    static func openDetachedWindow(
        transitionInfoOverride: NavigationTransitionInfo? = nil,
        makePage: @escaping (WindowContext) -> Page
    ) {
        let window = MainWindow()
        window.initialPageFactory = makePage
        window.initialNavigationTransitionInfoOverride = transitionInfoOverride
        try? window.activate()
    }

    // Opens a new top-level window in-process showing Home, skipping last-view
    // restore. The taskbar "New Window" reaches this after being redirected to
    // the primary instance.
    static func openDetachedWindowAtHome() {
        let window = MainWindow(forceHomeOnLaunch: true)
        try? window.activate()
    }
}
