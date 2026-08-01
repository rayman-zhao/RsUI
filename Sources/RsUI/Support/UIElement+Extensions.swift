import RsFoundation
import WinUI

extension UIElement {
    /// 把 `element` 从其当前 visual parent 断开。
    ///
    /// - Returns: 返回原 parent + 该 element 在其 children 中的位置。
    /// （Border/ContentControl/ContentPresenter 的 index 无意义，统一返回 nil）。
    /// VisualTreeHelper.getParent 返回 DependencyObject，这里强转回 UIElement，
    /// 转不出即当作 unsupported parent，返回 nil。
    public func detachFromVisualParent() -> (parent: UIElement, index: UInt32?)? {
        guard let raw = try? VisualTreeHelper.getParent(self),
            let parent = raw as? UIElement
        else { return nil }

        if let parentBorder = parent as? Border {
            parentBorder.child = nil
            return (parent, nil)
        } else if let parentPanel = parent as? Panel {
            var idx: UInt32 = 0
            if parentPanel.children.indexOf(self, &idx) {
                parentPanel.children.removeAt(idx)
                return (parent, idx)
            }
        } else if let parentContent = parent as? ContentControl {
            parentContent.content = nil
            return (parent, nil)
        } else if let parentPresenter = parent as? ContentPresenter {
            parentPresenter.content = nil
            return (parent, nil)
        }

        log.warning(
            "UIElement.detachFromVisualParent: unsupported parent type \(type(of: parent)) for child \(type(of: self))"
        )
        return nil
    }

    /// 把 `element` 挂回 `parent` 的原 `index` 位置。Panel 分支 `insertAt`；若期间父元素被
    /// 截短到比 idx 还小，安全降级到末尾。Border/ContentControl/ContentPresenter 直接赋回。
    public func attachToParent(_ parent: UIElement, index: UInt32?) {
        if let parentBorder = parent as? Border {
            parentBorder.child = self
        } else if let parentPanel = parent as? Panel, let index {
            let count = UInt32(parentPanel.children.size)
            let at = min(index, count)
            parentPanel.children.insertAt(at, self)
        } else if let parentContent = parent as? ContentControl {
            parentContent.content = self
        } else if let parentPresenter = parent as? ContentPresenter {
            parentPresenter.content = self
        } else {
            log.warning(
                "UIElement.restoreToVisualParent: unsupported parent type \(type(of: parent)) — element left un-parented"
            )
        }
    }
}
