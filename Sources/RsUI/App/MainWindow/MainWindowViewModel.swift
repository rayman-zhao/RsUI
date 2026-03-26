import Foundation
import Observation
import RsHelper

@Observable
class MainWindowViewModel {
    var routePreferences: RoutePreferences

    var backwardPages: [Page] = []
    var forwardPages: [Page] = []
    var currentPage: Page? = nil

    init() {
        routePreferences = App.context.preferences.load(for: RoutePreferences.self)
    }

    deinit {
        App.context.preferences.save(routePreferences)
    }

    func navigate(to page: Page) {
        if (currentPage === page) { // For refresh current page by appearance change etc.
            currentPage = page
        } else {
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

        if let page = currentPage {
            forwardPages.append(page)
        }
        currentPage = backwardPages.removeLast()        
        routePreferences.lastPageURL = currentPage?.url
    }

    func goForward() {
        guard !forwardPages.isEmpty else { return }

        if let page = currentPage {
            backwardPages.append(page)
        }
        currentPage = forwardPages.removeFirst()
        routePreferences.lastPageURL = currentPage?.url
    }

    private func dumpHistory() {
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
