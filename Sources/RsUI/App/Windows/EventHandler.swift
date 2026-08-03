import Foundation

class EventHandler<T> {
    typealias Handler = (T) -> Void
    private var handlers: [Handler] = []

    func addHandler(_ handler: @escaping Handler) {
        handlers.append(handler)
    }

    func invoke(_ value: T) {
        for handler in handlers {
            handler(value)
        }
    }
}

class EventWithArgumentHandler<T, U> {
    typealias Handler = (T, U) -> Void
    private var handlers: [Handler] = []

    func addHandler(_ handler: @escaping Handler) {
        handlers.append(handler)
    }

    func invoke(_ value: T, _ arg: U) {
        for handler in handlers {
            handler(value, arg)
        }
    }
}
