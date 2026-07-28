import Foundation
import UWP
import WinAppSDK
import WinUI

@testable import RsUI

/// 独立的 `WinUI.TabView` + `PageFrame` 手测窗口，抛开 MainWindow / Module /
/// WindowContext。
///
/// 三点结构（修复三类先前问题）：
///
/// 1. **TabView 作为窗口顶层控件** —— `window.content = tabView`，不再被塞进
///    子 Grid 行里。
///
/// 2. **顶部可拖动** —— `extendsContentIntoTitleBar = true` 之后必须用
///    `window.setTitleBar(<region>)` 注册一块 drag region；否则系统标题栏
///    隐藏后顶部无拖动区，启动时窗口无法拖动。这里按 Microsoft Learn 的
///    TabView 文档推荐做法：把一个透明 `Grid` 放在 `tabView.tabStripFooter`，
///    调 `setTitleBar` 把它注册为窗口 drag region。Strip 上的 tab 不受影响
///    （drag region 只占 strip footer 区域），并预留 `minWidth = 188` 保证有
///    足够拖动空间。
///
/// 3. **每个 TabViewItem 自带工具条 + PageFrame** —— `TabViewItem.content`
///    是一个 `Grid{ Row0 工具条, Row1 PageFrame }`。Back / Forward / +String /
///    +UIElem / +NilHdr / +Nav 全部作用于本 Tab 的 PageFrame，与窗口级选中
///    状态解耦；新 Page 只进入本 Tab 的导航栈。
final class TabViewPageFrameTestWindow: Window {
    // 中枢：strip 是数量/顺序/选中的真理来源，frame 由 name 索引跟随 strip
    // （WinRT 投影里 TabViewItem 的 `===` 不稳，故按 name 索引）。
    private var tabView: TabView!
    // 成为 window 的 title-bar drag region（TabStripFooter）。
    private var dragRegion: Grid!
    private var framesByName: [String: PageFrame] = [:]
    // 程序化选中时挂起 selectionChanged，避免重复处理（参照 MainWindow 的
    // isSyncingTabSelection）。
    private var isSyncingSelection = false
    // 首次导航帧抑制进入动画（参照 MainWindow.isFirstNavigation）。
    private var isFirstNavigation = true
    // 跨 tab 全局递增，保证 Tab #N / Page #N 编号唯一，便于肉眼区分。
    private var counter = 0

    override init() {
        // TabView 顶层内容 + drag region，必须在 super.init() 之前成型。
        tabView = TabView()
        tabView.isAddTabButtonVisible = true
        tabView.tabWidthMode = .sizeToContent
        tabView.closeButtonOverlayMode = .onPointerOver
        tabView.canDragTabs = true
        tabView.canReorderTabs = true
        tabView.canTearOutTabs = false
        tabView.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        tabView.margin = Thickness(left: 0, top: -1, right: 0, bottom: 0)

        // 透明 Grid 作为 strip footer / drag region。MinWidth=188 是 Microsoft
        // Learn TabView 文档建议的最小可拖动宽度。
        dragRegion = Grid()
        dragRegion.minWidth = 188
        tabView.tabStripFooter = dragRegion

        super.init()
        title = "TabView PageFrame Test"
        extendsContentIntoTitleBar = true
        appWindow.titleBar.preferredHeightOption = .tall
        content = tabView
        // 把 drag region 注册到 window 之后，整个 strip footer 区域可拖动
        // （含启动首帧、Strip 无 tab 的情形）。
        try? setTitleBar(dragRegion)

        // 只接窗口级事件：strip 选中切换无窗口级状态可刷新（状态在每 Tab 内
        // 自维护），新建 tab ＋ 关 tab ＋ 关闭按钮请求仍由窗口统筹。
        tabView.addTabButtonClick.addHandler { [weak self] _, _ in
            self?.addDefaultTabTapped()
        }
        tabView.tabCloseRequested.addHandler { [weak self] _, args in
            guard let self, let args, let item = args.tab else { return }
            self.closeTab(for: item)
        }
        tabView.selectionChanged.addHandler { _, _ in
            // 内容切换由 TabView native 处理；窗口级无状态可同步。
        }

        Task { @MainActor in
            let homePage = makePage(
                name: "Home", headerKind: .string, effect: .fromBottom
            )
            _ = addTab(
                page: homePage,
                tabHeader: "Home",
                transitionInfoOverride: NavigationTransitionInfo.make(
                    slideEffect: .fromBottom)
            )
        }
    }

    // MARK: - Cold start: drag region already wired in init; nothing else needed.

    // MARK: - Tab lifecycle

