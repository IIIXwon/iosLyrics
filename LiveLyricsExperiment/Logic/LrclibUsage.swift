// 앱 타깃 — 작업 017: LRCLIB 호출 수 기록 (개발자 메뉴 표시용)
//
// LRCLIB 한도는 "분당" 기준이라, 날짜별·종류별 횟수와 함께 "가장 많이 부른 1분"의 횟수도 저장해요.
import Foundation

/// LRCLIB 호출 수 (날짜별·종류별, 최근 7일). `UserDefaults`에 저장
nonisolated enum LrclibUsage {
    enum Kind: String, CaseIterable {
        case get      // 1단계 정확 조회 (/api/get)
        case search   // 2~4단계 검색 (/api/search)

        var label: String {
            switch self {
            case .get: return "정확 조회"
            case .search: return "검색"
            }
        }
    }

    // [날짜 "2026-10-28": [종류·minute·minuteCount·peak: 값]]
    private static let store = DailyUsageStore(key: "lrclibCallCounts")
    private static let minuteKey = "minute"        // 현재 분 (HH*60+mm)
    private static let minuteCountKey = "minuteCount"
    private static let peakKey = "peak"

    /// 서버가 응답한 요청마다 1회 기록 (상태 코드 무관, 응답이 없던 요청은 세지 않음)
    static func record(_ kind: Kind) {
        // now: 날짜 키와 같은 시각으로 분 키를 계산
        store.update { day, now in
            day[kind.rawValue, default: 0] += 1
            let c = Calendar.current.dateComponents([.hour, .minute], from: now)
            day = updatedPeak(day, minute: String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0))
        }
    }

    /// 순수 함수: 이번 호출의 분 키("10:00")로 minute·minuteCount·peak를 갱신 (종류별 횟수 키는 그대로)
    static func updatedPeak(_ day: [String: Int], minute: String) -> [String: Int] {
        var result = day
        let parts = minute.split(separator: ":").compactMap { Int($0) }
        let minuteValue = parts.count == 2 ? parts[0] * 60 + parts[1] : 0
        // 같은 분이면 이어서 세고, 분이 바뀌었거나 처음이면 1부터
        let sameMinute = result[minuteKey] == minuteValue && result[minuteCountKey] != nil
        let count = sameMinute ? (result[minuteCountKey] ?? 0) + 1 : 1
        result[minuteKey] = minuteValue
        result[minuteCountKey] = count
        result[peakKey] = max(result[peakKey] ?? 0, count)
        return result
    }

    /// daysAgo일 전(0 = 오늘)의 종류별 호출 수
    static func counts(daysAgo: Int) -> [Kind: Int] {
        let day = store.day(daysAgo: daysAgo)
        var result: [Kind: Int] = [:]
        for kind in Kind.allCases { result[kind] = day[kind.rawValue] ?? 0 }
        return result
    }

    static func total(daysAgo: Int) -> Int {
        counts(daysAgo: daysAgo).values.reduce(0, +)
    }

    /// 그날 가장 많이 부른 1분의 호출 수
    static func peak(daysAgo: Int) -> Int {
        store.day(daysAgo: daysAgo)[peakKey] ?? 0
    }

    /// "정확 조회 4 · 검색 8 · 1분 최고 5회"
    static func summary(daysAgo: Int) -> String {
        let counts = counts(daysAgo: daysAgo)
        let kinds = Kind.allCases.map { "\($0.label) \(counts[$0] ?? 0)" }
        return (kinds + ["1분 최고 \(peak(daysAgo: daysAgo))회"]).joined(separator: " · ")
    }
}
