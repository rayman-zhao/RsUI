import Foundation
import UWP
import WinAppSDK
import WinUI
import WindowsFoundation

/// 组合 `WinUI.TabView`（仅作 tab strip）与一个共享 `PageFrame`（一个 frame，
/// 切 tab 时通过 `PageFrame.rebind(to:)` 复用）的可复用控件，等同 AGENTS.md
/// "Core UI Composition Model" §4 所述的 `RsUI.TabView`。
///
/// 与 `MainWindow` 现有 frame-per-tab 实现、以及 `TabViewPageFrameTestWindow`
/// 的 frame-into-`TabViewItem.content` 实现的两点关键差异：
///
/// 1. **单 `PageFrame`** —— 全部 tab 共享同一个 frame + 它内部的
///    `PageTransitionHost`。切 tab 时调 `PageFrame.rebind(to:)`，把 frame 的
///    model 重设到目标 tab 的 `PageModel` 并即时渲染（Suppress 转场）。每个
///    tab 的导航栈仍由各自的 `PageModel` 独立持有，只是渲染管线复用同一份。
/// 2. **TabStrip ≤1 page 自动隐藏** —— page 内容位于共享 frame（Grid 的 Row1），
///    而非 `TabViewItem.content`，故隐藏整个 `TabView` 时内容仍显示。单 tab 窗
///    口看起来就是一个普通的 `PageFrame`，没有 strip 痕迹。
///
/// 本类自身为 `Grid`（2 行：strip / 内容），可直接 `window.content = pageTabView`
/// 或塞进任意 WinUI 容器。
class PageTabView: Grid, PageControl {
    var tabCount: Int { return tabView.tabItems.count }

    // WinUI.TabView 自身：只作 strip（行内不可见性的隐藏区 + 各 TabViewItem）。
    private let tabView: TabView
    private let closeOthersButton: Button
    // 全部 tab 共享的单 PageFrame，strip 隐藏后内容仍由它显示。
    private let pageFrame = PageFrame()

    // MARK: - Init

    override init() {
        tabView = (try? XamlReader.load(xamlUI)) as! TabView
        closeOthersButton = (try? tabView.findName("closeOthersButton")) as! Button

        super.init()
        let autoRow = RowDefinition()
        autoRow.height = GridLength(value: 0, gridUnitType: .auto)
        let starRow = RowDefinition()
        starRow.height = GridLength(value: 1, gridUnitType: .star)
        rowDefinitions.append(autoRow)
        rowDefinitions.append(starRow)

        children.append(tabView)
        try? Grid.setRow(tabView, 0)
        children.append(pageFrame)
        try? Grid.setRow(pageFrame, 1)

        bindEvents()
    }

    private func bindEvents() {
        tabView.selectionChanged.addHandler { [weak self] _, _ in
            guard let self else { return }
            guard let item = self.tabView.selectedItem as? TabViewItem else { return }
            guard let model = item.tag as? PageModel else { return }

            self.pageFrame.rebind(to: model)
        }
        tabView.tabCloseRequested.addHandler { sender, args in
            guard let sender, let args else { return }
            guard let closingTab = args.tab, let tabs = sender.tabItems else { return }

            var idx: UInt32 = 0
            if tabs.indexOf(closingTab, &idx) {
                tabs.removeAt(idx)
            }

            sender.visibility = sender.tabItems.count > 1 ? .visible : .collapsed
        }
        tabView.addTabButtonClick.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.tabView.selectedItem = self.addTabItems(with: [nil])
        }
        closeOthersButton.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            guard let item = self.tabView.selectedItem else { return }
            guard let index = self.tabView.tabItems.index(of: item) else { return }

