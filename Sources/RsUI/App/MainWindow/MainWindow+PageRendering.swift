import Foundation
import UWP
import WinUI

final class PageViewParts {
    var contentBorder: Border?
    var headerBorder: Border?
}

extension MainWindow {
    func title(for page: Page?) -> String {
        page?.title ?? MainWindow.tr("New Tab")
    }

    func makePageView(_ page: Page, for tab: MainWindowTab) -> UIElement {
        let tabID = ObjectIdentifier(tab)
        let parts = tabPageViewPartsByID[tabID] ?? PageViewParts()
        parts.contentBorder?.child = nil
        parts.headerBorder?.child = nil
        parts.contentBorder = nil
        parts.headerBorder = nil
        tabPageViewPartsByID[tabID] = parts

        // String header: 渲染为页面顶部标题
        // UIElement header: 直接渲染到页面顶部
        // nil header: 不渲染 header 区域，content 占满整个页面
        let headerView: UIElement
        if let text = page.header as? String {
            let tb = TextBlock()
            tb.text = text
            tb.fontSize = 28
            tb.fontWeight = FontWeights.semiBold
            tb.textWrapping = .wrap
            headerView = tb
        } else if let view = page.header as? UIElement {
            headerView = view
        } else {
            return page.content
        }

        let grid = Grid()
        let autoRow = RowDefinition()
        autoRow.height = GridLength(value: 0, gridUnitType: .auto)
        let starRow = RowDefinition()
        starRow.height = GridLength(value: 1, gridUnitType: .star)
        grid.rowDefinitions.append(autoRow)
        grid.rowDefinitions.append(starRow)

        // Row 0: header — margin matches WinUI default NavigationViewHeaderMargin (56,44,0,0)
        let headerBorder = Border()
        headerBorder.margin = Thickness(left: 56, top: 44, right: 0, bottom: 0)
        MainWindow.safelyAssignChild(headerView, toBorder: headerBorder)
        parts.headerBorder = headerBorder

        // Row 1: content
        let contentBorder = Border()
        let pageContent = page.content
        MainWindow.safelyAssignChild(pageContent, toBorder: contentBorder)
        parts.contentBorder = contentBorder

        try? Grid.setRow(headerBorder, 0)
        try? Grid.setRow(contentBorder, 1)
        grid.children.append(headerBorder)
        grid.children.append(contentBorder)
        return grid
    }

    /// 把 `child` 赋值给 `border.child` 之前先显式从原 parent 断开，
    /// 防御 Page 把 UIElement 作为存储属性返回导致的 
    /// "Element is already the child of another element" WinRT 异常 ——
    /// 这种异常发生在 COM callback 路径里，会从 `try!` 抛出但传不到 Swift 主线程，
    /// 进程不会真正终止，但相关 UI 操作会失败、日志会污染。
    private static func safelyAssignChild(_ child: UIElement, toBorder border: Border) {
        detachFromVisualParent(child)
        border.child = child
    }

    /// 把 element 从其当前 visual parent 上断开。覆盖 Border / Panel / ContentControl /
    /// ContentPresenter 这几种最常见的 parent 类型。其他类型（如 ItemsControl 直接挂载
    /// arbitrary UIElement，理论上不应该出现）打日志方便排查。
    private static func detachFromVisualParent(_ element: UIElement) {
        guard let parent = try? VisualTreeHelper.getParent(element) else { return }
        if let parentBorder = parent as? Border {
            parentBorder.child = nil
        } else if let parentPanel = parent as? Panel {
            var idx: UInt32 = 0
            if parentPanel.children.indexOf(element, &idx) {
                parentPanel.children.removeAt(idx)
            }
        } else if let parentContent = parent as? ContentControl {
            parentContent.content = nil
        } else if let parentPresenter = parent as? ContentPresenter {
            parentPresenter.content = nil
        } else {
            print("[RsUI] detachFromVisualParent: unsupported parent type \(type(of: parent)) for child \(type(of: element)) — 'Element is already the child of another element' may follow")
        }
    }
}
