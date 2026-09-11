import WinUI
import WindowsFoundation

/// ContentAlignment controls where the content is placed within SettingsCard.
public enum SettingsCardContentAlignment {
    /// Content is aligned to the right. Default state.
    case right
    /// Content is left-aligned; Header, HeaderIcon and Description are hidden.
    case left
    /// Content is vertically aligned below Header/Description.
    case vertical
}

/// A card control for consistent settings UI, matching the Windows 11 design language.
/// Mirrors the Community Toolkit SettingsCard: a ButtonBase whose CommonStates
/// (Normal/PointerOver/Pressed/Disabled) are driven by pointer and keyboard input,
/// with a smooth background transition between states.
/// Can be used standalone or hosted inside a SettingsExpander.
public class SettingsCard: ButtonBase {

    // MARK: - Properties

    public var header: Any? {
        didSet { rebuildLayout() }
    }

    public var description: Any? {
        didSet { rebuildLayout() }
    }

    public var headerIcon: IconElement? {
        didSet { rebuildLayout() }
    }

    public var actionIcon: FontIcon? = {
        let icon = WinUI.FontIcon()
        icon.glyph = "\u{E974}"  // ChevronRight
        icon.mirroredWhenRightToLeft = true
        return icon
    }()
    {
        didSet { rebuildLayout() }
    }

    public var actionIconToolTip: String? {
        didSet { rebuildLayout() }
    }

    public var isClickEnabled: Bool = false {
        didSet { onIsClickEnabledChanged() }
    }

    public var contentAlignment: SettingsCardContentAlignment = .right {
        didSet { rebuildLayout() }
    }

    public var isActionIconVisible: Bool = true {
        didSet { updateActionIconVisibility() }
    }

    // MARK: - Internal layout parts

    /// Root visual of the card. A Grid carries the same background/border/cornerRadius chrome a
    /// Border would, but can also animate background changes between visual states, matching the
    /// toolkit card's PART_RootGrid.
    let cardRoot = WinUI.Grid()
    private var contentElement: FrameworkElement?
    private var descriptionElement: FrameworkElement?
    private var headerIconHolder: Viewbox?
    private var actionIconHolder: Viewbox?
    private weak var interactionVisualTarget: WinUI.Grid?
    private var isLayoutBatchActive = false

    // MARK: - Visual state

    private enum VisualState {
        case normal
        case pointerOver
        case pressed
        case disabled
    }

    private var lastAppliedVisualState: VisualState?

    /// Computed from the framework-maintained ButtonBase inputs (IsPressed/IsPointerOver), so the
    /// card follows the exact native button semantics: release-while-over stays hovered, dragging
    /// off during a press clears the pressed fill, keyboard activation presses without hover.
    private var visualState: VisualState {
        if !isEnabled { return .disabled }
        guard isClickEnabled else { return .normal }
        if isPressed { return .pressed }
        if isPointerOver { return .pointerOver }
        return .normal
    }

    private func applyVisualState(force: Bool = false) {
        let state = visualState
        if !force && state == lastAppliedVisualState { return }
        lastAppliedVisualState = state

        let visualTarget = interactionVisualTarget ?? cardRoot
        switch state {
        case .normal:
            visualTarget.background = themeBrush("CardBackgroundFillColorDefaultBrush")
            visualTarget.borderBrush = themeBrush("CardStrokeColorDefaultBrush")
            self.foreground = themeBrush("TextFillColorPrimaryBrush")
        case .pointerOver:
            visualTarget.background = themeBrush("ControlFillColorSecondaryBrush")
            visualTarget.borderBrush = themeBrush("ControlElevationBorderBrush")
            self.foreground = themeBrush("TextFillColorPrimaryBrush")
        case .pressed:
            visualTarget.background = themeBrush("ControlFillColorTertiaryBrush")
            visualTarget.borderBrush = themeBrush("ControlStrokeColorDefaultBrush")
            self.foreground = themeBrush("TextFillColorSecondaryBrush")
        case .disabled:
            // Toolkit parity: disabling dims the foreground only, the card fill is unchanged.
            visualTarget.background = themeBrush("CardBackgroundFillColorDefaultBrush")
            visualTarget.borderBrush = themeBrush("CardStrokeColorDefaultBrush")
            self.foreground = themeBrush("TextFillColorDisabledBrush")
        }

        let disabled = !isEnabled
        if let descriptionText = descriptionElement as? WinUI.TextBlock {
            descriptionText.foreground = themeBrush(
                disabled ? "TextFillColorDisabledBrush" : "TextFillColorSecondaryBrush")
        }
        // Bitmap icons cannot be dimmed through the foreground; reduce opacity instead.
        if headerIcon is ImageIcon {
            headerIconHolder?.opacity = disabled ? 0.4 : 1
        }
    }

