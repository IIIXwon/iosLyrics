import Testing
import Foundation
@testable import LiveLyricsExperiment

@MainActor
struct IdleNoticeTests {

    @Test func 안내문구_현재줄_일시정지표시() {
        // given
        // when
        let result = IdleNotice.current
        // then
        #expect(result == "⏸ 일시정지")
    }

    @Test func 안내문구_다음줄_Spotify에서재생안내() {
        // given
        // when
        let result = IdleNotice.next
        // then
        #expect(result == "카드를 눌러 Spotify에서 재생해 주세요")
    }

    @Test func 안내문구_두줄모두_재생버튼기호를포함하지않는다() {
        // given
        // when
        let texts = [IdleNotice.current, IdleNotice.next]
        // then
        for text in texts {
            #expect(!text.contains("▶︎"))
        }
    }
}
