import WindowsFoundation
import UWP
import WinAppSDK
import WinUI

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
/// Can be used standalone or hosted inside a SettingsExpander.
public class SettingsCard: ButtonBase {

    // MARK: - Properties

    public var header: Any?
    public var description: Any?
    public var headerIcon: IconElement?
    public var actionIcon: FontIcon? = {
        let icon = WinUI.FontIcon()
        icon.glyph = "\u{E974}" // ChevronRight
        return icon
    }()
    public var actionIconToolTip: String?
    public var isClickEnabled: Bool = false {
        didSet { onIsClickEnabledChanged() }
    }
    public var contentAlignment: SettingsCardContentAlignment = .right
    public var isActionIconVisible: Bool = true {
        didSet { updateActionIconVisibility() }
    }

    // MARK: - Internal layout parts

    let cardBorder = WinUI.Border()
    private var rootGrid: WinUI.Grid?
    private var actionIconHolder: Viewbox?

    // Event cleanups for proper handler removal
    private var pointerEnteredToken: EventCleanup?
    private var pointerExitedToken: EventCleanup?
    private var pointerPressedToken: EventCleanup?
    private var pointerReleasedToken: EventCleanup?
    private var pointerCaptureLostToken: EventCleanup?
    private var pointerCanceledToken: EventCleanup?

    // MARK: - Init

    private override init() {
        super.init()

        let isDark: Bool = App.context.theme.isDark

        self.horizontalAlignment = .stretch
        self.verticalAlignment = .stretch
        self.horizontalContentAlignment = .stretch
        self.verticalContentAlignment = .stretch

        cardBorder.minWidth = 148
        cardBorder.minHeight = 68
        cardBorder.padding = WinUI.Thickness(left: 16, top: 16, right: 16, bottom: 16)
        cardBorder.horizontalAlignment = .stretch
        cardBorder.verticalAlignment = .center
        cardBorder.backgroundSizing = .innerBorderEdge
        cardBorder.borderThickness = WinUI.Thickness(left: 1, top: 1, right: 1, bottom: 1)
        cardBorder.cornerRadius = WinUI.CornerRadius(topLeft: 4, topRight: 4, bottomRight: 8, bottomLeft: 4)
        cardBorder.background = cardBackgroundBrush(isDark: isDark)
        cardBorder.borderBrush = cardBorderBrush(isDark: isDark)

        self.content = cardBorder
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
        self.header = header
        self.description = description
        self.actionIcon = actionIcon

        let icon = WinUI.FontIcon()
        icon.glyph = headerIconGlyph
        self.headerIcon = icon

        cardBorder.child = buildLayout(
            headerIcon: icon,
            header: header,
            description: makeDescriptionView(description),
            content: content,
            actionIcon: actionIcon
        )
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
        self.header = header
        self.description = description
        self.actionIcon = actionIcon

        let bitmap = BitmapImage()
        bitmap.uriSource = Uri(headerIconPath)
        let icon = ImageIcon()
        icon.source = bitmap
        self.headerIcon = icon

        let contentView: FrameworkElement? = contentText.map {
            let tb = TextBlock()
            tb.text = $0
            return tb
        }

        cardBorder.child = buildLayout(
            headerIcon: icon,
            header: header,
            description: makeDescriptionView(description),
            content: contentView,
            actionIcon: actionIcon
        )
    }

    /// Header only, with a right-side content control (no icon).
    public convenience init(
        header: String,
        description: FrameworkElement? = nil,
        content: FrameworkElement? = nil,
        actionIcon: FontIcon? = nil
    ) {
        self.init()
        self.header = header
        self.description = description
        self.actionIcon = actionIcon

        cardBorder.child = buildLayout(
            header: header,
            description: description,
            content: content,
            actionIcon: actionIcon
        )
    }

    /// Positional: glyph, header, description, content
    public convenience init(_ headerIconGlyph: String, _ header: String, _ description: String? = nil, _ content: FrameworkElement? = nil, _ actionIcon: FontIcon? = nil) {
        self.init(headerIconGlyph: headerIconGlyph, header: header, description: description, content: content, actionIcon: actionIcon)
    }

    /// Positional: header, description (FrameworkElement)
    public convenience init(_ header: String, _ description: FrameworkElement? = nil) {
        self.init(header: header, description: description, content: nil)
    }

    // MARK: - Internal helpers for SettingsExpander

