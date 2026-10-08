import Foundation
import UWP
import WinAppSDK
import WinUI
import WindowsFoundation

// MARK: - Label spec

/// 一条注记标签的规格：显示文本 + 对应的内容 scrollOffset。
///
/// offset 用作模板选择的键（值类型直读可靠）；`AnnotatedScrollBarLabel.content`
/// 读回是装箱的 `IInspectable`，`as? String` 桥不回，不要依赖读回。
public struct AnnotatedScrollBarLabelSpec {
    public let text: String
    public let scrollOffset: Double

    public init(text: String, scrollOffset: Double) {
        self.text = text
        self.scrollOffset = scrollOffset
    }
}

// MARK: - Options

/// 标签文本在标签区（控件默认宽度 44，`LabelsGridMinWidth`）内的水平对齐。
public enum AnnotatedScrollBarLabelAlignment {
    /// 贴标签区左缘，与 rail 之间留出整段空白（离得远的一侧）。
    case leading
    /// 右对齐、紧贴 rail（微软照片应用风格，默认）。
    case trailing
}

/// 悬停详情标签（tooltip）的呈现方式。
public enum AnnotatedScrollBarDetailLabelMode {
    /// 原生 XAML ToolTip 弹出层。指针移动时内容更新会触发 ToolTip 重新锚定，
    /// 有轻微抖动（WinUI 原生行为，无法从外部消除）。
    case native
    /// 自绘覆盖层（默认）：压掉原生 ToolTip，用 TranslateTransform 直接跟随指针，
    /// 位置完全由本类控制，构造上无抖动（照片应用即自绘方案）。
    case overlay
}

// MARK: - Label template selector

/// 按标签的 scrollOffset 选择「文本已烘焙进 XAML」的 DataTemplate。
///
/// 控件默认 LabelTemplate 的 `Text={Binding Content}` 是带路径的经典绑定，
/// 运行时要经应用的 IXamlMetadataProvider 反射 WinRT 类属性——swift-winui 应用
/// 没有元数据提供器，绑定解析为空，标签实现化后零尺寸不可见（实测）。把文本直接
/// 写进模板、用 Swift 侧的 offset 匹配来选模板，可完全绕开属性绑定。
final class AnnotatedScrollBarLabelTemplateSelector: WinUI.DataTemplateSelector {
    private let templatesByOffset: [Double: WinUI.DataTemplate]

    init(templatesByOffset: [Double: WinUI.DataTemplate]) {
        self.templatesByOffset = templatesByOffset
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
        guard let label = item as? WinUI.AnnotatedScrollBarLabel else { return nil }
        return templatesByOffset[label.scrollOffset]
    }
}

// MARK: - Thumb 全幅桥接

/// 原生 AnnotatedScrollBar 的 thumb 位置公式把 ViewportSize 计入映射因子:
/// thumb 全程只能行进到 (extent−viewport)/extent 比例,贴底时悬停在
/// 1−viewport/extent 处(FolderViewer 841/2848 ≈ 悬在 70%,滚到底指示器
/// 到不了轨道底端;标签同样被压缩进该子区间)。本桥接实现 IScrollController
/// 包住原生控制器的对外面,拦截 ScrollPresenter → setValues,把 viewportLength
/// 改写为 0:thumb 与标签都按 [0, maxOffset] 全幅展开(与本封装文档约定的
/// labels scrollOffset 取 [0, maxOffset] 一致)。事件对象直接透传原生实例,
/// 输入路径(拖拽/点击轨道)由原生按同一因子反算,无需二次校正。
private final class FullSpanScrollControllerBridge: WinUI.IScrollController {
    private let inner: WinUI.AnyIScrollController

    init(inner: WinUI.AnyIScrollController) {
        self.inner = inner
    }

    func setIsScrollable(_ isScrollable: Bool) throws {
        try inner.setIsScrollable(isScrollable)
    }

    func setValues(
        _ minOffset: Double, _ maxOffset: Double, _ offset: Double, _ viewportLength: Double
    ) throws {
        try inner.setValues(minOffset, maxOffset, offset, 0)
    }

    func getScrollAnimation(
        _ correlationId: Int32,
        _ startPosition: WindowsFoundation.Vector2,
        _ endPosition: WindowsFoundation.Vector2,
        _ defaultAnimation: WinAppSDK.CompositionAnimation!
    ) throws -> WinAppSDK.CompositionAnimation! {
        try inner.getScrollAnimation(correlationId, startPosition, endPosition, defaultAnimation)
    }

