/// XAML 控件延迟释放池：把"随页面拆除立即释放会被 XAML 异步收尾悬空调用"
/// 的对象推迟一拍再放行。
///
/// # 原理（为什么需要它）
///
/// swift-winui 投影下，"Swift 子类化的 XAML 控件"与"实现 WinRT 接口交给
/// XAML 的 Swift 类"本质都是 Swift 对象与原生 XAML 对象的 COM 聚合。投影层
/// 没有把"原生侧对 Swift 对象的调用面"的生命周期与 Swift 引用计数完全绑定：
/// Swift 侧最后一个引用释放后对象立即回收，而 XAML 的异步路径——UIA 事件
/// 派发、ItemsRepeater 清理、动画/过渡 tick、模板重排——可能在此之后仍沿
/// 原生侧引用发起调用，调用落进已释放内存。实测两种崩溃形态：同步投影
/// 调用抛 HRESULT（stowed exception 0xC000027B，内层 0x80070057）；原生
/// 虚调用跳转垃圾地址（0xC0000005 DEP 违例）。是否爆发取决于控件的
/// "异步调用面"大小与释放时序，属竞态：常规时序可长期全绿，调试器/慢速
/// 控制台等改变线程时序的环境下必现。
///
/// 本池的缓解方式：在 Swift 侧把对象多保活一小段（默认 2s），让在飞的
/// 收尾调用落在活对象上，窗口即闭合。**这是缓解不是治本**——治本需修
/// swift-winui 子类 COM 聚合的生命周期绑定。
///
/// # 使用契约
///
/// - 挂在**持有方**的 `deinit` 里；勿图省事在控件自身 deinit 里
///   `retain(self)` 统一兜底——Swift 5 模式下能静默编译，但 Swift 6 模式
///   是编译错误（deinit 逃逸 self）；且池放行后计数再次归零会重跑 deinit，
///   形成无限复活（须一次性守卫对抗语言生命周期模型）；竞态原因是持有方
///   的拆除时序，也不该由控件无条件买单（无竞态路径与生命周期断言会被拖
///   2s 尾巴）。
/// - "替换式换代"场景（如 `Viewer.leftContent = 新列表`）在替换**前**
///   retain 旧值；
/// - 任何 `AnyObject`（投影控件包装、COM 导出对象）皆可入池；2s 内对象
///   仅多占引用，不阻碍其余引用先行释放。
///
/// # swift-winui 生命周期最佳实践（防同族问题的三条纪律）
///
/// 1. **重机制控件不子类化，用组合**（外层 `Grid` 子类持有原生控件）。
///    判据：先问"XAML 会在哪些异步路径回调它"——内部带 repeater / 滚动 /
///    选择模型 / UIA peer / 动画的控件调用面大，风险高。已知实锤：
///    `WinUI.AnnotatedScrollBar` 子类化必崩（COM 聚合释放路径，2026-10-05）；
///    `WinUI.ItemsView` 子类化在拆除竞态窗口崩（2026-10-12）。`Grid` /
///    `FontIcon` 等调用面小的子类化目前可靠，但这是经验性窄窗口而非保证。
/// 2. **实现 WinRT 接口交给 XAML 的 Swift 对象，必须由 Swift 侧强持有到
///    宿主寿命结束**。适用 `IElementFactory` 工厂、`IScrollController` 桥、
///    `DataTemplateSelector`、itemTransitionProvider 等。禁止"临时表达式
///    直接赋给 XAML 属性"——Swift 引用赋完即丢，存活全押在 XAML 侧引用
///    计数上。正面范例：`ItemsViewBase.activeFactory`、
///    `AnnotatedScrollBar.scrollBridges` 与 `labelSelector`。
/// 3. **上述对象随页面/面板拆除时，持有方 deinit 调本池兜底**；有替换式
///    换代的，替换前先 retain 旧值（见使用契约）。
public enum XamlDeferredRelease {
    /// 延迟释放：主线程保活 `millis` 毫秒后放行最后一个引用。
    public static func retain(_ object: AnyObject, millis: UInt64 = 2_000) {
        // 引用仅用于延长生命周期（不做任何成员访问）；COM 引用计数原子，
        // 跨 Task 边界持有引用本身无数据竞争。
        nonisolated(unsafe) let retained = object
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: millis * 1_000_000)
            _ = retained  // 睡醒后才触发的"最后使用"，保证捕获活到此刻
        }
    }
}
