import Foundation
import Observation
import UWP
import WinAppSDK
import WindowsFoundation

public struct OAuthProvider: Codable, Sendable {
    public let key: String
    public let displayName: String
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let clientId: String
    public let scopes: [String]
    public let redirectUri: URL
    public let accessEndpoint: URL

    public init(
        key: String,
        displayName: String,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        clientId: String,
        scopes: [String],
        redirectUri: URL,
        accessEndpoint: URL
    ) {
        self.key = key
        self.displayName = displayName
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.clientId = clientId
        self.scopes = scopes
        self.redirectUri = redirectUri
        self.accessEndpoint = accessEndpoint
    }
}

public struct OAuthSession: Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiry: Date
}

/// OAuth 失败的机器可读形态：失败阶段 + IdP 错误码。
public struct OAuthError: Swift.Error, Equatable, Sendable {
    public enum Stage: String, Sendable {
        case authorize
        case token
    }

    public let stage: Stage
    public let error: String
    public let errorDescription: String
}

/// provider 生命周期状态，`states` 的值形态。缺 key = 从未登录；有凭据但
/// 恢复/续期失败 = .failed，与从未登录区分——GUI 据此显示"登录失败/重新授权"
/// 而非"登录"。
public enum ProviderState: Sendable {
    /// 静默续期中（启动恢复 / signIn 静默路径）；已登录的临期续期不进入此态，
    /// 维持 .authenticated 不闪"登录中"。
    case refreshing
    case authenticated(OAuthSession)
    case failed(OAuthError)
}

/// OAuth 2.0 客户端核心（授权码 + PKCE，基于 WinAppSDK OAuth2Manager）。GUI 观察
/// `authorizingProvider`/`states`；多提供方各自持有状态，授权
/// 串行——同一时刻至多一个授权进行中，完成或取消后方可登录下一个。access token
/// 内存持有，refresh token 作为长期凭据存 PasswordVault（用户级加密隔离，resource
/// 按应用身份派生），进程重启后经 `signIn` 的恢复路径或 `restoreSessions` 续用。
/// 协议激活回调由 `App.onActivated` 统一认领，无需使用方介入。
@MainActor @Observable
public class OAuthDirector {
    /// 进行中的授权（至多一个），nil = 空闲。授权串行是 director 级全局互斥，
    /// 不入 states（per-provider 表达不了"至多一个"）。
    public private(set) var authorizingProvider: String?
    /// 各 provider 生命周期状态，key = provider.key；缺 key = 从未登录。
    public private(set) var states: [String: ProviderState] = [:]

    @ObservationIgnored private var authOperation: AnyIAsyncOperation<AuthRequestResult?>?
    @ObservationIgnored private var cancellationRequested = false
    @ObservationIgnored private var refreshInFlight: [String: Task<OAuthSession, any Swift.Error>] = [:]

    public init() {
    }

    /// 登录入口，按该提供方的既有状态择路：已登录静默续期；存有 refresh token
    /// 先试恢复（失效清库走完整授权）；否则发起授权码 + PKCE 流程（系统浏览器，
    /// 回调经 RsUI 协议激活认领送达，WindowId 由前端传入用于父窗口归属）。
    /// 任意授权进行中再登录（含其他提供方）会被拒绝——串行不并发。
    @discardableResult
    public func signIn(to provider: OAuthProvider, in window: WindowId) async throws -> OAuthSession {
        guard authorizingProvider == nil else {
            throw OAuthError(stage: .authorize, error: "authorization_in_progress", errorDescription: "")
        }
        if isAuthenticated(provider.key) { return try await refresh(provider) }
        if storedRefreshToken(for: provider) != nil, let session = try? await refresh(provider) {
            return session
        }

        authorizingProvider = provider.key
        cancellationRequested = false
        defer {
            authorizingProvider = nil
            cancellationRequested = false
        }

        do {
            return try await authorizeAndExchange(provider, window: window)
        } catch {
            if cancellationRequested {
                // 主动取消：静默收尾，不记状态
                throw OAuthError(stage: .authorize, error: "cancelled", errorDescription: "")
            }
            let wrapped =
                error as? OAuthError
                ?? OAuthError(stage: .authorize, error: "\(error)", errorDescription: "")
            states[provider.key] = .failed(wrapped)
            throw wrapped
        }
    }

