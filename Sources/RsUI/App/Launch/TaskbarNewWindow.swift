// The capability App needs: make sure a "New Window" entry exists in the
// taskbar right-click menu. The backend is hidden behind this protocol so
// swapping it (Win32 COM today, WinRT JumpList or none later) never touches
// App.swift.
protocol TaskbarNewWindowProvider {
    // Whether this backend can register in the current environment.
    var isAvailable: Bool { get }
    func register(aumid: String, title: String, argument: String)
}

// Front door + the single place that picks the backend. Swap this one line
// (or make it environment-based) to change implementations; deleting a backend
// only removes its provider file, not this facade or App.swift.
enum TaskbarNewWindow {
    static var provider: TaskbarNewWindowProvider = JumpListCOMProvider()

    static func register(aumid: String, title: String, argument: String = "--new-window") {
        guard provider.isAvailable else { return }
        provider.register(aumid: aumid, title: title, argument: argument)
    }
}
