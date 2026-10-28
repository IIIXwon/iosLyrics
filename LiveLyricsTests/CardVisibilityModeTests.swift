import Testing
import Foundation
@testable import LiveLyricsExperiment

@MainActor
struct CardVisibilityModeTests {

    @Test func 카드표시모드_기본이면_우선순위0이고_알림없음() {
        // given
        let mode = CardVisibilityMode.normal
        // when
        let score = mode.relevanceScore
        let alerts = mode.alertsOnFirstLyrics
        // then
        #expect(score == 0)
        #expect(alerts == false)
    }

    @Test func 카드표시모드_우선순위면_우선순위100이고_알림없음() {
        // given
        let mode = CardVisibilityMode.priority
        // when
        let score = mode.relevanceScore
        let alerts = mode.alertsOnFirstLyrics
        // then
        #expect(score == 100)
        #expect(alerts == false)
    }

    @Test func 카드표시모드_시작알림이면_우선순위0이고_알림있음() {
        // given
        let mode = CardVisibilityMode.alert
        // when
        let score = mode.relevanceScore
        let alerts = mode.alertsOnFirstLyrics
        // then
        #expect(score == 0)
        #expect(alerts == true)
    }

    @Test func 카드표시모드_둘다면_우선순위100이고_알림있음() {
        // given
        let mode = CardVisibilityMode.both
        // when
        let score = mode.relevanceScore
        let alerts = mode.alertsOnFirstLyrics
        // then
        #expect(score == 100)
        #expect(alerts == true)
    }

    @Test func 저장값변환_없거나모르는값이면_기본으로() {
        // given
        let missing: String? = nil
        let unknown = "엉뚱한값"
        // when
        let fromNil = CardVisibilityMode(stored: missing)
        let fromUnknown = CardVisibilityMode(stored: unknown)
        // then
        #expect(fromNil == .normal)
        #expect(fromUnknown == .normal)
    }

    @Test func 저장값변환_priority면_우선순위모드() {
        // given
        let stored = "priority"
        // when
        let mode = CardVisibilityMode(stored: stored)
        // then
        #expect(mode == .priority)
    }

    @Test func 표시이름_모든모드가_비어있지않고_서로다르다() {
        // given
        let modes = CardVisibilityMode.allCases
        // when
        let labels = modes.map { $0.label }
        // then
        #expect(labels.count == 4)
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == 4)
    }
}
