import Foundation
import UWP
import WinUI

@testable import RsUI

var colorCycle: UInt32 = 0

enum HeaderKind { case string, uiElement, nilHeader }

// MARK: - Concrete test pages
func makePage(
    name: String,
    headerKind: HeaderKind,
    effect: SlideNavigationTransitionEffect
) -> RsUI.Page {
    // 循环颜色用肉眼分辨转场
    let palette: [(r: UInt8, g: UInt8, b: UInt8)] = [
        (0xE6, 0xF2, 0xFB), (0xFB, 0xF3, 0xE6), (0xF3, 0xE6, 0xFB),
        (0xE6, 0xFB, 0xF3), (0xFB, 0xE6, 0xF3), (0xF3, 0xFB, 0xE6),
    ]
    let rgb = palette[Int(colorCycle % UInt32(palette.count))]
    colorCycle += 1
    let bg = SolidColorBrush(UWP.Color(a: 0xFF, r: rgb.r / 2, g: rgb.g / 2, b: rgb.b / 2))

    switch headerKind {
    case .string:
        return StringHeaderPage(name: name, bg: bg)
    case .uiElement:
        return UIElementHeaderPage(name: name, bg: bg)
    case .nilHeader:
        return NilHeaderPage(name: name, bg: bg)
    }
}

private final class StringHeaderPage: RsUI.Page {
    let name: String
    let bg: SolidColorBrush

    init(name: String, bg: SolidColorBrush) {
        self.name = name
        self.bg = bg
    }

    var url: URL { URL(string: "rs://test-frame/string/\(name)")! }
    var title: String { name }
    var header: Any? { "String Header — \(name)" }

    var content: UIElement {
        return make(name: name, subtitle: "header.kind = String", bg: bg)
    }
}

private final class UIElementHeaderPage: RsUI.Page {
    let name: String
    let bg: SolidColorBrush

    init(name: String, bg: SolidColorBrush) {
        self.name = name
        self.bg = bg
    }

    var url: URL { URL(string: "rs://test-frame/uielem/\(name)")! }
    var title: String { name }

    // Header 用 XAML 加载，避免命令式 StackPanel/TextBlock 长链。
    var header: Any? {
        let escapedName = escape(name)
        let xaml = """
            <StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                        Orientation="Horizontal" Spacing="12">
                <TextBlock Text="UIElement Header" FontWeight="SemiBold"/>
                <TextBlock Text="\(escapedName)" Opacity="0.7"/>
            </StackPanel>
            """
        return (try? XamlReader.load(xaml)) as? UIElement
    }

    var content: UIElement {
        return make(name: name, subtitle: "header.kind = UIElement", bg: bg)
    }
}

private final class NilHeaderPage: RsUI.Page {
    let name: String
    let bg: SolidColorBrush

    init(name: String, bg: SolidColorBrush) {
        self.name = name
        self.bg = bg
    }

    var url: URL { URL(string: "rs://test-frame/nil/\(name)")! }
    var title: String { name }
    var header: Any? { nil }

    var content: UIElement {
        return make(name: name, subtitle: "header.kind = nil (content fills)", bg: bg)
    }
}

/// 用 XAML 字符串构建内容卡片：彩色 Border + 内部 StackPanel + 两个 TextBlock。
/// 颜色用 `#AARRGGBB` 十六进制字符串嵌入 XAML，避免运行时再设置画刷。
private func make(name: String, subtitle: String, bg: SolidColorBrush) -> UIElement {
    let escapedName = escape(name)
    let escapedSub = escape(subtitle)
    // SolidColorBrush 的 Color 在运行时才知道（来自调色板），故把 ARGB 拼成 XAML 颜色字面量。
    let colorHex = String(
        format: "#%02X%02X%02X%02X",
        bg.color.a, bg.color.r, bg.color.g, bg.color.b)
    let xaml = """
        <Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
            <Border Background="\(colorHex)"
                    Margin="16,0,16,16" Padding="24,24,24,24" CornerRadius="8">
                <StackPanel Spacing="6">
                    <TextBlock Text="\(escapedName)" FontSize="24" FontWeight="SemiBold"/>
                    <TextBlock Text="\(escapedSub)" Opacity="0.7"/>
                </StackPanel>
            </Border>
        </Grid>
        """
    return (try? XamlReader.load(xaml)) as! UIElement
}

/// 把可能影响 XAML 解析的字串做最小转义。XamlReader.load 走 XML 解析器，
/// `&`、`<`、`>`、`"` 必须转义；`#` 在属性值内合法无需处理。
private func escape(_ s: String) -> String {
    // 拼接两段字面量构建 XML 实体，避免编辑器对完整实体的处理。
    let amp = "&" + "amp;"
    let lt = "&" + "lt;"
    let gt = "&" + "gt;"
    let quot = "&" + "quot;"
    return
        s
        .replacingOccurrences(of: "&", with: amp)
        .replacingOccurrences(of: "<", with: lt)
        .replacingOccurrences(of: ">", with: gt)
        .replacingOccurrences(of: "\"", with: quot)
}
