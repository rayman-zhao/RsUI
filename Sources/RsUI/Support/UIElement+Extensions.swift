import RsFoundation
import WinUI

extension UIElement {
    /// 把 `element` 从其当前 visual parent 断开。
    ///
    /// - Returns: 返回原 parent + 该 element 在其 children 中的位置。
    /// （Border/Viewbox/ContentControl/ContentPresenter 的 index 无意义，统一返回 nil）。
    /// 父级解析优先 `FrameworkElement.parent`（逻辑父级）：它在子树未加载进可视树时依然有效
    /// （例如页面构造期间），且直接指向持有 child/content 属性的容器本身；构造中的子树里
    /// `VisualTreeHelper.getParent` 返回 nil，模板内部元素也只会误导。两者都拿不到即当作
    /// 无父级，返回 nil。
    public func detachFromVisualParent() -> (parent: UIElement, index: UInt32?)? {
        let logicalParent: DependencyObject? = (self as? FrameworkElement)?.parent
        let raw = logicalParent ?? (try? VisualTreeHelper.getParent(self))
        guard let parent = raw as? UIElement
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
        } else if let parentViewbox = parent as? Viewbox {
            // Viewbox 直接继承 FrameworkElement（非 ContentControl），child 即单子挂点。
            parentViewbox.child = nil
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
        } else if let parentViewbox = parent as? Viewbox {
            parentViewbox.child = self
        } else {
            log.warning(
                "UIElement.restoreToVisualParent: unsupported parent type \(type(of: parent)) — element left un-parented"
            )
        }
    }
}
