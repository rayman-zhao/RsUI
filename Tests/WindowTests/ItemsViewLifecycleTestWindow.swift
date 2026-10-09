import Foundation
import RsFoundation
import UWP
import WinAppSDK
import WinUI

@testable import RsUI

/// ItemsView / ItemsIndexView 生命周期自驱动测试窗口（无人值守，跑完自动结束进程）。
///
/// 字符串味阶段（unloadView crash 隔离）：
/// 1. `setIds(5000)`：有限高度窗口应只实现化少量条目（虚拟化生效），
///    每次实现化都会走 fillContainer → `container.tag = id` 装箱路径；
/// 2. 滚动内部 ScrollView 到中部：触发滚动回收（elementClearing →
///    unloadView，含 tag 反查解箱），此为布局过程中最敏感的路径；
/// 3. `setIds([])`：所有实现化过的条目都应收到卸载回调。
///
/// 索引味阶段（零装箱路径 + 顺移对账 + 回收池回归）：
/// 4. `setCount(5000)`：虚拟化同上；条目内容按索引构建，全程不读回向量元素值；
/// 5. `insert(200, at: 0)`、中部 `removeIndexes`、滚动中部再滚回顶部、二轮
///    插入+移除：索引顺移/视口移动后映射容器内容必须精确等于其索引（原生
///    elementPrepared 重发与 reconcile 对账幂等共存）。首个带过渡动画的换窗
///    可能一次性新建补池（旧窗口容器在动画器手里未归池），以换窗后数量为
///    封顶值，其后一切操作不得再增长——回收池生效的判据（无池工厂的旧行为
///    是停放的已清除容器单调累积）；
/// 6. `setCount(0)`：所有实现化过的索引都应收到卸载回调（displayedIndex
///    Swift 属性反查路径，无 tag 装箱解箱）。字符串味重置（阶段3）同样校验
///    容器数不增长。
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

    private let testIndexView = ItemsIndexView { _ in
        let block = TextBlock()
        block.text = "item"
        block.padding = Thickness(left: 8, top: 6, right: 8, bottom: 6)
        return block
    }

    private var realizedIds: Set<String> = []
    private var unloadedIds: Set<String> = []
    private var realizedIndexes: Set<Int> = []
    private var unloadedIndexes: Set<Int> = []
    private var makeViewCalls = 0
    private var failures: [String] = []

    private let totalIds = 5000
    private let totalIndexes = 5000

    override init() {
        super.init()
        title = "ItemsView Lifecycle Test"
        content = makeRoot()
        runScenario()
    }

    private func makeRoot() -> FrameworkElement {
        // 主线程计数闭包在 super.init 之后挂（构造期两个列表已创建，此处只挂回调）
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
        testIndexView.makeView = { [weak self] index in
            guard let self else { return TextBlock() }
            self.realizedIndexes.insert(index)
            self.makeViewCalls += 1
            let block = TextBlock()
            block.text = "item \(index)"
            block.padding = Thickness(left: 8, top: 6, right: 8, bottom: 6)
            return block
        }
        testIndexView.unloadView = { [weak self] index in
            self?.unloadedIndexes.insert(index)
        }

        let stackLayout = StackLayout()
        stackLayout.spacing = 4
        testItemsView.layout = stackLayout
        testItemsView.selectionMode = .single
        testIndexView.layout = stackLayout
        // 两个列表同占 star 行互斥显示：字符串味先跑，阶段4切换到索引味。
        testIndexView.visibility = .collapsed

        let listsHost = Grid()
        listsHost.children.append(testItemsView)
        listsHost.children.append(testIndexView)

        let status = TextBlock()
        status.text = "running…"

        let statusRow = RowDefinition()
        statusRow.height = GridLength(value: 0, gridUnitType: .auto)
        let listRow = RowDefinition()
        listRow.height = GridLength(value: 1, gridUnitType: .star)

        let root = Grid()
        root.rowDefinitions.append(statusRow)
        root.rowDefinitions.append(listRow)
        root.children.append(listsHost)
        _ = try? Grid.setRow(listsHost, 1)
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
            let stringContainers = ItemsViewBase.descendants(
                ofType: ItemContainer.self, from: self.testItemsView).count
            log.info(
                "IVLT: 阶段1 字符串味容器共 \(stringContainers)（含 repeater 停放的已清除容器，两味共有行为）")

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

            // 阶段3：整体重置，所有实现化过的条目都应收到卸载回调；
            // 回收池生效后容器总数不应随重置增长（清除即入池、再装填取池）
            let stringCountBeforeReset = ItemsViewBase.descendants(
                ofType: ItemContainer.self, from: self.testItemsView).count
            self.testItemsView.setIds([])
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let neverUnloaded = self.realizedIds.subtracting(self.unloadedIds)
            self.check(
                neverUnloaded.isEmpty,
                "阶段3: \(neverUnloaded.count) 个条目重置后未收到 unloadView（如 \(neverUnloaded.sorted().first ?? "?")）")
            let stringCountAfterReset = ItemsViewBase.descendants(
                ofType: ItemContainer.self, from: self.testItemsView).count
            self.checkContainerCount(
                stringCountAfterReset, highWater: stringCountBeforeReset,
                "阶段3: 字符串味重置后容器未复用（回收池未生效）")

            // 阶段4：切到索引味，装填并检查虚拟化（零装箱路径）
            self.testItemsView.visibility = .collapsed
            self.testIndexView.visibility = .visible
            self.testIndexView.setCount(self.totalIndexes)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.check(
                self.realizedIndexes.count > 0,
                "阶段4: 索引味无条目实现化（makeView 从未调用）")
            self.check(
                self.realizedIndexes.count < self.totalIndexes,
                "阶段4: 索引味虚拟化失效，实现化了全部 \(self.realizedIndexes.count) 条")
            self.checkMappedRows("阶段4: 初始装填")
            let indexHighWater = ItemsViewBase.descendants(
                ofType: ItemContainer.self, from: self.testIndexView).count

            // 阶段5：顶部插入 + 中部移除，顺移后映射容器内容必须与索引一致；
            // 容器复用经回收池消化。首个带过渡动画的换窗可能一次性新建补池
            // （旧窗口容器在动画器手里未归池），以换窗后的数量为封顶值，
            // 其后一切操作（移除/滚动/二轮插入移除）都不得再增长。
            let callsBeforeInsert = self.makeViewCalls
            let realizedBeforeInsert = self.realizedIndexes
            self.testIndexView.insert(200, at: 0)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.checkMappedRows("阶段5: 顶部插入后")
            let stabilizedContainers = ItemsViewBase.descendants(
                ofType: ItemContainer.self, from: self.testIndexView).count
            log.info(
                "IVLT: 换窗后容器封顶 \(stabilizedContainers)（装填 \(indexHighWater) + 动画换窗期新建）")
            let rebuildsAfterInsert = self.makeViewCalls - callsBeforeInsert
                - (self.realizedIndexes.subtracting(realizedBeforeInsert).count)
            log.info(
                "IVLT: insert 后重复构建 \(rebuildsAfterInsert) 条（>0 = 原生对顺移容器重发了 elementPrepared；=0 = 全靠 reconcile 对账重填）")

            self.testIndexView.removeIndexes(Array(1500..<1600))
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.checkMappedRows("阶段5: 中部移除后")
            self.checkContainerCount(
                nil, highWater: stabilizedContainers, "阶段5: 中部移除后容器增长（回收池未生效）")

            // 阶段5.5：滚动到中部再滚回顶部，跨视口移动容器全部取池
            if let indexScrollView = Self.findDescendantScrollView(from: self.testIndexView),
                indexScrollView.scrollableHeight > 0
            {
                _ = try? indexScrollView.scrollTo(0, indexScrollView.scrollableHeight / 2)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.checkMappedRows("阶段5: 滚动到中部后")
                self.checkContainerCount(
                    nil, highWater: stabilizedContainers, "阶段5: 滚动后容器增长（回收池未生效）")
                _ = try? indexScrollView.scrollTo(0, 0)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.checkMappedRows("阶段5: 滚回顶部后")
                self.checkContainerCount(
                    nil, highWater: stabilizedContainers, "阶段5: 滚回后容器增长（回收池未生效）")
            }

            // 阶段5.6：二轮插入+移除——池已覆盖全部工作集，任何增长即泄漏
            self.testIndexView.insert(50, at: 0)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.checkMappedRows("阶段5(二轮): 顶部插入后")
            self.checkContainerCount(
                nil, highWater: stabilizedContainers, "阶段5(二轮): 插入后容器增长（回收池未生效）")
            self.testIndexView.removeIndexes(Array(2000..<2100))
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.checkMappedRows("阶段5(二轮): 中部移除后")
            self.checkContainerCount(
                nil, highWater: stabilizedContainers, "阶段5(二轮): 移除后容器增长（回收池未生效）")

            // 阶段6：整体清空，所有实现化过的索引都应收到卸载回调
            self.testIndexView.setCount(0)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let neverUnloadedIndexes = self.realizedIndexes.subtracting(self.unloadedIndexes)
            self.check(
                neverUnloadedIndexes.isEmpty,
                "阶段6: \(neverUnloadedIndexes.count) 个索引重置后未收到 unloadView（如 \(neverUnloadedIndexes.sorted().first.map(String.init) ?? "?")）")

            self.report()
        }
    }

    /// 回收池回归断言：容器总数不应超过给定高水位（清除即入池、再实现化取池；
    /// 无池工厂的旧行为是每次实现化新建、停放的已清除容器单调累积）。
    /// count 传 nil 时统计索引味当前容器数。
    private func checkContainerCount(_ count: Int?, highWater: Int, _ message: String) {
        let actual = count ?? ItemsViewBase.descendants(
            ofType: ItemContainer.self, from: testIndexView).count
        log.info("IVLT: 容器数 \(actual)（高水位 \(highWater)）")
        check(actual <= highWater, "\(message)：容器 \(actual) 超过高水位 \(highWater)")
    }

    /// 索引味顺移一致性断言：被 repeater 映射的容器（`getElementIndex >= 0`）
    /// 内容必须精确等于其索引——比连续性更强，直接覆盖"顺移后内容停留旧索引"
    /// 的失败形态（原生未重发 elementPrepared 且 reconcile 未对上）。
    /// repeater 停放的已清除容器（映射为 -1，两味共有行为）不参与断言，
    /// 只经 `checkContainerCount` 约束不无界累积。
    private func checkMappedRows(_ stage: String) {
        let containers = ItemsViewBase.descendants(
            ofType: ItemContainer.self, from: testIndexView)
        guard let repeater = ItemsViewBase.descendants(
            ofType: WinUI.ItemsRepeater.self, from: testIndexView
        ).first else {
            check(false, "\(stage): 未找到内部 ItemsRepeater")
            return
        }
        var mapped = 0
        var parked = 0
        var mismatches: [String] = []
        for container in containers {
            guard let index = try? repeater.getElementIndex(container), index >= 0 else {
                parked += 1
                continue
            }
            mapped += 1
            let text = (container.child as? TextBlock)?.text
            let number = text.flatMap {
                $0.hasPrefix("item ") ? Int($0.dropFirst("item ".count)) : nil
            }
            if number != Int(index) {
                mismatches.append("index \(index) 显示 \(number.map(String.init) ?? "nil")")
            }
        }
        log.info(
            "IVLT: \(stage) 映射容器 \(mapped)/共 \(containers.count)（停放未映射 \(parked)）")
        check(
            mismatches.isEmpty,
            "\(stage): \(mismatches.count) 个映射容器内容与索引不符（\(mismatches.prefix(3).joined(separator: "；"))）")
        check(mapped >= 2, "\(stage): 可校验的映射行不足（\(mapped) 行）")
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
                "IVLT: ALL PASS — ids realized=\(realizedIds.count) unloaded=\(unloadedIds.count); indexes realized=\(realizedIndexes.count) unloaded=\(unloadedIndexes.count)")
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
