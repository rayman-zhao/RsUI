import Foundation
import RsFoundation
import WinAppSDK
import WinUI

/// Viewer 中可由外部提供内容的四个边缘区域。
public enum ViewerEdge: CaseIterable, Hashable {
    case top, bottom, left, right
}

/// Viewer 区域是否参与布局并显示内容。
public enum ViewerPaneState: Equatable {
    case expanded, collapsed
}

/// 中间区域上下栏的布局模式。
public enum ViewerChromeMode: Equatable {
    /// 上下栏占用中间区域的布局空间。
    case docked

    /// 上下栏覆盖主内容，并由 Viewer 自动处理鼠标靠近显示、移开隐藏。
    case overlay
}

/// 单个 Viewer 区域的初始配置。
///
/// - `content`: 由调用方创建并持有业务语义的 UI 内容；传入 `nil` 时该区域不参与布局。
/// - `state`: 区域是否显示；只有 `content` 不为空时才会实际显示。
/// - `length`: 固定宽度或高度；传入 `nil` 时由内容自动决定尺寸。
public struct ViewerPaneConfiguration {
    public var content: WinUI.UIElement?
    public var state: ViewerPaneState
    public var length: Double?

    public init(
        content: WinUI.UIElement? = nil, state: ViewerPaneState = .collapsed, length: Double? = nil
    ) {
        self.content = content
        self.state = state
        self.length = length
    }
}

/// Viewer 内部持久化的通用布局偏好。
///
/// 调用方只需要设置 `preferenceKey`。Viewer 会保存和恢复左右栏宽度、左右栏展开状态
/// 以及上下栏固定/悬浮模式；业务组件自己的偏好仍放在业务 Preferences 中。
private struct ViewerPreferences: PreferenceValue {
    var entries: [String: ViewerPreferenceEntry] = [:]
}

/// 单个 Viewer 实例对应的持久化状态。宽度可选值 `nil` 代表由内容自动决定尺寸。
private struct ViewerPreferenceEntry: Codable {
    let leftPaneWidth: Double?
    let rightPaneWidth: Double?
    let leftPaneCollapsed: Bool
    let rightPaneCollapsed: Bool
    let chromeModeRaw: String
}

/// 通用 Viewer 布局容器。
///
/// 布局结构为 `左侧 |（顶部 / 主内容 / 底部）| 右侧`。左右区域贯穿全高；
/// 顶部和底部可以固定显示，也可以悬浮覆盖主内容。
///
/// 使用守则：
/// - Viewer 只负责布局、区域状态、拖拽调整和悬浮交互，不应包含具体业务逻辑。
/// - 调用方负责创建各区域内容，并通过回调协调区域、主内容和 ViewModel。
/// - Viewer 可以通过 `preferenceKey` 自行保存通用布局偏好；业务偏好仍由调用方维护。
/// - 同一个 UIElement 同一时间只能属于一个父容器，设置内容前应确保它未挂载到其他位置。
/// - 左右区域支持拖拽调整尺寸；顶部和底部当前只支持固定尺寸或内容自适应。
public final class Viewer: WinUI.Grid {
    // MARK: - 内部状态模型

    private struct PaneRuntimeState {
        var state: ViewerPaneState = .collapsed
        var length: Double?
        var minimumLength: Double = 0
        var maximumLength: Double = .greatestFiniteMagnitude

        func constrained(_ proposedLength: Double) -> Double {
            min(maximumLength, max(minimumLength, proposedLength))
        }
    }

    private enum OverlayPointerRegion: String, Hashable {
        case topChrome, bottomChrome, topHotzone, bottomHotzone
    }

    private struct OverlayRuntimeState {
        var mode: ViewerChromeMode = .docked
        var isVisible = true
        var pointerRegions: Set<OverlayPointerRegion> = []
        var hideTask: Task<Void, Never>?
    }

    private let ui:
        (
            shellRoot: Grid,

            centerContentHost: ContentControl,
            centerOverlayHost: ContentControl,
            topHost: ContentControl,
            bottomHost: ContentControl,
            overlayTopHost: ContentControl,
            overlayBottomHost: ContentControl,
            overlayTopContainer: Border,
            overlayBottomContainer: Border,
            leftHost: ContentControl,
            rightHost: ContentControl,
            topRow: RowDefinition,
            bottomRow: RowDefinition,
            leftColumn: ColumnDefinition,
            rightColumn: ColumnDefinition,
            leftSplitterColumn: ColumnDefinition,
            rightSplitterColumn: ColumnDefinition,
            leftSplitter: Border,
            rightSplitter: Border,
            topHotzone: Border,
            bottomHotzone: Border,
            viewerLeftPaneButton: Button,
            viewerLeftPaneIcon: FontIcon,
            viewerRightPaneButton: Button,
            viewerRightPaneIcon: FontIcon,
            viewerFullscreenButton: Button,
            viewerFullscreenIcon: FontIcon,
            viewerChromeModeButton: Button,
            viewerChromeModeIcon: FontIcon,
            overlayViewerLeftPaneButton: Button,
            overlayViewerLeftPaneIcon: FontIcon,
            overlayViewerRightPaneButton: Button,
            overlayViewerRightPaneIcon: FontIcon,
            overlayViewerFullscreenButton: Button,
            overlayViewerFullscreenIcon: FontIcon,
            overlayViewerChromeModeButton: Button,
            overlayViewerChromeModeIcon: FontIcon,

            leftExpandedStoryboard: Storyboard,
            leftCollapsedStoryboard: Storyboard,
            rightExpandedStoryboard: Storyboard,
            rightCollapsedStoryboard: Storyboard,
            overlayTopShownStoryboard: Storyboard,
            overlayTopHiddenStoryboard: Storyboard,
            overlayBottomShownStoryboard: Storyboard,
            overlayBottomHiddenStoryboard: Storyboard,
        )

