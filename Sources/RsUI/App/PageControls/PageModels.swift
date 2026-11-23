import Foundation
import WinUI

/// 每标签一份的页面栈,仅在 UI 线程被 PageFrame/PageTabView 访问(持有
/// @MainActor 的 Page),整类隔离令编译器强制这一事实。视图缓存归页自身
/// (Page.view 槽位),失效与回填由框架经 updateView/currentView 进行
@MainActor class PageModel {
    var backwardPages: [Page] = []
    var forwardPages: [Page] = []
    var currentPage: Page?

    init() {
    }

    init(page: Page) {
        currentPage = page
    }

    var allPages: [Page] {
        [currentPage].compactMap { $0 } + backwardPages + forwardPages
    }

    /// 清空本 model 全部页的视图缓存(外观变化路径)
    func invalidateAllViews() {
        for page in allPages {
            page.view = nil
        }
    }

    func navigate(to page: Page) {
        guard currentPage !== page else { return }

        if let previousPage = currentPage {
            backwardPages.append(previousPage)
            if backwardPages.count > App.context.route.maxHistoryPages {
                backwardPages.removeFirst()
            }
        }
        currentPage = page
        forwardPages.removeAll()
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
