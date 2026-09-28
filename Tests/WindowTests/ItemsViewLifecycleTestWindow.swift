import Foundation
import RsFoundation
import UWP
import WinAppSDK
import WinUI

@testable import RsUI

/// ItemsView 生命周期自驱动测试窗口（无人值守，跑完自动结束进程）。
///
/// 针对 unloadView 改动的 crash 隔离测试，覆盖三个阶段：
/// 1. `setIds(5000)`：有限高度窗口应只实现化少量条目（虚拟化生效），
///    每次实现化都会走 fillContainer → `container.tag = id` 装箱路径；
/// 2. 滚动内部 ScrollView 到中部：触发滚动回收（elementClearing →
///    unloadView，含 tag 反查解箱），此为布局过程中最敏感的路径；
/// 3. `setIds([])`：所有实现化过的条目都应收到卸载回调。
///
/// 每阶段校验计数并输出 `IVLT:` 前缀日志，全部通过 exit(0)，断言失败或
/// 中途 crash（进程非零退出）即为 RsUI 侧问题。
final class ItemsViewLifecycleTestWindow: Window {

    private let testItemsView = ItemsView { _ in
        let block = TextBlock()
        block.text = "item"
        block.padding = Thickness(left: 8, top: 6, right: 8, bottom: 6)
        return block
    }

    private var realizedIds: Set<String> = []
    private var unloadedIds: Set<String> = []
    private var failures: [String] = []

    private let totalIds = 5000

    override init() {
        super.init()
        title = "ItemsView Lifecycle Test"
        content = makeRoot()
        runScenario()
    }

    private func makeRoot() -> FrameworkElement {
        // 主线程计数闭包在 super.init 之后挂（构造期 testItemsView 已创建，此处只挂回调）
        testItemsView.makeIdView = { [weak self] id in
            guard let self else { return TextBlock() }
            self.realizedIds.insert(id)
            let block = TextBlock()
            block.text = "item \(id)"
            block.padding = Thickness(left: 8, top: 6, right: 8, bottom: 6)
            return block
        }
        testItemsView.unloadView = { [weak self] id in
            self?.unloadedIds.insert(id)
        }
        let stackLayout = StackLayout()
        stackLayout.spacing = 4
        testItemsView.layout = stackLayout
        testItemsView.selectionMode = .single

        let status = TextBlock()
        status.text = "running…"

        let statusRow = RowDefinition()
        statusRow.height = GridLength(value: 0, gridUnitType: .auto)
        let listRow = RowDefinition()
        listRow.height = GridLength(value: 1, gridUnitType: .star)

        let root = Grid()
        root.rowDefinitions.append(statusRow)
        root.rowDefinitions.append(listRow)
        root.children.append(testItemsView)
        _ = try? Grid.setRow(testItemsView, 1)
        root.children.append(status)
        _ = try? Grid.setRow(status, 0)
        return root
    }

    // MARK: - 场景驱动

    private func runScenario() {
        let ids = (0..<totalIds).map(String.init)
        testItemsView.setIds(ids)

        Task { @MainActor [weak self] in
            // 阶段1：布局稳定后检查虚拟化（只应实现化远小于 totalIds 的条目）
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            let initialRealized = self.realizedIds.count
            self.check(initialRealized > 0, "阶段1: 无条目实现化（makeIdView 从未调用）")
            self.check(
                initialRealized < self.totalIds,
                "阶段1: 虚拟化失效，实现化了全部 \(initialRealized) 条")

            // 阶段2：滚动到中部触发回收
            let scrollView = Self.findDescendantScrollView(from: self.testItemsView)
            self.check(scrollView != nil, "阶段2: 未找到内部 ScrollView")
            var scrolled = false
            if let scrollView, scrollView.scrollableHeight > 0 {
                _ = try? scrollView.scrollTo(0, scrollView.scrollableHeight / 2)
                scrolled = true
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let afterScrollRealized = self.realizedIds.count
            let afterScrollUnloaded = self.unloadedIds.count
            self.check(
                afterScrollUnloaded > 0,
                "阶段2: 无 unloadView 回调（tag 反查或 elementClearing 未生效）")
            if scrolled {
                self.check(
                    afterScrollRealized > initialRealized,
                    "阶段2: 滚动后无新条目实现化（滚动未生效）")
            }

            // 阶段3：整体重置，所有实现化过的条目都应收到卸载回调
            self.testItemsView.setIds([])
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let neverUnloaded = self.realizedIds.subtracting(self.unloadedIds)
            self.check(
                neverUnloaded.isEmpty,
                "阶段3: \(neverUnloaded.count) 个条目重置后未收到 unloadView（如 \(neverUnloaded.sorted().first ?? "?")）")

            self.report()
        }
    }

    private func check(_ condition: Bool, _ message: String) {
        if condition {
            log.info("IVLT: PASS — \(message)")
        } else {
            failures.append(message)
            log.error("IVLT: FAIL — \(message)")
        }
    }

    private func report() {
        if failures.isEmpty {
            log.info(
                "IVLT: ALL PASS — realized=\(realizedIds.count) unloaded=\(unloadedIds.count)")
            exit(0)
        } else {
            for failure in failures {
                log.error("IVLT: FAILED — \(failure)")
            }
            exit(1)
        }
    }

    // MARK: - 工具

    /// 深度优先查找内部 ScrollView（ItemsView 模板使用 WinUI 3 的 ScrollView
    /// 而非旧 ScrollViewer；模板应用后有效）。
    private static func findDescendantScrollView(
        from root: DependencyObject
    ) -> ScrollView? {
        let count = (try? VisualTreeHelper.getChildrenCount(root)) ?? 0
        var index: Int32 = 0
        while index < count {
            if let child = try? VisualTreeHelper.getChild(root, index) {
                if let match = child as? ScrollView { return match }
                if let found = findDescendantScrollView(from: child) { return found }
            }
            index += 1
        }
        return nil
    }
}
