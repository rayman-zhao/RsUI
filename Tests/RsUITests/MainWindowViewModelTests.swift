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

@Suite
struct MainWindowViewModelTests {    
    @Test
    func initialState() {
        let viewModel = MainWindowViewModel()
        
        #expect(viewModel.backwardPages.isEmpty)
        #expect(viewModel.forwardPages.isEmpty)
        #expect(viewModel.currentPage == nil)
    }
    
    @Test
    func navigateToView() {
        let viewModel = MainWindowViewModel()
        let view = MockView()
        
        viewModel.navigate(to: view)
        
        #expect(viewModel.currentPage === view)
        #expect(viewModel.backwardPages.isEmpty)
        #expect(viewModel.forwardPages.isEmpty)
        #expect(viewModel.routePreferences.lastPageURL == view.url)
    }
    
    @Test
    func navigateToDifferentViewAddsToHistory() {
        let viewModel = MainWindowViewModel()
        let view1 = MockView()
        let view2 = MockView()
        
        viewModel.navigate(to: view1)
        viewModel.navigate(to: view2)
        
        #expect(viewModel.currentPage === view2)
        #expect(viewModel.backwardPages.count == 1)
        #expect(viewModel.backwardPages[0] === view1)
        #expect(viewModel.forwardPages.isEmpty)
        #expect(viewModel.routePreferences.lastPageURL == view2.url)
    }
    
    @Test
    func navigateToSameViewRefreshes() {
        let viewModel = MainWindowViewModel()
        let view = MockView()
        
        viewModel.navigate(to: view)
        viewModel.navigate(to: view)
        
        #expect(viewModel.currentPage === view)
        #expect(viewModel.backwardPages.isEmpty)
        #expect(viewModel.forwardPages.isEmpty)
        #expect(viewModel.routePreferences.lastPageURL == view.url)
    }
    
    @Test
    func historyLimitEnforced() {
        let viewModel = MainWindowViewModel()
        viewModel.routePreferences.maxHistoryPages = 2
        
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        let view4 = MockView()
        
        viewModel.navigate(to: view1)
        viewModel.navigate(to: view2)
        viewModel.navigate(to: view3)
        viewModel.navigate(to: view4)
        
        #expect(viewModel.backwardPages.count == 2)
        #expect(viewModel.backwardPages[0] === view2)
        #expect(viewModel.backwardPages[1] === view3)
        #expect(viewModel.currentPage === view4)
        #expect(viewModel.routePreferences.lastPageURL == view4.url)
    }
    
    @Test
    func goBack() {
        let viewModel = MainWindowViewModel()
        let view1 = MockView()
        let view2 = MockView()
        
        viewModel.navigate(to: view1)
        viewModel.navigate(to: view2)
        
        viewModel.goBack()
        
        #expect(viewModel.currentPage === view1)
        #expect(viewModel.backwardPages.isEmpty)
        #expect(viewModel.forwardPages.count == 1)
        #expect(viewModel.forwardPages[0] === view2)
        #expect(viewModel.routePreferences.lastPageURL == view1.url)
    }
    
    @Test
    func goBackWhenEmpty() {
        let viewModel = MainWindowViewModel()
        
        viewModel.goBack()
        
        #expect(viewModel.currentPage == nil)
        #expect(viewModel.backwardPages.isEmpty)
    }
    
    @Test
    func goForward() {
        let viewModel = MainWindowViewModel()
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        let view4 = MockView()
        
        viewModel.navigate(to: view1)
        viewModel.navigate(to: view2)
        viewModel.navigate(to: view3)
        viewModel.navigate(to: view4)
        viewModel.goBack()
        viewModel.goBack()
        
        viewModel.goForward()
        
        #expect(viewModel.currentPage === view3)
        #expect(viewModel.forwardPages.count == 1)
        #expect(viewModel.backwardPages.count == 2)
        #expect(viewModel.routePreferences.lastPageURL == view3.url)
    }
    
    @Test
    func goForwardWhenEmpty() {
        let viewModel = MainWindowViewModel()
        let view = MockView()
        
        viewModel.navigate(to: view)
        
        viewModel.goForward()
        
        #expect(viewModel.currentPage === view)
        #expect(viewModel.forwardPages.isEmpty)
        #expect(viewModel.routePreferences.lastPageURL == view.url)
    }
    
