import Foundation
import UWP
import WinUI
import RsUI

/// 演示页面，只有展示各种静态信息，表示使用自定义的NavigationViewItem可以工作正常
final class ArbitaryPage: RsUI.Page {
    var url: URL {
        return URL(string: "rs://arbitrary")!
    }

    var header: Any? {
        let container = StackPanel()
        container.padding = Thickness(left: 0, top: 0, right: 0, bottom: 32)
        
        // 欢迎标题
        let titleBlock = TextBlock()
        titleBlock.text = tr("Arbitrary Page")
        container.children.append(titleBlock)
        
        // 副标题
        let subtitleBlock = TextBlock()
        subtitleBlock.text = tr("A demonstration page with various UI components")
        subtitleBlock.fontSize = 14
        subtitleBlock.foreground = SolidColorBrush(App.context.theme.isDark ? 
            UWP.Color(a: 255, r: 180, g: 180, b: 180) : 
            UWP.Color(a: 255, r: 100, g: 100, b: 100))
        container.children.append(subtitleBlock)

        return container
    }

    var content: WinUI.UIElement {
        let root = WinUI.Grid()
        root.padding = Thickness(left: 40, top: 0, right: 40, bottom: 32)
        
        // 主容器
        let mainContainer = StackPanel()
        mainContainer.spacing = 24
        mainContainer.horizontalAlignment = .stretch
        mainContainer.verticalAlignment = .top
        
        // 信息卡片区域
        let infoSection = createInfoSection()
        mainContainer.children.append(infoSection)
        mainContainer.children.append(createSeparator())
        
        // 操作按钮区域
        let actionSection = createActionSection()
        mainContainer.children.append(actionSection)
        mainContainer.children.append(createSeparator())
        
        // 统计卡片
        let statsSection = createStatsSection()
        mainContainer.children.append(statsSection)
        
        root.children.append(mainContainer)
        return root
    }
    
    private func createSeparator() -> UIElement {
        let border = Border()
        border.height = 1
        border.horizontalAlignment = .stretch
        border.background = SolidColorBrush(App.context.theme.isDark ? 
            UWP.Color(a: 40, r: 255, g: 255, b: 255) : 
            UWP.Color(a: 40, r: 0, g: 0, b: 0))
        return border
    }
    
    private func createInfoSection() -> UIElement {
        let card = Border()
        card.background = SolidColorBrush(App.context.theme.isDark ? 
            UWP.Color(a: 255, r: 40, g: 40, b: 40) : 
            UWP.Color(a: 255, r: 250, g: 250, b: 250))
        card.cornerRadius = CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
        card.padding = Thickness(left: 20, top: 16, right: 20, bottom: 16)
        
        let stack = StackPanel()
        stack.spacing = 12
        
        // 卡片标题
        let cardTitle = TextBlock()
        cardTitle.text = "ℹ️ Module Information"
        cardTitle.fontSize = 18
        cardTitle.fontWeight = FontWeights.semiBold
        stack.children.append(cardTitle)
        
        // 信息项
        stack.children.append(createInfoItem("Module ID:", "arbitrary"))
        stack.children.append(createInfoItem("Status:", "Active"))
        stack.children.append(createInfoItem("Theme:", App.context.theme == .dark ? "Dark" : "Light"))
        stack.children.append(createInfoItem("Language:", App.context.language == .en_US ? "English" : "简体中文"))
        
        card.child = stack
        return card
    }
    
    private func createInfoItem(_ label: String, _ value: String) -> UIElement {
        let grid = Grid()
        
        let col1 = ColumnDefinition()
        col1.width = GridLength(value: 120, gridUnitType: .pixel)
        grid.columnDefinitions.append(col1)
        
        let col2 = ColumnDefinition()
        col2.width = GridLength(value: 1, gridUnitType: .star)
        grid.columnDefinitions.append(col2)
        
        let labelBlock = TextBlock()
        labelBlock.text = label
        labelBlock.foreground = SolidColorBrush(App.context.theme.isDark ? 
            UWP.Color(a: 255, r: 160, g: 160, b: 160) : 
            UWP.Color(a: 255, r: 120, g: 120, b: 120))
        try? Grid.setColumn(labelBlock, 0)
        grid.children.append(labelBlock)
        
        let valueBlock = TextBlock()
        valueBlock.text = value
        valueBlock.fontWeight = FontWeights.semiBold
        try? Grid.setColumn(valueBlock, 1)
        grid.children.append(valueBlock)
        
        return grid
    }
    
