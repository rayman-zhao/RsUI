import Foundation
import RsFoundation
import UWP
import WinUI

@testable import RsUI

/// useRestoration 窗口生命周期自驱动测试（无人值守，跑完自动结束进程）。
///
/// 验证 `Window.useRestoration` 的事件闭包不得把窗口钉死在内存：若闭包强捕获
/// self，会形成 原生 window → 事件表 → 闭包 → Swift 窗口实例 →（聚合内引用）
/// → 原生 window 的自持环——窗口 close、框架引用归零后，整个窗口簇永久滞留。
///
/// 流程：创建窗口（内部调用 useRestoration）→ 激活并调整尺寸（驱动
/// sizeChanged）→ close → 等待 → 检查外部 weak 引用归 nil（即 deinit 已执行）。
///
/// 窗口自挂 `[weak self]` 的 sizeChanged / closed 探针同时验证：子类实例上这
/// 两个原生事件触发时 weak 引用可解析——若解析失败，说明旧注释“extension 里
/// 必须 strong 捕获”所描述的情况复现，weak 化会静默失效。
///
/// 输出 `RLT:` 前缀日志；全部通过 exit(0)，断言失败 exit(1)。
/// 注：基类用 `AppearanceWindow` 而非 `NavigationViewWindow`——后者的 XAML
/// 依赖 `{x:AppIconPath}` 占位符在已 bootstrap 的 App 中解析，测试宿主没有
/// 应用图标会让 XamlReader 直接 fatal（与被测的内存问题无关）。泄漏机制
/// （Window 级原生事件 + 聚合子类实例 + useRestoration 闭包）两者一致。
final class RestorationLifecycleTestWindow: AppearanceWindow {

    private(set) var sawSizeChanged = false

    deinit {
        log.info("RLT: window deinit 执行")
    }

    override init() {
        super.init()
        title = "Restoration Lifecycle Test"
        useRestoration(false)

        sizeChanged.addHandler { [weak self] _, _ in
            guard let self else {
                log.error("RLT: sizeChanged 触发但 weak self 为 nil")
                return
            }
            self.sawSizeChanged = true
        }
        closed.addHandler { [weak self] _, _ in
            guard let self else {
                log.error("RLT: closed 触发但 weak self 为 nil")
                return
            }
            log.info("RLT: closed 触发，weak self 解析成功（sawSizeChanged=\(self.sawSizeChanged)）")
        }
    }

    // MARK: - 场景驱动

    static func run() {
        // 保活窗口：被测窗口 close 后应用继续运行（唯一窗口关闭会触发进程
        // teardown，原生窗口随应用整体销毁，测不出「关掉的窗口是否滞留」）。
        let keeper = AppearanceWindow()
        keeper.title = "RLT keeper"
        do {
            try keeper.activate()
        } catch {
            log.error("RLT: 保活窗口启动失败：\(error)")
            exit(1)
        }

        let window = RestorationLifecycleTestWindow()
        weak var tracked = window
        do {
            try window.activate()
            try? window.appWindow?.moveAndResize(
                UWP.RectInt32(x: 211, y: 223, width: 901, height: 603))
        } catch {
            log.error("RLT: 窗口启动失败：\(error)")
            exit(1)
        }
        // run() 返回后局部强引用即释放；窗口存活只应依赖框架 rooting 与
        // useRestoration 的事件闭包（后者不应构成关窗后仍存活的强引用）。

        Task { @MainActor in
            var failures: [String] = []
            func check(_ condition: Bool, _ message: String) {
                if condition {
                    log.info("RLT: PASS — \(message)")
                } else {
                    failures.append(message)
                    log.error("RLT: FAIL — \(message)")
                }
            }

            // 阶段1：打开期间 sizeChanged 探针（weak 解析验证）。
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            check(
                tracked?.sawSizeChanged == true,
                "阶段1: sizeChanged 期间 weak self 解析（失败说明 weak 化会静默失效）")

            // 阶段2：close 后窗口应可回收（deinit 执行 → weak 归 nil）。
            _ = try? tracked?.close()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            var reclaimed = tracked == nil
            if !reclaimed {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                reclaimed = tracked == nil
            }
            check(
                reclaimed,
                "阶段2: close 后窗口已回收（weak 归 nil，deinit 执行）")

            if failures.isEmpty {
                log.info("RLT: ALL PASS")
                exit(0)
            } else {
                for failure in failures {
                    log.error("RLT: FAILED — \(failure)")
                }
                exit(1)
            }
        }
    }
}