    func notifyRequestedScrollCompleted(_ correlationId: Int32) throws {
        try inner.notifyRequestedScrollCompleted(correlationId)
    }

    var canScroll: Bool { inner.canScroll }
    var isScrollingWithMouse: Bool { inner.isScrollingWithMouse }
    var panningInfo: WinUI.AnyIScrollControllerPanningInfo! { inner.panningInfo }

    var addScrollVelocityRequested: WindowsFoundation.Event<
        WindowsFoundation.TypedEventHandler<WinUI.IScrollController?, WinUI.ScrollControllerAddScrollVelocityRequestedEventArgs?>
    > { inner.addScrollVelocityRequested }

    var canScrollChanged: WindowsFoundation.Event<
        WindowsFoundation.TypedEventHandler<WinUI.IScrollController?, Any?>
    > { inner.canScrollChanged }

    var isScrollingWithMouseChanged: WindowsFoundation.Event<
        WindowsFoundation.TypedEventHandler<WinUI.IScrollController?, Any?>
    > { inner.isScrollingWithMouseChanged }

    var scrollByRequested: WindowsFoundation.Event<
        WindowsFoundation.TypedEventHandler<WinUI.IScrollController?, WinUI.ScrollControllerScrollByRequestedEventArgs?>
    > { inner.scrollByRequested }

    var scrollToRequested: WindowsFoundation.Event<
        WindowsFoundation.TypedEventHandler<WinUI.IScrollController?, WinUI.ScrollControllerScrollToRequestedEventArgs?>
    > { inner.scrollToRequested }
}

// MARK: - AnnotatedScrollBar

/// 原生注记滚动条的即用封装（注意：本类在 RsUI 模块内遮蔽 `WinUI.AnnotatedScrollBar`，
/// 引用投影原件需加 `WinUI.` 前缀——与 `RsUI.ItemsView` 同一决策）。
/// 封装 swift-winui 下使用原生控件所需的全部变通，客户端只提供标签与悬停文案，
/// 不必关心模板/接线/内置滚动条隐藏等 UI 细节。
///
/// 实现说明：组合而非继承——`WinUI.AnnotatedScrollBar` 的 Swift 子类化实测
/// 必崩（2026-10-05：空子类在启动重建 ~50%、真主题切换重建 ~1/3 崩溃率，
/// 0xC0000005 访问违例于 COM 聚合释放路径；对照纯 wrapper 全存活。复现要点：
/// 声明空子类 → 实例化进树 → 触发整页重建（如切换主题）释放它即可，无需任何
/// 定制。注意 `WinUI.ItemsView` 的子类化（`RsUI.ItemsView`）是可用的——投影
/// 控件的子类化支持并不齐整），外层改用 Grid 子类承载（`PageTransitionHost`
/// 已证明 Grid 子类化可靠），内部持有原生控件。
///
/// 封装的要点（均为实测结论，详见各类/方法注释）：
/// - 标签文本必须经 DataTemplateSelector 提供（默认模板的属性绑定取不到值）。
/// - 标签模板带 `MinWidth=44`（对齐控件的 `LabelsGridMinWidth`）：默认模板靠它把
///   标签网格撑满控件宽度、右缘贴 rail；缺了它，窄标签会让网格居中收缩、文本
///   悬在离 rail 十几像素处。相对位置由 `labelAlignment` / `labelSpacing` 调节。
/// - 标签前景色在构建时解析主题画刷、以具体色值注入模板（松散 XAML 的
///   `{ThemeResource}` / `{StaticResource}` 均静默解析失败）。主题切换由页面
///   重建（updateAppearance）自然刷新色值。
/// - 标签集合的重填时机：构造/接线后一次 + `sizeChanged`；**绝不挂 viewChanged**
///   ——滚轮滚动每帧触发它，重填会销毁重建全部标签、渐入动画反复重启，肉眼即闪烁。
/// - ItemsView 的内置滚动条需要 loaded + sizeChanged 双重试隐藏（loaded 时内部
///   ScrollView 可能还是 nil，一次性 guard 会永久漏掉）。
/// - 悬停详情默认走自绘 overlay（照片应用风格，平滑无抖动）；`.native` 保留
///   原生 ToolTip 行为（内容更新会重新锚定，有轻微抖动）。
/// - 标签空闲淡出、指针交互时点亮是 Windows 11 自动隐藏滚动条的系统行为，非缺陷。
///
/// 生命周期：外层 Grid 挂进视觉树即被树持有（投影控件 Swift 子类语义），事件闭包
/// 按惯例 `[weak self]`；labels / detailText / onScrolling 闭包请勿捕获比页面
/// 更长命的状态。
open class AnnotatedScrollBar: WinUI.Grid {
    /// 滚动条发起滚动时透出（可读 `scrollingEventKind` / `scrollOffset`，
    /// 写 `cancel` 拦截——配合本回调可复刻「取消滚动」类交互）。
    public var onScrolling: ((WinUI.AnnotatedScrollBarScrollingEventArgs) -> Void)?

