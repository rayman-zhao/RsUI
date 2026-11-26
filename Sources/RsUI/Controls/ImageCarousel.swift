import CppWinRT
import Foundation
import RsFoundation
import WinAppSDK
import WinUI
import WindowsFoundation

// MARK: - Slide cell

/// 轮播的一格。用 Swift 子类而不是 DataTemplate：repeater 回收后复用的是同一个原生
/// 元素，图片的 opened/failed 订阅只能挂一次；DataTemplate 的根每取一次都是新的投影
/// wrapper，无从判断"这个元素已经挂过"。
final class SlideCell: Grid, @unchecked Sendable {
    let image: Image
    private let busyRing: ProgressRing
    private let errorIcon: FontIcon

    private enum LoadState { case pending, ready, failed }

    private var loadState = LoadState.pending {
        didSet {
            busyRing.isActive = loadState == .pending
            errorIcon.visibility = loadState == .failed ? .visible : .collapsed
        }
    }

    /// 点按时回调，参数是所在页。
    var onTap: ((Int) -> Void)?
    private var pageIndex = 0

    nonisolated override init() {
        let parts: (Border, Image, ProgressRing, FontIcon) = MainActor.assumeIsolated {
            let visual: Border = App.context.requireXamlView(withString: slideXaml)
            return (
                visual,
                visual.requireElement("SlideImage"),
                visual.requireElement("SlideBusy"),
                visual.requireElement("SlideError")
            )
        }
        image = parts.1
        busyRing = parts.2
        errorIcon = parts.3
        super.init()
        MainActor.assumeIsolated {
            children.append(parts.0)
            // [weak self]：self 持有 image，image 的事件表持有闭包，强捕获即成环。
            image.imageOpened.addHandler { [weak self] _, _ in
                guard let self, self.loadState == .pending else { return }
                self.loadState = .ready
            }
            image.imageFailed.addHandler { [weak self] _, _ in
                guard let self, self.loadState == .pending else { return }
                self.loadState = .failed
            }
            tapped.addHandler { [weak self] _, _ in
                guard let self else { return }
                self.onTap?(self.pageIndex)
            }
        }
    }

    /// - Parameter isDecoded: 该源此前已解码完成，不必等 imageOpened。
    func show(_ source: BitmapImage, pageIndex: Int, isDecoded: Bool) {
        self.pageIndex = pageIndex
        image.source = source
        loadState = isDecoded ? .ready : .pending
    }
}

/// `itemTemplate` 的代码工厂：`SlideCell` 是 Swift 子类，DataTemplate 造不出来。
/// 回收契约同 `RecyclableItemContainerFactory`（见其注释）——清除的元素必须入池复用，
/// 否则滞留在 repeater 的子集合里单调累积。
@MainActor
private final class SlideCellFactory: IElementFactory {
    private var pool: [SlideCell] = []

    func getElement(_ args: ElementFactoryGetArgs!) throws -> UIElement! {
        pool.popLast() ?? SlideCell()
    }

    func recycleElement(_ args: ElementFactoryRecycleArgs!) throws {
        if let cell = args.element as? SlideCell {
            pool.append(cell)
        }
    }
}

// MARK: - ImageCarousel

/// 图片轮播：ScrollView 里的 ItemsRepeater，旁边一个 PipsPager，竖向。
///
/// 滚动、惯性、吸附都是 ScrollView 的原生行为——鼠标滚轮、触摸平移由它处理，每页一个
/// 原生吸附点，滚动停下时落在页上。本控件只做三件事：把图片按 URL 装进 repeater；
/// 让居中的一张保持原尺寸、其余随离视口中心的距离缩小（Composition 表达式，效果对齐
/// WinUI Gallery 里 `ItemsRepeater` 的 Animated Scrolling 示例）；让 PipsPager 跟随
/// 当前页。
///
/// ```swift
/// let carousel = ImageCarousel(imageURLs: urls)
/// carousel.height = 320
/// carousel.selectedIndexChanged.addHandler { carousel, index in /* … */ }
/// ```
///
/// 图片经 `BitmapImage` 加载（http(s) 与 file URI 均可）：加载中显示进度环，失败显示
/// 错误图标；同一 URL 在控件内复用同一个 `BitmapImage`。点按某张图把它滚到中间。
///
/// 宿主须同时约束两个方向的尺寸（Grid 星型格或显式宽高）——放进不限高的 StackPanel
/// 会得到零尺寸视口。
open class ImageCarousel: Grid, @unchecked Sendable {
    /// 当前页变化时触发，参数为新页索引。程序化选择在发起滚动时即触发；用户滚动
    /// 过程中随"哪一页最接近视口中心"变化。
    public let selectedIndexChanged = EventWithArgumentHandler<ImageCarousel, Int>()