    private var panes = Dictionary(
        uniqueKeysWithValues: ViewerEdge.allCases.map { ($0, PaneRuntimeState()) })
    private var overlay = OverlayRuntimeState()
    private var resizingEdge: ViewerEdge?

    private var viewerPreferences = App.context.preferences.load(for: ViewerPreferences.self)
    private var isApplyingStoredPreferences = false
    /// Viewer 通用布局偏好的存储 key。不同业务组件应使用不同 key。
    private let preferenceKey: String

    // MARK: - 公开配置与回调

    /// 是否输出悬浮区域的诊断日志。
    public var isOverlayLoggingEnabled = true

    /// 是否显示 Viewer 内置左侧区域开关。
    public var showsLeftPaneButton = true {
        didSet { updateChromeControls() }
    }

    /// 是否显示 Viewer 内置右侧区域开关。
    public var showsRightPaneButton = true {
        didSet { updateChromeControls() }
    }

    /// 是否显示 Viewer 内置固定/悬浮切换按钮。
    public var showsChromeModeButton = true {
        didSet { updateChromeControls() }
    }

    /// 是否显示 Viewer 内置全屏按钮。具体全屏行为由业务通过 `onFullscreenRequested` 提供。
    public var showsFullscreenButton = false {
        didSet { updateChromeControls() }
    }

    /// 鼠标离开悬浮区域后，自动隐藏上下栏的延迟时间。
    public var overlayHideDelayNanoseconds: UInt64 = 200_000_000

    /// 拖动分隔条时持续通知当前宽度，适合实时更新相关 UI。
    public var onPaneLengthChanged: ((ViewerEdge, Double) -> Void)?

    /// 拖动分隔条结束后通知最终宽度，适合持久化。
    public var onPaneResizeCompleted: ((ViewerEdge, Double) -> Void)?

    /// 区域展开状态发生变化时通知外部，用于业务联动或持久化。
    public var onPaneStateChanged: ((ViewerEdge, ViewerPaneState) -> Void)?

    /// 上下栏固定/悬浮模式发生变化时通知外部。
    public var onChromeModeChanged: ((ViewerChromeMode) -> Void)?

    /// 点击 Viewer 内置全屏按钮时通知外部，由业务决定如何进入或退出全屏。
    public var onFullscreenRequested: (() -> Void)? {
        didSet { updateChromeControls() }
    }

    /// 当前上下栏布局模式。
    public var chromeMode: ViewerChromeMode { overlay.mode }

    /// 中心主内容，例如 WebView、图像或其他任意 UIElement。
    public var centerContent: WinUI.UIElement? {
        get { ui.centerContentHost.content as? WinUI.UIElement }
        set { ui.centerContentHost.content = newValue }
    }

    /// 覆盖在中心主内容之上的非交互内容，例如加载状态或空状态。
    public var centerOverlayContent: WinUI.UIElement? {
        get { ui.centerOverlayHost.content as? WinUI.UIElement }
        set { ui.centerOverlayHost.content = newValue }
    }

    /// 顶部、底部、左侧和右侧区域内容。
    public var topContent: WinUI.UIElement? {
        get { activeChromeHost(.top).content as? WinUI.UIElement }
        set { setPaneContent(newValue, for: .top) }
    }
    public var bottomContent: WinUI.UIElement? {
        get { activeChromeHost(.bottom).content as? WinUI.UIElement }
        set { setPaneContent(newValue, for: .bottom) }
    }
    public var leftContent: WinUI.UIElement? {
        get { ui.leftHost.content as? WinUI.UIElement }
        set { setPaneContent(newValue, for: .left) }
    }
    public var rightContent: WinUI.UIElement? {
        get { ui.rightHost.content as? WinUI.UIElement }
        set { setPaneContent(newValue, for: .right) }
    }

    /// 悬浮模式上下栏的背景，可由具体业务覆盖。
    public var overlayTopBackground: WinUI.Brush? {
        get { ui.overlayTopContainer.background }
        set { ui.overlayTopContainer.background = newValue }
    }
    public var overlayBottomBackground: WinUI.Brush? {
        get { ui.overlayBottomContainer.background }
        set { ui.overlayBottomContainer.background = newValue }
    }

    // MARK: - 初始化

