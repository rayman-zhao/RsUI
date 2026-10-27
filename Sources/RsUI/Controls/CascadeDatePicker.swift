import Foundation
import WinUI
import WindowsFoundation

// MARK: - State

/// `CascadeDatePicker` 的纯逻辑状态：按天聚合 + 年/月/日级联选择规则，无 UI 依赖。
struct CascadeDatePickerState {
    /// 一天。时区语义由注入的 `Calendar` 决定，`Date` 的时间部分在聚合时截断。
    struct DayKey: Hashable {
        let year: Int
        let month: Int
        let day: Int

        init(_ date: Date, calendar: Calendar) {
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            self.init(year: comps.year!, month: comps.month!, day: comps.day!)
        }

        init(year: Int, month: Int, day: Int) {
            self.year = year
            self.month = month
            self.day = day
        }

        func date(calendar: Calendar) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }
    }

    private(set) var counts: [DayKey: Int] = [:]
    /// 按时序排列的有数据日；first / last 即 earliest / latest 候选。
    private(set) var sortedKeys: [DayKey] = []
    private(set) var selection: DayKey?

    var isEmpty: Bool { sortedKeys.isEmpty }

    /// 聚合日期（重复日期累计计数）。
    /// - Returns: 选中日是否因从新数据中消失而被清空（调用方据此发一次事件）。
    @discardableResult
    mutating func setDates(_ dates: [Date], calendar: Calendar) -> Bool {
        var aggregated: [DayKey: Int] = [:]
        for date in dates {
            aggregated[DayKey(date, calendar: calendar), default: 0] += 1
        }
        counts = aggregated
        sortedKeys = aggregated.keys.sorted {
            ($0.year, $0.month, $0.day) < ($1.year, $1.month, $1.day)
        }

        guard let selection, counts[selection] == nil else { return false }
        self.selection = nil
        return true
    }

    /// 年列条目：数据年份的连续区间（缺失年份以禁用样式占位）；无数据时仅显示 `now` 所在年。
    func years(calendar: Calendar, now: Date) -> [Int] {
        guard let first = sortedKeys.first, let last = sortedKeys.last else {
            return [calendar.component(.year, from: now)]
        }
        return Array(first.year...last.year)
    }

    func months(inYear year: Int) -> [Int] {
        Array(1...12)
    }

    func days(inYear year: Int, month: Int, calendar: Calendar) -> [Int] {
        guard
            let anchor = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let range = calendar.range(of: .day, in: .month, for: anchor)
        else { return [] }
        return Array(range)
    }

    func hasData(year: Int) -> Bool {
        sortedKeys.contains { $0.year == year }
    }

    func hasData(year: Int, month: Int) -> Bool {
        sortedKeys.contains { $0.year == year && $0.month == month }
    }

    func hasData(day key: DayKey) -> Bool {
        counts[key] != nil
    }

    func recordCount(year: Int) -> Int {
        var total = 0
        for key in sortedKeys where key.year == year {
            total += counts[key] ?? 0
        }
        return total
    }

    func recordCount(year: Int, month: Int) -> Int {
        var total = 0
        for key in sortedKeys where key.year == year && key.month == month {
            total += counts[key] ?? 0
        }
        return total
    }

    func recordCount(day key: DayKey) -> Int {
        counts[key] ?? 0
    }

    // MARK: - Selection

    /// 选中 `year`，并级联到该年第一个有数据的日（经其第一个有数据月）。
    mutating func select(year: Int) -> Bool {
        guard let key = sortedKeys.first(where: { $0.year == year }) else { return false }
        return select(key)
    }

    /// 在当前选中年内选中 `month`，并级联到该月第一个有数据的日。
    mutating func select(month: Int) -> Bool {
        guard let year = selection?.year,
            let key = sortedKeys.first(where: { $0.year == year && $0.month == month })
        else { return false }
        return select(key)
    }

    /// 选中当前选中月内的 `day`；当日无数据返回 false 且不动选择。
    mutating func select(day: Int) -> Bool {
        guard let current = selection else { return false }
        let key = DayKey(year: current.year, month: current.month, day: day)
        guard counts[key] != nil else { return false }
        return select(key)
    }

    mutating func selectEarliest() -> Bool {
        guard let key = sortedKeys.first else { return false }
        return select(key)
    }

    mutating func selectLatest() -> Bool {
        guard let key = sortedKeys.last else { return false }
        return select(key)
    }

    /// 落位选择。目标日与当前一致时返回 false（真变化才触发事件）。
    private mutating func select(_ key: DayKey) -> Bool {
        guard selection != key else { return false }
        selection = key
        return true
    }
}

