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
///    model 重设到目标 tab 的 `MainWindowTab` 并即时渲染（Suppress 转场）。每个
///    tab 的导航栈仍由各自的 `MainWindowTab` 独立持有，只是渲染管线复用同一份。
/// 2. **TabStrip ≤1 page 自动隐藏** —— page 内容位于共享 frame（Grid 的 Row1），
///    而非 `TabViewItem.content`，故隐藏整个 `TabView` 时内容仍显示。单 tab 窗
///    口看起来就是一个普通的 `PageFrame`，没有 strip 痕迹。
///
/// 本类自身为 `Grid`（2 行：strip / 内容），可直接 `window.content = pageTabView`
/// 或塞进任意 WinUI 容器。它只暴露 add/close/select 与"作用于当前 tab"导航的
/// 入口；具体 Page 的 header/content 由父层通过 `addTab` 注入。
class PageTabView: Grid {
    // Keep native TabView tear-out disabled for now. CanTearOutTabs currently
    // has two blocking issues for this shell:
    // - TabTearOutWindowRequested can make the receiver window visible briefly,
    //   causing flicker and taskbar animation.
    //   https://github.com/microsoft/microsoft-ui-xaml/issues/10155
    // - With a custom title bar, switching tabs can corrupt the drag region so
    //   dragging the title bar tears out a tab instead of moving the window.
    //   https://github.com/microsoft/microsoft-ui-xaml/issues/11170
    // Self-hosts the single place controlling `canTearOutTabs` of the inner strip.
    // The actual cross-window tear-out handlers / pending state still live in
    // `MainWindow` (`configureTabTearOutEvents`), gated on this same flag — the
    // flow is inherently cross-window (creates a receiver window, moves the model
    // between windows), so a windowless control can't own it yet. When the WinUI
    // bugs are fixed, flip this flag in one place.
    static let tabTearOutEnabled = false

    // MARK: - Bridging context

    /// 一个 strip item 到其导航 model 的桥接。注意：与 `MainWindow.TabContext`
    /// 不同，这里**不**持 per-tab `PageFrame` —— 全部 tab 共享 `pageTabView`
    /// 拥有的单 `sharedFrame`，切 tab 时把 frame 的 model 重绑到本 ctx 的 model。
    final class TabContext {
        let model: MainWindowTab
        let item: TabViewItem
        var title: String?
        var isClosable: Bool?

        init(model: MainWindowTab, item: TabViewItem) {
            self.model = model
            self.item = item
        }
    }

    // MARK: - Stored state

    // WinUI.TabView 自身：只作 strip（行内不可见性的隐藏区 + 各 TabViewItem）。
    private let tabView: TabView
    // 全部 tab 共享的单 PageFrame，strip 隐藏后内容仍由它显示。
    let sharedFrame: PageFrame
    // 切换 TabView 时使用 Suppress 转场：transitionInfo == nil 的 rebind，row 索引在此。
    private let contentRow: Int32 = 1

    // 按 `item.name` 索引（WinRT 投影里 TabViewItem 的 `===` 不稳，故按 name）。
    private var tabContextsByName: [String: TabContext] = [:]
    // 当前已被渲染进 sharedFrame 的 tab name，避免重复 rebind（切到已在显示的 tab）。
    private var visibleTabName: String?
    // 程序化选中（selectItem / insertItem）期间挂起 selectionChanged。
    private var isSyncingSelection = false
    // 首次进入帧抑制进入动画（参照 MainWindow.isFirstNavigation）。
    private var isFirstNavigation = true
    // 每个栈允许保留的最大历史页数。
    private let maxHistoryPages: Int
    // strip "+" 按钮的 page 来源；由宿主通过 setAddTabProvider 设置。
    // private var addNewTabProvider: (() -> (Page, String))?

    // strip 左侧"关闭其它 tab"按钮（图标按钮，挂 tabStripHeader）；当 strip 在
    // tabCount ≤1 整体收起时随之隐藏（参照 MainWindow.closeOtherTabsButton）。
    private lazy var closeOthersButton: Button = makeCloseOthersButton()

