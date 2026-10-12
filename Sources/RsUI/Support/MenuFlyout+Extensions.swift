import WinUI

extension MenuFlyout {
    /// MenuFlyout 不是 FrameworkElement。
    /// 获取 XAML 中必须存在的命名控件。名称或类型不匹配属于开发错误，应立即崩溃并明确指出位置。
    public func requireElement<T>(_ name: String) -> T {
        do {
            for item in items {
                guard let item else { continue }
                guard let obj = try item.findName(name) else { continue }
                guard let element = obj as? T else {
                    fatalError("The element \(name) is not a type of \(T.self)")
                }
                return element
            }
        } catch {
            fatalError("Find element failed with error: \(error)")
        }

        fatalError("The \(Self.self) missing element named: \(name)")
    }
}