// MARK: - Control

/// 数据驱动的年/月/日三列级联日期选择器（外观复刻 WinUI DatePicker 浮出层的三列形态）。
///
/// 输入一组日期（`setDates`，重复日期计为多条记录，时间部分截断到天）并按年/月/日聚合：
/// 有数据的条目可点，无数据的条目禁用置灰；点击年或月会级联选中该范围内第一个有数据的日，
/// 因此 `selectionChanged` 携带的总是一个完整日期。自然高度默认为 12 行预算——月份列
/// 始终完整显示，日至多 31 天自动分栏（≤3 栏）；可选 `maxVisibleHeight` 自定高度预算，
/// 宿主高度不足时同样自动分栏（先填满一栏再开下一栏，横向滚动兜底）。数据为空时展示
/// 当年、12 个月与 1...31 日占位（全部禁用、无选中样式，与真实月长无关，`selectedDate`
/// 仍为 nil）。初始不预选，客户端可用 `selectEarliestDate()` / `selectLatestDate()` 定位。
///
/// 基类取 `ContentControl`（同 RangeSlider / ToggleButtons）：`isEnabled` 沿可视树自动级联
/// 到全部条目，`isTabStop` 等控件语义齐备。投影类 Swift 子类的生命周期与基类选择无关
/// （同一 COM 聚合桥，树成员资格保活；按类型实证，本库 ContentControl 子类全部存活）。
open class CascadeDatePicker: ContentControl, @unchecked Sendable {
    /// 选中日变化时触发（点击条目、`selectEarliestDate()` / `selectLatestDate()`），
    /// 负载为选中的日期；`setDates` 导致选中日从数据中消失而清空时以 nil 触发。
    public let selectionChanged = EventWithArgumentHandler<CascadeDatePicker, Date?>()

    /// 条目右侧是否显示聚合计数（年/月为区间累计，日为当天条数）。默认关闭。
    public var showsRecordCounts = false {
        didSet { refreshColumns() }
    }

    /// 可见高度预算。默认 nil = 按 12 行（月份列完整显示）取自然高度；设值覆盖为指定像素
    /// 预算。宿主实际高度更小时以实际高度为准，不足时每列自动分栏。
    public var maxVisibleHeight: Double? {
        didSet {
            guard root != nil, maxVisibleHeight != oldValue else { return }
            root.maxHeight = maxVisibleHeight ?? naturalHeightBudget
            relayoutColumns()
        }
    }

    private enum Metrics {
        /// 自然形态的行数预算：12 行 = 月份列恰好完整显示；31 天则分 3 栏。
        static let naturalRows = 12
        /// 空数据时日列的占位天数（1...31），不查真实月长。
        static let emptyDisplayDays = 31
        /// Root 上下 Padding=4 的合计；高度预算与行数换算两处必须一致。
        static let rootVerticalPadding: Double = 8
        static let chevronGlyph = "\u{E76C}"
    }

    /// 12 行预算对应的控件高度（含 Root 上下 Padding 与行间距）。
    private var naturalHeightBudget: Double {
        Double(Metrics.naturalRows) * itemHeight
            + Double(Metrics.naturalRows - 1) * itemSpacing + Metrics.rootVerticalPadding
    }

    /// 条目高由控件字号推导：14px 字号对应 Segoe UI 约 20px 行高，上下各留 2px 呼吸
    /// （即默认 24px 高的紧凑密度）。下游改 `fontSize`、系统 DPI 缩放时行高随之等比
    /// 协调，而非固定像素。
    private var itemHeight: Double {
        (fontSize * 20 / 14).rounded() + 4
    }

    private var itemSpacing: Double { 2 }

    private var itemPitch: Double { itemHeight + itemSpacing }

    private enum Column: Int, CaseIterable {
        case year
        case month
        case day
    }

    private struct ItemEntry {
        let button: Button
        let chevron: FontIcon
        /// 计数徽章（InfoBadge 形态：accent 胶囊 + 反色数字。不用 InfoBadge 控件本体——
        /// 其默认模板的数值文本走 {Binding TemplatedParent}，swift-winui 无元数据提供方
        /// 会静默取空）。画刷为构建期实例，主题切换由 refreshThemeBrushes 重取。
        let badge: Border?
        /// 条目值（年/月/日数字）。
        let value: Int
    }