    let pageChanged: EventWithArgumentHandler<PageControl, Page?> = EventWithArgumentHandler<
        PageControl, Page?
    >()

    // MARK: - Init

    init(maxHistoryPages: Int = App.context.route.maxHistoryPages) {
        self.tabView = TabView()
        self.sharedFrame = PageFrame(model: MainWindowTab())
        self.maxHistoryPages = maxHistoryPages
        super.init()

        configureTabView()
        configureSharedFrame()
        assembleGrid()
        wireTabViewEvents()
    }

    // MARK: - Public API

    /// 全部 tab 的数量。
    var tabCount: Int { tabContextsByName.count }

    /// 当前选中 tab 的 model（无选中时为 nil）。
    var selectedTabModel: MainWindowTab? { selectedTabContext?.model }

    /// 当前选中 tab 的 page（由共享 frame 当前展示；切换瞬间可能为 nil）。
    var currentPage: Page? { selectedTabModel?.currentPage }

    /// 当前共享 frame 是否能 Back/Forward（作用于当前选中 tab 的栈）。
    var canGoBack: Bool { selectedTabModel.map { !$0.backwardPages.isEmpty } ?? false }
    var canGoForward: Bool { selectedTabModel.map { !$0.forwardPages.isEmpty } ?? false }

    /// 当前选中 tab 的当前页的 header/title（shell 可用来同步外部 UI）。
    var currentPageTitle: String? { selectedTabModel?.currentPage?.title }

    /// 当前选中 ctx，按 selected item 的 name 解析。
    var selectedTabContext: TabContext? {
        guard let item = tabView.selectedItem as? TabViewItem else { return nil }
        return tabContextsByName[item.name]
    }

    /// strip 顺序中的全部 ctx（tabView.tabItems 是权威排序，含 drag-reorder 后）。
    var orderedTabContexts: [TabContext] {
        guard let items = tabView.tabItems else { return [] }
        var result: [TabContext] = []
        var i: UInt32 = 0
        while i < items.size {
            if let item = items.getAt(i) as? TabViewItem,
                let ctx = tabContextsByName[item.name]
            {
                result.append(ctx)
            }
            i += 1
        }
        return result
    }

    /// 注册 strip 顶部"+"按钮的 page 来源。宿主提供返回 `(Page, tabHeader)`。
    // func setAddTabProvider(_ provider: @escaping () -> (Page, String)) {
    //     addNewTabProvider = provider
    // }

    /// shell 在 page 渲染后回调（更新 external 同步、写 lastPageURL 等）。在主线程触发。
    // var onPageChanged: ((PageTabView, TabContext, Page) -> Void)?
    /// shell 在当前 page 被清空时回调（如内容退出动画）。
    // var onCleared: ((PageTabView, TabContext) -> Void)?

    // MARK: - Tab lifecycle

    /// 新建一个 tab：建 model → 建 TabViewItem → 插入 strip → 选中并渲染。
    /// `switchToTab=false` 用于背景加 tab（不切走焦点）；背景 tab 的 frame 渲染
    /// 延迟到首次被选中时由 `applyTab` 触发，符合 `MainWindow.addTabs` 批处理。
    @discardableResult
    func addTab(
        page: Page?,
        header tabHeader: String?,
        transitionInfoOverride: NavigationTransitionInfo? = nil,
        at index: Int? = nil,
        switchToTab: Bool = true
    ) -> TabContext {
        let model =
            page != nil
            ? MainWindowTab(page: page!, transitionInfoOverride: transitionInfoOverride)
            : MainWindowTab()
        let item = TabViewItem()
        item.name = UUID().uuidString
        item.header = tabHeader ?? ""
        item.minWidth = 100
        // 已有 tab 才允许互关；lone tab 不可关（参照 MainWindow 规则）。
        item.isClosable = !tabContextsByName.isEmpty

        let ctx = TabContext(model: model, item: item)
        tabContextsByName[item.name] = ctx
        updateTabTitle(ctx)

        insertItem(item, at: index)

        let shouldSelect = switchToTab || selectedTabContext == nil
        if shouldSelect {
            selectItem(item)
            applyTab(ctx)
        }

        updateStripVisibility()
        updateAllClosableStates()
        return ctx
    }

