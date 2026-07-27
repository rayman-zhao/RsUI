import Foundation
import WindowsFoundation
import UWP
import WinUI

// Bridges one TabView strip item to its navigation model and content frame.
// Lives in MainWindow.tabContextsByName keyed by `item.name`. Holds a strong
// reference to the item (safe — only identity comparison of projected items is
// unstable, which we avoid by keying on name).
final class TabContext {
    let model: MainWindowTab
    let item: TabViewItem
    let frame: PageFrame
    var title: String?
    var isClosable: Bool?

    init(model: MainWindowTab, item: TabViewItem, frame: PageFrame) {
        self.model = model
        self.item = item
        self.frame = frame
    }
}

extension MainWindow {
    // MARK: - TabView-backed accessors (strip is the source of truth)

    var selectedTabContext: TabContext? {
        guard let item = tabView.selectedItem as? TabViewItem else { return nil }
        return tabContextsByName[item.name]
    }

    var selectedTabModel: MainWindowTab? { selectedTabContext?.model }

    var currentPage: Page? { selectedTabModel?.currentPage }

    var tabCount: Int { tabContextsByName.count }

    // True once the window has no tabs, or after teardown nilled the viewModel.
    var hasNoTabs: Bool { viewModel == nil || tabContextsByName.isEmpty }

    // Contexts in strip order (tabView.tabItems is authoritative for ordering,
    // including after a native drag-reorder — no separate sync needed).
    var orderedTabContexts: [TabContext] {
        guard let items = tabView.tabItems else { return [] }
        var result: [TabContext] = []
        var i: UInt32 = 0
        while i < items.size {
            if let item = items.getAt(i) as? TabViewItem, let ctx = tabContextsByName[item.name] {
                result.append(ctx)
            }
            i += 1
        }
        return result
    }

    func context(for model: MainWindowTab) -> TabContext? {
        tabContextsByName.values.first { $0.model === model }
    }

    // MARK: - Rendering

    func renderSelectedTab() {
        guard viewModel != nil else { return }
        updateTabStripVisibility()
        updateAllTabClosableStates()

        guard let ctx = selectedTabContext, let page = ctx.model.currentPage else {
            navigationView.header = nil
            hideAllTabFrames()
            navigationView.selectedItem = nil
            backButton.isEnabled = false
            forwardButton.isEnabled = false
            return
        }

        navigationView.header = nil
        updateTabTitle(ctx)
        let frame = showFrame(for: ctx)

        if ctx.model.needsRender {
            let effectiveTransitionInfo: NavigationTransitionInfo?
            if isFirstNavigation {
                effectiveTransitionInfo = SuppressNavigationTransitionInfo()
                isFirstNavigation = false
            } else {
                effectiveTransitionInfo = ctx.model.navigationTransitionInfo
            }
            frame.renderCurrentPageIfNeeded(transitionInfoOverride: effectiveTransitionInfo)
        }

        syncNavigationSelection(for: page.url)
        backButton.isEnabled = !ctx.model.backwardPages.isEmpty
        forwardButton.isEnabled = !ctx.model.forwardPages.isEmpty
        viewModel.routePreferences.lastPageURL = page.url
    }

    // Collapse the whole strip when only one tab remains, so a one-tab window
    // looks like a plain page. Safe to hide the entire TabView because page
    // content lives in tabContentHost, not TabViewItem.Content, so hiding the
    // strip leaves the content showing.
    private func updateTabStripVisibility() {
        tabView.visibility = tabCount <= 1 ? .collapsed : .visible
    }

    func updateTabTitle(_ ctx: TabContext) {
        let newTitle = title(for: ctx.model.currentPage)
        if ctx.title != newTitle {
            ctx.item.header = newTitle
            ctx.title = newTitle
        }
    }

    // 迁自 MainWindow+PageRendering.swift：strip 标题的本地化文案，属 TabView
    // 职责，故留在此文件而非 PageFrame。
    private func title(for page: Page?) -> String {
        page?.title ?? MainWindow.tr("New Tab")
    }

    // Closable iff more than one tab remains; the lone tab can't be closed.
    private func updateAllTabClosableStates() {
        let canClose = tabCount > 1
        for ctx in tabContextsByName.values where ctx.isClosable != canClose {
            ctx.item.isClosable = canClose
            ctx.isClosable = canClose
        }
    }

    // MARK: - Tab lifecycle

