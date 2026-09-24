import Foundation
import Observation
import RsUI
import UWP
import WinUI

/// AppearancePage 的 ViewModel —— UI 状态的唯一事实来源。
/// 事件处理器只改 VM；控件刷新全部由 `startObserving` 观察流驱动，
/// 不在事件里直接改控件（AGENTS「UI & MVVM Conventions」的示范形态）。
@Observable
final class AppearanceViewModel {
    var isDarkTheme: Bool {
        get { App.context.theme == .dark }
        set { App.context.theme = newValue ? .dark : .light }
    }

    var isChinese: Bool {
        get { App.context.language == .zh_CN }
        set { App.context.language = newValue ? .zh_CN : .en_US }
    }
}

final class AppearancePage: RsUI.Page {
    var context: WindowContext
    private let viewModel = AppearanceViewModel()
    // content 每次重建（主题/语言切换）都会换一批控件：先取消上一批观察 Task，
    // 再为新一批控件挂观察，避免旧 Task 持续更新已卸载的控件。
    private var observingTasks: [Task<Void, Never>] = []

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextDidChange(to context: WindowContext) {
        self.context = context
    }

    let url = URL(string: "rs://\(sampleModuleID)/appearance")!
    var title: String { tr("Appearance") }

    var header: Any? {
        featurePageHeader(
            title: tr("Theme & Language"),
            description: tr(
                "App.context.theme and App.context.language are @Observable. Setting them rebuilds the chrome of every open window and persists to preferences."
            )
        )
    }

    var content: WinUI.UIElement {
        observingTasks.forEach { $0.cancel() }
        observingTasks.removeAll()

        let themeToggle = ToggleSwitch()
        themeToggle.isOn = viewModel.isDarkTheme
        themeToggle.onContent = tr("Dark")
        themeToggle.offContent = tr("Light")
        themeToggle.toggled.addHandler { [weak viewModel] sender, _ in
            guard let toggle = sender as? ToggleSwitch, let viewModel else { return }
            viewModel.isDarkTheme = toggle.isOn
        }
        observingTasks.append(
            startObserving { [viewModel] in viewModel.isDarkTheme } onChanged: { _, isDark in
                themeToggle.isOn = isDark
                return true
            })

        let themeCard = SettingsCard(
            headerIconGlyph: "\u{E771}",
            header: tr("Theme"),
            description: tr("Sets App.context.theme."),
            content: themeToggle
        )

        let langToggle = ToggleSwitch()
        langToggle.isOn = viewModel.isChinese
        langToggle.onContent = "中文"
        langToggle.offContent = "EN"
        langToggle.toggled.addHandler { [weak viewModel] sender, _ in
            guard let toggle = sender as? ToggleSwitch, let viewModel else { return }
            viewModel.isChinese = toggle.isOn
        }
        observingTasks.append(
            startObserving { [viewModel] in viewModel.isChinese } onChanged: { _, isChinese in
                langToggle.isOn = isChinese
                return true
            })

        let langCard = SettingsCard(
            headerIconGlyph: "\u{F2B7}",
            header: tr("Language"),
            description: tr(
                "Sets App.context.language; the tr() helper flags untranslated keys when in zh_CN."),
            content: langToggle
        )

        return featurePageContent([themeCard, langCard])
    }
}