    /// 收养一个已含历史的 model（tear-out / 跨窗口迁移用）：直接用该 model 建
    /// `TabContext` 插入 strip，不走 `MainWindowTab(page:)` 新建 —— 保留 back/forward
    /// 历史与已渲染过的 `Page` 实例。`model.needsRender=true` 让 `applyTab` 渲染当前
    /// 页；宿主需在调用前自行把 `model.allPages` 的 `Page` `onWindowContextChanged`
    /// 重绑到本窗口（控件本身不知道窗口边界）。
    @discardableResult
    func adoptTab(model: MainWindowTab, header tabHeader: String?, at index: Int? = nil)
        -> TabContext
    {
        let item = TabViewItem()
        item.name = UUID().uuidString
        item.minWidth = 100
        item.isClosable = !tabContextsByName.isEmpty
        if let tabHeader {
            item.header = tabHeader
        }

        let ctx = TabContext(model: model, item: item)
        tabContextsByName[item.name] = ctx
        updateTabTitle(ctx)

        insertItem(item, at: index)

        // Tear-out 落地必选中 —— torn tab 跟随光标进入接收窗口后应立刻成为当前页。
        selectItem(item)
        model.needsRender = true
        applyTab(ctx)

        updateStripVisibility()
        updateAllClosableStates()
        return ctx
    }

    /// 关闭一个 tab（`>1` tab 才允许；lone tab `isClosable=false`，由 `updateAllClosableStates` 维护）。
    func closeTab(_ ctx: TabContext) {
        guard tabContextsByName.count > 1 else { return }
        let name = ctx.item.name
        guard tabContextsByName[name] != nil else { return }

        let wasSelected = (tabView.selectedItem as? TabViewItem)?.name == name

        removeItemFromStrip(name)
        tabContextsByName[name] = nil

        // 单 PageFrame 不需要"释放 item.content"，但若之前是选中的 tab，需重新
        // rebind 到接管的 tab，避免共享 frame 仍指向已被移除的 model。
        if wasSelected {
            if let next = orderedTabContexts.first(where: { $0.item.name != name }) {
                selectItem(next.item)
                applyTab(next)
            } else {
                visibleTabName = nil
            }
        }

        updateStripVisibility()
        updateAllClosableStates()
    }

    /// 关闭除当前选中 tab 外的全部其它 tab（与 `MainWindow.closeOtherTabs` 同语义）。
    /// 仅在已有选中且 `tabCount > 1` 时起作用；移除时按 strip 顺序遍历快照，
    /// 通过稳定 `item.name` 匹配（WinRT 投影 `===` 不稳，故按 name），避免
    /// 边遍历边修改 live `tabItems` 集合。最后重确认选中并 rebind 共享 frame。
    func closeOtherTabs() {
        guard let keep = selectedTabContext, tabContextsByName.count > 1 else { return }

        // 先快照再删除：`orderedTabContexts` 是计算属性，命中时立即物化成
        // `[TabContext]` 快照，下面的 `for ... where ...` 在快照上迭代，
        // 每次 `removeItemFromStrip(_:)` 只在 live `tabItems` 上按 name 移除一个并
        // `return`，互不干扰。
        for ctx in orderedTabContexts where ctx.item.name != keep.item.name {
            removeItemFromStrip(ctx.item.name)
            tabContextsByName[ctx.item.name] = nil
        }

        // 重确认选中（strip 的 selectedItem 在批量 remove 后可能失效或被系统改动）。
        selectItem(keep.item)
        applyTab(keep)

        updateStripVisibility()
        updateAllClosableStates()
    }

    /// 选中一个 tab（程序化选中）：切到给定的 ctx 并 rebind 共享 frame。
    func selectTab(_ ctx: TabContext) {
        guard tabContextsByName[ctx.item.name] != nil else { return }
        selectItem(ctx.item)
        applyTab(ctx)
    }