    /// 新建一个 tab：建 model → 建 PageFrame → 建 TabViewItem，content 设为
    /// "工具条 + PageFrame" 复合容器，插入 strip，渲染首页并按需要切到新 tab。
    @discardableResult
    private func addTab(
        page: RsUI.Page,
        tabHeader: String,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> TabViewItem? {
        let model = MainWindowTab(page: page, transitionInfoOverride: transitionInfoOverride)
        let frame = PageFrame(model: model)

        let item = TabViewItem()
        item.name = UUID().uuidString
        item.header = tabHeader
        item.minWidth = 100
        // 已有 tab 才允许互关；lone tab 不可关（参照 MainWindow 规则）。
        item.isClosable = !framesByName.isEmpty

        // 复合容器：工具条按钮闭包 capture 本 tab 的 frame，与本 tab 绑定。
        item.content = makeTabContent(frame: frame, tabHeader: tabHeader)
        framesByName[item.name] = frame

        guard let items = tabView.tabItems else { return item }
        items.insertAt(items.size, item)

        // 切到新 tab；isSyncingSelection 屏蔽期间 selectionChanged 不触发。
        isSyncingSelection = true
        tabView.selectedItem = item
        isSyncingSelection = false

        // 首次首页抑制进入动画；后续 tab 顺其自然播放 transitionInfo。
        let firstRender = isFirstNavigation
        isFirstNavigation = false
        let renderOverride: NavigationTransitionInfo? =
            firstRender ? SuppressNavigationTransitionInfo() : nil
        frame.renderCurrentPageIfNeeded(transitionInfoOverride: renderOverride)

        updateClosableStates()
        return item
    }

    /// 关闭一个 tab（≥1 tab 时允许；lone tab isClosable=false）。
    private func closeTab(for item: TabViewItem) {
        guard framesByName.count > 1, framesByName[item.name] != nil else { return }

        let wasSelected = (tabView.selectedItem as? TabViewItem)?.name == item.name

        // 从 strip 移除（按 name 找索引，避免 WinRT 投影 identity 不稳）。
        if let items = tabView.tabItems {
            var i: UInt32 = 0
            while i < items.size {
                if let it = items.getAt(i) as? TabViewItem, it.name == item.name {
                    items.removeAt(i)
                    break
                }
                i += 1
            }
        }

        // 释放对复合容器 + frame 的强引用（闭包随 item.content 一同离开）。
        item.content = nil
        framesByName[item.name] = nil

        // 若关掉的是当前选中 tab，找一个剩余 tab 接管选中。
        if wasSelected, tabView.selectedItem == nil, let next = anyRemainingItem() {
            isSyncingSelection = true
            tabView.selectedItem = next
            isSyncingSelection = false
        }

        updateClosableStates()
    }

    /// 取一个仍未删除的 TabViewItem（strip 顺序）。
    private func anyRemainingItem() -> TabViewItem? {
        guard let items = tabView.tabItems else { return nil }
        var i: UInt32 = 0
        while i < items.size {
            if let it = items.getAt(i) as? TabViewItem {
                return it
            }
            i += 1
        }
        return nil
    }

    /// 全部 tab 关闭按钮态：≥2 才允许关，lone tab 不可关。
    private func updateClosableStates() {
        let canClose = framesByName.count > 1
        guard let items = tabView.tabItems else { return }
        var i: UInt32 = 0
        while i < items.size {
            if let it = items.getAt(i) as? TabViewItem {
                it.isClosable = canClose
            }
            i += 1
        }
    }

    // MARK: - Per-tab content (toolbar + PageFrame)

    /// 构造一个 TabViewItem 的复合 content：Row0 工具条，Row1 PageFrame。
    /// 工具条按钮闭包 capture 本 tab 的 `frame`，所有加页 / Back / Forward
    /// 仅作用于本 frame。
    private func makeTabContent(frame: PageFrame, tabHeader: String) -> Grid {
        let root = (try? XamlReader.load(tabContentXAML)) as! Grid

        // 命名控件：findName 在 XamlReader.Load 返回的根上调用即可访问该 namescope。
        let backButton = (try? root.findName("BackButton")) as? Button
        let forwardButton = (try? root.findName("ForwardButton")) as? Button
        let statusText = (try? root.findName("StatusText")) as? TextBlock

        // 局部刷新该 tab 的工具条状态。闭包 capture frame 与 statusText。
        let updateStatus = { [weak frame] in
            guard let frame else { return }
            let current = frame.currentPage?.title ?? "(empty)"
            statusText?.text = "cur: \(current)"
                + " | back: \(frame.model.backwardPages.count)"
                + " | fwd: \(frame.model.forwardPages.count)"
            backButton?.isEnabled = frame.canGoBack
            forwardButton?.isEnabled = frame.canGoForward
        }

        backButton?.click.addHandler { [weak frame] _, _ in
            guard let frame, frame.canGoBack else { return }
            frame.goBack()
            frame.renderCurrentPageIfNeeded()
            updateStatus()
        }
        forwardButton?.click.addHandler { [weak frame] _, _ in
            guard let frame, frame.canGoForward else { return }
            frame.goForward()
            frame.renderCurrentPageIfNeeded()
            updateStatus()
        }

        for (name, kind) in [
            ("AddStringButton", HeaderKind.string),
            ("AddUIElemButton", HeaderKind.uiElement),
            ("AddNilHdrButton", HeaderKind.nilHeader),
        ] as [(String, HeaderKind)] {
            guard let btn = (try? root.findName(name)) as? Button else { continue }
            btn.click.addHandler { [weak self, weak frame] _, _ in
                guard let self, let frame else { return }
                self.navigateNewPage(into: frame, headerKind: kind)
                updateStatus()
            }
        }

        if let navBtn = (try? root.findName("NavInTabButton")) as? Button {
            // "+Nav in Tab" 与 "+String" 走同一加页路径，便于肉眼遍历 back/forward。
            navBtn.click.addHandler { [weak self, weak frame] _, _ in
                guard let self, let frame else { return }
                self.navigateNewPage(into: frame, headerKind: .string)
                updateStatus()
            }
        }

        // Row1 挂 PageFrame（Grid 子类，可直接 Grid.setRow）。
        root.children.append(frame)
        try? Grid.setRow(frame, 1)

        // 初始状态。
        backButton?.isEnabled = false
        forwardButton?.isEnabled = false
        statusText?.text = "cur: \(frame.currentPage?.title ?? "(empty)")"
            + " | back: 0 | fwd: 0"

        return root
    }

    /// 工具条 + 空 Row1 XAML。每个 TabViewItem 内独立加载，互不影响。
    private var tabContentXAML: String {
        """
        <Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <!-- Row 0: per-tab toolbar -->
            <Border Padding="8,8,8,8" Grid.Row="0">
                <StackPanel Orientation="Horizontal" Spacing="8">
                    <StackPanel Orientation="Horizontal" Spacing="2">
                        <Button Name="BackButton" Width="28" Height="28"
                                MinWidth="0" MinHeight="0" Padding="0,0,0,0"
                                VerticalAlignment="Center">
                            <FontIcon Glyph="&#xE72B;" FontSize="12"/>
                        </Button>
                        <Button Name="ForwardButton" Width="28" Height="28"
                                MinWidth="0" MinHeight="0" Padding="0,0,0,0"
                                VerticalAlignment="Center">
                            <FontIcon Glyph="&#xE72A;" FontSize="12"/>
                        </Button>
                    </StackPanel>
                    <Button Name="AddStringButton" MinHeight="28" Padding="10,4,10,4"
                            VerticalAlignment="Center">
                        <TextBlock Text="+String"/>
                    </Button>
                    <Button Name="AddUIElemButton" MinHeight="28" Padding="10,4,10,4"
                            VerticalAlignment="Center">
                        <TextBlock Text="+UIElem"/>
                    </Button>
                    <Button Name="AddNilHdrButton" MinHeight="28" Padding="10,4,10,4"
                            VerticalAlignment="Center">
                        <TextBlock Text="+NilHdr"/>
                    </Button>
                    <Button Name="NavInTabButton" MinHeight="28" Padding="10,4,10,4"
                            VerticalAlignment="Center">
                        <TextBlock Text="+Nav"/>
                    </Button>
                    <TextBlock Name="StatusText" Margin="12,0,12,0" VerticalAlignment="Center"/>
                </StackPanel>
            </Border>
        </Grid>
        """
    }

    // MARK: - Navigation helper

    /// 在指定 frame 上 navigate 一个新 Page（新 page 加入该 frame 的栈）。
    private func navigateNewPage(into frame: PageFrame, headerKind: HeaderKind) {
        counter += 1
        let n = counter
        let pageName = "Page #\(n)"
        // 循环改变方向以便肉眼分辨转场动画。
        let effect: SlideNavigationTransitionEffect
        switch n % 3 {
        case 0: effect = .fromBottom
        case 1: effect = .fromRight
        default: effect = .fromLeft
        }
        let page = makePage(name: pageName, headerKind: headerKind, effect: effect)
        frame.navigate(
            to: page,
            transitionInfoOverride: NavigationTransitionInfo.make(slideEffect: effect),
            maxHistoryPages: 64
        )
        frame.renderCurrentPageIfNeeded()
    }

    // MARK: - Strip "+ tab" button

    /// Strip 右上角 "+" 按钮：新建一个带默认 String-header Home 的 tab。
    private func addDefaultTabTapped() {
        counter += 1
        let n = counter
        let tabHeader = "Tab #\(n)"
        let page = makePage(
            name: "Home \(n)", headerKind: .string, effect: .fromBottom
        )
        _ = addTab(
            page: page,
            tabHeader: tabHeader,
            transitionInfoOverride: NavigationTransitionInfo.make(slideEffect: .fromBottom)
        )
    }
}