    private func createActionSection() -> UIElement {
        let stack = StackPanel()
        stack.spacing = 12
        
        let sectionTitle = TextBlock()
        sectionTitle.text = "⚡ Quick Actions"
        sectionTitle.fontSize = 18
        sectionTitle.fontWeight = FontWeights.semiBold
        sectionTitle.margin = Thickness(left: 0, top: 8, right: 0, bottom: 8)
        stack.children.append(sectionTitle)
        
        let buttonPanel = StackPanel()
        buttonPanel.orientation = .horizontal
        buttonPanel.spacing = 12
        
        buttonPanel.children.append(createActionButton("Refresh", "\u{E72C}"))
        buttonPanel.children.append(createActionButton("Settings", "\u{E713}"))
        buttonPanel.children.append(createActionButton("Export", "\u{E74E}"))
        
        stack.children.append(buttonPanel)
        return stack
    }
    
    private func createActionButton(_ text: String, _ glyph: String) -> UIElement {
        let button = Button()
        button.padding = Thickness(left: 16, top: 10, right: 16, bottom: 10)
        button.cornerRadius = CornerRadius(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
        
        let buttonStack = StackPanel()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        
        let icon = FontIcon()
        icon.glyph = glyph
        icon.fontSize = 16
        buttonStack.children.append(icon)
        
        let textBlock = TextBlock()
        textBlock.text = text
        buttonStack.children.append(textBlock)
        
        button.content = buttonStack
        return button
    }
    
    private func createStatsSection() -> UIElement {
        let grid = Grid()
        grid.columnSpacing = 16
        grid.margin = Thickness(left: 0, top: 8, right: 0, bottom: 0)
        
        for _ in 0..<3 {
            let col = ColumnDefinition()
            col.width = GridLength(value: 1, gridUnitType: .star)
            grid.columnDefinitions.append(col)
        }
        
        let stats = [
            ("📊", "Total Items", "1,234"),
            ("⏱️", "Active Time", "12h 34m"),
            ("✅", "Completed", "89%")
        ]
        
        for (index, stat) in stats.enumerated() {
            let card = createStatCard(icon: stat.0, title: stat.1, value: stat.2)
            try? Grid.setColumn(card, Int32(index))
            grid.children.append(card)
        }
        
        return grid
    }
    
    private func createStatCard(icon: String, title: String, value: String) -> Border {
        let card = Border()
        card.background = SolidColorBrush(App.context.theme.isDark ? 
            UWP.Color(a: 255, r: 45, g: 45, b: 45) : 
            UWP.Color(a: 255, r: 248, g: 248, b: 250))
        card.cornerRadius = CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
        card.padding = Thickness(left: 16, top: 16, right: 16, bottom: 16)
        
        let stack = StackPanel()
        stack.spacing = 8
        
        let iconBlock = TextBlock()
        iconBlock.text = icon
        iconBlock.fontSize = 24
        stack.children.append(iconBlock)
        
        let titleBlock = TextBlock()
        titleBlock.text = title
        titleBlock.fontSize = 12
        titleBlock.foreground = SolidColorBrush(App.context.theme.isDark ? 
            UWP.Color(a: 255, r: 160, g: 160, b: 160) : 
            UWP.Color(a: 255, r: 120, g: 120, b: 120))
        stack.children.append(titleBlock)
        
        let valueBlock = TextBlock()
        valueBlock.text = value
        valueBlock.fontSize = 20
        valueBlock.fontWeight = FontWeights.bold
        stack.children.append(valueBlock)
        
        card.child = stack
        return card
    }
}
