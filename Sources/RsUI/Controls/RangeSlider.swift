import UWP
import WinUI
import WindowsFoundation

// MARK: - State

/// `RangeSlider` 的纯数值状态：在 `[minimum, maximum]` 域内维护一对 lower/upper
/// 值,负责 step 吸附与 `minGap` 互斥约束。像素布局与事件分发在 `RangeSlider`。
struct RangeSliderState {
    var minimum: Double = 0
    var maximum: Double = 100
    /// 步进吸附,`0` 表示不吸附(连续取值)。
    var stepFrequency: Double = 0
    /// lower 与 upper 允许的最小间距(钳制到域宽以内)。
    var minGap: Double = 0

    var lowerValue: Double = 25
    var upperValue: Double = 75

    var span: Double { maximum - minimum }

    var range: ClosedRange<Double> { lowerValue...upperValue }

    init(
        minimum: Double = 0,
        maximum: Double = 100,
        stepFrequency: Double = 0,
        minGap: Double = 0,
        lowerValue: Double = 25,
        upperValue: Double = 75
    ) {
        self.minimum = minimum
        self.maximum = max(maximum, minimum)
        self.stepFrequency = max(0, stepFrequency)
        self.minGap = min(max(0, minGap), span)
        self.lowerValue = lowerValue
        self.upperValue = upperValue
        _ = setRange(lower: lowerValue, upper: upperValue)
    }

    /// 吸附到最近的 step 并消除浮点尾差。
    func snapped(_ value: Double) -> Double {
        guard stepFrequency > 0 else { return value }
        let steps = (value / stepFrequency).rounded()
        return clean(steps * stepFrequency)
    }

    private func clean(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }

    /// 值 → `[0, 1]` 比例。
    func fraction(of value: Double) -> Double {
        guard span > 0 else { return 0 }
        return min(max((value - minimum) / span, 0), 1)
    }

    /// `[0, 1]` 比例 → 域值(未吸附,吸附发生在 setLower / setUpper)。
    func value(atFraction fraction: Double) -> Double {
        minimum + min(max(fraction, 0), 1) * span
    }

    /// 设置 lower,吸附后钳制到 `[minimum, upperValue - minGap]`。
    mutating func setLower(_ raw: Double) -> Bool {
        let newValue = min(max(snapped(raw), minimum), max(minimum, upperValue - minGap))
        guard newValue != lowerValue else { return false }
        lowerValue = newValue
        return true
    }

    /// 设置 upper,吸附后钳制到 `[lowerValue + minGap, maximum]`。
    mutating func setUpper(_ raw: Double) -> Bool {
        let newValue = max(min(snapped(raw), maximum), min(maximum, lowerValue + minGap))
        guard newValue != upperValue else { return false }
        upperValue = newValue
        return true
    }

    /// 整体设置：乱序自动交换;间距不足时以 lower 为锚扩展 upper,
    /// upper 顶到 maximum 时再回拉 lower。
    mutating func setRange(lower rawLower: Double, upper rawUpper: Double) -> Bool {
        var lower = min(max(snapped(rawLower), minimum), maximum)
        var upper = min(max(snapped(rawUpper), minimum), maximum)
        if lower > upper { swap(&lower, &upper) }
        if upper - lower < minGap {
            upper = min(lower + minGap, maximum)
            lower = max(upper - minGap, minimum)
        }
        guard lower != lowerValue || upper != upperValue else { return false }
        lowerValue = lower
        upperValue = upper
        return true
    }

    /// 调整域参数后重校验(钳 minGap 到域宽、重吸附并重排现有值)。
    /// 收缩 domain 时旧值可能双双越界,需要两轮 set 才能恢复 lower ≤ upper 不变式。
    mutating func setDomain(
        minimum: Double? = nil,
        maximum: Double? = nil,
        stepFrequency: Double? = nil,
        minGap: Double? = nil
    ) -> Bool {
        let oldLower = lowerValue
        let oldUpper = upperValue

        if let minimum { self.minimum = minimum }
        if let maximum { self.maximum = max(maximum, self.minimum) }
        if let stepFrequency { self.stepFrequency = max(0, stepFrequency) }
        if let minGap { self.minGap = min(max(0, minGap), max(0, span)) }

        _ = setLower(lowerValue)
        _ = setUpper(upperValue)
        _ = setLower(lowerValue)

        return lowerValue != oldLower || upperValue != oldUpper
    }

    /// 整体平移（不吸附）：拖拽过程逐帧 1:1 跟随用，保持窗宽严格不变，
    /// 整体钳制在域内 —— 平移到 minimum / maximum 边界即停住。
    mutating func shiftRaw(by delta: Double) -> Bool {
        let clamped = min(max(delta, minimum - lowerValue), maximum - upperValue)
        guard clamped != 0 else { return false }
        lowerValue += clamped
        upperValue += clamped
        return true
    }

    /// 整体平移（键盘步进用）：`delta` 按 step 网格吸附（作用于位移量，不破坏窗宽）。
    mutating func shift(by delta: Double) -> Bool {
        var d = delta
        if stepFrequency > 0 {
            d = clean((delta / stepFrequency).rounded() * stepFrequency)
        }
        return shiftRaw(by: d)
    }

