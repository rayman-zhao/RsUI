import Foundation
import RsFoundation
import WinUI
import WindowsFoundation

/// 行为类似 `RadioButtons` 的单选按钮组：`VariableSizedWrapGrid` 内水平自动布局一组
/// `AppBarToggleButton`，同一时刻至多一项选中；点击已选中项不会反选。
/// 项目以 `tag`（HString）字符串标识，`selectionChanged` 携带新选中项的 tag。
///
/// `VariableSizedWrapGrid` 在投影里是 final，无法继承，故按 `PageTabView` 的组合模式
/// 以 `Grid` 子类内嵌一个铺满的 wrapGrid。
open class ToggleButtons: WinUI.Grid {
    public let selectionChanged = EventWithArgumentHandler<ToggleButtons, String>()

    private let wrapGrid = VariableSizedWrapGrid()
    private var buttons: [AppBarToggleButton] = []
    private var _selectedTag: String?

    override public init() {
        super.init()
        // Orientation 必须显式置 horizontal：默认 Vertical 时子项按列填充（单列竖排）。
        wrapGrid.orientation = .horizontal
        wrapGrid.horizontalAlignment = .stretch
        children.append(wrapGrid)
    }

    // MARK: - Items

    @discardableResult
    public func addItem(
        iconGlyph: String, label: String?, tag: String, tooltip: String? = nil
    ) -> AppBarToggleButton {
        let icon = FontIcon()
        icon.glyph = iconGlyph

        let button = AppBarToggleButton()
        button.icon = icon
        if let label {
            button.label = label
        } else {
            button.labelPosition = .collapsed
            button.width = 44
        }
        button.tag = try? HString(tag)
        if let tooltip {
            try? ToolTipService.setToolTip(button, tooltip)
        }

        button.click.addHandler { [weak self, weak button] _, _ in
            guard let self, let button else { return }
            self.select(button)
        }

        buttons.append(button)
        wrapGrid.children.append(button)
        return button
    }

    // MARK: - Selection

    /// 当前选中项的 tag；nil 表示尚无选中。setter 与用户点击走同一 commit 路径，
    /// 真正变化时触发 `selectionChanged`；无匹配 tag 时告警并保持现状。
    public var selectedTag: String? {
        get { _selectedTag }
        set {
            guard let newValue else {
                log.warning("ToggleButtons: setting selectedTag = nil is not supported, ignored.")
                return
            }
            select(tag: newValue)
        }
    }

    /// 换行方向，默认水平（从左到右排满换行）。
    public var orientation: Orientation {
        get { wrapGrid.orientation }
        set { wrapGrid.orientation = newValue }
    }

    public var itemWidth: Double {
        get { wrapGrid.itemWidth }
        set { wrapGrid.itemWidth = newValue }
    }

    public var itemHeight: Double {
        get { wrapGrid.itemHeight }
        set { wrapGrid.itemHeight = newValue }
    }

    public var maximumRowsOrColumns: Int32 {
        get { wrapGrid.maximumRowsOrColumns }
        set { wrapGrid.maximumRowsOrColumns = newValue }
    }

    // MARK: - Private

    /// 投影里 `ToggleButton` 没有 `isCheckedChanged`，而 `click` 在 toggle 状态翻转之后
    /// 触发，正好覆盖两种情况：选中新项、点击已选中项（此时它已被翻成 unchecked）。
    private func select(_ button: AppBarToggleButton) {
        guard let tag = tagString(of: button) else {
            log.warning("ToggleButtons: tapped item carries no HString tag, ignored.")
            return
        }
        commitSelection(to: tag, preferred: button)
    }

    private func select(tag: String) {
        guard let button = buttons.first(where: { tagString(of: $0) == tag }) else {
            log.warning("ToggleButtons: no item matches tag '\(tag)'.")
            return
        }
        commitSelection(to: tag, preferred: button)
    }

    private func commitSelection(to tag: String, preferred button: AppBarToggleButton) {
        let oldTag = _selectedTag
        for other in buttons where other !== button {
            other.isChecked = false
        }
        button.isChecked = true
        _selectedTag = tag
        if oldTag != tag {
            selectionChanged.invoke(self, tag)
        }
    }

    private func tagString(of button: AppBarToggleButton) -> String? {
        guard let tag = button.tag, let string = tag as? HString else { return nil }
        return String(hString: string)
    }
}