    public init(preferenceKey: String = "default") {
        let loaded = (try? XamlReader.load(App.context.tr(xaml: xamlUI))) as! Grid
        self.ui = (
            shellRoot: loaded,
            centerContentHost: (try? loaded.findName("CenterContentHost")) as! ContentControl,
            centerOverlayHost: (try? loaded.findName("CenterOverlayHost")) as! ContentControl,
            topHost: (try? loaded.findName("TopHost")) as! ContentControl,
            bottomHost: (try? loaded.findName("BottomHost")) as! ContentControl,
            overlayTopHost: (try? loaded.findName("OverlayTopHost")) as! ContentControl,
            overlayBottomHost: (try? loaded.findName("OverlayBottomHost")) as! ContentControl,
            overlayTopContainer: (try? loaded.findName("OverlayTopContainer")) as! Border,
            overlayBottomContainer: (try? loaded.findName("OverlayBottomContainer")) as! Border,
            leftHost: (try? loaded.findName("LeftHost")) as! ContentControl,
            rightHost: (try? loaded.findName("RightHost")) as! ContentControl,
            topRow: (try? loaded.findName("TopRow")) as! RowDefinition,
            bottomRow: (try? loaded.findName("BottomRow")) as! RowDefinition,
            leftColumn: (try? loaded.findName("LeftColumn")) as! ColumnDefinition,
            rightColumn: (try? loaded.findName("RightColumn")) as! ColumnDefinition,
            leftSplitterColumn: (try? loaded.findName("LeftSplitterColumn")) as! ColumnDefinition,
            rightSplitterColumn: (try? loaded.findName("RightSplitterColumn")) as! ColumnDefinition,
            leftSplitter: (try? loaded.findName("LeftSplitter")) as! Border,
            rightSplitter: (try? loaded.findName("RightSplitter")) as! Border,
            topHotzone: (try? loaded.findName("TopHotzone")) as! Border,
            bottomHotzone: (try? loaded.findName("BottomHotzone")) as! Border,
            viewerLeftPaneButton: (try? loaded.findName("ViewerLeftPaneButton")) as! Button,
            viewerLeftPaneIcon: (try? loaded.findName("ViewerLeftPaneIcon")) as! FontIcon,
            viewerRightPaneButton: (try? loaded.findName("ViewerRightPaneButton")) as! Button,
            viewerRightPaneIcon: (try? loaded.findName("ViewerRightPaneIcon")) as! FontIcon,
            viewerFullscreenButton: (try? loaded.findName("ViewerFullscreenButton")) as! Button,
            viewerFullscreenIcon: (try? loaded.findName("ViewerFullscreenIcon")) as! FontIcon,
            viewerChromeModeButton: (try? loaded.findName("ViewerChromeModeButton")) as! Button,
            viewerChromeModeIcon: (try? loaded.findName("ViewerChromeModeIcon")) as! FontIcon,
            overlayViewerLeftPaneButton: (try? loaded.findName("OverlayViewerLeftPaneButton")) as! Button,
            overlayViewerLeftPaneIcon: (try? loaded.findName("OverlayViewerLeftPaneIcon")) as! FontIcon,
            overlayViewerRightPaneButton: (try? loaded.findName("OverlayViewerRightPaneButton")) as! Button,
            overlayViewerRightPaneIcon: (try? loaded.findName("OverlayViewerRightPaneIcon")) as! FontIcon,
            overlayViewerFullscreenButton: (try? loaded.findName("OverlayViewerFullscreenButton")) as! Button,
            overlayViewerFullscreenIcon: (try? loaded.findName("OverlayViewerFullscreenIcon")) as! FontIcon,
            overlayViewerChromeModeButton: (try? loaded.findName("OverlayViewerChromeModeButton")) as! Button,
            overlayViewerChromeModeIcon: (try? loaded.findName("OverlayViewerChromeModeIcon")) as! FontIcon,

            leftExpandedStoryboard: loaded.resources.lookup("LeftExpanded") as! WinUI.Storyboard,
            leftCollapsedStoryboard: loaded.resources.lookup("LeftCollapsed") as! WinUI.Storyboard,
            rightExpandedStoryboard: loaded.resources.lookup("RightExpanded") as! WinUI.Storyboard,
            rightCollapsedStoryboard: loaded.resources.lookup("RightCollapsed") as! WinUI.Storyboard,
            overlayTopShownStoryboard: loaded.resources.lookup("OverlayTopShown") as! WinUI.Storyboard,
            overlayTopHiddenStoryboard: loaded.resources.lookup("OverlayTopHidden") as! WinUI.Storyboard,
            overlayBottomShownStoryboard: loaded.resources.lookup("OverlayBottomShown") as! WinUI.Storyboard,
            overlayBottomHiddenStoryboard: loaded.resources.lookup("OverlayBottomHidden") as! WinUI.Storyboard,
        )
        self.preferenceKey = preferenceKey
        super.init()

        children.append(ui.shellRoot)
        ui.leftSplitter.protectedCursor = try? InputSystemCursor.create(.sizeWestEast)
        ui.rightSplitter.protectedCursor = try? InputSystemCursor.create(.sizeWestEast)
        setupSplitterEvents()
        setupOverlayEvents()
        setupChromeControlEvents()
        updateChromeControls()
        applyStoredPreferences()
    }

    // MARK: - 公开区域接口

    /// 返回指定区域当前是否展开。
    public func paneState(_ edge: ViewerEdge) -> ViewerPaneState {
        pane(edge).state
    }

    /// 返回指定区域当前固定尺寸；`nil` 表示由内容自动决定。
    public func paneLength(_ edge: ViewerEdge) -> Double? {
        pane(edge).length
    }

    /// 返回指定区域当前内容。
    public func paneContent(_ edge: ViewerEdge) -> WinUI.UIElement? {
        host(edge).content as? WinUI.UIElement
    }

    /// 设置指定区域内容。
    public func setPaneContent(_ content: WinUI.UIElement?, for edge: ViewerEdge) {
        host(edge).content = content
        applyPaneLayout(edge)
        updateChromeControls()
    }

    /// 一次性设置区域内容、展开状态和尺寸。
    public func configurePane(_ edge: ViewerEdge, with configuration: ViewerPaneConfiguration) {
        setPaneContent(configuration.content, for: edge)
        setPaneLength(configuration.length, for: edge)
        setPaneState(configuration.state, for: edge)
    }

    /// 设置区域展开状态，并触发布局、动画和状态变化回调。
    public func setPaneState(_ state: ViewerPaneState, for edge: ViewerEdge) {
        guard paneState(edge) != state else { return }
        updatePane(edge) { $0.state = state }
        applyPaneLayout(edge)
        runPaneAnimation(edge, state: state)
        updateChromeControls()
        saveStoredPreferences()
        onPaneStateChanged?(edge, state)
    }

    /// 切换区域展开状态。
    public func togglePane(_ edge: ViewerEdge) {
        setPaneState(paneState(edge) == .expanded ? .collapsed : .expanded, for: edge)
    }

    /// 设置区域固定尺寸；传入 `nil` 时由内容自动决定尺寸。
    public func setPaneLength(_ length: Double?, for edge: ViewerEdge) {
        updatePane(edge) { pane in
            pane.length = length.map { pane.constrained($0) }
        }
        applyPaneLayout(edge)
    }

    /// 设置左右区域可拖拽调整的最小和最大宽度。
    public func setPaneLengthRange(minimum: Double, maximum: Double, for edge: ViewerEdge) {
        guard edge == .left || edge == .right else { return }
        updatePane(edge) { pane in
            pane.minimumLength = max(0, minimum)
            pane.maximumLength = max(pane.minimumLength, maximum)
            if let length = pane.length {
                pane.length = pane.constrained(length)
            }
        }
        applyPaneLayout(edge)
    }

