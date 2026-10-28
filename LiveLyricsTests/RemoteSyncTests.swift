import Testing
@testable import LiveLyricsExperiment

@MainActor
struct RemoteSyncTests {

    private func 스냅샷(uri: String = "spotify:track:abc", isPaused: Bool = false, isAd: Bool = false) -> RemoteSnapshot? {
        RemoteSnapshot.make(uri: uri, name: "T", artist: "A", album: "L",
                            durationMs: 200_000, positionMs: 12_500,
                            isPaused: isPaused, isAd: isAd)
    }

    // 1
    @Test func 스냅샷만들기_재생중트랙이면_값을초로바꾼다() throws {
        // given // when
        let snap = try #require(스냅샷())

        // then
        #expect(snap.trackID == "abc")
        #expect(snap.title == "T")
        #expect(snap.artist == "A")
        #expect(snap.album == "L")
        #expect(snap.duration == 200)
        #expect(snap.position == 12.5)
        #expect(snap.isPlaying == true)
    }

    // 2
    @Test func 스냅샷만들기_일시정지면_재생중이아니다() throws {
        // given // when
        let snap = try #require(스냅샷(isPaused: true))

        // then
        #expect(snap.isPlaying == false)
    }

    // 3
    @Test func 스냅샷만들기_에피소드URI면_nil() {
        // given // when
        let snap = 스냅샷(uri: "spotify:episode:x")

        // then
        #expect(snap == nil)
    }

    @Test func 스냅샷만들기_빈URI면_nil() {
        // given // when
        let snap = 스냅샷(uri: "")

        // then
        #expect(snap == nil)
    }

    @Test func 스냅샷만들기_트랙id가비었으면_nil() {
        // given // when
        let snap = 스냅샷(uri: "spotify:track:")

        // then
        #expect(snap == nil)
    }

    @Test func 스냅샷만들기_광고면_nil() {
        // given // when
        let snap = 스냅샷(isAd: true)

        // then
        #expect(snap == nil)
    }

    // 4
    @Test func 조회간격_미연결이면_3_15_10초다() {
        // given // when
        let playing = PollTiming.interval(connected: false, state: .playing)
        let paused = PollTiming.interval(connected: false, state: .paused)
        let none = PollTiming.interval(connected: false, state: .none)

        // then
        #expect(playing == 3)
        #expect(paused == 15)
        #expect(none == 10)
    }

    // 5
    @Test func 조회간격_연결이면_15_30_10초다() {
        // given // when
        let playing = PollTiming.interval(connected: true, state: .playing)
        let paused = PollTiming.interval(connected: true, state: .paused)
        let none = PollTiming.interval(connected: true, state: .none)

        // then
        #expect(playing == 15)
        #expect(paused == 30)
        #expect(none == 10)
    }

    // 6
    @Test func 재연결판단_시도한적없으면_true() {
        // given // when
        let result = RemoteRetry.shouldTry(now: 100, lastAttempt: nil, foreground: false)

        // then
        #expect(result == true)
    }

    // 7
    @Test func 재연결판단_백그라운드에서50초전시도면_false() {
        // given // when
        let result = RemoteRetry.shouldTry(now: 100, lastAttempt: 50, foreground: false)

        // then
        #expect(result == false)
    }

    // 8
    @Test func 재연결판단_백그라운드에서60초전시도면_true() {
        // given // when
        let result = RemoteRetry.shouldTry(now: 100, lastAttempt: 40, foreground: false)

        // then
        #expect(result == true)
    }

    // 9
    @Test func 재연결판단_화면복귀면_간격을무시한다() {
        // given // when
        let result = RemoteRetry.shouldTry(now: 100, lastAttempt: 99, foreground: true)

        // then
        #expect(result == true)
    }

    // 10
    @Test func 상수_재연결간격과연결중조회간격이_지시서와같다() {
        // given // when // then
        #expect(RemoteRetry.backgroundGap == 60)
        #expect(PollTiming.connectedPlaying == 15)
        #expect(PollTiming.connectedPaused == 30)
    }
}
