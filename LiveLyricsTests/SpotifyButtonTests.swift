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
}
