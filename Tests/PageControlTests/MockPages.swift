import Foundation
import UWP
import WinUI

@testable import RsUI

// MARK: - Test Page factory

// 用 static 而非实例属性：init 里 super.init() 之前不能 dispatch self 方法，
// static 计数器/调色板索引供静态 makePage 在构造期也能安全复用。本窗口全进程唯一。
var counter = 0
var colorCycle: UInt32 = 0
// 复用按钮：同一个 Grid 实例反复被不同 Page 返回，验证 UIElement 单 parent 重绑定。
let reusedGrid = Grid()

enum HeaderKind { case string, uiElement, nilHeader }

// MARK: - Concrete test pages
func makePage(
    name: String,
    headerKind: HeaderKind,
    effect: SlideNavigationTransitionEffect,
    reuseGrid: Bool,
    reusedGrid: Grid
) -> RsUI.Page {
    // 循环颜色用肉眼分辨转场
    let palette: [(r: UInt8, g: UInt8, b: UInt8)] = [
        (0xE6, 0xF2, 0xFB), (0xFB, 0xF3, 0xE6), (0xF3, 0xE6, 0xFB),
        (0xE6, 0xFB, 0xF3), (0xFB, 0xE6, 0xF3), (0xF3, 0xFB, 0xE6),
    ]
    let rgb = palette[Int(colorCycle % UInt32(palette.count))]
    colorCycle += 1
    let bg = SolidColorBrush(UWP.Color(a: 0xFF, r: rgb.r, g: rgb.g, b: rgb.b))
    let reused: Grid? = reuseGrid ? reusedGrid : nil

    switch headerKind {
    case .string:
        return StringHeaderPage(name: name, bg: bg, reusedGrid: reused)
    case .uiElement:
        return UIElementHeaderPage(name: name, bg: bg, reusedGrid: reused)
    case .nilHeader:
        return NilHeaderPage(name: name, bg: bg, reusedGrid: reused)
    }
}

/// 用 XAML 字符串构建内容卡片：彩色 Border + 内部 StackPanel + 两个 TextBlock。
/// 颜色用 `#AARRGGBB` 十六进制字符串嵌入 XAML，避免运行时再设置画刷。
func make(name: String, subtitle: String, bg: SolidColorBrush) -> UIElement {
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
    if let view = (try? XamlReader.load(xaml)) as? UIElement { return view }

    // 兜底：再走一次结果不带颜色的最小命令式构造，保证 page 始终有 content。
    let grid = Grid()
    let border = Border()
    border.background = bg
    border.margin = Thickness(left: 16, top: 0, right: 16, bottom: 16)
    border.padding = Thickness(left: 24, top: 24, right: 24, bottom: 24)
    let stack = StackPanel()
    stack.spacing = 6
    let title = TextBlock()
    title.text = name
    title.fontSize = 24
    let sub = TextBlock()
    sub.text = subtitle
    sub.opacity = 0.7
    stack.children.append(title)
    stack.children.append(sub)
    border.child = stack
    grid.children.append(border)
    return grid
}

private final class StringHeaderPage: RsUI.Page {
    let name: String
    let bg: SolidColorBrush
    let reusedGrid: Grid?

    init(name: String, bg: SolidColorBrush, reusedGrid: Grid?) {
        self.name = name
        self.bg = bg
        self.reusedGrid = reusedGrid
    }

    var url: URL { URL(string: "rs://test-frame/string/\(name)")! }
    var title: String { name }
    var header: Any? { "String Header — \(name)" }

    var content: UIElement {
        if let reusedGrid { return reusedGrid }
        return make(name: name, subtitle: "header.kind = String", bg: bg)
    }
}

private final class UIElementHeaderPage: RsUI.Page {
    let name: String
    let bg: SolidColorBrush
    let reusedGrid: Grid?

    init(name: String, bg: SolidColorBrush, reusedGrid: Grid?) {
        self.name = name
        self.bg = bg
        self.reusedGrid = reusedGrid
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
        if let panel = (try? XamlReader.load(xaml)) as? UIElement { return panel }
        // 兜底：返回 nil header，与 NilHeaderPage 行为一致，避免 render 抛异常。
        return nil
    }

    var content: UIElement {
        if let reusedGrid { return reusedGrid }
        return make(name: name, subtitle: "header.kind = UIElement", bg: bg)
    }
}

private final class NilHeaderPage: RsUI.Page {
    let name: String
    let bg: SolidColorBrush
    let reusedGrid: Grid?

    init(name: String, bg: SolidColorBrush, reusedGrid: Grid?) {
        self.name = name
        self.bg = bg
        self.reusedGrid = reusedGrid
    }

    var url: URL { URL(string: "rs://test-frame/nil/\(name)")! }
    var title: String { name }
    var header: Any? { nil }

    var content: UIElement {
        if let reusedGrid { return reusedGrid }
        return make(name: name, subtitle: "header.kind = nil (content fills)", bg: bg)
    }
}

// MARK: - Test page content factory (XAML-loaded)

/// 把可能影响 XAML 解析的字串做最小转义。XamlReader.load 走 XML 解析器，
/// `&`、`<`、`>`、`"` 必须转义；`#` 在属性值内合法无需处理。
func escape(_ s: String) -> String {
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
