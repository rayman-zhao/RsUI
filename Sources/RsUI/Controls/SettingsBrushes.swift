import UWP
import WinUI
import WindowsFoundation


// MARK: - Brushes (internal)

enum SettingsBrushMode {
    case light
    case dark
    case automatic

    init(theme: AppTheme) {
        switch theme {
        case .light:
            self = .light
        case .dark:
            self = .dark
        case .auto:
            self = .automatic
        }
    }
}

private struct SettingsBrushPalette {
    let settingsCardBackground: UWP.Color
    let settingsCardBackgroundPointerOver: UWP.Color
    let settingsCardBackgroundPressed: UWP.Color
    let settingsCardBackgroundDisabled: UWP.Color

    let settingsCardForeground: UWP.Color
    let settingsCardForegroundPointerOver: UWP.Color
    let settingsCardForegroundPressed: UWP.Color
    let settingsCardForegroundDisabled: UWP.Color

    let settingsCardBorderBrush: UWP.Color
    let settingsCardBorderBrushPressed: UWP.Color
    let settingsCardBorderBrushDisabled: UWP.Color

    let divider: UWP.Color
    let secondary: UWP.Color

    static let light = SettingsBrushPalette(
        settingsCardBackground: UWP.Color(a: 0xB3, r: 0xFF, g: 0xFF, b: 0xFF),
        settingsCardBackgroundPointerOver: UWP.Color(a: 0x80, r: 0xF9, g: 0xF9, b: 0xF9),
        settingsCardBackgroundPressed: UWP.Color(a: 0x4D, r: 0xF9, g: 0xF9, b: 0xF9),
        settingsCardBackgroundDisabled: UWP.Color(a: 0x4D, r: 0xF9, g: 0xF9, b: 0xF9),

        settingsCardForeground: UWP.Color(a: 0xE4, r: 0x00, g: 0x00, b: 0x00),
        settingsCardForegroundPointerOver: UWP.Color(a: 0xE4, r: 0x00, g: 0x00, b: 0x00),
        settingsCardForegroundPressed: UWP.Color(a: 0x9E, r: 0x00, g: 0x00, b: 0x00),
        settingsCardForegroundDisabled: UWP.Color(a: 0x5C, r: 0x00, g: 0x00, b: 0x00),

        settingsCardBorderBrush: UWP.Color(a: 0x0F, r: 0x00, g: 0x00, b: 0x00),
        settingsCardBorderBrushPressed: UWP.Color(a: 0x0F, r: 0x00, g: 0x00, b: 0x00),
        settingsCardBorderBrushDisabled: UWP.Color(a: 0x0F, r: 0x00, g: 0x00, b: 0x00),

        divider: UWP.Color(a: 15, r: 0, g: 0, b: 0),
        secondary: UWP.Color(a: 255, r: 96, g: 104, b: 112)
    )

    static let dark = SettingsBrushPalette(
        settingsCardBackground: UWP.Color(a: 0x0D, r: 0xFF, g: 0xFF, b: 0xFF),
        settingsCardBackgroundPointerOver: UWP.Color(a: 0x15, r: 0xFF, g: 0xFF, b: 0xFF),
        settingsCardBackgroundPressed: UWP.Color(a: 0x08, r: 0xFF, g: 0xFF, b: 0xFF),
        settingsCardBackgroundDisabled: UWP.Color(a: 0x0B, r: 0xFF, g: 0xFF, b: 0xFF),

        settingsCardForeground: UWP.Color(a: 0xFF, r: 0xFF, g: 0xFF, b: 0xFF),
        settingsCardForegroundPointerOver: UWP.Color(a: 0xFF, r: 0xFF, g: 0xFF, b: 0xFF),
        settingsCardForegroundPressed: UWP.Color(a: 0xC5, r: 0xFF, g: 0xFF, b: 0xFF),
        settingsCardForegroundDisabled: UWP.Color(a: 0x5D, r: 0xFF, g: 0xFF, b: 0xFF),

        settingsCardBorderBrush: UWP.Color(a: 0x19, r: 0x00, g: 0x00, b: 0x00),
        settingsCardBorderBrushPressed: UWP.Color(a: 0x12, r: 0xFF, g: 0xFF, b: 0xFF),
        settingsCardBorderBrushDisabled: UWP.Color(a: 0x12, r: 0xFF, g: 0xFF, b: 0xFF),

        divider: UWP.Color(a: 24, r: 255, g: 255, b: 255),
        secondary: UWP.Color(a: 255, r: 174, g: 178, b: 190)
    )

