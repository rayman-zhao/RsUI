import Foundation
import Observation
import WinUI

class PageModel {
    var backwardPages: [Page] = []
    var forwardPages: [Page] = []
    var currentPage: Page? = nil
    var needsRender: Bool = false

    init() {
    }

    init(page: Page) {
        currentPage = page
        needsRender = true
    }

    func navigate(to page: Page) {
        needsRender = true
        if currentPage === page {
            currentPage = page
        } else {
            if let previousPage = currentPage {
                backwardPages.append(previousPage)
                if backwardPages.count > App.context.route.maxHistoryPages {
                    backwardPages.removeFirst()
                }
            }
            currentPage = page
            forwardPages.removeAll()
        }
    }

    func goBack() {
        guard !backwardPages.isEmpty else { return }

        needsRender = true
        if let page = currentPage {
            forwardPages.append(page)
        }
        currentPage = backwardPages.removeLast()
    }

    func goForward() {
        guard !forwardPages.isEmpty else { return }

        needsRender = true
        if let page = currentPage {
            backwardPages.append(page)
        }
        currentPage = forwardPages.removeLast()
    }
}
