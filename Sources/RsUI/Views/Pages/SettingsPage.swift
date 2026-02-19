import Foundation
import UWP
import WinUI
import CppWinRT

fileprivate func tr(_ keyAndValue: String) -> String {
    return App.context.tr(keyAndValue, "SettingsPage")
}

/// 设置页面类，管理主题和语言偏好设置
class SettingsPage: AppPage {
    private let root = WinUI.Grid()
    var rootView: WinUI.UIElement { root }

    func onAppearanceChanged() {
        setupUI()
    }

    init(context: PageContext) {
        setupUI()
    }
    deinit {
        print("###SettingsPage deinit")
    }
    
    /// 初始化用户界面，包括主题和语言选择器
    private func setupUI() {
        root.children.clear()
        // ??? root.requestedTheme = App.context.theme.elementTheme

        // 主滚动视图
        let scrollViewer = WinUI.ScrollViewer()
        scrollViewer.verticalScrollMode = .enabled
        scrollViewer.horizontalScrollMode = .disabled
        
        let mainStackPanel = WinUI.StackPanel()
        mainStackPanel.orientation = .vertical
        mainStackPanel.spacing = 16
        mainStackPanel.padding = WinUI.Thickness(left: 32, top: 40, right: 32, bottom: 0)
        
        // 设置内容标题
        let titleBlock = WinUI.TextBlock()
        titleBlock.text = tr("title")
        titleBlock.fontSize = 32
        titleBlock.fontWeight = UWP.FontWeights.semiBold
        titleBlock.margin = WinUI.Thickness(left: 0, top: 0, right: 0, bottom: 8)
        mainStackPanel.children.append(titleBlock)

        let card = buildPersonalizationCard()
        mainStackPanel.children.append(card)
        
        for module in App.context.modules {
            if let card = module.makeSettingsCard() {
                mainStackPanel.children.append(card)
            }
        }

        scrollViewer.content = mainStackPanel
        root.children.append(scrollViewer)
        // ??? try? WinUI.Grid.setRow(scrollViewer, 0)
    }

    private func buildPersonalizationCard() -> WinUI.StackPanel {
        // 主题行
        let combo = WinUI.ComboBox()
        combo.minWidth = 160
        combo.maxWidth = 220
        combo.horizontalAlignment = .stretch
        combo.fontSize = 14
        combo.padding = WinUI.Thickness(left: 12, top: 6, right: 12, bottom: 6)
        combo.itemsSource = single_threaded_vector_inspectable([tr("lightMode"), tr("darkMode")])
        combo.selectedIndex = App.context.theme.isDark ? Int32(1) : Int32(0)
        combo.selectionChanged.addHandler { sender, _ in
            let theme = (sender as! WinUI.ComboBox).selectedIndex == 1 ? AppTheme.dark : AppTheme.light
            if theme != App.context.theme {
                App.context.theme = theme
            }
        }

        let themeRow = buildSettingsRow(
            iconGlyph: "\u{E790}",
            title: tr("theme"),
            description: tr("themeDescription"),
            control: combo
        ) 

        // 语言行
        let languageCombo = WinUI.ComboBox()
        languageCombo.minWidth = 160
        languageCombo.maxWidth = 220
        languageCombo.horizontalAlignment = .stretch
        languageCombo.fontSize = 14
        languageCombo.padding = WinUI.Thickness(left: 12, top: 6, right: 12, bottom: 6)
        languageCombo.itemsSource = single_threaded_vector_inspectable(AppLanguage.allCases.map { $0.displayName })
        languageCombo.selectedIndex = Int32(AppLanguage.allCases.firstIndex(of: App.context.language) ?? 0)
        languageCombo.selectionChanged.addHandler { sender, _ in
            let index = (sender as! WinUI.ComboBox).selectedIndex
            for (i, language) in AppLanguage.allCases.enumerated() {
                if i == index {
                    if language != App.context.language {
                        App.context.language = language
                    }
                    break
                }
            }
        }

        let languageRow = buildSettingsRow(
            iconGlyph: "\u{E775}",
            title: tr("language"),
            description: tr("languageDescription"),
            control: languageCombo
        )

        return buildSettingsCard(title: tr("personalizationSection"), content: [themeRow, languageRow])      
    }
}