    private struct ColumnModel {
        /// 该列的水平分栏宿主（XAML 命名元素）。
        var host: StackPanel!
        var items: [ItemEntry] = []
        var chunks: [StackPanel] = []
        /// 内容身份（数据版本 / 选中年 / 选中月 / 计数开关）：变化才重建条目，
        /// 未变时只原地刷选中样式，保持按钮身份与焦点。
        var contentsKey = ""
        /// 未测量前的默认行数 = 不分栏（垂直完全展开），首次布局后再按实际高度校正。
        var rows = Int.max
    }

    private var state = CascadeDatePickerState()
    private let calendar = Calendar.current
    /// 数据版本号，`setDates` 递增；驱动年列 contentsKey。
    private var dataVersion = 0
    private var root: Grid!
    private var columns = [ColumnModel(), ColumnModel(), ColumnModel()]

    public nonisolated override init() {
        super.init()
        MainActor.assumeIsolated {
            setupUI()
            bindEvents()
            // 未 setDates 即上屏也以空数据形态展示（当年/12 月/31 日占位）而非空白。
            refreshColumns()
        }
    }

    // MARK: - Public API

    /// 当前选中日；nil 表示尚未选择（初始状态或数据为空）。
    public var selectedDate: Date? {
        state.selection?.date(calendar: calendar)
    }

    /// 聚合日期数据。选中日仍在新数据中则保持不变；否则清空并触发一次
    /// `selectionChanged`（负载 nil）。
    public func setDates(_ dates: [Date]) {
        dataVersion += 1
        let selectionCleared = state.setDates(dates, calendar: calendar)
        refreshColumns()
        if selectionCleared {
            selectionChanged.invoke(self, nil)
        }
    }

    /// 选中数据中最早的有数据日。数据为空返回 false。
    @discardableResult
    public func selectEarliestDate() -> Bool {
        commitSelection { $0.selectEarliest() }
    }

    /// 选中数据中最晚的有数据日。数据为空返回 false。
    @discardableResult
    public func selectLatestDate() -> Bool {
        commitSelection { $0.selectLatest() }
    }

    // MARK: - Setup

    private func setupUI() {
        let loaded: Grid = App.context.requireXaml(withString: xamlUI)
        root = loaded
        columns[Column.year.rawValue].host = loaded.requireElement("YearHost")
        columns[Column.month.rawValue].host = loaded.requireElement("MonthHost")
        columns[Column.day.rawValue].host = loaded.requireElement("DayHost")
        loaded.maxHeight = maxVisibleHeight ?? naturalHeightBudget
        content = loaded
        isTabStop = false
        horizontalAlignment = .stretch
        horizontalContentAlignment = .stretch
        verticalContentAlignment = .stretch
    }

    private func bindEvents() {
        // 分栏对可用高度敏感：首布局（loaded，此时 actualHeight 才有效）与每次尺寸变化后重排。
        root.loaded.addHandler { [weak self] _, _ in self?.relayoutColumns() }
        root.sizeChanged.addHandler { [weak self] _, _ in self?.relayoutColumns() }
        // 选中 accent 前景与徽章画刷都是构建期解析实例，主题切换后需重取重刷。
        root.actualThemeChanged.addHandler { [weak self] _, _ in
            self?.applySelectionStyles()
            self?.refreshThemeBrushes()
        }
    }

    // MARK: - Selection flow

    private func handleItemClick(_ column: Column, value: Int) {
        switch column {
        case .year: commitSelection { $0.select(year: value) }
        case .month: commitSelection { $0.select(month: value) }
        case .day: commitSelection { $0.select(day: value) }
        }
    }

    @discardableResult
    private func commitSelection(_ mutate: (inout CascadeDatePickerState) -> Bool) -> Bool {
        guard mutate(&state) else { return false }
        refreshColumns()
        selectionChanged.invoke(self, state.selection?.date(calendar: calendar))
        return true
    }

    // MARK: - Column rendering

    /// 月列/日列的展示锚点：有选中时为选中日；有数据未选中时为最早的数据日；空数据时
    /// 为"今天"。锚点只决定三列展示什么（enable 集合随数据），不产生任何选中样式——
    /// 选中高亮只认 `state.selection`。
    private var displayAnchor: CascadeDatePickerState.DayKey {
        if let selection = state.selection { return selection }
        if state.isEmpty {
            return CascadeDatePickerState.DayKey(Date(), calendar: calendar)
        }
        return state.sortedKeys.first!
    }

