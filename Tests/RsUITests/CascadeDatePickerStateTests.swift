import Foundation
import Testing
@testable import RsUI

@Suite
struct CascadeDatePickerStateTests {
    /// 固定 UTC 日历，避免宿主机时区影响日期截断与月长。
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func key(_ year: Int, _ month: Int, _ day: Int) -> CascadeDatePickerState.DayKey {
        CascadeDatePickerState.DayKey(year: year, month: month, day: day)
    }

    @Test
    func aggregatesDatesAndTruncatesTime() {
        var state = CascadeDatePickerState()
        state.setDates(
            [
                date(2024, 3, 5), date(2024, 3, 5, hour: 23), date(2024, 3, 5, hour: 1),
                date(2024, 3, 6),
            ], calendar: calendar)

        #expect(state.recordCount(day: key(2024, 3, 5)) == 3)
        #expect(state.recordCount(day: key(2024, 3, 6)) == 1)
        #expect(state.recordCount(day: key(2024, 3, 7)) == 0)
        #expect(state.sortedKeys == [key(2024, 3, 5), key(2024, 3, 6)])
    }

    @Test
    func recordCountsAggregateByScope() {
        var state = CascadeDatePickerState()
        state.setDates(
            [
                date(2023, 4, 2), date(2023, 4, 8), date(2023, 10, 1), date(2024, 4, 2),
            ], calendar: calendar)

        #expect(state.recordCount(year: 2023) == 3)
        #expect(state.recordCount(year: 2024) == 1)
        #expect(state.recordCount(year: 2025) == 0)
        #expect(state.recordCount(year: 2023, month: 4) == 2)
        #expect(state.recordCount(year: 2023, month: 5) == 0)
    }

    @Test
    func yearRangeIsContiguousAcrossGaps() {
        var state = CascadeDatePickerState()
        state.setDates([date(2022, 5, 1), date(2025, 1, 2)], calendar: calendar)

        #expect(state.years(calendar: calendar, now: date(2024, 1, 1)) == [2022, 2023, 2024, 2025])
        #expect(state.hasData(year: 2022))
        #expect(!state.hasData(year: 2023))
        #expect(!state.hasData(year: 2024))
        #expect(state.hasData(year: 2025))
    }

    @Test
    func monthsAreAlwaysTwelve() {
        var state = CascadeDatePickerState()
        state.setDates([date(2024, 1, 1)], calendar: calendar)

        #expect(state.months(inYear: 2024) == Array(1...12))
        #expect(state.hasData(year: 2024, month: 1))
        #expect(!state.hasData(year: 2024, month: 2))
    }

    @Test
    func februaryLengthFollowsLeapYears() {
        var state = CascadeDatePickerState()
        state.setDates([date(2024, 2, 29), date(2023, 2, 28)], calendar: calendar)

        #expect(state.days(inYear: 2024, month: 2, calendar: calendar) == Array(1...29))
        #expect(state.days(inYear: 2023, month: 2, calendar: calendar) == Array(1...28))
        #expect(state.days(inYear: 2024, month: 4, calendar: calendar) == Array(1...30))
    }

    @Test
    func selectingYearCascadesToFirstDayWithData() {
        var state = CascadeDatePickerState()
        state.setDates(
            [date(2024, 7, 2), date(2024, 3, 10), date(2024, 7, 9)], calendar: calendar)

        // 乱序输入也能级联到时序上第一个有数据月（3 月）的第一天（10 日）。
        // #expect 宏内不能调用 mutating 方法，结果先落到局部量。
        let yearSelected = state.select(year: 2024)
        #expect(yearSelected)
        #expect(state.selection == key(2024, 3, 10))

        let monthSelected = state.select(month: 7)
        #expect(monthSelected)
        #expect(state.selection == key(2024, 7, 2))

        // 无数据年份不可选；重复选同年会重新级联回该年第一个有数据的日（需求 6 语义）。
        let missingYear = state.select(year: 2030)
        #expect(!missingYear)
        let sameYear = state.select(year: 2024)
        #expect(sameYear)
        #expect(state.selection == key(2024, 3, 10))
    }

    @Test
    func selectingMonthFromUnselectedStateUsesAnchorYear() {
        var state = CascadeDatePickerState()
        state.setDates([date(2024, 3, 1), date(2024, 4, 2)], calendar: calendar)

        // 未选年：月列以展示锚点年（最早数据年）为当前年，首击即落位该月第一个数据日。
        let monthBeforeYear = state.select(month: 3)
        #expect(monthBeforeYear)
        #expect(state.selection == key(2024, 3, 1))

        // 锚点年内无数据的月不可选。
        let emptyMonth = state.select(month: 5)
        #expect(!emptyMonth)
        #expect(state.selection == key(2024, 3, 1))

        // 已有选中年后保持既有语义：在当前年内切换到有数据的月。
        let dataMonth = state.select(month: 4)
        #expect(dataMonth)
        #expect(state.selection == key(2024, 4, 2))
    }

