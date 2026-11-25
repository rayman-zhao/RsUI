import Foundation
import WindowsFoundation

extension DateTime {
    /// WinRT DateTime 是自 1601-01-01 UTC 起的 100ns 计数，与 Foundation 的
    /// epoch(1970)和秒都不同。
    public static func make(date: Foundation.Date) -> DateTime {
        DateTime(universalTime: Int64(((date.timeIntervalSince1970 + 1_164_447_3600) * 10_000_000).rounded()))
    }

    public var date: Foundation.Date {
        Foundation.Date(timeIntervalSince1970: Double(universalTime) / 10_000_000 - 1_164_447_3600)
    }
}