    /// 同步三列内容与选中样式。contentsKey 未变的列只原地刷样式（保持焦点与按钮身份），
    /// 变了的列（数据域/选中年/选中月/计数开关变化）重建条目。
    private func refreshColumns() {
        guard root != nil else { return }

        let countsFlag = showsRecordCounts ? "1" : "0"
        let yearKey = "v\(dataVersion)|c\(countsFlag)"
        if columns[Column.year.rawValue].contentsKey != yearKey {
            rebuildYearColumn()
            columns[Column.year.rawValue].contentsKey = yearKey
        }

        let anchor = displayAnchor
        // 月/日列 key 必须含数据版本：enable 集合随数据变化（如清空后同一年份的
        // 月列若沿用旧 key 会跳过重建，残留有数据时代构建的可点样式）。
        let monthKey = "v\(dataVersion)y\(anchor.year)|c\(countsFlag)"
        if columns[Column.month.rawValue].contentsKey != monthKey {
            rebuildMonthColumn()
            columns[Column.month.rawValue].contentsKey = monthKey
        }
        let dayKey = "v\(dataVersion)y\(anchor.year)m\(anchor.month)|c\(countsFlag)"
        if columns[Column.day.rawValue].contentsKey != dayKey {
            rebuildDayColumn()
            columns[Column.day.rawValue].contentsKey = dayKey
        }
        applySelectionStyles()
    }

    private func rebuildYearColumn() {
        var items: [ItemEntry] = []
        for year in state.years(calendar: calendar, now: Date()) {
            items.append(
                makeItemEntry(
                    column: .year,
                    value: year,
                    label: String(year),
                    count: state.recordCount(year: year),
                    isEnabled: state.hasData(year: year)))
        }
        replaceColumn(.year, items: items)
    }

    private func rebuildMonthColumn() {
        let anchor = displayAnchor
        let formatter = makeMonthNameFormatter()
        var items: [ItemEntry] = []
        for month in state.months(inYear: anchor.year) {
            items.append(
                makeItemEntry(
                    column: .month,
                    value: month,
                    label: monthName(month, formatter: formatter),
                    count: state.recordCount(year: anchor.year, month: month),
                    isEnabled: state.hasData(year: anchor.year, month: month)))
        }
        replaceColumn(.month, items: items)
    }

    private func rebuildDayColumn() {
        let anchor = displayAnchor
        let days =
            state.isEmpty
            ? Array(1...Metrics.emptyDisplayDays)
            : state.days(inYear: anchor.year, month: anchor.month, calendar: calendar)
        var items: [ItemEntry] = []
        for day in days {
            let key = CascadeDatePickerState.DayKey(
                year: anchor.year, month: anchor.month, day: day)
            items.append(
                makeItemEntry(
                    column: .day,
                    value: day,
                    label: String(day),
                    count: state.recordCount(day: key),
                    isEnabled: state.hasData(day: key)))
        }
        replaceColumn(.day, items: items)
    }

    private func makeItemEntry(
        column: Column, value: Int, label: String, count: Int, isEnabled: Bool
    ) -> ItemEntry {
        let button = Button()
        button.height = itemHeight
        button.cornerRadius = CornerRadius(topLeft: 4, topRight: 4, bottomRight: 4, bottomLeft: 4)
        button.padding = Thickness(left: 12, top: 0, right: 10, bottom: 0)
        button.horizontalContentAlignment = .left
        button.isEnabled = isEnabled
        try? AutomationProperties.setName(button, label)

        let panel = StackPanel()
        panel.orientation = .horizontal
        panel.spacing = 6

        let text = TextBlock()
        text.text = label
        text.verticalAlignment = .center
        panel.children.append(text)

        var badge: Border?
        if showsRecordCounts, count > 0 {
            let countText = TextBlock()
            countText.text = String(count)
            countText.fontSize = 11
            countText.horizontalAlignment = .center
            countText.verticalAlignment = .center
            // 官方 ValueInfoBadgeTextMargin（底边 2 为数字基线补偿）。
            countText.margin = Thickness(left: 4, top: 0, right: 4, bottom: 2)
            countText.foreground = Brush.fluentTheme("TextOnAccentFillColorPrimaryBrush")

            let pill = Border()
            pill.background = Brush.fluentTheme("AccentFillColorDefaultBrush")
            // 对齐官方 InfoBadge 量规：MaxHeight 16、字号 11、padding 0、全圆角 8；
            // minWidth = 高度，单数字呈 16×16 正圆，两位数起自然加宽成胶囊。
            pill.height = 16
            pill.minWidth = 16
            pill.cornerRadius = CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
            pill.verticalAlignment = .center
            pill.child = countText
            panel.children.append(pill)
            badge = pill
        }

        let chevron = FontIcon()
        chevron.glyph = Metrics.chevronGlyph
        chevron.fontSize = 12
        chevron.verticalAlignment = .center
        // 恒占布局位、未选中透明（opacity 0 而非 collapsed）：选中态切换不改变按钮
        // 内容宽，列宽与文字位置稳定不跳。
        chevron.opacity = 0
        panel.children.append(chevron)

        button.content = panel
        // 本类是挂树存活的投影子类，weak 捕获安全；强捕获会成环
        // （picker → 按钮数组 → click 闭包 → picker），Flyout 关闭后泄漏。
        button.click.addHandler { [weak self] _, _ in
            self?.handleItemClick(column, value: value)
        }
        return ItemEntry(button: button, chevron: chevron, badge: badge, value: value)
    }