    @Test
    func selectingDayFromUnselectedStateUsesAnchorMonth() {
        var state = CascadeDatePickerState()
        state.setDates([date(2024, 3, 10), date(2024, 3, 15)], calendar: calendar)

        // 未选中：日列以最早数据日所在月为当前月，首击即选中该月内有数据的日。
        let dayBeforeSelection = state.select(day: 15)
        #expect(dayBeforeSelection)
        #expect(state.selection == key(2024, 3, 15))

        let noDataDay = state.select(day: 11)
        #expect(!noDataDay)
        #expect(state.selection == key(2024, 3, 15))
    }

    @Test
    func selectingDayRequiresDataInCurrentMonth() {
        var state = CascadeDatePickerState()
        state.setDates([date(2024, 3, 10), date(2024, 3, 15)], calendar: calendar)
        _ = state.select(year: 2024)

        let noDataDay = state.select(day: 11)
        #expect(!noDataDay)
        #expect(state.selection == key(2024, 3, 10))

        let otherDay = state.select(day: 15)
        #expect(otherDay)
        #expect(state.selection == key(2024, 3, 15))
    }

    @Test
    func clickingSelectedDayClearsSelection() {
        var state = CascadeDatePickerState()
        state.setDates([date(2024, 3, 10), date(2024, 3, 15)], calendar: calendar)
        _ = state.select(day: 15)
        #expect(state.selection == key(2024, 3, 15))

        // 再次点击已选中的日：清除选择（真变化，返回 true）。
        let toggled = state.select(day: 15)
        #expect(toggled)
        #expect(state.selection == nil)

        // 清除后未选中态再点同一天：重新选中（锚点回退路径）。
        let reselected = state.select(day: 15)
        #expect(reselected)
        #expect(state.selection == key(2024, 3, 15))

        // 非选中日的重复点击保持普通选中语义（选别的日）。
        let otherDay = state.select(day: 10)
        #expect(otherDay)
        #expect(state.selection == key(2024, 3, 10))
    }

    @Test
    func earliestAndLatestSelection() {
        var state = CascadeDatePickerState()
        let earliestEmpty = state.selectEarliest()
        let latestEmpty = state.selectLatest()
        #expect(!earliestEmpty)
        #expect(!latestEmpty)

        state.setDates(
            [date(2024, 6, 15), date(2023, 12, 31), date(2024, 1, 1)], calendar: calendar)

        let earliest = state.selectEarliest()
        #expect(earliest)
        #expect(state.selection == key(2023, 12, 31))
        let latest = state.selectLatest()
        #expect(latest)
        #expect(state.selection == key(2024, 6, 15))
    }

    @Test
    func selectingExactDateTruncatesTimeAndRequiresData() {
        var state = CascadeDatePickerState()
        state.setDates([date(2024, 3, 10), date(2024, 3, 15, hour: 9)], calendar: calendar)

        // 时间部分截断到天：同日晚间时刻命中当天数据。
        let restored = state.select(date: date(2024, 3, 15, hour: 23), calendar: calendar)
        #expect(restored)
        #expect(state.selection == key(2024, 3, 15))

        // 无数据的日不可选、不动既有选择。
        let missing = state.select(date: date(2024, 3, 11), calendar: calendar)
        #expect(!missing)
        #expect(state.selection == key(2024, 3, 15))

        // 与当前一致时返回 false（真变化才触发事件）。
        let same = state.select(date: date(2024, 3, 15), calendar: calendar)
        #expect(!same)
    }

    @Test
    func clearingSelection() {
        var state = CascadeDatePickerState()
        state.setDates([date(2024, 3, 10)], calendar: calendar)
        _ = state.select(year: 2024)

        let cleared = state.clearSelection()
        #expect(cleared)
        #expect(state.selection == nil)
        // 已无选择再清：返回 false，数据聚合不受影响。
        let clearedAgain = state.clearSelection()
        #expect(!clearedAgain)
        #expect(state.recordCount(day: key(2024, 3, 10)) == 1)
    }

    @Test
    func emptyDataShowsOnlyCurrentYearDisabled() {
        var state = CascadeDatePickerState()
        state.setDates([], calendar: calendar)

        #expect(state.isEmpty)
        #expect(state.years(calendar: calendar, now: date(2026, 3, 1)) == [2026])
        #expect(!state.hasData(year: 2026))
        let onlyYear = state.select(year: 2026)
        #expect(!onlyYear)
        let earliestEmpty = state.selectEarliest()
        #expect(!earliestEmpty)
        #expect(state.selection == nil)
    }

    @Test
    func setDatesKeepsSelectionStillInDataAndClearsOtherwise() {
        var state = CascadeDatePickerState()
        state.setDates([date(2024, 3, 10), date(2024, 3, 15)], calendar: calendar)
        _ = state.select(year: 2024)
        _ = state.select(day: 15)

        // 选中日仍在数据中：保留、不清空。
        let kept = state.setDates([date(2024, 3, 15)], calendar: calendar)
        #expect(!kept)
        #expect(state.selection == key(2024, 3, 15))

        // 选中日从数据中消失：清空。
        let cleared = state.setDates([date(2024, 3, 10)], calendar: calendar)
        #expect(cleared)
        #expect(state.selection == nil)
    }
}
