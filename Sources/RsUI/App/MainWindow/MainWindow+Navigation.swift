import Foundation
import WindowsFoundation
import UWP
import WinUI

extension MainWindow {
    func navigate(
        to page: Page,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) {
        let effective = resolveOpenMode(mode)
        performNavigate(to: page, mode: effective, transitionInfoOverride: transitionInfoOverride)
    }

    @discardableResult
    func navigate(
        to url: URL,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> Bool {
        let effective = resolveOpenMode(mode)
        return performNavigate(to: url, mode: effective, transitionInfoOverride: transitionInfoOverride)
    }

    /// NavigationViewItem 上 Ctrl+click 设置的 `openInNewTabRequested` 标记会把
    /// `.inplace` 升级为 `.newTab`；调用者显式指定的非 inplace 模式不被覆盖。
    private func resolveOpenMode(_ requested: NavigationOpenMode) -> NavigationOpenMode {
        let flag = openInNewTabRequested
        openInNewTabRequested = false
        if requested == .inplace && flag {
            return .newTab
        }
        return requested
    }

    private func performNavigate(
        to page: Page,
        mode: NavigationOpenMode,
        transitionInfoOverride: NavigationTransitionInfo?
    ) {
        switch mode {
        case .newWindow:
            MainWindow.openDetachedWindow(opening: page, transitionInfoOverride: transitionInfoOverride)
        case .inplace:
            navigateInSelectedTab(to: page, transitionInfoOverride: transitionInfoOverride)
        case .newTab:
            addTab(page: page, switchToTab: true, transitionInfoOverride: transitionInfoOverride)
        case .newTabBackground:
            addTab(page: page, switchToTab: false, transitionInfoOverride: transitionInfoOverride)
        }
    }

    // In-place navigation: push onto the selected tab's history. With no tab yet
    // (first navigation / restore), the page opens a new tab instead.
    private func navigateInSelectedTab(
        to page: Page,
        transitionInfoOverride: NavigationTransitionInfo?
    ) {
        guard let ctx = selectedTabContext else {
            addTab(page: page, switchToTab: true, transitionInfoOverride: transitionInfoOverride)
            return
        }
        ctx.frame.navigate(
            to: page,
            transitionInfoOverride: transitionInfoOverride,
            maxHistoryPages: viewModel.routePreferences.maxHistoryPages
        )
        renderSelectedTab()
    }

    @discardableResult
    private func performNavigate(
        to url: URL,
        mode: NavigationOpenMode,
        transitionInfoOverride: NavigationTransitionInfo?
    ) -> Bool {
        if mode == .newWindow {
            MainWindow.openDetachedWindow(navigatingTo: url, transitionInfoOverride: transitionInfoOverride)
            return true
        }
        // 仅在 inplace 模式下短路；其他模式（newTab / newTabBackground）允许重复打开同 URL
        if mode == .inplace, currentPage?.url == url {
            return true
        }

        guard let page = resolvePage(for: url) else { return false }
        performNavigate(to: page, mode: mode, transitionInfoOverride: transitionInfoOverride)
        return true
    }

    // Resolves a route URL to a Page via Settings or a registered module, without
    // performing any navigation. Returns nil when no module claims the URL. The
    // batch tab APIs reuse this so a list of URLs can be turned into pages up front.
    func resolvePage(for url: URL) -> Page? {
        if url == SettingsPage.url {
            return SettingsPage()
        }
        let context = WindowContext(owner: self)
        for module in App.context.modules {
            if let page = module.onNavigationRequested(for: url, in: context) {
                return page
            }
        }
        return nil
    }


    func firstNavigationItemURL() -> URL? {
        return firstNavigationItemURL(in: navigationView.menuItems)
            ?? firstNavigationItemURL(in: navigationView.footerMenuItems)
    }

    private func firstNavigationItemURL(in items: AnyIVector<Any?>?) -> URL? {
        guard let items else { return nil }

        for item in items {
            guard let navItem = item as? NavigationViewItem else { continue }
            if
                let tag = navItem.tag,
                let str = tag as? HString,
                let url = URL(string: String(hString: str)) {
                return url
            }
            if let url = firstNavigationItemURL(in: navItem.menuItems) {
                return url
            }
        }

        return nil
    }

    func syncNavigationSelection(for url: URL) {
        isSyncingSelection = true
        defer { isSyncingSelection = false }
        
        navigationView.selectItem(with: url)
    }

    private func captureOpenInNewTabRequested(_ args: PointerRoutedEventArgs?) {
        guard let args = args else { return }
        let rawValue = Int(args.keyModifiers.rawValue)
        openInNewTabRequested = (rawValue & 0x1) != 0
    }

    func appendNavigationItem(_ item: NavigationViewItemBase, _ isFooter: Bool) {
        item.pointerPressed.addHandler { [weak self, weak item] _, args in
            guard let self else { return }
            self.captureOpenInNewTabRequested(args)
            guard self.openInNewTabRequested, let item else { return }
            self.openSelectedNavigationItemInNewTabIfNeeded(item, args)
        }
        if isFooter {
            navigationView.footerMenuItems.append(item)
        } else {
            navigationView.menuItems.append(item)
        }
    }

    private func openSelectedNavigationItemInNewTabIfNeeded(_ item: NavigationViewItemBase, _ args: PointerRoutedEventArgs?) {
        guard isNavigationItemSelected(item), let url = url(for: item) else { return }

        args?.handled = true
        openInNewTabRequested = false

        let queued = (try? dispatcherQueue?.tryEnqueue { [weak self] in
            guard let self else { return }
            _ = self.navigate(
                to: url,
                mode: .newTab,
                transitionInfoOverride: SuppressNavigationTransitionInfo()
            )
        }) ?? false

        if !queued {
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = self.navigate(
                    to: url,
                    mode: .newTab,
                    transitionInfoOverride: SuppressNavigationTransitionInfo()
                )
            }
        }
    }

    private func isNavigationItemSelected(_ item: NavigationViewItemBase) -> Bool {
        guard let selectedItem = navigationView.selectedItem as? NavigationViewItemBase else { return false }
        return selectedItem === item
    }

    private func url(for item: NavigationViewItemBase) -> URL? {
        guard
            let navItem = item as? NavigationViewItem,
            let tag = navItem.tag,
            let str = tag as? HString
        else {
            return nil
        }

        return URL(string: String(hString: str))
    }
}