    /// 页码指示器。页数、当前页由本控件维护，`maxVisiblePips` 等外观可自行调整。
    public let pipsPager: PipsPager

    /// 当前页索引。赋值把该页滚到中间；图片列表为空时恒为 0。
    public var selectedIndex: Int {
        get { _selectedIndex }
        set { select(newValue) }
    }

    /// 图片 URL，按显示顺序。
    public private(set) var imageURLs: [URL] = []

    /// 相邻两张图片的间距，默认 8。
    public var spacing: Double = 8 {
        didSet {
            guard spacing != oldValue else { return }
            stackLayout.spacing = spacing
            refreshMetrics()
        }
    }

    /// 单张图片的高度，默认 240；宽度拉伸占满视口。
    public var slideHeight: Double = 240 {
        didSet {
            guard slideHeight != oldValue else { return }
            refreshMetrics()
        }
    }

    /// 紧邻居中页的那两张在静止时的缩放，默认 0.85；更远的按距离线性递减到
    /// `minimumScale`。置 1 即关闭缩放效果。
    public var neighborScale: Double = 0.85 {
        didSet {
            guard neighborScale != oldValue else { return }
            restartScaleAnimations()
        }
    }

    /// 远处图片缩放的下限，默认 0.6。
    public var minimumScale: Double = 0.6 {
        didSet {
            guard minimumScale != oldValue else { return }
            restartScaleAnimations()
        }
    }

    private let scrollView: ScrollView
    private let slideHost: Border
    private let repeater: ItemsRepeater
    private let stackLayout: StackLayout
    private let cellFactory = SlideCellFactory()
    /// itemsSource 的载体：只写不读的计数与变更通知（同 `ItemsIndexView`）。
    private let items: WinUI.IVectorAny
    private var imageSources: [URL: BitmapImage] = [:]

    private var _selectedIndex = 0
    /// 程序化滚动进行中：中途经过的页不当作"当前页"上报。
    private var isScrollingToSelection = false
    /// 回写 PipsPager 期间忽略其 selectedIndexChanged，避免自我触发。
    private var isSyncingPager = false
    /// 吸附点集合已按此键写入；未变则不重写。
    private var snapPointsKey = ""

    /// - Parameter imageURLs: 初始图片 URL。
    public init(imageURLs: [URL] = []) {
        guard let vector = single_threaded_observable_vector([]) else {
            fatalError("ImageCarousel: failed to create the observable items vector")
        }
        items = vector
        let root: Grid = App.context.requireXaml(withString: xamlUI)
        scrollView = root.requireElement("Scroller")
        slideHost = root.requireElement("SlideHost")
        repeater = root.requireElement("Repeater")
        stackLayout = root.requireElement("SlidesLayout")
        pipsPager = root.requireElement("Pager")
        super.init()

        // XAML 根只是载体，子元素整体搬进 self。挂树前 parent 查找不可靠，用集合级清空。
        root.children.clear()
        children.append(scrollView)
        children.append(pipsPager)

        let viewport = ColumnDefinition()
        viewport.width = GridLength(value: 1, gridUnitType: .star)
        let indicator = ColumnDefinition()
        indicator.width = GridLength(value: 0, gridUnitType: .auto)
        columnDefinitions.append(viewport)
        columnDefinitions.append(indicator)

        // 关掉元素锚定（默认 0.0，开启）：端部留白随视口变化时，它为了让边缘的格子不动，
        // 会在 arrange 中把内容挪一个"布局偏移"并等额扣减 verticalOffset——窗口缩放后
        // 偏移读数就与视觉位置分叉（实测差了一整页）。要保持居中的是选中页，由
        // handleExtentChanged 负责。
        scrollView.horizontalAnchorRatio = .nan
        scrollView.verticalAnchorRatio = .nan

        repeater.itemTemplate = cellFactory
        repeater.itemsSource = items

        bindEvents()
        setImageURLs(imageURLs)
    }

