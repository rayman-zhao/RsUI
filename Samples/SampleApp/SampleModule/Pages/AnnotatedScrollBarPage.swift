import Foundation
import WinAppSDK
import RsUI
import WinUI
import WindowsFoundation

/// AnnotatedScrollBar 投影可用性验证页（经公共 `RsUI.AnnotatedScrollBar` 封装接线）。
///
/// 覆盖面：
/// - 接线一：ScrollView 形态——binder 在 `loaded` 后取 `scrollPresenter` 连
///   `verticalScrollController`（模板应用前 scrollPresenter 为 nil）。
/// - 接线二：框架 ItemsView 直连（依赖属性，直通内部 ScrollPresenter）。
/// - 标签：固定行高使 scrollOffset 可按像素预计算；文本经 DataTemplateSelector
///   提供（默认模板的属性绑定在 swift-winui 下取不到文本，见 binder 注释）；
///   标签空闲时淡出、指针悬停滚动条时点亮是系统行为。
/// - `detailLabelRequested`（悬停 tooltip）、`scrolling`（kind/offset/cancel）、
///   `smallChange`（箭头步进）经 binder 的 detailText / onScrolling 参数驱动。
final class AnnotatedScrollBarPage: RsUI.Page {
    let url = URL(string: "rs://\(sampleModuleID)/annotated-scroll-bar")!
    var title: String { tr("Annotated ScrollBar") }

    var header: Any? {
        featurePageHeader(
            title: tr("Annotated ScrollBar"),
            description: tr(
                "Verifies the AnnotatedScrollBar projection end to end: wiring to a ScrollView via ScrollPresenter.VerticalScrollController, wiring to the framework ItemsView via its VerticalScrollController property, Labels populated through the projected IVector, the DetailLabelRequested event, the Scrolling event with Cancel, and SmallChange."
            )
        )
    }

