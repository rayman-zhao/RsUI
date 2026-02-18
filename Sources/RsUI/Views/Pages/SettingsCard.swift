import UWP
import WinUI

public func buildSettingsCard(title: String, content: [WinUI.UIElement]) -> WinUI.StackPanel {
    let isDark = App.context.theme.isDark
    // let titleForeground = WinUI.SolidColorBrush(isDark
    //         ? UWP.Color(a: 255, r: 232, g: 234, b: 242)
    //         : UWP.Color(a: 255, r: 23, g: 26, b: 32))
    let cardBrush = isDark
        ? WinUI.SolidColorBrush(UWP.Color(a: 255, r: 33, g: 37, b: 45))
        : WinUI.SolidColorBrush(UWP.Color(a: 255, r: 255, g: 255, b: 255))
    let cardBorderBrush = WinUI.SolidColorBrush(isDark
        ? UWP.Color(a: 255, r: 60, g: 63, b: 78)
        : UWP.Color(a: 255, r: 224, g: 228, b: 236))

    let card = WinUI.StackPanel()
    card.orientation = .vertical
    card.spacing = 0

    let label = WinUI.TextBlock()
    //label.foreground = titleForeground
    label.text = title
    label.fontSize = 20
    label.fontWeight = UWP.FontWeights.semiBold
    label.margin = WinUI.Thickness(left: 0, top: 0, right: 0, bottom: 4)
    card.children.append(label)

    let border = WinUI.Border()
    border.cornerRadius = WinUI.CornerRadius(topLeft: 20, topRight: 20, bottomRight: 20, bottomLeft: 20)
    border.background = cardBrush
    border.borderBrush = cardBorderBrush
    border.borderThickness = WinUI.Thickness(left: 1, top: 1, right: 1, bottom: 1)
    border.padding = WinUI.Thickness(left: 20, top: 12, right: 20, bottom: 12)
    border.margin = WinUI.Thickness(left: 0, top: 0, right: 0, bottom: 0)

    let stack = WinUI.StackPanel()
    stack.orientation = .vertical
    stack.spacing = 0

    for item in content {
        if stack.children.count > 0 {
            let divider = WinUI.Border()
            divider.height = 1
            divider.margin = WinUI.Thickness(left: 72, top: 16, right: 0, bottom: 16)
            divider.background = WinUI.SolidColorBrush(isDark
                ? UWP.Color(a: 255, r: 52, g: 57, b: 70)
                : UWP.Color(a: 255, r: 230, g: 232, b: 236))
            stack.children.append(divider)
        }
        stack.children.append(item)
    }

    border.child = stack
    card.children.append(border)
    return card
}
