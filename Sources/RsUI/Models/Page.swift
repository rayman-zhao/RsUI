import Foundation
import Observation
import UWP
import WinUI

// 页面为 UI 线程对象：协议显式 @MainActor（实现者多为 WinUI 子类，隐式继承本隔离）。
@MainActor public protocol Page: AnyObject {
    /// 框架持有的视图缓存槽位(nil = 待建):框架发现 nil 时调 makeView
    /// 构建并回填。页勿直接读写——形态更新走
    /// WindowContext.updateView(of: self)(失效+按需重挂一步完成),
    /// 外观失效由框架批量处理
    var view: UIElement? { get set }

    var url: URL { get }
    var title: String { get }
    var header: Any? { get }
    /// 模板路径的内容区原料;nil = 仅 header 形态(headerBorder 占满
    /// 整页,居中类全页 UI 用)。覆写 makeView 的页无须实现
    var content: UIElement? { get }

    /// 整页视图构建(框架在 view 为 nil 时调用):默认实现组装
    /// header/content 模板;整页自定义布局的页覆写本定制点
    func makeView() -> UIElement
    /// Callback when the page is attached to a window (before its content is
    /// first rendered), when the page is moved to another window (tab tear-out
    /// or merge), or when the window enter/exit fullscreen state.
    ///
    /// This is the single entry point for obtaining the WindowContext: a page
    /// that needs it should store it here — do not take it from the module
    /// factory / init. A page that changes fullscreen-derived UI (button text
    /// or icon) should also refresh it here; note the callback may fire before
    /// the page's content is first built.
    func windowContextDidChange(to context: WindowContext)
}

// MARK: - 默认实现

extension Page {
    public var header: Any? { nil }

    /// makeView 默认实现:组装 header/content 模板。整页自定义的页覆写
    /// 协议定制点 makeView();登录态等条件下回到模板组装须显式调
    /// makeTemplateView()——协议默认实现无法经 super 到达
    public func makeView() -> UIElement {
        makeTemplateView()
    }

    public func makeTemplateView() -> UIElement {
        let content = self.content

        // 无 header:content 直接作视图根,连容器都省;两者皆无为退化空页
        guard let header else {
            return content ?? Grid()
        }

        let grid = Grid()

        // headerBorder 边距:WinUI 默认 NavigationViewHeaderMargin (56,44,0,0)
        // 过大,对齐 Photos 应用的 (32,28,0,28)
        let headerBorder = Border()
        headerBorder.margin = WinUI.Thickness(left: 32, top: 28, right: 0, bottom: 28)
        if let text = header as? String {
            let headerText = TextBlock()
            headerText.text = text
            // TitleTextBlockStyle 的对齐值——库层样式键对程序化查询不可见,
            // 写死数值(WinUI Title 字阶)
            headerText.fontSize = 28
            headerText.fontWeight = UWP.FontWeights.semiBold
            headerBorder.child = headerText
        } else if let element = header as? UIElement {
            headerBorder.child = element
        }
        try? Grid.setRow(headerBorder, 0)
        grid.children.append(headerBorder)

        if let content {
            let headerRow = RowDefinition()
            headerRow.height = GridLength(value: 0, gridUnitType: .auto)
            grid.rowDefinitions.append(headerRow)
            let contentRow = RowDefinition()
            contentRow.height = GridLength(value: 1, gridUnitType: .star)
            grid.rowDefinitions.append(contentRow)

            // setRow 只收 FrameworkElement,content 协议形态是 UIElement,
            // 经无样式 Border 透传挂行
            let contentBorder = Border()
            contentBorder.child = content
            try? Grid.setRow(contentBorder, 1)
            grid.children.append(contentBorder)
        }
        // content 为 nil(仅 header 形态)时不加行定义:Grid 默认单 * 行,
        // headerBorder 占满整页,页内自行布局

        return grid
    }

    public func windowContextDidChange(to context: WindowContext) {}
}
