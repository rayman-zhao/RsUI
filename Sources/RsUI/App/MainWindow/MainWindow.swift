import Foundation
import UWP
import WinAppSDK

/// 主窗口壳：`NavigationViewWindow` + 一个 `PageControl (PageTabView)` 作为内容容器。
///
/// 本类主要功能在于处理导航URL与Page对象的映射，并协调UI元素的显示。
///
/// 提供context接口用于隔离窗口具体类型。
class MainWindow: NavigationViewWindow, WindowContextHost {
    private lazy var context = WindowContext(host: self)
    private lazy var pageControl: PageControl = PageTabView()

    // MARK: - Init

    init(url: URL? = nil, forceMinimalMode: Bool = false) {
        super.init(forceMinimalMode)
        useMicaBackdrop()
        useRestoration()

        setupUI()
        bindEvents()

        Task { @MainActor [weak self] in
            guard let self else { return }

            if let url, self.context.open(url) {
                return
            } else if let home = self.ui.navigationView.firstItemURL {
                self.context.open(home)
            }
        }
    }

    private func setupUI() {
        ui.navigationView.header = nil
        ui.navigationView.content = pageControl
        ui.backButton.isEnabled = false
        ui.forwardButton.isEnabled = false
    }

    private func bindEvents() {
        self.appearanceChanged.addHandler { [weak self] _ in
            guard let self else { return }

            ui.titleBarRightHeader.children.clear()
            ui.navigationView.menuItems.clear()
            ui.navigationView.footerMenuItems.clear()
            let context = self.context
            for module in App.context.modules {
                if let item = module.titleBarRightHeaderItem(in: context) {
                    ui.titleBarRightHeader.children.append(item)
                }
                for item in module.navigationViewMenuItems(in: context) {
                    ui.navigationView.menuItems.append(item)
                }
                for item in module.navigationViewFooterMenuItems(in: context) {
                    ui.navigationView.footerMenuItems.append(item)
                }
            }
            self.pageControl.updateAppearance()

            if let url = pageControl.currentPage?.url {
                ui.navigationView.selectItem(with: url)
            }
        }
        fullscreenChanged.addHandler { [weak self] _, _ in
            guard let self else { return }

            self.pageControl.updateWindowContext(self.context)
        }

        ui.navigationView.itemInvoked.addHandler { [weak self] _, arg in
            guard let self, let arg,
                let url = arg.isSettingsInvoked ? SettingsPage.url : arg.invokedItemContainer?.url
            else {
                return
            }

            let ctrlState =
                (try? InputKeyboardSource.getKeyStateForCurrentThread(VirtualKey.control)) ?? .none
            let ctrlDown =
                ctrlState.rawValue & CoreVirtualKeyStates.down.rawValue
                == CoreVirtualKeyStates.down.rawValue
            guard ctrlDown || url != pageControl.currentPage?.url else { return }

            Task { @MainActor [weak self] in
                self?.context.open(
                    url, mode: ctrlDown ? .newTabNoFocus : .inplace,
                    transitionInfoOverride: arg.recommendedNavigationTransitionInfo)
            }
        }
        ui.backButton.click.addHandler { [weak self] _, _ in
            self?.pageControl.goBack()
        }
        ui.forwardButton.click.addHandler { [weak self] _, _ in
            self?.pageControl.goForward()
        }

        pageControl.pageChanged.addHandler { [weak self] _, page in
            guard let self else { return }

            if let page {
                self.ui.navigationView.selectItem(with: page.url)
                self.ui.backButton.isEnabled = self.pageControl.canGoBack
                self.ui.forwardButton.isEnabled = self.pageControl.canGoForward

                App.context.route.lastPageURL = page.url
            } else {
                self.ui.backButton.isEnabled = false
                self.ui.forwardButton.isEnabled = false
                if let home = self.ui.navigationView.firstItemURL {
                    self.context.open(home)
                }
            }
        }
    }

    // MARK: WindowContextHost protocol

    var hwnd: WindowId { self.appWindow.id }
    var currentPageControl: any PageControl { pageControl }
}
