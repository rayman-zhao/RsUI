import Foundation
import WinUI

/// 表示导航视图中的一个节点，支持任意层级嵌套。
public struct NavigationNode: Sendable {
    /// 唯一标识符，用于匹配选择状态和页面缓存
    let id: String
    /// LocalizationService 中的文案 key
    let labelKey: String
    /// 显式的显示文本，若提供则忽略 labelKey
    let literalLabel: String?
    /// 显示在 NavigationViewItem 上的字体图标，分组节点可以为空
    let glyph: String?
    /// 在层级结构中是否默认展开
    let initiallyExpanded: Bool
    /// 若节点可导航，该闭包用于构建页面；为 nil 时表示仅作为分组节点
    let makePage: (@Sendable (PageContext) -> AppPage)?
    /// 子节点集合，用于构建层级导航
    let children: [NavigationNode]
    /// 右侧操作按钮的图标
    let actionGlyph: String?
    /// 右侧操作按钮的点击回调
    let actionHandler: (@Sendable () -> Void)?

    /// 当前语言环境下的可见文本
    var label: String {
        literalLabel ?? App.context.tr(labelKey)
    }

    /// decide whether to use custom NavigationViewItem
    let useCustomItem: Bool 
    /// factory to create custom NavigationViewItem
    let createNavigationViewItem: (@Sendable () -> WinUI.NavigationViewItem)?

    init(
        id: String,
        labelKey: String,
        literalLabel: String? = nil,
        glyph: String? = nil,
        initiallyExpanded: Bool = false,
        makePage: (@Sendable (PageContext) -> AppPage)? = nil,
        children: [NavigationNode] = [],
        actionGlyph: String? = nil,
        actionHandler: (@Sendable () -> Void)? = nil,
        useCustomItem: Bool = false,
        createNavigationViewItem: (@Sendable () -> WinUI.NavigationViewItem)? = nil
    ) {
        self.id = id
        self.labelKey = labelKey
        self.literalLabel = literalLabel
        self.glyph = glyph
        self.initiallyExpanded = initiallyExpanded
        self.makePage = makePage
        self.children = children
        self.actionGlyph = actionGlyph
        self.actionHandler = actionHandler
        self.createNavigationViewItem = createNavigationViewItem
        self.useCustomItem = useCustomItem
    }

    /// 是否可以被选择并跳转页面
    var isSelectable: Bool {
        makePage != nil
    }

    /// 返回自身或后代中第一个可导航的节点
    func firstSelectableDescendant() -> NavigationNode? {
        if isSelectable {
            return self
        }
        for child in children {
            if let match = child.firstSelectableDescendant() {
                return match
            }
        }
        return nil
    }

    /// 将当前节点及其后代扁平化
    func flattened() -> [NavigationNode] {
        [self] + children.flatMap { $0.flattened() }
    }
}

public extension NavigationNode {
    /// 构建可导航的叶子节点
    static func leaf(
        id: String,
        labelKey: String,
        literalLabel: String? = nil,
        glyph: String? = nil,
        initiallyExpanded: Bool = false,
        actionGlyph: String? = nil,
        actionHandler: (@Sendable () -> Void)? = nil,
        pageFactory: @escaping @Sendable (PageContext) -> AppPage,
        createNavigationViewItem: (@Sendable () -> WinUI.NavigationViewItem)? = nil,
        useCustomItem: Bool = false
    ) -> NavigationNode {
        NavigationNode(
            id: id,
            labelKey: labelKey,
            literalLabel: literalLabel,
            glyph: glyph,
            initiallyExpanded: initiallyExpanded,
            makePage: pageFactory,
            children: [],
            actionGlyph: actionGlyph,
            actionHandler: actionHandler,
            useCustomItem: useCustomItem,
            createNavigationViewItem: createNavigationViewItem
        )
    }

    /// 构建仅用于分组的节点
    static func group(
        id: String,
        labelKey: String,
        literalLabel: String? = nil,
        glyph: String? = nil,
        initiallyExpanded: Bool = true,
        children: [NavigationNode],
        actionGlyph: String? = nil,
        actionHandler: (@Sendable () -> Void)? = nil,
        pageFactory: (@Sendable (PageContext) -> AppPage)? = nil,
        createNavigationViewItem: (@Sendable () -> WinUI.NavigationViewItem)? = nil,
        useCustomItem: Bool = false
    ) -> NavigationNode {
        NavigationNode(
            id: id,
            labelKey: labelKey,
            literalLabel: literalLabel,
            glyph: glyph,
            initiallyExpanded: initiallyExpanded,
            makePage: pageFactory,
            children: children,
            actionGlyph: actionGlyph,
            actionHandler: actionHandler,
            useCustomItem: useCustomItem,
            createNavigationViewItem: createNavigationViewItem
        )
    }
}

extension NavigationNode {
    /// 返回更新子节点后的新节点副本
    func updating(children newChildren: [NavigationNode]) -> NavigationNode {
        NavigationNode(
            id: id,
            labelKey: labelKey,
            literalLabel: literalLabel,
            glyph: glyph,
            initiallyExpanded: initiallyExpanded,
            makePage: makePage,
            children: newChildren,
            actionGlyph: actionGlyph,
            actionHandler: actionHandler,
            useCustomItem: useCustomItem,
            createNavigationViewItem: createNavigationViewItem
        )
    }
}

