import Foundation
import UWP
import WinUI
import RsUI

// MARK: - Shared factories

/// 取当前主题字典中的 Fluent token 画刷（主题切换后由页面重建自然刷新）。
func themeBrush(_ key: String) -> Brush? {
    Application.current.resources?.lookup(key) as? Brush
}

/// 次要文字（说明/结果回显）。用主题资源替代硬编码灰色，跟随明暗主题与高对比度。
func makeCaption(_ text: String) -> TextBlock {
    let block = TextBlock()
    block.text = text
    block.fontSize = 12
    block.textWrapping = .wrap
    block.foreground = themeBrush("TextFillColorSecondaryBrush")
    return block
}

/// 分组小节标题。
func makeSectionTitle(_ text: String) -> TextBlock {
    let title = TextBlock()
    title.text = text
    title.fontSize = 14
    return title
}

/// 分组小节副标题（比 caption 再弱一档）。
func makeSectionSubtitle(_ text: String) -> TextBlock {
    let subtitle = TextBlock()
    subtitle.text = text
    subtitle.fontSize = 12
    subtitle.textWrapping = .wrap
    subtitle.foreground = themeBrush("TextFillColorTertiaryBrush")
    return subtitle
}

/// 可点击的整卡按钮（跳转卡/动作卡的公共形态）。
func makeClickableCard(
    glyph: String,
    header: String,
    description: String,
    onClick: @escaping () -> Void
) -> SettingsCard {
    let card = SettingsCard(
        headerIconGlyph: glyph,
        header: header,
        description: description
    )
    card.isClickEnabled = true
    card.click.addHandler { _, _ in
        onClick()
    }
    return card
}

// MARK: - Page chrome

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
    subtitleBlock.foreground = themeBrush("TextFillColorSecondaryBrush")
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
