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

    func setupTabDragHint() {
        let hintText = TextBlock()
        hintText.text = MainWindow.tr("TabDragHint")
        hintText.fontSize = 12
        hintText.textWrapping = .wrap
        hintText.maxWidth = 460
        hintText.foreground = SolidColorBrush(UWP.Color(a: 255, r: 245, g: 249, b: 255))

        let hintBorder = Border()
        hintBorder.background = SolidColorBrush(UWP.Color(a: 230, r: 21, g: 94, b: 175))
        hintBorder.borderBrush = SolidColorBrush(UWP.Color(a: 255, r: 166, g: 215, b: 255))
        hintBorder.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
        hintBorder.cornerRadius = CornerRadius(topLeft: 10, topRight: 10, bottomRight: 10, bottomLeft: 10)
        hintBorder.padding = Thickness(left: 12, top: 8, right: 12, bottom: 8)
        hintBorder.horizontalAlignment = .center
        hintBorder.verticalAlignment = .top
        hintBorder.margin = Thickness(left: 0, top: 12, right: 0, bottom: 0)
        hintBorder.opacity = 0
        hintBorder.visibility = .collapsed
        hintBorder.isHitTestVisible = false
        hintBorder.child = hintText
        try? Canvas.setZIndex(hintBorder, 99)
        tabContentHost.children.append(hintBorder)
        tabDragHintBorder = hintBorder
        tabDragHintText = hintText

        tabView.tabDragStarting.addHandler { [weak hintBorder] _, _ in
            hintBorder?.visibility = .visible
            hintBorder?.opacity = 1
        }
        tabView.tabDragCompleted.addHandler { [weak hintBorder] _, _ in
            hintBorder?.opacity = 0
            hintBorder?.visibility = .collapsed
        }
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
}
