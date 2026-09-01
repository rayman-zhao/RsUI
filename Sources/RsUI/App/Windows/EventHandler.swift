import Foundation

public class EventHandler<T> {
    public typealias Handler = (T) -> Void
    private var handlers: [Handler] = []

    public init() {
    }

    public func addHandler(_ handler: @escaping Handler) {
        handlers.append(handler)
    }

    public func invoke(_ value: T) {
        for handler in handlers {
            handler(value)
        }
    }
}

public class EventWithArgumentHandler<T, U> {
    public typealias Handler = (T, U) -> Void
    private var handlers: [Handler] = []

    public init() {
    }

    public func addHandler(_ handler: @escaping Handler) {
        handlers.append(handler)
    }

    public func invoke(_ value: T, _ arg: U) {
        for handler in handlers {
            handler(value, arg)
        }
    }
}
