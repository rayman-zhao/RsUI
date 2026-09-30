import Foundation
import RsFoundation
import WinAppSDK
import RsUI
import WinUI
import WindowsFoundation

/// 标签模板选择器：swift-winui 应用没有 XAML 元数据提供器，控件默认标签模板里的
/// `Text={Binding Content}`（带路径的经典绑定）在运行时反射不到
/// AnnotatedScrollBarLabel 的属性，实现化出的标签文本为空、不可见（本项目实测）。
/// 这里改为在 Swift 里读取标签 content、返回文本已烘焙进 XAML 的 DataTemplate，
/// 完全绕开属性绑定。前景色按当前主题解析后注入具体色值；主题切换会整体重建页面，
/// 色值随之刷新。
///
/// 注：`detailLabelRequested` 的 tooltip 不受此问题影响——它的默认模板用的是
/// 无路径 `{Binding}`（直接取内容对象本身），而我们在事件回调里写入的是字符串。
final class AnnotatedScrollBarLabelTemplateSelector: WinUI.DataTemplateSelector {
    private let templatesByOffset: [Double: WinUI.DataTemplate]

    /// labels: 每个标签的文本与 scrollOffset（一一对应，offset 作键——content 读回
    /// 是装箱的 IInspectable，`as? String` 桥不回，而 scrollOffset 是值类型直读可靠）。
    init(labels: [(content: String, offset: Double)]) {
        let foregroundHex = Self.resolvedForegroundHex()
        var xaml = """
        <ResourceDictionary
            xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
        """
        for (index, label) in labels.enumerated() {
            xaml += """

                <DataTemplate x:Key="L\(index)">
                    <Border IsHitTestVisible="False">
                        <TextBlock
                            Margin="0,-5,0,-2"
                            HorizontalAlignment="Right"
                            HorizontalTextAlignment="Right"
                            FontSize="12"
                            FontWeight="SemiBold"
                            Foreground="\(foregroundHex)"
                            Text="\(label.content)"
                            TextWrapping="NoWrap" />
                    </Border>
                </DataTemplate>
            """
        }
        xaml += "\n        </ResourceDictionary>"

        let dictionary: WinUI.ResourceDictionary = App.context.requireXaml(withString: xaml)
        var map: [Double: WinUI.DataTemplate] = [:]
        for (index, label) in labels.enumerated() {
            guard let template = dictionary.lookup("L\(index)") as? WinUI.DataTemplate else {
                fatalError("label template L\(index) not found in loaded ResourceDictionary")
            }
            map[label.offset] = template
        }
        templatesByOffset = map
        super.init()
    }

    override func selectTemplateCore(
        _ item: Any!, _ container: WinUI.DependencyObject!
    ) throws -> WinUI.DataTemplate! {
        template(for: item)
    }

    override func selectTemplateCore(_ item: Any!) throws -> WinUI.DataTemplate! {
        template(for: item)
    }

    private func template(for item: Any!) -> WinUI.DataTemplate! {
        guard let label = item as? WinUI.AnnotatedScrollBarLabel else {
            log.info("AnnotatedScrollBar label selector: item is not a label (\(type(of: item)))")
            return nil
        }
        guard let template = templatesByOffset[label.scrollOffset] else {
            log.info("AnnotatedScrollBar label selector: no template for offset \(label.scrollOffset)")
            return nil
        }
        return template
    }

    private static func resolvedForegroundHex() -> String {
        guard let solid = themeBrush("TextFillColorSecondaryBrush") as? SolidColorBrush else {
            return "#C8C8C8"
        }
        let color = solid.color
        return String(format: "#%02X%02X%02X%02X", color.a, color.r, color.g, color.b)
    }
}

/// 详情标签（悬浮 tooltip）模板：与控件默认模板同构（无路径 `Text="{Binding}"`，
/// 内容是 detailLabelRequested 事件里写入的字符串，不受投影元数据问题影响），
/// 仅在根节点关闭命中测试——悬停 rail 左侧标签区时 tooltip 会弹出并盖在指针下方，
/// 默认模板的文本命中区会把光标变成异常形状（实测 I 型，用户机器上报左右调整箭头）。
private func makeDetailLabelTemplate() -> WinUI.DataTemplate {
    let dictionary: WinUI.ResourceDictionary = App.context.requireXaml(withString: """
        <ResourceDictionary
            xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
            <DataTemplate x:Key="DetailLabelTemplate">
                <Border IsHitTestVisible="False">
                    <TextBlock
                        Margin="0,0,0,2"
                        HorizontalAlignment="Right"
                        Text="{Binding}"
                        TextWrapping="Wrap" />
                </Border>
            </DataTemplate>
        </ResourceDictionary>
        """)
    guard let template = dictionary.lookup("DetailLabelTemplate") as? WinUI.DataTemplate else {
        fatalError("DetailLabelTemplate not found in loaded ResourceDictionary")
    }
    return template
}

