// 앱 타깃 — 작업 008: Spotify Web API 호출 수 기록 + 호출 한도(429) 차단 상태
//
// Spotify 개발자 모드는 하루 누적 호출 한도가 있어서, 한도를 넘으면 수 시간 동안 모든 요청이 막혀요.
// 그래서 (1) 호출 수를 날짜별·종류별로 세어 두고, (2) 크게 막혔을 땐 그 시각까지 아예 호출하지 않아요.
import Foundation

/// Spotify Web API 호출 수 (날짜별·종류별, 최근 7일). `UserDefaults`에 저장
nonisolated enum APIUsage {
    enum Kind: String, CaseIterable {
        case state     // 재생 상태 조회 (/me/player)
        case play      // 재생 요청 (play · 재생 기기 이전)
        case devices   // 기기 목록
        case token     // 토큰 갱신·발급 (accounts.spotify.com)

        var label: String {
            switch self {
            case .state: return "재생 상태 조회"
            case .play: return "재생 요청"
            case .devices: return "기기 목록"
            case .token: return "토큰 갱신"
            }
        }
    }

    private static let key = "spotifyAPICallCounts"   // [날짜 "2026-10-27": [종류: 횟수]]

    /// 실제로 요청을 보내기 직전에 1회 기록
    static func record(_ kind: Kind) {
        var all = load()
        all[dayKey(daysAgo: 0), default: [:]][kind.rawValue, default: 0] += 1
        // 최근 7일만 남김
        let keep = Set(all.keys.sorted().suffix(7))
        all = all.filter { keep.contains($0.key) }
        UserDefaults.standard.set(all, forKey: key)
    }

    /// daysAgo일 전(0 = 오늘)의 종류별 호출 수
    static func counts(daysAgo: Int) -> [Kind: Int] {
        let day = load()[dayKey(daysAgo: daysAgo)] ?? [:]
        var result: [Kind: Int] = [:]
        for kind in Kind.allCases { result[kind] = day[kind.rawValue] ?? 0 }
        return result
    }

    static func total(daysAgo: Int) -> Int {
        counts(daysAgo: daysAgo).values.reduce(0, +)
    }

    /// "재생 상태 조회 120 · 재생 요청 2 · 기기 목록 0 · 토큰 갱신 3"
    static func summary(daysAgo: Int) -> String {
        let counts = counts(daysAgo: daysAgo)
        return Kind.allCases.map { "\($0.label) \(counts[$0] ?? 0)" }.joined(separator: " · ")
    }

    private static func load() -> [String: [String: Int]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Int]] ?? [:]
    }

    private static func dayKey(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// 호출 한도(429)로 크게 막혔을 때의 재개 시각. 앱을 껐다 켜도 유지
/// 이 시각 전에는 Spotify Web API를 전혀 호출하지 않음
nonisolated enum SpotifyBlock {
    private static let key = "spotifyBlockedUntil"

    /// 차단 중이면 재개 시각, 아니면 nil (재개 시각이 지났으면 저장값을 지움)
    static var until: Date? {
        let t = UserDefaults.standard.double(forKey: key)
        guard t > 0 else { return nil }
        if t > Date().timeIntervalSince1970 { return Date(timeIntervalSince1970: t) }
        UserDefaults.standard.removeObject(forKey: key)
        return nil
    }

    static func set(_ until: Date) {
        UserDefaults.standard.set(until.timeIntervalSince1970, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// "오전 10:11" (오늘이 아니면 날짜도: "2026년 10월 27일 오전 10:11")
    static func untilText(_ until: Date) -> String {
        Calendar.current.isDateInToday(until)
            ? until.formatted(date: .omitted, time: .shortened)
            : until.formatted(date: .abbreviated, time: .shortened)
    }
}
