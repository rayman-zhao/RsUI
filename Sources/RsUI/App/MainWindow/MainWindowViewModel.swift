import Foundation
import Observation
import RsHelper

enum NavigationDirection {
    case forward
    case backward
    case none
}

@Observable
class MainWindowViewModel {
    var windowPosition: WindowPosition
    var windowLayout: WindowLayout
    var routePreferences: RoutePreferences

    var backwardPages: [Page] = []
    var forwardPages: [Page] = []
    var currentPage: Page? = nil
    var navigationDirection: NavigationDirection = .none

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

    func navigate(to page: Page) {
        if (currentPage === page) { // For refresh current page by appearance change etc.
            navigationDirection = .none
            currentPage = page
        } else {
            navigationDirection = .forward
            if let previousPage = currentPage {
                backwardPages.append(previousPage)
                if backwardPages.count > routePreferences.maxHistoryPages {
                    backwardPages.removeFirst()
                }
            }
            currentPage = page
            forwardPages.removeAll()
            routePreferences.lastPageURL = page.url
        }
    }

    func goBack() {
        guard !backwardPages.isEmpty else { return }

        navigationDirection = .backward
        if let page = currentPage {
            forwardPages.append(page)
        }
        currentPage = backwardPages.removeLast()
        routePreferences.lastPageURL = currentPage?.url
    }

    func goForward() {
        guard !forwardPages.isEmpty else { return }

        navigationDirection = .forward
        if let page = currentPage {
            backwardPages.append(page)
        }
        currentPage = forwardPages.removeLast()
        routePreferences.lastPageURL = currentPage?.url
    }

    func dumpHistory() {
        for (index, page) in backwardPages.enumerated() {
            log.info("\(index) <===\(page.url)")
        }
        log.info("-----------------------------------------------")
        log.info("====\(currentPage?.url.absoluteString ?? "nil")")
        log.info("-----------------------------------------------")
        for (index, page) in forwardPages.enumerated() {
            log.info("\(index) ===>\(page.url)")
        }
    }
}
