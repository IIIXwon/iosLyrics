// 앱 타깃 — Spotify 개발자 앱 설정값
import Foundation

enum SpotifyConfig {
    /// Client ID는 `SpotifySecrets.swift`에 있어요 (예시: `SpotifySecrets.swift.example`)
    static let clientID = SpotifySecrets.clientID

    /// 대시보드의 Redirect URIs에 이 값을 "정확히 똑같이" 등록해야 해요
    static let redirectURI = "livelyrics://callback"
    static let callbackScheme = "livelyrics"

    /// 필요한 권한: SDK(App Remote) 연결 + 현재 재생 곡·재생 상태 읽기 (재생 제어는 하지 않음, 작업 026)
    /// 작업 032: 로그인 = Spotify 앱 승인 1번(SpotifyRemote). 그 세션 토큰을 SDK 연결과 Web API 폴링에 함께 쓰므로
    /// app-remote-control(SDK 연결용)과 Web API 읽기 권한을 한 번에 요청함
    /// ⚠️ 권한을 추가하면 로그아웃 후 다시 로그인해야 반영돼요 (줄이는 건 다시 로그인하지 않아도 됨, LoginScopes)
    static let scopes = ["app-remote-control", "user-read-currently-playing", "user-read-playback-state"]

    static var isConfigured: Bool { !clientID.contains("여기에") && !clientID.isEmpty }
}