    /// Fetches a system Fluent token brush, resolved against the current application theme.
    private func themeBrush(_ key: String) -> WinUI.Brush? {
        Application.current.resources?.lookup(key) as? WinUI.Brush
    }

    private func registerStateCallbacks() {
        // IsPressed/IsPointerOver/IsEnabled changes are the exact inputs of the native
        // CommonStates, kept current by ButtonBase itself for pointer and keyboard input.
        // The change-callback tokens are intentionally kept for the control's lifetime.
        _ = try? registerPropertyChangedCallback(Self.isPressedProperty) { [weak self] _, _ in
            self?.applyVisualState()
        }
        _ = try? registerPropertyChangedCallback(Self.isPointerOverProperty) { [weak self] _, _ in
            self?.applyVisualState()
        }
        _ = try? registerPropertyChangedCallback(Self.isEnabledProperty) { [weak self] _, _ in
            self?.applyVisualState()
        }
    }

    // MARK: - Init

    private override init() {
        super.init()

        self.horizontalAlignment = .stretch
        self.verticalAlignment = .stretch
        self.horizontalContentAlignment = .stretch
        self.verticalContentAlignment = .stretch

        cardRoot.minWidth = 148
        cardRoot.minHeight = 68
        cardRoot.padding = WinUI.Thickness(left: 16, top: 16, right: 16, bottom: 16)
        cardRoot.horizontalAlignment = .stretch
        cardRoot.verticalAlignment = .center
        cardRoot.backgroundSizing = .innerBorderEdge
        cardRoot.borderThickness = WinUI.Thickness(left: 1, top: 1, right: 1, bottom: 1)
        cardRoot.cornerRadius = WinUI.CornerRadius(
            topLeft: 4, topRight: 4, bottomRight: 4, bottomLeft: 4)
        let backgroundTransition = WinUI.BrushTransition()
        backgroundTransition.duration = WindowsFoundation.TimeSpan(duration: 83 * 10_000)
        cardRoot.backgroundTransition = backgroundTransition

        // Like the toolkit style: the card only joins tab navigation when it acts as a button.
        self.isTabStop = false
        self.useSystemFocusVisuals = true
        self.focusVisualMargin = WinUI.Thickness(left: -3, top: -3, right: -3, bottom: -3)

        self.content = cardRoot

        registerStateCallbacks()
        applyVisualState()
    }

    /// Header + description (text) + right-side content control, with a glyph icon.
    public convenience init(
        headerIconGlyph: String,
        header: String,
        description: String? = nil,
        content: FrameworkElement? = nil,
        actionIcon: FontIcon? = nil
    ) {
        self.init()
        batchLayoutChanges {
            contentElement = content
            self.header = header
            self.description = description
            if let actionIcon {
                self.actionIcon = actionIcon
            }

            let icon = WinUI.FontIcon()
            icon.glyph = headerIconGlyph
            headerIcon = icon
        }
    }