    /// 主动触发 strip "+" 加 tab：调用宿主注册的 provider，没有则 no-op。
    // @discardableResult
    // func addNewTabFromProvider() -> TabContext? {
    //     guard let provider = addNewTabProvider else { return nil }
    //     let (page, header) = provider()
    //     return addTab(page: page, header: header)
    // }

    // MARK: - Current-tab navigation（作用于共享 frame 当前的 model）

    /// 在当前选中 tab 的栈上 navigate 一个新 Page。
    func navigateCurrent(
        to page: Page,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) {
        guard let ctx = selectedTabContext else { return }
        ctx.model.navigate(
            to: page,
            transitionInfoOverride: transitionInfoOverride,
            maxHistoryPages: maxHistoryPages
        )
        updateTabTitle(ctx)
        // sharedFrame 当前已 rebind 到 ctx.model，直接走 needsRender 路径，让其用
        // navigate 时记录的 transitionInfo 播放栈内动画。renderCurrentPage 会同步
        // 触发 sharedFrame.onPageChanged → 经由 configureSharedFrame 中转回
        // self.onPageChanged（按 visibleTabName 解析出本 ctx），无需在此再触发。
        sharedFrame.renderCurrentPageIfNeeded()
    }

    /// 当前 tab 栈内 Back。
    func goBackCurrent() {
        guard let ctx = selectedTabContext, !ctx.model.backwardPages.isEmpty else { return }
        ctx.model.goBack(NavigationTransitionInfo.make(slideEffect: .fromLeft))
        updateTabTitle(ctx)
        // 触发回调链同 navigateCurrent 的说明：由 sharedFrame 内回调转发。
        sharedFrame.renderCurrentPageIfNeeded()
    }

    /// 当前 tab 栈内 Forward。
    func goForwardCurrent() {
        guard let ctx = selectedTabContext, !ctx.model.forwardPages.isEmpty else { return }
        ctx.model.goForward(NavigationTransitionInfo.make(slideEffect: .fromRight))
        updateTabTitle(ctx)
        sharedFrame.renderCurrentPageIfNeeded()
    }

    // MARK: - Shared frame setup

    private func configureSharedFrame() {
        // 共享 frame 直接持一个空 model 作为占位；第一个 addTab 时被 rebind 覆盖，
        // 此处保持不被渲染（占位 model.needsRender=false，currentPage=nil）。
        // 不设置 frame.visibility —— 始终可见（被选中的内容就靠它显示）。
        sharedFrame.onPageChanged = { [weak self] frame, page in
            guard let self else { return }
            // guard let name = self.visibleTabName
            // let ctx = self.tabContextsByName[name]
            // else { return }
            // self.onPageChanged?(self, ctx, page)
            self.pageChanged.invoke(self, page)
            _ = frame
        }
        sharedFrame.onCleared = { [weak self] frame in
            guard let self else { return }
            // guard let name = self.visibleTabName
            // let ctx = self.tabContextsByName[name]
            // else { return }
            // self.onCleared?(self, ctx)
            self.pageChanged.invoke(self, nil)
            _ = frame
        }
    }

    // MARK: - Grid assembly

    private func assembleGrid() {
        let autoRow = RowDefinition()
        autoRow.height = GridLength(value: 0, gridUnitType: .auto)
        let starRow = RowDefinition()
        starRow.height = GridLength(value: 1, gridUnitType: .star)
        rowDefinitions.append(autoRow)
        rowDefinitions.append(starRow)

        children.append(tabView)
        try? Grid.setRow(tabView, 0)
        children.append(sharedFrame)
        try? Grid.setRow(sharedFrame, contentRow)
    }

