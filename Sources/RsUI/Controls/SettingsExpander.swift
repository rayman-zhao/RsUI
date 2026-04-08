import UWP
import WinUI
import WindowsFoundation

public class SettingsExpander: StackPanel {
    var isExpanded = false
    var isAnimating = false

    let chevron = ChevronIcon(glyph: "\u{E70D}", expandAngle: 180)
    let expandedHost = {
        let host = WinUI.StackPanel()
        // host.orientation = .vertical
        // host.spacing = 0
        host.visibility = .collapsed
        host.opacity = 0
        return host
    }()
    let expandedTransform = {
        let transform = WinUI.CompositeTransform()
        transform.translateY = -8
        return transform
    }()

    public init(
        _ headerIconPath: String,
        _ header: String,
        _ description: String,
        _ content: String,
        _ items: [SettingsCard]
    ) {
        super.init()

        let isDark = App.context.theme.isDark
        let card = SettingsCard(headerIconPath, header, description, content, chevron)
        card.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.runExpandCollapseAnimation(expanding: !self.isExpanded)
        }
        self.children.append(card)

        expandedHost.renderTransform = expandedTransform

        for (index, item) in items.enumerated() {
            if index > 0 {
                let divider = WinUI.Border()
                divider.height = 1
                divider.margin = WinUI.Thickness(left: 16, top: 0, right: 16, bottom: 0)
                divider.background = dividerBrush(isDark: isDark)
                expandedHost.children.append(divider)
            }
            expandedHost.children.append(item)
        }
        self.children.append(expandedHost)
    }

    private func makeDuration(milliseconds: Int64) -> Duration {
        Duration(
            timeSpan: TimeSpan(duration: milliseconds * 10_000),
            type: .timeSpan
        )
    }

    private func runExpandCollapseAnimation(expanding: Bool) {
        guard !isAnimating else { return }
        isAnimating = true

        if expanding {
            expandedHost.visibility = .visible
            expandedHost.opacity = 0
            expandedTransform.translateY = -8
        }

        let storyboard = WinUI.Storyboard()

        let opacityAnimation = WinUI.DoubleAnimation()
        opacityAnimation.from = expanding ? 0 : 1
        opacityAnimation.to = expanding ? 1 : 0
        opacityAnimation.duration = makeDuration(milliseconds: 180)

        let translateAnimation = WinUI.DoubleAnimation()
        translateAnimation.from = expanding ? -8 : 0
        translateAnimation.to = expanding ? 0 : -8
        translateAnimation.duration = makeDuration(milliseconds: 180)

        let easing = WinUI.CubicEase()
        easing.easingMode = .easeOut
        opacityAnimation.easingFunction = easing
        translateAnimation.easingFunction = easing

        try? WinUI.Storyboard.setTarget(opacityAnimation, expandedHost)
        try? WinUI.Storyboard.setTargetProperty(opacityAnimation, "Opacity")

        try? WinUI.Storyboard.setTarget(translateAnimation, expandedTransform)
        try? WinUI.Storyboard.setTargetProperty(translateAnimation, "TranslateY")

        storyboard.children.append(opacityAnimation)
        storyboard.children.append(translateAnimation)

        storyboard.completed.addHandler { _, _ in
            if !expanding {
                self.expandedHost.visibility = .collapsed
            }

            self.isExpanded = expanding
            self.isAnimating = false
        }

        expanding ? chevron.expand() : chevron.collapse()

        try? storyboard.begin()
    }
}