    /// 本地清理：清状态（含失败记录）与保存的 refresh token（不吊销，见框架约定）。
    public func signOut(of provider: OAuthProvider) {
        states[provider.key] = nil
        storeRefreshToken(nil, for: provider)
    }

    /// 取消进行中的授权：挂起的等待以 cancelled 错误返回；浏览器侧该请求的
    /// state 已无配对，迟到的回调会被 completeAuthRequest 自然拒绝。
    public func cancelAuthorization() {
        guard authorizingProvider != nil else { return }
        cancellationRequested = true
        try? authOperation?.cancel()
    }

    /// 启动恢复：同步把 vault 存有凭据且未登录的 provider 置 .refreshing——
    /// 深链观察者初始发射即见 pending，勿闪登录入口（vault 条件承重：误置
    /// 从未登录者会令其经 no_refresh_token 落 .failed，与"恢复失败"混淆）；
    /// 随后异步逐个串行静默续期（.failed 会重试），失败保留凭据且转
    /// .failed——GUI 显示"登录失败"，留待再试；已登录不重刷（临期由
    /// validSession 自愈）。
    public func restoreSessions(for providers: [OAuthProvider]) {
        let pending = providers.filter {
            !isAuthenticated($0.key) && storedRefreshToken(for: $0) != nil
        }
        guard !pending.isEmpty else { return }
        for provider in pending {
            states[provider.key] = .refreshing
        }
        Task { [weak self] in
            for provider in pending {
                _ = try? await self?.refresh(provider)
            }
        }
    }

    /// 会话取用口：临期（余量 1 分钟）先续期再返回，调用方不感知
    /// expiry/refresh——发请求处逐次经此取用，勿直接读 sessions。
    public func validSession(for provider: OAuthProvider) async throws -> OAuthSession {
        guard case .authenticated(var session)? = states[provider.key] else {
            throw OAuthError(stage: .token, error: "not_signed_in", errorDescription: "")
        }
        if session.expiry < Date().addingTimeInterval(60) {
            session = try await refresh(provider)
        }
        return session
    }

    // MARK: - Private

    private func isAuthenticated(_ key: String) -> Bool {
        if case .authenticated? = states[key] { return true }
        return false
    }

    /// 用该提供方保存的 refresh token 换新 access token（启动恢复同一路径）。
    /// 同一 provider 的并发请求搭乘同一在飞任务（single-flight）：轮转 refresh
    /// token 的 IdP 会把同 token 二次使用判为重用并吊销整族凭据，并发去重是
    /// 正确性需求而非优化——actor 只串行化同步段，网络 await 的挂起窗口内
    /// 状态检查全部失效。token 阶段失败统一在此转 .failed 后 rethrow
    /// （authorize 阶段由 signIn 记录）；进入时非已登录先置 .refreshing。
    @discardableResult
    private func refresh(_ provider: OAuthProvider) async throws -> OAuthSession {
        guard authorizingProvider == nil else {
            throw OAuthError(stage: .authorize, error: "authorization_in_progress", errorDescription: "")
        }
        if let inFlight = refreshInFlight[provider.key] { return try await inFlight.value }
        if !isAuthenticated(provider.key) { states[provider.key] = .refreshing }
        let task = Task { try await performRefresh(provider) }
        refreshInFlight[provider.key] = task
        defer { refreshInFlight[provider.key] = nil }
        do {
            return try await task.value
        } catch {
            states[provider.key] = .failed(
                error as? OAuthError
                ?? OAuthError(stage: .token, error: "\(error)", errorDescription: ""))
            throw error
        }
    }

