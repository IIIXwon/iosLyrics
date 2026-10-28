import Testing
import Foundation
@testable import LiveLyricsExperiment

@MainActor
struct LyricsPrefetchTests {

    // MARK: - PollTiming.wait (1~6)

    @Test func 대기시간_남은시간없으면_기본값이다() {
        // given // when
        let result = PollTiming.wait(base: 3, remaining: nil)

        // then
        #expect(result == 3)
    }

    @Test func 대기시간_남은시간이많으면_기본값이다() {
        // given // when
        let result = PollTiming.wait(base: 3, remaining: 10)

        // then
        #expect(result == 3)
    }

    @Test func 대기시간_곧끝나면_남은시간에0점5초를더한다() {
        // given // when
        let result = PollTiming.wait(base: 3, remaining: 1.2)

        // then
        #expect(abs(result - 1.7) < 0.001)
    }

    @Test func 대기시간_끝났는데아직같은곡이면_1초다() {
        // given // when
        let zero = PollTiming.wait(base: 3, remaining: 0)
        let minus2 = PollTiming.wait(base: 3, remaining: -2)

        // then
        #expect(zero == 1)
        #expect(minus2 == 1)
    }

    @Test func 대기시간_끝난지5초이상이면_기본값이다() {
        // given // when
        let minus5 = PollTiming.wait(base: 3, remaining: -5)
        let minus30 = PollTiming.wait(base: 3, remaining: -30)

        // then
        #expect(minus5 == 3)
        #expect(minus30 == 3)
    }

    @Test func 대기시간_일시정지기본15초는남은시간없으면_그대로다() {
        // given // when
        let result = PollTiming.wait(base: 15, remaining: nil)

        // then
        #expect(result == 15)
    }

    // MARK: - SpotifyQueue.next (7~8)

    @Test func 대기열해석_첫항목이곡이면_QueuedTrack으로바꾼다() throws {
        // given
        let json = """
        {"currently_playing": {"type":"track","id":"cur","name":"Now"},
         "queue": [
           {"type":"track","id":"abc123","name":"Next Song","duration_ms":215500,
            "artists":[{"name":"A"},{"name":"B"}],
            "album":{"name":"Some Album"}},
           {"type":"track","id":"zzz","name":"Later","duration_ms":1000,
            "artists":[{"name":"C"}],"album":{"name":"X"}}
         ]}
        """
        let data = Data(json.utf8)

        // when
        let track = try #require(SpotifyQueue.next(from: data))

        // then
        #expect(track.id == "abc123")
        #expect(track.key == "abc123")
        #expect(track.title == "Next Song")
        #expect(track.artist == "A, B")
        #expect(track.album == "Some Album")
        #expect(abs(track.duration - 215.5) < 0.001)
    }

    @Test func 대기열해석_빈배열이면_nil이다() {
        // given
        let data = Data(#"{"currently_playing": null, "queue": []}"#.utf8)

        // when
        let result = SpotifyQueue.next(from: data)

        // then
        #expect(result == nil)
    }

    @Test func 대기열해석_첫항목이에피소드면_nil이다() {
        // given
        let json = """
        {"queue": [{"type":"episode","id":"ep1","name":"Podcast","duration_ms":60000}]}
        """

        // when
        let result = SpotifyQueue.next(from: Data(json.utf8))

        // then
        #expect(result == nil)
    }

    @Test func 대기열해석_깨진JSON이면_nil이다() {
        // given
        let data = Data("{not json".utf8)

        // when
        let result = SpotifyQueue.next(from: data)

        // then
        #expect(result == nil)
    }

    // MARK: - LyricsPrefetch.shouldPrefetch (9~12)

    @Test func 미리받기판단_다른곡이고_시도한적없으면_true다() {
        // given // when
        let result = LyricsPrefetch.shouldPrefetch(nextKey: "b", currentKey: "a", tried: [])

        // then
        #expect(result == true)
    }

    @Test func 미리받기판단_다음곡이현재곡과같으면_false다() {
        // given // when
        let result = LyricsPrefetch.shouldPrefetch(nextKey: "a", currentKey: "a", tried: [])

        // then
        #expect(result == false)
    }

    @Test func 미리받기판단_이미시도한곡이면_false다() {
        // given // when
        let result = LyricsPrefetch.shouldPrefetch(nextKey: "b", currentKey: "a", tried: ["b"])

        // then
        #expect(result == false)
    }

    @Test func 미리받기판단_다음곡key가비면_false다() {
        // given // when
        let result = LyricsPrefetch.shouldPrefetch(nextKey: "", currentKey: "a", tried: [])

        // then
        #expect(result == false)
    }

    // MARK: - 상수 (13)

    @Test func 미리받기상수_재확인간격과한도와기억수가지시서와같다() {
        // given // when // then
        #expect(PollTiming.endRecheck == 1)
        #expect(PollTiming.endRecheckLimit == 5)
        #expect(LyricsPrefetch.memory == 20)
    }
}
