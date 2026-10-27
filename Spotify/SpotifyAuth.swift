// 앱 타깃 — Spotify 로그인 (Authorization Code + PKCE), 토큰 저장·갱신
import Combine
import CryptoKit
import Foundation
import Security

enum SpotifyAuthError: LocalizedError {
    case notConfigured
    case notLoggedIn
    case denied(String)
    case invalidCallback
    case tokenFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "SpotifyConfig.swift에 Client ID를 넣어 주세요"
        case .notLoggedIn: return "Spotify에 로그인되어 있지 않아요"
        case .denied(let reason): return "Spotify가 로그인을 거부했어요 (\(reason))"
        case .invalidCallback: return "로그인 응답이 올바르지 않아요"
        case .tokenFailed(let code, let body): return "토큰 발급 실패 (HTTP \(code)): \(body)"
        }
    }
}

@MainActor
final class SpotifyAuth: ObservableObject {
    @Published private(set) var isLoggedIn = false
    /// 로그인은 돼 있지만 그때 받은 권한(scope)이 지금 필요한 것보다 적을 때 true → 다시 로그인 필요
    @Published private(set) var needsRelogin = false

    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date = .distantPast
    private var pendingVerifier: String?
    private var pendingState: String?
    private var refreshTask: Task<String, Error>?

    private static let refreshTokenKey = "spotify.refreshToken"
    /// 로그인했을 때 요청한 권한 목록을 기록해 두는 키 (권한이 늘었는지 비교용)
    private static let grantedScopesKey = "spotify.grantedScopes"
    private static var currentScopes: String { SpotifyConfig.scopes.joined(separator: " ") }

    init() {
        refreshToken = Keychain.read(Self.refreshTokenKey)
        isLoggedIn = refreshToken != nil
        needsRelogin = isLoggedIn && !Self.hasRequiredScopes
    }

    /// 로그인했을 때 받은 권한에 지금 필요한 권한이 모두 들어 있는지 (권한이 줄어든 경우엔 다시 로그인하지 않아도 됨, 작업 010)
    private static var hasRequiredScopes: Bool {
        let granted = Set((UserDefaults.standard.string(forKey: grantedScopesKey) ?? "").split(separator: " ").map(String.init))
        return Set(SpotifyConfig.scopes).isSubset(of: granted)
    }

    // MARK: - 로그인

    /// 브라우저로 열 Spotify 로그인 주소
    func makeAuthorizeURL() throws -> URL {
        guard SpotifyConfig.isConfigured else { throw SpotifyAuthError.notConfigured }
        let verifier = PKCE.makeVerifier()
        let state = UUID().uuidString
        pendingVerifier = verifier
        pendingState = state

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: SpotifyConfig.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            .init(name: "scope", value: SpotifyConfig.scopes.joined(separator: " ")),
            .init(name: "state", value: state),
        ]
        return components.url!
    }

    /// 로그인 후 돌아온 주소(livelyrics://callback?code=...)로 토큰 받기
    func handleCallback(_ url: URL) async throws {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") { throw SpotifyAuthError.denied(error) }
        guard let code = value("code"),
              value("state") == pendingState,
              let verifier = pendingVerifier
        else { throw SpotifyAuthError.invalidCallback }

        try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectURI,
            "client_id": SpotifyConfig.clientID,
            "code_verifier": verifier,
        ])
        pendingVerifier = nil
        pendingState = nil
        UserDefaults.standard.set(Self.currentScopes, forKey: Self.grantedScopesKey)
        needsRelogin = false
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        expiresAt = .distantPast
        Keychain.delete(Self.refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: Self.grantedScopesKey)
        isLoggedIn = false
        needsRelogin = false
    }

    // MARK: - 토큰

    /// 유효한 액세스 토큰 (만료 1분 전이면 자동 갱신)
    func validAccessToken() async throws -> String {
        if let accessToken, expiresAt.timeIntervalSinceNow > 60 { return accessToken }
        return try await refresh()
    }

    /// 리프레시 토큰으로 새 액세스 토큰 받기 (동시에 여러 번 불려도 한 번만 요청)
    func refresh() async throws -> String {
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken else { throw SpotifyAuthError.notLoggedIn }

        let task = Task { () throws -> String in
            try await self.requestToken([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": SpotifyConfig.clientID,
            ])
            guard let token = self.accessToken else { throw SpotifyAuthError.notLoggedIn }
            return token
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func requestToken(_ params: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params).data(using: .utf8)
        request.timeoutInterval = 15

        APIUsage.record(.token)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if status == 400, body.contains("invalid_grant") { logout() }  // 리프레시 토큰 만료·취소
            throw SpotifyAuthError.tokenFailed(status, body)
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int
            let refresh_token: String?
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = token.access_token
        expiresAt = Date().addingTimeInterval(TimeInterval(token.expires_in))
        if let newRefresh = token.refresh_token {   // Spotify가 새 리프레시 토큰을 줄 때마다 교체
            refreshToken = newRefresh
            Keychain.save(newRefresh, for: Self.refreshTokenKey)
        }
        isLoggedIn = true
    }

    private static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
    }
}

// MARK: - PKCE

enum PKCE {
    static func makeVerifier() -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in chars.randomElement()! })
    }

    static func challenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - 키체인 (리프레시 토큰 보관)

enum Keychain {
    static func save(_ value: String, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        // 화면이 잠겨 있어도 읽을 수 있게 (잠금 상태에서 토큰 갱신이 필요하므로)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
