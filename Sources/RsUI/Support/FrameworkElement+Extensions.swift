import Foundation
import WinUI

extension FrameworkElement {
    /// 获取 XAML 中必须存在的命名控件。名称或类型不匹配属于开发错误，应立即崩溃并明确指出位置。
    public func requireElement<T>(_ name: String) -> T {
        do {
            guard let obj = try self.findName(name) else {
                fatalError("The \(Self.self) missing element named: \(name)")
            }
            guard let element = obj as? T else {
                fatalError("The element \(name) is not a type of \(T.self) ")
            }
            return element
        } catch {
            fatalError("Find element failed with error: \(error)")
        }
    }

    public func requireResource<T>(_ name: String) -> T {
        guard let obj = self.resources.lookup(name) else {
            fatalError("The \(Self.self) missing resource named: \(name)")
        }
        guard let res = obj as? T else {
            fatalError("The resource \(name) is not a type of \(T.self) ")
        }
        return res
    }
}