    /// 拖拽结束时把窗口对齐到 step 网格（吸附下限、保持窗宽、整体平移差值）。
    mutating func settleToStep() -> Bool {
        guard stepFrequency > 0 else { return false }
        let snappedLower = minimum + clean(((lowerValue - minimum) / stepFrequency).rounded() * stepFrequency)
        return shiftRaw(by: snappedLower - lowerValue)
    }
}

// MARK: - Control

/// 双滑块范围选择控件：在一条轨道上提供 lower/upper 两个滑块,选取
/// `[lowerValue, upperValue]` 区间(如医学影像的窗宽/窗位调节)。
///
/// 视觉与交互 1:1 复刻 WinUI 3 原生 `Slider` / Community Toolkit `RangeSelector`：
/// 滑块是真正的 `Thumb` 控件,套用官方 `Slider_themeresources.xaml` 的 thumb 模板
/// (外环 `Margin=-2` + 1px elevation 边框 + 内圆 12px 缩放三态 0.86/1.167/0.71,
/// 悬停/按压动画由 Thumb 自带状态机自动驱动);轨道 4px 圆角 2,颜色全部走
/// `Slider*` 官方主题资源(随明暗主题自动更新)。每个滑块是独立 Tab 停靠,
/// 拖拽/键盘步进时在滑块上方显示数值 Tooltip(Toolkit 同款)。
///
/// 交互：直接拖动滑块(Thumb 原生捕获)、点击轨道(就近滑块跳到点击处后拖拽)、
/// 键盘(聚焦滑块后 ←/→ 步进,PageUp/PageDown 大步进,Home/End 到边界)。
public class RangeSlider: ContentControl {

    /// `valueChanged` 事件的负载。
    public struct Change {
        public let old: ClosedRange<Double>
        public let new: ClosedRange<Double>
    }

    /// lower/upper 值变化时触发(拖动、点击轨道、键盘、程序赋值)。
    public let valueChanged = EventWithArgumentHandler<RangeSlider, Change>()

    /// 拖拽/键盘操作时的数值 Tooltip 是否显示。默认开启。
    public var isToolTipEnabled = true

    private enum Handle {
        case lower
        case upper

        var isLower: Bool {
            if case .lower = self { return true }
            return false
        }
    }

    /// 官方 Slider 主题资源数值(SliderHorizontalHeight / SliderHorizontalThumb* /
    /// SliderTrackThemeHeight),Canvas 定位换算用。
    private enum Metrics {
        static let controlHeight: Double = 32
        static let thumbSize: Double = 18
        static let trackHeight: Double = 4
        /// 选区窄于该宽度时禁用整体拖动命中面。
        static let fillDragMinWidth: Double = 8
    }

    private var state: RangeSliderState

    // XAML 命名元素
    private var root: Grid!
    private var trackBackground: Border!
    private var activeRectangle: Rectangle!
    private var toolTip: Grid!
    private var toolTipText: TextBlock!
    private var lowerThumb: Thumb!
    private var upperThumb: Thumb!
    /// 两滑块之间的透明 Thumb 命中面：拖动它 = 同步平移（滑动窗口）。
    /// 用真 Thumb 承载，使整体平移骑在与单滑块完全相同的原生拖拽管线上。
    private var fillDrag: Thumb!

    /// 轨道点击发起的拖拽（滑块直接抓取由 Thumb.drag* 事件驱动，两路并存）。
    private var trackDraggingHandle: Handle?
    /// Thumb 拖拽的累计像素位置(DragDelta 只给增量)。
    private var thumbDragPosition: Double = 0
    /// 选区命中面拖拽的累计像素位置。
    private var fillDragPosition: Double = 0
    private var fillDragging = false
    private var hoveringControl = false
    /// 手动状态机：当前状态名与其 Storyboard（goToElementStateCore 失效的替代）。
    private var activeStateName: String?
    private var activeStateStoryboard: Storyboard?
    private var toolTipHideTask: Task<Void, Never>?
    /// tooltip 尺寸缓存键（文本），变化时才重新 measure。
    private var toolTipMeasuredKey: String?

    // MARK: - Init

    public init(
        minimum: Double = 0,
        maximum: Double = 100,
        lowerValue: Double = 25,
        upperValue: Double = 75,
        stepFrequency: Double = 0,
        minGap: Double = 0
    ) {
        state = RangeSliderState(
            minimum: minimum,
            maximum: maximum,
            stepFrequency: stepFrequency,
            minGap: minGap,
            lowerValue: lowerValue,
            upperValue: upperValue)
        super.init()

        setupUI()
        bindEvents()
    }

    // MARK: - Value & domain

    /// 当前选区。setter 乱序自动交换、间距不足自动补齐。
    public var range: ClosedRange<Double> {
        get { state.range }
        set { commitStateChange { $0.setRange(lower: newValue.lowerBound, upper: newValue.upperBound) } }
    }

    public var lowerValue: Double {
        get { state.lowerValue }
        set { commitStateChange { $0.setLower(newValue) } }
    }

    public var upperValue: Double {
        get { state.upperValue }
        set { commitStateChange { $0.setUpper(newValue) } }
    }

    public var minimum: Double {
        get { state.minimum }
        set { commitStateChange { $0.setDomain(minimum: newValue) } }
    }

    public var maximum: Double {
        get { state.maximum }
        set { commitStateChange { $0.setDomain(maximum: newValue) } }
    }