    private func configureTabView() {
        tabView.isAddTabButtonVisible = true
        tabView.tabWidthMode = .sizeToContent
        tabView.closeButtonOverlayMode = .onPointerOver
        tabView.canDragTabs = true
        tabView.canReorderTabs = true
        // Native tear-out gate — see PageTabView.tabTearOutEnabled above.
        tabView.canTearOutTabs = PageTabView.tabTearOutEnabled
        tabView.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        tabView.margin = Thickness(left: 0, top: -1, right: 0, bottom: 0)
        // "关闭其它 tab"按钮挂在 strip 左侧 header；strip 整体在 tabCount ≤1 时收起，
        // 按钮随之消失，与 MainWindow.closeOtherTabsButton 同策略。
        tabView.tabStripHeader = closeOthersButton
    }

    /// 按钮工厂：仿 `MainWindow` 的 closeOtherTabsButton，仅图标、透明底、hover/
    /// pressed 半透明灰覆盖，圆角与 padding 与 TabViewItem 风格对齐。
    private func makeCloseOthersButton() -> Button {
        let icon = FontIcon()
        icon.glyph = "\u{F166}"
        icon.fontSize = 12

        let btn = Button()
        btn.content = icon
        btn.minWidth = 0
        btn.minHeight = 0
        // 与 TabViewItem 一致的角圆 + 头部 padding。
        btn.cornerRadius = CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
        btn.padding = Thickness(left: 10, top: 0, right: 10, bottom: 0)
        // 4px 上下边距使按钮与 tab 项同高；2px 右边距紧贴第一个 tab。
        btn.margin = Thickness(left: 4, top: 4, right: 2, bottom: 4)
        btn.verticalAlignment = .stretch
        btn.allowFocusOnInteraction = false

        // 通过 resources 改写底层 Button 主题资源：默认/禁用透明、悬停/按下淡灰覆盖，
        // 边框恒透明。与 MainWindow 的实现一致。
        let transparent = SolidColorBrush(Colors.transparent)
        let hoverBrush = SolidColorBrush(UWP.Color(a: 0x18, r: 0x80, g: 0x80, b: 0x80))
        let pressedBrush = SolidColorBrush(UWP.Color(a: 0x30, r: 0x80, g: 0x80, b: 0x80))
        for key in ["ButtonBackground", "ButtonBackgroundDisabled"] {
            _ = btn.resources.insert(key, transparent)
        }
        _ = btn.resources.insert("ButtonBackgroundPointerOver", hoverBrush)
        _ = btn.resources.insert("ButtonBackgroundPressed", pressedBrush)
        for key in [
            "ButtonBorderBrush", "ButtonBorderBrushPointerOver",
            "ButtonBorderBrushPressed", "ButtonBorderBrushDisabled",
        ] {
            _ = btn.resources.insert(key, transparent)
        }

        btn.click.addHandler { [weak self] _, _ in
            self?.closeOtherTabs()
        }
        applyCloseOthersTooltip(to: btn)
        return btn
    }

    /// 把"关闭其它标签页"本地化文案挂到按钮 ToolTip。tooltip 在按钮 lazy 求值时定格，
    /// 语言切换后需由宿主重新调用（参照 MainWindow.applyAppearance 的同款再应用）。
    private func applyCloseOthersTooltip(to button: Button) {
        let toolTip = ToolTip()
        toolTip.content = App.context.tr("CloseOthers")
        try? ToolTipService.setToolTip(button, toolTip)
    }

    /// 重新应用"关闭其它"tooltip 文案。语言切换后由宿主调用一次即可更新按钮提示。
    func reapplyCloseOthersTooltip() {
        applyCloseOthersTooltip(to: closeOthersButton)
    }

    private func wireTabViewEvents() {
        tabView.selectionChanged.addHandler { [weak self] _, _ in
            guard let self, !self.isSyncingSelection else { return }
            guard let ctx = self.selectedTabContext else { return }
            self.applyTab(ctx)
        }
        tabView.tabCloseRequested.addHandler { [weak self] _, args in
            guard let self, let args, let item = args.tab else { return }
            guard let ctx = self.tabContextsByName[item.name] else { return }
            self.closeTab(ctx)
        }
        tabView.addTabButtonClick.addHandler { [weak self] _, _ in
            // self?.addNewTabFromProvider()
            self?.addTab(page: nil, header: nil)
            //self?.pageChanged.invoke(self!, nil)
        }
    }

