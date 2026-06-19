import Foundation
import WindowsFoundation
import UWP
import WinUI

extension MainWindow {
    func renderSelectedTab() {
        syncTabItems()
        updateTabStripVisibility()

        guard let tab = viewModel.selectedTab, let page = tab.currentPage else {
            navigationView.header = nil
            hideAllTabFrames()
            navigationView.selectedItem = nil
            backButton.isEnabled = false
            forwardButton.isEnabled = false
            return
        }

        navigationView.header = nil
        updateTabItemState(for: tab)
        let frame = showFrame(for: tab)

        if tab.needsRender {
            let effectiveTransitionInfo: NavigationTransitionInfo?
            if isFirstNavigation {
                effectiveTransitionInfo = SuppressNavigationTransitionInfo()
                isFirstNavigation = false
            } else {
                effectiveTransitionInfo = tab.navigationTransitionInfo
            }
            frame.transition(
                to: makePageView(page, for: tab),
                transitionInfo: effectiveTransitionInfo
            )
            tab.needsRender = false
        }

        let tabItem = tabViewItem(for: tab)
        if !tabViewItem(tabView.selectedItem as? TabViewItem, represents: ObjectIdentifier(tab)) {
            isSyncingTabSelection = true
            tabView.selectedItem = tabItem
            isSyncingTabSelection = false
        }

        syncNavigationSelection(for: page.url)
        backButton.isEnabled = !tab.backwardPages.isEmpty
        forwardButton.isEnabled = !tab.forwardPages.isEmpty
    }

    private func syncTabItems() {
        guard let items = tabView.tabItems else { return }

        let ids = viewModel.tabs.map { ObjectIdentifier($0) }
        let activeIDs = Set(ids)
        tabItemsByID = tabItemsByID.filter { activeIDs.contains($0.key) }
        tabIDByName = tabIDByName.filter { activeIDs.contains($0.value) }
        tabTitlesByID = tabTitlesByID.filter { activeIDs.contains($0.key) }
        tabClosableByID = tabClosableByID.filter { activeIDs.contains($0.key) }
        tabPageViewPartsByID = tabPageViewPartsByID.filter { activeIDs.contains($0.key) }
        removeClosedTabFrames(activeIDs: activeIDs)

        guard ids != tabStripIDs else {
            return
        }

        isSyncingTabSelection = true
        defer { isSyncingTabSelection = false }

        // Step 1: 按身份精确移除 items 中所有不再属于 viewModel.tabs 的 TabViewItem。
        //   旧版只 `items.removeAt(items.size - 1)` 截尾，关闭非末尾 tab 时残留错位 item，
        //   后续 insertAt 会试图把同一 UIElement 插到已存在位置 → "two parents" WinRT 异常。
        var i: UInt32 = 0
        while i < items.size {
            if let item = items.getAt(i) as? TabViewItem,
               let id = tabIDByName[item.name],
               activeIDs.contains(id) {
                i += 1
            } else {
                items.removeAt(i)
            }
        }

        // Step 2: 重排到目标顺序。如果目标 tabItem 已在 items 中（错位），先从原位置移除再插入。
        for (index, tab) in viewModel.tabs.enumerated() {
            let id = ObjectIdentifier(tab)
            let tabItem = tabViewItem(for: tab)
            if UInt32(index) < items.size,
               let item = items.getAt(UInt32(index)) as? TabViewItem,
               tabViewItem(item, represents: id) {
                continue
            }

            // 找一下 tabItem 是否已在 items 别处
            var existingIndex: UInt32? = nil
            var j: UInt32 = 0
            while j < items.size {
                if let item = items.getAt(j) as? TabViewItem,
                   tabViewItem(item, represents: id) {
                    existingIndex = j
                    break
                }
                j += 1
            }
            if let existingIndex {
                items.removeAt(existingIndex)
            }
            items.insertAt(UInt32(index), tabItem)
        }
        tabStripIDs = ids
        updateAllTabItemCloseStates()
    }

    // After an in-window drag reorder WinUI has already moved the TabViewItems,
    // but viewModel.tabs still holds the old order. Rebuild it from the strip so
    // the reorder survives later add/close operations, which re-sync items to
    // the model order and would otherwise snap the tabs back.
    func syncTabOrderFromStrip() {
        guard let items = tabView.tabItems else { return }
        var reordered: [MainWindowTab] = []
        var i: UInt32 = 0
        while i < items.size {
            if let item = items.getAt(i) as? TabViewItem, let tab = tab(for: item) {
                reordered.append(tab)
            }
            i += 1
        }
        guard reordered.count == viewModel.tabs.count else { return }
        viewModel.reorder(to: reordered)
        tabStripIDs = reordered.map { ObjectIdentifier($0) }
    }

    private func tabViewItem(_ item: TabViewItem?, represents id: ObjectIdentifier) -> Bool {
        guard let item else { return false }
        if tabIDByName[item.name] == id {
            return true
        }
        return tabItemsByID[id] === item
    }

    // Collapse the whole strip when only one tab remains, so a one-tab window
    // looks like a plain page. Safe to hide the entire TabView because page
    // content lives in tabContentHost, not TabViewItem.Content, so hiding the
    // strip leaves the content showing.
    private func updateTabStripVisibility() {
        tabView.visibility = viewModel.tabs.count <= 1 ? .collapsed : .visible
    }

    func openNewTabFromTabStrip() {
        if let url = firstNavigationItemURL() {
            _ = navigate(to: url, mode: .newTab, transitionInfoOverride: SuppressNavigationTransitionInfo())
        } else {
            navigate(to: SettingsPage(), mode: .newTab, transitionInfoOverride: SuppressNavigationTransitionInfo())
        }
    }

    func tabViewItem(for tab: MainWindowTab) -> TabViewItem {
        let id = ObjectIdentifier(tab)
        if let item = tabItemsByID[id] {
            return item
        }

        let item = TabViewItem()
        let name = id.debugDescription
        item.name = name
        tabIDByName[name] = id
        item.tapped.addHandler { [weak self, weak item] _, _ in
            guard let self, let item, let tab = self.tab(for: item) else { return }
            self.switchToTab(tab)
        }
        item.closeRequested.addHandler { [weak self, weak item] _, _ in
            guard let self, let item else { return }
            self.closeTab(for: item)
        }
        tabItemsByID[id] = item
        updateTabItemState(for: tab)
        return item
    }

    func updateTabItemState(for tab: MainWindowTab) {
        let id = ObjectIdentifier(tab)
        guard let item = tabItemsByID[id] else { return }

        let newTitle = title(for: tab.currentPage)
        if tabTitlesByID[id] != newTitle {
            item.header = newTitle
            tabTitlesByID[id] = newTitle
        }

        let canClose = viewModel.tabs.count > 1
        if tabClosableByID[id] != canClose {
            item.isClosable = canClose
            tabClosableByID[id] = canClose
        }
    }

    private func updateAllTabItemCloseStates() {
        for tab in viewModel.tabs {
            updateTabItemState(for: tab)
        }
    }

}