func buildSettingsExpanderCard(
    iconGlyph: String,
    title: String,
    description: String,
    trailingText: String? = nil,
    expandedContent: WinUI.UIElement,
    showsOuterCard: Bool = true
) -> WinUI.UIElement {
    let isDark = App.context.theme.isDark

    let root = WinUI.StackPanel()
    root.orientation = .vertical
    root.spacing = 0

    let cardStack = WinUI.StackPanel()
    cardStack.orientation = .vertical
    cardStack.spacing = 0

    // ===== 头部 =====
    let headerBorder = WinUI.Border()
    headerBorder.padding = WinUI.Thickness(left: 16, top: 14, right: 16, bottom: 14)

    let headerGrid = WinUI.Grid()

    let iconColumn = WinUI.ColumnDefinition()
    iconColumn.width = WinUI.GridLength(value: 56, gridUnitType: .pixel)
    headerGrid.columnDefinitions.append(iconColumn)

    let textColumn = WinUI.ColumnDefinition()
    textColumn.width = WinUI.GridLength(value: 1, gridUnitType: .star)
    headerGrid.columnDefinitions.append(textColumn)

    let trailingColumn = WinUI.ColumnDefinition()
    trailingColumn.width = WinUI.GridLength(value: 1, gridUnitType: .auto)
    headerGrid.columnDefinitions.append(trailingColumn)

    let titleRow = WinUI.RowDefinition()
    titleRow.height = WinUI.GridLength(value: 1, gridUnitType: .auto)
    headerGrid.rowDefinitions.append(titleRow)

    let descRow = WinUI.RowDefinition()
    descRow.height = WinUI.GridLength(value: 1, gridUnitType: .auto)
    headerGrid.rowDefinitions.append(descRow)

    let iconBadge = WinUI.Border()
    iconBadge.width = 40
    iconBadge.height = 40
    iconBadge.cornerRadius = WinUI.CornerRadius(topLeft: 12, topRight: 12, bottomRight: 12, bottomLeft: 12)
    iconBadge.background = accentFillBrush(isDark: isDark)
    iconBadge.verticalAlignment = .center
    iconBadge.horizontalAlignment = .center

    let icon = WinUI.FontIcon()
    icon.glyph = iconGlyph
    icon.fontSize = 18
    icon.foreground = WinUI.SolidColorBrush(UWP.Color(a: 255, r: 255, g: 255, b: 255))
    iconBadge.child = icon

    headerGrid.children.append(iconBadge)
    try? WinUI.Grid.setColumn(iconBadge, 0)
    try? WinUI.Grid.setRow(iconBadge, 0)
    try? WinUI.Grid.setRowSpan(iconBadge, 2)

    let titleLabel = WinUI.TextBlock()
    titleLabel.text = title
    titleLabel.fontSize = 16
    titleLabel.fontWeight = UWP.FontWeights.semiBold
    titleLabel.foreground = primaryBrush(isDark: isDark)
    titleLabel.margin = WinUI.Thickness(left: 12, top: 1, right: 12, bottom: 4)
    headerGrid.children.append(titleLabel)
    try? WinUI.Grid.setColumn(titleLabel, 1)
    try? WinUI.Grid.setRow(titleLabel, 0)

    let descLabel = WinUI.TextBlock()
    descLabel.text = description
    descLabel.fontSize = 13
    descLabel.textWrapping = .wrap
    descLabel.foreground = secondaryBrush(isDark: isDark)
    descLabel.margin = WinUI.Thickness(left: 12, top: 0, right: 12, bottom: 0)
    headerGrid.children.append(descLabel)
    try? WinUI.Grid.setColumn(descLabel, 1)
    try? WinUI.Grid.setRow(descLabel, 1)

    let trailingHost = WinUI.StackPanel()
    trailingHost.orientation = .horizontal
    trailingHost.spacing = 8
    trailingHost.verticalAlignment = .center
    trailingHost.horizontalAlignment = .right

    if let trailingText, !trailingText.isEmpty {
        let trailingLabel = WinUI.TextBlock()
        trailingLabel.text = trailingText
        trailingLabel.fontSize = 13
        trailingLabel.foreground = secondaryBrush(isDark: isDark)
        trailingLabel.verticalAlignment = .center
        trailingHost.children.append(trailingLabel)
    }

    let chevron = WinUI.FontIcon()
    chevron.glyph = "\u{E70D}"
    chevron.fontSize = 12
    chevron.foreground = secondaryBrush(isDark: isDark)
    chevron.verticalAlignment = .center
    trailingHost.children.append(chevron)

    headerGrid.children.append(trailingHost)
    try? WinUI.Grid.setColumn(trailingHost, 2)
    try? WinUI.Grid.setRow(trailingHost, 0)
    try? WinUI.Grid.setRowSpan(trailingHost, 2)

    headerBorder.child = headerGrid
    cardStack.children.append(headerBorder)

    // ===== 展开区 =====
    let expandedHost = WinUI.StackPanel()
    expandedHost.orientation = .vertical
    expandedHost.spacing = 0
    expandedHost.visibility = .collapsed
    expandedHost.opacity = 0

    let expandedTransform = WinUI.CompositeTransform()
    expandedTransform.translateY = -8
    expandedHost.renderTransform = expandedTransform

    var isExpanded = false
    var isAnimating = false

    let divider = WinUI.Border()
    divider.height = 1
    divider.margin = WinUI.Thickness(left: 16, top: 0, right: 16, bottom: 0)
    divider.background = dividerBrush(isDark: isDark)
    expandedHost.children.append(divider)

    let contentContainer = WinUI.Border()
    contentContainer.padding = WinUI.Thickness(left: 16, top: 16, right: 16, bottom: 16)
    contentContainer.child = expandedContent
    expandedHost.children.append(contentContainer)

    cardStack.children.append(expandedHost)

    if showsOuterCard {
        let card = WinUI.Border()
        card.cornerRadius = WinUI.CornerRadius(topLeft: 12, topRight: 12, bottomRight: 12, bottomLeft: 12)
        card.background = cardBackgroundBrush(isDark: isDark)
        card.borderBrush = cardBorderBrush(isDark: isDark)
        card.borderThickness = WinUI.Thickness(left: 1, top: 1, right: 1, bottom: 1)
        card.child = cardStack
        root.children.append(card)
    } else {
        root.children.append(cardStack)
    }

    func makeDuration(milliseconds: Int64) -> WinUI.Duration {
        WinUI.Duration(
            timeSpan: WindowsFoundation.TimeSpan(duration: milliseconds * 10_000),
            type: .timeSpan
        )
    }

    func runExpandCollapseAnimation(expanding: Bool) {
        guard !isAnimating else { return }
        isAnimating = true

        if expanding {
            expandedHost.visibility = .visible
            expandedHost.opacity = 0
            expandedTransform.translateY = -8
        }

        let storyboard = WinUI.Storyboard()

        let opacityAnimation = WinUI.DoubleAnimation()
        opacityAnimation.from = expanding ? 0 : 1
        opacityAnimation.to = expanding ? 1 : 0
        opacityAnimation.duration = makeDuration(milliseconds: 180)

        let translateAnimation = WinUI.DoubleAnimation()
        translateAnimation.from = expanding ? -8 : 0
        translateAnimation.to = expanding ? 0 : -8
        translateAnimation.duration = makeDuration(milliseconds: 180)

        let easing = WinUI.CubicEase()
        easing.easingMode = .easeOut
        opacityAnimation.easingFunction = easing
        translateAnimation.easingFunction = easing

        try? WinUI.Storyboard.setTarget(opacityAnimation, expandedHost)
        try? WinUI.Storyboard.setTargetProperty(opacityAnimation, "Opacity")

        try? WinUI.Storyboard.setTarget(translateAnimation, expandedTransform)
        try? WinUI.Storyboard.setTargetProperty(translateAnimation, "TranslateY")

        storyboard.children.append(opacityAnimation)
        storyboard.children.append(translateAnimation)

        storyboard.completed.addHandler { _, _ in
            if !expanding {
                expandedHost.visibility = .collapsed
            }

            isExpanded = expanding
            isAnimating = false
        }

        chevron.glyph = expanding ? "\u{E70E}" : "\u{E70D}"

        try? storyboard.begin()
    }

    headerBorder.pointerPressed.addHandler { _, e in
        runExpandCollapseAnimation(expanding: !isExpanded)
        e?.handled = true
    }

    return root
}

// MARK: - 卡片画刷

private func primaryBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 255, r: 243, g: 244, b: 246)
            : UWP.Color(a: 255, r: 28, g: 30, b: 33)
    )
}

private func secondaryBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 255, r: 174, g: 178, b: 190)
            : UWP.Color(a: 255, r: 96, g: 104, b: 112)
    )
}

private func dividerBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 255, r: 58, g: 63, b: 77)
            : UWP.Color(a: 255, r: 230, g: 232, b: 236)
    )
}

private func cardBackgroundBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 255, r: 32, g: 36, b: 44)
            : UWP.Color(a: 255, r: 255, g: 255, b: 255)
    )
}

private func cardBorderBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 255, r: 49, g: 55, b: 66)
            : UWP.Color(a: 255, r: 229, g: 231, b: 235)
    )
}

private func accentFillBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 255, r: 103, g: 122, b: 255)
            : UWP.Color(a: 255, r: 90, g: 104, b: 255)
    )
}
