import Foundation
import RsHelper

public enum AppShared {
    public static let moduleManager = ModuleManager()
}

/// 模块管理器，负责模块的生命周期和注册
public final class ModuleManager: @unchecked Sendable {    
    private var modules: [String: Module] = [:]
    var initializedModules: [Module] = []
    
    init() {}
    
    /// 注册并初始化一个模块
    func register(_ module: Module, context: ModuleContext) {
        log.info("[ModuleManager] Registering module: \(module.id)")
        modules[module.id] = module
        module.initialize(context: context)

        initializedModules.append(module)
    }
}
