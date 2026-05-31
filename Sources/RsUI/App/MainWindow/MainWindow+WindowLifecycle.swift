import Foundation
import Observation
import WinAppSDK
import WinUI

extension MainWindow {
    func setupWindow() {
        self.extendsContentIntoTitleBar = true
        self.appWindow.titleBar.preferredHeightOption = .tall
                
        // 设置 Mica 背景
        let micaBackdrop = MicaBackdrop()
        micaBackdrop.kind = .base
        self.systemBackdrop = micaBackdrop

        self.sizeChanged.addHandler { [weak self] _, _ in
            self?.trackWindowSize()
        }
        self.closed.addHandler { [weak self] _, _ in
            guard let self else { return }

            // 先 cancel observation tasks，避免死窗口的 task 继续访问 self.appWindow / self.viewModel
            self.envObservationTask?.cancel()
            self.routeObservationTask?.cancel()
            self.envObservationTask = nil
            self.routeObservationTask = nil

            // TODO: appWindow.changed事件不工作，此处窗口最大化时记录有缺陷。其实也可以不保存，恢复窗口在中间即可。
            self.trackWindowPosition()
            if !self.suppressLayoutPersistence {
                self.viewModel.windowLayout.navigationViewPaneOpen = self.navigationView.isPaneOpen
                self.viewModel.windowLayout.navigationViewOpenPaneLength = self.navigationView.openPaneLength
            }
            self.viewModel = nil
        }
        restoreWindowRect()
    }


    func startObserving() {
        let env = Observations {
            (App.context.theme, App.context.language)
        }
        envObservationTask = Task { [weak self] in
            for await _ in env {
                await MainActor.run { [weak self] in
                    self?.applyAppearance()
                }
            }
        }

        // viewModel 在 closed handler 里会被设为 nil（包括最大化最后一个 tab 的场景），
        // 此处必须用 ?. 避免 IUO 强解包崩溃；renderSelectedTab 也会再做一次 nil 检查
        let route = Observations {
            self.viewModel?.navigationRevision ?? 0
        }
        routeObservationTask = Task { [weak self] in
            for await _ in route {
                await MainActor.run { [weak self] in
                    guard let self, self.viewModel != nil else { return }
                    self.renderSelectedTab()
                }
            }
        }
    }

    private func applyAppearance() {
        // 死窗口防御：closed handler 把 viewModel 置为 nil，此时 appWindow 也已失效（IUO → nil）
        guard viewModel != nil, appWindow != nil else { return }
        // 防止并发/重入（多窗口下 env Observation 接连触发可能引发 menuItems 的双 parent 错误）
        guard !isApplyingAppearance else { return }
        isApplyingAppearance = true
        defer { isApplyingAppearance = false }

        // For min/max/close buttons. 目前不支持材质效果，但比逐个设置按钮颜色简单，并且容易由框架修正。
        self.appWindow.titleBar.preferredTheme = App.context.theme.titleBarTheme

        self.title = MainWindow.tr(App.context.productName)
        titleBar.title = self.title
        searchBox?.placeholderText = MainWindow.tr("searchControlsAndSamples")
        applyCloseOthersTooltip(to: closeOtherTabsButton)
        tabDragHintText?.text = MainWindow.tr("TabDragHint")

        let context = WindowContext(owner: self)
        titleBarRightHeader.children.clear()
        navigationView.menuItems.clear()
        navigationView.footerMenuItems.clear()
        for module in App.context.modules {
            if let item = module.titleBarRightHeaderItemRequired(in: context) {
                titleBarRightHeader.children.append(item)
            }
            for item in module.navigationViewMenuItemsRequired(in: context) {
                appendNavigationItem(item, false)
            }
            for item in module.navigationViewFooterMenuItemsRequired(in: context) {
                appendNavigationItem(item, true)
            }
        }

        if let makeInitialPage = initialPageFactory {
            initialPageFactory = nil
            let transitionInfoOverride = initialNavigationTransitionInfoOverride ?? SuppressNavigationTransitionInfo()
            initialNavigationTransitionInfoOverride = nil
            navigate(to: makeInitialPage(context), transitionInfoOverride: transitionInfoOverride)
            return
        }

        if let url = initialNavigationURL {
            initialNavigationURL = nil
            let transitionInfoOverride = initialNavigationTransitionInfoOverride ?? SuppressNavigationTransitionInfo()
            initialNavigationTransitionInfoOverride = nil
            _ = navigate(to: url, transitionInfoOverride: transitionInfoOverride)
            return
        }

        if let page = viewModel.currentPage {
            navigate(to: page)
        } else if let lastURL = viewModel.routePreferences.lastPageURL, navigate(to: lastURL) {
            return
        } else {
            navigationView.selectFirstItem()
        }
    }
    
    private func restoreWindowRect() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter
        else { return }

        let maximized = viewModel.windowPosition.isMaximized //moveAndResize will cause pref changed in event, so need to reserve here
        try? hwnd.moveAndResize(viewModel.windowPosition.windowRect)
        if maximized {
            try? presenter.maximize()
        }
    }

    private func trackWindowSize() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter else { return }

        if presenter.state == .restored {
            viewModel.windowPosition.windowWidth = Int(hwnd.size.width)
            viewModel.windowPosition.windowHeight = Int(hwnd.size.height)
            viewModel.windowPosition.isMaximized = false
        } else if presenter.state == .maximized {
            viewModel.windowPosition.isMaximized = true
        }
    }

    private func trackWindowPosition() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter
        else { return }

        if presenter.state == .restored {
            viewModel.windowPosition.windowX = Int(hwnd.position.x)
            viewModel.windowPosition.windowY = Int(hwnd.position.y)
        }
    }

    // MARK: - Splitter Methods
}