    public var stepFrequency: Double {
        get { state.stepFrequency }
        set { commitStateChange { $0.setDomain(stepFrequency: newValue) } }
    }

    /// lower 与 upper 允许的最小间距(超出域宽时钳制到域宽)。
    public var minGap: Double {
        get { state.minGap }
        set { commitStateChange { $0.setDomain(minGap: newValue) } }
    }

    /// 统一的改值入口：改 state → 重排视觉 → 值变化时广播。
    private func commitStateChange(_ mutate: (inout RangeSliderState) -> Bool) {
        let old = range
        let valuesChanged = mutate(&state)
        updateTrackLayout()
        if valuesChanged {
            valueChanged.invoke(self, Change(old: old, new: range))
        }
    }

    // MARK: - UI setup

    private func setupUI() {
        let loaded: Grid = App.context.requireXaml(withString: xamlUI)
        root = loaded
        trackBackground = loaded.requireElement("TrackBackground")
        activeRectangle = loaded.requireElement("ActiveRectangle")
        toolTip = loaded.requireElement("ToolTip")
        toolTipText = loaded.requireElement("ToolTipText")
        lowerThumb = loaded.requireElement("LowerThumb")
        upperThumb = loaded.requireElement("UpperThumb")
        fillDrag = loaded.requireElement("FillDrag")

        content = loaded
        isTabStop = false
        minWidth = 64
        horizontalAlignment = .stretch
        horizontalContentAlignment = .stretch

        updateTrackLayout()
    }

    private func bindEvents() {
        // 轨道：点击跳转 + 拖拽(按压落在滑块上时交给 Thumb 原生捕获,不跳值)。
        // 指针事件必须注册在控件自身：capturePointer 捕获在 self 上，捕获期间的
        // 事件只在捕获元素上触发并向上冒泡，子元素（root）收不到 —— 否则拖拽
        // 过程中收不到 pointerMoved，UI 会等到松手才更新。
        pointerPressed.addHandler { [weak self] _, args in self?.handlePointerPressed(args) }
        pointerMoved.addHandler { [weak self] _, args in self?.handlePointerMoved(args) }
        pointerReleased.addHandler { [weak self] _, args in self?.handlePointerReleased(args) }
        pointerCanceled.addHandler { [weak self] _, _ in self?.endTrackDragging() }
        pointerCaptureLost.addHandler { [weak self] _, _ in self?.endTrackDragging() }

        pointerEntered.addHandler { [weak self] _, _ in
            guard let self else { return }
            hoveringControl = true
            updateControlState()
        }
        pointerExited.addHandler { [weak self] _, _ in
            guard let self else { return }
            hoveringControl = false
            updateControlState()
        }

        // 滑块：Thumb 原生拖拽(悬停/按压缩放动画由 Thumb 状态机自动播放)。
        lowerThumb.dragStarted.addHandler { [weak self] _, _ in self?.handleThumbDragStarted(.lower) }
        upperThumb.dragStarted.addHandler { [weak self] _, _ in self?.handleThumbDragStarted(.upper) }
        lowerThumb.dragDelta.addHandler { [weak self] _, args in self?.handleThumbDragDelta(.lower, args) }
        upperThumb.dragDelta.addHandler { [weak self] _, args in self?.handleThumbDragDelta(.upper, args) }
        lowerThumb.dragCompleted.addHandler { [weak self] _, _ in self?.handleThumbDragCompleted() }
        upperThumb.dragCompleted.addHandler { [weak self] _, _ in self?.handleThumbDragCompleted() }

        // 选区命中面：拖动 = 整体平移（同一条原生拖拽管线）。
        fillDrag.dragStarted.addHandler { [weak self] _, _ in self?.handleFillDragStarted() }
        fillDrag.dragDelta.addHandler { [weak self] _, args in self?.handleFillDragDelta(args) }
        fillDrag.dragCompleted.addHandler { [weak self] _, _ in self?.handleFillDragCompleted() }

        // 键盘：聚焦到哪个滑块,方向键就驱动哪个。
        lowerThumb.keyDown.addHandler { [weak self] _, args in self?.handleKeyDown(.lower, args) }
        upperThumb.keyDown.addHandler { [weak self] _, args in self?.handleKeyDown(.upper, args) }

        isEnabledChanged.addHandler { [weak self] _, _ in self?.updateControlState() }

        // ThemeResource 画刷随主题自动更新;重进当前状态以刷新状态 Storyboard 持有的画刷。
        // ThemeResource 画刷随主题自动更新;清掉状态缓存以重跑当前状态的 Storyboard。
        root.actualThemeChanged.addHandler { [weak self] _, _ in
            guard let self else { return }
            activeStateName = nil
            updateControlState()
        }

        root.sizeChanged.addHandler { [weak self] _, _ in self?.updateTrackLayout() }
        root.loaded.addHandler { [weak self] _, _ in self?.updateTrackLayout() }
    }

    // MARK: - Visual states