    /// Header + description (text) + right-side text content, with an image icon.
    public convenience init(
        headerIconPath: String,
        header: String,
        description: String? = nil,
        contentText: String? = nil,
        actionIcon: FontIcon? = nil
    ) {
        self.init()
        batchLayoutChanges {
            self.header = header
            self.description = description
            if let actionIcon {
                self.actionIcon = actionIcon
            }

            let bitmap = BitmapImage()
            bitmap.uriSource = Uri(headerIconPath)
            let icon = ImageIcon()
            icon.source = bitmap
            headerIcon = icon

            if let contentText {
                let tb = TextBlock()
                tb.text = contentText
                contentElement = tb
            }
        }
    }

    /// Header only, with a right-side content control (no icon).
    public convenience init(
        header: String,
        description: FrameworkElement? = nil,
        content: FrameworkElement? = nil,
        actionIcon: FontIcon? = nil
    ) {
        self.init()
        batchLayoutChanges {
            contentElement = content
            self.header = header
            self.description = description
            if let actionIcon {
                self.actionIcon = actionIcon
            }
        }
    }

    public convenience init(content: FrameworkElement) {
        self.init()
        batchLayoutChanges {
            contentElement = content
        }
    }

    /// Positional: glyph, header, description, content
    public convenience init(
        _ headerIconGlyph: String, _ header: String, _ description: String? = nil,
        _ content: FrameworkElement? = nil, _ actionIcon: FontIcon? = nil
    ) {
        self.init(
            headerIconGlyph: headerIconGlyph, header: header, description: description,
            content: content, actionIcon: actionIcon)
    }

    /// Positional: header, description (FrameworkElement)
    public convenience init(_ header: String, _ description: FrameworkElement? = nil) {
        self.init(header: header, description: description, content: nil)
    }

    // MARK: - Internal helpers for SettingsExpander