/// AnnotatedScrollBar 投影可用性验证页。
///
/// 覆盖面：
/// - 接线一：`scrollView.scrollPresenter.verticalScrollController = bar.scrollController`
///   （`AnyIScrollController` 接口值跨投影传递；`ScrollPresenter` 要等模板应用后才取得到，
///   所以在 `loaded` 里接线）。
/// - 接线二：`RsUI.ItemsView` 直连 `verticalScrollController`（依赖属性，直通内部 ScrollPresenter）。
/// - `labels`：`AnnotatedScrollBarLabel` 工厂构造 + 投影 `IVector.append`；行高固定，
///   标签的 scrollOffset 才能按像素预计算。标签文本必须经 `labelTemplate` 的
///   DataTemplateSelector 提供（见选择器类注释）；标签空闲时淡出、指针悬停滚动条时点亮
///   是控件自身的交互设计。
/// - `detailLabelRequested`：读 `args.scrollOffset`、写 `args.content`（悬浮 tooltip）。
/// - `scrolling`：读 `args.scrollingEventKind` / `args.scrollOffset`，写 `args.cancel`
///   （开关打开后由滚动条发起的滚动被取消，验证 setter 回写生效）。
/// - `smallChange`：箭头按钮的步进。
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
        scrollView.verticalScrollBarVisibility = .hidden
        scrollView.content = listPanel

        let scrollBar = AnnotatedScrollBar()
        scrollBar.smallChange = Self.groupStride
        // 默认标签模板的属性绑定在 swift-winui 下取不到文本（见选择器类注释），
        // 换用按 content 选模板、文本已烘焙进 XAML 的 DataTemplateSelector。
        scrollBar.labelTemplate = AnnotatedScrollBarLabelTemplateSelector(labels: Self.scrollViewLabelSpecs)
        scrollBar.detailLabelTemplate = makeDetailLabelTemplate()
        Self.repopulateLabels(of: scrollBar, with: Self.makeScrollViewLabels())

        scrollBar.detailLabelRequested.addHandler { _, args in
            guard let args else { return }
            let group = min(
                Self.groupLetters.count - 1,
                max(0, Int(args.scrollOffset / Self.groupStride)))
            let first = group * Self.rowsPerGroup
            args.content = String(
                format: tr("Group %@ · rows %d–%d"),
                Self.groupLetters[group], Int32(first),
                Int32(first + Self.rowsPerGroup - 1))
        }

        scrollBar.scrolling.addHandler { _, args in
            guard let args else { return }
            eventCount += 1
            let canceled = cancelToggle.isOn
            if canceled { args.cancel = true }
            statusText.text = String(
                format: tr("Scrolling #%d: %@ · offset %d%@"),
                Int32(eventCount), Self.eventKindName(args.scrollingEventKind),
                Int32(args.scrollOffset), canceled ? tr(" (canceled)") : "")
        }

        // ScrollPresenter 实例要等模板应用后才可用（loaded 前为 nil），且 loaded 可能
        // 因重新挂树再次触发（如进/出全屏），用标记只接一次。接线后 ScrollPresenter 会
        // 推送 min/max/viewport，控件自身按最终 factor 重排标签（约 500ms 防抖），
        // 这里再重填一次标签集合兜底。注意：不能挂在 viewChanged 上——滚轮滚动每帧
        // 都触发它，重填会销毁重建全部标签、渐入动画反复重启，肉眼即闪烁。
        var wiredToScrollView = false
        scrollView.loaded.addHandler { _, _ in
            guard !wiredToScrollView, let presenter = scrollView.scrollPresenter else { return }
            wiredToScrollView = true
            presenter.verticalScrollController = scrollBar.scrollController
            Self.repopulateLabels(of: scrollBar, with: Self.makeScrollViewLabels())
        }
        // 视口尺寸变化（首次布局、窗口缩放）会改变 extent；重填标签集合强制控件按
        // 当前 extent 重排（官方 Gallery 即随内容尺寸变化重填 Labels）。
        scrollView.sizeChanged.addHandler { _, _ in
            Self.repopulateLabels(of: scrollBar, with: Self.makeScrollViewLabels())
        }

        let demo1 = Self.makeSideBySide(content: scrollView, scrollBar: scrollBar)
        // 固定高度：页面在 ScrollViewer 内布局（见下），不能依赖 star 行分配空间。
        demo1.height = 320

        // —— 演示二：框架 ItemsView 直连 ——
        let list = RsUI.ItemsView { id in
            Self.makeRow(String(format: tr("Item %02d"), Int32(id) ?? 0))
        }
        list.setIds((0..<Self.itemsViewCount).map(String.init))

        let scrollBar2 = AnnotatedScrollBar()
        scrollBar2.smallChange = Self.rowHeight * 3
        scrollBar2.labelTemplate = AnnotatedScrollBarLabelTemplateSelector(labels: Self.itemsViewLabelSpecs)
        scrollBar2.detailLabelTemplate = scrollBar.detailLabelTemplate
        Self.repopulateLabels(of: scrollBar2, with: Self.makeItemsViewLabels())
        scrollBar2.detailLabelRequested.addHandler { _, args in
            guard let args else { return }
            args.content = String(
                format: tr("≈ item %d of %d"),
                Int32(args.scrollOffset / Self.rowHeight), Int32(Self.itemsViewCount))
        }
        list.verticalScrollController = scrollBar2.scrollController

        // ItemsView 自带的内置滚动条与注记滚动条会并存，模板应用后隐藏内置那条。
        // loaded 时内部 ScrollView 可能尚未就绪（guard 吞掉后 loaded 不会再来），
        // 故 sizeChanged 里也重试，成功一次即止。
        var hidBuiltInScrollbar = false
        func hideBuiltInScrollbarIfNeeded() {
            guard !hidBuiltInScrollbar, let inner = list.scrollView else { return }
            inner.verticalScrollBarVisibility = .hidden
            hidBuiltInScrollbar = true
        }
        list.loaded.addHandler { _, _ in
            hideBuiltInScrollbarIfNeeded()
            Self.repopulateLabels(of: scrollBar2, with: Self.makeItemsViewLabels())
        }
        list.sizeChanged.addHandler { _, _ in
            hideBuiltInScrollbarIfNeeded()
            Self.repopulateLabels(of: scrollBar2, with: Self.makeItemsViewLabels())
        }

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
            code: "scrollView.scrollPresenter.verticalScrollController = annotatedScrollBar.scrollController",
            caption: tr("Arrow buttons step one whole group per click (SmallChange)."))
        let section2 = Self.makeSection(
            title: tr("Wired to ItemsView"),
            code: "itemsView.verticalScrollController = annotatedScrollBar.scrollController",
            caption: tr("The framework ItemsView exposes VerticalScrollController directly; labels mark quarters of the collection."),
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

    // MARK: - Labels

    /// （重）填充标签集合：集合每次变动都会触发控件重建标签容器并按当前 extent 重排。
    /// 初次布局时 ScrollPresenter 的 extent 尚未推送给控制器，标签会全堆在 rail 顶部
    /// 被碰撞规则折叠——除构造期外，在 loaded / sizeChanged 时机重填（官方 Gallery 的
    /// 做法同样是随尺寸变化重填 Labels）。
    private static func repopulateLabels(
        of scrollBar: AnnotatedScrollBar, with labels: [AnnotatedScrollBarLabel]
    ) {
        scrollBar.labels.clear()
        for label in labels {
            scrollBar.labels.append(label)
        }
    }

    private static func makeScrollViewLabels() -> [AnnotatedScrollBarLabel] {
        scrollViewLabelSpecs.map { AnnotatedScrollBarLabel($0.content, $0.offset) }
    }

    private static func makeItemsViewLabels() -> [AnnotatedScrollBarLabel] {
        itemsViewLabelSpecs.map { AnnotatedScrollBarLabel($0.content, $0.offset) }
    }

    private static var scrollViewLabelSpecs: [(content: String, offset: Double)] {
        groupLetters.enumerated().map { ($0.element, Double($0.offset) * groupStride) }
    }

    private static var itemsViewLabelSpecs: [(content: String, offset: Double)] {
        (0..<4).map { ("Q\($0 + 1)", Double($0 * itemsViewCount / 4) * rowHeight) }
    }

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
    private static func makeSideBySide(content: FrameworkElement, scrollBar: AnnotatedScrollBar) -> Grid {
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