    /// 被封装的原生控件（组合）。
    private let nativeBar: WinUI.AnnotatedScrollBar

    private let labelsProvider: () -> [AnnotatedScrollBarLabelSpec]
    private let detailText: ((Double) -> String)?
    private let labelAlignment: AnnotatedScrollBarLabelAlignment
    private let labelSpacing: Double
    private let detailLabelMode: AnnotatedScrollBarDetailLabelMode
    /// 按文本缓存已加载的模板，避免 resize 重排时重复 XamlReader 加载。
    private var labelTemplatesByText: [String: WinUI.DataTemplate] = [:]

    /// overlay 模式状态（懒创建）。
    private var detailOverlay: WinUI.Border?
    private var detailOverlayText: WinUI.TextBlock?
    private var detailOverlayTransform: WinUI.TranslateTransform?
    private var detailOverlayFade: WinUI.Storyboard?
    private var overlayAdopted = false
    private var nativeTooltipSuppressed = false
    /// attach 时记录的宿主（强引用：ScrollView 是纯投影 wrapper 不能 weak；
    /// 生命周期与页面视图一致）。ItemsView 是 RsUI 类，可 weak 且必须 weak——
    /// 宿主 itemsView 经 verticalScrollController 反向持有本控件内部滚动条，
    /// 强引用即成环，列表换代会泄漏整棵已实现视图（含位图）。
    private var attachedScrollView: WinUI.ScrollView?
    private weak var attachedList: RsUI.ItemsView?

    /// - Parameters:
    ///   - smallChange: 上下箭头按钮的单次滚动步进（内容坐标）。
    ///   - labels: 标签规格闭包。重排时（窗口缩放等）会重新求值——offset 依赖
    ///     extent，闭包应按当前布局实时计算，勿缓存过期值。
    ///   - detailText: 悬停 offset → 详情文案。传 nil 则不显示任何悬停详情。
    ///     闭包应轻量——指针每帧移动都会调用。
    ///   - labelAlignment: 标签相对 rail 的水平对齐（默认 `.trailing` 紧贴 rail，
    ///     照片应用风格）。
    ///   - labelSpacing: trailing 时文本右缘与 rail 的间距（内容坐标像素，默认 0）。
    ///   - detailLabelMode: 悬停详情的呈现方式（默认 `.overlay` 自绘、平滑）。
    public init(
        smallChange: Double,
        labels: @escaping () -> [AnnotatedScrollBarLabelSpec],
        detailText: ((Double) -> String)? = nil,
        labelAlignment: AnnotatedScrollBarLabelAlignment = .trailing,
        labelSpacing: Double = 0,
        detailLabelMode: AnnotatedScrollBarDetailLabelMode = .overlay
    ) {
        self.labelsProvider = labels
        self.detailText = detailText
        self.labelAlignment = labelAlignment
        self.labelSpacing = labelSpacing
        self.detailLabelMode = detailLabelMode
        self.nativeBar = WinUI.AnnotatedScrollBar()
        super.init()
        nativeBar.smallChange = smallChange
        configure()
        children.append(nativeBar)
    }

    /// 接到框架 ItemsView（依赖属性直通内部 ScrollPresenter，随时可调）。
    /// 本控件可直接放进宿主布局的 auto 列（overlay 详情会自动收养进同一父容器
    /// 并跨满列）。经 FullSpanScrollControllerBridge 桥接(见该类型注释)。
    public func attach(to list: RsUI.ItemsView) {
        attachedList = list
        list.verticalScrollController = FullSpanScrollControllerBridge(inner: nativeBar.scrollController)

        var hidBuiltInScrollbar = false
        func hideBuiltInScrollbarIfNeeded(_ list: RsUI.ItemsView) {
            guard !hidBuiltInScrollbar, let inner = list.scrollView else { return }
            inner.verticalScrollBarVisibility = .hidden
            hidBuiltInScrollbar = true
        }
        // 处理器挂在 list 自身的事件上，强捕获 list 即成环，必须 weak
        list.loaded.addHandler { [weak self, weak list] _, _ in
            if let list { hideBuiltInScrollbarIfNeeded(list) }
            self?.repopulate()
            self?.adoptDetailOverlayIfNeeded()
        }
        list.sizeChanged.addHandler { [weak self, weak list] _, _ in
            if let list { hideBuiltInScrollbarIfNeeded(list) }
            self?.repopulate()
            self?.syncDetailOverlayMargin()
        }
        repopulate()
    }