    /// 切换上下栏固定或悬浮模式。
    public func setChromeMode(_ mode: ViewerChromeMode) {
        guard overlay.mode != mode else { return }

        let top = activeChromeHost(.top).content as? WinUI.UIElement
        let bottom = activeChromeHost(.bottom).content as? WinUI.UIElement
        ui.topHost.content = nil
        ui.bottomHost.content = nil
        ui.overlayTopHost.content = nil
        ui.overlayBottomHost.content = nil

        overlay.mode = mode
        overlay.isVisible = true
        activeChromeHost(.top).content = top
        activeChromeHost(.bottom).content = bottom
        applyPaneLayout(.top)
        applyPaneLayout(.bottom)
        updateOverlayVisibility()

        if mode == .overlay {
            scheduleOverlayHide()
        } else {
            overlay.hideTask?.cancel()
            overlay.hideTask = nil
        }
        updateChromeControls()
        saveStoredPreferences()
        onChromeModeChanged?(mode)
    }

    // MARK: - 内部状态访问

    /// 返回指定区域的完整运行状态。
    private func pane(_ edge: ViewerEdge) -> PaneRuntimeState {
        panes[edge] ?? PaneRuntimeState()
    }

    /// 集中修改指定区域状态，避免多个属性分别更新后产生不一致。
    private func updatePane(_ edge: ViewerEdge, _ update: (inout PaneRuntimeState) -> Void) {
        var value = pane(edge)
        update(&value)
        panes[edge] = value
    }

    /// 返回指定区域当前实际承载内容的 ContentControl。
    private func host(_ edge: ViewerEdge) -> WinUI.ContentControl {
        switch edge {
        case .top, .bottom: activeChromeHost(edge)
        case .left: ui.leftHost
        case .right: ui.rightHost
        }
    }

    /// 返回指定区域是否有调用方提供的内容。没有内容的区域即使状态为 expanded 也不会占位。
    private func hasPaneContent(_ edge: ViewerEdge) -> Bool {
        paneContent(edge) != nil
    }

    /// 根据固定或悬浮模式，返回顶部或底部当前活动的内容宿主。
    private func activeChromeHost(_ edge: ViewerEdge) -> WinUI.ContentControl {
        switch (edge, overlay.mode) {
        case (.top, .docked): ui.topHost
        case (.top, .overlay): ui.overlayTopHost
        case (.bottom, .docked): ui.bottomHost
        case (.bottom, .overlay): ui.overlayBottomHost
        default: fatalError("Only top and bottom edges have chrome hosts")
        }
    }

    // MARK: - 布局更新

    /// 根据区域类型分发到上下栏或左右栏布局更新逻辑。
    private func applyPaneLayout(_ edge: ViewerEdge) {
        switch edge {
        case .top, .bottom: applyChromeLayout(edge)
        case .left, .right: applySideLayout(edge)
        }
    }

    /// 更新顶部或底部区域在固定/悬浮模式下的布局。
    private func applyChromeLayout(_ edge: ViewerEdge) {
        let runtime = pane(edge)
        let expanded = runtime.state == .expanded && hasPaneContent(edge)
        let dockedLength = WinUI.GridLength(
            value: expanded ? (runtime.length ?? 1) : 0,
            gridUnitType: expanded && runtime.length == nil ? .auto : .pixel
        )
        if edge == .top {
            ui.topRow.height =
                overlay.mode == .docked
                ? dockedLength : WinUI.GridLength(value: 0, gridUnitType: .pixel)
            ui.topHost.visibility = overlay.mode == .docked && expanded ? .visible : .collapsed
        } else {
            ui.bottomRow.height =
                overlay.mode == .docked
                ? dockedLength : WinUI.GridLength(value: 0, gridUnitType: .pixel)
            ui.bottomHost.visibility = overlay.mode == .docked && expanded ? .visible : .collapsed
        }
        updateOverlayVisibility()
    }

    /// 更新左右区域、分隔条宽度和可见性。
    private func applySideLayout(_ edge: ViewerEdge) {
        let runtime = pane(edge)
        let expanded = runtime.state == .expanded && hasPaneContent(edge)
        let paneLength = WinUI.GridLength(
            value: expanded ? (runtime.length ?? 1) : 0,
            gridUnitType: expanded && runtime.length == nil ? .auto : .pixel
        )
        let splitLength = WinUI.GridLength(value: 0, gridUnitType: .pixel)
        if edge == .left {
            ui.leftColumn.width = paneLength
            ui.leftSplitterColumn.width = splitLength
            ui.leftHost.visibility = expanded ? .visible : .collapsed
            ui.leftSplitter.visibility = expanded ? .visible : .collapsed
        } else {
            ui.rightColumn.width = paneLength
            ui.rightSplitterColumn.width = splitLength
            ui.rightHost.visibility = expanded ? .visible : .collapsed
            ui.rightSplitter.visibility = expanded ? .visible : .collapsed
        }
    }

    // MARK: - 内置 Chrome 控件

    /// 注册 Viewer 通用按钮事件。按钮只处理布局状态，不承载业务动作。
    private func setupChromeControlEvents() {
        for button in [ui.viewerLeftPaneButton, ui.overlayViewerLeftPaneButton] {
            button.click.addHandler { [weak self] _, _ in self?.togglePane(.left) }
        }
        for button in [ui.viewerRightPaneButton, ui.overlayViewerRightPaneButton] {
            button.click.addHandler { [weak self] _, _ in self?.togglePane(.right) }
        }
        for button in [ui.viewerChromeModeButton, ui.overlayViewerChromeModeButton] {
            button.click.addHandler { [weak self] _, _ in
                guard let self else { return }
                self.setChromeMode(self.chromeMode == .docked ? .overlay : .docked)
            }
        }
        for button in [ui.viewerFullscreenButton, ui.overlayViewerFullscreenButton] {
            button.click.addHandler { [weak self] _, _ in self?.onFullscreenRequested?() }
        }
    }

