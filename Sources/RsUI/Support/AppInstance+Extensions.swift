import Dispatch
import Foundation
import RsFoundation
import WinAppSDK

extension AppInstance {
    static func redirectOrRegister(
        for key: String, onActivated: @escaping @MainActor (Any?, AppActivationArguments?) -> Void
    ) {
        guard let instance = try? AppInstance.findOrRegisterForKey(key)
        else {
            fatalError("Failed to findOrRegister AppInstance.")
        }

        // Single instance check.
        guard instance.isCurrent else {
            if let args = try? instance.getActivatedEventArgs(),
                let asyncResult = try? instance.redirectActivationToAsync(args)
            {
                // 等 redirect 真正送达主实例再退出：立即 exit(0) 可能在激活转发完成前
                // 杀掉本进程，表现为「二次启动没有聚焦已有窗口」。后台等待 + 超时兜底。
                let done = DispatchSemaphore(value: 0)
                Task.detached(priority: .userInitiated) {
                    try? await asyncResult.get()
                    done.signal()
                }
                _ = done.wait(timeout: .now() + 5)
            }
            log.info("Found running instance, exit.")
            exit(0)
        }

        // Response to activated event.
        instance.activated.addHandler { sender, args in
            Task { @MainActor in
                onActivated(sender, args)
            }
        }
    }
}
