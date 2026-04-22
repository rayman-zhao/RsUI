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
    private var actionIconHolder: FrameworkElement?

    // MARK: - Init

    private override init() {
        super.init()

        let isDark: Bool = App.context.theme.isDark

        self.horizontalAlignment = .stretch
        self.verticalAlignment = .stretch
        self.horizontalContentAlignment = .stretch
        self.verticalContentAlignment = .stretch

        cardBorder.background = cardBackgroundBrush(isDark: isDark)
        cardBorder.borderBrush = cardBorderBrush(isDark: isDark)
        cardBorder.borderThickness = WinUI.Thickness(left: 1, top: 1, right: 1, bottom: 1)
        cardBorder.cornerRadius = WinUI.CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
        cardBorder.padding = WinUI.Thickness(left: 16, top: 16, right: 16, bottom: 16)

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
        // Left = 58 (aligns with header icon column), right = 44 (leaves room for action icon)
        cardBorder.padding = WinUI.Thickness(left: 58, top: 8, right: 44, bottom: 8)
    }

    // MARK: - State management

    private func onIsClickEnabledChanged() {
        updateActionIconVisibility()
        if isClickEnabled {
            enableHoverInteraction()
        } else {
            disableHoverInteraction()
        }
    }

    private func updateActionIconVisibility() {
        guard let holder = actionIconHolder else { return }
        holder.visibility = (isClickEnabled && isActionIconVisible) ? .visible : .collapsed
    }

    private func enableHoverInteraction() {
        disableHoverInteraction()
        let isDark = App.context.theme.isDark
        pointerEntered.addHandler { [weak self] _, _ in
            self?.cardBorder.background = cardHoverBrush(isDark: isDark)
        }
        pointerExited.addHandler { [weak self] _, _ in
            self?.cardBorder.background = cardBackgroundBrush(isDark: isDark)
        }
        pointerPressed.addHandler { [weak self] _, _ in
            self?.cardBorder.background = cardPressedBrush(isDark: isDark)
        }
        pointerReleased.addHandler { [weak self] _, _ in
            self?.cardBorder.background = cardBackgroundBrush(isDark: isDark)
        }
    }

    private func disableHoverInteraction() {
        // WinUI event tokens are not easily removable without storing them;
        // reassign background to reset visual state.
        let isDark = App.context.theme.isDark
        cardBorder.background = cardBackgroundBrush(isDark: isDark)
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
        iconCol.width = WinUI.GridLength(value: headerIcon != nil ? 40 : 0, gridUnitType: .pixel)
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

        // Rows: [header auto] [description auto]
        let headerRow = WinUI.RowDefinition()
        headerRow.height = WinUI.GridLength(value: 1, gridUnitType: .auto)
        container.rowDefinitions.append(headerRow)

        let descRow = WinUI.RowDefinition()
        descRow.height = WinUI.GridLength(value: 1, gridUnitType: .auto)
        container.rowDefinitions.append(descRow)

        // Header icon (col 0, spans both rows)
        if let icon = headerIcon {
            if let fontIcon = icon as? WinUI.FontIcon {
                fontIcon.fontSize = 20
            } else if let imageIcon = icon as? ImageIcon {
                imageIcon.width = 24
                imageIcon.height = 24
            }
            icon.verticalAlignment = .center
            container.children.append(icon)
            try? WinUI.Grid.setRow(icon, 0)
            try? WinUI.Grid.setColumn(icon, 0)
            try? WinUI.Grid.setRowSpan(icon, 2)
        }

        // Header label (col 1, row 0)
        if let headerText = header, !headerText.isEmpty {
            let titleLabel = WinUI.TextBlock()
            titleLabel.text = headerText
            titleLabel.fontSize = 14
            titleLabel.textWrapping = .wrap
            titleLabel.margin = WinUI.Thickness(left: headerIcon != nil ? 16 : 0, top: 0, right: 0, bottom: 2)
            container.children.append(titleLabel)
            try? WinUI.Grid.setRow(titleLabel, 0)
            try? WinUI.Grid.setColumn(titleLabel, 1)
        }

        // Description (col 1, row 1)
        if let desc = description {
            if let tb = desc as? TextBlock {
                tb.foreground = secondaryForeground
                tb.fontSize = 12
                tb.textWrapping = .wrap
                tb.margin = WinUI.Thickness(left: headerIcon != nil ? 16 : 0, top: 0, right: 0, bottom: 0)
            } else {
                desc.margin = WinUI.Thickness(left: headerIcon != nil ? 16 : 0, top: 0, right: 0, bottom: 0)
            }
            container.children.append(desc)
            try? WinUI.Grid.setRow(desc, 1)
            try? WinUI.Grid.setColumn(desc, 1)
        }

        // Right-side content (col 2, spans both rows) — only shown in .right alignment
        if let ctrl = content, contentAlignment == .right {
            ctrl.verticalAlignment = .center
            container.children.append(ctrl)
            try? WinUI.Grid.setRow(ctrl, 0)
            try? WinUI.Grid.setColumn(ctrl, 2)
            try? WinUI.Grid.setRowSpan(ctrl, 2)
        }

        // Action icon (col 3, spans both rows) — only when isClickEnabled && isActionIconVisible
        let effectiveActionIcon = actionIcon ?? self.actionIcon
        if let aIcon = effectiveActionIcon {
            aIcon.fontSize = 13
            aIcon.margin = WinUI.Thickness(left: 14, top: 0, right: 0, bottom: 0)
            aIcon.verticalAlignment = .center
            if let toolTip = actionIconToolTip {
                // ToolTipService not directly available in this API; store for future use
                _ = toolTip
            }
            aIcon.visibility = (isClickEnabled && isActionIconVisible) ? .visible : .collapsed
            container.children.append(aIcon)
            try? WinUI.Grid.setRow(aIcon, 0)
            try? WinUI.Grid.setColumn(aIcon, 3)
            try? WinUI.Grid.setRowSpan(aIcon, 2)
            actionIconHolder = aIcon
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
            ? UWP.Color(a: 255, r: 32, g: 36, b: 44)
            : UWP.Color(a: 255, r: 255, g: 255, b: 255)
    )
}

func cardBorderBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 255, r: 49, g: 55, b: 66)
            : UWP.Color(a: 255, r: 229, g: 231, b: 235)
    )
}

private func cardHoverBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    // ControlFillColorSecondary
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 255, r: 40, g: 44, b: 53)
            : UWP.Color(a: 255, r: 246, g: 246, b: 248)
    )
}

private func cardPressedBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    // ControlFillColorTertiary
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 255, r: 28, g: 32, b: 40)
            : UWP.Color(a: 255, r: 240, g: 240, b: 242)
    )
}

func dividerBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 255, r: 58, g: 63, b: 77)
            : UWP.Color(a: 255, r: 230, g: 232, b: 236)
    )
}

func secondaryBrush(isDark: Bool) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(
        isDark
            ? UWP.Color(a: 255, r: 174, g: 178, b: 190)
            : UWP.Color(a: 255, r: 96, g: 104, b: 112)
    )
}
