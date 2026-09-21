import WinUI
import WindowsFoundation

public class SettingsExpander: StackPanel {

    // MARK: - Public properties

    public var onExpanded: (() -> Void)?
    public var onCollapsed: (() -> Void)?

    public var itemsHeader: WinUI.UIElement? {
        didSet { rebuildItems() }
    }
    public var itemsFooter: WinUI.UIElement? {
        didSet { rebuildItems() }
    }
    public var itemsSource: [SettingsCard]? {
        didSet { rebuildItems() }
    }

    public var isExpanded: Bool = false {
        didSet {
            guard isExpanded != oldValue else { return }
            runExpandCollapseAnimation(expanding: isExpanded)
        }
    }

    // MARK: - Private state

    private var isAnimating = false
    // 动画进行中到达的展开/收起请求暂存于此，当前动画完成后接着跑，
    // 保证 isExpanded 与视觉状态最终一致（而不是静默丢弃请求导致失步）。
    private var pendingExpanded: Bool?
    private var outerCard: WinUI.Grid?
    private let chevron = ChevronIcon(glyph: "\u{E70D}", expandAngle: 180)
    private let expandedHost: WinUI.StackPanel = {
        let host = WinUI.StackPanel()
        host.visibility = .collapsed
        host.opacity = 0
        return host
    }()
    private let expandedTransform: WinUI.CompositeTransform = {
        let t = WinUI.CompositeTransform()
        t.translateY = -8
        return t
    }()

    // MARK: - Init

    public init(
        headerIconGlyph: String,
        header: String,
        description: String? = nil,
        content: FrameworkElement? = nil,
        items: [SettingsCard] = []
    ) {
        super.init()
        itemsSource = items
        setup(
            headerCard: SettingsCard(
                headerIconGlyph: headerIconGlyph,
                header: header,
                description: description,
                content: content,
                actionIcon: chevron
            )
        )
    }

    /// Positional: iconPath, header, description, contentText, items
    public convenience init(
        _ headerIconPath: String, _ header: String, _ description: String? = nil,
        _ contentText: String? = nil, _ items: [SettingsCard] = []
    ) {
        self.init(
            headerIconPath: headerIconPath, header: header, description: description,
            contentText: contentText, items: items)
    }

    public init(
        headerIconPath: String,
        header: String,
        description: String? = nil,
        contentText: String? = nil,
        items: [SettingsCard] = []
    ) {
        super.init()
        itemsSource = items
        setup(
            headerCard: SettingsCard(
                headerIconPath: headerIconPath,
                header: header,
                description: description,
                contentText: contentText,
                actionIcon: chevron
            )
        )
    }

    public init(
        header: String,
        description: FrameworkElement? = nil,
        content: FrameworkElement? = nil,
        items: [SettingsCard] = []
    ) {
        super.init()
        itemsSource = items
        setup(
            headerCard: SettingsCard(
                header: header,
                description: description,
                content: content,
                actionIcon: chevron
            )
        )
    }

    // MARK: - Setup

    private func setup(headerCard: SettingsCard) {
        headerCard.isClickEnabled = true
        headerCard.suppressCardStyling()
        headerCard.isActionIconVisible = true
        headerCard.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.isExpanded = !self.isExpanded
        }

        expandedHost.renderTransform = expandedTransform
        buildExpandedContent()

        let cardStack = WinUI.StackPanel()
        cardStack.orientation = .vertical
        cardStack.spacing = 0
        cardStack.children.append(headerCard)
        cardStack.children.append(expandedHost)

        let outerCard = WinUI.Grid()
        outerCard.cornerRadius = WinUI.CornerRadius(
            topLeft: 4, topRight: 4, bottomRight: 4, bottomLeft: 4)
        outerCard.background = fluentThemeBrush("CardBackgroundFillColorDefaultBrush")
        outerCard.borderBrush = fluentThemeBrush("CardStrokeColorDefaultBrush")
        outerCard.borderThickness = WinUI.Thickness(left: 1, top: 1, right: 1, bottom: 1)
        let backgroundTransition = WinUI.BrushTransition()
        backgroundTransition.duration = WindowsFoundation.TimeSpan(duration: 83 * 10_000)
        outerCard.backgroundTransition = backgroundTransition
        outerCard.children.append(cardStack)
        headerCard.setInteractionVisualTarget(outerCard)
        self.outerCard = outerCard

