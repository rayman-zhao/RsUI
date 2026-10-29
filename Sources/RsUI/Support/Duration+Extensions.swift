import WinUI
import WindowsFoundation

extension TimeSpan {
    /// 毫秒转 `TimeSpan`(底层 tick 单位是 100ns)。
    public static func make(milliseconds: Int64) -> TimeSpan {
        TimeSpan(duration: milliseconds * 10_000)
    }
}

extension WinUI.Duration {
    /// 毫秒转 XAML 动画时长(`.timeSpan` 形态)。
    public static func make(milliseconds: Int64) -> WinUI.Duration {
        WinUI.Duration(timeSpan: .make(milliseconds: milliseconds), type: .timeSpan)
    }
}
