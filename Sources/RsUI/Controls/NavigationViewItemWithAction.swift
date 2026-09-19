import WinAppSDK
import WinUI
import WindowsFoundation

/// A navigation view item carrying a hover-revealed action button at the right end of its
/// content: the button is completely hidden while the row is idle and appears when the row is
/// hovered, the button is keyboard-focused, or the item is selected.
///
/// Row hover cannot come from pointer events: NavigationViewItem's class handling swallows
/// pointer routed events, so classic pointer handlers never fire anywhere in the item subtree
/// (verified at runtime). The surviving signal is the item's own visual state machine — its
/// hover highlight is the "PointerOver" state of the template's "PointerStates" group — so on
/// load we locate that group in the visual subtree and track its `currentStateChanged`
/// transitions (a classic, non-routed event, unaffected by pointer handling). Selection and
/// focus ride the reliable property / focus events.
public final class NavigationViewItemWithAction: NavigationViewItem {
    public let actionButton: Button
    private var rowHovered = false
    private var buttonFocused = false

    public init(
        iconGlyph: String,
        label: String,
        url: String,
        actionGlyph: String,
        actionTooltip: String,
        actionHandler: @escaping (Any?, RoutedEventArgs?) throws -> Void
    ) {
        // 内容：标签(填充) | 动作按钮(自动)
        let grid = Grid()
        grid.horizontalAlignment = .stretch
        grid.verticalAlignment = .center

        let textCol = ColumnDefinition()
        textCol.width = GridLength(value: 1, gridUnitType: .star)
        grid.columnDefinitions.append(textCol)
        let actionCol = ColumnDefinition()
        actionCol.width = GridLength(value: 0, gridUnitType: .auto)
        grid.columnDefinitions.append(actionCol)

        let textBlock = TextBlock()
        textBlock.text = label
        textBlock.verticalAlignment = .center
        try? Grid.setColumn(textBlock, 0)
        grid.children.append(textBlock)

        let actionButton = Button()
        actionButton.background = SolidColorBrush(Colors.transparent)
        actionButton.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        actionButton.padding = Thickness(left: 4, top: 4, right: 4, bottom: 4)
        let actionIcon = FontIcon()
        actionIcon.glyph = actionGlyph
        // actionIcon.fontSize = 16
        actionButton.content = actionIcon
        try? ToolTipService.setToolTip(actionButton, actionTooltip)
        actionButton.click.addHandler(actionHandler)
        actionButton.opacity = 0
        actionButton.isHitTestVisible = false
        try? Grid.setColumn(actionButton, 1)
        grid.children.append(actionButton)
        self.actionButton = actionButton

        super.init()

        let icon = FontIcon()
        icon.glyph = iconGlyph
        self.icon = icon
        self.content = grid
        self.tag = try? HString(url)

        // 强捕获 self 是有意的：swift-winrt 包装对象不按 COM 身份缓存，仅靠原生可视树
        // 持有无法维持本实例 Swift 一侧的存活。
        loaded.addHandler { [self] _, _ in
            bindHoverStates()
            update()
        }
        // 主题/语言切换会重建模板，使已绑定的状态组失效；重新绑定是幂等的。
        actualThemeChanged.addHandler { [self] _, _ in
            bindHoverStates()
        }
        _ = try? registerPropertyChangedCallback(
            NavigationViewItem.isSelectedProperty
        ) { [self] _, _ in
            update()
        }

        actionButton.gotFocus.addHandler { [weak self] _, _ in
            self?.setButtonFocused(true)
        }
        actionButton.lostFocus.addHandler { [weak self] _, _ in
            self?.setButtonFocused(false)
        }

        update()
    }

    /// Finds the item template's CommonStates (the group that defines a "PointerOver" state)
    /// and mirrors its transitions into `rowHovered`.
    private func bindHoverStates() {
        for group in collectStateGroups(from: self, depth: 0) {
            guard let states = group.states else { continue }
            let names = Array(states).compactMap { $0?.name }
            guard names.contains("PointerOver") else { continue }

            group.currentStateChanged.addHandler { [self] _, args in
                let name = args?.newState?.name ?? ""
                setRowHovered(name.contains("PointerOver") || name.contains("Pressed"))
            }
            let current = group.currentState?.name ?? ""
            setRowHovered(current.contains("PointerOver") || current.contains("Pressed"))
        }
    }

    /// Depth-limited walk collecting every VisualStateGroup declared in the subtree — the
    /// groups live on the template roots, not on the item itself.
    private func collectStateGroups(from element: DependencyObject, depth: Int) -> [VisualStateGroup] {
        guard depth < 8 else { return [] }
        var groups: [VisualStateGroup] = []
        if let frameworkElement = element as? FrameworkElement,
            let list = try? VisualStateManager.getVisualStateGroups(frameworkElement)
        {
            groups += Array(list).compactMap { $0 }
        }
        for index in 0..<((try? VisualTreeHelper.getChildrenCount(element)) ?? 0) {
            if let child = try? VisualTreeHelper.getChild(element, index) {
                groups += collectStateGroups(from: child, depth: depth + 1)
            }
        }
        return groups
    }

    private func setRowHovered(_ hovered: Bool) {
        rowHovered = hovered
        update()
    }

    private func setButtonFocused(_ focused: Bool) {
        buttonFocused = focused
        update()
    }

    private func update() {
        let revealed = rowHovered || buttonFocused || isSelected
        actionButton.opacity = revealed ? 1 : 0
        actionButton.isHitTestVisible = revealed
    }
}
