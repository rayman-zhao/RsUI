import Foundation
import WinUI
import UWP
import RsHelper
import Observation

struct NavigationPanePreferences: Preferable {
    /// 侧边栏宽度
    var sidebarWidth: Int = 300
    /// 侧边栏是否展开
    var isSidebarExpanded: Bool = true
}

/// 封装 NavigationView 的构建、导航逻辑以及页面缓存
final class NavigationPane {
    private let viewModel: MainWindowViewModel
    private let makePageContext: () -> PageContext
    private let selectionChanged: (String, String) -> Void

    private let navigationView: NavigationView
    private let rootFrame: Frame

    private var nodeMap: [String: NavigationNode] = [:]
    private var itemMap: [String: NavigationViewItem] = [:]
    private var parentMap: [String: String] = [:]
    private var pageCache: [String: AppPage] = [:]

    private(set) var currentPageId: String = ""

    init(
        viewModel: MainWindowViewModel,
        makePageContext: @escaping () -> PageContext,
        selectionChanged: @escaping (String, String) -> Void
    ) {
        self.viewModel = viewModel
        self.makePageContext = makePageContext
        self.selectionChanged = selectionChanged
        self.navigationView = NavigationView()
        self.rootFrame = Frame()

        configureNavigationView()
        
        // 立即应用初始状态
        applyTheme(App.context.theme)
        refreshLocalizationUI()
        
        startObserving()
    }

    var rootView: NavigationView { navigationView }
    var currentTitle: String { nodeMap[currentPageId]?.label ?? "Ruslan" }
    var canGoBack: Bool { rootFrame.canGoBack }

    func goBack() {
        guard rootFrame.canGoBack else { return }
        try? rootFrame.goBack()
    }

    func togglePane() {
        navigationView.isPaneOpen.toggle()
    }

    func applyTheme(_ theme: AppTheme) {
        let elementTheme: WinUI.ElementTheme = theme.elementTheme
        navigationView.requestedTheme = elementTheme
        rootFrame.requestedTheme = elementTheme
    }

    func refreshLocalizationUI() {
        refreshNavigationLocalization()
        notifySelectionChanged()
    }

    private func startObserving() {
        let env = Observations {
            (App.context.theme, App.context.language)
        }
        Task { [weak self] in
            for await ctx in env {
                guard let self else { break }
                await MainActor.run {
                    self.applyTheme(ctx.0)
                    self.refreshLocalizationUI()
                }
            }
        }
    }

    /// 重建导航栏，通常在外部动态修改节点后调用
    func rebuildNavigation() {
        let previousPageId = currentPageId
        let validIds = Set(NavigationCatalog.allNodes.map { $0.id })
        pageCache.keys.filter { !validIds.contains($0) }.forEach { pageCache.removeValue(forKey: $0) }

        rebuildNavigationItems()

        if let retainedItem = itemMap[previousPageId], let retainedNode = nodeMap[previousPageId], retainedNode.isSelectable {
            expandAncestors(of: previousPageId)
            navigationView.selectedItem = retainedItem
        } else {
            currentPageId = previousPageId
            prepareInitialSelection()
        }
    }

    // MARK: - Private helpers

    private func configureNavigationView() {
        let pref = App.context.preferences.load(for: NavigationPanePreferences.self)

        navigationView.paneDisplayMode = .left
        navigationView.isSettingsVisible = false
        navigationView.openPaneLength = Double(pref.sidebarWidth)
        navigationView.isBackButtonVisible = .collapsed
        navigationView.isPaneToggleButtonVisible = true

        rebuildNavigationItems()

        navigationView.content = rootFrame

        navigationView.selectionChanged.addHandler { [weak self] _, _ in
            self?.handleNavigationSelection()
        }

        prepareInitialSelection()
    }
    
    /// 重构导航栏，清除节点缓存，导航栏缓存，关系缓存。重新根据model(NavigationCatalog)构建导航栏。
    private func rebuildNavigationItems() {
        nodeMap.removeAll()
        itemMap.removeAll()
        parentMap.removeAll()
        navigationView.menuItems.clear()

        for node in NavigationCatalog.menuNodes {
            let navItem = createNavigationItem(for: node, parentId: nil)
            navigationView.menuItems.append(navItem)
        }

        if let footerCollection = navigationView.footerMenuItems {
            footerCollection.clear()
            for node in NavigationCatalog.footerNodes {
                let navItem = createNavigationItem(for: node, parentId: nil)
                footerCollection.append(navItem)
            }
        }
    }

    private func prepareInitialSelection() {
        if currentPageId.isEmpty {
            currentPageId = NavigationCatalog.defaultNodeId
        }

        guard
            let initialId = resolveInitialSelectionId(),
            let item = itemMap[initialId]
        else {
            return
        }

        currentPageId = initialId
        expandAncestors(of: initialId)
        navigationView.selectedItem = item
        handleNavigationSelection()
    }