    var content: WinUI.UIElement {
        // 事件回显：闭包强捕获这些纯投影控件（无弱引用生命周期，遵守捕获规则），
        // 生命周期与页面视图一致（页面重建即整体重建）。
        var eventCount = 0
        let cancelToggle = ToggleSwitch()
        cancelToggle.header = tr("Cancel scrolling (args.cancel)")
        cancelToggle.onContent = tr("On")
        cancelToggle.offContent = tr("Off")

        let statusText = makeCaption(
            tr("Interact with the scrollbar on the right; Scrolling events will show up here."))

        // —— 演示一：ScrollView 接线 ——
        let listPanel = StackPanel()
        for (groupIndex, letter) in Self.groupLetters.enumerated() {
            listPanel.children.append(Self.makeGroupHeaderRow(letter))
            for row in 0..<Self.rowsPerGroup {
                let index = groupIndex * Self.rowsPerGroup + row
                listPanel.children.append(
                    Self.makeRow(String(format: tr("Item %02d"), Int32(index))))
            }
        }

        let scrollView = ScrollView()
        scrollView.content = listPanel

        let scrollBar = RsUI.AnnotatedScrollBar(
            smallChange: Self.groupStride,
            labels: {
                Self.groupLetters.enumerated().map {
                    AnnotatedScrollBarLabelSpec(
                        text: $0.element, scrollOffset: Double($0.offset) * Self.groupStride)
                }
            },
            detailText: { offset in
                let group = min(
                    Self.groupLetters.count - 1,
                    max(0, Int(offset / Self.groupStride)))
                let first = group * Self.rowsPerGroup
                return String(
                    format: tr("Group %@ · rows %d–%d"),
                    Self.groupLetters[group], Int32(first),
                    Int32(first + Self.rowsPerGroup - 1))
            })
        scrollBar.onScrolling = { args in
            eventCount += 1
            let canceled = cancelToggle.isOn
            if canceled { args.cancel = true }
            statusText.text = String(
                format: tr("Scrolling #%d: %@ · offset %d%@"),
                Int32(eventCount), Self.eventKindName(args.scrollingEventKind),
                Int32(args.scrollOffset), canceled ? tr(" (canceled)") : "")
        }
        scrollBar.attach(to: scrollView)

        let demo1 = Self.makeSideBySide(content: scrollView, scrollBar: scrollBar)
        // 固定高度：页面在 ScrollViewer 内布局（见下），不能依赖 star 行分配空间。
        demo1.height = 320

        // —— 演示二：框架 ItemsIndexView 直连 ——
        let list = RsUI.ItemsIndexView { index in
            Self.makeRow(String(format: tr("Item %02d"), Int32(index)))
        }
        list.setCount(Self.itemsViewCount)

        let scrollBar2 = RsUI.AnnotatedScrollBar(
            smallChange: Self.rowHeight * 3,
            labels: {
                (0..<4).map {
                    AnnotatedScrollBarLabelSpec(
                        text: "Q\($0 + 1)",
                        scrollOffset: Double($0 * Self.itemsViewCount / 4) * Self.rowHeight)
                }
            },
            detailText: { offset in
                String(
                    format: tr("≈ item %d of %d"),
                    Int32(offset / Self.rowHeight), Int32(Self.itemsViewCount))
            },
            labelAlignment: .leading,
            detailLabelMode: .native)
        scrollBar2.attach(to: list)

        let demo2 = Self.makeSideBySide(content: list, scrollBar: scrollBar2)
        demo2.height = 240

        // —— 组装：整页进垂直 ScrollViewer（与 featurePageContent 同模式）。
        // 页面固定高度内容较多（两个演示块），小窗口下星行会被压扁甚至挤零，
        // 换成可滚动整页 + 演示块固定高度，任何窗口尺寸下两个演示都完整可见。
        let statusRow = Grid()
        let statusColumn = ColumnDefinition()
        statusColumn.width = GridLength(value: 1, gridUnitType: .star)
        let toggleColumn = ColumnDefinition()
        toggleColumn.width = GridLength(value: 0, gridUnitType: .auto)
        statusRow.columnDefinitions.append(statusColumn)
        statusRow.columnDefinitions.append(toggleColumn)
        statusText.verticalAlignment = .center
        try? Grid.setColumn(statusText, 0)
        try? Grid.setColumn(cancelToggle, 1)
        statusRow.children.append(statusText)
        statusRow.children.append(cancelToggle)
        statusRow.margin = Thickness(left: 0, top: 0, right: 0, bottom: 12)

        let section1 = Self.makeSection(
            title: tr("Wired to ScrollView"),
            code: "AnnotatedScrollBar(smallChange:labels:detailText:).attach(to: scrollView)",
            caption: tr("Photos-style: hover detail label is a custom overlay that tracks the pointer without jitter; labels trail flush against the rail."))
        let section2 = Self.makeSection(
            title: tr("Wired to ItemsView"),
            code: "AnnotatedScrollBar(...).attach(to: itemsView)",
            caption: tr("For comparison: native detail-label ToolTip (slight jitter on move) and leading-aligned labels away from the rail."),
            topMargin: 16)

        let stack = StackPanel()
        stack.children.append(statusRow)
        stack.children.append(section1)
        stack.children.append(demo1)
        stack.children.append(section2)
        stack.children.append(demo2)

        // 页面级滚动条设 hidden：小窗口下页面溢出时它出现在最右缘、紧挨注记滚动条，
        // 视觉上像“原滚动条没被替换掉”；隐藏后页面上可见的滚动条只剩注记滚动条
        //（hidden 只是不显示，滚轮翻页不受影响）。
        let pageScroll = ScrollViewer()
        pageScroll.verticalScrollBarVisibility = .hidden
        pageScroll.content = stack

        let root = Grid()
        root.padding = Thickness(left: 40, top: 0, right: 40, bottom: 32)
        // 整页强制箭头光标：标签 ContentPresenter 的命中区会溢出滚动条控件边界，
        // 文本命中使光标变成异常形状（实测 I 型；用户机器上报左右调整箭头），
        // 逐元素关闭命中测试与控件级 protectedCursor 都覆盖不到溢出区，
        // 页面级 protectedCursor 一律压回箭头（本页无文本选择交互，行为无损）。
        root.protectedCursor = try? InputSystemCursor.create(.arrow)
        root.children.append(pageScroll)

        return root
    }