    /// 控件级状态(Normal / PointerOver / MinPressed / MaxPressed / WindowPressed /
    /// Disabled)，决定轨道、选区与滑块颜色;名字与 Toolkit RangeSelector 一致，
    /// 经 goToVisualState 手动驱动松散 XAML 上的状态机。
    private func updateControlState() {
        let name: String
        if !isEnabled {
            name = "Disabled"
        } else if fillDragging {
            name = "WindowPressed"
        } else if let dragging = currentDraggingHandle {
            name = dragging.isLower ? "MinPressed" : "MaxPressed"
        } else if hoveringControl {
            name = "PointerOver"
        } else {
            name = "Normal"
        }
        goToVisualState(name)
    }

    /// `FrameworkElement.goToElementStateCore` 在 XamlReader 松散 XAML 上恒返回
    /// false（状态机不工作，实测确认），改为手动驱动：从 root 的
    /// VisualStateGroups 取目标状态的 Storyboard 直接 begin，并停掉上一个。
    private func goToVisualState(_ name: String) {
        guard name != activeStateName else { return }
        guard let groups = try? VisualStateManager.getVisualStateGroups(root) else { return }
        for case let group? in groups where group.name == "CommonStates" {
            for case let state? in group.states where state.name == name {
                try? activeStateStoryboard?.stop()
                activeStateStoryboard = state.storyboard
                try? state.storyboard?.begin()
                activeStateName = name
                return
            }
        }
    }

    private var currentDraggingHandle: Handle? {
        trackDraggingHandle ?? thumbDragHandle
    }

    private var thumbDragHandle: Handle?

    // MARK: - Track pointer interaction

    private func handlePointerPressed(_ args: PointerRoutedEventArgs?) {
        guard isEnabled, let args, let point = try? args.getCurrentPoint(root) else { return }
        guard !pressedOnThumb(args) else { return }  // 滑块自身处理：无跳值,原生手感

        let x = Double(point.position.x)
        let handle = nearestHandle(toX: x)

        raiseThumb(of: handle)
        _ = try? thumbControl(of: handle).focus(.pointer)

        trackDraggingHandle = handle
        _ = try? capturePointer(args.pointer)
        applyValue(atX: x)
        showToolTip(for: handle)
        updateControlState()
        args.handled = true
    }

    private func handlePointerMoved(_ args: PointerRoutedEventArgs?) {
        guard let handle = trackDraggingHandle, let args,
            let point = try? args.getCurrentPoint(root)
        else { return }
        applyValue(atX: Double(point.position.x))
        showToolTip(for: handle)
        args.handled = true
    }

    private func handlePointerReleased(_ args: PointerRoutedEventArgs?) {
        guard trackDraggingHandle != nil, let args else { return }
        endTrackDragging()
        try? releasePointerCapture(args.pointer)
        args.handled = true
    }

    private func endTrackDragging() {
        guard trackDraggingHandle != nil else { return }
        trackDraggingHandle = nil
        hideToolTip()
        updateControlState()
    }

    /// 按压是否落在某个 Thumb（滑块或选区命中面）上：沿 visual tree 上溯判断。
    /// 这些表面自带原生拖拽处理，无需跳值。
    private func pressedOnThumb(_ args: PointerRoutedEventArgs) -> Bool {
        var element = args.originalSource as? UIElement
        while let current = element {
            if current === lowerThumb || current === upperThumb || current === fillDrag { return true }
            element = (try? VisualTreeHelper.getParent(current)) as? UIElement
        }
        return false
    }

    private func applyValue(atX x: Double) {
        let target = state.value(atFraction: pixelFraction(atX: x))
        let handle = currentDraggingHandle ?? .lower
        commitStateChange { state in
            handle.isLower ? state.setLower(target) : state.setUpper(target)
        }
    }

    // MARK: - Thumb drag interaction

    private func handleThumbDragStarted(_ handle: Handle) {
        raiseThumb(of: handle)
        thumbDragPosition = thumbX(of: handle.isLower ? state.lowerValue : state.upperValue)
        thumbDragHandle = handle
        _ = try? thumbControl(of: handle).focus(.pointer)
        showToolTip(for: handle)
        updateControlState()
    }

    private func handleThumbDragDelta(_ handle: Handle, _ args: DragDeltaEventArgs?) {
        guard let args else { return }
        thumbDragPosition += Double(args.horizontalChange)

        let usable = max(0, Double(root.actualWidth) - Metrics.thumbSize)
        let fraction = usable > 0 ? min(max(thumbDragPosition / usable, 0), 1) : 0
        let target = state.value(atFraction: fraction)
        commitStateChange { state in
            handle.isLower ? state.setLower(target) : state.setUpper(target)
        }
        // 以吸附/钳制后的实际位置继续累计,避免拖拽与吸附错位。
        thumbDragPosition = thumbX(of: handle.isLower ? state.lowerValue : state.upperValue)
        showToolTip(for: handle)
    }

    private func handleThumbDragCompleted() {
        thumbDragHandle = nil
        hideToolTip()
        updateTrackLayout()
        updateControlState()
    }

    // MARK: - Fill (window) drag interaction

    /// 选区命中面的整体平移：数学与滑块拖拽完全一致（以 lower thumb 位置为锚），
    /// 区别仅在于 dragDelta 来自 FillDrag 这个透明 Thumb。
    private func handleFillDragStarted() {
        fillDragPosition = thumbX(of: state.lowerValue)
        fillDragging = true
        showWindowToolTip()
        updateControlState()
    }

