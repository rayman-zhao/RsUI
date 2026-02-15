import Foundation
import WinUI
import UWP
import WindowsFoundation
import Observation

fileprivate func tr(_ keyAndValue: String) -> String {
    return App.context.tr(keyAndValue, "SettingsPage")
}

/// 设置页面类，管理主题和语言偏好设置
class SettingsPage: AppPage {
    private let root = WinUI.Grid()
    
    private let viewModel: MainWindowViewModel
    
    // MARK: - UI 控件
    
    private var titleBlock: WinUI.TextBlock!
    private var personalizationLabel: WinUI.TextBlock!
    private var themeComboBox: WinUI.ComboBox?
    private var languageComboBox: WinUI.ComboBox?
    private var statusText: WinUI.TextBlock!
    private var themeTitleLabel: WinUI.TextBlock?
    private var themeDescriptionLabel: WinUI.TextBlock?
    private var languageTitleLabel: WinUI.TextBlock?
    private var languageDescriptionLabel: WinUI.TextBlock?
    private var personalizationCard: WinUI.Border?
    private var lightThemeItem: WinUI.ComboBoxItem?
    private var darkThemeItem: WinUI.ComboBoxItem?
    private var languageItems: [(language: AppLanguage, item: WinUI.ComboBoxItem)] = []
    private var isUpdatingThemeUI = false
    private var isUpdatingLanguageUI = false
    private var toggleRows: [ToggleRowBinding] = []
    private var personalizationDividers: [WinUI.Border] = []
    
    // 模块注册的设置项
    private var moduleSectionsContainer: WinUI.StackPanel?
    private let context: PageContext

    private struct ToggleRowBinding {
        let kind: ToggleRowKind
        let titleLabel: WinUI.TextBlock
        let descriptionLabel: WinUI.TextBlock
        let toggle: WinUI.ToggleSwitch
    }

    private enum ToggleRowKind {
        case metadata
    }
    
    init(context: PageContext) {
        self.viewModel = context.viewModel
        self.context = context
        setupUI(initialLanguage: context.currentLanguage, initialTheme: context.currentTheme)
        bindEvents()
        
        // 立即应用初始状态
        applyTheme(context.currentTheme)
        updateLocalization(language: context.currentLanguage)
        
        startObserving()
    }

    var rootView: WinUI.UIElement { root }

    private func startObserving() {
        let env = Observations {
            (App.context.theme, App.context.language)
        }
        Task { [weak self] in
            for await ctx in env {
                guard let self = self else { break }
                await MainActor.run {
                    self.applyTheme(ctx.0)
                    self.updateLocalization(language: ctx.1)
                }
            }
        }
    }
    
    // MARK: - UI 初始化
    
