// 앱 타깃 — 순수 로직 (작업 024: ReadinessModel.swift에서 옮김, `swift test` 대상)
import Foundation

/// 준비 상태 항목 하나
nonisolated struct ReadinessItem: Identifiable, Equatable {
    /// 문제를 고치는 버튼이 하는 일
    /// (Spotify 로그인 버튼은 없음 — 로그인/로그아웃은 메인 화면 "Spotify" 칸에서만, 작업 018 검토 1차)
    nonisolated enum Fix: Equatable {
        case openSettings     // 이 앱의 설정 화면 열기
        case requestLocation  // 위치 권한 요청 (사용자가 눌렀을 때만)
    }

    let id: String
    let title: String
    let isReady: Bool
    /// ✅일 때 보여 줄 짧은 설명 (예: "앱 사용 중")
    var okDetail: String?
    /// ❌일 때 이유 한 줄
    var problem: String?
    /// ❌일 때 설정 경로 안내
    var hint: String?
    var fix: Fix?
    var fixTitle: String?
}

// MARK: - 순수 판단 (작업 018 검토 1차, 단위 테스트 대상)

/// 준비 상태 라벨 3단계 (작업 018 검토 1차)
nonisolated enum ReadinessSummary: Equatable {
    case ready                  // 전부 ✅ (항목 없음 포함)
    case partial(problems: Int) // ✅와 ❌가 섞임 → ⚠️
    case notReady(problems: Int) // 전부 ❌ → ❌ (Optional.none과 헷갈리지 않게 이름 변경, 리뷰 반영)
}

/// 준비 상태 순수 판단 (작업 018 검토 1차, 024에서 ReadinessModel 밖으로 이동)
nonisolated enum ReadinessRules {
    /// 항목들로 라벨 단계 정하기
    static func summary(_ items: [ReadinessItem]) -> ReadinessSummary {
        let problems = items.filter { !$0.isReady }.count
        if problems == 0 { return .ready }
        return problems == items.count ? .notReady(problems: problems) : .partial(problems: problems)
    }

    /// Spotify 로그인 항목 만들기 (버튼 없음 — 로그인/로그아웃은 Spotify 칸에서만)
    static func spotifyItem(isConfigured: Bool, isLoggedIn: Bool, needsRelogin: Bool) -> ReadinessItem {
        let id = "spotify", title = "Spotify 로그인"
        if !isConfigured {
            return ReadinessItem(id: id, title: title, isReady: false,
                                 problem: "SpotifyConfig.swift에 Client ID를 넣어 주세요")
        }
        if !isLoggedIn {
            return ReadinessItem(id: id, title: title, isReady: false, problem: "로그인이 필요해요")
        }
        if needsRelogin {
            return ReadinessItem(id: id, title: title, isReady: false,
                                 problem: "Spotify 칸에서 로그아웃 후 다시 로그인해 주세요")
        }
        return ReadinessItem(id: id, title: title, isReady: true, okDetail: "로그인됨")
    }
}