    @Test
    func navigationClearsForwardHistory() {
        let viewModel = MainWindowViewModel()
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        
        viewModel.navigate(to: view1)
        viewModel.navigate(to: view2)
        viewModel.goBack()
        
        #expect(viewModel.forwardPages.count == 1)
        
        viewModel.navigate(to: view3)
        
        #expect(viewModel.forwardPages.isEmpty)
        #expect(viewModel.backwardPages.count == 1)
        #expect(viewModel.routePreferences.lastPageURL == view3.url)
    }

    // Requirement: normal navigation stays in the current tab and appends the previous page to that tab's back stack.
    @Test
    func navigateInCurrentTabKeepsOneTabAndAddsCurrentTabHistory() {
        let viewModel = MainWindowViewModel()
        let view1 = MockView()
        let view2 = MockView()

        viewModel.navigate(to: view1)
        let firstTab = viewModel.selectedTab
        viewModel.navigate(to: view2)

        #expect(viewModel.tabs.count == 1)
        #expect(viewModel.selectedTab === firstTab)
        #expect(viewModel.currentPage === view2)
        #expect(viewModel.backwardPages.count == 1)
        #expect(viewModel.backwardPages[0] === view1)
    }

    // Requirement: Ctrl/open-in-new-tab navigation creates and selects a separate tab with an empty history stack.
    @Test
    func navigateInNewTabCreatesIndependentSelectedTab() {
        let viewModel = MainWindowViewModel()
        let view1 = MockView()
        let view2 = MockView()

        viewModel.navigate(to: view1)
        let firstTab = viewModel.selectedTab
        viewModel.navigate(to: view2, inNewTab: true)
        let secondTab = viewModel.selectedTab

        #expect(viewModel.tabs.count == 2)
        #expect(firstTab !== secondTab)
        #expect(firstTab?.currentPage === view1)
        #expect(secondTab?.currentPage === view2)
        #expect(secondTab?.backwardPages.isEmpty == true)
        #expect(secondTab?.forwardPages.isEmpty == true)
    }

    // Requirement: the same URL can be opened in multiple independent tabs, matching browser duplicate-tab behavior.
    @Test
    func navigateSameURLInNewTabCreatesDuplicateIndependentTab() {
        let viewModel = MainWindowViewModel()
        let view1 = MockView(id: "same-url")
        let view2 = MockView(id: "same-url")

        viewModel.navigate(to: view1)
        let firstTab = viewModel.selectedTab
        viewModel.navigate(to: view2, inNewTab: true)
        let secondTab = viewModel.selectedTab

        #expect(viewModel.tabs.count == 2)
        #expect(firstTab !== secondTab)
        #expect(firstTab?.currentPage === view1)
        #expect(secondTab?.currentPage === view2)
        #expect(firstTab?.currentPage?.url == secondTab?.currentPage?.url)
    }

    // Requirement: switching tabs restores each tab's own back and forward history without sharing state.
    @Test
    func eachTabKeepsItsOwnBackForwardHistory() {
        let viewModel = MainWindowViewModel()
        let tab1Page1 = MockView()
        let tab1Page2 = MockView()
        let tab2Page1 = MockView()
        let tab2Page2 = MockView()

        viewModel.navigate(to: tab1Page1)
        let firstTab = viewModel.selectedTab!
        viewModel.navigate(to: tab1Page2)

        viewModel.navigate(to: tab2Page1, inNewTab: true)
        let secondTab = viewModel.selectedTab!
        viewModel.navigate(to: tab2Page2)
        viewModel.goBack()

        viewModel.select(tab: firstTab)
        #expect(viewModel.currentPage === tab1Page2)
        #expect(viewModel.backwardPages.count == 1)
        #expect(viewModel.backwardPages[0] === tab1Page1)
        #expect(viewModel.forwardPages.isEmpty)

        viewModel.select(tab: secondTab)
        #expect(viewModel.currentPage === tab2Page1)
        #expect(viewModel.backwardPages.isEmpty)
        #expect(viewModel.forwardPages.count == 1)
        #expect(viewModel.forwardPages[0] === tab2Page2)
    }
}
