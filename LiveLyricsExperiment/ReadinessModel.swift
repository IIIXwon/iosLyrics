// 앱 타깃 — 작업 004: "준비 상태" 확인 (Spotify 로그인 · 위치 서비스 · 위치 권한 · 실시간 현황)
//
// 이 앱은 설정이 하나만 빠져도 조용히 안 돼서(위치 권한이 꺼지면 가사가 멈추고, 실시간 현황이 꺼지면 카드가 안 뜸),
// 무엇이 빠졌는지와 고치는 방법을 화면 맨 위에 보여 주기 위한 모델이에요.
// 확인만 하고 백그라운드 동작·카드 갱신에는 관여하지 않아요.
import ActivityKit
import Combine
import CoreLocation
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

@MainActor
final class ReadinessModel: ObservableObject {
    @Published private(set) var items: [ReadinessItem] = []

    var onLog: (@MainActor (String) -> Void)?

    private let auth: SpotifyAuth
    private let location: LocationKeepAlive
    private var servicesEnabled = true            // 기기 전체 위치 서비스 (마지막으로 확인한 값)
    private var previousReady: [String: Bool] = [:]

    var hasProblem: Bool { items.contains { !$0.isReady } }

    init(auth: SpotifyAuth, location: LocationKeepAlive) {
        self.auth = auth
        self.location = location
        apply(logChanges: false)
        refresh(logChanges: false)

        // 설정 앱에서 실시간 현황을 켜고 끄면 바로 반영
        Task {
            for await _ in ActivityAuthorizationInfo().activityEnablementUpdates {
                refresh()
            }
        }
    }

    /// 다시 확인. 앱이 화면으로 돌아올 때, 위치 권한이 바뀔 때, 로그인·로그아웃 뒤에 부름
    func refresh(logChanges: Bool = true) {
        apply(logChanges: logChanges)
        // 기기 전체 위치 서비스 확인은 메인 스레드를 막을 수 있어서 따로 실행
        Task {
            let enabled = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
            servicesEnabled = enabled
            apply(logChanges: logChanges)
        }
    }

    /// 확인이 끝날 때까지 기다리는 버전 (자동 시작이 "준비 상태가 모두 ✅인지" 판단하기 직전에 사용)
    func refreshAndWait() async {
        apply(logChanges: true)
        let enabled = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        servicesEnabled = enabled
        apply(logChanges: true)
    }

    private func apply(logChanges: Bool) {
        let new = makeItems()
        if logChanges {
            for item in new {
                if let old = previousReady[item.id], old != item.isReady {
                    onLog?("🧭 준비 상태: \(item.title) \(old ? "✅" : "❌") → \(item.isReady ? "✅" : "❌")")
                }
            }
        }
        for item in new { previousReady[item.id] = item.isReady }
        if new != items { items = new }
    }

    private func makeItems() -> [ReadinessItem] {
        // ① Spotify 로그인 (버튼 없음 — 로그인/로그아웃은 "Spotify" 칸에서)
        let spotify = Self.spotifyItem(isConfigured: SpotifyConfig.isConfigured,
                                       isLoggedIn: auth.isLoggedIn,
                                       needsRelogin: auth.needsRelogin)

        // ①-2 Spotify 조회 (호출 한도로 막혔는지) — 막혀 있으면 자동 시작도 하지 않음
        let quota: ReadinessItem
        if let until = SpotifyBlock.until {
            quota = ReadinessItem(
                id: "spotifyQuota", title: "Spotify 조회", isReady: false,
                problem: "호출 한도 초과 · \(SpotifyBlock.untilText(until)) 이후 재개")
        } else {
            quota = ReadinessItem(id: "spotifyQuota", title: "Spotify 조회", isReady: true, okDetail: "정상")
        }

        // ② 위치 서비스 (기기 전체)
        let services: ReadinessItem
        if servicesEnabled {
            services = ReadinessItem(id: "locationServices", title: "위치 서비스", isReady: true, okDetail: "켜짐")
        } else {
            services = ReadinessItem(
                id: "locationServices", title: "위치 서비스", isReady: false,
                problem: "아이폰의 위치 서비스가 꺼져 있어요",
                // 앱은 아이폰 전체의 위치 서비스 화면으로 바로 갈 수 없고(열 수 있는 건 '이 앱'의 설정 화면뿐),
                // 그래서 이 항목에는 버튼 없이 직접 찾아가는 경로만 안내함
                hint: "아이폰 설정 앱 → 개인정보 보호 및 보안 → 위치 서비스 → 맨 위 '위치 서비스'를 켜 주세요 (이 앱의 설정 화면이 아니라 아이폰 전체 설정이에요)")
        }

        // ③ 위치 권한 (이 앱) — "앱 사용 중"이면 충분, "항상 허용"은 요구하지 않음
        let permission: ReadinessItem
        switch location.authorization {
        case .authorizedWhenInUse, .authorizedAlways:
            permission = ReadinessItem(id: "locationPermission", title: "위치 권한", isReady: true,
                                       okDetail: location.authorizationText)
        case .notDetermined:
            permission = ReadinessItem(
                id: "locationPermission", title: "위치 권한", isReady: false,
                problem: "위치 권한을 허용해 주세요",
                fix: .requestLocation, fixTitle: "권한 요청")
        default:   // 거부 · 제한
            permission = ReadinessItem(
                id: "locationPermission", title: "위치 권한", isReady: false,
                problem: "꺼져 있으면 잠금화면 가사가 몇 초 뒤 멈춰요",
                hint: "설정 → 이 앱 → 위치 → '앱을 사용하는 동안'",
                fix: .openSettings, fixTitle: "설정 열기")
        }

        // ④ 실시간 현황 (Live Activity)
        let liveActivity: ReadinessItem
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            liveActivity = ReadinessItem(id: "liveActivity", title: "실시간 현황", isReady: true, okDetail: "켜짐")
        } else {
            liveActivity = ReadinessItem(
                id: "liveActivity", title: "실시간 현황", isReady: false,
                problem: "꺼져 있으면 잠금화면 카드가 뜨지 않아요",
                hint: "설정 → 이 앱 → 실시간 현황",
                fix: .openSettings, fixTitle: "설정 열기")
        }

        // 문제가 있는 항목을 위로 (순서는 유지)
        let all = [spotify, quota, services, permission, liveActivity]
        return all.filter { !$0.isReady } + all.filter { $0.isReady }
    }
}

// MARK: - 순수 판단 (작업 018 검토 1차, 단위 테스트 대상)

/// 준비 상태 라벨 3단계 (작업 018 검토 1차)
nonisolated enum ReadinessSummary: Equatable {
    case ready                  // 전부 ✅ (항목 없음 포함)
    case partial(problems: Int) // ✅와 ❌가 섞임 → ⚠️
    case notReady(problems: Int) // 전부 ❌ → ❌ (Optional.none과 헷갈리지 않게 이름 변경, 리뷰 반영)
}

extension ReadinessModel {
    /// 항목들로 라벨 단계 정하기
    nonisolated static func summary(_ items: [ReadinessItem]) -> ReadinessSummary {
        let problems = items.filter { !$0.isReady }.count
        if problems == 0 { return .ready }
        return problems == items.count ? .notReady(problems: problems) : .partial(problems: problems)
    }

    /// Spotify 로그인 항목 만들기 (버튼 없음 — 로그인/로그아웃은 Spotify 칸에서만)
    nonisolated static func spotifyItem(isConfigured: Bool, isLoggedIn: Bool, needsRelogin: Bool) -> ReadinessItem {
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
