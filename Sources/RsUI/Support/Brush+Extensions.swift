import WinUI

extension Brush {
    /// 取当前应用主题字典中的 Fluent token 画刷。
    /// 画刷是解析时的实例，不随主题切换自动更新 —— 长生命周期的控件应在
    /// `actualThemeChanged` 里重取（参照 SettingsCard / SettingsExpander / RangeSlider）。
    static func fluentTheme(_ key: String) -> Brush? {
        Application.current.resources?.lookup(key) as? Brush
    }
}