    private func handleFillDragDelta(_ args: DragDeltaEventArgs?) {
        guard let args else { return }
        fillDragPosition += Double(args.horizontalChange)

        let usable = max(0, Double(root.actualWidth) - Metrics.thumbSize)
        let fraction = usable > 0 ? min(max(fillDragPosition / usable, 0), 1) : 0
        let targetLower = state.value(atFraction: fraction)
        // 读取必须在 inout 闭包外完成：闭包内再读 self.state 会触发
        // Swift 独占性检查（Simultaneous accesses）直接崩溃。
        let delta = targetLower - state.lowerValue

        commitStateChange { $0.shiftRaw(by: delta) }
        // 以钳制后的实际位置继续累计，避免拖拽与边界错位。
        fillDragPosition = thumbX(of: state.lowerValue)
        showWindowToolTip()
    }

    private func handleFillDragCompleted() {
        fillDragging = false
        commitStateChange { $0.settleToStep() }
        hideToolTip()
        updateTrackLayout()
        updateControlState()
    }

    // MARK: - Keyboard interaction

    private func handleKeyDown(_ handle: Handle, _ args: KeyRoutedEventArgs?) {
        guard isEnabled, let args else { return }
        // 未设置 step 时以 1/100 域宽作为键盘步进。
        let step = state.stepFrequency > 0 ? state.stepFrequency : max(state.span / 100, 0)

        switch args.key {
        case VirtualKey.left, VirtualKey.right:
            let sign: Double = args.key == VirtualKey.left ? -1 : 1
            moveHandle(handle, by: sign * step)
        case VirtualKey.pageUp, VirtualKey.pageDown:
            let sign: Double = args.key == VirtualKey.pageUp ? 1 : -1
            moveHandle(handle, by: sign * step * 10)
        case VirtualKey.home:
            let target = handle.isLower ? state.minimum : state.lowerValue + state.minGap
            commitStateChange { state in
                handle.isLower ? state.setLower(target) : state.setUpper(target)
            }
        case VirtualKey.end:
            let target = handle.isLower ? state.upperValue - state.minGap : state.maximum
            commitStateChange { state in
                handle.isLower ? state.setLower(target) : state.setUpper(target)
            }
        default:
            return
        }
        args.handled = true
        showToolTip(for: handle)
        scheduleToolTipAutoHide()
    }

    private func moveHandle(_ handle: Handle, by delta: Double) {
        guard delta != 0 else { return }
        let target = handle.isLower ? state.lowerValue + delta : state.upperValue + delta
        commitStateChange { state in
            handle.isLower ? state.setLower(target) : state.setUpper(target)
        }
    }

    // MARK: - Layout

    /// 像素 x → `[0, 1]`。滑块中心可触达轨道全长(thumbSize/2 内衬)。
    private func pixelFraction(atX x: Double) -> Double {
        let usable = max(0, Double(root.actualWidth) - Metrics.thumbSize)
        guard usable > 0 else { return 0 }
        return min(max((x - Metrics.thumbSize / 2) / usable, 0), 1)
    }

    /// 值 → 滑块左缘像素 x。
    private func thumbX(of value: Double) -> Double {
        let usable = max(0, Double(root.actualWidth) - Metrics.thumbSize)
        return state.fraction(of: value) * usable
    }

    private func thumbCenterX(of handle: Handle) -> Double {
        thumbX(of: handle.isLower ? state.lowerValue : state.upperValue) + Metrics.thumbSize / 2
    }

    private func nearestHandle(toX x: Double) -> Handle {
        // 平手时偏向 lower(Toolkit RangeSelector 同款)。
        let lowerDiff = abs(x - thumbCenterX(of: .lower))
        let upperDiff = abs(x - thumbCenterX(of: .upper))
        return upperDiff < lowerDiff ? .upper : .lower
    }

    private func thumbControl(of handle: Handle) -> Thumb {
        handle.isLower ? lowerThumb : upperThumb
    }

    /// 拖拽中的滑块提升 z-order(Toolkit 同款)。
    private func raiseThumb(of handle: Handle) {
        try? Canvas.setZIndex(thumbControl(of: handle), 10)
        try? Canvas.setZIndex(thumbControl(of: handle.isLower ? Handle.upper : Handle.lower), 0)
    }

    /// 重排两个滑块与选区矩形(轨道由 XAML 布局自管)。
    /// 选区对齐滑块中心,与原生 Slider 的 DecreaseRect 到 thumb 中心的几何一致。
    private func updateTrackLayout() {
        guard root != nil else { return }
        let lowerX = thumbX(of: state.lowerValue)
        let upperX = thumbX(of: state.upperValue)

        try? Canvas.setLeft(lowerThumb, lowerX)
        try? Canvas.setLeft(upperThumb, upperX)
        try? Canvas.setLeft(activeRectangle, lowerX + Metrics.thumbSize / 2)
        activeRectangle.width = max(0, upperX - lowerX)

        // 选区命中面覆盖 [lower 中心, upper 中心]，z-order 在滑块之下；
        // 选区过窄（两滑块接近重合）时禁用命中，回落到就近滑块逻辑。
        try? Canvas.setLeft(fillDrag, lowerX + Metrics.thumbSize / 2)
        fillDrag.width = max(0, upperX - lowerX)
        fillDrag.isHitTestVisible = (upperX - lowerX) >= Metrics.fillDragMinWidth
    }

