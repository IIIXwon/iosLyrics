// 앱 타깃 — 순수 로직 (작업 024: ContentView.swift에서 옮김, `swift test` 대상)
import Foundation

/// Spotify 칸에 보일 버튼 하나 (로그인 상태면 로그아웃, 아니면 로그인)
nonisolated enum SpotifyButton: Equatable {
    case login(enabled: Bool)
    case logout

    /// 로그인돼 있으면 설정과 무관하게 로그아웃만, 아니면 설정(Client ID)이 있을 때만 로그인 버튼 활성
    static func make(isLoggedIn: Bool, isConfigured: Bool) -> SpotifyButton {
        isLoggedIn ? .logout : .login(enabled: isConfigured)
    }
}

/// [시작] 버튼 상태 (작업 018 검토 2차: 로그아웃이면 회색)
nonisolated struct StartButton: Equatable {
    let enabled: Bool
    let hint: String?

    /// 로그아웃이면 비활성 + 로그인 안내, 로그인됐지만 다른 준비 항목이 ❌이면 활성 + 확인 안내
    static func make(isLoggedIn: Bool, hasProblem: Bool) -> StartButton {
        if !isLoggedIn {
            return StartButton(enabled: false, hint: "Spotify에 로그인하면 시작할 수 있어요")
        }
        return StartButton(enabled: true, hint: hasProblem ? "준비 상태를 먼저 확인해 주세요" : nil)
    }
}