    /// 接到 ScrollView。`scrollPresenter` 在模板应用前为 nil，接线在 `loaded`
    /// 之后进行（内部含一次性标记，重挂树如进/出全屏导致的重复 loaded 无害）。
    /// 本控件可直接放进宿主布局的 auto 列（overlay 详情会自动收养进同一父容器
    /// 并跨满列）。
    public func attach(to scrollView: WinUI.ScrollView) {
        attachedScrollView = scrollView
        scrollView.verticalScrollBarVisibility = .hidden
        var wired = false
        scrollView.loaded.addHandler { [weak self] _, _ in
            guard let self, !wired, let presenter = scrollView.scrollPresenter else { return }
            wired = true
            presenter.verticalScrollController = FullSpanScrollControllerBridge(
                inner: nativeBar.scrollController)
            self.repopulate()
            self.adoptDetailOverlayIfNeeded()
        }
        scrollView.sizeChanged.addHandler { [weak self] _, _ in
            self?.repopulate()
            self?.syncDetailOverlayMargin()
        }
        repopulate()
    }

    // MARK: - Configuration

    private func configure() {
        nativeBar.detailLabelTemplate = cachedNativeDetailTemplate
        // 标签 ContentPresenter 的命中区会溢出控件边界，文本命中使光标变成异常
        // 形状——强制箭头（防御性，实测在部分机器上不能完全压制，见已知问题）。
        nativeBar.protectedCursor = try? InputSystemCursor.create(.arrow)
        if detailLabelMode == .native, let detailText {
            nativeBar.detailLabelRequested.addHandler { _, args in
                guard let args else { return }
                args.content = detailText(args.scrollOffset)
            }
        }
        nativeBar.scrolling.addHandler { [weak self] _, args in
            guard let args else { return }
            self?.onScrolling?(args)
        }
        if detailLabelMode == .overlay && detailText != nil {
            bindDetailOverlayTracking()
        }
    }

    // MARK: - Label repopulation

    /// 重填标签集合并按当前 specs 重建模板选择器。集合与 labelTemplate 的变动
    /// 都会触发控件内部约 50ms 防抖的标签重排（同一防抖合并）。
    private func repopulate() {
        let specs = labelsProvider()
        var templatesByOffset: [Double: WinUI.DataTemplate] = [:]
        for spec in specs {
            templatesByOffset[spec.scrollOffset] = labelTemplate(for: spec.text)
        }
        nativeBar.labelTemplate = AnnotatedScrollBarLabelTemplateSelector(templatesByOffset: templatesByOffset)
        nativeBar.labels.clear()
        for spec in specs {
            nativeBar.labels.append(WinUI.AnnotatedScrollBarLabel(spec.text, spec.scrollOffset))
        }
    }

    private func labelTemplate(for text: String) -> WinUI.DataTemplate {
        if let cached = labelTemplatesByText[text] {
            return cached
        }
        let template = loadLabelTemplate(text: text, foregroundHex: foregroundHex)
        labelTemplatesByText[text] = template
        return template
    }

    /// 前景色解析一次并快照（主题切换由页面重建整个控件自然刷新）。
    private lazy var foregroundHex: String = {
        guard let solid = Brush.fluentTheme("TextFillColorSecondaryBrush") as? SolidColorBrush else {
            return "#C8C8C8"
        }
        let color = solid.color
        return String(format: "#%02X%02X%02X%02X", color.a, color.r, color.g, color.b)
    }()