    /// 初始化用户界面，包括主题和语言选择器
    private func setupUI(initialLanguage: AppLanguage, initialTheme: AppTheme) {
        
        // 清空根网格
        while root.children.count > 0 {
            root.children.removeAt(0)
        }

        languageItems.removeAll()
        
        // 主滚动视图
        let scrollViewer = WinUI.ScrollViewer()
        scrollViewer.verticalScrollMode = .enabled
        scrollViewer.horizontalScrollMode = .disabled
        
    let mainStackPanel = WinUI.StackPanel()
    mainStackPanel.orientation = .vertical
    mainStackPanel.spacing = 16
    mainStackPanel.padding = WinUI.Thickness(left: 32, top: 40, right: 32, bottom: 0)
        
        // 设置内容标题
        titleBlock = WinUI.TextBlock()
        titleBlock.text = tr("title")
        titleBlock.fontSize = 32
        titleBlock.fontWeight = UWP.FontWeights.semiBold
        titleBlock.margin = WinUI.Thickness(left: 0, top: 0, right: 0, bottom: 8)
        mainStackPanel.children.append(titleBlock)

    personalizationLabel = WinUI.TextBlock()
    personalizationLabel.text = tr("personalizationSection")
    personalizationLabel.fontSize = 20
    personalizationLabel.fontWeight = UWP.FontWeights.semiBold
    personalizationLabel.margin = WinUI.Thickness(left: 0, top: 0, right: 0, bottom: 4)
    mainStackPanel.children.append(personalizationLabel)
        
    let card = buildPersonalizationCard(
        initialLanguage: initialLanguage,
        initialTheme: initialTheme
    )
    card.margin = WinUI.Thickness(left: 0, top: 0, right: 0, bottom: 0)
    personalizationCard = card
    mainStackPanel.children.append(card)
        
        // 状态提示
        statusText = WinUI.TextBlock()
        statusText.textWrapping = .wrap
        statusText.text = ""
        statusText.fontSize = 14
    statusText.foreground = WinUI.SolidColorBrush(UWP.Color(a: 255, r: 0, g: 111, b: 191))
        mainStackPanel.children.append(statusText)

        // 模块扩展的设置项
        let moduleContainer = WinUI.StackPanel()
        moduleContainer.orientation = .vertical
        moduleContainer.spacing = 16
        self.moduleSectionsContainer = moduleContainer
        
        for module in App.context.modules {
            if let sectionView = module.makeSettingsSection() {
                moduleContainer.children.append(sectionView)
            }
        }

        mainStackPanel.children.append(moduleContainer)
        scrollViewer.content = mainStackPanel
        root.children.append(scrollViewer)
        try? WinUI.Grid.setRow(scrollViewer, 0)
    }
    /// 创建设置项容器（标签+描述+控件）
    private func buildPersonalizationCard(initialLanguage: AppLanguage, initialTheme: AppTheme) -> WinUI.Border {
        toggleRows.removeAll()
        personalizationDividers.removeAll()


        let card = WinUI.Border()
        card.cornerRadius = WinUI.CornerRadius(topLeft: 20, topRight: 20, bottomRight: 20, bottomLeft: 20)
        card.background = WinUI.SolidColorBrush(UWP.Color(a: 255, r: 248, g: 249, b: 252))
        card.borderThickness = WinUI.Thickness(left: 1, top: 1, right: 1, bottom: 1)
        card.borderBrush = WinUI.SolidColorBrush(UWP.Color(a: 255, r: 230, g: 232, b: 236))
        card.padding = WinUI.Thickness(left: 20, top: 12, right: 20, bottom: 12)

        let stack = WinUI.StackPanel()
        stack.orientation = .vertical
        stack.spacing = 0

        // 主题行
        let themeRow = buildRow(iconGlyph: "\u{E790}", accentColor: UWP.Color(a: 255, r: 90, g: 104, b: 255))
        themeTitleLabel = themeRow.title
        themeDescriptionLabel = themeRow.description
        themeRow.title.text = tr("theme")
        themeRow.description.text = tr("themeDescription")

        let combo = WinUI.ComboBox()
        combo.minWidth = 160
        combo.maxWidth = 220
        combo.horizontalAlignment = .stretch
        combo.fontSize = 14
        combo.padding = WinUI.Thickness(left: 12, top: 6, right: 12, bottom: 6)
        themeComboBox = combo
        configureThemeItems(selectedTheme: initialTheme)
        themeRow.control.children.append(combo)

        stack.children.append(themeRow.container)

        // 分隔线
        let divider1 = createDivider()
        stack.children.append(divider1)
        personalizationDividers.append(divider1)

        // 语言行
        let languageRow = buildRow(iconGlyph: "\u{E775}", accentColor: UWP.Color(a: 255, r: 0, g: 120, b: 215))
        languageTitleLabel = languageRow.title
        languageDescriptionLabel = languageRow.description
        languageRow.title.text = tr("language")
        languageRow.description.text = tr("languageDescription")

        let languageCombo = WinUI.ComboBox()
        languageCombo.minWidth = 160
        languageCombo.maxWidth = 220
        languageCombo.horizontalAlignment = .stretch
        languageCombo.fontSize = 14
        languageCombo.padding = WinUI.Thickness(left: 12, top: 6, right: 12, bottom: 6)
        languageComboBox = languageCombo
        configureLanguageItems(selectedLanguage: initialLanguage, displayLanguage: initialLanguage)
        languageRow.control.children.append(languageCombo)

        stack.children.append(languageRow.container)

        let dividerLanguage = createDivider()
        stack.children.append(dividerLanguage)
        personalizationDividers.append(dividerLanguage)

        // 元数据行
        let metadataRow = buildToggleRow(
            kind: .metadata,
            iconGlyph: "\u{E70A}",
            accentColor: UWP.Color(a: 255, r: 0, g: 120, b: 215),
            titleText: tr("metadataTitle"),
            descriptionText: tr("metadataDescription"),
            defaultIsOn: true
        )
        stack.children.append(metadataRow)



        card.child = stack
        personalizationCard = card
        return card
    }

