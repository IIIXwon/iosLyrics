import Testing
@testable import LiveLyricsExperiment

struct LogLineTests {
    // 035-1
    @Test func 수준판단_엑스표시로시작하면_error() {
        // given
        let message = "❌ 실패"
        // when
        let level = LogLine.level(of: message)
        // then
        #expect(level == .error)
    }

    // 035-2
    @Test func 수준판단_경고로시작하면_warning() {
        // given
        let message = "⚠️ 주의"
        // when
        let level = LogLine.level(of: message)
        // then
        #expect(level == .warning)
    }

    // 035-3
    @Test func 수준판단_안내로시작하면_notice() {
        // given
        let message = "ℹ️ 안내"
        // when
        let level = LogLine.level(of: message)
        // then
        #expect(level == .notice)
    }

    // 035-4
    @Test func 수준판단_중간에엑스표시가있으면_notice() {
        // given
        let message = "🧭 준비 상태: 위치 ❌ → ✅"
        // when
        let level = LogLine.level(of: message)
        // then
        #expect(level == .notice)
    }

    // 035-5
    @Test func 분류판단_번개일시정지로시작하면_sdk() {
        // given
        let message = "⚡⏸ 일시정지 (0:42)"
        // when
        let category = LogLine.category(of: message)
        // then
        #expect(category == .sdk)
    }

    // 035-6
    @Test func 분류판단_번개로시작하면_sdk() {
        // given
        let message = "⚡ SDK 연결됨"
        // when
        let category = LogLine.category(of: message)
        // then
        #expect(category == .sdk)
    }

    // 035-7
    @Test func 분류판단_위치핀으로시작하면_location() {
        // given
        let message = "📍 위치 추적 시작"
        // when
        let category = LogLine.category(of: message)
        // then
        #expect(category == .location)
    }

    // 035-8
    @Test func 분류판단_카드로시작하면_card() {
        // given
        let message = "🪪 카드 상태: active"
        // when
        let category = LogLine.category(of: message)
        // then
        #expect(category == .card)
    }

    // 035-9
    @Test func 분류판단_그밖은_app() {
        // given
        let message = "🎵 곡: 가수 - 제목"
        // when
        let category = LogLine.category(of: message)
        // then
        #expect(category == .app)
    }

    // 035-10
    @Test func 시간표시_42초는_0분42초() {
        // given // when
        let text = LogLine.time(42)
        // then
        #expect(text == "0:42")
    }

    // 035-11
    @Test func 시간표시_191초는_3분11초() {
        // given // when
        let text = LogLine.time(191)
        // then
        #expect(text == "3:11")
    }

    // 035-12
    @Test func 시간표시_음수는_0() {
        // given // when
        let text = LogLine.time(-3)
        // then
        #expect(text == "0:00")
    }

    // 035-13
    @Test func 곡줄_접두어가있으면_앞에붙인다() {
        // given // when
        let line = LogLine.song(prefix: "⚡", artist: "가수", title: "제목", position: 42, duration: 191)
        // then
        #expect(line == "⚡🎵 곡: 가수 - 제목 (0:42 / 3:11)")
    }

    // 035-14
    @Test func 곡줄_접두어가비면_곡표시로시작한다() {
        // given // when
        let line = LogLine.song(prefix: "", artist: "가수", title: "제목", position: 42, duration: 191)
        // then
        #expect(line == "🎵 곡: 가수 - 제목 (0:42 / 3:11)")
    }

    // 035-15
    @Test func 위치없음문구_권한을넣어_정상일수있다고안내한다() {
        // given // when
        let note = LogLine.noFixNote(authorization: "앱 사용 중")
        // then
        #expect(note == "저전력 설정에서는 정상일 수 있어요 (권한 앱 사용 중)")
    }

    // 035-16
    @Test func 반복필터_처음보는키는_true() {
        // given
        var filter = RepeatFilter()
        // when
        let result = filter.shouldLog("a")
        // then
        #expect(result == true)
    }

    // 035-17
    @Test func 반복필터_같은키가연속이면_false() {
        // given
        var filter = RepeatFilter()
        _ = filter.shouldLog("a")
        // when
        let result = filter.shouldLog("a")
        // then
        #expect(result == false)
    }

    // 035-18
    @Test func 반복필터_다른키를거친뒤같은키는_true() {
        // given
        var filter = RepeatFilter()
        _ = filter.shouldLog("a")
        _ = filter.shouldLog("b")
        // when
        let result = filter.shouldLog("a")
        // then
        #expect(result == true)
    }

    // 035-19
    @Test func 반복필터_리셋뒤같은키는_true() {
        // given
        var filter = RepeatFilter()
        _ = filter.shouldLog("a")
        filter.reset()
        // when
        let result = filter.shouldLog("a")
        // then
        #expect(result == true)
    }

    // 035-20
    @Test func 수준_한도차단_error다() {
        // given
        let message = "⛔️ 한도 차단"
        // when
        let result = LogLine.level(of: message)
        // then
        #expect(result == .error)
    }

    // 035-21
    @Test func 수준_SDK연결실패반복_warning이다() {
        // given
        let message = "⚡ SDK 연결 실패 #3: 같은 오류 반복"
        // when
        let result = LogLine.level(of: message)
        // then
        #expect(result == .warning)
    }

    // 035-22
    @Test func 수준_SDK연결끊김_notice다() {
        // given
        let message = "⚡ SDK 연결 끊김 — 3초 폴링 복귀"
        // when
        let result = LogLine.level(of: message)
        // then
        #expect(result == .notice)
    }

    // 035-23
    @Test func 수준_위치추적재시작실패_error다() {
        // given
        let message = "❌ 위치 추적 재시작 실패"
        // when
        let result = LogLine.level(of: message)
        // then
        #expect(result == .error)
    }
}
