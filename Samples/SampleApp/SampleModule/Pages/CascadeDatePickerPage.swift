import Foundation
import RsFoundation
import RsUI
import WinUI

final class CascadeDatePickerPage: RsUI.Page {
    let url = URL(string: "rs://\(sampleModuleID)/cascade-date-picker")!
    var title: String { tr("Cascade Date Picker") }

    var header: Any? {
        featurePageHeader(
            title: tr("Cascade Date Picker"),
            description: tr(
                "A data-driven year / month / day cascade picker. Days without records are disabled; picking a year "
                    + "or month jumps to its first day with data. When height is limited, lists split into side-by-side columns."
            ))
    }

    var content: WinUI.UIElement {
        let sample = Self.makeSampleDates()

        // —— 定高宿主：高度不足自动分栏 ——
        let constrained = CascadeDatePicker()
        constrained.setDates(sample)
        constrained.selectEarliestDate()
        let constrainedHost = Grid()
        constrainedHost.height = 260
        constrainedHost.children.append(constrained)

        let constrainedSection = StackPanel()
        constrainedSection.spacing = 8
        constrainedSection.children.append(makeSectionTitle(tr("Height-constrained host")))
        constrainedSection.children.append(
            makeSectionSubtitle(
                tr("Host height is 260: the lists split into side-by-side columns instead of scrolling.")))
        constrainedSection.children.append(constrainedHost)

        // —— 自然高度：默认 12 行预算（月份列完整显示，日列自动分栏）——
        let natural = CascadeDatePicker()
        natural.setDates(sample)
        natural.selectLatestDate()

        let naturalSection = StackPanel()
        naturalSection.spacing = 8
        naturalSection.children.append(makeSectionTitle(tr("Natural height")))
        naturalSection.children.append(
            makeSectionSubtitle(
                tr(
                    "Natural height is capped at 12 rows: the month column always fits, and days (up to 31) split "
                        + "into side-by-side columns. A tighter host splits further.")))
        naturalSection.children.append(natural)

        // —— Flyout 集成（DropDownButton.flyout，仓库 Flyout 首例）——
        let flyoutPicker = CascadeDatePicker()
        flyoutPicker.setDates(sample)
        flyoutPicker.selectEarliestDate()

        let formatter = DateFormatter(systemDate: true, systemTime: false)
        let echo = TextBlock()
        echo.verticalAlignment = .center
        echo.foreground = themeBrush("TextFillColorSecondaryBrush")
        func formatEcho(_ date: Date?) -> String {
            date.map { formatter.string(from: $0) } ?? tr("No date selected")
        }
        echo.text = formatEcho(flyoutPicker.selectedDate)
        flyoutPicker.selectionChanged.addHandler { _, date in
            echo.text = formatEcho(date)
        }

        let dropDown = DropDownButton()
        dropDown.content = tr("Pick a date")
        let flyout = Flyout()
        flyout.content = flyoutPicker
        dropDown.flyout = flyout

        // 原生对照：同屏打开两个浮层，直接比密度与留白。
        let nativePicker = CalendarDatePicker()
        nativePicker.placeholderText = tr("Native CalendarDatePicker")

        let flyoutRow = StackPanel()
        flyoutRow.orientation = .horizontal
        flyoutRow.spacing = 12
        flyoutRow.children.append(dropDown)
        flyoutRow.children.append(echo)
        flyoutRow.children.append(nativePicker)

        let flyoutCard = SettingsCard(
            header: tr("In a flyout"),
            description: makeCaption(
                tr("The same control hosted in a DropDownButton flyout, next to the native CalendarDatePicker for comparison.")),
            content: flyoutRow)

        // —— 数据与选项（作用于上面三个 picker）——
        let pickers = [constrained, natural, flyoutPicker]

        let countsToggle = ToggleSwitch()
        countsToggle.header = tr("Show record counts")
        countsToggle.toggled.addHandler { _, _ in
            for picker in pickers {
                picker.showsRecordCounts = countsToggle.isOn
            }
        }

        let clearButton = Button()
        clearButton.content = tr("Clear data")
        clearButton.click.addHandler { _, _ in
            for picker in pickers {
                picker.setDates([])
            }
        }

        let restoreButton = Button()
        restoreButton.content = tr("Restore data")
        restoreButton.click.addHandler { _, _ in
            for picker in pickers {
                picker.setDates(sample)
            }
        }

        let optionsRow = StackPanel()
        optionsRow.orientation = .horizontal
        optionsRow.spacing = 12
        optionsRow.children.append(countsToggle)
        optionsRow.children.append(clearButton)
        optionsRow.children.append(restoreButton)

        let optionsCard = SettingsCard(
            header: tr("Data & options"),
            description: makeCaption(tr("Applied to all three pickers above.")),
            content: optionsRow)

        return featurePageContent([constrainedSection, naturalSection, flyoutCard, optionsCard])
    }

    /// 确定性示例数据：跨 2023–2026 四年、月份有洞、日期有重复、含闰日与时间部分。
    private static func makeSampleDates() -> [Date] {
        let calendar = Calendar.current
        func d(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 10))!
        }

        var dates: [Date] = []
        for month in [1, 4, 7, 10] {
            for day in [2, 8, 15, 23] {
                dates.append(d(2023, month, day))
            }
        }
        for month in 1...12 {
            for day in [1, 11, 21] {
                dates.append(d(2024, month, day))
            }
        }
        dates.append(d(2024, 2, 29))
        for month in 1...6 {
            for day in [5, 6, 7] {
                dates.append(d(2025, month, day))
            }
            dates.append(d(2025, month, 6))
        }
        for day in 1...12 {
            dates.append(d(2026, 3, day))
        }
        return dates
    }
}