    /// 整体替换图片，当前页回到第 0 张。
    public func setImageURLs(_ urls: [URL]) {
        imageURLs = urls
        imageSources = imageSources.filter { urls.contains($0.key) }
        try? items.Clear()
        for index in urls.indices {
            try? items.Append(index)
        }
        isScrollingToSelection = false
        // 没有页时先收起指示器再清页数：PipsPager 的圆点区在焦点进入时会按
        // SelectedPageIndex 向（已空的）repeater 要元素，抛 E_INVALIDARG（实测点过圆点后
        // 清空即崩）；折叠的子树不参与焦点解析。
        pipsPager.visibility = urls.isEmpty ? .collapsed : .visible
        isSyncingPager = true
        pipsPager.numberOfPages = Int32(urls.count)
        commitSelection(0)
        syncPager()
        isSyncingPager = false
        handleExtentChanged()
    }

    // MARK: - 布局

    private var stride: Double { max(0, slideHeight) + max(0, spacing) }

    /// 首尾两页也能停在视口中间的内容端部留白。
    private var edgePadding: Double {
        max(0, (scrollView.viewportHeight - max(0, slideHeight)) / 2)
    }

    private var currentOffset: Double { scrollView.verticalOffset }

    // 端部留白本身在内容坐标里（第 index 页的前缘 = 留白 + index × 步长），
    // 把它挪到视口中间只需偏移 index × 步长。
    private func offset(forPage index: Int) -> Double {
        Double(index) * stride
    }

    /// 视口或度量变化后重排：端部留白与已实现格子的尺寸。
    private func refreshMetrics() {
        slideHost.padding = Thickness(left: 0, top: edgePadding, right: 0, bottom: edgePadding)
        for index in 0..<imageURLs.count {
            if let cell = try? repeater.tryGetElement(Int32(index)) as? SlideCell {
                applyMetrics(to: cell)
            }
        }
    }

    private func applyMetrics(to cell: SlideCell) {
        cell.height = slideHeight
        startScaleAnimation(for: cell)
    }

    /// extent 变化只源于本控件的度量/页数变化。视口变化后 ScrollPresenter 的 viewport
    /// 先于控件的 sizeChanged 给出终值，度量在这里重算。页偏移 = 页号 × 步长，本就不随
    /// 视口变，这里只兜底确认选中页仍然居中。
    private func handleExtentChanged() {
        refreshMetrics()
        refreshSnapPoints()
        let target = offset(forPage: selectedIndex)
        if abs(currentOffset - target) > 0.5 {
            scrollTo(offset: target, animated: false)
        }
    }

    private func refreshSnapPoints() {
        guard
            let presenter = scrollView.scrollPresenter,
            let snapPoints = presenter.verticalSnapPoints
        else { return }
        let key = "\(edgePadding)|\(stride)|\(imageURLs.count)"
        guard key != snapPointsKey else { return }
        snapPointsKey = key
        snapPoints.clear()
        // 单页没有可滚距离，不设吸附点。
        guard imageURLs.count > 1 else { return }
        for index in imageURLs.indices {
            snapPoints.append(ScrollSnapPoint(offset(forPage: index), .near))
        }
    }

    // MARK: - 缩放

    private func restartScaleAnimations() {
        for index in 0..<imageURLs.count {
            if let cell = try? repeater.tryGetElement(Int32(index)) as? SlideCell {
                startScaleAnimation(for: cell)
            }
        }
    }