    private func buildRow(iconGlyph: String, accentColor: UWP.Color) -> (container: WinUI.Grid, title: WinUI.TextBlock, description: WinUI.TextBlock, control: WinUI.StackPanel) {
        let container = WinUI.Grid()

        let iconColumn = WinUI.ColumnDefinition()
        iconColumn.width = WinUI.GridLength(value: 56, gridUnitType: .auto)
        container.columnDefinitions.append(iconColumn)

        let textColumn = WinUI.ColumnDefinition()
        textColumn.width = WinUI.GridLength(value: 1, gridUnitType: .star)
        container.columnDefinitions.append(textColumn)

        let controlColumn = WinUI.ColumnDefinition()
        controlColumn.width = WinUI.GridLength(value: 1, gridUnitType: .auto)
        container.columnDefinitions.append(controlColumn)

        let titleRow = WinUI.RowDefinition()
        titleRow.height = WinUI.GridLength(value: 1, gridUnitType: .auto)
        container.rowDefinitions.append(titleRow)

        let descRow = WinUI.RowDefinition()
        descRow.height = WinUI.GridLength(value: 1, gridUnitType: .auto)
        container.rowDefinitions.append(descRow)

        let iconBadge = WinUI.Border()
        iconBadge.width = 44
        iconBadge.height = 44
        iconBadge.cornerRadius = WinUI.CornerRadius(topLeft: 14, topRight: 14, bottomRight: 14, bottomLeft: 14)
        iconBadge.background = WinUI.SolidColorBrush(accentColor)
        iconBadge.verticalAlignment = .center
        iconBadge.horizontalAlignment = .center

        let icon = WinUI.FontIcon()
        icon.glyph = iconGlyph
        icon.fontSize = 20
        icon.foreground = WinUI.SolidColorBrush(UWP.Color(a: 255, r: 255, g: 255, b: 255))
        iconBadge.child = icon

        container.children.append(iconBadge)
        try? WinUI.Grid.setRow(iconBadge, 0)
        try? WinUI.Grid.setColumn(iconBadge, 0)
        try? WinUI.Grid.setRowSpan(iconBadge, 2)

        let titleLabel = WinUI.TextBlock()
        titleLabel.fontSize = 16
        titleLabel.fontWeight = UWP.FontWeights.semiBold
        titleLabel.margin = WinUI.Thickness(left: 16, top: 2, right: 12, bottom: 4)
        container.children.append(titleLabel)
        try? WinUI.Grid.setRow(titleLabel, 0)
        try? WinUI.Grid.setColumn(titleLabel, 1)

        let descriptionLabel = WinUI.TextBlock()
        descriptionLabel.fontSize = 13
        descriptionLabel.margin = WinUI.Thickness(left: 16, top: 0, right: 12, bottom: 0)
        descriptionLabel.textWrapping = .wrap
        container.children.append(descriptionLabel)
        try? WinUI.Grid.setRow(descriptionLabel, 1)
        try? WinUI.Grid.setColumn(descriptionLabel, 1)

        let controlHost = WinUI.StackPanel()
        controlHost.orientation = .horizontal
        controlHost.verticalAlignment = .center
        controlHost.spacing = 8
        container.children.append(controlHost)
        try? WinUI.Grid.setRow(controlHost, 0)
        try? WinUI.Grid.setColumn(controlHost, 2)
        try? WinUI.Grid.setRowSpan(controlHost, 2)

        return (container, titleLabel, descriptionLabel, controlHost)
    }

    private func buildToggleRow(
        kind: ToggleRowKind,
        iconGlyph: String,
        accentColor: UWP.Color,
        titleText: String,
        descriptionText: String,
        defaultIsOn: Bool
    ) -> WinUI.UIElement {
        let row = buildRow(iconGlyph: iconGlyph, accentColor: accentColor)
        row.title.text = titleText
        row.description.text = descriptionText

        let toggle = WinUI.ToggleSwitch()
        toggle.isOn = defaultIsOn
        toggle.onContent = tr("toggleOn") as AnyObject
        toggle.offContent = tr("toggleOff") as AnyObject
        row.control.children.append(toggle)

        toggleRows.append(
            ToggleRowBinding(
                kind: kind,
                titleLabel: row.title,
                descriptionLabel: row.description,
                toggle: toggle
            )
        )

        return row.container
    }

