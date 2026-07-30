import Foundation
import Observation
import RsFoundation
import WinUI

/// FIXME: 我不确定这里的保护机制是必要的。从遗留代码迁移过来，应确认测试有效。
class AppearanceWindow: Window {
    // 持有 Observation Task 句柄，窗口关闭时 cancel，避免死窗口的 task 继续访问失效的 self.appWindow / self.viewModel
    var observationTask: Task<Void, Never>? = nil
    var isApplyingAppearance = false

    override init() {
        super.init()

        observationTask = self.startObserving {
            (App.context.theme, App.context.language)
        } onChanged: { [weak self] _, _ in
            // 防止并发/重入（多窗口下 env Observation 接连触发可能引发 menuItems 的双 parent 错误）
            guard let self else { return }
            // Really happend?
            guard self.appWindow != nil else {
                log.warning("self.appWindow == nil")
                return
            }
            // Really happend?
            guard !self.isApplyingAppearance else {
                log.warning("self.isApplyingAppearance == true")
                return
            }
            self.isApplyingAppearance = true
            defer { self.isApplyingAppearance = false }

            self.onAppearanceChanged()
        }

        self.closed.addHandler { [weak self] _, _ in
            guard let self else { return }

            // 先 cancel observation task，避免死窗口的 task 继续访问 self.appWindow / self.viewModel
            self.observationTask?.cancel()
            self.observationTask = nil
        }
    }

    func onAppearanceChanged() {
    }
}
