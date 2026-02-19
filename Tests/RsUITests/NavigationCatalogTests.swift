import Foundation
import Testing
import WinUI
@testable import RsUI

/// 导航目录系统的单元测试
/// 测试目的：验证导航树的构建、查询、添加和删除功能
@Suite("Navigation Catalog Tests")
struct NavigationCatalogTests {
    /// 虚拟页面类：用于测试导航时的页面工厂方法
    /// 实现最小的 AppPage 协议以支持测试
    private final class DummyPage: AppPage {
        private let root = WinUI.Grid()
        var rootView: WinUI.UIElement { root }

        func applyTheme(_ theme: AppTheme) {}

        func updateLocalization(language: AppLanguage) {}

        func onAppearanceChanged() {}
    }

    /// 测试：验证 firstSelectableDescendant() 能否在多层级导航树中找到可选择的叶子节点
    /// 场景：
    /// - 创建一个分组节点（无页面工厂）
    /// - 该分组包含一个可选择的叶子节点（有页面工厂）
    /// - 从分组节点查找第一个可选择的后代
    /// 检查项：
    /// - 能否正确返回叶子节点
    /// - 返回的节点 ID 是否为 "dummy-leaf"
    /// 目的：测试导航树的层级遍历和节点查找逻辑
    @Test("firstSelectableDescendant finds leaf")
    func testFirstSelectableDescendantFindsLeafInHierarchy() {
        let selectable = NavigationNode(
            id: "dummy-leaf",
            labelKey: "home",
            glyph: nil,
            initiallyExpanded: false,
            makePage: { _ in DummyPage() },
            children: []
        )
        let group = NavigationNode(
            id: "dummy-group",
            labelKey: "home",
            glyph: nil,
            initiallyExpanded: true,
            makePage: nil,
            children: [selectable]
        )

        let result = group.firstSelectableDescendant()
        #expect(result?.id == "dummy-leaf")
    }

    /// 测试：验证 flattened() 方法能否将多层级导航树转换为平面列表
    /// 场景：
    /// - 创建一个根节点
    /// - 根节点包含一个子节点
    /// - 调用 flattened() 将树结构展平
    /// 检查项：
    /// - 返回的平面列表中是否包含根节点和子节点
    /// - 节点顺序是否正确（先根后子）
    /// - 列表中节点数量是否为 2
    /// 目的：测试导航树的扁平化功能（用于全局搜索或遍历）
    @Test("flattened includes all descendants")
    func testFlattenedIncludesAllDescendants() {
        let child = NavigationNode(
            id: "child",
            labelKey: "settings",
            glyph: nil,
            initiallyExpanded: false,
            makePage: nil,
            children: []
        )
        let root = NavigationNode(
            id: "root",
            labelKey: "home",
            glyph: nil,
            initiallyExpanded: true,
            makePage: nil,
            children: [child]
        )

        let flattened = root.flattened()
        #expect(flattened.map { $0.id } == ["root", "child"])
    }

    /// 测试：验证导航节点的添加和删除功能
    /// 场景：
    /// 1. 创建一个新导航节点
    /// 2. 将其添加到菜单区域（.menu）
    /// 3. 验证节点已成功添加
    /// 4. 从目录中删除该节点
    /// 5. 验证节点已成功删除
    /// 检查项：
    /// - addNode() 是否返回 true（插入成功）
    /// - 插入后能否通过 node(for:) 查询到该节点
    /// - removeNode() 是否返回 true（删除成功）
    /// - 删除后 node(for:) 是否返回 nil
    /// 目的：测试导航目录的增删操作（支持动态菜单）
    @Test("add and remove node in menu section")
    func testAddAndRemoveNodeInMenuSection() {
        let nodeId = "test-node-\(UUID().uuidString)"
        let node = NavigationNode(
            id: nodeId,
            labelKey: "home",
            glyph: nil,
            initiallyExpanded: false,
            makePage: nil,
            children: []
        )

        let inserted = NavigationCatalog.addNode(node, in: .menu)
        #expect(inserted)
        #expect(NavigationCatalog.node(for: nodeId)?.id == nodeId)

        let removed = NavigationCatalog.removeNode(withId: nodeId)
        #expect(removed)
        #expect(NavigationCatalog.node(for: nodeId) == nil)
    }

    /// 测试：验证在导航树中为已存在的父节点添加子节点
    /// 场景：
    /// 1. 创建并添加一个父节点到菜单
    /// 2. 创建一个子节点
    /// 3. 将子节点添加为父节点的子项
    /// 4. 验证父节点的子列表中是否包含新子节点
    /// 检查项：
    /// - 子节点添加是否返回 true（插入成功）
    /// - 重新查询父节点时是否包含子节点 ID
    /// - 父节点的 children 数组是否正确更新
    /// 目的：测试嵌套导航的创建和管理（支持多级菜单）
    @Test("add node as child of existing parent")
    func testAddNodeAsChildOfExistingParent() {
        let parentId = "test-parent-\(UUID().uuidString)"
        let childId = "test-child-\(UUID().uuidString)"

        let parent = NavigationNode(
            id: parentId,
            labelKey: "home",
            glyph: nil,
            initiallyExpanded: true,
            makePage: nil,
            children: []
        )
        #expect(NavigationCatalog.addNode(parent, in: .menu))
        defer { _ = NavigationCatalog.removeNode(withId: parentId) }

        let child = NavigationNode(
            id: childId,
            labelKey: "settings",
            glyph: nil,
            initiallyExpanded: false,
            makePage: nil,
            children: []
        )

        #expect(NavigationCatalog.addNode(child, toParent: parentId, in: .menu))
        defer { _ = NavigationCatalog.removeNode(withId: childId) }

        let fetchedParent = NavigationCatalog.node(for: parentId)
        #expect(fetchedParent != nil)
        let hasChild = fetchedParent?.children.contains { $0.id == childId } ?? false
        #expect(hasChild)
    }
}