    // MARK: - Selection visuals

    private func applySelectionStyles() {
        guard let selection = state.selection else {
            for column in Column.allCases {
                styleColumn(column) { _ in false }
            }
            return
        }
        styleColumn(.year) { $0 == selection.year }
        styleColumn(.month) { $0 == selection.month }
        styleColumn(.day) { $0 == selection.day }
    }

    private func styleColumn(_ column: Column, isSelected: (Int) -> Bool) {
        for item in columns[column.rawValue].items {
            setSelected(isSelected(item.value), on: item)
        }
    }

    private func setSelected(_ selected: Bool, on item: ItemEntry) {
        if selected {
            item.button.foreground = Brush.fluentTheme("AccentTextFillColorPrimaryBrush")
        } else {
            try? item.button.clearValue(Control.foregroundProperty)
        }
        item.chevron.opacity = selected ? 1 : 0
    }

    private func refreshThemeBrushes() {
        for model in columns {
            for item in model.items {
                guard let badge = item.badge, let countText = badge.child as? TextBlock
                else { continue }
                badge.background = Brush.fluentTheme("AccentFillColorDefaultBrush")
                countText.foreground = Brush.fluentTheme("TextOnAccentFillColorPrimaryBrush")
            }
        }
    }

    // MARK: - Chunked columns

    /// 整列换装：装上新条目并按当前行数重新分栏（清空重装统一在 chunkColumn）。
    private func replaceColumn(_ column: Column, items: [ItemEntry]) {
        columns[column.rawValue].items = items
        chunkColumn(column.rawValue)
    }

    private func chunkColumn(_ index: Int) {
        // 不走 detachFromVisualParent：从未挂过视觉树的子树里父级反查会静默失效
        // （实测 FrameworkElement.parent 对此类按钮返回 nil），旧子元素未解除父子
        // 关系就 append 会撞 "Element is already the child of another element" 直接
        // 崩溃。host 与 chunk 都是自己创建的面板，集合级 clear 无需父级反查。
        columns[index].host.children.clear()
        for chunk in columns[index].chunks {
            chunk.children.clear()
        }
        var chunks: [StackPanel] = []
        var current = makeChunkPanel()
        var rowCount = 0
        for item in columns[index].items {
            if rowCount == columns[index].rows {
                chunks.append(current)
                current = makeChunkPanel()
                rowCount = 0
            }
            current.children.append(item.button)
            rowCount += 1
        }
        if !columns[index].items.isEmpty {
            chunks.append(current)
        }
        for chunk in chunks {
            columns[index].host.children.append(chunk)
        }
        columns[index].chunks = chunks
    }

    private func makeChunkPanel() -> StackPanel {
        let panel = StackPanel()
        panel.orientation = .vertical
        panel.spacing = itemSpacing
        return panel
    }

    private func relayoutColumns() {
        let available: Double
        if root.actualHeight > 0 {
            available = root.actualHeight
        } else {
            available = maxVisibleHeight ?? naturalHeightBudget
        }
        let rows: Int
        if available.isInfinite {
            rows = Int.max
        } else {
            // StackPanel 不在末项后追加间距：行数判定先把间距补回去再按节距取整，
            // 否则恰好容纳全部行的宿主会被误判少一行而多余分栏。
            let usable = max(0, available - Metrics.rootVerticalPadding)
            rows = max(1, Int((usable + itemSpacing) / itemPitch))
        }
        for index in columns.indices where columns[index].rows != rows {
            columns[index].rows = rows
            chunkColumn(index)
        }
    }

