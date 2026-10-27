import Testing
import Foundation
@testable import LiveLyricsExperiment

@MainActor
struct LyricsRetryPolicyTests {

    @Test func 일시오류판단_http503이면_true() {
        // given
        let error = LyricsError.http(503)
        // when
        let result = LyricsRetryPolicy.isTransient(error)
        // then
        #expect(result == true)
    }

    @Test func 일시오류판단_http500이면_true() {
        // given
        let error = LyricsError.http(500)
        // when
        let result = LyricsRetryPolicy.isTransient(error)
        // then
        #expect(result == true)
    }

    @Test func 일시오류판단_http429이면_true() {
        // given
        let error = LyricsError.http(429)
        // when
        let result = LyricsRetryPolicy.isTransient(error)
        // then
        #expect(result == true)
    }

    @Test func 일시오류판단_http400이면_false() {
        // given
        let error = LyricsError.http(400)
        // when
        let result = LyricsRetryPolicy.isTransient(error)
        // then
        #expect(result == false)
    }

    @Test func 일시오류판단_시간초과이면_true() {
        // given
        let error = URLError(.timedOut)
        // when
        let result = LyricsRetryPolicy.isTransient(error)
        // then
        #expect(result == true)
    }

    @Test func 일시오류판단_인터넷끊김이면_true() {
        // given
        let error = URLError(.notConnectedToInternet)
        // when
        let result = LyricsRetryPolicy.isTransient(error)
        // then
        #expect(result == true)
    }

    @Test func 일시오류판단_URLError취소이면_false() {
        // given
        let error = URLError(.cancelled)
        // when
        let result = LyricsRetryPolicy.isTransient(error)
        // then
        #expect(result == false)
    }

    @Test func 일시오류판단_CancellationError이면_false() {
        // given
        let error = CancellationError()
        // when
        let result = LyricsRetryPolicy.isTransient(error)
        // then
        #expect(result == false)
    }

    @Test func 대기시간_1에서5번째실패면_2_5_15_30_60초() {
        // given
        let attempts = [1, 2, 3, 4, 5]
        // when
        let delays = attempts.map { LyricsRetryPolicy.delay(afterFailure: $0) }
        // then
        #expect(delays == [2, 5, 15, 30, 60])
    }

    @Test func 대기시간_6이상이거나0이면_nil() {
        // given
        let attempts = [6, 7, 0]
        // when
        let delays = attempts.map { LyricsRetryPolicy.delay(afterFailure: $0) }
        // then
        #expect(delays.allSatisfy { $0 == nil })
    }
}
