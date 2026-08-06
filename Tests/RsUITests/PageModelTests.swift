import Foundation
import Testing
import WinUI

@testable import RsUI

private final class MockView: RsUI.Page {
    let id: String

    init(id: String = UUID().uuidString) {
        self.id = id
    }

    var url: URL { return URL(string: "rs://ui/test/\(id)")! }

    var title: String { "Mock \(id)" }

    var content: WinUI.UIElement {
        WinUI.Grid()
    }
}

@Suite
struct PageModelTests {
    @Test
    func initialState() {
        let view = MockView()
        let tab = PageModel(page: view)

        #expect(tab.currentPage === view)
        #expect(tab.backwardPages.isEmpty)
        #expect(tab.forwardPages.isEmpty)
    }

    @Test
    func navigateToDifferentPageAddsHistory() {
        let view1 = MockView()
        let view2 = MockView()
        let tab = PageModel(page: view1)

        tab.navigate(to: view2)

        #expect(tab.currentPage === view2)
        #expect(tab.backwardPages.count == 1)
        #expect(tab.backwardPages[0] === view1)
        #expect(tab.forwardPages.isEmpty)
    }

    @Test
    func navigateToSamePageRefreshesWithoutHistory() {
        let view = MockView()
        let tab = PageModel(page: view)

        tab.navigate(to: view)

        #expect(tab.currentPage === view)
        #expect(tab.backwardPages.isEmpty)
        #expect(tab.forwardPages.isEmpty)
    }

    @Test
    func historyLimitEnforced() {
        App.context.route.maxHistoryPages = 3
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        let view4 = MockView()
        let view5 = MockView()
        let tab = PageModel(page: view1)

        tab.navigate(to: view2)
        tab.navigate(to: view3)
        tab.navigate(to: view4)
        tab.navigate(to: view5)

        #expect(tab.backwardPages.count == App.context.route.maxHistoryPages)
        #expect(tab.backwardPages[0] === view2)
        #expect(tab.backwardPages[1] === view3)
        #expect(tab.currentPage === view5)
    }

    @Test
    func goBack() {
        let view1 = MockView()
        let view2 = MockView()
        let tab = PageModel(page: view1)
        tab.navigate(to: view2)

        tab.goBack()

        #expect(tab.currentPage === view1)
        #expect(tab.backwardPages.isEmpty)
        #expect(tab.forwardPages.count == 1)
        #expect(tab.forwardPages[0] === view2)
    }

    @Test
    func goBackWhenEmptyIsNoOp() {
        let view = MockView()
        let tab = PageModel(page: view)

        tab.goBack()

        #expect(tab.currentPage === view)
        #expect(tab.backwardPages.isEmpty)
        #expect(tab.forwardPages.isEmpty)
    }

    @Test
    func goForward() {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        let view4 = MockView()
        let tab = PageModel(page: view1)
        tab.navigate(to: view2)
        tab.navigate(to: view3)
        tab.navigate(to: view4)
        tab.goBack()
        tab.goBack()

        tab.goForward()

        #expect(tab.currentPage === view3)
        #expect(tab.forwardPages.count == 1)
        #expect(tab.backwardPages.count == 2)
    }

    @Test
    func goForwardWhenEmptyIsNoOp() {
        let view = MockView()
        let tab = PageModel(page: view)

        tab.goForward()

        #expect(tab.currentPage === view)
        #expect(tab.forwardPages.isEmpty)
    }

    @Test
    func navigationClearsForwardHistory() {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        let tab = PageModel(page: view1)
        tab.navigate(to: view2)
        tab.goBack()

        #expect(tab.forwardPages.count == 1)

        tab.navigate(to: view3)

        #expect(tab.forwardPages.isEmpty)
        #expect(tab.backwardPages.count == 1)
        #expect(tab.currentPage === view3)
    }

    @Test
    func allPagesIncludesHistoryAndCurrent() {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        let tab = PageModel(page: view1)
        tab.navigate(to: view2)
        tab.navigate(to: view3)
        tab.goBack()

        #expect(
            tab.backwardPages.count + tab.forwardPages.count + (tab.currentPage != nil ? 1 : 0) == 3
        )
    }
}