    // MARK: - Month names

    private func makeMonthNameFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        // "LLLL" 是 standalone 月名（zh → 一月…十二月，en → January…），非复合格式里的
        // 序数月名（"1月"）。语言跟随 App 语言；切换语言由页面重建自然生效。
        formatter.locale = App.context.language.locale
        formatter.dateFormat = "LLLL"
        return formatter
    }

    private func monthName(_ month: Int, formatter: DateFormatter) -> String {
        guard
            let anchor = calendar.date(from: DateComponents(year: 2001, month: month, day: 1))
        else { return String(month) }
        return formatter.string(from: anchor)
    }
}

private var xamlUI: String {
    // swiftformat:disable:next all
    """
    <!-- 条目是默认 Button + 轻量样式：不写自定义模板，仅在本作用域的 ThemeDictionaries
         覆盖 Button* 主题资源键（generic.xaml 文档化的轻量样式契约，NavigationView 与
         AppBarButton 内部同款手法），把 rest / hover / pressed 底色切到 Subtle* 列表行
         画刷家族并去描边。HighContrast 不写字典 → 回落平台 SystemColor* 定义。
         画刷的 Color 经 {ThemeResource} 引用同名 Color token：松散 XAML 中
         {ThemeResource} 可解析（RangeSlider 实证），{StaticResource} 重定向不可靠。 -->
    <Grid
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Name="Root"
        Background="Transparent"
        Padding="4">
        <Grid.Resources>
            <ResourceDictionary>
                <ResourceDictionary.ThemeDictionaries>
                    <ResourceDictionary x:Key="Light">
                        <SolidColorBrush x:Key="ButtonBackground" Color="{ThemeResource SubtleFillColorTransparent}" />
                        <SolidColorBrush x:Key="ButtonBackgroundPointerOver" Color="{ThemeResource SubtleFillColorSecondary}" />
                        <SolidColorBrush x:Key="ButtonBackgroundPressed" Color="{ThemeResource SubtleFillColorTertiary}" />
                        <SolidColorBrush x:Key="ButtonBackgroundDisabled" Color="{ThemeResource SubtleFillColorDisabled}" />
                        <Thickness x:Key="ButtonBorderThemeThickness">0</Thickness>
                    </ResourceDictionary>
                    <ResourceDictionary x:Key="Dark">
                        <SolidColorBrush x:Key="ButtonBackground" Color="{ThemeResource SubtleFillColorTransparent}" />
                        <SolidColorBrush x:Key="ButtonBackgroundPointerOver" Color="{ThemeResource SubtleFillColorSecondary}" />
                        <SolidColorBrush x:Key="ButtonBackgroundPressed" Color="{ThemeResource SubtleFillColorTertiary}" />
                        <SolidColorBrush x:Key="ButtonBackgroundDisabled" Color="{ThemeResource SubtleFillColorDisabled}" />
                        <Thickness x:Key="ButtonBorderThemeThickness">0</Thickness>
                    </ResourceDictionary>
                </ResourceDictionary.ThemeDictionaries>
            </ResourceDictionary>
        </Grid.Resources>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto" />
            <ColumnDefinition Width="Auto" />
            <ColumnDefinition Width="Auto" />
            <ColumnDefinition Width="Auto" />
            <ColumnDefinition Width="Auto" />
        </Grid.ColumnDefinitions>
        <ScrollViewer Grid.Column="0" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Disabled">
            <StackPanel Name="YearHost" Orientation="Horizontal" />
        </ScrollViewer>
        <Border Grid.Column="1" Width="1" Margin="4,2" Background="{ThemeResource DividerStrokeColorDefaultBrush}" />
        <ScrollViewer Grid.Column="2" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Disabled">
            <StackPanel Name="MonthHost" Orientation="Horizontal" />
        </ScrollViewer>
        <Border Grid.Column="3" Width="1" Margin="4,2" Background="{ThemeResource DividerStrokeColorDefaultBrush}" />
        <ScrollViewer Grid.Column="4" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Disabled">
            <StackPanel Name="DayHost" Orientation="Horizontal" />
        </ScrollViewer>
    </Grid>
    """
}