    /// 根据区域内容、展开状态和 Chrome 模式刷新内置按钮。
    private func updateChromeControls() {
        let leftVisible = showsLeftPaneButton && hasPaneContent(.left)
        let rightVisible = showsRightPaneButton && hasPaneContent(.right)
        let chromeVisible = showsChromeModeButton && hasPaneContent(.top)
        let fullscreenVisible =
            showsFullscreenButton && onFullscreenRequested != nil && hasPaneContent(.top)

        for button in [ui.viewerLeftPaneButton, ui.overlayViewerLeftPaneButton] {
            button.visibility = leftVisible ? .visible : .collapsed
        }
        for button in [ui.viewerRightPaneButton, ui.overlayViewerRightPaneButton] {
            button.visibility = rightVisible ? .visible : .collapsed
        }
        for button in [ui.viewerChromeModeButton, ui.overlayViewerChromeModeButton] {
            button.visibility = chromeVisible ? .visible : .collapsed
        }
        for button in [ui.viewerFullscreenButton, ui.overlayViewerFullscreenButton] {
            button.visibility = fullscreenVisible ? .visible : .collapsed
        }

        let leftGlyph = paneState(.left) == .expanded ? "\u{E76B}" : "\u{E76C}"
        let rightGlyph = paneState(.right) == .expanded ? "\u{E76C}" : "\u{E76B}"
        let chromeGlyph = chromeMode == .docked ? "\u{E7F8}" : "\u{E7F7}"
        ui.viewerLeftPaneIcon.glyph = leftGlyph
        ui.overlayViewerLeftPaneIcon.glyph = leftGlyph
        ui.viewerRightPaneIcon.glyph = rightGlyph
        ui.overlayViewerRightPaneIcon.glyph = rightGlyph
        ui.viewerFullscreenIcon.glyph = "\u{E740}"
        ui.overlayViewerFullscreenIcon.glyph = "\u{E740}"
        ui.viewerChromeModeIcon.glyph = chromeGlyph
        ui.overlayViewerChromeModeIcon.glyph = chromeGlyph
    }

    // MARK: - 通用偏好持久化

    /// 根据 `preferenceKey` 恢复 Viewer 通用布局偏好。
    private func applyStoredPreferences() {
        guard let entry = viewerPreferences.entries[preferenceKey] else { return }
        isApplyingStoredPreferences = true
        defer { isApplyingStoredPreferences = false }

        if let leftWidth = entry.leftPaneWidth { setPaneLength(leftWidth, for: .left) }
        if let rightWidth = entry.rightPaneWidth { setPaneLength(rightWidth, for: .right) }
        setPaneState(entry.leftPaneCollapsed ? .collapsed : .expanded, for: .left)
        setPaneState(entry.rightPaneCollapsed ? .collapsed : .expanded, for: .right)
        setChromeMode(entry.chromeModeRaw == "overlay" ? .overlay : .docked)
        updateChromeControls()
    }

    /// 保存 Viewer 通用布局偏好；没有设置 key 时 Viewer 保持无状态。
    private func saveStoredPreferences() {
        guard !isApplyingStoredPreferences else { return }

        let entry = ViewerPreferenceEntry(
            leftPaneWidth: paneLength(.left),
            rightPaneWidth: paneLength(.right),
            leftPaneCollapsed: paneState(.left) == .collapsed,
            rightPaneCollapsed: paneState(.right) == .collapsed,
            chromeModeRaw: chromeMode == .overlay ? "overlay" : "docked"
        )
        viewerPreferences.entries[preferenceKey] = entry
        App.context.preferences.save(viewerPreferences)
    }

    // MARK: - 左右栏拖拽

    /// 注册左右分隔条的拖拽事件。
    private func setupSplitterEvents() {
        bindSplitter(ui.leftSplitter, edge: .left)
        bindSplitter(ui.rightSplitter, edge: .right)
    }