            for i in stride(from: self.tabView.tabItems.count - 1, through: 0, by: -1) {
                if i != index {
                    self.tabView.tabItems.removeAt(UInt32(i))
                }
            }
            self.tabView.visibility = .collapsed
        }
        pageFrame.pageChanged.addHandler { [weak self] _, page in
            guard let self, let item = self.tabView.selectedItem as? TabViewItem else { return }

            item.header = page?.title
        }
    }

    // MARK: - PageControl conformance

    var currentPage: Page? { pageFrame.currentPage }
    var canGoBack: Bool { pageFrame.canGoBack }
    var canGoForward: Bool { pageFrame.canGoForward }

    var rootView: FrameworkElement { self }
    var fullscreenView: UIElement { pageFrame.fullscreenView }

    var pageChanged: EventWithArgumentHandler<PageControl, Page?> { pageFrame.pageChanged }

    func goBack() { pageFrame.goBack() }
    func goForward() { pageFrame.goForward() }

    func navigate(
        to page: Page,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo = SuppressNavigationTransitionInfo()
    ) {
        if self.tabView.tabItems.count == 0 {
            let item = addTabItems(with: [page])
            pageFrame.rebind(to: item.tag as! PageModel)  // The very first item will not fire selection changed event, have to do it manually.
        } else if case .inplace = mode {
            pageFrame.navigate(to: page, mode: mode, transitionInfoOverride: transitionInfoOverride)
        } else {
            let item = addTabItems(with: [page])
            if case .newTab = mode {
                tabView.selectedItem = item
            }
        }
    }

    func navigate(
        to pages: [Page],
        mode: NavigationOpenMode = .newTab,
        transitionInfoOverride: NavigationTransitionInfo = SuppressNavigationTransitionInfo()
    ) -> Int {
        if case .inplace = mode {
            if self.tabView.tabItems.count == 0 {
                _ = addTabItems(with: [nil])
            }
            _ = pageFrame.navigate(
                to: pages, mode: mode, transitionInfoOverride: transitionInfoOverride)
        } else {
            let item = addTabItems(with: pages)
            if case .newTab = mode {
                tabView.selectedItem = item
            }
        }
        return tabCount
    }

    func selectPage(matchingURL url: URL) -> Bool {
        for item in tabView.tabItems {
            if let tabViewItem = item as? TabViewItem, let tag = tabViewItem.tag,
                let model = tag as? PageModel, model.currentPage?.url == url
            {
                tabView.selectedItem = item
                return true
            }
        }
        return false
    }

    func updateAppearance() {
        try? ToolTipService.setToolTip(closeOthersButton, App.context.tr("CloseOthers"))

        for item in tabView.tabItems {
            if let tabViewItem = item as? TabViewItem, let tag = tabViewItem.tag,
                let model = tag as? PageModel, let page = model.currentPage
            {
                tabViewItem.header = page.title
            }
        }

        pageFrame.updateAppearance()
    }

    func updateWindowContext(_ context: WindowContext) {
        for item in tabView.tabItems {
            if let tabViewItem = item as? TabViewItem, let tag = tabViewItem.tag,
                let model = tag as? PageModel
            {
                model.currentPage?.windowContextDidChange(to: context)
                for page in model.backwardPages + model.forwardPages {
                    page.windowContextDidChange(to: context)
                }
            }
        }
    }

    private func addTabItems(with pages: [Page?]) -> TabViewItem {
        for page in pages {
            let item = TabViewItem()
            item.minWidth = 120
            if let page {
                item.header = page.title
                item.tag = PageModel(page: page)
            } else {
                item.tag = PageModel()
            }

            tabView.tabItems.append(item)
        }

        tabView.closeButtonOverlayMode = .onPointerOver  // Have to reset the mode, otherwise item become display close button.
        tabView.visibility = tabView.tabItems.count > 1 ? .visible : .collapsed
        let lastIndex = tabView.tabItems.count - 1
        let lastItem = tabView.tabItems[lastIndex] as! TabViewItem
        if tabView.selectedItem == nil {
            tabView.selectedItem = lastItem
        }
        return lastItem
    }
}

private var xamlUI: String {
    """
    <!-- Keep native TabView tear-out disabled for now. CanTearOutTabs currently
        has two blocking issues for this shell:
        - TabTearOutWindowRequested can make the receiver window visible briefly,
        causing flicker and taskbar animation.
        https://github.com/microsoft/microsoft-ui-xaml/issues/10155
        - With a custom title bar, switching tabs can corrupt the drag region so
        dragging the title bar tears out a tab instead of moving the window.
        https://github.com/microsoft/microsoft-ui-xaml/issues/11170
        Self-hosts the single place controlling `canTearOutTabs` of the inner strip.
        The actual cross-window tear-out handlers / pending state still live in
        `MainWindow` (`configureTabTearOutEvents`), gated on this same flag — the
        flow is inherently cross-window (creates a receiver window, moves the model
        between windows), so a windowless control can't own it yet. When the WinUI
        bugs are fixed, flip this flag in one place. -->
    <TabView
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:primitives="using:Microsoft.UI.Xaml.Controls.Primitives" 
        Name="tabView"
        IsAddTabButtonVisible="True"
        TabWidthMode="SizeToContent"
        CloseButtonOverlayMode="OnPointerOver"
        CanDragTabs="True"
        CanReorderTabs="True"
        CanTearOutTabs="False"
        Padding="0,0,0,0" Margin="0,-1,0,0"
        Visibility="Collapsed" >
        <!-- 禁用Tab新增删除动画。TransitionCollection 空集合，禁用所有项容器动画 -->
        <TabView.Resources>
            <Style TargetType="primitives:TabViewListView">
                <Setter Property="ItemContainerTransitions">
                    <Setter.Value>
                        <TransitionCollection />
                    </Setter.Value>
                </Setter>
            </Style>
        </TabView.Resources>
        <TabView.TabStripHeader>
            <Button Name="closeOthersButton"
                CornerRadius="{StaticResource ControlCornerRadius}"
                Padding="8,4,8,4" Margin="4,0,0,0">
                <FontIcon Glyph="&#xF166;" FontSize="14" />
            </Button>
        </TabView.TabStripHeader>
    </TabView>
    """
}
