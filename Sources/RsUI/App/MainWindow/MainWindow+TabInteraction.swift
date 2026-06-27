import Foundation
import WindowsFoundation
import UWP
import WinUI

extension MainWindow {
    // MARK: - Close

    func closeTab(for item: TabViewItem) {
        guard tabCount > 1, let ctx = tabContextsByName[item.name] else { return }
        let wasSelected = (tabView.selectedItem as? TabViewItem)?.name == item.name
        removeTab(ctx)
        if wasSelected, tabView.selectedItem == nil, let next = orderedTabContexts.first {
            selectItem(next.item)
        }
        renderSelectedTab()
    }

    func closeOtherTabs() {
        guard let keep = selectedTabContext, tabCount > 1 else { return }
        for ctx in orderedTabContexts where ctx.item.name != keep.item.name {
            removeTab(ctx)
        }
        selectItem(keep.item)
        renderSelectedTab()
    }

    func focusTab(matchingURL url: URL) -> Bool {
        guard let ctx = findTabContext(matchingURL: url) else { return false }
        selectItem(ctx.item)
        renderSelectedTab()
        return true
    }

    func findTabContext(matchingURL url: URL) -> TabContext? {
        orderedTabContexts.first { $0.model.currentPage?.url == url }
    }

    // MARK: - Native tear-out helpers

    // Returns a window for the native tear-out to drop a tab into. Reuses the
    // current empty spare if one exists (the framework asks repeatedly during a
    // drag); otherwise creates and activates a fresh one so it owns a valid
    // AppWindow.Id. The OS positions it as it follows the cursor.
    static func tearOutReceiver() -> MainWindow {
        if let spare = MainWindow.spareReceiver, spare.hasNoTabs {
            return spare
        }
        let window = MainWindow(tearOutReceiver: true)
        try? window.activate()
        MainWindow.spareReceiver = window
        return window
    }

    // Removes a tab from this window's strip; the MainWindowTab object — with its
    // history — lives on to be adopted elsewhere.
    func releaseTab(_ model: MainWindowTab) {
        guard viewModel != nil, let ctx = context(for: model) else { return }
        let wasSelected = selectedTabContext === ctx
        removeTab(ctx)
        if wasSelected, tabView.selectedItem == nil, let next = orderedTabContexts.first {
            selectItem(next.item)
        }
        renderSelectedTab()
    }

    // Adopts a torn model into this window's strip, building a fresh item + frame
    // for it. `at` is the merge drop position; nil appends (empty-receiver case).
    func adoptTornTab(_ model: MainWindowTab, at index: Int? = nil) {
        guard viewModel != nil else { return }
        awaitTransferredTab = false
        // The same Page instances travel with the model; rebind their context to
        // this window so window-scoped calls hit the new owner, not the creator.
        let context = WindowContext(owner: self)
        for page in model.allPages {
            page.windowContextChanged(context)
        }
        model.navigationTransitionInfo = SuppressNavigationTransitionInfo()
        model.needsRender = true
        let ctx = makeTab(model: model)
        insertItem(ctx.item, at: index)
        selectItem(ctx.item)
        renderSelectedTab()
    }

    // Closes this window once its last tab has been torn/merged away, so an
    // emptied floating receiver doesn't linger.
    func closeIfEmpty() {
        guard hasNoTabs else { return }
        try? close()
    }

    // MARK: - Detach / Restore (caller-managed transfer, used by viewer windows)

    func detachCurrentTab() -> DetachedTabInfo? {
        guard let ctx = selectedTabContext, let url = ctx.model.currentPage?.url else { return nil }
        let index = indexOfItem(name: ctx.item.name) ?? 0
        removeTab(ctx)
        if tabView.selectedItem == nil, let next = orderedTabContexts.first {
            selectItem(next.item)
        }
        renderSelectedTab()
        return DetachedTabInfo(url: url, index: index)
    }

    func restoreTab(
        _ page: Page,
        atIndex index: Int? = nil,
        switchToTab: Bool = true,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) {
        addTab(
            page: page,
            at: index,
            switchToTab: switchToTab,
            transitionInfoOverride: transitionInfoOverride
        )
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