    private func createDivider() -> WinUI.Border {
        let divider = WinUI.Border()
        divider.height = 1
        divider.margin = WinUI.Thickness(left: 72, top: 16, right: 0, bottom: 16)
        divider.background = WinUI.SolidColorBrush(UWP.Color(a: 255, r: 230, g: 232, b: 236))
        return divider
    }
    
    // MARK: - 事件绑定
    
    /// 绑定用户交互事件
    private func bindEvents() {
        // 主题 ComboBox 选择变更
        themeComboBox?.selectionChanged.addHandler { [weak self] _, _ in
            guard let self = self, !self.isUpdatingThemeUI else { return }
            self.applyThemeSelection()
        }
        
        // 语言 ComboBox 选择变更
        languageComboBox?.selectionChanged.addHandler { [weak self] _, _ in
            guard let self = self, !self.isUpdatingLanguageUI else { return }
            self.applyLanguageSelection()
        }
    }

    /// 根据当前本地化配置重新构建主题下拉项
    private func configureThemeItems(selectedTheme: AppTheme) {
        guard let combo = themeComboBox else { return }
        guard let items = ensureItemsCollection(for: combo) else { return }

        isUpdatingThemeUI = true
        defer { isUpdatingThemeUI = false }

        items.clear()

        let lightItem = WinUI.ComboBoxItem()
        lightItem.content = tr("lightMode") as AnyObject
        items.append(lightItem)
        lightThemeItem = lightItem

        let darkItem = WinUI.ComboBoxItem()
        darkItem.content = tr("darkMode") as AnyObject
        items.append(darkItem)
        darkThemeItem = darkItem

        combo.selectedIndex = selectedTheme.isDark ? Int32(1) : Int32(0)
    }

    /// 根据目标语言重建语言下拉项
    private func configureLanguageItems(selectedLanguage: AppLanguage, displayLanguage: AppLanguage) {
        guard let combo = languageComboBox else { return }
        guard let items = ensureItemsCollection(for: combo) else { return }

        isUpdatingLanguageUI = true
        defer { isUpdatingLanguageUI = false }

        if languageItems.isEmpty {
            for language in AppLanguage.allCases {
                let item = WinUI.ComboBoxItem()
                items.append(item)
                languageItems.append((language: language, item: item))
            }
        }

        var matchedIndex: Int32 = -1
        for (index, entry) in languageItems.enumerated() {
            entry.item.content = entry.language.displayName as AnyObject
            if entry.language == selectedLanguage {
                matchedIndex = Int32(index)
            }
        }

        if matchedIndex >= 0 {
            combo.selectedIndex = matchedIndex
        } else if !languageItems.isEmpty {
            combo.selectedIndex = 0
        }
    }

    private func ensureItemsCollection(for comboBox: WinUI.ComboBox) -> WinUI.ItemCollection? {
        if let items = comboBox.items {
            return items
        }
        _ = comboBox.items
        return comboBox.items
    }

    /// 更新现有语言项的显示文本
    private func refreshLanguageItemLabels(selectedLanguage: AppLanguage, displayLanguage: AppLanguage) {
        guard let combo = languageComboBox else {
            configureLanguageItems(selectedLanguage: selectedLanguage, displayLanguage: displayLanguage)
            return
        }

        guard !languageItems.isEmpty else {
            configureLanguageItems(selectedLanguage: selectedLanguage, displayLanguage: displayLanguage)
            return
        }

        isUpdatingLanguageUI = true
        defer { isUpdatingLanguageUI = false }

        for entry in languageItems {
            entry.item.content = entry.language.displayName as AnyObject
        }

        if let index = languageItems.firstIndex(where: { $0.language == selectedLanguage }) {
            combo.selectedIndex = Int32(index)
        }
    }
    
    // MARK: - 设置处理
    
    /// 处理主题选择变更
    private func applyThemeSelection() {
        guard let combo = themeComboBox else { return }
        let selectedIndex = combo.selectedIndex
        let theme: AppTheme = selectedIndex == 1 ? .dark : .light
        guard theme != App.context.theme else { return }

        App.context.theme = theme
        statusText.text = tr("settingsSaved")
    }
    
