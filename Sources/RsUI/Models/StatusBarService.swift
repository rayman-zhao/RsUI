import Foundation
import Observation

/// 状态栏可用的布局槽位。
public enum StatusBarSlot: String, Sendable {
    case left
    case center
    case right
}

/// 描述一个可出现在状态栏中的项目元信息。
public struct StatusBarItemDescriptor: Sendable {
    /// 组合后的稳定唯一 ID，格式为 `moduleId:itemId`。
    public let id: String
    /// 所属模块 ID。
    public let moduleId: String
    /// 模块内部的项目 ID。
    public let itemId: String
    /// 在右键菜单中展示的标题。
    public let title: String
    /// 项目所属槽位。
    public let slot: StatusBarSlot
    /// 数值越小越靠前。
    public let priority: Int
    /// 首次出现时默认是否显示。
    public let defaultVisibility: Bool

    public init(
        id: String,
        moduleId: String,
        itemId: String,
        title: String,
        slot: StatusBarSlot,
        priority: Int,
        defaultVisibility: Bool = true
    ) {
        self.id = id
        self.moduleId = moduleId
        self.itemId = itemId
        self.title = title
        self.slot = slot
        self.priority = priority
        self.defaultVisibility = defaultVisibility
    }
}

/// 状态栏项目的当前运行时状态。
public struct StatusBarItem: Sendable {
    /// 组合后的稳定唯一 ID，格式为 `moduleId:itemId`。
    public let id: String
    /// 所属模块 ID。
    public let moduleId: String
    /// 模块内部的项目 ID。
    public let itemId: String
    /// 项目所属槽位。
    public let slot: StatusBarSlot
    /// 数值越小越靠前。
    public let priority: Int
    /// 当前显示文本。
    public var text: String
    /// 最后更新时间。
    public var updatedAt: Date

    public init(
        id: String,
        moduleId: String,
        itemId: String,
        slot: StatusBarSlot,
        priority: Int,
        text: String,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.moduleId = moduleId
        self.itemId = itemId
        self.slot = slot
        self.priority = priority
        self.text = text
        self.updatedAt = updatedAt
    }
}

/// 状态栏日志记录。
public struct StatusBarLogEntry: Sendable {
    /// 记录时间。
    public let timestamp: Date
    /// 产生日志的模块 ID。
    public let moduleId: String
    /// 日志内容。
    public let message: String

    public init(timestamp: Date = .now, moduleId: String, message: String) {
        self.timestamp = timestamp
        self.moduleId = moduleId
        self.message = message
    }
}

@Observable
public final class StatusBarService {
    /// 已注册的状态栏项目描述。
    public private(set) var descriptors: [StatusBarItemDescriptor] = []

    /// 当前所有状态栏项目的运行时值。
    public private(set) var items: [StatusBarItem] = []

    /// 状态栏关联的日志记录。
    public private(set) var logs: [StatusBarLogEntry] = []

    /// 当前被隐藏的项目 ID 集合。
    public private(set) var hiddenItemIDs: Set<String>

    /// 当状态栏偏好发生变化时回调给外部持久化。
    public var onPreferencesChanged: ((StatusBarPreferences) -> Void)?

    public init(
        preferences: StatusBarPreferences = .init(),
        onPreferencesChanged: ((StatusBarPreferences) -> Void)? = nil
    ) {
        self.hiddenItemIDs = Set(preferences.hiddenItemIDs)
        self.onPreferencesChanged = onPreferencesChanged
    }

    /// 注册一个新的状态栏项目定义；若已存在则覆盖其元信息。
    public func register(
        moduleId: String,
        itemId: String,
        title: String,
        slot: StatusBarSlot,
        priority: Int = 100,
        defaultVisibility: Bool = true
    ) {
        let id = "\(moduleId):\(itemId)"
        let descriptor = StatusBarItemDescriptor(
            id: id,
            moduleId: moduleId,
            itemId: itemId,
            title: title,
            slot: slot,
            priority: priority,
            defaultVisibility: defaultVisibility
        )

        if let index = descriptors.firstIndex(where: { $0.id == id }) {
            descriptors[index] = descriptor
        } else {
            descriptors.append(descriptor)
            if !defaultVisibility && !hiddenItemIDs.contains(id) {
                hiddenItemIDs.insert(id)
                persistPreferences()
            }
        }
    }

    /// 新增或更新某个状态栏项目当前显示内容。
    public func upsert(moduleId: String, itemId: String, slot: StatusBarSlot, text: String, priority: Int = 100) {
        let id = "\(moduleId):\(itemId)"
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index] = StatusBarItem(
                id: id,
                moduleId: moduleId,
                itemId: itemId,
                slot: slot,
                priority: priority,
                text: text,
                updatedAt: .now
            )
        } else {
            items.append(
                StatusBarItem(
                    id: id,
                    moduleId: moduleId,
                    itemId: itemId,
                    slot: slot,
                    priority: priority,
                    text: text
                )
            )
        }
    }

    /// 移除某个状态栏项目当前显示状态。
    public func remove(moduleId: String, itemId: String) {
        let id = "\(moduleId):\(itemId)"
        items.removeAll { $0.id == id }
    }

    /// 通过模块 ID 和项目 ID 设置某个项目是否可见。
    public func setVisibility(moduleId: String, itemId: String, isVisible: Bool) {
        setVisibility(id: "\(moduleId):\(itemId)", isVisible: isVisible)
    }

    /// 通过稳定 ID 设置某个项目是否可见。
    public func setVisibility(id: String, isVisible: Bool) {
        if isVisible {
            hiddenItemIDs.remove(id)
        } else {
            hiddenItemIDs.insert(id)
        }
        persistPreferences()
    }

    /// 查询某个项目当前是否可见。
    public func isVisible(id: String) -> Bool {
        !hiddenItemIDs.contains(id)
    }

    /// 返回可供右键菜单使用的全部项目定义，已按槽位和优先级排序。
    public func availableDescriptors() -> [StatusBarItemDescriptor] {
        descriptors.sorted { lhs, rhs in
            if lhs.slot != rhs.slot {
                return lhs.slot.rawValue < rhs.slot.rawValue
            }
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.id < rhs.id
        }
    }

    /// 返回某个槽位下当前可见的项目，已按优先级和更新时间排序。
    public func visibleItems(for slot: StatusBarSlot) -> [StatusBarItem] {
        items
            .filter { $0.slot == slot && isVisible(id: $0.id) }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority < rhs.priority
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    /// 追加一条模块日志。
    public func appendLog(moduleId: String, message: String) {
        logs.append(StatusBarLogEntry(moduleId: moduleId, message: message))
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }
    }

    /// 将某个槽位下的可见项目拼接为可直接渲染的文本。
    public func text(for slot: StatusBarSlot, fallback: String) -> String {
        let values = visibleItems(for: slot)
            .map(\.text)

        if values.isEmpty {
            return fallback
        }
        return values.joined(separator: "  ·  ")
    }

    /// 将当前状态栏偏好回写给外部持久化层。
    private func persistPreferences() {
        onPreferencesChanged?(StatusBarPreferences(hiddenItemIDs: Array(hiddenItemIDs).sorted()))
    }
}