    // MARK: - ToolTip

    /// 拖拽/键盘步进时在滑块上方显示当前值(Toolkit RangeSelector 同款交互)。
    private func showToolTip(for handle: Handle) {
        guard isToolTipEnabled else { return }
        let value = handle.isLower ? state.lowerValue : state.upperValue
        toolTipText.text = formatValue(value)
        toolTip.visibility = .visible
        positionToolTip(centerX: thumbCenterX(of: handle))
    }

    /// 窗口整体平移时显示两端值与窗宽，例如 "-160 – 240 (W 400)"。
    private func showWindowToolTip() {
        guard isToolTipEnabled else { return }
        toolTipText.text =
            "\(formatValue(state.lowerValue)) – \(formatValue(state.upperValue)) (W \(formatValue(state.upperValue - state.lowerValue)))"
        toolTip.visibility = .visible
        positionToolTip(centerX: (thumbCenterX(of: .lower) + thumbCenterX(of: .upper)) / 2)
    }

    private func positionToolTip(centerX: Double) {
        // 文本变化时才做一次 scoped measure 并缓存尺寸。
        // 不能在每次 move 里 updateLayout()——那是全树同步布局，会把 UI 线程
        // 塞爆导致拖拽卡顿（先冻住、积压消化后一跳一大截）。
        let key = toolTipText.text
        if key != toolTipMeasuredKey {
            try? toolTip.measure(
                WindowsFoundation.Size(width: .infinity, height: .infinity))
            toolTipMeasuredKey = key
        }
        let width = Double(toolTip.desiredSize.width)
        guard width > 0 else { return }
        let canvasWidth = Double(root.actualWidth)
        let left = min(max(centerX - width / 2, 0), max(0, canvasWidth - width))
        try? Canvas.setLeft(toolTip, left)
        // 滑块顶缘(7)上方留 12px 间距;canvas 不裁剪,可为负值。
        try? Canvas.setTop(toolTip, 7 - Double(toolTip.desiredSize.height) - 12)
    }

    private func hideToolTip() {
        toolTipHideTask?.cancel()
        toolTipHideTask = nil
        toolTip.visibility = .collapsed
    }

    /// 键盘步进后 1s 自动隐藏(Toolkit 用 DispatcherQueueTimer 防抖,此处等价)。
    private func scheduleToolTipAutoHide() {
        toolTipHideTask?.cancel()
        toolTipHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.toolTip.visibility = .collapsed
        }
    }

    /// 与 Toolkit 的 `{0:0.##}` 对齐：整数不带小数,小数保留两位。
    private func formatValue(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }
}