    // MARK: - Apply / render

    /// 把共享 frame 重绑到指定 ctx 的 model 并渲染。tab 切换恒用 Suppress 转场：
    /// 切 tab 是"切 View"，跨 tab 滑动动画只会串扰；栈内 Back/Forward 才走 Slide。
    private func applyTab(_ ctx: TabContext) {
        let name = ctx.item.name
        // 切换到已在显示的 tab 而又无新渲染：跳过（避免无谓 rebind + 防御 detach
        // 误伤之前 tab 把 content 作为存储属性的 Page）。
        if visibleTabName == name && !ctx.model.needsRender {
            return
        }
        // 先置 visibleTabName，再 rebind：rebind 内 `renderCurrentPage` 会同步触发
        // `sharedFrame.onPageChanged`，经由 configureSharedFrame 中转回 self 回调，
        // 届时依赖 visibleTabName 把回调绑到正确 ctx。
        visibleTabName = name

        // 消耗首帧标志。rebind 恒 Suppress，故无需把 firstRender 接进 transitionInfo
        // （tab 切换全走即时；栈内 Back/Forward 才会播 Slide）。
        isFirstNavigation = false

        // 单 frame model 重绑：恒 rebind + Suppress 渲染。renderCurrentPage 会同步
        // 调 sharedFrame.onPageChanged/onCleared，无需在此处再触发一次。
        sharedFrame.rebind(to: ctx.model)
        updateTabTitle(ctx)
    }

    // MARK: - Strip helpers

    /// 从 page.title 派生 strip 标题，变化时写回 item.header 并缓存。
    private func updateTabTitle(_ ctx: TabContext) {
        let newTitle = ctx.model.currentPage?.title ?? "New Tab"
        if ctx.title != newTitle {
            ctx.item.header = newTitle
            ctx.title = newTitle
        }
    }

    /// 单 tab 时隐藏整个 TabView：内容靠共享 frame 在 Row1 显示，遮 strip 无副作用。
    private func updateStripVisibility() {
        tabView.visibility = tabContextsByName.count <= 1 ? .collapsed : .visible
    }

    private func updateAllClosableStates() {
        let canClose = tabContextsByName.count > 1
        for ctx in tabContextsByName.values where ctx.isClosable != canClose {
            ctx.item.isClosable = canClose
            ctx.isClosable = canClose
        }
    }

    private func insertItem(_ item: TabViewItem, at index: Int?) {
        guard let items = tabView.tabItems else { return }
        isSyncingSelection = true
        defer { isSyncingSelection = false }
        if let index, index >= 0, UInt32(index) <= items.size {
            items.insertAt(UInt32(index), item)
        } else {
            items.insertAt(items.size, item)
        }
    }

    private func selectItem(_ item: TabViewItem) {
        isSyncingSelection = true
        tabView.selectedItem = item
        isSyncingSelection = false
    }

    private func removeItemFromStrip(_ name: String) {
        guard let items = tabView.tabItems else { return }
        isSyncingSelection = true
        defer { isSyncingSelection = false }
        var i: UInt32 = 0
        while i < items.size {
            if let it = items.getAt(i) as? TabViewItem, it.name == name {
                items.removeAt(i)
                return
            }
            i += 1
        }
    }

    // MARK: - Host-facing entry points (MainWindow cross-window tear-out & fullscreen)

    /// 暴露内部 strip `TabView` 供宿主挂 cross-window tear-out 事件。Tear-out 本质跨
    /// 窗口（创建接收窗、在窗口间迁移 model），windowless 控件无法自己拥有，故把这
    /// 个事件源暴露给宿主窗口。受 `PageTabView.tabTearOutEnabled` gate:`false` 时
    /// 宿主的 `configureTearOutEvents` 直接 early-return，永不读取本 accessor。
    var tearOutTabView: TabView { tabView }
}
