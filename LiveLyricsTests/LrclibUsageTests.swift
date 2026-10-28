import Testing
import Foundation
@testable import LiveLyricsExperiment

@MainActor
struct LrclibUsageTests {

    @Test func 분당최고_같은분에두번_최고2() {
        // given
        let empty: [String: Int] = [:]
        // when
        let first = LrclibUsage.updatedPeak(empty, minute: "10:00")
        let second = LrclibUsage.updatedPeak(first, minute: "10:00")
        // then
        #expect(second["peak"] == 2)
    }

    @Test func 분당최고_분이바뀜_현재분은1부터_최고는유지() {
        // given
        var day: [String: Int] = [:]
        for _ in 0..<3 {
            day = LrclibUsage.updatedPeak(day, minute: "10:00")
        }
        // when
        day = LrclibUsage.updatedPeak(day, minute: "10:01")
        // then
        #expect(day["minuteCount"] == 1)
        #expect(day["peak"] == 3)
    }

    @Test func 분당최고_새분이더많음_최고갱신() {
        // given
        var day: [String: Int] = [:]
        for _ in 0..<2 {
            day = LrclibUsage.updatedPeak(day, minute: "10:00")
        }
        // when
        for _ in 0..<3 {
            day = LrclibUsage.updatedPeak(day, minute: "10:01")
        }
        // then
        #expect(day["peak"] == 3)
    }
}
