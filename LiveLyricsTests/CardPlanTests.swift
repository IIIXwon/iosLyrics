import Testing
import Foundation
@testable import LiveLyricsExperiment

@MainActor
struct CardPlanTests {

    private func snap(_ p: String = "a", _ c: String = "b", _ n: String = "c",
                      playing: Bool = true, countdown: Int = 0) -> CardSnapshot {
        CardSnapshot(previous: p, current: c, next: n, isPlaying: playing, countdown: countdown)
    }

    private let lines = [LyricLine(time: 10, text: "A"), LyricLine(time: 12, text: "B"), LyricLine(time: 14, text: "C")]

    // 1
    @Test func 갱신이유_이전카드가없으면_처음() {
        // given // when
        let r = CardPlan.reason(old: nil, new: snap(), trackChanged: false)
        // then
        #expect(r == .first)
    }

    // 2
    @Test func 갱신이유_곡이바뀌면_글자가달라도_곡변경이우선() {
        // given // when
        let r = CardPlan.reason(old: snap(), new: snap("x", "y", "z"), trackChanged: true)
        // then
        #expect(r == .trackChanged)
    }

    // 3
    @Test func 갱신이유_현재줄과재생이같이바뀌면_글자변경이우선() {
        // given // when
        let r = CardPlan.reason(old: snap(), new: snap("a", "other", "c", playing: false), trackChanged: false)
        // then
        #expect(r == .textChanged)
    }

    // 4
    @Test func 갱신이유_일시정지에서재생으로바뀌면_재생() {
        // given // when
        let r = CardPlan.reason(old: snap(playing: false), new: snap(playing: true), trackChanged: false)
        // then
        #expect(r == .resumed)
    }

    // 5
    @Test func 갱신이유_재생에서일시정지로바뀌면_일시정지() {
        // given // when
        let r = CardPlan.reason(old: snap(playing: true), new: snap(playing: false), trackChanged: false)
        // then
        #expect(r == .paused)
    }

    // 6
    @Test func 갱신이유_카운트다운만다르면_가사줄변경() {
        // given // when
        let r = CardPlan.reason(old: snap(), new: snap(countdown: 3), trackChanged: false)
        // then
        #expect(r == .lineChanged)
    }

    // 7
    @Test func 갱신이유_똑같으면_nil() {
        // given // when
        let r = CardPlan.reason(old: snap(), new: snap(), trackChanged: false)
        // then
        #expect(r == nil)
    }

    // 8
    @Test func 줄변경여부_다음줄만다르면_true() {
        // given // when // then
        #expect(CardPlan.linesChanged(old: snap(), new: snap("a", "b", "z")))
    }

    // 9
    @Test func 줄변경여부_카운트다운만다르면_true() {
        // given // when // then
        #expect(CardPlan.linesChanged(old: snap(), new: snap(countdown: 2)))
    }

    // 10
    @Test func 줄변경여부_재생상태만다르면_false() {
        // given // when // then
        #expect(!CardPlan.linesChanged(old: snap(), new: snap(playing: false)))
    }

    // 11
    @Test func 갱신이유문구_처음_곡변경_표시내용변경() {
        // given // when // then
        #expect(CardUpdateReason.first.text == "처음")
        #expect(CardUpdateReason.trackChanged.text == "곡 변경")
        #expect(CardUpdateReason.textChanged.text == "표시 내용 변경")
    }

    // 12
    @Test func 갱신이유문구_재생_일시정지_가사줄변경() {
        // given // when // then
        #expect(CardUpdateReason.resumed.text == "재생")
        #expect(CardUpdateReason.paused.text == "일시정지")
        #expect(CardUpdateReason.lineChanged.text == "가사 줄 변경")
    }

    // 13
    @Test func 갱신이유문구_한도차단과유휴안내() {
        // given // when // then
        #expect(CardUpdateReason.quotaNotice.text == "한도 차단 안내")
        #expect(CardUpdateReason.idleNotice.text == "위치 추적 끄기 직전 안내")
    }

    // 14
    @Test func 갱신이유문구_싱크가사와일반가사() {
        // given // when // then
        #expect(CardUpdateReason.lyrics(.synced).text == "가사 도착")
        #expect(CardUpdateReason.lyrics(.plain).text == "싱크 가사 없음 (일반 가사만)")
    }

    // 15
    @Test func 갱신이유문구_연주곡과가사없음() {
        // given // when // then
        #expect(CardUpdateReason.lyrics(.instrumental).text == "연주곡")
        #expect(CardUpdateReason.lyrics(.none).text == "가사 없음")
    }