    private func loadLabelTemplate(text: String, foregroundHex: String) -> WinUI.DataTemplate {
        let escaped = Self.escapeXml(text)
        // MinWidth=44 对齐控件 LabelsGridMinWidth：把标签网格撑满控件宽度、
        // 右缘贴 rail；缺了它窄标签会让网格居中收缩、文本悬在离 rail 十几像素处。
        // 间距另加在文本 Margin 上，MinWidth 同步加宽保证 trailing 间距不裁切。
        let zoneMinWidth = max(44.0, labelSpacing + 1)
        let alignment: String
        switch labelAlignment {
        case .leading: alignment = "Left"
        case .trailing: alignment = "Right"
        }
        let dictionary: WinUI.ResourceDictionary = App.context.requireXaml(withString: """
            <ResourceDictionary
                xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
                <DataTemplate x:Key="LabelTemplate">
                    <Border IsHitTestVisible="False" MinWidth="\(zoneMinWidth)">
                        <TextBlock
                            Margin="0,-5,\(labelSpacing),-2"
                            HorizontalAlignment="\(alignment)"
                            HorizontalTextAlignment="\(alignment)"
                            FontSize="12"
                            FontWeight="SemiBold"
                            Foreground="\(foregroundHex)"
                            Text="\(escaped)"
                            TextWrapping="NoWrap" />
                    </Border>
                </DataTemplate>
            </ResourceDictionary>
            """)
        guard let template = dictionary.lookup("LabelTemplate") as? WinUI.DataTemplate else {
            fatalError("AnnotatedScrollBar: label template not found in loaded ResourceDictionary")
        }
        return template
    }

