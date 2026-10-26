import Foundation

/// App identity consumed by `App` before anything else — support directories,
/// preferences and the single-instance key all derive from it. Provided by the
/// app subclass via `App.makeConfiguration()`; `nil` keeps the framework defaults.
public struct AppConfiguration {
    public let group: String
    public let product: String
    public let resourceBundle: Bundle

    public init(group: String, product: String, resourceBundle: Bundle) {
        self.group = group
        self.product = product
        self.resourceBundle = resourceBundle
    }
}