    static let automatic = dark
}

private func settingsBrushPalette(for mode: SettingsBrushMode) -> SettingsBrushPalette {
    switch mode {
    case .light:
        return .light
    case .dark:
        return .dark
    case .automatic:
        return .automatic
    }
}

private func settingsBrushPalette(for theme: AppTheme = App.context.theme) -> SettingsBrushPalette {
    settingsBrushPalette(for: SettingsBrushMode(theme: theme))
}

func cardBackgroundBrush(theme: AppTheme = App.context.theme) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(settingsBrushPalette(for: theme).settingsCardBackground)
}

func cardHoverBrush(theme: AppTheme = App.context.theme) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(settingsBrushPalette(for: theme).settingsCardBackgroundPointerOver)
}

func cardPressedBrush(theme: AppTheme = App.context.theme) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(settingsBrushPalette(for: theme).settingsCardBackgroundPressed)
}

func cardForegroundBrush(theme: AppTheme = App.context.theme) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(settingsBrushPalette(for: theme).settingsCardForeground)
}

func cardForegroundHoverBrush(theme: AppTheme = App.context.theme) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(settingsBrushPalette(for: theme).settingsCardForegroundPointerOver)
}

func cardForegroundPressedBrush(theme: AppTheme = App.context.theme) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(settingsBrushPalette(for: theme).settingsCardForegroundPressed)
}


func cardBorderBrush(theme: AppTheme = App.context.theme) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(settingsBrushPalette(for: theme).settingsCardBorderBrush)
}

func cardBorderBrushPointerOver(theme: AppTheme = App.context.theme) -> WinUI.Brush {
    makeControlElevationBorderBrush(mode: SettingsBrushMode(theme: theme))
}

/// 此 Brush 是渐变, 比较特殊, 需要特殊处理.
private func makeControlElevationBorderBrush(mode: SettingsBrushMode) -> WinUI.Brush {
    let brush = WinUI.LinearGradientBrush()
    brush.mappingMode = .absolute
    brush.startPoint = WindowsFoundation.Point(x: 0, y: 0)
    brush.endPoint = WindowsFoundation.Point(x: 0, y: 3)

    let stops = WinUI.GradientStopCollection()

    let topStop = WinUI.GradientStop()
    topStop.offset = 0.33

    let bottomStop = WinUI.GradientStop()
    bottomStop.offset = 1.0

    switch mode {
    case .light:
        topStop.color = UWP.Color(a: 0x29, r: 0x00, g: 0x00, b: 0x00)
        bottomStop.color = UWP.Color(a: 0x0F, r: 0x00, g: 0x00, b: 0x00)

        let transform = WinUI.CompositeTransform()
        transform.scaleY = -1
        transform.centerY = 0.5
        brush.relativeTransform = transform

    case .dark, .automatic:
        topStop.color = UWP.Color(a: 0x18, r: 0xFF, g: 0xFF, b: 0xFF)
        bottomStop.color = UWP.Color(a: 0x12, r: 0xFF, g: 0xFF, b: 0xFF)
    }

    stops.append(topStop)
    stops.append(bottomStop)
    brush.gradientStops = stops

    return brush
}

func cardBorderBrushPressed(theme: AppTheme = App.context.theme) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(settingsBrushPalette(for: theme).settingsCardBorderBrushPressed)
}

func dividerBrush(theme: AppTheme = App.context.theme) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(settingsBrushPalette(for: theme).divider)
}

func secondaryBrush(theme: AppTheme = App.context.theme) -> WinUI.SolidColorBrush {
    WinUI.SolidColorBrush(settingsBrushPalette(for: theme).secondary)
}