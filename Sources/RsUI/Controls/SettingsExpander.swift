import UWP
import WinUI
import WindowsFoundation

public class SettingsExpander: StackPanel {

    // MARK: - Public properties

    public var expanded: (() -> Void)?
    public var collapsed: (() -> Void)?

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

    private var items: [SettingsCard] = []

    // MARK: - Init

    public init(
        headerIconGlyph: String,
        header: String,
        description: String? = nil,
        content: FrameworkElement? = nil,
        items: [SettingsCard] = []
    ) {
        super.init()
        self.items = items
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
    public convenience init(_ headerIconPath: String, _ header: String, _ description: String? = nil, _ contentText: String? = nil, _ items: [SettingsCard] = []) {
        self.init(headerIconPath: headerIconPath, header: header, description: description, contentText: contentText, items: items)
    }

    public init(
        headerIconPath: String,
        header: String,
        description: String? = nil,
        contentText: String? = nil,
        items: [SettingsCard] = []
    ) {
        super.init()
        self.items = items
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
        self.items = items
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
        let isDark = App.context.theme.isDark

        headerCard.isClickEnabled = true
        headerCard.suppressCardStyling()
        headerCard.isActionIconVisible = true
        headerCard.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.isExpanded = !self.isExpanded
        }

        expandedHost.renderTransform = expandedTransform
        buildExpandedContent(isDark: isDark)

        let cardStack = WinUI.StackPanel()
        cardStack.orientation = .vertical
        cardStack.spacing = 0
        cardStack.children.append(headerCard)
        cardStack.children.append(expandedHost)

        let outerCard = WinUI.Border()
        outerCard.cornerRadius = WinUI.CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
        outerCard.background = cardBackgroundBrush(isDark: isDark)
        outerCard.borderBrush = cardBorderBrush(isDark: isDark)
        outerCard.borderThickness = WinUI.Thickness(left: 1, top: 1, right: 1, bottom: 1)
        outerCard.child = cardStack

        self.children.append(outerCard)
    }

    private func buildExpandedContent(isDark: Bool) {
        // Clear existing children (keep transform)
        while expandedHost.children.count > 0 {
            expandedHost.children.removeAt(0)
        }

        // ItemsHeader
        if let header = itemsHeader {
            expandedHost.children.append(header)
        }

        // Items
        let effectiveItems = itemsSource ?? items
        for item in effectiveItems {
            item.suppressCardStyling()
            item.applyExpanderItemPadding()
            // Top border only (0,1,0,0) to match WCTK item separator style
            item.cardBorder.borderThickness = WinUI.Thickness(left: 0, top: 1, right: 0, bottom: 0)
            item.cardBorder.borderBrush = dividerBrush(isDark: isDark)
            expandedHost.children.append(item)
        }

        // ItemsFooter
        if let footer = itemsFooter {
            expandedHost.children.append(footer)
        }
    }

    private func rebuildItems() {
        let isDark = App.context.theme.isDark
        buildExpandedContent(isDark: isDark)
    }

    // MARK: - Animation

    private func runExpandCollapseAnimation(expanding: Bool) {
        guard !isAnimating else { return }
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
                self.expanded?()
            } else {
                self.collapsed?()
            }
        }

        expanding ? chevron.expand() : chevron.collapse()
        try? storyboard.begin()
    }

    private func makeDuration(milliseconds: Int64) -> WinUI.Duration {
        WinUI.Duration(
            timeSpan: WindowsFoundation.TimeSpan(duration: milliseconds * 10_000),
            type: .timeSpan
        )
    }
}
