import Testing
@testable import LiveLyricsExperiment

@MainActor
struct LogLimitTests {

    @Test func 로그보관줄수_상수_100이다() {
        // given // when
        let max = LogLimit.maxLines

        // then
        #expect(max == 100)
    }

    @Test func 로그자르기_101줄이면_오래된줄을버리고100줄만남긴다() throws {
        // given: 최신이 앞인 101줄 ["101", "100", ..., "1"]
        let logs = (1...101).reversed().map { String($0) }

        // when
        let result = LogLimit.trimmed(logs)

        // then
        #expect(result.count == 100)
        #expect(result.first == "101")
        #expect(result.last == "2")
    }

    @Test func 로그자르기_50줄이면_그대로돌려준다() {
        // given
        let logs = (1...50).reversed().map { String($0) }

        // when
        let result = LogLimit.trimmed(logs)

        // then
        #expect(result == logs)
        #expect(result.count == 50)
    }
}
