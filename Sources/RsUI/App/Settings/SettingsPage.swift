import Foundation
import WindowsFoundation
import WinUI
import CppWinRT
import RsHelper

fileprivate func tr(_ keyAndValue: String) -> String {
    return App.context.tr(keyAndValue, "SettingsPage")
}

/// 设置页面类，管理主题和语言偏好设置
class SettingsPage: Page {
    static let url = URL(string: "rs://ui/settings")!

    var url: URL {
        return SettingsPage.url
    }
    var header: Any? {
        return tr("title")
    }

    var content: UIElement {
        let mainStackPanel = WinUI.StackPanel()
        mainStackPanel.orientation = .vertical
        mainStackPanel.spacing = 30
        mainStackPanel.padding = WinUI.Thickness(left: 32, top: 40, right: 32, bottom: 40)

        /// MARK: - 外观
        mainStackPanel.children.append(SettingsGroup(tr("personalizationSection"), [themeCard, languageCard]))
        
        /// MARK: - 各个模块
        for module in App.context.modules {
            if let group = module.settingsGroupRequired() {
                mainStackPanel.children.append(SettingsGroup(group.title, group.cards))
            }
        }

        /// MARK: - 关于
        let year = Calendar.current.component(.year, from: Date())
        let copyright = tr("copyright").replacingOccurrences(of: "%lld", with: "\(year)").replacingOccurrences(of: "%@", with: App.context.groupName)
        let aboutCard = SettingsExpander(
            App.context.iconPath ?? "",
            App.context.productName,
            copyright,
            Bundle.main.executableURL?.version ?? "",
            [dependenciesCard]
        )
        mainStackPanel.children.append(SettingsGroup(tr("AboutTitle"), [aboutCard]))

        /// MARK: - 总装视图
        let scrollViewer = ScrollViewer()
        scrollViewer.verticalScrollBarVisibility = .auto
        scrollViewer.content = mainStackPanel
        scrollViewer.maxWidth = 1200
        return scrollViewer
    }

    private var themeCard: SettingsCard {
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

        return SettingsCard("\u{E790}", tr("theme"), tr("themeDescription"), combo)
    }

    private var languageCard: SettingsCard {
        let combo = WinUI.ComboBox()
        combo.minWidth = 160
        combo.maxWidth = 220
        combo.horizontalAlignment = .stretch
        combo.fontSize = 14
        combo.padding = WinUI.Thickness(left: 12, top: 6, right: 12, bottom: 6)
        combo.itemsSource = single_threaded_vector_inspectable(AppLanguage.allCases.map { $0.displayName })
        combo.selectedIndex = Int32(AppLanguage.allCases.firstIndex(of: App.context.language) ?? 0)
        combo.selectionChanged.addHandler { sender, _ in
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

        return SettingsCard("\u{E775}", tr("language"), tr("languageDescription"), combo)
    }

    private var dependenciesCard: SettingsCard {
        let wasdk = HyperlinkButton()
        wasdk.content = "Windows App SDK \(App.context.winAppSDKVersion)"
        wasdk.navigateUri = Uri("https://aka.ms/windowsappsdk")
        wasdk.padding = WinUI.Thickness(left: 0, top: 4, right: 0, bottom: 4)

        let winui = HyperlinkButton()
        winui.content = "WinUI 3"
        winui.navigateUri = Uri("https://aka.ms/winui")
        winui.padding = WinUI.Thickness(left: 0, top: 4, right: 0, bottom: 4)

        let winrt = HyperlinkButton()
        winrt.content = "Swift/WinRT"
        winrt.navigateUri = Uri("https://github.com/thebrowsercompany/swift-winrt")
        winrt.padding = WinUI.Thickness(left: 0, top: 4, right: 0, bottom: 4)

        let depends = WinUI.StackPanel()
        depends.children.append(wasdk)
        depends.children.append(winui)
        depends.children.append(winrt)
        
        return SettingsCard(tr("Dependencies & references"), depends)
    }
}
