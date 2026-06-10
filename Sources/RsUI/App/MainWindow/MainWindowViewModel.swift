import Foundation
import Observation
import WinUI
import RsHelper

class MainWindowTab {
    var backwardPages: [Page] = []
    var forwardPages: [Page] = []
    var currentPage: Page? = nil
    var navigationTransitionInfo: NavigationTransitionInfo? = nil
    var needsRender: Bool = false

    // Current page plus both history stacks, e.g. to rebind page-held state when
    // the tab migrates to another window.
    var allPages: [Page] {
        backwardPages + forwardPages + (currentPage.map { [$0] } ?? [])
    }

    init(page: Page, transitionInfoOverride: NavigationTransitionInfo? = nil) {
        navigate(to: page, transitionInfoOverride: transitionInfoOverride)
    }

    func navigate(to page: Page, transitionInfoOverride: NavigationTransitionInfo? = nil, maxHistoryPages: Int) {
        navigationTransitionInfo = transitionInfoOverride
        needsRender = true
        if currentPage === page {
            currentPage = page
        } else {
            if let previousPage = currentPage {
                backwardPages.append(previousPage)
                if backwardPages.count > maxHistoryPages {
                    backwardPages.removeFirst()
                }
            }
            currentPage = page
            forwardPages.removeAll()
        }
    }

    func navigate(to page: Page, transitionInfoOverride: NavigationTransitionInfo? = nil) {
        navigationTransitionInfo = transitionInfoOverride
        currentPage = page
        needsRender = true
    }

    func goBack(_ transitionInfoOverride: NavigationTransitionInfo? = nil) {
        guard !backwardPages.isEmpty else { return }

        navigationTransitionInfo = transitionInfoOverride
        needsRender = true
        if let page = currentPage {
            forwardPages.append(page)
        }
        currentPage = backwardPages.removeLast()
    }

    func goForward(_ transitionInfoOverride: NavigationTransitionInfo? = nil) {
        guard !forwardPages.isEmpty else { return }

        navigationTransitionInfo = transitionInfoOverride
        needsRender = true
        if let page = currentPage {
            backwardPages.append(page)
        }
        currentPage = forwardPages.removeLast()
    }
}

@Observable
class MainWindowViewModel {
    var windowPosition: WindowPosition
    var windowLayout: WindowLayout
    var routePreferences: RoutePreferences

    var tabs: [MainWindowTab] = []
    var selectedTab: MainWindowTab? = nil
    var navigationRevision: Int = 0

    var backwardPages: [Page] {
        selectedTab?.backwardPages ?? []
    }
    var forwardPages: [Page] {
        selectedTab?.forwardPages ?? []
    }
    var currentPage: Page? {
        selectedTab?.currentPage
    }
    var navigationTransitionInfo: NavigationTransitionInfo? {
        selectedTab?.navigationTransitionInfo
    }

    init() {
        windowPosition = App.context.preferences.load(for: WindowPosition.self)
        windowLayout = App.context.preferences.load(for: WindowLayout.self)
        routePreferences = App.context.preferences.load(for: RoutePreferences.self)
    }

    deinit {
        App.context.preferences.save(windowPosition)
        App.context.preferences.save(windowLayout)
        App.context.preferences.save(routePreferences)
    }

    @discardableResult
    func navigate(
        to page: Page,
        transitionInfoOverride: NavigationTransitionInfo? = nil,
        inNewTab: Bool = false,
        switchToTab: Bool = true
    ) -> MainWindowTab {
        let tab: MainWindowTab
        if inNewTab || selectedTab == nil {
            tab = MainWindowTab(page: page, transitionInfoOverride: transitionInfoOverride)
            tabs.append(tab)
        } else {
            tab = selectedTab!
            tab.navigate(
                to: page,
                transitionInfoOverride: transitionInfoOverride,
                maxHistoryPages: routePreferences.maxHistoryPages
            )
        }

        if switchToTab || selectedTab == nil {
            selectedTab = tab
            routePreferences.lastPageURL = page.url
        }
        navigationRevision += 1
        return tab
    }

    func goBack(_ transitionInfoOverride: NavigationTransitionInfo? = nil) {
        guard let selectedTab, !selectedTab.backwardPages.isEmpty else { return }

        selectedTab.goBack(transitionInfoOverride)
        routePreferences.lastPageURL = currentPage?.url
        navigationRevision += 1
    }

    func goForward(_ transitionInfoOverride: NavigationTransitionInfo? = nil) {
        guard let selectedTab, !selectedTab.forwardPages.isEmpty else { return }

        selectedTab.goForward(transitionInfoOverride)
        routePreferences.lastPageURL = currentPage?.url
        navigationRevision += 1
    }

    func findTab(matchingURL url: URL) -> MainWindowTab? {
        tabs.first { $0.currentPage?.url == url }
    }

    @discardableResult
    func addTab(
        at index: Int? = nil,
        for page: Page,
        transitionInfoOverride: NavigationTransitionInfo? = nil,
        switchToTab: Bool = true
    ) -> MainWindowTab {
        let tab = MainWindowTab(page: page, transitionInfoOverride: transitionInfoOverride)
        if let index, index >= 0, index <= tabs.count {
            tabs.insert(tab, at: index)
        } else {
            tabs.append(tab)
        }
        if switchToTab || selectedTab == nil {
            selectedTab = tab
            routePreferences.lastPageURL = page.url
        }
        navigationRevision += 1
        return tab
    }

    func select(tab: MainWindowTab) {
        guard tabs.contains(where: { $0 === tab }) else { return }
        selectedTab = tab
        routePreferences.lastPageURL = tab.currentPage?.url
        navigationRevision += 1
    }

    func close(tab: MainWindowTab) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0 === tab }) else { return }

        let wasSelected = selectedTab === tab
        tabs.remove(at: index)
        if wasSelected {
            selectedTab = tabs[min(index, tabs.count - 1)]
            routePreferences.lastPageURL = selectedTab?.currentPage?.url
        }
        navigationRevision += 1
    }

    func reorder(to reordered: [MainWindowTab]) {
        guard reordered.count == tabs.count else { return }
        tabs = reordered
    }

    func closeOtherTabs() {
        guard let tab = selectedTab, tabs.count > 1 else { return }
        tabs = [tab]
        navigationRevision += 1
    }

    /// Removes a tab for transfer to another window; unlike close(tab:), allows removing with only 1 tab remaining.
    func detachTab(_ tab: MainWindowTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        let wasSelected = selectedTab === tab
        tabs.remove(at: index)
        if wasSelected {
            selectedTab = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)]
            routePreferences.lastPageURL = selectedTab?.currentPage?.url
        }
        navigationRevision += 1
    }

    /// Adopts an existing tab object dragged in from another window (merge),
    /// preserving its back/forward history instead of re-navigating by URL.
    @discardableResult
    func adoptTab(
        _ tab: MainWindowTab,
        at index: Int? = nil,
        transitionInfoOverride: NavigationTransitionInfo? = nil,
        switchToTab: Bool = true
    ) -> MainWindowTab {
        guard !tabs.contains(where: { $0 === tab }) else { return tab }
        tab.navigationTransitionInfo = transitionInfoOverride
        tab.needsRender = true
        if let index, index >= 0, index <= tabs.count {
            tabs.insert(tab, at: index)
        } else {
            tabs.append(tab)
        }
        if switchToTab || selectedTab == nil {
            selectedTab = tab
            routePreferences.lastPageURL = tab.currentPage?.url
        }
        navigationRevision += 1
        return tab
    }
}