    // MARK: - Demo data

    private static let groupLetters = ["A", "B", "C", "D", "E", "F"]
    private static let rowsPerGroup = 30
    private static let headerRowHeight: Double = 40
    private static let rowHeight: Double = 32
    private static let itemsViewCount = 120
    /// 一组占用的内容高度（组头 + N 行），兼作标签间隔与 SmallChange。
    private static var groupStride: Double { headerRowHeight + Double(rowsPerGroup) * rowHeight }

    // MARK: - Row factories

    /// 固定行高的普通行（两处演示共用；行高固定保证标签 offset 可预计算）。
    private static func makeRow(_ text: String) -> UIElement {
        let block = TextBlock()
        block.text = text
        block.fontSize = 13
        block.verticalAlignment = .center
        block.margin = Thickness(left: 16, top: 0, right: 0, bottom: 0)
        // 行文本命中测试关闭：TextBlock 布局框被拉伸到整列宽，命中区会延伸到
        // 滚动条标签下方，悬停标签时光标变成 I 型/异常形状；行本身无点击交互
        //（demo2 的选择命中由 ItemContainer 承担），关掉不影响任何行为。
        block.isHitTestVisible = false

        let row = Border()
        row.height = rowHeight
        row.child = block
        return row
    }

    private static func makeGroupHeaderRow(_ letter: String) -> UIElement {
        let block = TextBlock()
        block.text = String(format: tr("Group %@"), letter)
        block.fontSize = 14
        block.verticalAlignment = .center
        block.margin = Thickness(left: 12, top: 0, right: 0, bottom: 0)

        let row = Border()
        row.height = headerRowHeight
        row.background = themeBrush("CardBackgroundFillColorDefaultBrush")
        row.child = block
        return row
    }

    /// 内容 + 注记滚动条并排（两列：* 内容、auto 滚动条）；两侧同高，滚动映射天然对齐。
    private static func makeSideBySide(content: FrameworkElement, scrollBar: RsUI.AnnotatedScrollBar) -> Grid {
        let grid = Grid()
        let contentColumn = ColumnDefinition()
        contentColumn.width = GridLength(value: 1, gridUnitType: .star)
        let barColumn = ColumnDefinition()
        barColumn.width = GridLength(value: 0, gridUnitType: .auto)
        grid.columnDefinitions.append(contentColumn)
        grid.columnDefinitions.append(barColumn)
        scrollBar.margin = Thickness(left: 4, top: 0, right: 0, bottom: 0)
        try? Grid.setColumn(content, 0)
        try? Grid.setColumn(scrollBar, 1)
        grid.children.append(content)
        grid.children.append(scrollBar)
        return grid
    }

    /// 小节标题 + 接线代码行 + 说明。代码行不本地化（是 API 调用文档）。
    private static func makeSection(title: String, code: String, caption: String, topMargin: Double = 0) -> StackPanel {
        let section = StackPanel()
        section.spacing = 2
        section.margin = Thickness(left: 0, top: topMargin, right: 0, bottom: 8)
        section.children.append(makeSectionTitle(title))
        section.children.append(makeSectionSubtitle(code))
        section.children.append(makeCaption(caption))
        return section
    }

    private static func eventKindName(
        _ kind: WinUI.AnnotatedScrollBarScrollingEventKind
    ) -> String {
        if kind == .drag { return "drag" }
        if kind == .incrementButton { return "incrementButton" }
        if kind == .decrementButton { return "decrementButton" }
        return "click"
    }
}
