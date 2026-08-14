import Foundation

class PageModel {
    var backwardPages: [Page] = []
    var forwardPages: [Page] = []
    var currentPage: Page?

    init() {
    }

    init(page: Page) {
        currentPage = page
    }

    func navigate(to page: Page) {
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

        if let page = currentPage {
            forwardPages.append(page)
        }
        currentPage = backwardPages.removeLast()
    }

    func goForward() {
        guard !forwardPages.isEmpty else { return }

        if let page = currentPage {
            backwardPages.append(page)
        }
        currentPage = forwardPages.removeLast()
    }
}