    /// 每格挂一条表达式：缩放 = 1 − 距视口中心的距离 × 斜率，下限 minimumScale；
    /// 以格子自身中心为缩放原点。item.Offset 是格子 visual 相对 repeater 的偏移，不含
    /// SlideHost 的端部留白，视口中心按同一坐标系给出。
    private func startScaleAnimation(for cell: SlideCell) {
        guard
            let visual = try? ElementCompositionPreview.getElementVisual(cell),
            let sources = scrollView.expressionAnimationSources,
            let compositor = visual.compositor,
            stride > 0
        else { return }

        let slope = Self.number((1 - neighborScale) / stride)
        // 视口半长减去端部留白恰为幻灯片半长（视口比幻灯片短时留白为 0，退回视口半长）。
        // Viewport / Position 取自 ScrollView 的动画属性集：Position 即滚动偏移（朝页码
        // 增大方向为正），表达式全程在合成线程求值，缩放与滚动位置逐帧同步。
        let restCenter = "min(sv.Viewport.Y, \(Self.number(max(0, slideHeight)))) / 2"
        let slideCenter = "item.Offset.Y + item.Size.Y / 2"
        guard
            let scale = try? compositor.createExpressionAnimation(
                "max(\(Self.number(minimumScale)), 1 - abs((\(restCenter) + sv.Position.Y) - (\(slideCenter))) * \(slope))"
            ),
            let center = try? compositor.createExpressionAnimation(
                "Vector3(item.Size.X / 2, item.Size.Y / 2, 0)")
        else { return }
        do {
            try scale.setReferenceParameter("sv", sources)
            try scale.setReferenceParameter("item", visual)
            try center.setReferenceParameter("item", visual)
            try visual.startAnimation("Scale.X", scale)
            try visual.startAnimation("Scale.Y", scale)
            try visual.startAnimation("CenterPoint", center)
        } catch {
            // 启动失败不会抛到用户面前，只表现为"不缩放"——必须留痕。
            log.warning("ImageCarousel: scale animation failed to start: \(error)")
        }
    }

    /// 表达式字面量统一用定点记号：`%.g` 在极端值下会输出指数记号。
    private static func number(_ value: Double) -> String {
        String(format: "%.6g", value)
    }

    // MARK: - 选择

    private func select(_ index: Int) {
        guard imageURLs.indices.contains(index) else { return }
        let target = offset(forPage: index)
        isScrollingToSelection = abs(target - currentOffset) > 0.5
        scrollTo(offset: target, animated: true)
        commitSelection(index)
    }

    private func commitSelection(_ index: Int) {
        guard index != _selectedIndex else { return }
        _selectedIndex = index
        syncPager()
        selectedIndexChanged.invoke(self, index)
    }

    private func syncPager() {
        guard
            pipsPager.numberOfPages > 0,
            pipsPager.selectedPageIndex != Int32(_selectedIndex)
        else { return }
        isSyncingPager = true
        pipsPager.selectedPageIndex = Int32(_selectedIndex)
        isSyncingPager = false
    }

    private func syncSelectionFromScroll() {
        guard !isScrollingToSelection else { return }
        commitSelection(
            Self.nearestPage(
                toOffset: currentOffset, stride: stride, count: imageURLs.count))
    }

    private func scrollTo(offset: Double, animated: Bool) {
        // 偏移量已是页中心，吸附交给本控件的算术，不让 ScrollPresenter 二次取整。
        let options = ScrollingScrollOptions(
            animated ? .enabled : .disabled, .ignore)
        _ = try? scrollView.scrollTo(0, offset, options)
    }

    /// 距滚动偏移 `offset` 最近的一页。
    static func nearestPage(toOffset offset: Double, stride: Double, count: Int) -> Int {
        guard stride > 0, count > 0 else { return 0 }
        return min(max(Int((offset / stride).rounded()), 0), count - 1)
    }