    // 16
    @Test func 로그줄_곡변경이면_번호와이유를적는다() {
        // given // when
        let s = CardPlan.logLine(count: 3, reason: .trackChanged, syncOffset: nil)
        // then
        #expect(s == "🪪 카드 갱신 #3 — 곡 변경")
    }

    // 17
    @Test func 로그줄_가사줄변경이고_보정없으면_nil() {
        // given // when
        let s = CardPlan.logLine(count: 3, reason: .lineChanged, syncOffset: nil)
        // then
        #expect(s == nil)
    }

    // 18
    @Test func 로그줄_싱크보정양수면_보정값을덧붙인다() {
        // given // when
        let s = CardPlan.logLine(count: 3, reason: .textChanged, syncOffset: 0.25)
        // then
        #expect(s == "🪪 카드 갱신 #3 — 표시 내용 변경 (싱크 보정 +0.25초)")
    }

    // 19
    @Test func 로그줄_가사줄변경이어도_보정이면_기록한다() {
        // given // when
        let s = CardPlan.logLine(count: 3, reason: .lineChanged, syncOffset: -0.5)
        // then
        #expect(s == "🪪 카드 갱신 #3 — 가사 줄 변경 (싱크 보정 -0.50초)")
    }

    // 20
    @Test func 위치계산_범위안이면_보정을더한다() {
        // given // when // then
        #expect(CardPlan.position(10, offset: 0.25, duration: 100) == 10.25)
    }

    // 21
    @Test func 위치계산_음수가되면_0() {
        // given // when // then
        #expect(CardPlan.position(0.1, offset: -1, duration: 100) == 0)
    }

    // 22
    @Test func 위치계산_곡길이를넘으면_곡길이() {
        // given // when // then
        #expect(CardPlan.position(99.9, offset: 1, duration: 100) == 100)
    }

    // 23
    @Test func 카운트다운_일반가사면_전주끝이어도_0() {
        // given // when
        let v = CardPlan.countdown(kind: .plain, isPlaying: true, lines: lines, position: 8)
        // then
        #expect(v == 0)
    }

    // 24
    @Test func 카운트다운_일시정지면_싱크가사여도_0() {
        // given // when
        let v = CardPlan.countdown(kind: .synced, isPlaying: false, lines: lines, position: 8)
        // then
        #expect(v == 0)
    }

    // 25
    @Test func 카운트다운_싱크가사재생중이면_계산값() {
        // given
        let expected = LyricCountdown.value(lines, at: 8)
        // when
        let v = CardPlan.countdown(kind: .synced, isPlaying: true, lines: lines, position: 8)
        // then
        #expect(v == expected)
        #expect(v != 0)
    }

    // 26
    @Test func 카드문구_싱크가사면_현재위치의세줄() {
        // given
        let ctx = LRCParser.context(lines, at: 12)
        // when
        let t = CardText.make(kind: .synced, lines: lines, position: 12, title: "T", artist: "A", album: "L")
        // then
        #expect(t.previous == ctx.previous)
        #expect(t.current == ctx.current)
        #expect(t.next == ctx.next)
        #expect(t.trackInfo == "T · A")
    }

    // 27
    @Test func 카드문구_일반가사면_싱크없음안내() {
        // given // when
        let t = CardText.make(kind: .plain, lines: [], position: 0, title: "T", artist: "A", album: "L")
        // then
        #expect(t == CardText(previous: "", current: "싱크 가사가 없어요", next: "일반 가사만 있어서 저장해 뒀어요", trackInfo: "T · A"))
    }

    // 28
    @Test func 카드문구_연주곡이면_연주곡표시() {
        // given // when
        let t = CardText.make(kind: .instrumental, lines: [], position: 0, title: "T", artist: "A", album: "L")
        // then
        #expect(t == CardText(previous: "", current: "🎼 연주곡", next: "", trackInfo: "T · A"))
    }

    // 29
    @Test func 카드문구_가사없음이면_아티스트제목앨범() {
        // given // when
        let t = CardText.make(kind: .none, lines: [], position: 0, title: "T", artist: "A", album: "L")
        // then
        #expect(t == CardText(previous: "A", current: "T", next: "L", trackInfo: ""))
    }

    // 30
    @Test func 카드문구_곡이없으면_재생안내() {
        // given // when
        let t = CardText.noTrack(status: "곡 없음")
        // then
        #expect(t == CardText(previous: "", current: "곡 없음", next: "Spotify에서 음악을 재생하세요", trackInfo: ""))
    }

    // 31
    @Test func 검색기록저장값_종류별_이름() {
        // given // when // then
        #expect(SearchRecord.resultName(for: .plain) == "plain")
        #expect(SearchRecord.resultName(for: .none) == "none")
        #expect(SearchRecord.resultName(for: .instrumental) == "instrumental")
    }
}
