import Foundation
import Testing
import WinUI
@testable import RsUI

private final class MockView: RsUI.Page {
    let id: String

    init(id: String = UUID().uuidString) {
        self.id = id
    }

    var url: URL { return URL(string: "rs://ui/mainwindow/test/\(id)")! }

    var title: String { "Mock \(id)" }

    var content: WinUI.UIElement {
        WinUI.Grid()
    }
}

// Per-tab navigation history. The tab list / selection moved into TabView (the
// strip is the source of truth and needs a live window), so these cover only the
// window-independent history logic of a single MainWindowTab.
@Suite
struct MainWindowTabTests {
    private let maxHistory = 32

    @Test
    func initialState() {
        let view = MockView()
        let tab = MainWindowTab(page: view)

        #expect(tab.currentPage === view)
        #expect(tab.backwardPages.isEmpty)
        #expect(tab.forwardPages.isEmpty)
    }

    @Test
    func navigateToDifferentPageAddsHistory() {
        let view1 = MockView()
        let view2 = MockView()
        let tab = MainWindowTab(page: view1)

        tab.navigate(to: view2, maxHistoryPages: maxHistory)

        #expect(tab.currentPage === view2)
        #expect(tab.backwardPages.count == 1)
        #expect(tab.backwardPages[0] === view1)
        #expect(tab.forwardPages.isEmpty)
    }

    @Test
    func navigateToSamePageRefreshesWithoutHistory() {
        let view = MockView()
        let tab = MainWindowTab(page: view)

        tab.navigate(to: view, maxHistoryPages: maxHistory)

        #expect(tab.currentPage === view)
        #expect(tab.backwardPages.isEmpty)
        #expect(tab.forwardPages.isEmpty)
    }

    @Test
    func historyLimitEnforced() {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        let view4 = MockView()
        let tab = MainWindowTab(page: view1)

        tab.navigate(to: view2, maxHistoryPages: 2)
        tab.navigate(to: view3, maxHistoryPages: 2)
        tab.navigate(to: view4, maxHistoryPages: 2)

        #expect(tab.backwardPages.count == 2)
        #expect(tab.backwardPages[0] === view2)
        #expect(tab.backwardPages[1] === view3)
        #expect(tab.currentPage === view4)
    }

    @Test
    func goBack() {
        let view1 = MockView()
        let view2 = MockView()
        let tab = MainWindowTab(page: view1)
        tab.navigate(to: view2, maxHistoryPages: maxHistory)

        tab.goBack()

        #expect(tab.currentPage === view1)
        #expect(tab.backwardPages.isEmpty)
        #expect(tab.forwardPages.count == 1)
        #expect(tab.forwardPages[0] === view2)
    }

    @Test
    func goBackWhenEmptyIsNoOp() {
        let view = MockView()
        let tab = MainWindowTab(page: view)

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
        let tab = MainWindowTab(page: view1)
        tab.navigate(to: view2, maxHistoryPages: maxHistory)
        tab.navigate(to: view3, maxHistoryPages: maxHistory)
        tab.navigate(to: view4, maxHistoryPages: maxHistory)
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
        let tab = MainWindowTab(page: view)

        tab.goForward()

        #expect(tab.currentPage === view)
        #expect(tab.forwardPages.isEmpty)
    }

    @Test
    func navigationClearsForwardHistory() {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        let tab = MainWindowTab(page: view1)
        tab.navigate(to: view2, maxHistoryPages: maxHistory)
        tab.goBack()

        #expect(tab.forwardPages.count == 1)

        tab.navigate(to: view3, maxHistoryPages: maxHistory)

        #expect(tab.forwardPages.isEmpty)
        #expect(tab.backwardPages.count == 1)
        #expect(tab.currentPage === view3)
    }

    @Test
    func allPagesIncludesHistoryAndCurrent() {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        let tab = MainWindowTab(page: view1)
        tab.navigate(to: view2, maxHistoryPages: maxHistory)
        tab.navigate(to: view3, maxHistoryPages: maxHistory)
        tab.goBack()

        #expect(tab.allPages.count == 3)
    }
}
