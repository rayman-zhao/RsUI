import Foundation
import WinUI
import WindowsFoundation

extension NavigationViewItemBase {
    public var url: URL? {
        guard let tag = self.tag, let str = tag as? HString else { return nil }

        return URL(string: String(hString: str))
    }
}
