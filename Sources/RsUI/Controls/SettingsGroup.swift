import UWP
import WinUI

public class SettingsGroup: StackPanel {
    public init(_ title: String, _ cards: [WinUI.UIElement]) {
        super.init()

        self.orientation = .vertical
        self.spacing = 4

        let label = WinUI.TextBlock()
        label.text = title
        label.fontSize = 15
        label.fontWeight = FontWeights.semiBold
        label.margin = WinUI.Thickness(left: 0, top: 0, right: 0, bottom: 8)
        self.children.append(label)

        cards.forEach { self.children.append($0) }
    }
}