    /// 处理语言选择变更
    private func applyLanguageSelection() {
        guard let combo = languageComboBox else { return }
        let selectedIndex = combo.selectedIndex
        
        guard languageItems.indices.contains(Int(selectedIndex)) else {
            return
        }
        let language = languageItems[Int(selectedIndex)].language
        guard language != App.context.language else { return }
        
        App.context.language = language
        statusText.text = tr("settingsSaved")
    }

    // MARK: - AppPage 协议实现
    
    func applyTheme(_ theme: AppTheme) {
        root.requestedTheme = theme.elementTheme
        // 更新主题 ComboBox 的选中状态
        configureThemeItems(selectedTheme: theme)
        updateCardAppearance(for: theme)
    }

    /// 更新页面的本地化文本
    func updateLocalization(language: AppLanguage) {
        titleBlock.text = tr("title")
        personalizationLabel.text = tr("personalizationSection")
        themeTitleLabel?.text = tr("theme")
        themeDescriptionLabel?.text = tr("themeDescription")
        languageTitleLabel?.text = tr("language")
        languageDescriptionLabel?.text = tr("languageDescription")
        
        configureThemeItems(selectedTheme: App.context.theme)
        refreshLanguageItemLabels(selectedLanguage: language, displayLanguage: language)

        for binding in toggleRows {
            switch binding.kind {
            case .metadata:
                binding.titleLabel.text = tr("metadataTitle")
                binding.descriptionLabel.text = tr("metadataDescription")
            }
            binding.toggle.onContent = tr("toggleOn") as AnyObject
            binding.toggle.offContent = tr("toggleOff") as AnyObject
        }

        if !statusText.text.isEmpty {
            statusText.text = tr("settingsSaved")
        }
    }

    private func updateCardAppearance(for theme: AppTheme) {
        let isDark = theme.isDark

        let appBackground = isDark
            ? WinUI.SolidColorBrush(UWP.Color(a: 255, r: 18, g: 21, b: 28))
            : WinUI.SolidColorBrush(UWP.Color(a: 255, r: 244, g: 246, b: 250))
        root.background = appBackground

        let cardBrush = isDark
            ? WinUI.SolidColorBrush(UWP.Color(a: 255, r: 33, g: 37, b: 45))
            : WinUI.SolidColorBrush(UWP.Color(a: 255, r: 255, g: 255, b: 255))
        personalizationCard?.background = cardBrush
        let cardBorderBrush = WinUI.SolidColorBrush(isDark
            ? UWP.Color(a: 255, r: 60, g: 63, b: 78)
            : UWP.Color(a: 255, r: 224, g: 228, b: 236))
        personalizationCard?.borderBrush = cardBorderBrush
        personalizationCard?.borderThickness = WinUI.Thickness(left: 1, top: 1, right: 1, bottom: 1)

        let titleForeground = WinUI.SolidColorBrush(isDark
            ? UWP.Color(a: 255, r: 232, g: 234, b: 242)
            : UWP.Color(a: 255, r: 23, g: 26, b: 32))
        let secondaryForeground = WinUI.SolidColorBrush(isDark
            ? UWP.Color(a: 255, r: 169, g: 173, b: 189)
            : UWP.Color(a: 255, r: 96, g: 104, b: 112))

        titleBlock.foreground = titleForeground
        personalizationLabel.foreground = titleForeground

        themeTitleLabel?.foreground = titleForeground
        languageTitleLabel?.foreground = titleForeground
        themeDescriptionLabel?.foreground = secondaryForeground
        languageDescriptionLabel?.foreground = secondaryForeground

        for binding in toggleRows {
            binding.titleLabel.foreground = titleForeground
            binding.descriptionLabel.foreground = secondaryForeground
        }

        for divider in personalizationDividers {
            divider.background = WinUI.SolidColorBrush(isDark
                ? UWP.Color(a: 255, r: 52, g: 57, b: 70)
                : UWP.Color(a: 255, r: 230, g: 232, b: 236))
        }

        statusText.foreground = WinUI.SolidColorBrush(isDark
            ? UWP.Color(a: 255, r: 102, g: 178, b: 255)
            : UWP.Color(a: 255, r: 0, g: 111, b: 191))

        // no additional dividers to update
    }

}

