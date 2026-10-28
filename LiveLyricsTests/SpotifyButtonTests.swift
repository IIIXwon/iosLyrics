import Testing
import Foundation
@testable import LiveLyricsExperiment

@MainActor
struct SpotifyButtonTests {

    @Test func 버튼판단_로그인됨_설정됨_로그아웃() {
        // given
        let isLoggedIn = true
        let isConfigured = true
        // when
        let button = SpotifyButton.make(isLoggedIn: isLoggedIn, isConfigured: isConfigured)
        // then
        #expect(button == .logout)
    }

    @Test func 버튼판단_로그인됨_설정안됨_로그아웃() {
        // given
        let isLoggedIn = true
        let isConfigured = false
        // when
        let button = SpotifyButton.make(isLoggedIn: isLoggedIn, isConfigured: isConfigured)
        // then
        #expect(button == .logout)
    }

    @Test func 버튼판단_로그아웃상태_설정됨_로그인활성() {
        // given
        let isLoggedIn = false
        let isConfigured = true
        // when
        let button = SpotifyButton.make(isLoggedIn: isLoggedIn, isConfigured: isConfigured)
        // then
        #expect(button == .login(enabled: true))
    }

    @Test func 버튼판단_로그아웃상태_설정안됨_로그인비활성() {
        // given
        let isLoggedIn = false
        let isConfigured = false
        // when
        let button = SpotifyButton.make(isLoggedIn: isLoggedIn, isConfigured: isConfigured)
        // then
        #expect(button == .login(enabled: false))
    }

    @Test func 시작버튼_로그아웃상태_비활성이고_로그인안내() {
        // given
        let isLoggedIn = false
        let hasProblem = true
        // when
        let button = StartButton.make(isLoggedIn: isLoggedIn, hasProblem: hasProblem)
        // then
        #expect(button.enabled == false)
        #expect(button.hint == "Spotify에 로그인하면 시작할 수 있어요")
    }

    @Test func 시작버튼_로그인됨_준비문제있음_활성이고_확인안내() {
        // given
        let isLoggedIn = true
        let hasProblem = true
        // when
        let button = StartButton.make(isLoggedIn: isLoggedIn, hasProblem: hasProblem)
        // then
        #expect(button.enabled == true)
        #expect(button.hint == "준비 상태를 먼저 확인해 주세요")
    }

    @Test func 시작버튼_로그인됨_문제없음_활성이고_안내없음() {
        // given
        let isLoggedIn = true
        let hasProblem = false
        // when
        let button = StartButton.make(isLoggedIn: isLoggedIn, hasProblem: hasProblem)
        // then
        #expect(button.enabled == true)
        #expect(button.hint == nil)
    }
}
