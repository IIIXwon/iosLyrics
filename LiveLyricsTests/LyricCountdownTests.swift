import Testing
import Foundation
@testable import LiveLyricsExperiment

@MainActor
struct LyricCountdownTests {

    private func lines(_ items: [(TimeInterval, String)]) -> [LyricLine] {
        items.map { LyricLine(time: $0.0, text: $0.1) }
    }

    private var L: [LyricLine] {
        lines([(10, "A"), (12, ""), (22, "B"), (24, "C")])
    }

    // 1
    @Test func 카운트다운값_전주인데_3초보다_멀면_0() {
        // given
        let l = L
        // when
        let v = LyricCountdown.value(l, at: 6.5)
        // then
        #expect(v == 0)
    }

    // 2
    @Test func 카운트다운값_전주끝3초안이면_올림한숫자() {
        // given
        let l = L
        // when
        let a = LyricCountdown.value(l, at: 7.0)
        let b = LyricCountdown.value(l, at: 7.5)
        let c = LyricCountdown.value(l, at: 8.5)
        let d = LyricCountdown.value(l, at: 9.5)
        // then
        #expect(a == 3)
        #expect(b == 3)
        #expect(c == 2)
        #expect(d == 1)
    }

    // 3
    @Test func 카운트다운값_첫줄시작시각이면_0() {
        // given
        let l = L
        // when
        let v = LyricCountdown.value(l, at: 10.0)
        // then
        #expect(v == 0)
    }

    // 4
    @Test func 카운트다운값_전주가5초미만이면_0() {
        // given
        let l = lines([(4, "A")])
        // when
        let v = LyricCountdown.value(l, at: 2.0)
        // then
        #expect(v == 0)
    }

    // 5
    @Test func 카운트다운값_간주10초의끝3초안이면_숫자() {
        // given
        let l = L
        // when
        let a = LyricCountdown.value(l, at: 19.5)
        let b = LyricCountdown.value(l, at: 20.5)
        let c = LyricCountdown.value(l, at: 21.5)
        // then
        #expect(a == 3)
        #expect(b == 2)
        #expect(c == 1)
    }

    // 6
    @Test func 카운트다운값_간주가8초미만이면_0() {
        // given
        let l = lines([(10, "A"), (12, ""), (18, "B")])
        // when
        let v = LyricCountdown.value(l, at: 16.0)
        // then
        #expect(v == 0)
    }

    // 7
    @Test func 카운트다운값_일반줄이면_0() {
        // given
        let l = L
        // when
        let v = LyricCountdown.value(l, at: 11.5)
        // then
        #expect(v == 0)
    }

    // 8
    @Test func 카운트다운값_마지막줄이빈줄이면_0() {
        // given
        let l = lines([(10, "A"), (20, "")])
        // when
        let v = LyricCountdown.value(l, at: 30)
        // then
        #expect(v == 0)
    }

    // 9
    @Test func 카운트다운값_빈배열이면_0() {
        // given
        let l: [LyricLine] = []
        // when
        let v = LyricCountdown.value(l, at: 1)
        // then
        #expect(v == 0)
    }

    // 10
    @Test func 다음변화_전주에서_첫줄3초전() {
        // given
        let l = L
        // when
        let n = LyricCountdown.nextChange(l, at: 0)
        // then
        #expect(n == 7.0)
    }

    // 11
    @Test func 다음변화_숫자표시중이면_다음정수초전() {
        // given
        let l = L
        // when
        let a = LyricCountdown.nextChange(l, at: 7.5)
        let b = LyricCountdown.nextChange(l, at: 8.2)
        // then
        #expect(a == 8.0)
        #expect(b == 9.0)
    }

    // 12
    @Test func 다음변화_마지막숫자1이면_nil() {
        // given
        let l = L
        // when
        let n = LyricCountdown.nextChange(l, at: 9.5)
        // then
        #expect(n == nil)
    }

    // 13
    @Test func 다음변화_간주중이면_다음줄3초전() {
        // given
        let l = L
        // when
        let n = LyricCountdown.nextChange(l, at: 14)
        // then
        #expect(n == 19.0)
    }

    // 14
    @Test func 다음변화_카운트다운구간이아니면_nil() {
        // given
        let normal = L
        let shortIntro = lines([(4, "A")])
        let shortInterlude = lines([(10, "A"), (12, ""), (18, "B")])
        // when
        let a = LyricCountdown.nextChange(normal, at: 11)
        let b = LyricCountdown.nextChange(shortIntro, at: 2.0)
        let c = LyricCountdown.nextChange(shortInterlude, at: 14)
        // then
        #expect(a == nil)
        #expect(b == nil)
        #expect(c == nil)
    }

    // 15
    @Test func 상수_지시서값과같다() {
        // given // when // then
        #expect(LyricCountdown.introMinimum == 5)
        #expect(LyricCountdown.interludeMinimum == 8)
        #expect(LyricCountdown.seconds == 3)
    }
}
