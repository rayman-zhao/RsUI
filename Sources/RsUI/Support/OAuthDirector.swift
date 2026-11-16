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
    public let provider: String
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

public struct ProviderFailure: Equatable, Sendable {
    public let provider: String
    public let error: OAuthError
}

/// OAuth 2.0 客户端核心（授权码 + PKCE，基于 WinAppSDK OAuth2Manager）。GUI 观察
/// `authorizingProvider`/`sessions`/`lastFailure`；多提供方各自持有会话，授权
/// 串行——同一时刻至多一个授权进行中，完成或取消后方可登录下一个。access token
/// 内存持有，refresh token 作为长期凭据存 PasswordVault（用户级加密隔离，resource
/// 按应用身份派生），进程重启后经 `signIn` 的恢复路径或 `restoreSessions` 续用。
/// 协议激活回调由 `App.onActivated` 统一认领，无需使用方介入。
@MainActor @Observable
public class OAuthDirector {
    /// 进行中的授权（至多一个），nil = 空闲。
    public private(set) var authorizingProvider: String?
    /// 已建立的会话，key = provider.key。
    public private(set) var sessions: [String: OAuthSession] = [:]
    /// 最近一次失败及其归属提供方（主动取消不计入，任一成功即清空），GUI 展示用。
    public private(set) var lastFailure: ProviderFailure?

    @ObservationIgnored private var authOperation: AnyIAsyncOperation<AuthRequestResult?>?
    @ObservationIgnored private var cancellationRequested = false

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
        if sessions[provider.key] != nil { return try await refresh(provider) }
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
            try await authorizeAndExchange(provider, window: window)
        } catch {
            if cancellationRequested {
                // 主动取消：静默收尾，不记 lastFailure
                throw OAuthError(stage: .authorize, error: "cancelled", errorDescription: "")
            }
            let wrapped =
                error as? OAuthError
                ?? OAuthError(stage: .authorize, error: "\(error)", errorDescription: "")
            lastFailure = ProviderFailure(provider: provider.key, error: wrapped)
            throw wrapped
        }
        return sessions[provider.key]!
    }

    /// 取消进行中的授权：挂起的等待以 cancelled 错误返回；浏览器侧该请求的
    /// state 已无配对，迟到的回调会被 completeAuthRequest 自然拒绝。
    public func cancelAuthorization() {
        guard authorizingProvider != nil else { return }
        cancellationRequested = true
        try? authOperation?.cancel()
    }

    /// 启动恢复：对给定 providers 中 vault 存有凭据的逐个串行静默续期，失败
    /// （离线/凭据失效）跳过且凭据保留——保持未登录，留待下次 signIn 再试。
    public func restoreSessions(for providers: [OAuthProvider]) async {
        for provider in providers where storedRefreshToken(for: provider) != nil {
            _ = try? await refresh(provider)
        }
    }

    /// 用该提供方保存的 refresh token 换新 access token（启动恢复同一路径）。
    @discardableResult
    private func refresh(_ provider: OAuthProvider) async throws -> OAuthSession {
        guard authorizingProvider == nil else {
            throw OAuthError(stage: .authorize, error: "authorization_in_progress", errorDescription: "")
        }
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
                error: failure?.error ?? "no_response",
                errorDescription: failure?.errorDescription ?? "")
        }

        adopt(token, for: provider)
        return sessions[provider.key]!
    }

    /// token 取用口：临期（余量 10 分钟）先续期再返回，调用方不感知
    /// expiry/refresh——发请求处逐次经此取用，勿直接读 sessions 的 token。
    public func validAccessToken(for provider: OAuthProvider) async throws -> String {
        guard var session = sessions[provider.key] else {
            throw OAuthError(stage: .token, error: "not_signed_in", errorDescription: "")
        }
        if session.expiry < Date().addingTimeInterval(600) {
            session = try await refresh(provider)
        }
        return session.accessToken
    }

    /// 本地清理：清会话与保存的 refresh token（不吊销，见框架约定）。
    public func signOut(of provider: OAuthProvider) {
        sessions[provider.key] = nil
        storeRefreshToken(nil, for: provider)
    }

    // MARK: - Private

    /// 授权码 + PKCE 全流程：系统浏览器授权 → 换码。code challenge/verifier
    /// 由 OAuth2Manager 内部生成配对，公共客户端不传 ClientAuthentication。
    private func authorizeAndExchange(_ provider: OAuthProvider, window: WindowId) async throws {
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
                error: failure?.error ?? "no_response",
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
                error: failure?.error ?? "no_response",
                errorDescription: failure?.errorDescription ?? "")
        }

        adopt(token, for: provider)
    }

    private func adopt(_ token: TokenResponse, for provider: OAuthProvider) {
        sessions[provider.key] = OAuthSession(
            provider: provider.key,
            accessToken: token.accessToken,
            tokenType: token.tokenType,
            // expiresIn 为 0（未返回）时按官方示例默认 1 小时
            expiry: Self.expiry(fromExpiresIn: token.expiresIn))
        lastFailure = nil
        storeRefreshToken(token.refreshToken, for: provider)
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
