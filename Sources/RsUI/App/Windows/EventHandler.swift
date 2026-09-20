import Foundation

/// `addHandler` 返回的订阅凭据；`removeHandler(_:)` 用它注销对应闭包。
/// 调用方按「每个 owner 注册一次、owner 销毁前移除」使用即可。
public struct EventHandlerToken {
    fileprivate let id: UUID

    fileprivate init() {
        id = UUID()
    }
}

public class EventHandler<T> {
    public typealias Handler = (T) -> Void
    private var handlers: [(token: EventHandlerToken, handler: Handler)] = []

    public init() {
    }

    @discardableResult
    public func addHandler(_ handler: @escaping Handler) -> EventHandlerToken {
        let entry: (token: EventHandlerToken, handler: Handler) = (EventHandlerToken(), handler)
        handlers.append(entry)
        return entry.token
    }

    public func removeHandler(_ token: EventHandlerToken) {
        handlers.removeAll { $0.token.id == token.id }
    }

    public func invoke(_ value: T) {
        for entry in handlers {
            entry.handler(value)
        }
    }
}

public class EventWithArgumentHandler<T, U> {
    public typealias Handler = (T, U) -> Void
    private var handlers: [(token: EventHandlerToken, handler: Handler)] = []

    public init() {
    }

    @discardableResult
    public func addHandler(_ handler: @escaping Handler) -> EventHandlerToken {
        let entry: (token: EventHandlerToken, handler: Handler) = (EventHandlerToken(), handler)
        handlers.append(entry)
        return entry.token
    }

    public func removeHandler(_ token: EventHandlerToken) {
        handlers.removeAll { $0.token.id == token.id }
    }

    public func invoke(_ value: T, _ arg: U) {
        for entry in handlers {
            entry.handler(value, arg)
        }
    }
}
