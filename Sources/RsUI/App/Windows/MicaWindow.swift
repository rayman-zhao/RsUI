import WinUI

class MicaWindow: Window {
    override init() {
        super.init()

        self.extendsContentIntoTitleBar = true
        self.appWindow.titleBar.preferredHeightOption = .tall

        // 设置 Mica 背景
        let micaBackdrop = MicaBackdrop()
        micaBackdrop.kind = .base
        self.systemBackdrop = micaBackdrop
    }
}
