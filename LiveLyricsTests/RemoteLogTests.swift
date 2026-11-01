import Testing
import Foundation
@testable import LiveLyricsExperiment

@MainActor
struct RemoteLogTests {

    /// 백그라운드 시도 하나를 기록하고 줄을 남길지 돌려준다
    @discardableResult
    private func bg(_ log: inout RemoteConnectLog, _ now: TimeInterval = 1) -> Bool {
        log.attemptStarted(now: now, foreground: false, appState: "background")
    }

    @discardableResult
    private func fg(_ log: inout RemoteConnectLog, _ now: TimeInterval = 1) -> Bool {
        log.attemptStarted(now: now, foreground: true, appState: "active")
    }

    /// 35 상태: 백그라운드 시도(true) → 실패 k → 시도(true) → 실패 k → 시도(false)
    private func state35() -> RemoteConnectLog {
        var log = RemoteConnectLog()
        bg(&log)
        _ = log.failed(key: "k")
        bg(&log)
        _ = log.failed(key: "k")
        bg(&log)
        return log
    }

    // 32
    @Test func 시도기록_첫시도_foreground면_남기고_값을저장한다() {
        // given
        var log = RemoteConnectLog()
        // when
        let r = log.attemptStarted(now: 5, foreground: true, appState: "active")
        // then
        #expect(r == true)
        #expect(log.attemptCount == 1)
        #expect(log.lastAttempt == 5)
        #expect(log.attemptAppState == "active")
    }

    // 33
    @Test func 시도기록_foreground뒤첫백그라운드시도는_남긴다() {
        // given
        var log = RemoteConnectLog()
        fg(&log)
        // when
        let r = bg(&log)
        // then
        #expect(r == true)
    }

    // 34
    @Test func 시도기록_직전결과가바뀌면_백그라운드시도도_남긴다() {
        // given
        var log = RemoteConnectLog()
        bg(&log)
        _ = log.failed(key: "k")
        // when
        let r = bg(&log)
        // then
        #expect(r == true)
    }

    // 35
    @Test func 시도기록_같은결과가반복되면_백그라운드시도는_생략한다() {
        // given
        var log = RemoteConnectLog()
        bg(&log)
        _ = log.failed(key: "k")
        bg(&log)
        _ = log.failed(key: "k")
        // when
        let r = bg(&log)
        // then
        #expect(r == false)
    }

    // 36
    @Test func 시도기록_연결성공뒤_백그라운드시도는_남긴다() {
        // given
        var log = RemoteConnectLog()
        bg(&log)
        _ = log.failed(key: "k")
        bg(&log)
        _ = log.failed(key: "k")
        bg(&log)
        log.connected()
        // when
        let r = bg(&log)
        // then
        #expect(r == true)
    }

    // 37
    @Test func 시도기록_앱화면시도는_항상남긴다() {
        // given
        var log = state35()
        // when
        let r = fg(&log)
        // then
        #expect(r == true)
    }

    // 38
    @Test func 실패기록_앱화면시도뒤_첫실패는_자세히() {
        // given
        var log = RemoteConnectLog()
        fg(&log)
        // when
        let r = log.failed(key: "k")
        // then
        #expect(r == .detail)
    }

    // 39
    @Test func 실패기록_앱화면시도뒤_같은실패는_반복표시() {
        // given
        var log = RemoteConnectLog()
        fg(&log)
        _ = log.failed(key: "k")
        fg(&log)
        // when
        let r = log.failed(key: "k")
        // then
        #expect(r == .repeated)
    }

    // 40
    @Test func 실패기록_줄을생략한시도뒤_같은실패는_조용히() {
        // given
        var log = state35()
        // when
        let r = log.failed(key: "k")
        // then
        #expect(r == .silent)
    }

    // 41
    @Test func 실패기록_다른실패가오면_자세히() {
        // given
        var log = RemoteConnectLog()
        _ = log.failed(key: "k")
        // when
        let r = log.failed(key: "j")
        // then
        #expect(r == .detail)
    }

    // 42
    @Test func 실패기록_연결성공을거치면_같은실패도_자세히() {
        // given
        var log = RemoteConnectLog()
        _ = log.failed(key: "k")
        log.connected()
        // when
        let r = log.failed(key: "k")
        // then
        #expect(r == .detail)
    }

    // 43
    @Test func 연결성공_연결후시도표시가_꺼진다() {
        // given
        var log = RemoteConnectLog()
        log.connectAfterAttempt = true
        // when
        log.connected()
        // then
        #expect(log.connectAfterAttempt == false)
    }

