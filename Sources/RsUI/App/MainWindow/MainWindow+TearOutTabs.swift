/*

/// Information returned when a selected tab is detached from a main window.
public struct DetachedTabInfo: Sendable {
    /// The page URL that identified the detached tab.
    public let url: URL

    /// The tab's original 0-based position in the source tab strip.
    public let index: Int
}

class WindowContext {
    // MARK: - Detach / Restore

    /// Removes the currently selected tab from this window for a caller-managed transfer.
    ///
    /// Use this after capturing any page runtime state needed by the destination host.
    /// The method allows detaching the last tab; in that case the source window remains
    /// open without a selected page until another tab is added or selected.
    ///
    /// - Returns: Information about the detached tab, or `nil` if the owner window has
    ///   been released, no tab is selected, or the selected tab has no current page.
    @discardableResult
    public func detachCurrentTab() -> DetachedTabInfo? {
        guard let owner else { return nil }
        return owner.detachCurrentTab()
    }

    /// Restores caller-managed detached content into this window as a tab.
    ///
    /// Use this for "merge back from detached window" flows. The caller creates a
    /// `Page` with restored runtime state and asks RsUI to insert it back into the tab
    /// strip, typically at the index returned by `detachCurrentTab()`.
    ///
    /// - Parameters:
    ///   - page: The page to display in the new tab.
    ///   - preferredIndex: Preferred insertion position (0-based). If `nil` or out of
    ///     range, the tab is appended to the end.
    ///   - switchToTab: Whether to select the new tab. Defaults to `true`.
    ///   - transitionInfoOverride: Optional navigation transition.
    /// - Returns: `true` if the page was inserted. `false` if the owner window has
    ///   already been released.
    ///
    @discardableResult
    public func restoreDetachedTab(
        _ page: Page,
        preferredIndex: Int? = nil,
        switchToTab: Bool = true,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> Bool {
        guard let owner else { return false }
        owner.restoreTab(
            page,
            atIndex: preferredIndex,
            switchToTab: switchToTab,
            transitionInfoOverride: transitionInfoOverride
        )
        return true
    }
}

class MainWindow {
    // An empty window created to receive a tab torn out into a new window. It
    // comes up with no tab (startup navigation is skipped) and waits for
    // tabTearOutRequested to inject the torn tab; it also skips position restore.
    var awaitTransferredTab: Bool = false

    // Native tear-out gate moved to PageTabView.tabTearOutEnabled (the single
    // place controlling `canTearOutTabs`). The cross-window tear-out handlers /
    // pending state below remain gated on it; see the comment there for the
    // blocking WinUI bugs.

    // Tracks the single tab being torn out across windows. Drag is single-pointer
    // on the UI thread, so at most one is ever in flight. `holder` follows the tab
    // as it moves between windows during the drag; `receiver` is the floating
    // window the native flow asked us to create.
    // The receiver is resolved from HERE, not from args.newWindowId — that property
    // reads back 0 in the tabTearOutRequested event, so we remember it ourselves.
    struct PendingTearOut {
        let tab: MainWindowTab
        var holder: MainWindow
        let receiver: MainWindow
    }
    static var pendingTearOut: PendingTearOut? = nil
    // Reused so the framework's repeated windowRequested calls within one drag
    // (it over-fires, incl. speculative tears it never commits) don't leak empty
    // windows.
    static var spareReceiver: MainWindow? = nil

    // Empty receiver window for a tear-out. Comes up with no tab and skips
    // position restore; the torn tab is injected by tabTearOutRequested.
    init(tearOutReceiver: Bool) {
        // A tear-out receiver is positioned by the OS as it follows the cursor —
        // don't restore the saved main-window rect over it.
        super.init()
        useMicaBackdrop()
        useRestoration(!tearOutReceiver)
        self.awaitTransferredTab = tearOutReceiver
        bootstrap()

        //Bind Events
                // An empty tear-out receiver: the torn tab is injected later by
                // tabTearOutRequested, so skip all startup navigation and come up blank.
                if awaitTransferredTab {
                    return
                }
    }

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

            self.viewModel = nil
        }
    }

    // MARK: - Detach / Restore (caller-managed transfer, used by viewer windows)

    func detachCurrentTab() -> DetachedTabInfo? {
        guard let ctx = selectedTabContext, let url = ctx.model.currentPage?.url else { return nil }
        let index = indexOfItem(name: ctx.item.name) ?? 0
        pageTabView.closeTab(ctx)
        return DetachedTabInfo(url: url, index: index)
    }

    func restoreTab(
        _ page: Page,
        atIndex index: Int? = nil,
        switchToTab: Bool = true,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) {
        addTab(
            page: page,
            at: index,
            switchToTab: switchToTab,
            transitionInfoOverride: transitionInfoOverride
        )
    }

    // MARK: - Native tear-out

    // Returns a window for the native tear-out to drop a tab into. Reuses the
    // current empty spare if one exists (the framework asks repeatedly during a
    // drag); otherwise creates and activates a fresh one so it owns a valid
    // AppWindow.Id. The OS positions it as it follows the cursor.
    static func tearOutReceiver() -> MainWindow {
        if let spare = MainWindow.spareReceiver, spare.hasNoTabs {
            return spare
        }
        let window = MainWindow(tearOutReceiver: true)
        try? window.activate()
        MainWindow.spareReceiver = window
        return window
    }

    // Removes a tab from this window's strip; the MainWindowTab object — with its
    // history — lives on to be adopted elsewhere.
    func releaseTab(_ model: MainWindowTab) {
        guard viewModel != nil, let ctx = context(for: model) else { return }
        pageTabView.closeTab(ctx)
    }

    // Adopts a torn model into this window's strip, building a fresh item for it
    // (shared frame 由 PageTabView 自身 rebind）。`at` is the merge drop position;
    // nil appends (empty-receiver case).
    func adoptTornTab(_ model: MainWindowTab, at index: Int? = nil) {
        guard viewModel != nil else { return }
        awaitTransferredTab = false
        // The same Page instances travel with the model; rebind their context to
        // this window so window-scoped calls hit the new owner, not the creator.
        let context = WindowContext(owner: self)
        for page in model.allPages {
            page.windowContextDidChange(to: context)
        }
        let header = model.currentPage?.title
        pageTabView.adoptTab(model: model, header: header, at: index)
    }


    // Closes this window once its last tab has been torn/merged away, so an
    // emptied floating receiver doesn't linger.
    func closeIfEmpty() {
        guard hasNoTabs else { return }
        try? close()
    }

    // Registers native tear-out/merge handlers. The guard below gates this
    // optional native tear-out/merge — currently disabled globally.
    private func configureTabTearOutEvents() {
        guard PageTabView.tabTearOutEnabled else { return }

        // Native tear-out (CanTearOutTabs). The OS owns the drag visuals and the
        // window-follow animation; these handlers only move our model — the
        // MainWindowTab — between windows; shared frame 由接收方 PageTabView 自己 rebind。

        // Both the tab in flight and its receiving window are tracked in
        // MainWindow.pendingTearOut. The receiver can't be read from the event:
        // tabTearOutRequested gives args.newWindowId 0 even though we set it in
        // the window-requested event, so we remember it ourselves, like the
        // official CanTearOutTabs sample.
        let strip = pageTabView.tearOutTabView

        // A tab is being torn out and needs a window to land in. The framework
        // over-fires this within one drag (incl. speculative tears it never
        // commits), so tearOutReceiver() reuses one empty spare instead of
        // leaking a window per call.
        strip.tabTearOutWindowRequested.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            // WinUI selects the pressed tab before the tear begins, so the
            // selected tab is the one being torn out.
            guard let model = self.selectedTabModel else { return }
            let receiver = MainWindow.tearOutReceiver()
            MainWindow.pendingTearOut = MainWindow.PendingTearOut(
                tab: model, holder: self, receiver: receiver
            )
            args.newWindowId = receiver.appWindow.id
        }

        // Commit the tear: move the torn tab from its holder into the
        // receiver. Once moved, the spare is no longer empty, so release it.
        strip.tabTearOutRequested.addHandler { _, _ in
            guard var pending = MainWindow.pendingTearOut,
                pending.holder !== pending.receiver
            else { return }
            pending.holder.releaseTab(pending.tab)
            pending.receiver.adoptTornTab(pending.tab)
            pending.holder = pending.receiver
            MainWindow.pendingTearOut = pending
            MainWindow.spareReceiver = nil
        }

        // A torn tab from another window is dragged over this strip. always
        // allow it to drop.
        strip.externalTornOutTabsDropping.addHandler { _, args in
            guard let args, MainWindow.pendingTearOut != nil else { return }
            args.allowDrop = true
        }

        // Merge: pull the torn tab from its current holder into this window at
        // dropIndex, then discard the now-empty floating receiver.
        strip.externalTornOutTabsDropped.addHandler { [weak self] _, args in
            guard let self, let args, let pending = MainWindow.pendingTearOut else { return }
            let index = Int(args.dropIndex)
            pending.holder.releaseTab(pending.tab)
            self.adoptTornTab(pending.tab, at: index)
            if pending.receiver !== self {
                // Defer the close: when this handler returns the framework is
                // still finalizing the drop on the receiver window, so closing it
                // synchronously here crashes. Close on the next UI tick instead.
                let receiver = pending.receiver
                Task { @MainActor in receiver.closeIfEmpty() }
            }
            MainWindow.pendingTearOut = nil
        }
    }

    // MARK: - Strip primitives (match items by stable name, not by ===)

    /// strip 顺序中按 name 找 index；tear-out 合并 / detach 用到。WinRT 投影 `===` 不
    /// 稳，故按 name。
    func indexOfItem(name: String) -> Int? {
        guard let items = pageControl.tearOutTabView.tabItems else { return nil }
        var i: UInt32 = 0
        while i < items.size {
            if let it = items.getAt(i) as? TabViewItem, it.name == name {
                return Int(i)
            }
            i += 1
        }
        return nil
    }
}

class PageTabView {
    // MARK: - Host-facing entry points (MainWindow cross-window tear-out & fullscreen)

    /// 暴露内部 strip `TabView` 供宿主挂 cross-window tear-out 事件。Tear-out 本质跨
    /// 窗口（创建接收窗、在窗口间迁移 model），windowless 控件无法自己拥有，故把这
    /// 个事件源暴露给宿主窗口。受 `PageTabView.tabTearOutEnabled` gate:`false` 时
    /// 宿主的 `configureTearOutEvents` 直接 early-return，永不读取本 accessor。
    var tearOutTabView: TabView { tabView }

    /// 收养一个已含历史的 model（tear-out / 跨窗口迁移用）：直接用该 model 建
    /// `TabContext` 插入 strip，不走 `PageModel(page:)` 新建 —— 保留 back/forward
    /// 历史与已渲染过的 `Page` 实例。`model.needsRender=true` 让 `applyTab` 渲染当前
    /// 页；宿主需在调用前自行把 `model.allPages` 的 `Page` `windowContextDidChange`
    /// 重绑到本窗口（控件本身不知道窗口边界）。
    @discardableResult
    func adoptTab(model: PageModel, header tabHeader: String?, at index: Int? = nil)
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
        // model.needsRender = true
        applyTab(ctx)

        updateStripVisibility()
        updateAllClosableStates()
        return ctx
    }
}
*/