    /// 为单个左右分隔条绑定按下、移动、释放和捕获丢失事件。
    private func bindSplitter(_ splitter: WinUI.Border, edge: ViewerEdge) {
        splitter.pointerPressed.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            self.resizingEdge = edge
            _ = try? splitter.capturePointer(args.pointer)
            args.handled = true
        }
        splitter.pointerMoved.addHandler { [weak self] _, args in
            guard let self, self.resizingEdge == edge, let args else { return }
            let point = try? args.getCurrentPoint(self)
            let rawLength =
                edge == .left
                ? Double(point?.position.x ?? 0)
                : Double(self.actualWidth) - Double(point?.position.x ?? 0)
            let length = self.pane(edge).constrained(rawLength)
            self.setPaneLength(length, for: edge)
            self.onPaneLengthChanged?(edge, length)
            args.handled = true
        }
        splitter.pointerReleased.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            self.resizingEdge = nil
            try? splitter.releasePointerCapture(args.pointer)
            if let length = self.paneLength(edge) {
                self.saveStoredPreferences()
                self.onPaneResizeCompleted?(edge, length)
            }
            args.handled = true
        }
        splitter.pointerCaptureLost.addHandler { [weak self] _, _ in
            self?.resizingEdge = nil
        }
    }

    // MARK: - 悬浮栏交互

    /// 注册上下栏和上下热区的鼠标进入、移动及离开事件。
    private func setupOverlayEvents() {
        bindOverlayRegion(ui.topHotzone, region: .topHotzone, tracksMovement: true)
        bindOverlayRegion(ui.bottomHotzone, region: .bottomHotzone, tracksMovement: true)
        bindOverlayRegion(ui.overlayTopContainer, region: .topChrome)
        bindOverlayRegion(ui.overlayBottomContainer, region: .bottomChrome)
    }

    /// 为单个悬浮区域绑定鼠标事件，并按需持续跟踪鼠标移动。
    private func bindOverlayRegion(
        _ element: WinUI.UIElement,
        region: OverlayPointerRegion,
        tracksMovement: Bool = false
    ) {
        element.pointerEntered.addHandler { [weak self] _, _ in
            self?.setOverlayPointer(region, inside: true)
        }
        if tracksMovement {
            element.pointerMoved.addHandler { [weak self] _, _ in
                self?.revealOverlayChrome()
            }
        }
        element.pointerExited.addHandler { [weak self] _, _ in
            self?.setOverlayPointer(region, inside: false)
        }
    }

    /// 更新鼠标当前所在的悬浮区域，并决定显示或延迟隐藏上下栏。
    private func setOverlayPointer(_ region: OverlayPointerRegion, inside: Bool) {
        if inside {
            overlay.pointerRegions.insert(region)
            revealOverlayChrome()
        } else {
            overlay.pointerRegions.remove(region)
            scheduleOverlayHide()
        }
    }

    /// 立即显示悬浮上下栏，并取消尚未执行的隐藏任务。
    private func revealOverlayChrome() {
        guard overlay.mode == .overlay else { return }
        overlay.hideTask?.cancel()
        overlay.hideTask = nil
        guard !overlay.isVisible else { return }
        overlay.isVisible = true
        updateOverlayVisibility()
    }

    /// 在指定延迟后隐藏悬浮上下栏；鼠标仍位于相关区域时取消隐藏。
    private func scheduleOverlayHide() {
        guard overlay.mode == .overlay else { return }
        overlay.hideTask?.cancel()
        overlay.hideTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.overlayHideDelayNanoseconds)
            guard !Task.isCancelled, self.overlay.pointerRegions.isEmpty, self.overlay.isVisible
            else { return }
            self.overlay.isVisible = false
            self.overlay.hideTask = nil
            self.updateOverlayVisibility()
        }
    }

    /// 根据悬浮模式、区域状态和临时显示状态更新上下栏与热区。
    private func updateOverlayVisibility() {
        let isOverlay = overlay.mode == .overlay
        let topAvailable = paneState(.top) == .expanded && hasPaneContent(.top)
        let bottomAvailable = paneState(.bottom) == .expanded && hasPaneContent(.bottom)
        let showTop = isOverlay && overlay.isVisible && topAvailable
        let showBottom = isOverlay && overlay.isVisible && bottomAvailable

        ui.overlayTopContainer.visibility = isOverlay && topAvailable ? .visible : .collapsed
        ui.overlayBottomContainer.visibility = isOverlay && bottomAvailable ? .visible : .collapsed
        ui.overlayTopContainer.isHitTestVisible = showTop
        ui.overlayBottomContainer.isHitTestVisible = showBottom
        ui.topHotzone.visibility = isOverlay && !overlay.isVisible && topAvailable ? .visible : .collapsed
        ui.bottomHotzone.visibility = isOverlay && !overlay.isVisible && bottomAvailable ? .visible : .collapsed

        showTop ? try? ui.overlayTopShownStoryboard.begin() : try? ui.overlayTopHiddenStoryboard.begin()
        showBottom ? try? ui.overlayBottomShownStoryboard.begin() : try? ui.overlayBottomHiddenStoryboard.begin()
    }

    // MARK: - XAML 动画

    /// 根据左右栏展开状态选择并播放对应动画。
    private func runPaneAnimation(_ edge: ViewerEdge, state: ViewerPaneState) {
        switch (edge, state) {
        case (.left, .expanded): try? ui.leftExpandedStoryboard.begin()
        case (.left, .collapsed): try? ui.leftCollapsedStoryboard.begin()
        case (.right, .expanded): try? ui.rightExpandedStoryboard.begin()
        case (.right, .collapsed): try? ui.rightCollapsedStoryboard.begin()
        case (.top, _), (.bottom, _): return
        }
    }
}