    // 44
    @Test func 승인필요_첫호출은_안내를남기고_시각을저장한다() {
        // given
        var log = RemoteConnectLog()
        // when
        let r = log.needAuthorize(now: 7)
        // then
        #expect(r == true)
        #expect(log.lastAttempt == 7)
    }

    // 45
    @Test func 승인필요_둘째호출은_안내를생략하고_시각을갱신한다() {
        // given
        var log = RemoteConnectLog()
        _ = log.needAuthorize(now: 7)
        // when
        let r = log.needAuthorize(now: 9)
        // then
        #expect(r == false)
        #expect(log.lastAttempt == 9)
    }

    // 46
    @Test func 승인필요_승인뒤에는_다시_안내한다() {
        // given
        var log = RemoteConnectLog()
        _ = log.needAuthorize(now: 7)
        _ = log.needAuthorize(now: 9)
        log.authorized()
        // when
        let r = log.needAuthorize(now: 10)
        // then
        #expect(r == true)
    }

    // 47
    @Test func 승인필요_연결시도를거치면_다시_안내한다() {
        // given
        var log = RemoteConnectLog()
        _ = log.needAuthorize(now: 7)
        _ = log.needAuthorize(now: 9)
        bg(&log, 10)
        // when
        let r = log.needAuthorize(now: 11)
        // then
        #expect(r == true)
    }

    // 48
    @Test func 세션문구_세션이없으면_세션없음() {
        // given // when // then
        #expect(RemoteLogText.session(hasSession: false, remaining: 100) == "세션 없음")
    }

    // 49
    @Test func 세션문구_남은시간을모르면_세션없음() {
        // given // when // then
        #expect(RemoteLogText.session(hasSession: true, remaining: nil) == "세션 없음")
    }

    // 50
    @Test func 세션문구_남은시간0이면_만료됨() {
        // given // when // then
        #expect(RemoteLogText.session(hasSession: true, remaining: 0) == "세션 있음, 만료됨(연결 전 갱신)")
    }

    // 51
    @Test func 세션문구_60초이하면_곧만료() {
        // given // when // then
        #expect(RemoteLogText.session(hasSession: true, remaining: 60) == "세션 있음, 남은 유효 곧 만료(연결 전 갱신)")
    }

    // 52
    @Test func 세션문구_61초이상이면_분단위() {
        // given // when // then
        #expect(RemoteLogText.session(hasSession: true, remaining: 61) == "세션 있음, 남은 유효 1분")
        #expect(RemoteLogText.session(hasSession: true, remaining: 3600) == "세션 있음, 남은 유효 60분")
    }

    // 53
    @Test func 재생상태문구_없음_재생중_일시정지() {
        // given // when // then
        #expect(RemoteLogText.playback(isPlaying: nil) == "없음")
        #expect(RemoteLogText.playback(isPlaying: true) == "재생 중")
        #expect(RemoteLogText.playback(isPlaying: false) == "일시정지")
    }

    // 54
    @Test func 끊김문구_사용자가끊으면_끊음() {
        // given // when // then
        #expect(RemoteLogText.disconnected(byUser: true, error: "로그아웃") == "⚡ SDK 연결 끊음 (로그아웃)")
        #expect(RemoteLogText.disconnected(byUser: true, error: nil) == "⚡ SDK 연결 끊음 (정지)")
    }

    // 55
    @Test func 끊김문구_저절로끊기면_폴링복귀() {
        // given // when // then
        #expect(RemoteLogText.disconnected(byUser: false, error: "x") == "⚡ SDK 연결 끊김 — 3초 폴링 복귀 (x)")
        #expect(RemoteLogText.disconnected(byUser: false, error: nil) == "⚡ SDK 연결 끊김 — 3초 폴링 복귀 (이유 없음)")
    }

    // 56
    @Test func 승인필요문구_세션이있으면_카드탭안내() {
        // given // when // then
        #expect(RemoteLogText.needAuthorize(hasSession: true) == "⚡ SDK 세션 만료·갱신 불가 — 잠금화면 카드를 탭하면 Spotify를 잠깐 거쳐 자동으로 다시 승인해요 (앱의 [Spotify 다시 연결]도 가능)")
    }

    // 57
    @Test func 승인필요문구_세션이없으면_로그인안내() {
        // given // when // then
        #expect(RemoteLogText.needAuthorize(hasSession: false) == "⚡ Spotify 로그인 필요 — 앱에서 [Spotify로 로그인]을 눌러 주세요")
    }

    // 58
    @Test func 시간문구_초수별_분초또는초로반올림() {
        // given // when // then
        #expect(RemoteLogText.duration(295) == "4분 55초")
        #expect(RemoteLogText.duration(42) == "42초")
        #expect(RemoteLogText.duration(59.6) == "1분 0초")
    }
}
