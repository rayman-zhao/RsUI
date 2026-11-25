import Foundation
import RsFoundation
import WinUI

// MARK: - 标签文案工具(网格宿主共用：逐条目日期/名称 → 组标签文案与标签区前缀)

extension AnnotatedScrollBar {
    /// 标签组数预算。ASB 标签数量悬崖是 WinAppSDK 1.8 运行时行为（37 组活/
    /// 45 组死，超发全部消失）；WinAppRuntime 2.6.4 实测至 512 组全活
    /// （AsbLabelCliffTestPage），预算留 5 倍余量，采样只对极端跨度兜底。
    public static let labelGroupBudget = 96

    /// 按日期排序的逐条目组标签文案（每个条目一个，同组文案相同），粒度按数据
    /// 跨年情况自适应：
    /// - 单年且天数组 ≤ 预算：月-日（最细；单年内无年份歧义）；
    /// - 否则月粒度：每年首组发年标签（"2024"）、其余月组发缩写月名，跨年时
    ///   同月日的归属由最近的年标签消解；月组超出预算按步长采样（年界恒发），
    ///   被跳过的月组沿用它上方最近标签的文案——调用方的连续去重随即
    ///   吞掉，等效于不发标签。
    public static func dateGroupLabels(for times: [Date]) -> [String] {
        let calendar = Calendar.current
        var comps: [(year: Int, month: Int, day: Int)] = []
        comps.reserveCapacity(times.count)
        var years = Set<Int>()
        var months = Set<Int>()
        var days = Set<Int>()
        for time in times {
            let c = calendar.dateComponents([.year, .month, .day], from: time)
            let year = c.year ?? 0
            let month = c.month ?? 0
            let day = c.day ?? 0
            comps.append((year, month, day))
            years.insert(year)
            months.insert(year * 100 + month)
            days.insert(year * 10000 + month * 100 + day)
        }

        if years.count == 1, days.count <= labelGroupBudget {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = DateFormatter.systemShortDateIsDayFirst ? "dd/MM" : "MM/dd"
            return times.map { dayFormatter.string(from: $0) }
        }

        let monthFormatter = DateFormatter()
        // "LLL" = 缩写 standalone 月名（zh → 1月，en → Jan），宽度在标签前缀
        // 预算内；语言跟随 App 语言（swift-foundation 的进程默认 locale 在
        // Windows 不跟随用户区域设置，须显式指定）
        monthFormatter.locale = App.context.language.locale
        monthFormatter.dateFormat = "LLL"

        let multiYear = years.count > 1
        let monthlySlots = max(1, labelGroupBudget - years.count)
        let stride = max(1, (months.count + monthlySlots - 1) / monthlySlots)
        var lastYear: Int?
        var lastMonth: (year: Int, month: Int)?
        var groupIndex = 0
        var lastLabel = ""
        return times.indices.map { i in
            let c = comps[i]
            guard c.year != lastMonth?.year || c.month != lastMonth?.month else { return lastLabel }
            lastMonth = (c.year, c.month)
            let label: String
            if multiYear, c.year != lastYear {
                lastYear = c.year
                label = String(c.year)
            } else if groupIndex % stride == 0 {
                label = monthFormatter.string(from: times[i])
            } else {
                label = lastLabel
            }
            groupIndex += 1
            lastLabel = label
            return label
        }
    }

    /// 标签区 44px（LabelsGridMinWidth）、12px SemiBold 下实测容 5-6 个半角字符宽；
    /// 全角字符按 2 个半角单位计，中文截 2 个完整字，杜绝第 3 字被半字裁切
    public static func labelPrefix(_ text: String) -> String {
        var units = 0
        var prefix = ""
        for ch in text {
            let width = ch.unicodeScalars.contains(where: isFullWidth) ? 2 : 1
            guard units + width <= 5 else { break }
            units += width
            prefix.append(ch)
        }
        return prefix
    }

    /// East Asian Wide 的常用子集，文件名场景足够
    static func isFullWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0x9FFF, 0xA960...0xA97F, 0xAC00...0xD7A3,
            0xF900...0xFAFF, 0xFE30...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6,
            0x1F300...0x1FAFF, 0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}