        self.children.append(outerCard)

        // setup 时一次性解析的 Fluent 画刷不跟随主题更新，主题切换后重取。
        actualThemeChanged.addHandler { [weak self] _, _ in
            self?.refreshThemeBrushes()
        }
    }

    private func refreshThemeBrushes() {
        guard let outerCard else { return }
        outerCard.background = fluentThemeBrush("CardBackgroundFillColorDefaultBrush")
        outerCard.borderBrush = fluentThemeBrush("CardStrokeColorDefaultBrush")
        for item in itemsSource ?? [] {
            item.cardRoot.borderBrush = fluentThemeBrush("DividerStrokeColorDefaultBrush")
        }
    }

    private func buildExpandedContent() {
        // Clear existing children (keep transform)
        while expandedHost.children.count > 0 {
            expandedHost.children.removeAt(0)
        }

        // ItemsHeader
        if let header = itemsHeader {
            expandedHost.children.append(header)
        }

        // Items
        let effectiveItems = itemsSource ?? []
        for item in effectiveItems {
            item.suppressCardStyling()
            item.applyExpanderItemPadding()
            // Top border only (0,1,0,0) to match WCTK item separator style
            item.cardRoot.borderThickness = WinUI.Thickness(left: 0, top: 1, right: 0, bottom: 0)
            item.cardRoot.borderBrush = fluentThemeBrush("DividerStrokeColorDefaultBrush")
            expandedHost.children.append(item)
        }

        // ItemsFooter
        if let footer = itemsFooter {
            expandedHost.children.append(footer)
        }
    }

    private func rebuildItems() {
        buildExpandedContent()
    }

    // MARK: - Animation

    private func runExpandCollapseAnimation(expanding: Bool) {
        guard !isAnimating else {
            pendingExpanded = expanding
            return
        }
        isAnimating = true

        if expanding {
            expandedHost.visibility = .visible
            expandedHost.opacity = 0
            expandedTransform.translateY = -8
        }

        let storyboard = WinUI.Storyboard()

        // Expand: 333ms with decelerate (0,0,0,1); Collapse: 167ms with accelerate (1,1,0,1)
        let duration = expanding ? 333 : 167
        let easingMode: WinUI.EasingMode = expanding ? .easeOut : .easeIn

        let opacityAnim = WinUI.DoubleAnimation()
        opacityAnim.from = expanding ? 0 : 1
        opacityAnim.to = expanding ? 1 : 0
        opacityAnim.duration = makeDuration(milliseconds: Int64(duration))

        let translateAnim = WinUI.DoubleAnimation()
        translateAnim.from = expanding ? -8 : 0
        translateAnim.to = expanding ? 0 : -8
        translateAnim.duration = makeDuration(milliseconds: Int64(duration))

        let easing = WinUI.CubicEase()
        easing.easingMode = easingMode
        opacityAnim.easingFunction = easing
        translateAnim.easingFunction = easing

        try? WinUI.Storyboard.setTarget(opacityAnim, expandedHost)
        try? WinUI.Storyboard.setTargetProperty(opacityAnim, "Opacity")
        try? WinUI.Storyboard.setTarget(translateAnim, expandedTransform)
        try? WinUI.Storyboard.setTargetProperty(translateAnim, "TranslateY")

        storyboard.children.append(opacityAnim)
        storyboard.children.append(translateAnim)

        storyboard.completed.addHandler { [weak self] _, _ in
            guard let self else { return }
            if !expanding {
                self.expandedHost.visibility = .collapsed
            }
            self.isAnimating = false
            if expanding {
                self.onExpanded?()
            } else {
                self.onCollapsed?()
            }
            if let pending = self.pendingExpanded {
                self.pendingExpanded = nil
                self.runExpandCollapseAnimation(expanding: pending)
            }
        }

        if expanding {
            chevron.expand()
        } else {
            chevron.collapse()
        }
        try? storyboard.begin()
    }

    private func makeDuration(milliseconds: Int64) -> WinUI.Duration {
        WinUI.Duration(
            timeSpan: WindowsFoundation.TimeSpan(duration: milliseconds * 10_000),
            type: .timeSpan
        )
    }
}