    private func createNavigationItem(for node: NavigationNode, parentId: String?) -> NavigationViewItem {
        if node.useCustomItem {
            let navItem = node.createNavigationViewItem?() ?? NavigationViewItem()
            navItem.tag = node.id as AnyObject
            navItem.selectsOnInvoked = node.isSelectable

            nodeMap[node.id] = node
            itemMap[node.id] = navItem
            if let parentId = parentId {
                parentMap[node.id] = parentId
            }
            
            if !node.children.isEmpty {
                navItem.menuItems.clear()
                for child in node.children {
                    let childItem = createNavigationItem(for: child, parentId: node.id)
                    navItem.menuItems.append(childItem)
                }
                navItem.isExpanded = node.initiallyExpanded
            }
            return navItem
        }
        let navItem = NavigationViewItem()
        
        if let glyph = node.glyph {
            let icon = FontIcon()
            icon.glyph = glyph
            icon.fontSize = 16
            navItem.icon = icon
        }

        navItem.content = makeNavItemContent(node: node) as AnyObject
        navItem.horizontalContentAlignment = .stretch

        navItem.tag = node.id as AnyObject
        navItem.selectsOnInvoked = node.isSelectable

        nodeMap[node.id] = node
        itemMap[node.id] = navItem
        if let parentId = parentId {
            parentMap[node.id] = parentId
        }

        if !node.children.isEmpty {
            navItem.menuItems.clear()
            for child in node.children {
                let childItem = createNavigationItem(for: child, parentId: node.id)
                navItem.menuItems.append(childItem)
            }
            navItem.isExpanded = node.initiallyExpanded
        }

        return navItem
    }

    /// 根据节点生成可复用的内容视图（含动作按钮和图标）
    private func makeNavItemContent(node: NavigationNode) -> UIElement {
        let grid = Grid()
        grid.horizontalAlignment = .stretch
        grid.verticalAlignment = .center
        
        // 定义列：标签(填充) | 动作按钮(自动)
        let textCol = ColumnDefinition()
        textCol.width = GridLength(value: 1, gridUnitType: .star)
        grid.columnDefinitions.append(textCol)

        let actionCol = ColumnDefinition()
        actionCol.width = GridLength(value: 0, gridUnitType: .auto)
        grid.columnDefinitions.append(actionCol)

        // 1. 标签
        let textBlock = TextBlock()
        textBlock.text = node.label
        textBlock.verticalAlignment = .center
        textBlock.horizontalAlignment = .left
        textBlock.textTrimming = .characterEllipsis
        try? Grid.setColumn(textBlock, 0)
        grid.children.append(textBlock)

        // 2. 动作按钮
        if let actionGlyph = node.actionGlyph, let actionHandler = node.actionHandler {
            let actionButton = Button()
            actionButton.background = SolidColorBrush(UWP.Color(a: 0, r: 0, g: 0, b: 0))
            actionButton.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
            actionButton.padding = Thickness(left: 4, top: 4, right: 4, bottom: 4)
            actionButton.verticalAlignment = .center
            actionButton.horizontalAlignment = .right
            actionButton.width = 32
            actionButton.height = 32
            actionButton.cornerRadius = CornerRadius(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)

            let icon = FontIcon()
            icon.glyph = actionGlyph
            icon.fontSize = 16
            actionButton.content = icon

            // 设置提示文字
            let tooltip: String
            if node.id == "triage" {
                tooltip = App.context.tr("add_folder")
            } else if actionGlyph == "\u{E74D}" {
                tooltip = App.context.tr("delete_folder")
            } else {
                tooltip = ""
            }
            try? ToolTipService.setToolTip(actionButton, tooltip as AnyObject)

            actionButton.click.addHandler { _, _ in
                actionHandler()
            }
            try? Grid.setColumn(actionButton, 1)
            grid.children.append(actionButton)
        }

        return grid
    }

    private func resolveInitialSelectionId() -> String? {
        if let node = nodeMap[currentPageId], node.isSelectable {
            return currentPageId
        }

        let preferred = NavigationCatalog.defaultNodeId
        if !preferred.isEmpty, let node = nodeMap[preferred], node.isSelectable {
            return node.id
        }

        return itemMap.first { nodeMap[$0.key]?.isSelectable == true }?.key
    }

    private func expandAncestors(of nodeId: String) {
        var parentId = parentMap[nodeId]
        while let currentParent = parentId {
            if let parentItem = itemMap[currentParent] {
                parentItem.isExpanded = true
            }
            parentId = parentMap[currentParent]
        }
    }

    private func handleNavigationSelection() {
        guard
            let selectedItem = navigationView.selectedItem as? NavigationViewItem,
            let nodeId = extractNavigationId(from: selectedItem),
            let node = nodeMap[nodeId],
            node.isSelectable
        else {
            return
        }

        navigateToPage(nodeId, node: node)
    }

    private func extractNavigationId(from item: NavigationViewItem) -> String? {
        if let identifier = item.tag as? String {
            return identifier
        }

        return itemMap.first { $0.value === item }?.key
    }

    private func navigateToPage(_ nodeId: String, node: NavigationNode) {
        expandAncestors(of: nodeId)
        currentPageId = nodeId
        let page = resolvePage(for: node)
        rootFrame.content = page.rootView
        notifySelectionChanged()
    }

    private func resolvePage(for node: NavigationNode) -> AppPage {
        if let cached = pageCache[node.id] {
            return cached
        }

        guard let factory = node.makePage else {
            preconditionFailure("导航节点 \(node.id) 未配置页面工厂")
        }

        let context = makePageContext()
        let page = factory(context)
        pageCache[node.id] = page
        return page
    }

    private func refreshNavigationLocalization() {
        for (nodeId, navItem) in itemMap {
            if let node = nodeMap[nodeId] {
                if !node.useCustomItem {
                    navItem.content = makeNavItemContent(node: node) as AnyObject
                } else {
                    itemMap[nodeId] = navItem
                }
            }
        }
    }

    private func notifySelectionChanged() {
        let title = nodeMap[currentPageId]?.label ?? "Ruslan"
        selectionChanged(currentPageId, title)
    }
}