private var xamlUI: String {
    """
    <Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
        <Grid.Resources>
            <ResourceDictionary>
                <ResourceDictionary.ThemeDictionaries>
                    <ResourceDictionary x:Key="Light">
                        <SolidColorBrush x:Key="ViewerChromeButtonBackgroundPointerOver" Color="#10000000" />
                        <SolidColorBrush x:Key="ViewerChromeButtonBackgroundPressed" Color="#18000000" />
                    </ResourceDictionary>
                    <ResourceDictionary x:Key="Dark">
                        <SolidColorBrush x:Key="ViewerChromeButtonBackgroundPointerOver" Color="#18FFFFFF" />
                        <SolidColorBrush x:Key="ViewerChromeButtonBackgroundPressed" Color="#24FFFFFF" />
                    </ResourceDictionary>
                </ResourceDictionary.ThemeDictionaries>

                <Style x:Key="ViewerChromeButtonStyle" TargetType="Button">
                    <Setter Property="Width" Value="34" />
                    <Setter Property="Height" Value="32" />
                    <Setter Property="Padding" Value="6" />
                    <Setter Property="Margin" Value="4,0" />
                    <Setter Property="Background" Value="Transparent" />
                    <Setter Property="BorderThickness" Value="0" />
                    <Setter Property="CornerRadius" Value="4" />
                    <Setter Property="HorizontalContentAlignment" Value="Center" />
                    <Setter Property="VerticalContentAlignment" Value="Center" />
                </Style>

                <Style x:Key="ViewerOverlayChromeButtonStyle" TargetType="Button" BasedOn="{StaticResource ViewerChromeButtonStyle}" />

                <Storyboard x:Name="LeftExpanded">
                    <DoubleAnimation Storyboard.TargetName="LeftHost" Storyboard.TargetProperty="Opacity"
                                    To="1" Duration="0:0:0.16" />
                    <DoubleAnimation Storyboard.TargetName="LeftHostTransform" Storyboard.TargetProperty="TranslateX"
                                    To="0" Duration="0:0:0.16" />
                </Storyboard>
                <Storyboard x:Name="LeftCollapsed">
                    <DoubleAnimation Storyboard.TargetName="LeftHost" Storyboard.TargetProperty="Opacity"
                                    To="0" Duration="0:0:0.16" />
                    <DoubleAnimation Storyboard.TargetName="LeftHostTransform" Storyboard.TargetProperty="TranslateX"
                                    To="-12" Duration="0:0:0.16" />
                </Storyboard>
                <Storyboard x:Name="RightExpanded">
                    <DoubleAnimation Storyboard.TargetName="RightHost" Storyboard.TargetProperty="Opacity"
                                    To="1" Duration="0:0:0.16" />
                    <DoubleAnimation Storyboard.TargetName="RightHostTransform" Storyboard.TargetProperty="TranslateX"
                                    To="0" Duration="0:0:0.16" />
                </Storyboard>
                <Storyboard x:Name="RightCollapsed">
                    <DoubleAnimation Storyboard.TargetName="RightHost" Storyboard.TargetProperty="Opacity"
                                    To="0" Duration="0:0:0.16" />
                    <DoubleAnimation Storyboard.TargetName="RightHostTransform" Storyboard.TargetProperty="TranslateX"
                                    To="12" Duration="0:0:0.16" />
                </Storyboard>
                <Storyboard x:Name="OverlayTopShown">
                    <DoubleAnimation Storyboard.TargetName="OverlayTopContainer" Storyboard.TargetProperty="Opacity"
                                    To="1" Duration="0:0:0.16" />
                    <DoubleAnimation Storyboard.TargetName="OverlayTopTransform" Storyboard.TargetProperty="TranslateY"
                                    To="0" Duration="0:0:0.16" />
                </Storyboard>
                <Storyboard x:Name="OverlayTopHidden">
                    <DoubleAnimation Storyboard.TargetName="OverlayTopContainer" Storyboard.TargetProperty="Opacity"
                                    To="0" Duration="0:0:0.16" />
                    <DoubleAnimation Storyboard.TargetName="OverlayTopTransform" Storyboard.TargetProperty="TranslateY"
                                    To="-10" Duration="0:0:0.16" />
                </Storyboard>
                <Storyboard x:Name="OverlayBottomShown">
                    <DoubleAnimation Storyboard.TargetName="OverlayBottomContainer" Storyboard.TargetProperty="Opacity"
                                    To="1" Duration="0:0:0.16" />
                    <DoubleAnimation Storyboard.TargetName="OverlayBottomTransform" Storyboard.TargetProperty="TranslateY"
                                    To="0" Duration="0:0:0.16" />
                </Storyboard>
                <Storyboard x:Name="OverlayBottomHidden">
                    <DoubleAnimation Storyboard.TargetName="OverlayBottomContainer" Storyboard.TargetProperty="Opacity"
                                    To="0" Duration="0:0:0.16" />
                    <DoubleAnimation Storyboard.TargetName="OverlayBottomTransform" Storyboard.TargetProperty="TranslateY"
                                    To="10" Duration="0:0:0.16" />
                </Storyboard>
            </ResourceDictionary>
        </Grid.Resources>
        <Grid.RowDefinitions>
            <RowDefinition x:Name="TopRow" Height="0" />
            <RowDefinition Height="*" />
            <RowDefinition x:Name="BottomRow" Height="0" />
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
            <ColumnDefinition x:Name="LeftColumn" Width="0" />
            <ColumnDefinition x:Name="LeftSplitterColumn" Width="0" />
            <ColumnDefinition Width="*" />
            <ColumnDefinition x:Name="RightSplitterColumn" Width="0" />
            <ColumnDefinition x:Name="RightColumn" Width="0" />
        </Grid.ColumnDefinitions>

        <ContentControl x:Name="CenterContentHost" Grid.Row="1" Grid.Column="2"
                        HorizontalContentAlignment="Stretch" VerticalContentAlignment="Stretch" />
        <ContentControl x:Name="CenterOverlayHost" Grid.Row="1" Grid.Column="2" IsHitTestVisible="False"
                        HorizontalContentAlignment="Stretch" VerticalContentAlignment="Stretch" />
        <Grid x:Name="TopChromeRoot" Grid.Row="0" Grid.Column="2"
            Background="{ThemeResource SolidBackgroundFillColorBaseBrush}">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto" />
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="Auto" />
                <ColumnDefinition Width="Auto" />
                <ColumnDefinition Width="Auto" />
            </Grid.ColumnDefinitions>
            <Button x:Name="ViewerLeftPaneButton" Grid.Column="0" Style="{StaticResource ViewerChromeButtonStyle}" Visibility="Collapsed" ToolTipService.ToolTip="{x:Tr ViewerLeftPane}">
                <FontIcon x:Name="ViewerLeftPaneIcon" Glyph="&#xE76B;" FontSize="14" />
            </Button>
            <ContentControl x:Name="TopHost" Grid.Column="1"
                            HorizontalContentAlignment="Stretch" VerticalContentAlignment="Stretch" />
            <Button x:Name="ViewerFullscreenButton" Grid.Column="2" Style="{StaticResource ViewerChromeButtonStyle}" Visibility="Collapsed" ToolTipService.ToolTip="{x:Tr ViewerFullscreen}">
                <FontIcon x:Name="ViewerFullscreenIcon" Glyph="&#xE740;" FontSize="14" />
            </Button>
            <Button x:Name="ViewerChromeModeButton" Grid.Column="3" Style="{StaticResource ViewerChromeButtonStyle}" Visibility="Collapsed" ToolTipService.ToolTip="{x:Tr ViewerChromeMode}">
                <FontIcon x:Name="ViewerChromeModeIcon" Glyph="&#xE7F8;" FontSize="14" />
            </Button>
            <Button x:Name="ViewerRightPaneButton" Grid.Column="4" Style="{StaticResource ViewerChromeButtonStyle}" Visibility="Collapsed" ToolTipService.ToolTip="{x:Tr ViewerRightPane}">
                <FontIcon x:Name="ViewerRightPaneIcon" Glyph="&#xE76C;" FontSize="14" />
            </Button>
        </Grid>
        <ContentControl x:Name="BottomHost" Grid.Row="2" Grid.Column="2"
                        HorizontalContentAlignment="Stretch" VerticalContentAlignment="Stretch" />
        <Border x:Name="OverlayTopContainer" Grid.Row="0" Grid.RowSpan="3" Grid.Column="2"
                VerticalAlignment="Top" Background="{ThemeResource SolidBackgroundFillColorBaseBrush}"
                Visibility="Collapsed" Canvas.ZIndex="100">
            <Border.RenderTransform>
                <CompositeTransform x:Name="OverlayTopTransform" />
            </Border.RenderTransform>
            <Grid x:Name="OverlayTopChromeRoot" Background="{ThemeResource SolidBackgroundFillColorBaseBrush}">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto" />
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                    <ColumnDefinition Width="Auto" />
                    <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>
                <Button x:Name="OverlayViewerLeftPaneButton" Grid.Column="0" Style="{StaticResource ViewerOverlayChromeButtonStyle}" Visibility="Collapsed" ToolTipService.ToolTip="{x:Tr ViewerLeftPane}">
                    <FontIcon x:Name="OverlayViewerLeftPaneIcon" Glyph="&#xE76B;" FontSize="14" />
                </Button>
                <ContentControl x:Name="OverlayTopHost" Grid.Column="1" HorizontalContentAlignment="Stretch"
                                VerticalContentAlignment="Stretch" />
                <Button x:Name="OverlayViewerFullscreenButton" Grid.Column="2" Style="{StaticResource ViewerOverlayChromeButtonStyle}" Visibility="Collapsed" ToolTipService.ToolTip="{x:Tr ViewerFullscreen}">
                    <FontIcon x:Name="OverlayViewerFullscreenIcon" Glyph="&#xE740;" FontSize="14" />
                </Button>
                <Button x:Name="OverlayViewerChromeModeButton" Grid.Column="3" Style="{StaticResource ViewerOverlayChromeButtonStyle}" Visibility="Collapsed" ToolTipService.ToolTip="{x:Tr ViewerChromeMode}">
                    <FontIcon x:Name="OverlayViewerChromeModeIcon" Glyph="&#xE7F8;" FontSize="14" />
                </Button>
                <Button x:Name="OverlayViewerRightPaneButton" Grid.Column="4" Style="{StaticResource ViewerOverlayChromeButtonStyle}" Visibility="Collapsed" ToolTipService.ToolTip="{x:Tr ViewerRightPane}">
                    <FontIcon x:Name="OverlayViewerRightPaneIcon" Glyph="&#xE76C;" FontSize="14" />
                </Button>
            </Grid>
        </Border>
        <Border x:Name="OverlayBottomContainer" Grid.Row="0" Grid.RowSpan="3" Grid.Column="2"
                VerticalAlignment="Bottom" Background="{ThemeResource LayerFillColorDefaultBrush}"
                Visibility="Collapsed" Canvas.ZIndex="100">
            <Border.RenderTransform>
                <CompositeTransform x:Name="OverlayBottomTransform" />
            </Border.RenderTransform>
            <ContentControl x:Name="OverlayBottomHost" HorizontalContentAlignment="Stretch"
                            VerticalContentAlignment="Stretch" />
        </Border>
        <ContentControl x:Name="LeftHost" Grid.Row="0" Grid.RowSpan="3" Grid.Column="0"
                        HorizontalContentAlignment="Stretch" VerticalContentAlignment="Stretch"
                        BorderBrush="{ThemeResource DividerStrokeColorDefaultBrush}" BorderThickness="0,0,1,0">
            <ContentControl.RenderTransform>
                <CompositeTransform x:Name="LeftHostTransform" />
            </ContentControl.RenderTransform>
        </ContentControl>
        <ContentControl x:Name="RightHost" Grid.Row="0" Grid.RowSpan="3" Grid.Column="4"
                        HorizontalContentAlignment="Stretch" VerticalContentAlignment="Stretch"
                        BorderBrush="{ThemeResource DividerStrokeColorDefaultBrush}" BorderThickness="1,0,0,0">
            <ContentControl.RenderTransform>
                <CompositeTransform x:Name="RightHostTransform" />
            </ContentControl.RenderTransform>
        </ContentControl>

        <Border x:Name="LeftSplitter" Grid.Row="0" Grid.RowSpan="3" Grid.Column="0"
                Width="6" Margin="0,0,-3,0" HorizontalAlignment="Right" Background="Transparent"
                Visibility="Collapsed" Canvas.ZIndex="102" />
        <Border x:Name="RightSplitter" Grid.Row="0" Grid.RowSpan="3" Grid.Column="4"
                Width="6" Margin="-3,0,0,0" HorizontalAlignment="Left" Background="Transparent"
                Visibility="Collapsed" Canvas.ZIndex="102" />
        <Border x:Name="TopHotzone" Grid.Row="0" Grid.RowSpan="3" Grid.Column="2"
                Width="176" Height="16" HorizontalAlignment="Center" VerticalAlignment="Top"
                Background="Transparent" Visibility="Collapsed" Canvas.ZIndex="101">
            <Border Width="88" Height="14" VerticalAlignment="Top"
                Background="#B0000000" CornerRadius="0,0,10,10">
            <Border Width="42" Height="3" VerticalAlignment="Center"
                Background="#F2FFFFFF" CornerRadius="2" />
            </Border>
        </Border>
        <Border x:Name="BottomHotzone" Grid.Row="0" Grid.RowSpan="3" Grid.Column="2"
                Width="176" Height="16" HorizontalAlignment="Center" VerticalAlignment="Bottom"
                Background="Transparent" Visibility="Collapsed" Canvas.ZIndex="101">
            <Border Width="88" Height="14" VerticalAlignment="Bottom"
                Background="#B0000000" CornerRadius="10,10,0,0">
            <Border Width="42" Height="3" VerticalAlignment="Center"
                Background="#F2FFFFFF" CornerRadius="2" />
            </Border>
        </Border>
    </Grid>
    """
}
