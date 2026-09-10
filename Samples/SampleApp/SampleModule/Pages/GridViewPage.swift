import Foundation
import RsUI
import UWP
import WinUI
import WindowsFoundation

final class GridViewPage: RsUI.Page {
    let context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://sample/grid-view")! }
    var title: String { tr("Grid View") }

    var header: Any? {
        featurePageHeader(
            title: tr("Grid View"),
            description: tr(
                "A GridView composed over ItemsView. Ctrl/Shift-click to multi-select, then double-click any selected tile: the selection is kept and itemDoubleTapped reports the whole set. Enable check box selection to toggle items with hover check boxes like File Explorer."
            )
        )
    }

    var content: WinUI.UIElement {
        let doubleTapText = TextBlock()
        let itemsText = TextBlock()
        let selectionText = TextBlock()
        for text in [doubleTapText, itemsText, selectionText] {
            text.textWrapping = .wrap
        }

        // SampleApp 同时 import RsUI 与 WinUI,`GridView` 需限定为 RsUI.GridView
        // (与 WinUI.GridView 同名,不限定会产生歧义引用)。
        let gridView = RsUI.GridView()
        gridView.selectionMode = .extended
        gridView.height = 360
        gridView.setItems((1...12).map { String(format: tr("Item %02d"), Int32($0)) })

        func updateSelectionText(_ gridView: RsUI.GridView) {
            selectionText.text = tr("Selected") + ": " + String(gridView.selectedCount)
        }
        gridView.selectionChanged.addHandler { [weak gridView] _ in
            guard let gridView else { return }
            updateSelectionText(gridView)
        }
        updateSelectionText(gridView)

        gridView.itemDoubleTapped.addHandler { sender, payload in
            doubleTapText.text = tr("Double-tapped") + ": " + gridViewItemText(payload.tappedItem)
            let names = payload.items.map(gridViewItemText).joined(separator: ", ")
            itemsText.text = tr("Event items") + " (" + String(payload.items.count) + "): " + names
            updateSelectionText(sender)
        }

        // Win11 资源管理器式复选框(阶段 2)。
        let checkBoxToggle = ToggleSwitch()
        checkBoxToggle.header = tr("Check box selection")
        checkBoxToggle.isOn = gridView.isCheckBoxSelectionEnabled
        checkBoxToggle.onContent = tr("On")
        checkBoxToggle.offContent = tr("Off")
        checkBoxToggle.toggled.addHandler { _, _ in
            gridView.isCheckBoxSelectionEnabled = checkBoxToggle.isOn
        }

        let stack = StackPanel()
        stack.spacing = 8
        stack.children.append(doubleTapText)
        stack.children.append(itemsText)
        stack.children.append(selectionText)
        stack.children.append(checkBoxToggle)
        stack.children.append(gridView)

        let root = Grid()
        root.padding = Thickness(left: 40, top: 0, right: 40, bottom: 32)
        root.children.append(stack)
        return root
    }
}

/// item 经 WinRT 装箱往返后的类型不确定(可能是 `String` 也可能是 `HString`),
/// 统一转成可显示文本。
private func gridViewItemText(_ item: Any?) -> String {
    if let string = item as? String {
        return string
    }
    if let hString = item as? HString {
        return String(hString: hString)
    }
    return String(describing: item ?? "nil")
}
