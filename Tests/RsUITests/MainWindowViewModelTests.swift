import Foundation
import Testing
import WinUI
@testable import RsUI

private final class MockView: RsUI.Page {
    let id = UUID().uuidString
    var url: URL { return URL(string: "rs://ui/mainwindow/test/\(id)")! }

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
        
        viewModel.navigate(to: view1)
        viewModel.navigate(to: view2)
        viewModel.goBack()
        
        viewModel.goForward()
        
        #expect(viewModel.currentPage === view2)
        #expect(viewModel.forwardPages.isEmpty)
        #expect(viewModel.backwardPages.count == 1)
        #expect(viewModel.routePreferences.lastPageURL == view2.url)
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
}