    /// Suppresses the card border/background for use as an inner item inside SettingsExpander.
    func suppressCardStyling() {
        cardRoot.background = nil
        cardRoot.borderBrush = nil
        cardRoot.borderThickness = WinUI.Thickness(left: 0, top: 0, right: 0, bottom: 0)
        cardRoot.cornerRadius = WinUI.CornerRadius(
            topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
    }

    /// Applies the item padding used when hosted inside a SettingsExpander.
    func applyExpanderItemPadding() {
        // Clickable items: right=16 (no action icon space); others: right=44
        let rightPadding: Double = isClickEnabled ? 16 : 44
        cardRoot.padding = WinUI.Thickness(left: 58, top: 8, right: rightPadding, bottom: 8)
    }

    /// Redirects hover/pressed visuals to an outer grid, used by SettingsExpander headers.
    func setInteractionVisualTarget(_ target: WinUI.Grid?) {
        interactionVisualTarget = target
        applyVisualState(force: true)
    }

    // MARK: - State management

    private func onIsClickEnabledChanged() {
        isTabStop = isClickEnabled
        updateActionIconVisibility()
        applyVisualState(force: true)
    }

    private func updateActionIconVisibility() {
        guard let actionIconHolder else { return }
        actionIconHolder.visibility = (isClickEnabled && isActionIconVisible) ? .visible : .collapsed
    }

    // MARK: - Layout

    /// Groups several property assignments into a single layout rebuild.
    private func batchLayoutChanges(_ changes: () -> Void) {
        isLayoutBatchActive = true
        changes()
        isLayoutBatchActive = false
        rebuildLayout()
    }

    private func rebuildLayout() {
        guard !isLayoutBatchActive else { return }

        // UIElement single-parent rule: detach the retained elements from the discarded layout
        // before they get parented into the fresh one.
        for element in [headerIcon, description as? FrameworkElement, contentElement, actionIcon] {
            if let element {
                _ = element.detachFromVisualParent()
            }
        }

        while cardRoot.children.count > 0 {
            cardRoot.children.removeAt(0)
        }
        cardRoot.children.append(buildLayout())
        applyVisualState(force: true)
        updateAccessibleContentName()
    }

    private func resolvedDescriptionView() -> FrameworkElement? {
        if let element = description as? FrameworkElement {
            return element
        }
        if let text = description as? String, !text.isEmpty {
            return makeDescriptionView(text)
        }
        return nil
    }

    private func buildLayout() -> WinUI.Grid {
        let secondaryForeground = themeBrush("TextFillColorSecondaryBrush")

        let container = WinUI.Grid()

        // Columns: [icon] [text*] [content auto] [actionIcon auto]
        for width in [
            WinUI.GridLength(value: 1, gridUnitType: .auto),
            WinUI.GridLength(value: 1, gridUnitType: .star),
            WinUI.GridLength(value: 1, gridUnitType: .auto),
            WinUI.GridLength(value: 1, gridUnitType: .auto),
        ] {
            let column = WinUI.ColumnDefinition()
            column.width = width
            container.columnDefinitions.append(column)
        }

        // Rows: [header row*] [content/description row auto]
        let headerRow = WinUI.RowDefinition()
        headerRow.height = WinUI.GridLength(value: 1, gridUnitType: .star)
        container.rowDefinitions.append(headerRow)

        let descRow = WinUI.RowDefinition()
        descRow.height = WinUI.GridLength(value: 1, gridUnitType: .auto)
        container.rowDefinitions.append(descRow)

        // A card built with only content (init(content:)) hosts the element full-bleed across
        // the whole card face; it does not participate in the header/content column layout.
        if header == nil, description == nil, headerIcon == nil, let ctrl = contentElement {
            headerIconHolder = nil
            actionIconHolder = nil
            descriptionElement = nil
            ctrl.horizontalAlignment = .stretch
            ctrl.verticalAlignment = .stretch
            container.children.append(ctrl)
            try? WinUI.Grid.setRow(ctrl, 0)
            try? WinUI.Grid.setColumn(ctrl, 0)
            try? WinUI.Grid.setRowSpan(ctrl, 2)
            try? WinUI.Grid.setColumnSpan(ctrl, 4)
            return container
        }

        // Determine visibility based on contentAlignment
        let headerText = (header as? String) ?? ""
        let descriptionView = resolvedDescriptionView()
        let showHeaderIcon = (contentAlignment != .left) && (headerIcon != nil)
        let showHeaderText = (contentAlignment != .left) && !headerText.isEmpty
        let showDescription = (contentAlignment != .left) && (descriptionView != nil)

        // Header Icon Holder (col 0, row 0)
        if showHeaderIcon, let icon = headerIcon {
            if let fontIcon = icon as? WinUI.FontIcon {
                fontIcon.fontSize = 20
            } else if let imageIcon = icon as? ImageIcon {
                imageIcon.width = 24
                imageIcon.height = 24
            }
            icon.verticalAlignment = .center

            let holder: Viewbox = WinUI.Viewbox()
            holder.maxWidth = 20
            holder.maxHeight = 20
            holder.margin = WinUI.Thickness(left: 2, top: 0, right: 20, bottom: 0)
            holder.verticalAlignment = .center
            holder.stretch = .uniform
            holder.child = icon
            headerIconHolder = holder
            container.children.append(holder)
            try? WinUI.Grid.setRow(holder, 0)
            try? WinUI.Grid.setColumn(holder, 0)
        } else {
            headerIconHolder = nil
        }

        // Header Panel (col 1, row 0)
        if showHeaderText || showDescription {
            let headerPanel: StackPanel = WinUI.StackPanel()
            headerPanel.orientation = .vertical
            headerPanel.verticalAlignment = .center
            headerPanel.margin =
                (contentAlignment == .right)
                ? WinUI.Thickness(left: 0, top: 0, right: 24, bottom: 0)
                : WinUI.Thickness(left: 0, top: 0, right: 0, bottom: 0)
            try? WinUI.Grid.setRow(headerPanel, 0)
            try? WinUI.Grid.setColumn(headerPanel, 1)
            container.children.append(headerPanel)

            // Header label
            if showHeaderText {
                let titleLabel = WinUI.TextBlock()
                titleLabel.text = headerText
                titleLabel.fontSize = 14
                titleLabel.textWrapping = .wrap
                headerPanel.children.append(titleLabel)
            }

            // Description
            if showDescription, let desc = descriptionView {
                if let tb = desc as? WinUI.TextBlock {
                    tb.foreground = secondaryForeground
                    tb.fontSize = 12
                    tb.textWrapping = .wrap
                }
                headerPanel.children.append(desc)
            }
        }
        descriptionElement = showDescription ? descriptionView : nil

        // Content placement based on contentAlignment
        if let ctrl = contentElement {
            switch contentAlignment {
            case .right:
                // Content in col 2, row 0, right-aligned
                ctrl.verticalAlignment = .center
                ctrl.horizontalAlignment = .right
                container.children.append(ctrl)
                try? WinUI.Grid.setRow(ctrl, 0)
                try? WinUI.Grid.setColumn(ctrl, 2)
                try? WinUI.Grid.setRowSpan(ctrl, 2)

            case .left:
                // Content in col 1, row 1, left-aligned
                ctrl.horizontalAlignment = .left
                ctrl.verticalAlignment = .center
                container.children.append(ctrl)
                try? WinUI.Grid.setRow(ctrl, 1)
                try? WinUI.Grid.setColumn(ctrl, 1)

            case .vertical:
                // Content in col 1, row 1, stretch horizontally
                ctrl.horizontalAlignment = .stretch
                ctrl.verticalAlignment = .center
                container.children.append(ctrl)
                try? WinUI.Grid.setRow(ctrl, 1)
                try? WinUI.Grid.setColumn(ctrl, 1)
            }
        }

        // Vertical content sits below the header block; give it the toolkit's 8px spacing.
        if contentAlignment == .vertical, contentElement != nil,
            showHeaderText || showDescription
        {
            container.rowSpacing = 8
        }

        // Action icon (col 3, spans both rows)
        if let aIcon = actionIcon {
            let holder: Viewbox = WinUI.Viewbox()
            holder.maxWidth = 13
            holder.maxHeight = 13
            holder.margin = WinUI.Thickness(left: 14, top: 0, right: 0, bottom: 0)
            holder.horizontalAlignment = .center
            holder.verticalAlignment = .center
            holder.stretch = .uniform

            aIcon.fontSize = 13
            aIcon.verticalAlignment = .center

            // Apply ToolTip if available
            if let toolTip = actionIconToolTip, !toolTip.isEmpty {
                try? WinUI.ToolTipService.setToolTip(holder, toolTip)
            }

            holder.visibility =
                (isClickEnabled && isActionIconVisible) ? .visible : .collapsed
            holder.child = aIcon
            actionIconHolder = holder
            container.children.append(holder)
            try? WinUI.Grid.setRowSpan(holder, 2)
            try? WinUI.Grid.setColumn(holder, 3)
        } else {
            actionIconHolder = nil
        }

        return container
    }

    // MARK: - Accessibility

    /// Gives the content element the header text as its automation name, unless one was already
    /// set or the content announces itself (buttons, plain text).
    private func updateAccessibleContentName() {
        guard let headerText = header as? String, !headerText.isEmpty,
            let element = contentElement,
            !(element is WinUI.TextBlock),
            !(element is WinUI.ButtonBase),
            (try? WinUI.AutomationProperties.getName(element))?.isEmpty == true
        else { return }
        try? WinUI.AutomationProperties.setName(element, headerText)
    }

    // MARK: - Helpers

    private func makeDescriptionView(_ text: String) -> FrameworkElement {
        let tb: TextBlock = App.context.requireXaml(
            withString:
                """
                <TextBlock xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" >
                \(text)
                </TextBlock>
                """)
        return tb
    }
}
