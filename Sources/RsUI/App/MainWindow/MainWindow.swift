import Foundation
import Observation
import UWP
import WinAppSDK
import WinUI
import WindowsFoundation

private func tr(_ keyAndValue: String) -> String {
    return App.context.tr(keyAndValue)
}

/// 主窗口壳：`NavigationViewWindow` + 一个 `PageControl (PageTabView)` 作为内容容器。
///
/// 本类主要功能在于处理导航URL与Page对象的映射，并协调UI元素的显示。
///
/// 提供context接口用于隔离窗口具体类型。
class MainWindow: NavigationViewWindow, WindowContextHost {
    private var context: WindowContext {
        WindowContext(host: self)
    }
    private lazy var pageControl = PageTabView()

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

            if let page = pageControl.currentPage {
                ui.navigationView.selectItem(with: page.url)
            }
        }
        fullscreenChanged.addHandler { [weak self] _, arg in
            self?.pageControl.updateFullscreen(arg)
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
                _ = self?.context.open(
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

        bindPageControlEvents()
    }

    private func bindPageControlEvents() {
        // PageTabView 自管 strip：selectionChanged / tabCloseRequested / addTabButtonClick
        // 已在控件内部 wire。宿主只需挂 onPageChanged / onCleared 同步 NavView 选中 +
        // 写 lastPageURL + 刷新 back/forward 按钮态，替代旧 renderSelectedTab 末尾刷新。
        pageControl.onPageChanged = { [weak self] _, _, page in
            guard let self else { return }
            self.ui.navigationView.header = nil
            self.ui.navigationView.selectItem(with: page.url)
            self.ui.backButton.isEnabled = self.pageControl.canGoBack
            self.ui.forwardButton.isEnabled = self.pageControl.canGoForward
            App.context.route.lastPageURL = page.url
        }
        pageControl.onCleared = { [weak self] _, _ in
            guard let self else { return }
            self.ui.navigationView.header = nil
            self.ui.backButton.isEnabled = false
            self.ui.forwardButton.isEnabled = false
        }

        // strip "+" 的 page 来源：返回首个 NavView 项的 URL，否则 Settings。
        pageControl.setAddTabProvider { [weak self] in
            guard let self else { return (SettingsPage(), tr("Settings")) }
            if let url = self.ui.navigationView.firstItemURL {
                let page = self.context.resolvePage(from: url) ?? SettingsPage()
                return (page, page.title)
            }
            return (SettingsPage(), tr("Settings"))
        }
    }

    // MARK: WindowContextHost protocol

    var hwnd: WindowId { self.appWindow.id }
    var currentPageControl: any PageControl { pageControl }
}