    func makeTab(model: MainWindowTab) -> TabContext {
        let item = TabViewItem()
        item.name = UUID().uuidString
        item.minWidth = 100

        let frame = PageFrame(model: model)
        frame.visibility = .collapsed
        tabContentHost.children.append(frame)

        let ctx = TabContext(model: model, item: item, frame: frame)
        tabContextsByName[item.name] = ctx
        updateTabTitle(ctx)
        return ctx
    }

    @discardableResult
    func addTab(
        page: Page,
        at index: Int? = nil,
        switchToTab: Bool = true,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> TabContext {
        let model = MainWindowTab(page: page, transitionInfoOverride: transitionInfoOverride)
        let ctx = makeTab(model: model)
        insertItem(ctx.item, at: index)
        if switchToTab || selectedTabContext == nil {
            selectItem(ctx.item)
        }
        renderSelectedTab()
        return ctx
    }

    // Batch form of addTab: inserts every page as a tab but renders the strip
    // only once at the end, instead of once per tab. A client loop that called
    // addTab N times would pay renderSelectedTab() N times — and its
    // O(tabCount) closable-state rescan makes that O(N²) — plus N selection
    // changes and N frame shows. Here all items are inserted first, the final
    // selection is chosen once, and a single renderSelectedTab() draws only the
    // landed tab; background tabs stay unrendered until first selected, exactly
    // like a single background addTab.
    @discardableResult
    func addTabs(
        pages: [Page],
        switchToLast: Bool = true,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> [TabContext] {
        guard !pages.isEmpty else { return [] }
        let hadSelection = selectedTabContext != nil

        var contexts: [TabContext] = []
        contexts.reserveCapacity(pages.count)
        for page in pages {
            let model = MainWindowTab(page: page, transitionInfoOverride: transitionInfoOverride)
            let ctx = makeTab(model: model)
            insertItem(ctx.item, at: nil)
            contexts.append(ctx)
        }

        // Mirror the looped-addTab selection: foreground lands on the last tab;
        // a background batch into an empty window still needs a selection, so it
        // lands on the first; an existing selection is otherwise preserved.
        let selection: TabContext?
        if switchToLast {
            selection = contexts.last
        } else if !hadSelection {
            selection = contexts.first
        } else {
            selection = nil
        }
        if let selection {
            selectItem(selection.item)
        }

        renderSelectedTab()
        return contexts
    }

    // Removes a tab from the strip and tears down its frame, keeping its model
    // alive so a tear-out/detach caller can re-home it. Does not adjust selection.
    func removeTab(_ ctx: TabContext) {
        removeItemFromStrip(name: ctx.item.name)
        tabContextsByName[ctx.item.name] = nil
        removeFrame(ctx.frame)
        if visibleTabFrameName == ctx.item.name {
            visibleTabFrameName = nil
        }
    }

    func openNewTabFromTabStrip() {
        if let url = firstNavigationItemURL() {
            _ = navigate(to: url, mode: .newTab, transitionInfoOverride: SuppressNavigationTransitionInfo())
        } else {
            navigate(to: SettingsPage(), mode: .newTab, transitionInfoOverride: SuppressNavigationTransitionInfo())
        }
    }

    // MARK: - Strip primitives (match items by stable name, not by === identity)

    func insertItem(_ item: TabViewItem, at index: Int?) {
        guard let items = tabView.tabItems else { return }
        isSyncingTabSelection = true
        defer { isSyncingTabSelection = false }
        if let index, index >= 0, UInt32(index) <= items.size {
            items.insertAt(UInt32(index), item)
        } else {
            items.insertAt(items.size, item)
        }
    }

    func selectItem(_ item: TabViewItem) {
        isSyncingTabSelection = true
        tabView.selectedItem = item
        isSyncingTabSelection = false
    }

    private func removeItemFromStrip(name: String) {
        guard let items = tabView.tabItems else { return }
        isSyncingTabSelection = true
        defer { isSyncingTabSelection = false }
        var i: UInt32 = 0
        while i < items.size {
            if let it = items.getAt(i) as? TabViewItem, it.name == name {
                items.removeAt(i)
                return
            }
            i += 1
        }
    }

    func indexOfItem(name: String) -> Int? {
        guard let items = tabView.tabItems else { return nil }
        var i: UInt32 = 0
        while i < items.size {
            if let it = items.getAt(i) as? TabViewItem, it.name == name {
                return Int(i)
            }
            i += 1
        }
        return nil
    }
}