    /// Suppresses the card border/background for use as an inner item inside SettingsExpander.
    func suppressCardStyling() {
        cardBorder.background = nil
        cardBorder.borderBrush = nil
        cardBorder.borderThickness = WinUI.Thickness(left: 0, top: 0, right: 0, bottom: 0)
        cardBorder.cornerRadius = WinUI.CornerRadius(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
    }

    /// Applies the item padding used when hosted inside a SettingsExpander.
    func applyExpanderItemPadding() {
        // Clickable items: right=16 (no action icon space); others: right=44
        let rightPadding: Double = isClickEnabled ? 16 : 44
        cardBorder.padding = WinUI.Thickness(left: 58, top: 8, right: rightPadding, bottom: 8)
    }

    // MARK: - State management

    private func onIsClickEnabledChanged() {
        updateActionIconVisibility()
        if isClickEnabled {
            enableInteraction()
        } else {
            disableInteraction()
        }
    }

    private func updateActionIconVisibility() {
        guard let holder = actionIconHolder else { return }
        holder.visibility = (isClickEnabled && isActionIconVisible) ? .visible : .collapsed
    }

    private func enableInteraction() {
        disableInteraction()

        pointerEnteredToken = pointerEntered.addHandler { [weak self] _, _ in
            self?.goToPointerOverState()
        }
        pointerExitedToken = pointerExited.addHandler { [weak self] _, _ in
            self?.goToNormalState()
        }
        pointerPressedToken = pointerPressed.addHandler { [weak self] _, _ in
            self?.goToPressedState()
        }
        pointerReleasedToken = pointerReleased.addHandler { [weak self] _, _ in
            self?.goToNormalState()
        }
        pointerCaptureLostToken = pointerCaptureLost.addHandler { [weak self] _, _ in
            self?.goToNormalState()
        }
        pointerCanceledToken = pointerCanceled.addHandler { [weak self] _, _ in
            self?.goToNormalState()
        }
    }

    private func disableInteraction() {
        pointerEnteredToken?.dispose(); pointerEnteredToken = nil
        pointerExitedToken?.dispose(); pointerExitedToken = nil
        pointerPressedToken?.dispose(); pointerPressedToken = nil
        pointerReleasedToken?.dispose(); pointerReleasedToken = nil
        pointerCaptureLostToken?.dispose(); pointerCaptureLostToken = nil
        pointerCanceledToken?.dispose(); pointerCanceledToken = nil

        goToNormalState()
    }

    // Visual state transitions
    private func goToNormalState() {
        let isDark = App.context.theme.isDark
        cardBorder.background = cardBackgroundBrush(isDark: isDark)
    }

    private func goToPointerOverState() {
        let isDark = App.context.theme.isDark
        cardBorder.background = cardHoverBrush(isDark: isDark)
    }

    private func goToPressedState() {
        let isDark = App.context.theme.isDark
        cardBorder.background = cardPressedBrush(isDark: isDark)
    }

    // MARK: - Layout builder

    private func buildLayout(
        headerIcon: IconElement? = nil,
        header: String? = nil,
        description: FrameworkElement? = nil,
        content: FrameworkElement? = nil,
        actionIcon: FontIcon? = nil
    ) -> WinUI.Grid {
        let isDark = App.context.theme.isDark
        let secondaryForeground = secondaryBrush(isDark: isDark)

        let container = WinUI.Grid()

        // Columns: [icon] [text*] [content auto] [actionIcon auto]
        let iconCol = WinUI.ColumnDefinition()
        iconCol.width = WinUI.GridLength(value: 1, gridUnitType: .auto)
        container.columnDefinitions.append(iconCol)

        let textCol = WinUI.ColumnDefinition()
        textCol.width = WinUI.GridLength(value: 1, gridUnitType: .star)
        container.columnDefinitions.append(textCol)

        let contentCol = WinUI.ColumnDefinition()
        contentCol.width = WinUI.GridLength(value: 1, gridUnitType: .auto)
        container.columnDefinitions.append(contentCol)

        let actionCol = WinUI.ColumnDefinition()
        actionCol.width = WinUI.GridLength(value: 1, gridUnitType: .auto)
        container.columnDefinitions.append(actionCol)

        // Rows: [header row*] [content/description row auto]
        let headerRow = WinUI.RowDefinition()
        headerRow.height = WinUI.GridLength(value: 1, gridUnitType: .star)
        container.rowDefinitions.append(headerRow)

        let descRow = WinUI.RowDefinition()
        descRow.height = WinUI.GridLength(value: 1, gridUnitType: .auto)
        container.rowDefinitions.append(descRow)

        // Determine visibility based on contentAlignment
        let showHeaderIcon = (contentAlignment != .left) && (headerIcon != nil)
        let showHeaderText = (contentAlignment != .left) && (header != nil && !header!.isEmpty)
        let showDescription = (contentAlignment != .left) && (description != nil)

        // Header Icon Holder (col 0, row 0)
        if showHeaderIcon, let icon = headerIcon {
            if let fontIcon = icon as? WinUI.FontIcon {
                fontIcon.fontSize = 20
            } else if let imageIcon = icon as? ImageIcon {
                imageIcon.width = 24
                imageIcon.height = 24
            }
            icon.verticalAlignment = .center

            let headerIconHolder: Viewbox = WinUI.Viewbox()
            headerIconHolder.width = 20
            headerIconHolder.height = 20
            headerIconHolder.margin = WinUI.Thickness(left: 2, top: 0, right: 20, bottom: 0)
            headerIconHolder.verticalAlignment = .center
            headerIconHolder.stretch = .uniform
            headerIconHolder.child = icon
            container.children.append(headerIconHolder)
            try? WinUI.Grid.setRow(headerIconHolder, 0)
            try? WinUI.Grid.setColumn(headerIconHolder, 0)
        }

        // Header Panel (col 1, row 0)
        if showHeaderText || showDescription {
            let headerPanel: StackPanel = WinUI.StackPanel()
            headerPanel.orientation = .vertical
            headerPanel.verticalAlignment = .center
            headerPanel.margin = (contentAlignment == .right)
                ? WinUI.Thickness(left: 0, top: 0, right: 24, bottom: 0)
                : WinUI.Thickness(left: 0, top: 0, right: 0, bottom: 0)
            try? WinUI.Grid.setRow(headerPanel, 0)
            try? WinUI.Grid.setColumn(headerPanel, 1)
            container.children.append(headerPanel)

            // Header label
            if showHeaderText, let headerText = header {
                let titleLabel = WinUI.TextBlock()
                titleLabel.text = headerText
                titleLabel.fontSize = 14
                titleLabel.textWrapping = .wrap
                titleLabel.margin = WinUI.Thickness(left: 0, top: 0, right: 0, bottom: 0)
                headerPanel.children.append(titleLabel)
            }

            // Description
            if showDescription, let desc = description {
                if let tb = desc as? TextBlock {
                    tb.foreground = secondaryForeground
                    tb.fontSize = 12
                    tb.textWrapping = .wrap
                    tb.margin = WinUI.Thickness(left: 0, top: 0, right: 0, bottom: 0)
                } else {
                    desc.margin = WinUI.Thickness(left: 0, top: 0, right: 0, bottom: 0)
                }
                headerPanel.children.append(desc)
            }
        }

        // Content placement based on contentAlignment
        if let ctrl = content {
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

        // Action icon (col 3, spans both rows)
        let effectiveActionIcon = actionIcon ?? self.actionIcon
        if let aIcon = effectiveActionIcon {
            let actionIconHolder: Viewbox = Viewbox()
            actionIconHolder.width = 13
            actionIconHolder.height = 13
            actionIconHolder.margin = WinUI.Thickness(left: 14, top: 0, right: 0, bottom: 0)
            actionIconHolder.horizontalAlignment = .center
            actionIconHolder.verticalAlignment = .center
            actionIconHolder.stretch = .uniform

            aIcon.fontSize = 13
            aIcon.margin = WinUI.Thickness(left: 0, top: 0, right: 0, bottom: 0)
            aIcon.verticalAlignment = .center

            // Apply ToolTip if available
            if let toolTip = actionIconToolTip, !toolTip.isEmpty {
                try? WinUI.ToolTipService.setToolTip(actionIconHolder, toolTip)
            }

            actionIconHolder.visibility = (isClickEnabled && isActionIconVisible) ? .visible : .collapsed
            actionIconHolder.child = aIcon
            self.actionIconHolder = actionIconHolder
            container.children.append(actionIconHolder)
            try? WinUI.Grid.setRowSpan(actionIconHolder, 2)
            try? WinUI.Grid.setColumn(actionIconHolder, 3)
        }

        rootGrid = container
        return container
    }

    // MARK: - Helpers

    private func makeDescriptionView(_ text: String?) -> FrameworkElement? {
        guard let text, !text.isEmpty else { return nil }
        let tb: TextBlock = (try? XamlReader.load("""
            <TextBlock xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" >
            \(text)
            </TextBlock>
            """)) as? TextBlock ?? {
            let t = TextBlock()
            t.text = text
            return t
        }()
        return tb
    }
}

// MARK: - Brushes (internal)

func cardBackgroundBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 13, r: 255, g: 255, b: 255)
            : UWP.Color(a: 179, r: 255, g: 255, b: 255)
    )
}

func cardBorderBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 25, r: 255, g: 255, b: 255)   // CardStrokeColorDefaultBrush dark: #19FFFFFF
            : UWP.Color(a: 15, r: 0, g: 0, b: 0)          // CardStrokeColorDefaultBrush light: #0F000000
    )
}

private func cardHoverBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    // ControlFillColorSecondaryBrush: light #F9F9F9, dark #0FFFFFFF
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 15, r: 255, g: 255, b: 255)
            : UWP.Color(a: 255, r: 249, g: 249, b: 249)
    )
}

private func cardPressedBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    // ControlFillColorTertiaryBrush: light #F9F9F9 ~78%, dark #0AFFFFFF
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 10, r: 255, g: 255, b: 255)
            : UWP.Color(a: 199, r: 249, g: 249, b: 249)
    )
}

func dividerBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    // ExpanderContentBorderBrush: light #0F000000, dark #18FFFFFF
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 24, r: 255, g: 255, b: 255)
            : UWP.Color(a: 15, r: 0, g: 0, b: 0)
    )
}

func secondaryBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 255, r: 174, g: 178, b: 190)
            : UWP.Color(a: 255, r: 96, g: 104, b: 112)
    )
}
