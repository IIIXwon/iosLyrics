// 앱 타깃 — Spotify 개발자 앱 설정값
import Foundation

enum SpotifyConfig {
    /// ⚠️ Spotify 개발자 대시보드 → 내 앱 → Settings에서 Client ID를 복사해 붙여 넣으세요
    static let clientID = "내 ClientID"

    /// 대시보드의 Redirect URIs에 이 값을 "정확히 똑같이" 등록해야 해요
    static let redirectURI = "livelyrics://callback"
    static let callbackScheme = "livelyrics"

    /// 필요한 권한: 현재 재생 곡·재생 상태 읽기, 재생 제어(카드의 ▶︎ 버튼)
    /// ⚠️ 권한을 추가하면 로그아웃 후 다시 로그인해야 반영돼요 (줄이는 건 다시 로그인하지 않아도 됨)
    static let scopes = ["user-read-currently-playing", "user-read-playback-state", "user-modify-playback-state"]

    static var isConfigured: Bool { !clientID.contains("여기에") && !clientID.isEmpty }
}