private var xamlUI: String {
    // swiftformat:disable:next all
    """
    <!-- 复刻 WinUI 3 官方 Slider 模板(microsoft-ui-xaml Slider_themeresources.xaml)
         + Community Toolkit RangeSelector 的双滑块布局。
         几何：控件高 32(SliderHorizontalHeight),轨道 4(SliderTrackThemeHeight) 圆角
         2(SliderTrackCornerRadius) 垂直居中;滑块 18x18(SliderHorizontalThumb*),
         Canvas.Top 7 = (32-18)/2;内圆 12(SliderInnerThumb*),外环 Border Margin -2、
         圆角 10(SliderThumbCornerRadius)、1px SliderThumbBorderBrush(elevation)。
         内圆缩放三态 0.86/1.167/0.71(官方 thumb 模板原值)由 Thumb 状态机自动驱动;
         动画时长为官方 ControlFast/NormalAnimationDuration 的字面量(0.15s/0.25s),
         缓动 ControlFastOutSlowInKeySpline 字面量(0,0,0,1)。
         控件级状态经 FrameworkElement.goToElementStateCore 驱动。 -->
    <Grid
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Name="Root"
        Height="32"
        Background="Transparent">
        <Grid.Resources>
            <Style x:Key="SliderThumbStyle" TargetType="Thumb">
                <Setter Property="UseSystemFocusVisuals" Value="True" />
                <Setter Property="BorderThickness" Value="1" />
                <Setter Property="BorderBrush" Value="{ThemeResource SliderThumbBorderBrush}" />
                <Setter Property="Background" Value="{ThemeResource SliderThumbBackground}" />
                <Setter Property="Height" Value="18" />
                <Setter Property="Width" Value="18" />
                <Setter Property="CornerRadius" Value="10" />
                <Setter Property="FocusVisualMargin" Value="-7" />
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="Thumb">
                            <Border Margin="-2"
                                    Background="{ThemeResource SliderOuterThumbBackground}"
                                    BorderBrush="{TemplateBinding BorderBrush}"
                                    BorderThickness="{TemplateBinding BorderThickness}"
                                    CornerRadius="{TemplateBinding CornerRadius}">
                                <VisualStateManager.VisualStateGroups>
                                    <VisualStateGroup x:Name="CommonStates">
                                        <VisualState x:Name="Normal">
                                            <Storyboard>
                                                <DoubleAnimationUsingKeyFrames Storyboard.TargetName="SliderInnerThumb" Storyboard.TargetProperty="(UIElement.RenderTransform).(CompositeTransform.ScaleX)">
                                                    <SplineDoubleKeyFrame KeyTime="0:0:0.15" KeySpline="0,0,0,1" Value="0.86" />
                                                </DoubleAnimationUsingKeyFrames>
                                                <DoubleAnimationUsingKeyFrames Storyboard.TargetName="SliderInnerThumb" Storyboard.TargetProperty="(UIElement.RenderTransform).(CompositeTransform.ScaleY)">
                                                    <SplineDoubleKeyFrame KeyTime="0:0:0.15" KeySpline="0,0,0,1" Value="0.86" />
                                                </DoubleAnimationUsingKeyFrames>
                                            </Storyboard>
                                        </VisualState>
                                        <VisualState x:Name="PointerOver">
                                            <Storyboard>
                                                <DoubleAnimationUsingKeyFrames Storyboard.TargetName="SliderInnerThumb" Storyboard.TargetProperty="(UIElement.RenderTransform).(CompositeTransform.ScaleX)">
                                                    <SplineDoubleKeyFrame KeyTime="0:0:0.25" KeySpline="0,0,0,1" Value="1.167" />
                                                </DoubleAnimationUsingKeyFrames>
                                                <DoubleAnimationUsingKeyFrames Storyboard.TargetName="SliderInnerThumb" Storyboard.TargetProperty="(UIElement.RenderTransform).(CompositeTransform.ScaleY)">
                                                    <SplineDoubleKeyFrame KeyTime="0:0:0.25" KeySpline="0,0,0,1" Value="1.167" />
                                                </DoubleAnimationUsingKeyFrames>
                                                <ObjectAnimationUsingKeyFrames Storyboard.TargetName="SliderInnerThumb" Storyboard.TargetProperty="Fill">
                                                    <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderThumbBackgroundPointerOver}" />
                                                </ObjectAnimationUsingKeyFrames>
                                            </Storyboard>
                                        </VisualState>
                                        <VisualState x:Name="Pressed">
                                            <Storyboard>
                                                <DoubleAnimationUsingKeyFrames Storyboard.TargetName="SliderInnerThumb" Storyboard.TargetProperty="(UIElement.RenderTransform).(CompositeTransform.ScaleX)">
                                                    <SplineDoubleKeyFrame KeyTime="0:0:0.25" KeySpline="0,0,0,1" Value="0.71" />
                                                </DoubleAnimationUsingKeyFrames>
                                                <DoubleAnimationUsingKeyFrames Storyboard.TargetName="SliderInnerThumb" Storyboard.TargetProperty="(UIElement.RenderTransform).(CompositeTransform.ScaleY)">
                                                    <SplineDoubleKeyFrame KeyTime="0:0:0.25" KeySpline="0,0,0,1" Value="0.71" />
                                                </DoubleAnimationUsingKeyFrames>
                                                <ObjectAnimationUsingKeyFrames Storyboard.TargetName="SliderInnerThumb" Storyboard.TargetProperty="Fill">
                                                    <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderThumbBackgroundPressed}" />
                                                </ObjectAnimationUsingKeyFrames>
                                            </Storyboard>
                                        </VisualState>
                                        <VisualState x:Name="Disabled">
                                            <Storyboard>
                                                <DoubleAnimationUsingKeyFrames Storyboard.TargetName="SliderInnerThumb" Storyboard.TargetProperty="(UIElement.RenderTransform).(CompositeTransform.ScaleX)">
                                                    <SplineDoubleKeyFrame KeyTime="0:0:0.15" KeySpline="0,0,0,1" Value="1.167" />
                                                </DoubleAnimationUsingKeyFrames>
                                                <DoubleAnimationUsingKeyFrames Storyboard.TargetName="SliderInnerThumb" Storyboard.TargetProperty="(UIElement.RenderTransform).(CompositeTransform.ScaleY)">
                                                    <SplineDoubleKeyFrame KeyTime="0:0:0.15" KeySpline="0,0,0,1" Value="1.167" />
                                                </DoubleAnimationUsingKeyFrames>
                                            </Storyboard>
                                        </VisualState>
                                    </VisualStateGroup>
                                </VisualStateManager.VisualStateGroups>
                                <Ellipse x:Name="SliderInnerThumb"
                                         Width="12" Height="12"
                                         Fill="{TemplateBinding Background}"
                                         RenderTransformOrigin="0.5, 0.5">
                                    <Ellipse.RenderTransform>
                                        <CompositeTransform />
                                    </Ellipse.RenderTransform>
                                </Ellipse>
                            </Border>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
            </Style>
        </Grid.Resources>
        <VisualStateManager.VisualStateGroups>
            <VisualStateGroup x:Name="CommonStates">
                <VisualState x:Name="Normal">
                    <Storyboard>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="TrackBackground" Storyboard.TargetProperty="Background">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderTrackFill}" />
                        </ObjectAnimationUsingKeyFrames>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="ActiveRectangle" Storyboard.TargetProperty="Fill">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderTrackValueFill}" />
                        </ObjectAnimationUsingKeyFrames>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="LowerThumb" Storyboard.TargetProperty="Background">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderThumbBackground}" />
                        </ObjectAnimationUsingKeyFrames>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="UpperThumb" Storyboard.TargetProperty="Background">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderThumbBackground}" />
                        </ObjectAnimationUsingKeyFrames>
                    </Storyboard>
                </VisualState>
                <VisualState x:Name="PointerOver">
                    <Storyboard>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="ActiveRectangle" Storyboard.TargetProperty="Fill">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderTrackValueFillPointerOver}" />
                        </ObjectAnimationUsingKeyFrames>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="LowerThumb" Storyboard.TargetProperty="Background">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderThumbBackgroundPointerOver}" />
                        </ObjectAnimationUsingKeyFrames>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="UpperThumb" Storyboard.TargetProperty="Background">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderThumbBackgroundPointerOver}" />
                        </ObjectAnimationUsingKeyFrames>
                    </Storyboard>
                </VisualState>
                <VisualState x:Name="MinPressed">
                    <Storyboard>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="ActiveRectangle" Storyboard.TargetProperty="Fill">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderTrackValueFillPressed}" />
                        </ObjectAnimationUsingKeyFrames>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="LowerThumb" Storyboard.TargetProperty="Background">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderThumbBackgroundPressed}" />
                        </ObjectAnimationUsingKeyFrames>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="UpperThumb" Storyboard.TargetProperty="Background">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderThumbBackgroundPressed}" />
                        </ObjectAnimationUsingKeyFrames>
                    </Storyboard>
                </VisualState>
                <VisualState x:Name="MaxPressed">
                    <Storyboard>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="ActiveRectangle" Storyboard.TargetProperty="Fill">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderTrackValueFillPressed}" />
                        </ObjectAnimationUsingKeyFrames>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="LowerThumb" Storyboard.TargetProperty="Background">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderThumbBackgroundPressed}" />
                        </ObjectAnimationUsingKeyFrames>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="UpperThumb" Storyboard.TargetProperty="Background">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderThumbBackgroundPressed}" />
                        </ObjectAnimationUsingKeyFrames>
                    </Storyboard>
                </VisualState>
                <!-- 整体平移（拖动选区命中面）进行中 -->
                <VisualState x:Name="WindowPressed">
                    <Storyboard>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="ActiveRectangle" Storyboard.TargetProperty="Fill">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderTrackValueFillPressed}" />
                        </ObjectAnimationUsingKeyFrames>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="LowerThumb" Storyboard.TargetProperty="Background">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderThumbBackgroundPressed}" />
                        </ObjectAnimationUsingKeyFrames>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="UpperThumb" Storyboard.TargetProperty="Background">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderThumbBackgroundPressed}" />
                        </ObjectAnimationUsingKeyFrames>
                    </Storyboard>
                </VisualState>
                <VisualState x:Name="Disabled">
                    <Storyboard>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="TrackBackground" Storyboard.TargetProperty="Background">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderTrackFillDisabled}" />
                        </ObjectAnimationUsingKeyFrames>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="ActiveRectangle" Storyboard.TargetProperty="Fill">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderTrackValueFillDisabled}" />
                        </ObjectAnimationUsingKeyFrames>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="LowerThumb" Storyboard.TargetProperty="Background">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderThumbBackgroundDisabled}" />
                        </ObjectAnimationUsingKeyFrames>
                        <ObjectAnimationUsingKeyFrames Storyboard.TargetName="UpperThumb" Storyboard.TargetProperty="Background">
                            <DiscreteObjectKeyFrame KeyTime="0" Value="{ThemeResource SliderThumbBackgroundDisabled}" />
                        </ObjectAnimationUsingKeyFrames>
                    </Storyboard>
                </VisualState>
            </VisualStateGroup>
        </VisualStateManager.VisualStateGroups>
        <Border x:Name="TrackBackground" Height="4" VerticalAlignment="Center"
                CornerRadius="2" Background="{ThemeResource SliderTrackFill}" />
        <Canvas Name="ContainerCanvas" Background="Transparent">
            <Rectangle x:Name="ActiveRectangle" Height="4" Canvas.Top="14"
                       Fill="{ThemeResource SliderTrackValueFill}" />
            <!-- 透明 Thumb 命中面：拖动选区 = 整体平移（原生拖拽管线，宽度/位置由代码更新） -->
            <Thumb Name="FillDrag" Height="32" IsTabStop="False"
                   AutomationProperties.Name="Range">
                <Thumb.Template>
                    <ControlTemplate TargetType="Thumb">
                        <Border Background="Transparent" />
                    </ControlTemplate>
                </Thumb.Template>
            </Thumb>
            <Grid Name="ToolTip"
                  Background="{ThemeResource ToolTipBackground}"
                  BorderBrush="{ThemeResource ToolTipBorderBrush}"
                  BorderThickness="{ThemeResource ToolTipBorderThemeThickness}"
                  CornerRadius="{ThemeResource ControlCornerRadius}"
                  Visibility="Collapsed">
                <TextBlock Name="ToolTipText" Margin="8,7,8,5"
                           Foreground="{ThemeResource ToolTipForeground}" />
            </Grid>
            <Thumb Name="LowerThumb" Canvas.Top="7"
                   Style="{StaticResource SliderThumbStyle}"
                   IsTabStop="True" TabIndex="0"
                   AutomationProperties.Name="Lower thumb" />
            <Thumb Name="UpperThumb" Canvas.Top="7"
                   Style="{StaticResource SliderThumbStyle}"
                   IsTabStop="True" TabIndex="1"
                   AutomationProperties.Name="Upper thumb" />
        </Canvas>
    </Grid>
    """
}
