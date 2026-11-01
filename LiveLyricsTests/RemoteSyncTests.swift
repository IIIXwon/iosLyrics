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

    // 11
    @Test func 승인판단_세션이없으면_승인이필요하다() {
        // given // when
        let result = RemoteAuthPlan.action(hasSession: false, expiresIn: nil, canRenew: false)

        // then
        #expect(result == .needAuthorize)
    }

    // 12
    @Test func 승인판단_만료까지여유가있으면_바로연결한다() {
        // given // when
        let result = RemoteAuthPlan.action(hasSession: true, expiresIn: 3000, canRenew: true)

        // then
        #expect(result == .connect)
    }

    // 13
    @Test func 승인판단_만료임박이고갱신가능하면_갱신한다() {
        // given // when
        let result = RemoteAuthPlan.action(hasSession: true, expiresIn: 30, canRenew: true)

        // then
        #expect(result == .renew)
    }

    // 14
    @Test func 승인판단_이미만료됐고갱신불가면_승인이필요하다() {
        // given // when
        let result = RemoteAuthPlan.action(hasSession: true, expiresIn: -10, canRenew: false)

        // then
        #expect(result == .needAuthorize)
    }

    // 15
    @Test func 승인판단_만료임박이고갱신불가면_승인이필요하다() {
        // given // when
        let result = RemoteAuthPlan.action(hasSession: true, expiresIn: 30, canRenew: false)

        // then
        #expect(result == .needAuthorize)
    }

    // 16
    @Test func 승인버튼_로그인돼있고승인이필요할때만_보인다() {
        // given // when // then
        #expect(RemoteAuthPlan.showsAuthorizeButton(loggedIn: true, action: .needAuthorize) == true)
        #expect(RemoteAuthPlan.showsAuthorizeButton(loggedIn: true, action: .connect) == false)
        #expect(RemoteAuthPlan.showsAuthorizeButton(loggedIn: true, action: .renew) == false)
        #expect(RemoteAuthPlan.showsAuthorizeButton(loggedIn: false, action: .needAuthorize) == false)
    }

    // 17
    @Test func 상수_갱신여유시간이_60초다() {
        // given // when // then
        #expect(RemoteAuthPlan.renewMargin == 60)
    }

    private func 카드탭(isRunning: Bool = true, loggedIn: Bool = true,
                      remoteConnected: Bool = false,
                      authAction: RemoteAuthPlan.Action = .connect) -> CardTapPlan.Action {
        CardTapPlan.action(isRunning: isRunning, loggedIn: loggedIn,
                           remoteConnected: remoteConnected,
                           authAction: authAction)
    }

    // 029-1
    @Test func 카드탭판단_끊김이고세션이유효하면_재연결한다() {
        // given // when
        let result = 카드탭()

        // then
        #expect(result == .reconnect)
    }

    // 029-2
    @Test func 카드탭판단_세션곧만료지만갱신가능하면_재연결한다() {
        // given // when
        let result = 카드탭(authAction: .renew)

        // then
        #expect(result == .reconnect)
    }

    // 029-3
    @Test func 카드탭판단_승인세션이없으면_스포티파이만연다() {
        // given // when
        let result = 카드탭(authAction: .needAuthorize)

        // then
        #expect(result == .openSpotify)
    }

    // 029-4
    @Test func 카드탭판단_SDK가연결돼있으면_스포티파이만연다() {
        // given // when
        let result = 카드탭(remoteConnected: true)

        // then
        #expect(result == .openSpotify)
    }

    // 029-6
    @Test func 카드탭판단_추적중이아니면_스포티파이만연다() {
        // given // when
        let result = 카드탭(isRunning: false)

        // then
        #expect(result == .openSpotify)
    }

    // 029-7
    @Test func 카드탭판단_로그인안돼있으면_스포티파이만연다() {
        // given // when
        let result = 카드탭(loggedIn: false)

        // then
        #expect(result == .openSpotify)
    }

    // 030-1
    @Test func 갱신가능판단_토큰있고실패0번이면_true() {
        // given // when
        let result = RemoteAuthPlan.canRenew(hasRefreshToken: true, renewFailures: 0)

        // then
        #expect(result == true)
    }

    // 030-2
    @Test func 갱신가능판단_토큰있고실패1번이면_true() {
        // given // when
        let result = RemoteAuthPlan.canRenew(hasRefreshToken: true, renewFailures: 1)

        // then
        #expect(result == true)
    }

    // 030-3
    @Test func 갱신가능판단_토큰있어도실패2번이면_false() {
        // given // when
        let result = RemoteAuthPlan.canRenew(hasRefreshToken: true, renewFailures: 2)

        // then
        #expect(result == false)
    }

    // 030-4
    @Test func 갱신가능판단_토큰없으면_false() {
        // given // when
        let result = RemoteAuthPlan.canRenew(hasRefreshToken: false, renewFailures: 0)

        // then
        #expect(result == false)
    }

    private func 재승인카드탭(isRunning: Bool = true, loggedIn: Bool = true,
                         remoteConnected: Bool = false,
                         authAction: RemoteAuthPlan.Action = .needAuthorize,
                         hasSession: Bool = true) -> CardTapPlan.Action {
        CardTapPlan.action(isRunning: isRunning, loggedIn: loggedIn,
                           remoteConnected: remoteConnected,
                           authAction: authAction, hasSession: hasSession)
    }

    // 030-5
    @Test func 카드탭판단_세션있고만료갱신불가면_재연결한다() {
        // given // when
        let result = 재승인카드탭()

        // then
        #expect(result == .reconnect)
    }

    // 030-6
    @Test func 카드탭판단_세션이없으면_승인필요여도_스포티파이만연다() {
        // given // when
        let result = 재승인카드탭(hasSession: false)

        // then
        #expect(result == .openSpotify)
    }

    // 030-7
    @Test func 카드탭판단_세션있어도SDK가연결돼있으면_스포티파이만연다() {
        // given // when
        let result = 재승인카드탭(remoteConnected: true)

        // then
        #expect(result == .openSpotify)
    }

    // 030-8
    @Test func 카드탭판단_세션있어도추적중이아니면_스포티파이만연다() {
        // given // when
        let result = 재승인카드탭(isRunning: false)

        // then
        #expect(result == .openSpotify)
    }

    // 030-9
    @Test func 카드탭판단_세션있어도로그인안돼있으면_스포티파이만연다() {
        // given // when
        let result = 재승인카드탭(loggedIn: false)

        // then
        #expect(result == .openSpotify)
    }
}