    /// 详情标签模板（native 模式用）：与控件默认同构（无路径 `Text="{Binding}"`，
    /// 内容是 detailLabelRequested 事件写入的字符串，不受属性绑定缺陷影响），
    /// 仅在根节点关闭命中测试——tooltip 弹出并盖住指针时其文本命中区
    /// 会把光标变成异常形状。
    private lazy var cachedNativeDetailTemplate: WinUI.DataTemplate = {
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
            fatalError("AnnotatedScrollBar: detail label template not found in loaded ResourceDictionary")
        }
        return template
    }()

    private static func escapeXml(_ text: String) -> String {
        var escaped = ""
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&apos;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    // MARK: - Detail overlay (Photos-style)

    /// overlay 模式的悬停跟踪：entered 淡入、moved 更新位置与文案、exited 淡出。
    /// 位置只经 TranslateTransform 更新，不受 ToolTip 重新锚定影响——无抖动。
    private func bindDetailOverlayTracking() {
        nativeBar.pointerEntered.addHandler { [weak self] _, _ in
            self?.suppressNativeTooltipIfNeeded()
            self?.fadeDetailOverlay(to: 1)
        }
        nativeBar.pointerMoved.addHandler { [weak self] _, args in
            guard let self, let args, let point = try? args.getCurrentPoint(self.nativeBar) else { return }
            self.updateDetailOverlay(pointerY: Double(point.position.y))
        }
        nativeBar.pointerExited.addHandler { [weak self] _, _ in
            self?.fadeDetailOverlay(to: 0)
        }
    }

    /// 原生 ToolTip 挂在模板内的 PART_ToolTipRail 上；首个 pointerEntered 时
    /// 模板必然已应用，此时摘除即可（无固定延时等待模板的竞争窗口）。
    private func suppressNativeTooltipIfNeeded() {
        guard !nativeTooltipSuppressed else { return }
        nativeTooltipSuppressed = true
        if let rail = Self.findNamedElement(nativeBar, name: "PART_ToolTipRail") {
            try? ToolTipService.setToolTip(rail, nil)
        }
    }

    private static func findNamedElement(
        _ root: WinUI.DependencyObject, name: String
    ) -> WinUI.FrameworkElement? {
        if let element = root as? WinUI.FrameworkElement, element.name == name {
            return element
        }
        let count = (try? VisualTreeHelper.getChildrenCount(root)) ?? 0
        for index in 0..<count {
            if let child = try? VisualTreeHelper.getChild(root, Int32(index)),
                let found = findNamedElement(child, name: name)
            {
                return found
            }
        }
        return nil
    }

    /// 把 overlay 收养进本控件的父容器：追加为最后一个子元素（置于顶层），
    /// Grid 场景跨满所有列；overlay 右对齐 + 右 margin = 滚动条宽 + 间距，
    /// 使其悬在滚动条列左侧的内容区右缘（Grid 默认不裁剪，越界渲染合法）。
    /// 要求本控件位于父容器最右列（并排布局的标准形态）。
    private func adoptDetailOverlayIfNeeded() {
        guard !overlayAdopted else { return }
        guard let parent = self.parent as? WinUI.UIElement else { return }
        let overlay = makeDetailOverlayIfNeeded()
        if let grid = parent as? WinUI.Grid {
            let columnCount = Int32(max(1, grid.columnDefinitions.count))
            try? WinUI.Grid.setColumn(overlay, 0)
            try? WinUI.Grid.setColumnSpan(overlay, columnCount)
        }
        if Self.appendChild(overlay, to: parent) {
            overlayAdopted = true
            syncDetailOverlayMargin()
        }
    }

    /// 当前 overlay 视图（懒创建）。父容器不受支持（非 Grid/StackPanel）时，
    /// 调用方可用它自行挂载并跨列。
    public var detailOverlayView: WinUI.UIElement? {
        makeDetailOverlayIfNeeded()
    }

    private static func appendChild(_ child: WinUI.UIElement, to parent: WinUI.UIElement) -> Bool {
        if let grid = parent as? WinUI.Grid {
            grid.children.append(child)
            return true
        }
        if let panel = parent as? WinUI.StackPanel {
            panel.children.append(child)
            return true
        }
        return false
    }

    private func makeDetailOverlayIfNeeded() -> WinUI.Border {
        if let detailOverlay {
            return detailOverlay
        }
        let text = WinUI.TextBlock()
        text.text = ""
        text.fontSize = 12
        text.foreground = WinUI.SolidColorBrush(UWP.Color(a: 0xFF, r: 0xFF, g: 0xFF, b: 0xFF))

        let border = WinUI.Border()
        border.cornerRadius = WinUI.CornerRadius(
            topLeft: 5, topRight: 5, bottomRight: 5, bottomLeft: 5)
        // 照片应用风格：不随应用主题翻转的深色悬浮面（浅色主题下同样深色）。
        border.background = WinUI.SolidColorBrush(
            UWP.Color(a: 0xE6, r: 0x2C, g: 0x2C, b: 0x2C))
        border.padding = Thickness(left: 9, top: 4, right: 9, bottom: 5)
        border.isHitTestVisible = false
        border.verticalAlignment = .top
        border.horizontalAlignment = .right
        border.opacity = 0
        border.child = text

        let transform = WinUI.TranslateTransform()
        border.renderTransform = transform

        detailOverlay = border
        detailOverlayText = text
        detailOverlayTransform = transform
        return border
    }

    private func syncDetailOverlayMargin() {
        guard overlayAdopted, let detailOverlay, nativeBar.actualWidth > 0 else { return }
        let gap = 8.0
        detailOverlay.margin = Thickness(left: 0, top: 0, right: nativeBar.actualWidth + gap, bottom: 0)
    }

    /// 按指针在滚动条上的纵向位置更新 overlay：文案由 detailText(offset) 提供，
    /// offset = 纵向比例 × 当前可滚动高度（纯比例近似，标签粒度下与原生
    /// factor 映射的差异不可感知）。纵向以指针为中心并夹取到滚动条范围。
    private func updateDetailOverlay(pointerY: Double) {
        guard let text = detailOverlayText, let transform = detailOverlayTransform else { return }
        let height = attachedScrollView?.actualHeight ?? attachedList?.actualHeight ?? 0
        guard height > 0 else { return }

        let ratio = min(1, max(0, pointerY / height))
        if let detailText {
            text.text = detailText(ratio * hostScrollableHeight())
        }

        let overlayHeight = detailOverlay?.actualHeight ?? 0
        transform.y = min(max(0, pointerY - overlayHeight / 2), max(0, height - overlayHeight))
    }

    private func hostScrollableHeight() -> Double {
        if let scrollView = attachedScrollView {
            return scrollView.scrollableHeight
        }
        if let list = attachedList {
            return list.scrollView?.scrollableHeight ?? 0
        }
        return 0
    }

    /// 简单不透明度过渡（dependent animation：150ms 跟手即可，无逐帧精度要求）。
    private func fadeDetailOverlay(to target: Double) {
        guard let overlay = detailOverlay, overlay.opacity != target else { return }
        try? detailOverlayFade?.stop()

        let animation = WinUI.DoubleAnimation()
        animation.enableDependentAnimation = true
        animation.from = overlay.opacity
        animation.to = target
        animation.duration = WinUI.Duration(
            timeSpan: WindowsFoundation.TimeSpan(duration: 150 * 10_000), type: .timeSpan)
        try? WinUI.Storyboard.setTarget(animation, overlay)
        try? WinUI.Storyboard.setTargetProperty(animation, "Opacity")

        let storyboard = WinUI.Storyboard()
        storyboard.children.append(animation)
        try? storyboard.begin()
        detailOverlayFade = storyboard
    }
}
