import Foundation
import UWP
import WinUI
import WindowsFoundation

extension MainWindow {
    func setupContent() {
        let root = Grid()

        // 设置行定义
        let titleRowDef = RowDefinition()
        titleRowDef.height = GridLength(value: 1, gridUnitType: .auto)
        root.rowDefinitions.append(titleRowDef)

        let contentRowDef = RowDefinition()
        contentRowDef.height = GridLength(value: 1, gridUnitType: .star)
        root.rowDefinitions.append(contentRowDef)

        root.children.append(titleBar)
        try? Grid.setRow(titleBar, 0)
        try? setTitleBar(titleBar)

        configureNavigationViewSelection()
        configureTabViewEvents()
        configurePaneEvents()

        let navWrapper = makeNavigationWrapper()
        self.navWrapper = navWrapper
        root.children.append(navWrapper)
        try? Grid.setRow(navWrapper, 1)

        self.content = root

        installFullscreenEscapeAccelerator(on: root)
    }

    private func configureNavigationViewSelection() {
        navigationView.selectionChanged.addHandler { [weak self] _, args in
            guard let self, let args, !self.isSyncingSelection else { return }

            if args.isSettingsSelected {
                navigate(
                    to: SettingsPage(), transitionInfoOverride: SuppressNavigationTransitionInfo())
            } else if let item = args.selectedItem as? NavigationViewItem,
                let tag = item.tag,
                let str = tag as? HString,
                let url = URL(string: String(hString: str))
            {
                _ = navigate(to: url, transitionInfoOverride: SuppressNavigationTransitionInfo())
            }
        }
    }

    private func configureTabViewEvents() {
        // TabView owns selection: just render whatever it selected. Our own
        // programmatic selectItem(_:) sets isSyncingTabSelection and renders
        // separately, so skip those to avoid a redundant pass. In-window
        // drag-reorder needs no handler — order lives in tabView.tabItems.
        tabView.selectionChanged.addHandler { [weak self] _, _ in
            guard let self, !self.isSyncingTabSelection else { return }
            self.renderSelectedTab()
        }

        tabView.tabCloseRequested.addHandler { [weak self] _, args in
            guard let self, let args, let item = args.tab else { return }
            self.closeTab(for: item)
        }

        tabView.addTabButtonClick.addHandler { [weak self] _, _ in
            self?.openNewTabFromTabStrip()
        }

        configureTabTearOutEvents()
    }

    // Registers native tear-out/merge handlers. the guard below gates this
    // optional native tear-out/merge.
    private func configureTabTearOutEvents() {
        guard PageTabView.tabTearOutEnabled else { return }

        // Native tear-out (CanTearOutTabs). The OS owns the drag visuals and the
        // window-follow animation; these handlers only move our model — the
        // MainWindowTab plus its decoupled content frame — between windows.

        // Both the tab in flight and its receiving window are tracked in
        // MainWindow.pendingTearOut. The receiver can't be read from the event:
        // tabTearOutRequested gives args.newWindowId 0 even though we set it in
        // the window-requested event, so we remember it ourselves, like the
        // official CanTearOutTabs sample.

        // A tab is being torn out and needs a window to land in. The framework
        // over-fires this within one drag (incl. speculative tears it never
        // commits), so tearOutReceiver() reuses one empty spare instead of
        // leaking a window per call. Without reuse, speculative requests can
        // leave empty receiver windows that never get a tab and keep the app
        // process alive after the real windows close.
        tabView.tabTearOutWindowRequested.addHandler { [weak self] _, args in
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
        tabView.tabTearOutRequested.addHandler { _, _ in
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
        tabView.externalTornOutTabsDropping.addHandler { _, args in
            guard let args, MainWindow.pendingTearOut != nil else { return }
            args.allowDrop = true
        }

        // Merge: pull the torn tab from its current holder into this window at
        // dropIndex, then discard the now-empty floating receiver.
        tabView.externalTornOutTabsDropped.addHandler { [weak self] _, args in
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

    private func configurePaneEvents() {
        navigationView.paneClosed.addHandler { [weak self] _, _ in
            self?.splitterBorder.visibility = .collapsed
        }
        navigationView.paneOpened.addHandler { [weak self] _, _ in
            self?.splitterBorder.visibility = .visible
        }
    }

    private func makeNavigationWrapper() -> Grid {
        let navWrapper = Grid()
        navWrapper.children.append(navigationView)
        splitterBorder = makeSplitterBorder()
        navWrapper.children.append(splitterBorder)
        try? Canvas.setZIndex(splitterBorder, 10)
        return navWrapper
    }
}
