import Foundation
import UWP
import WinUI
import RsUI

func featurePageHeader(title: String, description: String) -> UIElement {
    let container = StackPanel()
    container.padding = Thickness(left: 0, top: 0, right: 0, bottom: 16)

    let titleBlock = TextBlock()
    titleBlock.text = title
    container.children.append(titleBlock)

    let subtitleBlock = TextBlock()
    subtitleBlock.text = description
    subtitleBlock.fontSize = 14
    subtitleBlock.textWrapping = .wrap
    subtitleBlock.foreground = SolidColorBrush(App.context.theme.isDark
        ? UWP.Color(a: 255, r: 180, g: 180, b: 180)
        : UWP.Color(a: 255, r: 100, g: 100, b: 100))
    container.children.append(subtitleBlock)

    return container
}

func featurePageContent(_ cards: [UIElement]) -> UIElement {
    let stack = StackPanel()
    stack.spacing = 12
    for card in cards {
        stack.children.append(card)
    }

    let scroll = ScrollViewer()
    scroll.verticalScrollBarVisibility = .auto
    scroll.content = stack

    let root = Grid()
    root.padding = Thickness(left: 40, top: 0, right: 40, bottom: 32)
    root.children.append(scroll)
    return root
}