    private func performRefresh(_ provider: OAuthProvider) async throws -> OAuthSession {
        guard let refreshToken = storedRefreshToken(for: provider) else {
            throw OAuthError(stage: .token, error: "no_refresh_token", errorDescription: "")
        }

        let params: TokenRequestParams = try TokenRequestParams.createForRefreshToken(refreshToken)
        params.clientId = provider.clientId
        let result = try await OAuth2Manager.requestTokenAsync(
            Uri(provider.tokenEndpoint.absoluteString), params
        ).get()
        guard let token = result?.response else {
            let failure = result?.failure
            throw OAuthError(
                stage: .token,
                error: Self.failureCode(failure?.error),
                errorDescription: failure?.errorDescription ?? "")
        }

        return adopt(token, for: provider)
    }

    /// 授权码 + PKCE 全流程：系统浏览器授权 → 换码。code challenge/verifier
    /// 由 OAuth2Manager 内部生成配对，公共客户端不传 ClientAuthentication。
    private func authorizeAndExchange(_ provider: OAuthProvider, window: WindowId) async throws -> OAuthSession {
        let authParams: AuthRequestParams = try AuthRequestParams.createForAuthorizationCodeRequest(
            provider.clientId, Uri(provider.redirectUri.absoluteString))
        authParams.scope = provider.scopes.joined(separator: " ")
        let operation: AnyIAsyncOperation<AuthRequestResult?> = try OAuth2Manager.requestAuthWithParamsAsync(
            window, Uri(provider.authorizationEndpoint.absoluteString), authParams)
        authOperation = operation
        defer { authOperation = nil }
        let authResult = try await operation.get()
        guard let response = authResult?.response else {
            let failure = authResult?.failure
            throw OAuthError(
                stage: .authorize,
                error: Self.failureCode(failure?.error),
                errorDescription: failure?.errorDescription ?? "")
        }

        let tokenParams: TokenRequestParams = try TokenRequestParams.createForAuthorizationCodeRequest(response)
        let tokenResult = try await OAuth2Manager.requestTokenAsync(
            Uri(provider.tokenEndpoint.absoluteString), tokenParams
        ).get()
        guard let token = tokenResult?.response else {
            let failure = tokenResult?.failure
            throw OAuthError(
                stage: .token,
                error: Self.failureCode(failure?.error),
                errorDescription: failure?.errorDescription ?? "")
        }

        return adopt(token, for: provider)
    }

    /// OAuth2Manager 失败对象的 error 可能为空串（如断网无响应）而非
    /// nil——空串与 nil 统一落 no_response，保错误码非空（下游展示与
    /// 判别依赖非空；2026-11-20 断网实测空串产生过全空 OAuthError）
    private static func failureCode(_ code: String?) -> String {
        if let code, !code.isEmpty { return code }
        return "no_response"
    }

    @discardableResult
    private func adopt(_ token: TokenResponse, for provider: OAuthProvider) -> OAuthSession {
        let session = OAuthSession(
            accessToken: token.accessToken,
            tokenType: token.tokenType,
            // expiresIn 为 0（未返回）时按官方示例默认 1 小时
            expiry: Self.expiry(fromExpiresIn: token.expiresIn))
        states[provider.key] = .authenticated(session)
        storeRefreshToken(token.refreshToken, for: provider)
        return session
    }

    private static func expiry(fromExpiresIn seconds: Double) -> Date {
        return Date().addingTimeInterval(seconds > 0 ? seconds : 3600)
    }

    // PasswordVault 无进程内状态，按次构造；resource 按应用身份派生（多应用
    // 共用本库时凭据互不串），userName 放 provider.key
    private static let vaultResource = "\(App.context.groupName)/\(App.context.productName)/OAuth"

    private func storedRefreshToken(for provider: OAuthProvider) -> String? {
        let vault = PasswordVault()
        guard
            let credential = try? vault.retrieve(
                Self.vaultResource, provider.key)
        else { return nil }
        return credential.password
    }

    private func storeRefreshToken(_ refreshToken: String?, for provider: OAuthProvider) {
        let vault = PasswordVault()
        if let old = try? vault.retrieve(Self.vaultResource, provider.key) {
            try? vault.remove(old)
        }
        if let refreshToken, !refreshToken.isEmpty {
            try? vault.add(
                PasswordCredential(Self.vaultResource, provider.key, refreshToken))
        }
    }
}
