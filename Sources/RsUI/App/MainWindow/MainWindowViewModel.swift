import Foundation
import Observation
import WinUI
import RsFoundation

// Per-tab navigation model: the current page plus its back/forward history.
// TabView owns the tab strip (order, selection, lifecycle); this type only
// carries one tab's navigation state and is bridged to a strip item by
// `MainWindow.TabContext`. It holds no WinUI strip/window types so its history
// logic stays unit-testable in isolation (see MainWindowTabTests).
class MainWindowTab {
    var backwardPages: [Page] = []
    var forwardPages: [Page] = []
    var currentPage: Page? = nil
    var navigationTransitionInfo: NavigationTransitionInfo? = nil
    var needsRender: Bool = false

    // Current page plus both history stacks
    var allPages: [Page] {
        backwardPages + forwardPages + (currentPage.map { [$0] } ?? [])
    }

    init(page: Page, transitionInfoOverride: NavigationTransitionInfo? = nil) {
        currentPage = page
        navigationTransitionInfo = transitionInfoOverride
        needsRender = true
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

// Window-scoped, non-tab state. The tab list/selection moved into TabView (the
// strip is the source of truth), so this is now only persisted preferences.
@Observable
class MainWindowViewModel {
    var windowPosition: WindowPosition
    var windowLayout: WindowLayout
    var routePreferences: RoutePreferences

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
}
