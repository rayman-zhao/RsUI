import Foundation
import Observation
import WinAppSDK
import WinUI

extension MainWindow {
    func setupWindow() {
        self.closed.addHandler { [weak self] _, _ in
            guard let self else { return }

            // A speculative tear-out can create an empty spare window that never
            // gets a tab. The process exits only when all windows close, so a
            // lingering spare keeps it alive after the user closes the real
            // windows. Drop the empty spare and stale tear state on any close.
            if MainWindow.spareReceiver === self {
                MainWindow.spareReceiver = nil
                MainWindow.pendingTearOut = nil
            } else if let spare = MainWindow.spareReceiver, spare.hasNoTabs {
                MainWindow.spareReceiver = nil
                MainWindow.pendingTearOut = nil
                try? spare.close()
            }

            // 先 cancel observation task，避免死窗口的 task 继续访问 self.appWindow / self.viewModel
            self.envObservationTask?.cancel()
            self.envObservationTask = nil

            if !self.suppressLayoutPersistence {
                self.viewModel.windowLayout.navigationViewPaneOpen = self.navigationView.isPaneOpen
                self.viewModel.windowLayout.navigationViewOpenPaneLength = self.navigationView.openPaneLength
            }
            self.viewModel = nil
        }
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

        let context = WindowContext(owner: self)
        titleBarRightHeader.children.clear()
        navigationView.menuItems.clear()
        navigationView.footerMenuItems.clear()
        for module in App.context.modules {
            if let item = module.titleBarRightHeaderItem(in: context) {
                titleBarRightHeader.children.append(item)
            }
            for item in module.navigationViewMenuItems(in: context) {
                appendNavigationItem(item, false)
            }
            for item in module.navigationViewFooterMenuItems(in: context) {
                appendNavigationItem(item, true)
            }
        }

        // An empty tear-out receiver: the torn tab is injected later by
        // tabTearOutRequested, so skip all startup navigation and come up blank.
        if awaitTransferredTab {
            return
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

        // Taskbar "New Window" / --new-window: skip currentPage/lastPageURL,
        // force-select the first NavigationView item (Home) without polluting
        // routePreferences.
        if forceHomeOnLaunch {
            forceHomeOnLaunch = false
            navigationView.selectFirstItem()
            return
        }

        if let page = currentPage {
            navigate(to: page)
        } else if let lastURL = viewModel.routePreferences.lastPageURL, navigate(to: lastURL) {
            return
        } else {
            navigationView.selectFirstItem()
        }
    }
}