    private func bindEvents() {
        scrollView.extentChanged.addHandler { [weak self] _, _ in self?.handleExtentChanged() }
        scrollView.loaded.addHandler { [weak self] _, _ in self?.refreshMetrics() }
        scrollView.sizeChanged.addHandler { [weak self] _, _ in self?.refreshMetrics() }
        // ScrollView 自带的滚动动画拖着一秒多的长尾（单页实测约 1.07s），逐页切换显得迟滞。
        scrollView.scrollAnimationStarting.addHandler { _, args in
            (args?.animation as? Vector3KeyFrameAnimation)?.duration = Self.scrollDuration
        }
        scrollView.viewChanged.addHandler { [weak self] _, _ in self?.syncSelectionFromScroll() }
        // 以滚动操作的完成事件收尾：它在滚动结束的当帧触发，不依赖轮询 state。
        scrollView.scrollCompleted.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.isScrollingToSelection = false
            self.syncSelectionFromScroll()
        }

        repeater.elementPrepared.addHandler { [weak self] _, args in
            guard let self, let args, let cell = args.element as? SlideCell else { return }
            self.prepare(cell, at: Int(args.index))
        }
        repeater.elementClearing.addHandler { _, args in
            (args?.element as? SlideCell)?.image.source = nil
        }

        pipsPager.selectedIndexChanged.addHandler { [weak self] _, _ in
            guard let self else { return }
            let index = Int(self.pipsPager.selectedPageIndex)
            // 模板应用时 PipsPager 也会发一次索引未变的事件。
            guard !self.isSyncingPager, index != self._selectedIndex else { return }
            self.select(index)
        }
    }

    private func prepare(_ cell: SlideCell, at index: Int) {
        applyMetrics(to: cell)
        guard imageURLs.indices.contains(index) else { return }
        let url = imageURLs[index]
        let source: BitmapImage
        if let cached = imageSources[url] {
            source = cached
        } else {
            source = BitmapImage(Uri(url.absoluteString))
            imageSources[url] = source
        }
        try? AutomationProperties.setName(cell, url.absoluteString)
        cell.onTap = { [weak self] page in self?.select(page) }
        cell.show(source, pageIndex: index, isDecoded: source.pixelWidth > 0)
    }

    /// 程序化滚动的动画时长。
    private static let scrollDuration = TimeSpan.make(milliseconds: 300)
}

// MARK: - XAML

private var slideXaml: String {
    // swiftformat:disable:next all
    """
    <!-- 背景与圆角放在同一层 Border 上，图片才会被裁进圆角。 -->
    <Border
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Background="{ThemeResource CardBackgroundFillColorDefaultBrush}"
        CornerRadius="8">
        <Grid>
            <Image Name="SlideImage" Stretch="Uniform" />
            <ProgressRing Name="SlideBusy"
                          IsActive="True"
                          HorizontalAlignment="Center"
                          VerticalAlignment="Center" />
            <FontIcon Name="SlideError"
                      Glyph="&#xE783;"
                      FontSize="24"
                      Foreground="{ThemeResource TextFillColorSecondaryBrush}"
                      HorizontalAlignment="Center"
                      VerticalAlignment="Center"
                      Visibility="Collapsed" />
        </Grid>
    </Border>
    """
}

private var xamlUI: String {
    // swiftformat:disable:next all
    """
    <Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <!-- ItemsRepeater 没有 Padding：首尾页居中的端部留白由包住它的 Border 提供。 -->
        <ScrollView Name="Scroller"
                    ContentOrientation="Vertical"
                    HorizontalScrollMode="Disabled"
                    VerticalScrollMode="Enabled"
                    HorizontalScrollBarVisibility="Hidden"
                    VerticalScrollBarVisibility="Hidden">
            <Border Name="SlideHost">
                <ItemsRepeater Name="Repeater">
                    <ItemsRepeater.Layout>
                        <StackLayout Name="SlidesLayout" Orientation="Vertical" Spacing="8" />
                    </ItemsRepeater.Layout>
                </ItemsRepeater>
            </Border>
        </ScrollView>
        <PipsPager Name="Pager"
                   Grid.Column="1"
                   Orientation="Vertical"
                   VerticalAlignment="Center"
                   Margin="8,0,0,0"
                   PreviousButtonVisibility="VisibleOnPointerOver"
                   NextButtonVisibility="VisibleOnPointerOver" />
    </Grid>
    """
}
