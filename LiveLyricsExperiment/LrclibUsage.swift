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

    private static let key = "lrclibCallCounts"   // [날짜 "2026-10-28": [종류·minute·minuteCount·peak: 값]]
    private static let minuteKey = "minute"        // 현재 분 (HH*60+mm)
    private static let minuteCountKey = "minuteCount"
    private static let peakKey = "peak"

    /// 실제로 요청을 보내기 직전에 1회 기록
    static func record(_ kind: Kind) {
        var all = load()
        let today = dayKey(daysAgo: 0)
        var day = all[today] ?? [:]
        day[kind.rawValue, default: 0] += 1
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        day = updatedPeak(day, minute: String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0))
        all[today] = day
        // 최근 7일만 남김
        let keep = Set(all.keys.sorted().suffix(7))
        all = all.filter { keep.contains($0.key) }
        UserDefaults.standard.set(all, forKey: key)
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
        let day = load()[dayKey(daysAgo: daysAgo)] ?? [:]
        var result: [Kind: Int] = [:]
        for kind in Kind.allCases { result[kind] = day[kind.rawValue] ?? 0 }
        return result
    }

    static func total(daysAgo: Int) -> Int {
        counts(daysAgo: daysAgo).values.reduce(0, +)
    }

    /// 그날 가장 많이 부른 1분의 호출 수
    static func peak(daysAgo: Int) -> Int {
        load()[dayKey(daysAgo: daysAgo)]?[peakKey] ?? 0
    }

    /// "정확 조회 4 · 검색 8 · 1분 최고 5회"
    static func summary(daysAgo: Int) -> String {
        let counts = counts(daysAgo: daysAgo)
        let kinds = Kind.allCases.map { "\($0.label) \(counts[$0] ?? 0)" }
        return (kinds + ["1분 최고 \(peak(daysAgo: daysAgo))회"]).joined(separator: " · ")
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
