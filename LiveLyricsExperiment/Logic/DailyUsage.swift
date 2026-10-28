// 앱 타깃 — 작업 017(중복 정리): 날짜별 호출 수 기록의 공통 저장소
//
// Spotify 호출 수(`APIUsage`)와 LRCLIB 호출 수(`LrclibUsage`)가 같은 방식으로 저장돼서
// 날짜 키 계산·불러오기·저장·최근 7일 정리·잠금을 여기 한 곳에 모았어요.
// 저장 형식: UserDefaults[key] = [날짜 "2026-10-28": [이름: 값]]
import Foundation

/// 날짜별 `[String: Int]` 기록을 `UserDefaults`에 저장 (최근 7일만 유지)
nonisolated struct DailyUsageStore: Sendable {
    let key: String
    private let lock = NSLock()

    init(key: String) {
        self.key = key
    }

    /// 오늘 딕셔너리를 고쳐 저장. 읽기-수정-쓰기가 겹쳐 횟수가 사라지지 않게 잠금
    /// - `body`의 두 번째 인자는 이번 기록 시각 (날짜 키와 같은 시각)
    func update(_ body: (inout [String: Int], Date) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        var all = load()
        let today = Self.dayKey(daysAgo: 0, from: now)
        var day = all[today] ?? [:]
        body(&day, now)
        all[today] = day
        // 최근 7일만 남김
        let keep = Set(all.keys.sorted().suffix(7))
        all = all.filter { keep.contains($0.key) }
        UserDefaults.standard.set(all, forKey: key)
    }

    /// daysAgo일 전(0 = 오늘)의 딕셔너리 (없으면 빈 딕셔너리)
    func day(daysAgo: Int) -> [String: Int] {
        load()[Self.dayKey(daysAgo: daysAgo)] ?? [:]
    }

    private func load() -> [String: [String: Int]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Int]] ?? [:]
    }

    /// "2026-10-28" 형식의 날짜 키
    static func dayKey(daysAgo: Int, from now: Date = Date()) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