/// 导航节点所属区域
public enum NavigationSection: Sendable {
    case menu
    case footer
}

/// 定义导航树的全部节点。
enum NavigationCatalog {
    /// 顶部（主菜单）节点
    ///
    /// 要扩展二级、三级导航，只需在此处组合 `NavigationNode.group` 和 `NavigationNode.leaf`
    ///，例如：
    ///
    /// ```swift
    /// .group(
    ///     id: "samples",
    ///     labelKey: "samples",
    ///     glyph: "\u{E14C}",
    ///     children: [
    ///         .leaf(id: "sample-detail", labelKey: "home", pageFactory: { HomePage(context: $0) })
    ///     ]
    /// )
    /// ```
    nonisolated(unsafe) private static var menuNodesStorage: [NavigationNode] = []

    /// 页脚节点（显示在 FooterMenuItems）
    nonisolated(unsafe) private static var footerNodesStorage: [NavigationNode] = [
        .leaf(
            id: "settings",
            labelKey: "settings",
            glyph: "\u{E713}",
            pageFactory: { SettingsPage(context: $0) }
        )
    ]

    static var menuNodes: [NavigationNode] { menuNodesStorage }
    static var footerNodes: [NavigationNode] { footerNodesStorage }

    /// 添加导航节点
    @discardableResult
    static func addNode(
        _ node: NavigationNode,
        toParent parentId: String? = nil,
        in section: NavigationSection = .menu
    ) -> Bool {
        guard nodesById[node.id] == nil else {
            return false
        }

        switch section {
        case .menu:
            let (updated, inserted) = insert(node: node, parentId: parentId, in: menuNodesStorage)
            if inserted {
                menuNodesStorage = updated
            }
            return inserted
        case .footer:
            let (updated, inserted) = insert(node: node, parentId: parentId, in: footerNodesStorage)
            if inserted {
                footerNodesStorage = updated
            }
            return inserted
        }
    }

    /// 删除导航节点
    @discardableResult
    static func removeNode(
        withId nodeId: String,
        in section: NavigationSection? = nil
    ) -> Bool {
        var removed = false

        if section == nil || section == .menu {
            let (updatedMenu, didRemove) = delete(nodeId: nodeId, in: menuNodesStorage)
            if didRemove {
                menuNodesStorage = updatedMenu
                removed = true
            }
        }

        if !removed && (section == nil || section == .footer) {
            let (updatedFooter, didRemove) = delete(nodeId: nodeId, in: footerNodesStorage)
            if didRemove {
                footerNodesStorage = updatedFooter
                removed = true
            }
        }

        return removed
    }

    /// 默认选中节点 ID（优先选择顶部可导航节点）
    static var defaultNodeId: String {
        firstSelectableNode(in: menuNodesStorage)?.id
            ?? firstSelectableNode(in: footerNodesStorage)?.id
            ?? menuNodesStorage.first?.id
            ?? footerNodesStorage.first?.id
            ?? ""
    }

    /// 导航树中所有节点
    static var allNodes: [NavigationNode] {
        (menuNodesStorage + footerNodesStorage).flatMap { $0.flattened() }
    }

    /// 根据 ID 获取节点
    static func node(for id: String) -> NavigationNode? {
        nodesById[id]
    }

    private static var nodesById: [String: NavigationNode] {
        Dictionary(uniqueKeysWithValues: allNodes.map { ($0.id, $0) })
    }

    private static func firstSelectableNode(in nodes: [NavigationNode]) -> NavigationNode? {
        for node in nodes {
            if let match = node.firstSelectableDescendant() {
                return match
            }
        }
        return nil
    }

    private static func insert(
        node: NavigationNode,
        parentId: String?,
        in nodes: [NavigationNode]
    ) -> ([NavigationNode], Bool) {
        guard let parentId else {
            var updated = nodes
            updated.append(node)
            return (updated, true)
        }

        var inserted = false
        var resultingNodes: [NavigationNode] = []
        resultingNodes.reserveCapacity(nodes.count)

        for current in nodes {
            if current.id == parentId {
                var children = current.children
                children.append(node)
                resultingNodes.append(current.updating(children: children))
                inserted = true
            } else {
                let (updatedChildren, didInsert) = insert(node: node, parentId: parentId, in: current.children)
                if didInsert {
                    resultingNodes.append(current.updating(children: updatedChildren))
                    inserted = true
                } else {
                    resultingNodes.append(current)
                }
            }
        }

        return inserted ? (resultingNodes, true) : (nodes, false)
    }

    private static func delete(
        nodeId: String,
        in nodes: [NavigationNode]
    ) -> ([NavigationNode], Bool) {
        var removed = false
        var remaining: [NavigationNode] = []
        remaining.reserveCapacity(nodes.count)

        for current in nodes {
            if current.id == nodeId {
                removed = true
                continue
            }

            let (updatedChildren, childRemoved) = delete(nodeId: nodeId, in: current.children)
            if childRemoved {
                remaining.append(current.updating(children: updatedChildren))
                removed = true
            } else {
                remaining.append(current)
            }
        }

        return (remaining, removed)
    }
}
